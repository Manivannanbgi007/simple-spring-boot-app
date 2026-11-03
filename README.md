# Simple Spring Boot REST API Application

## Project Overview

A minimal Spring Boot application that exposes one REST endpoint:

```
GET /api/hello  →  {"message": "Hello! Spring Boot application is running successfully."}
```

It is intentionally small: one application class, one controller, one configuration file, and one test.

## Technology Stack

| Technology       | Version | Purpose                                         |
|------------------|---------|-------------------------------------------------|
| Java             | 21      | Programming language / runtime                  |
| Spring Boot      | 4.1.2   | Application framework                           |
| Spring Web (MVC) | (managed by Spring Boot) | REST API support with embedded Tomcat |
| Maven            | 3.9.16 (via Maven Wrapper) | Dependency management and build |
| JUnit 5 + MockMvc| (managed by Spring Boot) | Testing the REST endpoint          |

## Prerequisites

- **JDK 21** installed, with `JAVA_HOME` pointing to it. Check with:
  ```
  java -version
  ```
- **Maven is optional.** The project includes the Maven Wrapper (`mvnw` / `mvnw.cmd`), which downloads the correct Maven version automatically on first use.
- Internet access for the first build (to download Maven and dependencies).

## Project Structure

```text
simple-spring-boot-app/
├── .mvn/wrapper/maven-wrapper.properties    # Maven Wrapper settings (which Maven version to use)
├── .dockerignore                            # Files Docker may read when building the image (only the JAR)
├── .gitignore                               # Files Git must not commit (target/, IDE files)
├── CICD-GUIDE.md                            # Step-by-step Jenkins CI/CD setup guide
├── Dockerfile                               # Builds the Docker image from the JAR
├── Jenkinsfile                              # Jenkins CI/CD pipeline: build, test, Docker, deploy
├── JENKINS_SETUP_AND_PIPELINE_GUIDE_TAMIL.md  # Jenkins setup and pipeline guide in Tamil
├── mvnw                                     # Maven Wrapper script (macOS / Linux)
├── mvnw.cmd                                 # Maven Wrapper script (Windows)
├── pom.xml                                  # Maven build file: Java version, dependencies, plugins
├── README.md
└── src/
    ├── main/
    │   ├── java/com/example/demo/
    │   │   ├── DemoApplication.java         # Application entry point (main method)
    │   │   └── controller/
    │   │       └── HelloController.java     # REST controller with GET /api/hello
    │   └── resources/
    │       └── application.yml              # Configuration (server port, app name)
    └── test/
        └── java/com/example/demo/controller/
            └── HelloControllerTest.java     # Test for GET /api/hello
```

### What each important file does

- **`pom.xml`** – Inherits from `spring-boot-starter-parent`, which manages all library versions. Declares two dependencies:
  - `spring-boot-starter-webmvc` – Spring MVC + embedded Tomcat server, used to build REST APIs.
  - `spring-boot-starter-webmvc-test` – JUnit 5, MockMvc, and AssertJ for testing (test scope only).

  The `spring-boot-maven-plugin` builds a runnable JAR and provides the `spring-boot:run` command.
  The `buildNumber` property (default `0`) sets the number in the JAR name; Jenkins overrides it (see [Build Version Numbering](#build-version-numbering)).
- **`DemoApplication.java`** – Contains the `main` method. `@SpringBootApplication` turns on auto-configuration and scans the `com.example.demo` package (and its sub-packages) for components such as controllers.
- **`HelloController.java`** – `@RestController` marks it as a REST controller whose return values are written directly as the HTTP response body. `@RequestMapping("/api")` + `@GetMapping("/hello")` map the method to `GET /api/hello`. The returned `Map` is converted to JSON automatically.
- **`application.yml`** – External configuration in YAML format (indentation shows the nesting, so `server:` → `port:` means `server.port`). `server.port` sets the HTTP port, so it can be changed without touching Java code. Use spaces for indentation, never tabs.
- **`HelloControllerTest.java`** – Uses `@WebMvcTest` to load only the web layer and `MockMvc` to send a fake HTTP request, then checks the status code is `200` and the JSON `message` is correct.
- **`Jenkinsfile`** – The Jenkins CI/CD pipeline: builds and tests the code, creates the JAR and Docker image, pushes the image to Docker Hub, and deploys it as a container (see [Jenkins CI/CD Pipeline](#jenkins-cicd-pipeline)).
- **`Dockerfile`** – Builds a Docker image that runs the JAR on a Java 21 runtime as a non-root user. `.dockerignore` makes Docker read only the JAR.

## Maven Build Commands

Run all commands from the `simple-spring-boot-app` folder.

| Step                         | Windows (PowerShell / CMD)   | macOS / Linux / Git Bash   |
|------------------------------|------------------------------|----------------------------|
| 1. Clean                     | `.\mvnw.cmd clean`           | `./mvnw clean`             |
| 2. Compile                   | `.\mvnw.cmd compile`         | `./mvnw compile`           |
| 3. Run unit tests            | `.\mvnw.cmd test`            | `./mvnw test`              |
| 4. Package (creates the JAR) | `.\mvnw.cmd clean package`   | `./mvnw clean package`     |
| 5. Start the application     | `.\mvnw.cmd spring-boot:run` | `./mvnw spring-boot:run`   |

> If Maven is installed globally, you can replace `mvnw` / `mvnw.cmd` with `mvn`.

`package` also runs the tests. A successful build ends with `BUILD SUCCESS` and creates:

```
target/simple-spring-boot-app-v0.jar
```

`v0` means "built on a developer computer". Jenkins builds get a real build number (see below).

> **Note:** During tests you may see `WARNING` lines about Mockito / "A Java agent has been loaded dynamically". These come from the test libraries on Java 21 and are harmless.

## Build Version Numbering

The JAR name contains a build number, set by the `buildNumber` property in `pom.xml`:

| Where the JAR is built | Command                                                  | JAR created                             |
|------------------------|----------------------------------------------------------|-----------------------------------------|
| Your computer          | `.\mvnw.cmd clean package`                               | `target/simple-spring-boot-app-v0.jar`  |
| Jenkins build #42      | `mvnw package -DbuildNumber=42` (run by the Jenkinsfile) | `target/simple-spring-boot-app-v42.jar` |

- **Jenkins owns the build number.** Every Jenkins build gets a unique, increasing number (`BUILD_NUMBER`), which the `Jenkinsfile` passes to Maven. So `v42` always means "Jenkins build #42", and you can look up its log, test results, and Git commit in Jenkins. The Docker image of that build is tagged `v42` too.
- **`v0` means a developer build** – built on someone's computer, not a release.
- Why not count on each computer? A local counter gives different code the same number (your `v5` is not a colleague's `v5`), and it resets whenever Jenkins checks out a fresh copy.
- To try a number locally: `.\mvnw.cmd clean package -DbuildNumber=5` creates `simple-spring-boot-app-v5.jar`.
- The number is only in the JAR file name. The Maven project `<version>` in `pom.xml` (`0.0.1-SNAPSHOT`) does not change.
- Use `clean package` so that `target/` contains only the latest JAR.

## Jenkins CI/CD Pipeline

On every push to GitHub, the `Jenkinsfile` runs these stages on Jenkins (Windows + Docker Desktop):

```text
Checkout ▶ Build ▶ Unit Tests ▶ Package JAR ▶ Docker Build ▶ Docker Login ▶ Docker Push ▶ Docker Pull ▶ Deploy ▶ Smoke Test
```

The result is the image `<docker-hub-username>/simple-spring-boot-app:v<build number>` on Docker Hub and a running container at `http://localhost:8080/api/hello`.

**Setup:** follow [CICD-GUIDE.md](CICD-GUIDE.md) – GitHub, Jenkins, plugins, Docker, Docker Hub, credentials, webhook, verifying each stage, and troubleshooting.
The same guide in Tamil, with more detail on installing Jenkins and Docker Desktop: [JENKINS_SETUP_AND_PIPELINE_GUIDE_TAMIL.md](JENKINS_SETUP_AND_PIPELINE_GUIDE_TAMIL.md).

## Starting the Application

**Option A – Run with Maven (good during development):**

```
.\mvnw.cmd spring-boot:run        # Windows
./mvnw spring-boot:run            # macOS / Linux
```

**Option B – Run the packaged JAR (how it runs on a server):**

```
.\mvnw.cmd clean package
java -jar target/simple-spring-boot-app-v0.jar
```

The application is ready when the console shows:

```
Tomcat started on port 8080 (http) with context path '/'
Started DemoApplication in ... seconds
```

Press **Ctrl + C** in the terminal to stop the application.

## Port Configuration

The port is set in `src/main/resources/application.yml`:

```yaml
server:
  port: 8080
```

### If port 8080 is already in use

The application will fail to start with a message like:

```
Web server failed to start. Port 8080 was already in use.
```

To find which process is using the port:

```
netstat -ano | findstr :8080      # Windows
lsof -i :8080                     # macOS / Linux
```

Then choose **one** of these ways to use another port, such as `8081`:

1. **Permanently** – edit `application.yml` and restart:
   ```yaml
   server:
     port: 8081
   ```
2. **For a single run (JAR)** – pass it on the command line:
   ```
   java -jar target/simple-spring-boot-app-v0.jar --server.port=8081
   ```
3. **For a single run (Maven)**:
   ```
   .\mvnw.cmd spring-boot:run "-Dspring-boot.run.arguments=--server.port=8081"    # Windows (keep the quotes in PowerShell)
   ./mvnw spring-boot:run -Dspring-boot.run.arguments=--server.port=8081          # macOS / Linux
   ```
4. **Environment variable** – set `SERVER_PORT=8081` before starting the application.

Options 2–4 override the value in `application.yml` without editing any file. Remember to use the new port in the URLs below.

## REST API

| Method | URL                               | Description                     |
|--------|-----------------------------------|---------------------------------|
| GET    | `http://localhost:8080/api/hello` | Returns a success message       |

**Expected response** – HTTP `200 OK`, `Content-Type: application/json`:

```json
{
  "message": "Hello! Spring Boot application is running successfully."
}
```

### Testing the API manually

Start the application first, then use any of the following.

**Web browser**

Open `http://localhost:8080/api/hello`. The browser displays the JSON response.

**Postman**

1. Click **New → HTTP Request** (or the **+** tab).
2. Select method **GET**.
3. Enter the URL `http://localhost:8080/api/hello`.
4. Click **Send**.
5. Check that the status is **200 OK** and the body shows the JSON message above.

**Command line (curl)**

```
curl http://localhost:8080/api/hello
```

### Automated test

```
.\mvnw.cmd test        # Windows
./mvnw test            # macOS / Linux
```

Expected output includes:

```
Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
```
