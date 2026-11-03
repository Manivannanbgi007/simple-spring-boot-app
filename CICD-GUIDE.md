# Jenkins CI/CD Guide – simple-spring-boot-app

> **Replaced:** Jenkins and SonarQube now run as Docker containers with Docker Compose – follow
> [cicd/README.md](cicd/README.md). This guide describes the previous setup (Jenkins as a Windows service); the
> `Jenkinsfile` shown below is the old Windows version (`bat`), the one in the repository now uses Linux commands (`sh`).

This guide sets up a Jenkins pipeline that, on every push to GitHub, automatically **builds, tests, packages, containerizes, publishes, and deploys** the application with Docker.

It is written for **Jenkins running on Windows with Docker Desktop**. Follow the steps in order; each step ends with a way to check that it worked.

---

## Contents

- [What the pipeline does](#what-the-pipeline-does)
- [Your setup at a glance](#your-setup-at-a-glance)
- [Step 1 – Create the accounts](#step-1--create-the-accounts)
- [Step 2 – Put the project on GitHub](#step-2--put-the-project-on-github)
- [Step 3 – Install and set up Jenkins](#step-3--install-and-set-up-jenkins)
- [Step 4 – Install the Jenkins plugins](#step-4--install-the-jenkins-plugins)
- [Step 5 – Java and Maven](#step-5--java-and-maven)
- [Step 6 – Let Jenkins use Git and Docker](#step-6--let-jenkins-use-git-and-docker)
- [Step 7 – Create a Docker Hub access token](#step-7--create-a-docker-hub-access-token)
- [Step 8 – Store the credentials in Jenkins](#step-8--store-the-credentials-in-jenkins)
- [Step 9 – Create the pipeline job](#step-9--create-the-pipeline-job)
- [Step 10 – Build automatically on every push (webhook)](#step-10--build-automatically-on-every-push-webhook)
- [Step 11 – Check every stage](#step-11--check-every-stage)
- [The pipeline files explained](#the-pipeline-files-explained)
- [Environment variables and credentials](#environment-variables-and-credentials)
- [Build failures, logs, and troubleshooting](#build-failures-logs-and-troubleshooting)
- [Housekeeping](#housekeeping)
- [Running Jenkins on Linux instead](#running-jenkins-on-linux-instead)

---

## What the pipeline does

```text
 git push ──▶ GitHub ──webhook──▶ Jenkins
                                     │
   Checkout ▶ Build ▶ Unit Tests ▶ Integration Tests ▶ SonarQube Analysis ▶ Quality Gate ──┐
                                                       (SonarQube: localhost:9000)         │ passed
   ┌───────────────────────────────────────────────────────────────────────────────────────┘
   └▶ Package JAR ▶ Docker Build ▶ Docker Login ▶ Docker Push ──▶ Docker Hub
                                                                    │
               Smoke Test ◀ Deploy (docker run) ◀ Docker Pull ◀─────┘
```

| #  | Stage             | What happens                                                         | Command (in the `Jenkinsfile`)                               |
|----|-------------------|----------------------------------------------------------------------|--------------------------------------------------------------|
| 1  | Checkout          | Downloads the latest code from GitHub                                | `checkout scm`                                               |
| 2  | Build             | Compiles the code                                                    | `mvnw.cmd -B clean compile`                                  |
| 3  | Unit Tests        | Runs the unit tests and publishes the results                        | `mvnw.cmd -B test`                                           |
| 4  | Integration Tests | Starts the whole application on a random port, tests it over HTTP, and publishes the results | `mvnw.cmd -B failsafe:integration-test failsafe:verify` |
| 5  | SonarQube Analysis | Sends the code, test results and coverage to SonarQube              | `withSonarQubeEnv('SonarQube') { mvnw.cmd -B sonar:sonar }`  |
| 6  | Quality Gate      | Waits for SonarQube's verdict; stops the build if the quality gate failed | `waitForQualityGate abortPipeline: true`                |
| 7  | Package JAR       | Builds `simple-spring-boot-app-v<N>.jar` and archives it             | `mvnw.cmd -B package -DskipTests -DbuildNumber=<N>`          |
| 8  | Docker Build      | Builds a Docker image from the JAR, tagged `v<N>` and `latest`       | `docker build -t <image>:v<N> -t <image>:latest .`           |
| 9  | Docker Login      | Logs in to Docker Hub with the token stored in Jenkins               | `docker login --password-stdin`                              |
| 10 | Docker Push       | Uploads both tags to Docker Hub                                      | `docker push`                                                |
| 11 | Docker Pull       | Deletes the local copy and downloads the image from Docker Hub       | `docker rmi` + `docker pull`                                 |
| 12 | Deploy            | Replaces the old container with the new version                      | `docker rm -f` + `docker run -d -p 8080:8080 ...`            |
| 13 | Smoke Test        | Calls the API to prove the new container works                       | `curl http://localhost:8080/api/hello`                       |

`<N>` is the **Jenkins build number**, so build #42 produces `simple-spring-boot-app-v42.jar` and the image tag `v42`.

If any stage fails, the pipeline stops there. Deploy is near the end, so **a broken build never replaces the running application**.

Stages 5 and 6 need SonarQube running on your PC – install and connect it with [SONARQUBE-GUIDE.md](SONARQUBE-GUIDE.md) (Tamil: [SONARQUBE_GUIDE_TAMIL.md](SONARQUBE_GUIDE_TAMIL.md)).

---

## Your setup at a glance

| Tool           | Version / location                                                     | Used for                          |
|----------------|------------------------------------------------------------------------|-----------------------------------|
| Jenkins        | 2.580.2 LTS, Windows service **Jenkins**, http://localhost:8079        | Runs the pipeline                 |
| Jenkins data   | `C:\ProgramData\Jenkins\.jenkins` (install folder: `D:\Jenkins`)       | Jobs, builds, credentials         |
| Java (JDK)     | 21 – `JAVA_HOME` is set as a **system** variable                       | Compiling and running             |
| Maven          | 3.9.16, downloaded automatically by the Maven Wrapper (`mvnw.cmd`)     | Build and tests                   |
| Docker Desktop | 29.x, Linux containers, installed for your Windows user               | Building and running images       |
| Git            | Git for Windows, installed for your Windows user                      | Pushing code; Jenkins checkout    |
| curl           | Built into Windows 10/11                                               | Smoke test                        |
| SonarQube      | Community Build 26.10, Docker container `sonarqube`, http://localhost:9000 | Code analysis and quality gate |

> Jenkins uses port **8079** because the application itself uses **8080**. SonarQube uses **9000**.

---

## Step 1 – Create the accounts

1. **GitHub** – sign up at https://github.com (skip if you have an account). Note your **username**.
2. **Docker Hub** – sign up at https://hub.docker.com. Note your **username** (always lowercase). The pipeline pushes images to `<docker-hub-username>/simple-spring-boot-app`.

**Check:** you can sign in to both websites.

---

## Step 2 – Put the project on GitHub

### 2.1 Set your Docker Hub image name

Open `Jenkinsfile` and change this line to your Docker Hub username:

```groovy
DOCKER_IMAGE   = 'your-dockerhub-username/simple-spring-boot-app'
```

For example, for the Docker Hub user `johndoe`: `'johndoe/simple-spring-boot-app'`.

### 2.2 Create the GitHub repository

1. On GitHub, click **+** (top right) → **New repository**.
2. **Repository name:** `simple-spring-boot-app`.
3. Choose **Public** (simplest – Jenkins needs no GitHub credentials) or **Private**.
4. Do **not** tick "Add a README", ".gitignore", or "license" – the project already has them.
5. Click **Create repository** and copy the URL, e.g. `https://github.com/<github-username>/simple-spring-boot-app.git`.

### 2.3 Push the code

Run in a terminal **inside the `simple-spring-boot-app` folder** (the folder that contains `pom.xml`):

```powershell
git init
git add .
git commit -m "Initial commit: Spring Boot app with Jenkins CI/CD"
git branch -M main
git remote add origin https://github.com/<github-username>/simple-spring-boot-app.git
git push -u origin main
```

The first push opens a browser window to sign in to GitHub (Git Credential Manager, included with Git for Windows). After that, Git remembers you.

**Check:** the repository page on GitHub shows `pom.xml`, `mvnw.cmd`, `Jenkinsfile`, and `Dockerfile` **at the top level**, and there is **no** `target` folder (it is excluded by `.gitignore`).

> The pipeline expects `pom.xml`, `mvnw.cmd`, `Jenkinsfile`, and `Dockerfile` in the repository root. Don't push the parent folder.

### 2.4 Private repository only: create a token for Jenkins

Jenkins can't use your browser login, so a private repository needs a **personal access token**:

1. GitHub → your profile picture → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**.
2. **Token name:** `jenkins`. **Expiration:** your choice (you must renew it when it expires).
3. **Repository access:** **Only select repositories** → `simple-spring-boot-app`.
4. **Permissions** → **Repository permissions** → **Contents:** **Read-only**.
5. Click **Generate token** and copy it now (it is shown only once). You'll store it in Jenkins in [Step 8](#step-8--store-the-credentials-in-jenkins).

---

## Step 3 – Install and set up Jenkins

### 3.1 Already installed?

Open http://localhost:8079. If you see the Jenkins login page, Jenkins is installed – skip to [Step 4](#step-4--install-the-jenkins-plugins).

### 3.2 Fresh installation on Windows

1. Download the **LTS Windows installer** from https://www.jenkins.io/download/.
2. Run it and click through the wizard:
   - **Service Logon Credentials:** choose **Run service as local or domain user** and enter your Windows account (see [Step 6](#step-6--let-jenkins-use-git-and-docker) for why). Click **Test Credentials**.
   - **Port:** `8079` → **Test Port**.
   - **Java home directory:** your JDK 21 folder, e.g. `C:\Program Files\Java\jdk-21...`.
3. Finish the installation. Jenkins starts automatically as a Windows service.

### 3.3 First-time setup

1. Open http://localhost:8079.
2. **Unlock Jenkins:** paste the password from `C:\ProgramData\Jenkins\.jenkins\secrets\initialAdminPassword` (open it with Notepad as Administrator).
3. Choose **Install suggested plugins** and wait.
4. **Create First Admin User** – remember this username and password.
5. **Jenkins URL:** `http://localhost:8079/` → **Save and Finish** → **Start using Jenkins**.

**Check:** you can log in and see the Jenkins dashboard.

---

## Step 4 – Install the Jenkins plugins

The pipeline uses plain `mvnw.cmd` and `docker` commands, so it needs only a few standard plugins. All of them come with **Install suggested plugins** (some as dependencies of others) – just confirm they are there.

| Plugin                                      | Why the pipeline needs it                                        |
|---------------------------------------------|------------------------------------------------------------------|
| **Pipeline**                                | Runs the `Jenkinsfile`                                           |
| **Git**                                     | Checks out the code                                              |
| **GitHub**                                  | Receives GitHub webhooks ("GitHub hook trigger for GITScm polling") |
| **Credentials Binding**                     | `withCredentials` – uses the Docker Hub token safely             |
| **JUnit**                                   | `junit` – shows test results on the build page                   |
| **Pipeline Graph View** (or Pipeline: Stage View) | Shows the stages as a diagram (turn it on below)           |
| **SonarQube Scanner**                       | `withSonarQubeEnv` and `waitForQualityGate` – **not** part of the suggested plugins; set up in [SONARQUBE-GUIDE.md Step 5](SONARQUBE-GUIDE.md#step-5--install-the-sonarqube-scanner-plugin-in-jenkins) |

**How to check / install:**

1. **Manage Jenkins** → **Plugins** → **Installed plugins** → search for each name.
2. If one is missing: **Available plugins** → search → tick it → **Install** → tick **Restart Jenkins when installation is complete** if asked.

> Not needed: the "Docker Pipeline" and "Maven Integration" plugins. Plain commands are easier to read, and you can run exactly the same commands in your own terminal.

**Show Pipeline Graph View on the job page:** the plugin doesn't appear on the job page until you turn it on – until then the job page shows only the old **Stage View** table.

1. **Manage Jenkins** → **Appearance**.
2. Under **Pipeline Stages**, tick **Show pipeline stages on job page** (optional: also tick **Show stage names by default** and **Show stage durations by default**).
3. Under **Pipeline Graph**, tick **Show pipeline graph on build page**.
4. Click **Save** (no restart needed).

Optional – remove the old Stage View table: **Manage Jenkins** → **Plugins** → **Installed plugins** → search **Pipeline: Stage View** → switch it off → restart Jenkins (http://localhost:8079/safeRestart). If the switch is greyed out, another plugin needs it – leave it on; the job page then shows both views.

---

## Step 5 – Java and Maven

**Java:** JDK 21 is installed and `JAVA_HOME` is a **system** environment variable, so the Jenkins service uses it automatically. Nothing to configure in Jenkins.

- Check in a terminal: `echo %JAVA_HOME%` (CMD) or `$env:JAVA_HOME` (PowerShell) → JDK 21 folder; `java -version` → 21.
- If you change `JAVA_HOME`, **restart the Jenkins service** (Windows services only read environment variables when they start).

**Maven:** no Maven installation in Jenkins is needed. The project's **Maven Wrapper** (`mvnw.cmd`) downloads Maven 3.9.16 on the first build. The version is set in `.mvn/wrapper/maven-wrapper.properties`, so Jenkins and every developer use exactly the same Maven version.

> Optional alternative (not used here): **Manage Jenkins → Tools → Maven installations** lets Jenkins install Maven, which you then use with `tools { maven '<name>' }` in the Jenkinsfile. With the wrapper, you don't need this.

---

## Step 6 – Let Jenkins use Git and Docker

### 6.1 Docker Desktop settings

1. Open Docker Desktop → **Settings** → **General** → tick **Start Docker Desktop when you sign in to your computer** → **Apply**.
2. Make sure Docker Desktop uses **Linux containers** (the default). The tray menu shows "Switch to Windows containers…" when Linux containers are active.

**Check:** in a terminal, `docker version` shows both a **Client** and a **Server** section.

> Docker Desktop runs only while you are signed in to Windows. The Docker stages work only while Docker Desktop is running.

### 6.2 Why Jenkins can't see Git and Docker yet

The Jenkins Windows service runs as the special account **Local System**. On this PC, **Git and Docker Desktop are installed for your Windows user only**: their folders are on *your* `PATH`, and Docker's build component (`buildx`) and settings are in *your* user profile (`C:\Users\<you>\.docker`). Local System sees none of this, so builds fail with `'git' is not recognized` or `'docker' is not recognized`.

**Fix:** run the Jenkins service as **your Windows account**. Then Jenkins sees the same Git, Docker, and Maven cache that you use in your terminal.

### 6.3 Run the Jenkins service as your Windows account

**a) Find your account name.** In a normal (not Administrator) terminal:

```powershell
whoami
```

The output looks like `YOURDOMAIN\yourname`. Use it below.

**b) Give your account access to the Jenkins folders.** Open **PowerShell as Administrator** and run (replace `YOURDOMAIN\yourname`):

```powershell
icacls "C:\ProgramData\Jenkins" /grant "YOURDOMAIN\yourname:(OI)(CI)F" /T
icacls "D:\Jenkins" /grant "YOURDOMAIN\yourname:(OI)(CI)F" /T
```

`C:\ProgramData\Jenkins` holds Jenkins' data and `D:\Jenkins` is the install folder (it holds the service log files). `(OI)(CI)F` = full control for the folder, its subfolders, and files.

**c) Change the service account:**

1. Press **Win + R**, type `services.msc`, press **Enter**.
2. Right-click **Jenkins** → **Properties** → **Log On** tab.
3. Select **This account**, enter `YOURDOMAIN\yourname` and your Windows password twice → **OK**.
4. Windows may say the account was granted the **Log On As A Service** right – click **OK**.
5. Right-click **Jenkins** → **Restart**. Wait about a minute, then open http://localhost:8079.

> When your Windows password changes, update it on this **Log On** tab too – otherwise Jenkins won't start after the next reboot.
> If the service won't start, see [Jenkins service doesn't start](#common-errors-and-solutions) in the troubleshooting table.

### 6.4 Check: run a "tools check" pipeline

1. Jenkins → **New Item** → name `tools-check` → **Pipeline** → **OK**.
2. In **Pipeline**, keep **Definition: Pipeline script** and paste:

   ```groovy
   pipeline {
       agent any
       stages {
           stage('Tools check') {
               steps {
                   bat 'whoami'
                   bat 'echo JAVA_HOME=%JAVA_HOME%'
                   bat 'git --version'
                   bat 'docker version'
                   bat 'docker buildx version'
               }
           }
       }
   }
   ```

3. **Save** → **Build Now** → click the build → **Console Output**.

**Expected:** `whoami` shows **your** account (not `nt authority\system`), `JAVA_HOME` is the JDK 21 folder, and `git`, `docker` (Client **and** Server), and `buildx` print versions. Then delete the `tools-check` job.

**If `whoami` shows your account but `git` or `docker` is still "not recognized":** tell Jenkins where they are.

1. In your own terminal, find the folders: `where.exe git` and `where.exe docker` (use the folder part, e.g. `C:\Users\<you>\AppData\Local\Programs\Git\cmd`).
2. **Manage Jenkins** → **System** → **Global properties** → tick **Environment variables** → **Add**:
   - **Name:** `PATH+TOOLS`
   - **Value:** the two folders separated by `;`, e.g. `C:\Users\<you>\AppData\Local\Programs\Git\cmd;C:\Users\<you>\AppData\Local\Programs\DockerDesktop\resources\bin`
3. **Save** and run `tools-check` again. (`PATH+TOOLS` means "add these folders to the front of `PATH`".)

---

## Step 7 – Create a Docker Hub access token

Jenkins logs in to Docker Hub with an **access token** instead of your password (you can revoke a token at any time without changing your password).

1. https://hub.docker.com → your avatar → **Account settings** → **Personal access tokens** → **Generate new token**.
2. **Description:** `jenkins`. **Access permissions:** **Read & Write** (push needs write access).
3. Click **Generate** and copy the token now (it is shown only once).

**Check (optional):** in a terminal run `docker login -u <docker-hub-username>` and paste the token as the password → `Login Succeeded`.

> Docker Hub creates the repository `<docker-hub-username>/simple-spring-boot-app` automatically on the first push. To create it yourself first (for example to choose public/private): **Repositories** → **Create a repository**.

---

## Step 8 – Store the credentials in Jenkins

Secrets live in Jenkins, **never in the Jenkinsfile or in Git**.

**Manage Jenkins** → **Credentials** → under *Stores scoped to Jenkins*, click **System** → **Global credentials (unrestricted)** → **Add Credentials**:

| Field          | Docker Hub (required)                | GitHub (private repository only)     |
|----------------|--------------------------------------|--------------------------------------|
| Kind           | Username with password               | Username with password               |
| Scope          | Global                               | Global                               |
| Username       | your Docker Hub username             | your GitHub username                 |
| Password       | the Docker Hub access token (Step 7) | the GitHub token (Step 2.4)          |
| ID             | `dockerhub-credentials`              | `github-credentials`                 |
| Description    | Docker Hub token for Jenkins         | GitHub token for Jenkins             |

The **ID must match exactly** – the Jenkinsfile looks up `dockerhub-credentials` by this ID.

The SonarQube token is a third credential (**Secret text**, ID `sonarqube-token`) – see [SONARQUBE-GUIDE.md Step 6](SONARQUBE-GUIDE.md#step-6--store-the-token-in-jenkins).

**Check:** both credentials appear in the list (the secret itself is never shown again).

---

## Step 9 – Create the pipeline job

1. Jenkins dashboard → **New Item**.
2. **Name:** `simple-spring-boot-app` → choose **Pipeline** → **OK**.
3. **Triggers:** tick **GitHub hook trigger for GITScm polling** (used in [Step 10](#step-10--build-automatically-on-every-push-webhook)).
4. **Pipeline** section:
   - **Definition:** **Pipeline script from SCM**
   - **SCM:** **Git**
   - **Repository URL:** `https://github.com/<github-username>/simple-spring-boot-app.git`
   - **Credentials:** **- none -** for a public repository, or `github-credentials` for a private one
   - **Branch Specifier:** `*/main`
   - **Script Path:** `Jenkinsfile`
5. **Save** → **Build Now**.

The first build takes a few minutes (it downloads Maven, the dependencies, and the Java base image). The first build must be started manually – afterwards the webhook starts builds automatically.

**Check:** the build turns green, and all thirteen stages are shown as passed. See [Step 11](#step-11--check-every-stage) for what to look for in each stage.

---

## Step 10 – Build automatically on every push (webhook)

A webhook makes GitHub call Jenkins after every push. GitHub is on the internet, but `http://localhost:8079` exists only on your PC, so GitHub needs a **public URL** that forwards to your Jenkins. **ngrok** provides one for free.

### Option A – GitHub webhook through ngrok

1. Create a free account at https://ngrok.com and install ngrok (download from https://ngrok.com/download, or `winget install ngrok.ngrok`).
2. Connect it to your account (the command with your token is on the ngrok dashboard → **Your Authtoken**):
   ```powershell
   ngrok config add-authtoken <your-ngrok-token>
   ```
3. Start the tunnel to Jenkins and **leave the window open**:
   ```powershell
   ngrok http 8079
   ```
   Copy the **Forwarding** URL, e.g. `https://abcd-1234.ngrok-free.app`.
   > Free accounts get one **static domain** (ngrok dashboard → **Domains**), which keeps the same URL every time. Otherwise the URL changes on every restart and you must update the webhook.
4. GitHub repository → **Settings** → **Webhooks** → **Add webhook**:
   - **Payload URL:** `https://abcd-1234.ngrok-free.app/github-webhook/` – the trailing **`/github-webhook/`** (with the final `/`) is required
   - **Content type:** `application/json`
   - **Secret:** leave empty
   - **Which events:** **Just the push event**
   - **Active:** ticked → **Add webhook**

**Check:**

1. GitHub → **Webhooks** → your webhook → **Recent Deliveries**: a green tick with response **200** (GitHub sends a test "ping").
2. Change something small (for example this guide), then `git commit` and `git push`. Within seconds a new build starts; the build page says **Started by GitHub push by <your-name>**.

> Security: ngrok makes your Jenkins reachable from the internet. Keep the Jenkins login enabled with a strong password, and stop ngrok (Ctrl + C) when you don't need it.

### Option B – Poll GitHub (no extra tool)

If you can't use ngrok: job → **Configure** → **Triggers** → untick the GitHub hook trigger, tick **Poll SCM**, and enter the schedule:

```text
H/2 * * * *
```

Jenkins then checks GitHub about every 2 minutes and builds only when there are new commits.

---

## Step 11 – Check every stage

Open the build page → **Pipeline Overview** (or **Stage View**) to see the stages; click a stage to see its log. The full log is in **Console Output**.

| Stage        | Success looks like this in the log                                                     | Extra check                                                         |
|--------------|-----------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| Checkout     | `Checking out Revision 1a2b3c… (refs/remotes/origin/main)`                             | The commit matches the latest one on GitHub                         |
| Build        | `BUILD SUCCESS`                                                                        | –                                                                   |
| Unit Tests   | `Tests run: 5, Failures: 0, Errors: 0, Skipped: 0` and `BUILD SUCCESS`                 | Build page → **Test Result**                                        |
| Integration Tests | `Tomcat started on port <random number>`, then `Tests run: 8, Failures: 0, Errors: 0, Skipped: 0` and `BUILD SUCCESS` | **Test Result** also lists `DemoApplicationIT` (13 tests in total) |
| SonarQube Analysis | `ANALYSIS SUCCESSFUL, you can find the results at: http://localhost:9000/dashboard?id=simple-spring-boot-app` | The SonarQube dashboard shows the new analysis                     |
| Quality Gate | `SonarQube task '…' completed. Quality gate is 'OK'`                                     | Build page → **SonarQube Quality Gate** badge                       |
| Package JAR  | `Building jar: …\target\simple-spring-boot-app-v<N>.jar`                               | Build page → **Build Artifacts** has the JAR                        |
| Docker Build | `naming to docker.io/<user>/simple-spring-boot-app:v<N> done`                          | `docker images <user>/simple-spring-boot-app`                       |
| Docker Login | `Login Succeeded`                                                                      | –                                                                   |
| Docker Push  | `v<N>: digest: sha256:…` and `latest: digest: sha256:…`                                | Docker Hub → **Repositories** → `simple-spring-boot-app` → **Tags** |
| Docker Pull  | `Untagged: …` then `Status: Downloaded newer image for <user>/simple-spring-boot-app:v<N>` | –                                                               |
| Deploy       | A long container ID (64 hex characters)                                                | `docker ps` shows `simple-spring-boot-app`, **Up**, `0.0.0.0:8080->8080/tcp` |
| Smoke Test   | `{"message":"Hello! Spring Boot application is running successfully."}`                | –                                                                   |

> In the Smoke Test you may first see `curl: (52) Empty reply from server`. That is normal – the application was still starting and curl retried.

**Check the deployed application:** open http://localhost:8080/api/hello in a browser. Useful commands:

```powershell
docker ps                                   # is the container running?
docker logs simple-spring-boot-app          # application log
docker logs -f simple-spring-boot-app       # follow the log live (Ctrl + C to stop)
```

**Run the published image on any other machine** with Docker:

```powershell
docker pull <docker-hub-username>/simple-spring-boot-app:latest
docker run -d --name simple-spring-boot-app -p 8080:8080 <docker-hub-username>/simple-spring-boot-app:latest
```

---

## The pipeline files explained

All files are in the project root (next to `pom.xml`).

| File            | Purpose                                                                          |
|-----------------|----------------------------------------------------------------------------------|
| `Jenkinsfile`   | The pipeline: all stages and commands                                            |
| `Dockerfile`    | How to build the Docker image from the JAR                                       |
| `.dockerignore` | Which files Docker may read while building (only the JAR)                        |
| `.gitignore`    | Files Git must not commit (`target/`, IDE files)                                 |
| `pom.xml`       | The `buildNumber` property (default `0`) puts the build number in the JAR name; `maven-failsafe-plugin` runs the integration tests; JaCoCo measures coverage and `sonar-maven-plugin` runs the SonarQube analysis |
| `mvnw.cmd`      | Maven Wrapper – downloads and runs the correct Maven version                    |

### Jenkinsfile (complete)

```groovy
// CI/CD pipeline for simple-spring-boot-app (Jenkins on Windows + Docker Desktop).
//
// Checkout -> Build -> Unit Tests -> Integration Tests -> SonarQube Analysis -> Quality Gate
//          -> Package JAR -> Docker Build -> Docker Login -> Docker Push -> Docker Pull
//          -> Deploy -> Smoke Test
//
// Before the first run: set DOCKER_IMAGE below and create the Jenkins credential
// 'dockerhub-credentials'. Step-by-step setup: CICD-GUIDE.md
// (Tamil: JENKINS_SETUP_AND_PIPELINE_GUIDE_TAMIL.md)
// SonarQube setup (server 'SonarQube' in Manage Jenkins -> System): SONARQUBE-GUIDE.md
// (Tamil: SONARQUBE_GUIDE_TAMIL.md)
pipeline {
    agent any

    environment {
        // Docker Hub repository: <your Docker Hub username>/simple-spring-boot-app (lowercase)
        DOCKER_IMAGE   = 'your-dockerhub-username/simple-spring-boot-app'
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

        stage('Integration Tests') {
            steps {
                // Runs only the integration tests (classes ending in IT, e.g. DemoApplicationIT): starts the
                // whole application on a random free port and calls it over HTTP. The stages above already
                // compiled the code, so the unit tests do not run again and no JAR is built here.
                bat '.\\mvnw.cmd -B failsafe:integration-test failsafe:verify'
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
                // 'SonarQube' = server name in Manage Jenkins -> System -> SonarQube servers (gives URL + token)
                withSonarQubeEnv('SonarQube') {
                    bat '.\\mvnw.cmd -B sonar:sonar'
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
```

**Key points:**

- **`environment`** – values used by several stages, defined once. Change `DOCKER_IMAGE` (your Docker Hub user) and, if needed, `HOST_PORT`.
- **`'.\\mvnw.cmd'`** – Groovy needs the backslash written twice; Windows receives `.\mvnw.cmd` ("run `mvnw.cmd` from the project folder").
- **Single quotes** around `bat` commands – Jenkins passes the text unchanged and Windows replaces `%NAME%` with the variable's value.
- **`failsafe:integration-test failsafe:verify`** in the Integration Tests stage – runs only the test classes ending in `IT`; `verify` fails the stage if one of them failed. Running these two goals directly (instead of `mvnw verify`) means the unit tests don't run twice and no second JAR lands in `target`, which would break the Docker Build. The application starts on a random free port, so it doesn't clash with the deployed container on 8080.
- **`TEST-*.xml`** in the Integration Tests `junit` step – the folder also contains `failsafe-summary.xml`, which is not a test report.
- **`withSonarQubeEnv('SonarQube')`** – gives the scanner the SonarQube URL and token configured in Jenkins, so the token is never in the Jenkinsfile. **`waitForQualityGate abortPipeline: true`** waits for SonarQube's webhook and fails the build if the quality gate failed, before anything is packaged or deployed. Details: [SONARQUBE-GUIDE.md](SONARQUBE-GUIDE.md#the-project-files-explained).
- **`--retry-all-errors`** in the Smoke Test – the application needs a few seconds to start; curl keeps trying for about 30 seconds before failing.
- **`--restart unless-stopped`** – Docker restarts the container automatically, for example after a reboot, until you remove it.
- **No `docker logout`** – Jenkins runs as your Windows account and shares your Docker login, so logging out would also sign you out of Docker Desktop. On a dedicated build server, add `post { always { bat 'docker logout' } }`.

### Dockerfile

```dockerfile
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
```

- **`eclipse-temurin:21-jre`** – official OpenJDK 21 runtime image. A JRE is enough to *run* a JAR.
- **Non-root user** – if the application were ever compromised, the attacker would not be root inside the container.
- **`app.jar`** – a fixed name, so `ENTRYPOINT` doesn't change when the build number does.

### .dockerignore

```text
*
!target/*.jar
```

Docker may read **only** the built JAR (`*` = ignore everything, `!` = except). The image stays clean and `docker build` only transfers about 20 MB.

### .gitignore

Keeps `target/` (build output) and IDE/OS files out of Git.

### Build the image on your own PC (optional)

The same steps as the pipeline, from the project folder:

```powershell
.\mvnw.cmd clean package
docker build -t simple-spring-boot-app:local .
docker run -d --name simple-spring-boot-app-local -p 8080:8080 simple-spring-boot-app:local
curl.exe http://localhost:8080/api/hello
docker rm -f simple-spring-boot-app-local
```

---

## Environment variables and credentials

**Variables Jenkins provides** to every build (full list: http://localhost:8079/env-vars.html):

| Variable       | Example                                               |
|----------------|-------------------------------------------------------|
| `BUILD_NUMBER` | `42`                                                  |
| `JOB_NAME`     | `simple-spring-boot-app`                              |
| `WORKSPACE`    | `C:\ProgramData\Jenkins\.jenkins\workspace\simple-spring-boot-app` |
| `BUILD_URL`    | `http://localhost:8079/job/simple-spring-boot-app/42/` |

**Your own variables** go in the `environment { }` block of the Jenkinsfile.

**How to read a variable:**

| Where                                 | Syntax              | Example                                  |
|---------------------------------------|---------------------|------------------------------------------|
| Inside a `bat` command (Windows)      | `%NAME%`            | `bat 'docker push %DOCKER_IMAGE%:latest'` |
| Inside Groovy (e.g. `echo`)            | `${env.NAME}` in double quotes | `echo "Tag: ${env.IMAGE_TAG}"`  |

**Credentials (secrets):**

- Stored in **Manage Jenkins → Credentials**, encrypted. Never put tokens or passwords in the Jenkinsfile, `application.yml`, or Git.
- `withCredentials([...]) { ... }` makes a secret available as a variable **only inside its block**.
- Jenkins replaces secrets with `****` in the log.
- To rotate a token: create a new one, then **Credentials** → the credential → **Update** → paste it → **Save**. No Jenkinsfile change needed.

**Machine-specific settings** (for example, an extra folder on `PATH`) belong in **Manage Jenkins → System → Global properties → Environment variables**, not in the Jenkinsfile.

---

## Build failures, logs, and troubleshooting

### Where to look

1. **Build page → Pipeline Overview / Stage View** – the red stage is where it failed.
2. **Console Output** – the full log. Search (Ctrl + F) for `ERROR` or `FAILURE`; the **first** error is usually the real cause.
3. **Test Result** – which test failed and why.
4. **`docker logs simple-spring-boot-app`** – why the running application doesn't respond.
5. **Manage Jenkins → System Log** – Jenkins' own problems.
6. **Windows Event Viewer → Windows Logs → System** – why the Jenkins *service* didn't start. The service's own log files (`*.log`) are in `D:\Jenkins`.

### How the pipeline behaves on failure

- The failed stage turns red, the **remaining stages are skipped**, and the build is marked **FAILURE**.
- The **previous container keeps running** if the failure happens before Deploy – a broken build never replaces a working one.
- A build that runs longer than **30 minutes** is stopped (`timeout`).
- To retry: **Build Now**. To try a Jenkinsfile change without committing it: build page → **Replay**. To rerun only the later stages: build page → **Restart from Stage**.

### Common errors and solutions

| Error message (in Console Output)                                                                 | Cause                                                                    | Solution                                                                                         |
|---------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| `Cannot run program "git.exe"` or `'git' is not recognized` (Checkout)                            | Jenkins service still runs as Local System                               | [Step 6.3](#63-run-the-jenkins-service-as-your-windows-account), then restart the service       |
| `'docker' is not recognized as an internal or external command`                                   | Same as above                                                            | Same as above                                                                                    |
| `BuildKit is enabled but the buildx component is missing or broken`                               | Same as above (`buildx` is in your user profile)                         | Same as above                                                                                    |
| `error during connect: … open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified` | Docker Desktop is not running                                  | Start Docker Desktop; enable "Start when you sign in" ([6.1](#61-docker-desktop-settings))       |
| `Error saving credentials: … A specified logon session does not exist`                            | Jenkins service runs as Local System                                     | [Step 6.3](#63-run-the-jenkins-service-as-your-windows-account)                                  |
| `remote: Repository not found` / `Authentication failed for 'https://github.com/…'`              | Private repo without (valid) credentials, or wrong URL                   | Check the URL; select `github-credentials`; renew an expired token ([2.4](#24-private-repository-only-create-a-token-for-jenkins)) |
| `Couldn't find any revision to build`                                                             | Branch name doesn't match                                                | Branch Specifier `*/main` (or `*/master` if that is your branch)                                 |
| `'.\mvnw.cmd' is not recognized`                                                                  | `mvnw.cmd` is not in the repository root                                 | The repository root must contain `pom.xml` and `mvnw.cmd` ([2.3](#23-push-the-code))             |
| `JAVA_HOME environment variable is not defined correctly` / `release version 21 not supported`    | Jenkins doesn't see JDK 21                                               | Set the **system** `JAVA_HOME` to JDK 21, restart the Jenkins service ([Step 5](#step-5--java-and-maven)) |
| `Tests run: 5, Failures: 1` (Unit Tests stage red)                                                | A unit test failed                                                       | **Test Result** shows which and why; fix the code and push again                                 |
| `Tests run: 8, Failures: 1` (Integration Tests stage red)                                         | An integration test failed: an endpoint gives the wrong answer, or the application doesn't start (`Failed to load ApplicationContext`) | **Test Result** → `DemoApplicationIT` shows which and why; reproduce it locally with `.\mvnw.cmd clean verify` |
| `No test report files were found. Configuration error?` (Integration Tests stage)                 | No test class ends in `IT`, so no integration test ran                   | Integration test class names must end in `IT` (e.g. `DemoApplicationIT`) and be in `src/test/java` |
| `No such DSL method 'junit'` / `'withCredentials'`                                                | Plugin missing                                                           | Install **JUnit** / **Credentials Binding** ([Step 4](#step-4--install-the-jenkins-plugins))     |
| SonarQube Analysis or Quality Gate stage red (`withSonarQubeEnv`, `401 Unauthorized`, `Pipeline aborted due to quality gate failure`, timeout) | SonarQube not running, not connected, or the code failed the quality gate | [SONARQUBE-GUIDE.md → Troubleshooting](SONARQUBE-GUIDE.md#troubleshooting) |
| `COPY failed: no source files were specified` / `"/target": not found`                            | No JAR in `target`                                                       | The Package JAR stage must succeed; don't change `.dockerignore`                                 |
| `When using COPY with more than one source file, the destination must be a directory`             | Several JARs in `target`                                                 | Run a `clean` build (the pipeline does); locally use `.\mvnw.cmd clean package`                  |
| `unauthorized: incorrect username or password`                                                    | Wrong Docker Hub username or token in `dockerhub-credentials`, or token revoked | Update the credential ([Step 8](#step-8--store-the-credentials-in-jenkins))                |
| `denied: requested access to the resource is denied` (push)                                       | `DOCKER_IMAGE` doesn't start with *your* Docker Hub username, or the token is read-only | Fix `DOCKER_IMAGE` in the Jenkinsfile; create a **Read & Write** token             |
| `invalid reference format` / `repository name must be lowercase`                                  | `DOCKER_IMAGE` has capital letters or spaces                             | Use lowercase only, e.g. `johndoe/simple-spring-boot-app`                                        |
| `Bind for 0.0.0.0:8080 failed: port is already allocated`                                         | Something else uses port 8080 (e.g. the app started with `mvnw`)          | Stop it (`netstat -ano \| findstr :8080`), or set `HOST_PORT = '8081'` in the Jenkinsfile        |
| `Conflict. The container name "/simple-spring-boot-app" is already in use`                        | The old container could not be removed                                   | Run `docker rm -f simple-spring-boot-app`, then build again                                      |
| Smoke Test fails with `curl: (22)` or `curl: (7)` after all retries                               | The application didn't start in the container                            | `docker logs simple-spring-boot-app` shows the reason                                            |
| GitHub **Recent Deliveries** shows a red mark / `failed to connect to host`                       | ngrok isn't running, or its URL changed                                  | Start ngrok; update the Payload URL ([Step 10](#step-10--build-automatically-on-every-push-webhook)) |
| Webhook delivery is **200** but no build starts                                                   | Trigger not ticked, the job never ran, or a push to another branch       | Tick **GitHub hook trigger for GITScm polling**; run the job once manually; push to `main`       |
| Jenkins service doesn't start after changing **Log On**                                           | Wrong password, missing folder permissions, or company policy blocks "Log on as a service" | Re-enter the password; repeat [6.3 b](#63-run-the-jenkins-service-as-your-windows-account); check Event Viewer; ask IT about the policy |

---

## Housekeeping

- **Old builds:** Jenkins keeps the last 10 builds (`buildDiscarder`).
- **Old images:** every build adds a new image version on this PC. Remove images that no container uses, from time to time:
  ```powershell
  docker image prune -a
  ```
- **Stop the deployed application:**
  ```powershell
  docker rm -f simple-spring-boot-app
  ```
- **Token renewal:** GitHub and Docker Hub tokens can expire – update them in **Manage Jenkins → Credentials**.

---

## Running Jenkins on Linux instead

For a build server that runs 24/7 (Docker Desktop only runs while you are signed in to Windows), Jenkins on Linux is common. The pipeline stays the same; only the command syntax changes:

| Windows (this guide)                                        | Linux                                                              |
|-------------------------------------------------------------|--------------------------------------------------------------------|
| `bat '…'`                                                   | `sh '…'`                                                           |
| `.\\mvnw.cmd`                                               | `./mvnw` (run `chmod +x mvnw` once, or in the pipeline)            |
| `%DOCKER_IMAGE%`                                            | `$DOCKER_IMAGE`                                                    |
| `echo %DOCKERHUB_TOKEN%\| docker login -u %DOCKERHUB_USER% --password-stdin` | `echo "$DOCKERHUB_TOKEN" \| docker login -u "$DOCKERHUB_USER" --password-stdin` |
| `docker rm -f %CONTAINER_NAME% \|\| exit /b 0`              | `docker rm -f "$CONTAINER_NAME" \|\| true`                         |
| Jenkins service runs as your Windows account                | Add the `jenkins` user to the `docker` group: `sudo usermod -aG docker jenkins`, then restart Jenkins |
