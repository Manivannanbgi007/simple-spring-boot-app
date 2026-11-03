# Java 21 runtime (JRE only). Maven already built the JAR, so no build tools are needed in the image.
FROM eclipse-temurin:21-jre

# Create a normal (non-root) user to run the application - safer than running as root
RUN groupadd --system spring && useradd --system --gid spring spring

WORKDIR /app

# Copy the executable JAR built by Maven (target/simple-spring-boot-app-v<N>.jar) and name it app.jar
COPY target/*.jar app.jar

USER spring

# The application listens on port 8080 (server.port in application.yml)
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
