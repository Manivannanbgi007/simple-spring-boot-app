// CI/CD pipeline for simple-spring-boot-app.
// Jenkins runs as a Linux container (cicd/docker-compose.yml) - the same on Windows (Docker Desktop) and Ubuntu.
//
// Checkout -> Build -> Unit Tests -> Integration Tests -> SonarQube Analysis -> Quality Gate
//          -> Package JAR -> Docker Build -> Image Scan -> Docker Push
//          -> Candidate Test -> Deploy -> Smoke Test
//
// Safety rules:
//   - One build at a time: a second push waits instead of deploying at the same moment.
//   - Nothing is pushed or deployed that failed the tests, the quality gate or the vulnerability scan.
//   - Every image has a unique tag (build number + commit), so a tag is never overwritten.
//   - The new image is tested in a temporary container before it replaces the running application.
//   - If the new version fails after the switch, the previous version is started again (rollback).
//
// Jenkins itself (credentials 'dockerhub-credentials' and 'sonarqube-token', SonarQube server 'SonarQube',
// this job) is configured by cicd/jenkins/casc.yaml. Step-by-step setup: cicd/README.md
// The previous version of this pipeline is kept in Jenkinsfile.backup.

// Starts an application container in DOCKER_NETWORK, with the memory limit APP_MEMORY.
// Used for the candidate, the live container and a rollback.
def startApp(String name, String image, String extraArgs) {
    withEnv(["APP_NAME=${name}", "APP_IMAGE=${image}", "APP_ARGS=${extraArgs}"]) {
        sh 'docker run -d --name "$APP_NAME" --network "$DOCKER_NETWORK" --memory "$APP_MEMORY" $APP_ARGS "$APP_IMAGE"'
    }
}

// Waits (up to about 1 minute) until the application reports UP on /actuator/health, then calls the API.
// Jenkins reaches the container by its name through DOCKER_NETWORK ('localhost' would be Jenkins itself).
def checkApp(String name) {
    withEnv(["APP_NAME=${name}"]) {
        sh '''
            curl --fail --silent --show-error --max-time 5 --retry 20 --retry-delay 3 --retry-all-errors "http://$APP_NAME:8080/actuator/health"
            echo
            curl --fail --silent --show-error --max-time 5 "http://$APP_NAME:8080/api/hello"
            echo
        '''
    }
}

pipeline {
    agent any

    environment {
        // Docker Hub repository: <your Docker Hub username>/simple-spring-boot-app (lowercase)
        DOCKER_IMAGE   = 'manivannanbgi/simple-spring-boot-app'
        // The running application, and the temporary container that tests a new image first
        CONTAINER_NAME = 'simple-spring-boot-app'
        CANDIDATE_NAME = 'simple-spring-boot-app-candidate'
        // Docker network created by cicd/docker-compose.yml. Jenkins reaches the containers through it.
        DOCKER_NETWORK = 'cicd-network'
        // Port on the Docker host where the deployed application is available
        HOST_PORT      = '8080'
        // Memory limit of each application container (the JVM uses up to 75% of it - see the Dockerfile)
        APP_MEMORY     = '512m'
        // Vulnerability scanner, pinned by digest: a tag can be re-pushed (as in the 2026 Trivy compromise), a digest can't
        TRIVY_IMAGE    = 'aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c'
    }

    options {
        skipDefaultCheckout()                           // the 'Checkout' stage below does it
        timeout(time: 30, unit: 'MINUTES')              // stop a build that hangs
        buildDiscarder(logRotator(numToKeepStr: '10'))  // keep only the last 10 builds
        disableConcurrentBuilds()                       // one build at a time - the next one waits in the queue
    }

    stages {
        stage('Checkout') {
            steps {
                // Gets the latest code from the GitHub repository set in the Jenkins job
                checkout scm
                script {
                    // Image tag = build number + commit, e.g. v42-1a2b3c4: unique even if the build numbers
                    // start again at 1 (new Jenkins), and it shows which commit is inside the image
                    env.COMMIT_SHA = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG  = "v${env.BUILD_NUMBER}-" + sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                }
                echo "Image tag: ${env.IMAGE_TAG}"
            }
        }

        stage('Build') {
            steps {
                // -B (batch mode) and -ntp (no download progress) keep the log clean. In 'sh' commands, $NAME reads a variable.
                sh './mvnw -B -ntp clean compile'
            }
        }

        stage('Unit Tests') {
            steps {
                sh './mvnw -B -ntp test'
            }
            post {
                always {
                    // Show the test results on the build page (also when tests fail)
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('Integration Tests') {
            steps {
                // Runs only the integration tests (classes ending in IT, e.g. DemoApplicationIT): starts the
                // whole application on a random free port and calls it over HTTP. The stages above already
                // compiled the code, so the unit tests do not run again and no JAR is built here.
                sh './mvnw -B -ntp failsafe:integration-test failsafe:verify'
            }
            post {
                always {
                    // TEST-*.xml only: failsafe-summary.xml in the same folder is not a JUnit report
                    junit 'target/failsafe-reports/TEST-*.xml'
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                // Sends the code, test results and coverage (from the stages above) to SonarQube.
                // 'SonarQube' = server name in cicd/jenkins/casc.yaml (gives the URL + token)
                withSonarQubeEnv('SonarQube') {
                    sh './mvnw -B -ntp sonar:sonar'
                }
            }
        }

        stage('Quality Gate') {
            steps {
                // Waits for SonarQube's verdict (sent back by its webhook); a failed gate stops the build here
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Package JAR') {
            steps {
                // Creates target/simple-spring-boot-app-v<build number>.jar (tests already ran above)
                sh './mvnw -B -ntp package -DskipTests -DbuildNumber=$BUILD_NUMBER'
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
            }
        }

        stage('Docker Build') {
            steps {
                // Tagged with the unique IMAGE_TAG and 'latest'. The labels record the commit and version inside
                // the image ('docker inspect' shows them).
                sh '''
                    docker build \
                      --label "org.opencontainers.image.revision=$COMMIT_SHA" \
                      --label "org.opencontainers.image.version=$IMAGE_TAG" \
                      -t "$DOCKER_IMAGE:$IMAGE_TAG" -t "$DOCKER_IMAGE:latest" .
                '''
            }
        }

        stage('Image Scan') {
            steps {
                // Trivy checks the operating-system packages and the Java libraries in the image for known
                // vulnerabilities, and stops the build on HIGH or CRITICAL ones that already have a fix -
                // so a vulnerable image is never pushed or deployed.
                // The image is handed over as a file (docker save): Trivy gets no access to the Docker Engine.
                // The Docker volume 'trivy-cache' keeps Trivy's vulnerability database between builds.
                sh '''
                    docker save "$DOCKER_IMAGE:$IMAGE_TAG" | docker run --rm -i \
                      -v trivy-cache:/root/.cache \
                      --entrypoint sh "$TRIVY_IMAGE" -c \
                      'cat > /tmp/image.tar && trivy image --input /tmp/image.tar --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --no-progress'
                '''
            }
        }

        stage('Docker Push') {
            steps {
                // Uses the Docker Hub token stored in Jenkins (credential ID 'dockerhub-credentials').
                // Single quotes: the shell reads the token, so it never appears in the Jenkinsfile or the log.
                withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials',
                                                  usernameVariable: 'DOCKERHUB_USER',
                                                  passwordVariable: 'DOCKERHUB_TOKEN')]) {
                    sh 'echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin'
                }
                sh 'docker push "$DOCKER_IMAGE:$IMAGE_TAG"'
                sh 'docker push "$DOCKER_IMAGE:latest"'
            }
        }

        stage('Candidate Test') {
            steps {
                // Starts the new image as a temporary container (no public port) next to the running application
                // and checks it. If it doesn't start or answer, the build stops and the running application
                // is not touched.
                sh 'docker rm -f "$CANDIDATE_NAME" || true'
                script {
                    startApp(env.CANDIDATE_NAME, "${env.DOCKER_IMAGE}:${env.IMAGE_TAG}", '')
                    checkApp(env.CANDIDATE_NAME)
                }
            }
            post {
                failure {
                    sh 'docker logs --tail 100 "$CANDIDATE_NAME" || true'
                }
                cleanup {
                    sh 'docker rm -f "$CANDIDATE_NAME" || true'
                }
            }
        }

        stage('Deploy') {
            steps {
                script {
                    // Remember the running version, so it can be started again if the new one fails (rollback)
                    env.PREVIOUS_IMAGE = sh(script: 'docker inspect --format "{{.Config.Image}}" "$CONTAINER_NAME" 2>/dev/null || true',
                                            returnStdout: true).trim()
                    echo "Running now: ${env.PREVIOUS_IMAGE ?: 'nothing'}"
                    env.DEPLOY_STARTED = 'true'
                }
                // A few seconds of downtime: the old container must stop before the new one can use HOST_PORT
                sh 'docker rm -f "$CONTAINER_NAME" || true'
                script {
                    startApp(env.CONTAINER_NAME, "${env.DOCKER_IMAGE}:${env.IMAGE_TAG}",
                             "-p ${env.HOST_PORT}:8080 --restart unless-stopped")
                }
            }
        }

        stage('Smoke Test') {
            steps {
                // Checks the live container, the same way as the candidate
                script {
                    checkApp(env.CONTAINER_NAME)
                }
            }
        }
    }

    post {
        always {
            // Remove the Docker Hub login from the Jenkins container (docker login stores it in the jenkins_home volume)
            sh 'docker logout'
        }
        success {
            // Keep the 3 newest versions of the image on this machine (enough for a rollback), delete older ones
            sh '''
                docker images "$DOCKER_IMAGE" --format '{{.Tag}}' | grep -v '^latest$' | tail -n +4 \
                  | while read -r tag; do docker rmi "$DOCKER_IMAGE:$tag" || true; done
            '''
            echo "Deployed ${env.DOCKER_IMAGE}:${env.IMAGE_TAG} - open http://localhost:${env.HOST_PORT}/api/hello (on EC2: http://<EC2 address>:${env.HOST_PORT}/api/hello)"
        }
        failure {
            echo 'Build failed. Open "Console Output" and look for the first ERROR in the failed stage.'
        }
        unsuccessful {
            script {
                // Rollback: the build failed after the old container was replaced (Deploy or Smoke Test)
                if (env.DEPLOY_STARTED == 'true') {
                    sh 'docker logs --tail 100 "$CONTAINER_NAME" || true'
                    sh 'docker rm -f "$CONTAINER_NAME" || true'
                    if (env.PREVIOUS_IMAGE) {
                        echo "ROLLBACK: starting the previous version ${env.PREVIOUS_IMAGE} again"
                        startApp(env.CONTAINER_NAME, env.PREVIOUS_IMAGE, "-p ${env.HOST_PORT}:8080 --restart unless-stopped")
                        try {
                            checkApp(env.CONTAINER_NAME)
                            echo "ROLLBACK done: ${env.PREVIOUS_IMAGE} is running"
                        } catch (err) {
                            echo "WARNING: the previous version ${env.PREVIOUS_IMAGE} does not answer either - check 'docker logs ${env.CONTAINER_NAME}'"
                        }
                    } else {
                        echo 'No previous version to roll back to - the failed container was removed'
                    }
                }
            }
        }
    }
}
