# Jenkins image for the simple-spring-boot-app pipeline.
# Everything Jenkins needs is baked in here, so nothing has to be installed or clicked by hand:
#   - Java 21 (comes with the base image) - Maven Wrapper builds and tests the code with it
#   - Git and curl                        (come with the base image) - checkout and smoke test
#   - Docker CLI + buildx                 - docker build / push / run, executed by the host's Docker Engine
#   - the plugins listed in plugins.txt
#   - casc.yaml                           - the complete Jenkins configuration (Configuration as Code)
#
# After changing this file, plugins.txt or casc.yaml, rebuild and restart:  docker compose up -d --build

# Jenkins LTS (long-term support) with Java 21. An exact version, so every rebuild gives the same Jenkins.
FROM jenkins/jenkins:2.580.2-lts-jdk21

# Docker CLI and its buildx plugin, copied from the official Docker CLI image (same version as Docker Engine 29).
# Only the client is installed: the commands are sent to the host's Docker Engine through the mounted socket.
COPY --from=docker:29.9.2-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:29.9.2-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx

# Install the plugins at build time (plugins.txt lists name:version)
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Jenkins Configuration as Code reads this file on every start
COPY casc.yaml /var/jenkins_config/casc.yaml
ENV CASC_JENKINS_CONFIG=/var/jenkins_config/casc.yaml

# casc.yaml already creates the admin user and installs nothing else, so skip the setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
