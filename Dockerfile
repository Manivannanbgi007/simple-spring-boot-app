# Java 21 runtime (JRE only, Ubuntu 26.04 LTS). Maven already built the JAR, so no build tools are needed in the image.
# Exact version + digest: every build uses the same base image. To update it: cicd/README.md, "Upgrading".
FROM eclipse-temurin:21.0.13_9-jre-resolute@sha256:f8622d0220c9e218d7a33f24a7b9e1ad6bc726085f8b0ae74e1adf85f67f05c4

# Create a normal (non-root) user to run the application - safer than running as root
RUN groupadd --system spring && useradd --system --gid spring spring

WORKDIR /app

# Copy the executable JAR built by Maven (target/simple-spring-boot-app-v<N>.jar) and name it app.jar
COPY target/*.jar app.jar

USER spring

# The application listens on port 8080 (server.port in application.yml)
EXPOSE 8080

# Docker checks every 30 seconds that the application answers; 'docker ps' shows (healthy) or (unhealthy)
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fs http://localhost:8080/actuator/health || exit 1

# The JVM may use up to 75% of the container's memory limit (docker run --memory) for its heap
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
