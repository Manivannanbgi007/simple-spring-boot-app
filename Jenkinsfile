// CI/CD pipeline for simple-spring-boot-app (Jenkins on Windows + Docker Desktop).
//
// Checkout -> Build -> Unit Tests -> Package JAR -> Docker Build -> Docker Login
//          -> Docker Push -> Docker Pull -> Deploy -> Smoke Test
//
// Before the first run: set DOCKER_IMAGE below and create the Jenkins credential
// 'dockerhub-credentials'. Step-by-step setup: CICD-GUIDE.md
// (Tamil: JENKINS_SETUP_AND_PIPELINE_GUIDE_TAMIL.md)
pipeline {
    agent any

    environment {
        // Docker Hub repository: <your Docker Hub username>/simple-spring-boot-app (lowercase)
        DOCKER_IMAGE   = 'manivannanbgi/simple-spring-boot-app'
        // Image tag = Jenkins build number, e.g. v42 (the same number as the JAR name)
        IMAGE_TAG      = "v${env.BUILD_NUMBER}"
        CONTAINER_NAME = 'simple-spring-boot-app'
        // Port on this machine where the deployed application is available
        HOST_PORT      = '8080'
    }

    options {
        skipDefaultCheckout()                           // the 'Checkout' stage below does it
        timeout(time: 30, unit: 'MINUTES')              // stop a build that hangs
        buildDiscarder(logRotator(numToKeepStr: '10'))  // keep only the last 10 builds
    }

    stages {
        stage('Checkout') {
            steps {
                // Gets the latest code from the GitHub repository set in the Jenkins job
                checkout scm
            }
        }

        stage('Build') {
            steps {
                // -B (batch mode) keeps the log clean. In 'bat' commands, %NAME% reads a variable.
                bat '.\\mvnw.cmd -B clean compile'
            }
        }

        stage('Unit Tests') {
            steps {
                bat '.\\mvnw.cmd -B test'
            }
            post {
                always {
                    // Show the test results on the build page (also when tests fail)
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('Package JAR') {
            steps {
                // Creates target\simple-spring-boot-app-v<build number>.jar (tests already ran above)
                bat '.\\mvnw.cmd -B package -DskipTests -DbuildNumber=%BUILD_NUMBER%'
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
            }
        }

        stage('Docker Build') {
            steps {
                // Builds the image from the Dockerfile, tagged with the version and 'latest'
                bat 'docker build -t %DOCKER_IMAGE%:%IMAGE_TAG% -t %DOCKER_IMAGE%:latest .'
            }
        }

        stage('Docker Login') {
            steps {
                // Uses the Docker Hub token stored in Jenkins (credential ID 'dockerhub-credentials')
                withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials',
                                                  usernameVariable: 'DOCKERHUB_USER',
                                                  passwordVariable: 'DOCKERHUB_TOKEN')]) {
                    // No space before '|' - otherwise Windows adds a space to the end of the token
                    bat 'echo %DOCKERHUB_TOKEN%| docker login -u %DOCKERHUB_USER% --password-stdin'
                }
            }
        }

        stage('Docker Push') {
            steps {
                bat 'docker push %DOCKER_IMAGE%:%IMAGE_TAG%'
                bat 'docker push %DOCKER_IMAGE%:latest'
            }
        }

        stage('Docker Pull') {
            steps {
                // Delete the local copy first, so the image really comes from Docker Hub
                bat 'docker rmi %DOCKER_IMAGE%:%IMAGE_TAG% %DOCKER_IMAGE%:latest'
                bat 'docker pull %DOCKER_IMAGE%:%IMAGE_TAG%'
            }
        }

        stage('Deploy') {
            steps {
                // Remove the container of the previous build ("|| exit /b 0" = no error if there is none)
                bat 'docker rm -f %CONTAINER_NAME% || exit /b 0'
                bat 'docker run -d --name %CONTAINER_NAME% -p %HOST_PORT%:8080 --restart unless-stopped %DOCKER_IMAGE%:%IMAGE_TAG%'
            }
        }

        stage('Smoke Test') {
            steps {
                // Call the API, retrying for up to ~30 seconds while the application starts
                bat 'curl --fail --silent --show-error --retry 10 --retry-delay 3 --retry-all-errors http://localhost:%HOST_PORT%/api/hello'
            }
        }
    }

    post {
        success {
            echo "Deployed ${env.DOCKER_IMAGE}:${env.IMAGE_TAG} - open http://localhost:${env.HOST_PORT}/api/hello"
        }
        failure {
            echo 'Build failed. Open "Console Output" and look for the first ERROR in the failed stage.'
        }
    }
}
