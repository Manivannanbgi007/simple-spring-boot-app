// Jenkins pipeline: runs the tests, builds the JAR, and keeps the JAR with the Jenkins build.
// The JAR name contains Jenkins' build number, e.g. build #42 -> simple-spring-boot-app-v42.jar
pipeline {
    agent any

    stages {
        stage('Build and Test') {
            steps {
                script {
                    // BUILD_NUMBER is provided by Jenkins. -B (batch mode) keeps the log clean.
                    def mavenArgs = "clean package -B -DbuildNumber=${env.BUILD_NUMBER}"

                    if (isUnix()) {
                        // Files committed from Windows lose the "executable" flag, so set it again
                        sh 'chmod +x mvnw'
                        sh "./mvnw ${mavenArgs}"
                    } else {
                        // ".\" makes Windows run the wrapper from the project folder
                        bat ".\\mvnw.cmd ${mavenArgs}"
                    }
                }
            }
        }
    }

    post {
        always {
            // Show test results on the Jenkins build page (also when the build fails)
            junit testResults: 'target/surefire-reports/*.xml', allowEmptyResults: true
        }
        success {
            // Keep the JAR with this build so it can be downloaded from Jenkins
            archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
        }
    }
}
