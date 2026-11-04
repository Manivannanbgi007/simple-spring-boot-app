# CI/CD with Docker Compose – Jenkins + SonarQube

This folder runs the complete CI/CD environment for `simple-spring-boot-app` as Docker containers:
**Jenkins**, **SonarQube** and SonarQube's **PostgreSQL** database. Nothing is installed on the machine except Docker,
and the same files work on **Windows with Docker Desktop** and on **Ubuntu Linux** (for example an AWS EC2 instance).

On every push to GitHub, Jenkins builds and tests the application, checks it with SonarQube, packages the JAR,
builds a Docker image, scans it for vulnerabilities, pushes it to Docker Hub, tests the new image in a temporary
container and only then deploys it – with an automatic rollback if the new version fails. 13 stages in total
([Step 12](#step-12--check-every-stage)); the previous, simpler pipeline is kept in `Jenkinsfile.backup`.

---

## Contents

- [The short answer](#the-short-answer)
- [What runs where](#what-runs-where)
- [Folder structure](#folder-structure)
- [What replaced the manual Windows setup](#what-replaced-the-manual-windows-setup)
- [Part 1 – Set up on Windows (Docker Desktop)](#part-1--set-up-on-windows-docker-desktop) – Steps 1–13
- [Part 2 – Move to Ubuntu on AWS EC2](#part-2--move-to-ubuntu-on-aws-ec2) – separate guide: [AWS-EC2-GUIDE.md](AWS-EC2-GUIDE.md)
- [The files explained](#the-files-explained)
- [Persistent data (volumes)](#persistent-data-volumes)
- [Everyday commands](#everyday-commands)
- [Changing settings and rotating tokens](#changing-settings-and-rotating-tokens)
- [Backup and restore](#backup-and-restore)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Security notes](#security-notes)

---

## The short answer

> *"Can we install Docker and Docker Compose on an Ubuntu EC2 instance, copy the Compose configuration and start
> everything with Docker Compose?"*

**Yes.** That is exactly how this setup is built. On a new machine you:

1. install Docker (Docker Desktop on Windows, Docker Engine + the Compose plugin on Ubuntu),
2. get this folder (`git clone` the repository),
3. create the `.env` file with that machine's passwords, tokens and addresses,
4. run `docker compose up -d --build`.

Jenkins, its plugins, Java, Git, the Docker CLI, the credentials, the SonarQube connection and the pipeline job all
come from the files in this folder. Ubuntu needs **three small host settings** that Docker Desktop already handles for
you – they are in [Part 2](#part-2--move-to-ubuntu-on-aws-ec2):

| Host setting                      | Windows (Docker Desktop)         | Ubuntu (EC2)                                      |
|-----------------------------------|----------------------------------|---------------------------------------------------|
| Kernel limit for SonarQube's search engine (`vm.max_map_count`) | already set by Docker Desktop | set by `scripts/setup-ubuntu-host.sh` ([guide](AWS-EC2-GUIDE.md#step-3--launch-the-instance-with-automatic-setup)) |
| Group that owns the Docker socket (`DOCKER_GID` in `.env`) | `0`             | the `docker` group's number, e.g. `988`           |
| Network access from outside       | localhost + ngrok for the GitHub webhook | AWS security group rules                  |

The `.env` file is **not** in Git (it contains secrets), so you create it on each machine. Your data (build history,
SonarQube analyses) can be carried over with the [backup and restore](#backup-and-restore) commands.

---

## What runs where

```text
 Docker host: your PC (Docker Desktop) or an Ubuntu EC2 instance
 ┌───────────────────────────────────────────────────────────────────────────────────────────┐
 │  network cicd-network                                    network sonarqube-db (internal)  │
 │                                                                                           │
 │  ┌──────────────┐  analysis (token)   ┌──────────────┐  SQL   ┌──────────────┐           │
 │  │   jenkins    │ ──────────────────▶ │  sonarqube   │ ─────▶ │ sonarqube-db │           │
 │  │              │ ◀────────────────── │              │        │ (PostgreSQL) │           │
 │  └──────┬───────┘  quality gate       └──────────────┘        └──────────────┘           │
 │         │          (signed webhook)                                                       │
 │         │ docker build / push / run  (through /var/run/docker.sock)                       │
 │         ▼                                                                                 │
 │  ┌────────────────────────┐   Smoke Test: http://simple-spring-boot-app:8080/api/hello    │
 │  │ simple-spring-boot-app │   (deployed by the pipeline)                                  │
 │  └────────────────────────┘                                                               │
 └───────┬───────────────────────────────┬──────────────────────────────┬────────────────────┘
         │ :8079                         │ :9000                        │ :8080
     Jenkins UI                     SonarQube UI                   the application
         ▲
         │ webhook on every push (directly on EC2, through the optional ngrok container on a PC)
       GitHub                                     Docker Hub ◀── docker push / pull
```

| Service (container) | Image                                  | Port on the host | Purpose                                 |
|---------------------|----------------------------------------|------------------|-----------------------------------------|
| `jenkins`           | `cicd-jenkins:2.580.2` (built here)    | **8079**         | Runs the pipeline (`Jenkinsfile`)       |
| `sonarqube`         | `sonarqube:26.10.0.133078-community`   | **9000**         | Code quality analysis and quality gate  |
| `sonarqube-db`      | `postgres:17`                          | none             | SonarQube's database                    |
| `ngrok` (optional)  | `ngrok/ngrok:3.39.13-alpine`           | none             | Public HTTPS address for the GitHub webhook on a PC |
| `backup` (on demand)| `postgres:17`                          | none             | Backup and restore                      |
| `simple-spring-boot-app` | `manivannanbgi/simple-spring-boot-app:v<N>-<commit>` | **8080** | The application, started by the pipeline (not by Compose) |
| `simple-spring-boot-app-candidate` | the new image | none | Temporary: the pipeline tests a new image in it before it goes live, then removes it |
| Trivy (one per build) | `aquasec/trivy:0.76.1`, pinned by digest | none | Temporary: scans the new image for vulnerabilities (cache: volume `trivy-cache`) |

Containers in the same network reach each other **by service name**: Jenkins calls `http://sonarqube:9000`, SonarQube
calls `http://jenkins:8080`, and the Smoke Test calls `http://simple-spring-boot-app:8080`. Inside a container,
`localhost` means *that container itself*.

---

## Folder structure

```text
simple-spring-boot-app/
├── .gitattributes                  # NEW: keeps Unix line endings for files used inside Linux containers
├── Jenkinsfile                     # CHANGED: Linux commands (sh); scan, candidate test and rollback
├── Jenkinsfile.backup              # the previous Jenkinsfile (same 13-stage idea, no scan, no rollback)
├── Dockerfile                      # CHANGED: pinned base image, HEALTHCHECK, JVM memory setting
├── mvnw                            # CHANGED: marked as executable in Git (needed on Linux)
├── pom.xml, src/, ...              # the application – unchanged
└── cicd/                           # NEW: the CI/CD environment
    ├── README.md                   # this guide (reference for every file and setting)
    ├── AWS-EC2-GUIDE.md            # step-by-step setup on an AWS EC2 instance
    ├── docker-compose.yml          # all services, volumes, networks and secrets
    ├── .env.example                # template for .env (all settings, no secrets)
    ├── .env                        # YOUR settings and secrets – created by you, never committed
    ├── .gitignore                  # keeps .env and backups/ out of Git
    ├── jenkins/
    │   ├── Dockerfile              # Jenkins image: Jenkins LTS + Java 21 + Docker CLI + plugins + configuration
    │   ├── plugins.txt             # Jenkins plugins with exact versions
    │   └── casc.yaml               # Jenkins configuration as code: users, credentials, SonarQube, pipeline job
    ├── scripts/
    │   ├── setup-ubuntu-host.sh    # prepares an Ubuntu server: Docker, Compose, kernel settings, swap, log rotation
    │   └── create-env.sh           # creates .env with new random passwords and secrets
    ├── aws/
    │   └── user-data.sh            # EC2 user data: clones the repository and runs both scripts at the first boot
    ├── backup/
    │   ├── backup.sh               # backs up Jenkins data + SonarQube database
    │   └── restore.sh              # restores such a backup
    └── backups/                    # created by the first backup – never committed
```

Run every `docker compose` command **inside the `cicd` folder** – Compose reads `docker-compose.yml` and `.env` from
the current folder.

---

## What replaced the manual Windows setup

Everything you configured by hand in [CICD-GUIDE.md](../CICD-GUIDE.md) and [SONARQUBE-GUIDE.md](../SONARQUBE-GUIDE.md)
is now a file in this folder:

| Before (manual, on Windows)                                              | Now                                                                  |
|--------------------------------------------------------------------------|----------------------------------------------------------------------|
| Jenkins Windows installer, Windows service, port 8079                    | `jenkins` service in `docker-compose.yml`, `JENKINS_PORT` in `.env`  |
| Unlock Jenkins, setup wizard, first admin user                           | Wizard switched off in `jenkins/Dockerfile`; admin user in `casc.yaml` from `JENKINS_ADMIN_USER` / `JENKINS_ADMIN_PASSWORD` |
| Jenkins URL                                                              | `casc.yaml` → `location.url` from `JENKINS_PUBLIC_URL`               |
| Install suggested plugins, SonarQube Scanner, Pipeline Graph View        | `jenkins/plugins.txt` (installed when the image is built)            |
| JDK 21 + system `JAVA_HOME`                                              | Included in the base image `jenkins/jenkins:2.580.2-lts-jdk21`       |
| Git for Windows on the service's `PATH`                                  | Included in the base image                                           |
| Service runs as your Windows account, `icacls`, `PATH+TOOLS` for Docker  | Docker CLI in the image + Docker socket mounted + `DOCKER_GID`       |
| Credentials `dockerhub-credentials`, `github-credentials`, `sonarqube-token` | `casc.yaml` → `credentials`, values from `.env`                  |
| Manage Jenkins → System → SonarQube servers → `SonarQube`                | `casc.yaml` → `sonarGlobalConfiguration`                             |
| New Item → Pipeline → *Pipeline script from SCM* + *GitHub hook trigger* | `casc.yaml` → `jobs` (Job DSL), from `GITHUB_REPO_URL` / `GITHUB_BRANCH` |
| Manage Jenkins → Appearance → Pipeline Graph View ticks                  | `casc.yaml` → `appearance.pipelineGraphView`                         |
| `docker run ... sonarqube` with the embedded H2 database                 | `sonarqube` + `sonarqube-db` (PostgreSQL – can be upgraded and backed up) |
| SonarQube webhook to `http://host.docker.internal:8079/...`              | `http://jenkins:8080/sonarqube-webhook/` with a secret ([Step 7](#step-7--set-up-sonarqube-one-time)) |
| ngrok installed on Windows                                               | Optional `ngrok` container ([Step 11](#step-11--build-automatically-on-every-push-github-webhook)) |
| `bat '.\\mvnw.cmd ...'`, `%NAME%`, `localhost:8080` in the Smoke Test     | `sh './mvnw ...'`, `$NAME`, `simple-spring-boot-app:8080` ([Jenkinsfile](#jenkinsfile--what-changed)) |

**Still done by hand, once per installation** (the results are stored in the volumes and survive restarts):
creating the Docker Hub token, SonarQube's admin password, token, webhook and two settings ([Step 7](#step-7--set-up-sonarqube-one-time)),
and the webhook in GitHub ([Step 11](#step-11--build-automatically-on-every-push-github-webhook)).

---

## Part 1 – Set up on Windows (Docker Desktop)

Follow the steps in order; each one ends with a check. Use **PowerShell** for the commands (Git Bash works too, see
[Troubleshooting](#troubleshooting) for one Git Bash pitfall).

### Step 1 – Docker Desktop

Docker Desktop is the only program the CI/CD environment needs on Windows.

1. If it isn't installed: download it from https://www.docker.com/products/docker-desktop/, install it with the
   **WSL 2** option, and restart Windows when asked.
2. Docker Desktop → **Settings** → **General** → tick **Start Docker Desktop when you sign in to your computer** → **Apply**.
3. Memory: SonarQube, Jenkins and a Maven build together need about **6 GB**. Docker Desktop (WSL 2) may use half of
   your PC's memory by default. Check:

   ```powershell
   docker info --format "{{.MemTotal}}"     # bytes; 6 GB = about 6000000000
   ```

   If it is lower, create `%USERPROFILE%\.wslconfig` with the two lines `[wsl2]` and `memory=8GB`, run
   `wsl --shutdown`, and start Docker Desktop again.

**Check:**

```powershell
docker version            # shows a Client and a Server section
docker compose version    # Docker Compose version v2.30 or newer (Docker Desktop includes it)
```

> Docker Desktop runs only while you are signed in to Windows. For a build server that runs 24/7, use
> [Part 2](#part-2--move-to-ubuntu-on-aws-ec2).

### Step 2 – Retire the old Windows setup

The new containers need ports **8079** and **9000**, which the old Jenkins service and the old SonarQube container
still use. Stop them (nothing is deleted yet – [Step 13](#step-13--remove-the-old-windows-setup) removes them once the
new setup works).

In **PowerShell as Administrator**:

```powershell
Stop-Service Jenkins
Set-Service Jenkins -StartupType Disabled     # don't start again after a reboot
```

In a normal PowerShell:

```powershell
docker stop sonarqube                         # the old SonarQube container (H2 database)
docker update --restart=no sonarqube          # don't start again with Docker Desktop
```

If the old **ngrok** window is still open, stop it with **Ctrl + C**.

The deployed application (container `simple-spring-boot-app`) can keep running – the first build of the new pipeline
replaces it.

> The old SonarQube data can't be moved over: SonarQube's embedded H2 database can't be migrated to PostgreSQL.
> SonarQube starts fresh; your next analysis becomes the new starting point. The old Jenkins build history isn't moved
> either – the new Jenkins starts with build #1.

**Check:** `netstat -ano | findstr ":8079 :9000"` shows no `LISTENING` lines.

### Step 3 – Commit and push the project changes

Jenkins reads the `Jenkinsfile` and the code **from GitHub**, so the changes must be pushed before the first build:

- `Jenkinsfile` – Linux commands (the old one only works on Windows Jenkins).
- `mvnw` – marked executable in Git (Linux won't run it otherwise). This change is already staged.
- `.gitattributes` and the `cicd/` folder.
- Your other changes that the pipeline needs (for example JaCoCo, failsafe and the SonarQube plugin in `pom.xml`, and
  the new test classes).

```powershell
cd "D:\Drive E\dev\test\simple-spring-boot-app"
git status                     # review the list
git add -A
git commit -m "Run Jenkins and SonarQube with Docker Compose"
git push
```

> If `git status` lists files under `target/`: they were committed before `.gitignore` existed. Remove them from
> Git once (the files on disk stay): `git rm -r --cached target`, then commit.

**Check:** on GitHub, `mvnw` shows as executable and the `cicd` folder is there – **without** a `.env` file.

### Step 4 – Create the access tokens

**Docker Hub (required).** Jenkins pushes the image with an access token, never your password.

1. https://hub.docker.com → your avatar → **Account settings** → **Personal access tokens** → **Generate new token**.
2. **Description:** `jenkins` – **Access permissions:** **Read & Write** → **Generate**.
3. Copy the token now (shown only once). It goes into `DOCKERHUB_TOKEN` in Step 5.

**GitHub (only for a private repository).** The repository is public, so Jenkins needs no GitHub credentials. If you
make it private: GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens**
→ **Generate new token** → repository `simple-spring-boot-app` → **Contents: Read-only**. It goes into
`GITHUB_USERNAME` / `GITHUB_TOKEN`.

### Step 5 – Create the `.env` file

```powershell
cd "D:\Drive E\dev\test\simple-spring-boot-app\cicd"
Copy-Item .env.example .env
notepad .env
```

Fill in these values (every variable is explained in [.env – all settings](#env--all-settings)):

| Variable                 | What to enter                                                                     |
|--------------------------|-----------------------------------------------------------------------------------|
| `JENKINS_ADMIN_PASSWORD` | A strong password for the Jenkins user `admin`                                    |
| `DOCKERHUB_TOKEN`        | The Docker Hub token from Step 4                                                  |
| `SONARQUBE_DB_PASSWORD`  | A strong password for SonarQube's database – choose it now and keep it            |
| `SONAR_WEBHOOK_SECRET`   | A long random text (command below) – you also type it into SonarQube in Step 7    |
| `GITHUB_WEBHOOK_SECRET`  | Another long random text (same command) – you also type it into GitHub in Step 11 |
| `SONAR_TOKEN`            | **Leave empty for now** – SonarQube creates it in Step 7                          |

Create a random secret in PowerShell:

```powershell
$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); -join ($b | ForEach-Object { '{0:x2}' -f $_ })
```

(Linux / Git Bash: `openssl rand -hex 32`.)

Leave the other values as they are: `DOCKER_GID=0` is right for Docker Desktop, and the GitHub and Docker Hub
names are already yours. **Keep every line in the file**, even when its value is empty.

**Check:** `docker compose config --quiet` prints nothing. If a required value is missing it prints, for example,
`required variable SONARQUBE_DB_PASSWORD is missing a value`.

### Step 6 – Start the containers

```powershell
docker compose up -d --build
```

- `up` creates and starts all containers, `-d` runs them in the background, `--build` builds the Jenkins image from
  `jenkins/Dockerfile`.
- The first start downloads about 3 GB of images and takes a few minutes. Jenkins is ready after about 1 minute,
  SonarQube after 2–3 minutes.

**Check:**

```powershell
docker compose ps
```

Wait until all three show **`(healthy)`**:

```text
NAME                  IMAGE                                SERVICE        STATUS
cicd-jenkins-1        cicd-jenkins:2.580.2                 jenkins        Up 3 minutes (healthy)
cicd-sonarqube-1      sonarqube:26.10.0.133078-community   sonarqube      Up 3 minutes (healthy)
cicd-sonarqube-db-1   postgres:17                          sonarqube-db   Up 3 minutes (healthy)
```

`(health: starting)` means "still starting" – wait. If a service doesn't become healthy, look at its log:
`docker compose logs sonarqube` (or `jenkins`).

### Step 7 – Set up SonarQube (one time)

Open **http://localhost:9000**.

**7.1 Admin password.** Log in with `admin` / `admin`. SonarQube asks for a new password – choose a strong one and keep
it in your password manager.

**7.2 Two settings.** **Administration** → **Configuration** → **General Settings**:

| Category  | Setting                              | Value                         | Why                                                        |
|-----------|--------------------------------------|-------------------------------|------------------------------------------------------------|
| General   | **Server base URL**                  | `http://localhost:9000`       | The links in Jenkins and in the build log point here       |
| Security  | **Enable local webhooks validation** | **off**                       | Otherwise SonarQube refuses webhooks to private addresses, which includes the `jenkins` container |

Click **Save** after each change.

> Turning off the validation is safe here: only SonarQube administrators can create webhooks, and the webhook below
> is signed with a secret that Jenkins checks.

**7.3 Webhook to Jenkins.** **Administration** → **Configuration** → **Webhooks** → **Create**:

| Field  | Value                                                         |
|--------|---------------------------------------------------------------|
| Name   | `Jenkins`                                                     |
| URL    | `http://jenkins:8080/sonarqube-webhook/` – the final `/` is required |
| Secret | the value of `SONAR_WEBHOOK_SECRET` from your `.env`          |

The URL uses the container name `jenkins` and Jenkins' **container** port 8080 (not 8079) because the call goes
from container to container. This URL is the same on every machine.

**7.4 Token for Jenkins.** Avatar (top right) → **My Account** → **Security** → **Generate Tokens**:
**Name** `jenkins`, **Type** **User Token**, **Expires in** e.g. 90 days → **Generate** → copy the token (`squ_…`).

**Check:** **Webhooks** lists `Jenkins` with the URL above; **My Account → Security** lists the token `jenkins`.

### Step 8 – Give Jenkins the SonarQube token

1. Put the token into `.env`: `SONAR_TOKEN=squ_...`
2. Recreate the Jenkins container, so it reads the new value:

   ```powershell
   docker compose up -d --force-recreate jenkins
   ```

> Why `--force-recreate`? Docker Compose doesn't notice when only a **secret** in `.env` changes, so a plain
> `docker compose up -d` would keep the old value. Jenkins' build history and jobs are in the `jenkins_home` volume and
> are not affected by recreating the container.

**Check:** after about a minute `docker compose ps` shows `jenkins` as `(healthy)` again.

### Step 9 – Log in to Jenkins and check the configuration

Open **http://localhost:8079** and log in as `admin` with `JENKINS_ADMIN_PASSWORD`.

Everything is already configured by `jenkins/casc.yaml` – check that it is there:

| Where                                                | What you should see                                                        |
|------------------------------------------------------|----------------------------------------------------------------------------|
| Dashboard                                            | The job **simple-spring-boot-app**, and a message that Jenkins is configured by `casc.yaml` |
| **Manage Jenkins** → **Credentials**                 | `dockerhub-credentials`, `github-credentials`, `github-webhook-secret`, `sonarqube-token`, `sonarqube-webhook-secret` |
| **Manage Jenkins** → **System** → *SonarQube servers* | `SonarQube` – `http://sonarqube:9000` – token `sonarqube-token`            |
| **Manage Jenkins** → **Appearance** → *Pipeline Graph View* | Graph on job page and build page, stage names and durations – all ticked |
| **Manage Jenkins** → **Plugins** → **Installed plugins** | Configuration as Code, Job DSL, Pipeline, Git, GitHub, Credentials Binding, JUnit, Pipeline Graph View, SonarQube Scanner |
| Job → **Configure**                                  | *GitHub hook trigger for GITScm polling* ticked; *Pipeline script from SCM*, Git, your repository URL, branch `*/master`, script path `Jenkinsfile` |

> **Change settings in the files, not in the web UI.** Jenkins applies `casc.yaml` at every start, so a setting
> changed only in the UI is overwritten at the next restart. See [Changing settings](#changing-settings-and-rotating-tokens).

> Jenkins may show the warning **"Building on the built-in node can be a security issue"**. Builds run on the Jenkins
> container itself, which is the simplest setup for one team. The usual next step is a separate build agent – see
> [Security notes](#security-notes).

### Step 10 – Run the pipeline

Job **simple-spring-boot-app** → **Build Now**.

The first build takes a few minutes: the Maven Wrapper downloads Maven and all dependencies into the `jenkins_home`
volume (later builds reuse them). **Run this first build by hand** – after it, the GitHub webhook can start builds.

**Check:** the build turns green with 13 stages – [Step 12](#step-12--check-every-stage) shows what each one prints.

### Step 11 – Build automatically on every push (GitHub webhook)

GitHub must reach Jenkins from the internet. `http://localhost:8079` exists only on your PC, so on a PC the optional
**ngrok** container gives Jenkins a public HTTPS address. (On EC2 you use the instance's address instead –
[AWS-EC2-GUIDE.md, Step 11](AWS-EC2-GUIDE.md#step-11--build-on-every-push-github-webhook).)

1. Create a free account at https://ngrok.com → dashboard → **Your Authtoken** → copy it into `.env`:
   `NGROK_AUTHTOKEN=...`
2. Start the tunnel (the profile `tunnel` switches the `ngrok` service on):

   ```powershell
   docker compose --profile tunnel up -d
   docker compose logs ngrok
   ```

   The log contains a line with `url=https://<name>.ngrok-free.app` (newer accounts: `.ngrok-free.dev`) – that is
   Jenkins' public address. Free accounts
   get one fixed domain (ngrok dashboard → **Domains**), so the address stays the same after restarts.
3. GitHub repository → **Settings** → **Webhooks** → edit the existing webhook (from the old setup) or **Add webhook**:

   | Field         | Value                                                         |
   |---------------|---------------------------------------------------------------|
   | Payload URL   | `https://<name>.ngrok-free.app/github-webhook/` – the final `/github-webhook/` is required |
   | Content type  | `application/json`                                            |
   | Secret        | the value of `GITHUB_WEBHOOK_SECRET` from your `.env`         |
   | Which events  | **Just the push event**                                       |
   | Active        | ticked                                                        |

**Check:**

1. GitHub → **Webhooks** → your webhook → **Recent Deliveries**: green tick, response **200**.
   (**400** means the Secret differs from `GITHUB_WEBHOOK_SECRET` – Jenkins ignores requests that GitHub didn't sign.)
2. Push a small change. A new build starts within seconds; the build page says **Started by GitHub push by …**.

> ngrok makes your Jenkins reachable from the internet. Jenkins requires a login for everything except the webhook
> address. Stop the tunnel when you don't need it: `docker compose --profile tunnel stop ngrok`.

**No webhook possible?** Let Jenkins check GitHub every 2 minutes instead: in `jenkins/casc.yaml` replace
`githubPush()` with `pollSCM { scmpoll_spec('H/2 * * * *') }`, then `docker compose up -d --build`.

### Step 12 – Check every stage

Open the job: the **Pipeline Graph View** shows the stages of the recent builds. Click a build, then a stage, to see
that stage's log; the full log is in **Console Output**.

| #  | Stage              | What happens                                                | Success looks like this in the log |
|----|--------------------|-------------------------------------------------------------|------------------------------------|
| 1  | Checkout           | Gets the code from GitHub; sets the image tag `v<N>-<commit>` | `Checking out Revision 1a2b3c… (refs/remotes/origin/master)`, `Image tag: v42-1a2b3c4` |
| 2  | Build              | Compiles (`./mvnw -B -ntp clean compile`)                   | `BUILD SUCCESS` |
| 3  | Unit Tests         | Runs the unit tests (`./mvnw -B -ntp test`) and JaCoCo coverage | `Tests run: 5, Failures: 0, Errors: 0, Skipped: 0` |
| 4  | Integration Tests  | Starts the application on a random port, tests it over HTTP | `Tests run: 8, Failures: 0, Errors: 0, Skipped: 0` |
| 5  | SonarQube Analysis | Sends code, test results and coverage to SonarQube          | `ANALYSIS SUCCESSFUL, you can find the results at: http://localhost:9000/dashboard?id=simple-spring-boot-app` |
| 6  | Quality Gate       | Waits for SonarQube's verdict (webhook)                     | `SonarQube task '…' completed. Quality gate is 'OK'` |
| 7  | Package JAR        | Builds and archives the JAR                                 | `Building jar: /var/jenkins_home/workspace/simple-spring-boot-app/target/simple-spring-boot-app-v<N>.jar` |
| 8  | Docker Build       | Builds the image, tagged `v<N>-<commit>` and `latest`, with commit/version labels | `naming to docker.io/manivannanbgi/simple-spring-boot-app:v<N>-<commit> done` |
| 9  | Image Scan         | Trivy scans OS packages and Java libraries; stops on fixable HIGH/CRITICAL vulnerabilities | a table with `0` for `ubuntu` and `app/app.jar` |
| 10 | Docker Push        | Logs in to Docker Hub with the token, uploads both tags     | `Login Succeeded`, `v<N>-<commit>: digest: sha256:…` |
| 11 | Candidate Test     | Starts the new image as `simple-spring-boot-app-candidate` (no public port) and checks it; the running application isn't touched | `{"groups":["liveness","readiness"],"status":"UP"}` and the API message |
| 12 | Deploy             | Remembers the running version, then replaces the container  | `Running now: manivannanbgi/simple-spring-boot-app:v<N-1>-…`, a 64-character container ID |
| 13 | Smoke Test         | Checks `/actuator/health` and the API of the live container | `{"groups":["liveness","readiness"],"status":"UP"}`, `{"message":"Hello! Spring Boot application is running successfully."}` |

After the stages, **Declarative: Post Actions** logs out of Docker Hub (`Removing login credentials for https://index.docker.io/v1/`)
and, after a successful build, deletes local image versions older than the 3 newest (Docker Hub keeps all of them).
If the Deploy or Smoke Test stage failed, it **rolls back**: `ROLLBACK: starting the previous version … again`, then
`ROLLBACK done: … is running`.

`<N>` is the Jenkins build number, `<commit>` the first 7 characters of the Git commit. In the Candidate Test and the
Smoke Test you may first see `curl: (7) Failed to connect to … port 8080` – normal: the application was still starting
and curl retried (for up to about a minute).

The first build after this change takes about 2 minutes longer: Trivy downloads its vulnerability database once into
the `trivy-cache` volume.

**Check the application:** open http://localhost:8080/api/hello. The image is on Docker Hub under **Tags**, and the
build page shows the test results, the JAR under **Build Artifacts** and a **SonarQube Quality Gate** badge.

### Step 13 – Remove the old Windows setup

Only after the new pipeline has run successfully:

| What                         | How                                                                                 |
|------------------------------|-------------------------------------------------------------------------------------|
| Jenkins Windows service      | Windows **Settings** → **Apps** → **Jenkins** → **Uninstall**; then delete `C:\ProgramData\Jenkins` and `D:\Jenkins` |
| Old SonarQube container + data | `docker rm sonarqube` then `docker volume rm sonarqube_data sonarqube_extensions sonarqube_logs` |
| ngrok on Windows             | `winget uninstall ngrok.ngrok` (or delete the downloaded `ngrok.exe`)               |

Keep JDK 21 and Git – you still use them to develop. The CI/CD environment no longer needs them.

---

## Part 2 – Move to Ubuntu on AWS EC2

The same files and the same `docker compose up -d --build` run on an Ubuntu EC2 instance. The complete step-by-step
guide – AWS key pair, security group, instance, Elastic IP, the automatic server setup, `.env`, the SSH tunnel, the
one-time SonarQube and GitHub steps, backups, security and the way to other AWS services – is a separate document:

**[AWS-EC2-GUIDE.md](AWS-EC2-GUIDE.md)**

In short, what differs from the Windows setup:

| On Windows (Part 1) | On EC2 |
|---------------------|--------|
| Docker Desktop installed by hand | `aws/user-data.sh` runs `scripts/setup-ubuntu-host.sh` at the first boot: Docker Engine, Compose, `vm.max_map_count`, swap, log rotation |
| `.env` filled in by hand | `scripts/create-env.sh` creates it with new random secrets, the right `DOCKER_GID` and the Jenkins address; you add only the Docker Hub token (and later the SonarQube token) |
| `localhost:8079` / `localhost:9000` | through an SSH tunnel: `localhost:18079` / `localhost:19000` – the ports stay closed to the internet |
| GitHub webhook through ngrok | directly to `http://<elastic-ip>:8079/github-webhook/`, open only for GitHub's webhook addresses |

---

## The files explained

### docker-compose.yml

The file describes the whole environment. The important parts, from top to bottom:

**`name: cicd`** – the project name. Compose puts it in front of the volume names (`cicd_jenkins_home`, …) and
container names (`cicd-jenkins-1`, …), so they are the same on every machine.

**`services:`** – one entry per container.

| Service        | Key settings                                                                                    |
|----------------|--------------------------------------------------------------------------------------------------|
| `jenkins`      | `build: ./jenkins` builds the image from `jenkins/Dockerfile` and names it `cicd-jenkins:2.580.2`. `ports: "8079:8080"` = port 8079 on the host → 8080 in the container. `environment:` passes the non-secret settings to `casc.yaml`; `secrets:` passes the secret ones as files. `group_add: DOCKER_GID` lets the `jenkins` user use the Docker socket. Volumes: `jenkins_home` (all Jenkins data) and the Docker socket. |
| `sonarqube`    | Exact image version. `depends_on … service_healthy` = start only when the database is ready. `SONAR_JDBC_*` = how to reach the database. `ulimits` = the open-file and thread limits SonarQube's search engine requires. In both networks: `cicd` (Jenkins reaches it) and `sonarqube-db` (it reaches its database). |
| `sonarqube-db` | PostgreSQL 17. `POSTGRES_*` create the database `sonar` and user `sonar` on the **first** start. Only in the internal `sonarqube-db` network and **no `ports:`** – nothing outside can reach it. |
| `ngrok`        | `profiles: [tunnel]` = starts only with `docker compose --profile tunnel up -d`. Forwards a public HTTPS address to `jenkins:8080`. |
| `backup`       | `profiles: [backup]` = never starts with `up`; run it with `docker compose run --rm backup`. Uses the PostgreSQL image for `pg_dump`/`pg_restore` and mounts the volumes it backs up. |

**Common settings:**

| Setting                    | Meaning                                                                                       |
|----------------------------|-----------------------------------------------------------------------------------------------|
| `restart: unless-stopped`  | Docker starts the container again after a crash or a reboot, unless you stopped it yourself    |
| `healthcheck:`             | A command Docker runs regularly. `docker compose ps` shows `(healthy)` when it succeeds. Jenkins: the login page answers; SonarQube: `/api/system/status` says `UP`; database: `pg_isready` |
| `${NAME:-default}`         | The value of `NAME` from `.env`, or `default` if it is empty                                   |
| `${NAME:?message}`         | The value of `NAME`; if it is empty, Compose stops with `message` – used for required values    |

**`secrets:`** – each secret is created from a `.env` variable (`environment: DOCKERHUB_TOKEN`) and appears inside
the Jenkins container as a file, e.g. `/run/secrets/dockerhub_token`. Jenkins reads the files; builds don't see them as
environment variables, so a `sh 'env'` in a Jenkinsfile can't print them. Builds get secrets only through
`withCredentials`, where Jenkins masks them as `****`.

**`volumes:`** – named volumes: storage that Docker keeps outside the containers. See
[Persistent data](#persistent-data-volumes).

**`networks:`**

| Network                    | Members                                      | Notes                                                    |
|----------------------------|----------------------------------------------|----------------------------------------------------------|
| `cicd-network`             | jenkins, sonarqube, ngrok, the deployed application | The fixed name `cicd-network` is used by the Jenkinsfile (`DOCKER_NETWORK`) to put the deployed container into this network |
| `cicd_sonarqube-db`        | sonarqube, sonarqube-db, backup              | `internal: true` – no traffic to or from outside this network |

### .env – all settings

`.env` is read by Docker Compose from the `cicd` folder. Lines starting with `#` are comments. Values need no quotes.

| Variable                 | Used by                      | Secret | Example / default                                   | Meaning |
|--------------------------|------------------------------|--------|-----------------------------------------------------|---------|
| `JENKINS_PORT`           | `jenkins` port               | no     | `8079`                                              | Port of the Jenkins UI on the host |
| `JENKINS_PUBLIC_URL`     | `casc.yaml` → Jenkins URL    | no     | `http://localhost:8079/`                            | Address people use to open Jenkins (with final `/`) |
| `JENKINS_ADMIN_USER`     | `casc.yaml` → user           | no     | `admin`                                             | Jenkins administrator login |
| `JENKINS_ADMIN_PASSWORD` | secret → `casc.yaml`         | **yes**| –                                                   | Its password – set again at every start |
| `DOCKER_GID`             | `jenkins` → `group_add`      | no     | `0` (Docker Desktop), e.g. `988` (Ubuntu)           | Group owning the Docker socket |
| `GITHUB_REPO_URL`        | `casc.yaml` → job            | no     | `https://github.com/Manivannanbgi007/simple-spring-boot-app.git` | Repository the job builds |
| `GITHUB_BRANCH`          | `casc.yaml` → job            | no     | `master`                                            | Branch the job builds |
| `GITHUB_USERNAME`        | `casc.yaml` → `github-credentials` | no | empty                                             | Private repository only |
| `GITHUB_TOKEN`           | secret → `github-credentials`| **yes**| empty                                               | Private repository only (Contents: Read-only) |
| `GITHUB_WEBHOOK_SECRET`  | secret → `github-webhook-secret` | **yes** | –                                              | Same text as the Secret of the webhook in GitHub |
| `DOCKERHUB_USERNAME`     | `casc.yaml` → `dockerhub-credentials` | no | `manivannanbgi`                               | Docker Hub user |
| `DOCKERHUB_TOKEN`        | secret → `dockerhub-credentials` | **yes** | –                                               | Docker Hub access token (Read & Write) |
| `SONARQUBE_PORT`         | `sonarqube` port             | no     | `9000`                                              | Port of the SonarQube UI on the host |
| `SONAR_TOKEN`            | secret → `sonarqube-token`   | **yes**| empty until Step 7                                  | Token Jenkins uses for the analysis |
| `SONAR_WEBHOOK_SECRET`   | secret → `sonarqube-webhook-secret` | **yes** | –                                            | Same text as the webhook secret in SonarQube |
| `SONARQUBE_DB_PASSWORD`  | `sonarqube`, `sonarqube-db`, `backup` | **yes** | –                                          | Database password (set once – see [Changing settings](#changing-settings-and-rotating-tokens)) |
| `NGROK_AUTHTOKEN`        | `ngrok`                      | **yes**| empty                                               | Only for the optional tunnel on a PC |

> The image name `manivannanbgi/simple-spring-boot-app` is set in the `Jenkinsfile` (`DOCKER_IMAGE`), because it
> belongs to the application. If the Docker Hub account changes, change both `DOCKERHUB_USERNAME` and `DOCKER_IMAGE`.

### jenkins/Dockerfile

Builds the Jenkins image, so nothing has to be installed by hand:

| Line                                             | Purpose                                                                 |
|--------------------------------------------------|-------------------------------------------------------------------------|
| `FROM jenkins/jenkins:2.580.2-lts-jdk21`         | Official Jenkins LTS with Java 21, Git and curl (Debian Linux)          |
| `COPY --from=docker:29.9.2-cli …`                | Copies the Docker command-line tool and its `buildx` plugin from the official Docker image. Only the client: it sends commands to the host's Docker Engine through the socket |
| `COPY plugins.txt` + `RUN jenkins-plugin-cli …`  | Installs the plugins at build time                                      |
| `COPY casc.yaml` + `ENV CASC_JENKINS_CONFIG=…`   | Tells the Configuration as Code plugin where the configuration is       |
| `ENV JAVA_OPTS=-Djenkins.install.runSetupWizard=false` | No setup wizard – `casc.yaml` already creates the admin user      |

The image runs as the normal user `jenkins` (not root).

### jenkins/plugins.txt – the required plugins

One plugin per line as `<plugin-id>:<version>`; their dependencies (about 65 plugins) are installed automatically.

| Plugin ID               | Name                      | Why the pipeline needs it                                        |
|-------------------------|---------------------------|------------------------------------------------------------------|
| `configuration-as-code` | Configuration as Code     | Applies `casc.yaml` at every start                               |
| `job-dsl`               | Job DSL                   | Creates the pipeline job described in `casc.yaml`                |
| `workflow-aggregator`   | Pipeline                  | Runs the `Jenkinsfile`                                           |
| `git`                   | Git                       | `checkout scm`                                                   |
| `github`                | GitHub                    | Receives the GitHub webhook and starts the build                 |
| `credentials-binding`   | Credentials Binding       | `withCredentials(...)` for the Docker Hub token                  |
| `junit`                 | JUnit                     | `junit '...'` – test results on the build page                   |
| `pipeline-graph-view`   | Pipeline Graph View       | Stage diagram on the job and build pages                         |
| `sonar`                 | SonarQube Scanner         | `withSonarQubeEnv(...)` and `waitForQualityGate`                 |

Not needed: "Docker Pipeline", "Maven Integration" (the pipeline uses plain `./mvnw` and `docker` commands) and
"Pipeline: Stage View" (replaced by Pipeline Graph View).

### jenkins/casc.yaml – Jenkins configuration as code

Jenkins applies this file **at every start**. Its sections:

| Section                                | What it configures                                                            |
|----------------------------------------|-------------------------------------------------------------------------------|
| `jenkins.systemMessage`                | The note on the dashboard                                                     |
| `jenkins.numExecutors: 2`              | Two builds can run at the same time                                           |
| `jenkins.securityRealm`                | Jenkins' own user database with the admin user; nobody can sign up            |
| `jenkins.authorizationStrategy`        | Logged-in users can do everything; anonymous visitors see only the login page |
| `unclassified.location.url`            | The Jenkins URL                                                               |
| `unclassified.sonarGlobalConfiguration`| SonarQube server `SonarQube` at `http://sonarqube:9000` with the token and the webhook secret |
| `appearance.pipelineGraphView`         | Pipeline Graph View on job and build pages                                    |
| `credentials`                          | The four credentials (IDs used by the Jenkinsfile and the SonarQube server)   |
| `jobs`                                 | The pipeline job, written in Job DSL: repository, branch, `Jenkinsfile`, GitHub push trigger |

`${NAME}` is filled in when Jenkins starts: `UPPER_CASE` names come from environment variables, `lower_case` names
from the secret files in `/run/secrets/`, and `${name:-}` means "empty if not set".

### Jenkinsfile – what changed

Compared with the Windows `Jenkinsfile`, Jenkins now runs in a **Linux** container, so the commands changed:

| Before (Windows Jenkins)                               | Now (Linux container)                                         | Why |
|--------------------------------------------------------|---------------------------------------------------------------|-----|
| `bat '.\\mvnw.cmd -B ...'`                             | `sh './mvnw -B ...'`                                          | Linux shell and the Linux Maven Wrapper |
| `%NAME%`                                               | `$NAME` (inside single quotes)                                | Shell syntax; single quotes let the shell, not Groovy, read the value – secrets stay out of the log |
| `echo %DOCKERHUB_TOKEN%\| docker login ...`             | `echo "$DOCKERHUB_TOKEN" \| docker login ... --password-stdin` | Same, Linux syntax |
| `docker rm -f ... \|\| exit /b 0`                       | `docker rm -f ... \|\| true`                                  | "No error if there is no old container" |
| `docker run -d ... -p 8080:8080 ...`                   | adds `--network "$DOCKER_NETWORK"` (`cicd-network`)            | So Jenkins can reach the new container by name |
| Smoke Test `curl http://localhost:8080/api/hello`      | `curl http://$CONTAINER_NAME:8080/api/hello`                  | Inside the Jenkins container `localhost` is Jenkins itself |
| no `docker logout`                                     | `post { always { sh 'docker logout' } }`                      | Don't leave the Docker Hub login stored in `jenkins_home` |

The `docker` commands run on the **host's** Docker Engine (through the socket). So the image and the deployed container
appear in `docker images` / `docker ps` on the host, exactly as before. One consequence for future changes: in a
`docker run -v <path>:...` inside the pipeline, `<path>` would be a path on the **host**, not in the Jenkins container.

**Production safeguards** in the current `Jenkinsfile` (the previous version without them is `Jenkinsfile.backup`):

| Safeguard | How | Why |
|-----------|-----|-----|
| One build at a time | `options { disableConcurrentBuilds() }` | Two quick pushes would otherwise deploy at the same moment – the older build could finish last and put the older version back |
| Unique image tags | `IMAGE_TAG = v<N>-<commit>`, set in the Checkout stage; labels `org.opencontainers.image.revision` / `.version` | Build numbers start again at 1 on a new Jenkins – `v1` would overwrite an old image on Docker Hub. The commit shows what is inside |
| Vulnerability scan before the push | **Image Scan** stage: Trivy, `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` | A vulnerable image is never published or deployed. Only problems that already have a fix stop the build |
| Least privilege for the scanner | the image is passed as a file (`docker save … \| docker run -i …`); Trivy pinned by digest | Trivy gets no Docker socket, and a re-pushed tag can't change the scanner (this happened with Trivy in March 2026) |
| Test before the switch | **Candidate Test**: the new image runs as a temporary container and must report `UP` and answer the API | An image that doesn't start never replaces the running application |
| Automatic rollback | **Deploy** remembers the running image; `post { unsuccessful { … } }` starts it again if Deploy or Smoke Test failed | A version that fails after the switch is replaced by the previous one within about a minute |
| Health and memory | Dockerfile `HEALTHCHECK` (`/actuator/health`), `--memory 512m`, `-XX:MaxRAMPercentage=75` | `docker ps` shows `(healthy)`; a memory leak can't take the whole host down |
| Reproducible base image | `FROM eclipse-temurin:21.0.13_9-jre-resolute@sha256:…` | `21-jre` moves: it already changed from Ubuntu 24.04 to 26.04. Updates are now deliberate ([Upgrading](#upgrading)) |
| Disk housekeeping | `post { success { … } }` keeps the 3 newest image versions on the host | Every build adds an image; the 3 newest are enough for a rollback |
| No redundant stages | the old **Docker Pull** stage is gone; **Docker Login** is part of **Docker Push** | On one host, pulling the image just pushed adds time and a failure point, not safety |

**Downtime:** the switch itself still has a few seconds of downtime (the old container must free port 8080 before the
new one starts). Zero downtime needs a reverse proxy (for example Traefik or nginx) in front of two containers.

**Back to the previous pipeline:** copy `Jenkinsfile.backup` over `Jenkinsfile` and push – or set
`scriptPath('Jenkinsfile.backup')` in `jenkins/casc.yaml` and run `docker compose up -d --build`.

### backup/, .gitattributes, .gitignore

- **`backup/backup.sh`** – writes `backups/<date_time>/jenkins_home.tar.gz` (jobs, build history, credentials,
  settings) and `sonarqube_db.dump` (the whole SonarQube database). It leaves out what is recreated automatically:
  workspaces, download caches, plugins and Jenkins' program files. A backup is about 25 MB plus the archived JARs.
- **`backup/restore.sh`** – puts such a backup back and deletes SonarQube's search index, which SonarQube rebuilds
  from the database.
- **`.gitattributes`** (project root) – `mvnw`, `*.sh` and everything in `cicd/` keep Unix line endings (LF), also
  when checked out on Windows. Linux can't run scripts with Windows line endings (`bad interpreter`, `$'\r'`).
- **`cicd/.gitignore`** – keeps `.env` and `backups/` out of Git; both contain secrets.

---

## Persistent data (volumes)

Containers are disposable: they are deleted and recreated on upgrades and configuration changes. Everything that must
survive lives in **named volumes**.

| Volume                      | Mounted at (container)        | Contains                                                              | If it is lost |
|-----------------------------|-------------------------------|-----------------------------------------------------------------------|---------------|
| `cicd_jenkins_home`         | `/var/jenkins_home`           | Jobs, build history and logs, archived JARs, test results, credentials (encrypted), installed plugins, Maven cache (`.m2`) | Build history is gone. Configuration, credentials and the job come back from `casc.yaml` + `.env` at the next start |
| `cicd_sonarqube_db`         | `/var/lib/postgresql/data`    | **All SonarQube data**: projects, analyses, users, tokens, quality gates, webhooks, settings | Everything in SonarQube is gone – back it up |
| `cicd_sonarqube_data`       | `/opt/sonarqube/data`         | SonarQube's search index                                              | Nothing – rebuilt from the database |
| `cicd_sonarqube_extensions` | `/opt/sonarqube/extensions`   | Extra SonarQube plugins (none by default)                             | Reinstall extra plugins |
| `cicd_sonarqube_logs`       | `/opt/sonarqube/logs`         | SonarQube log files                                                   | Only old logs |

**What keeps your data, and what deletes it:**

| Command / event                                         | Containers      | Volumes (data)   |
|---------------------------------------------------------|-----------------|------------------|
| `docker compose restart`, `stop`, `start`               | kept            | kept             |
| `docker compose up -d`, `up -d --build`, `--force-recreate` | recreated if changed | kept     |
| `docker compose down`                                   | removed         | kept             |
| PC / EC2 reboot, Docker Desktop restart                 | started again (`restart: unless-stopped`) | kept |
| `docker compose down -v`                                | removed         | **DELETED**      |
| `docker volume rm cicd_...`, `docker volume prune -a`   | –               | **DELETED**      |

Look at the volumes: `docker volume ls --filter name=cicd_` – their size: `docker system df -v`.

---

## Everyday commands

Run them in the `cicd` folder. `<service>` is `jenkins`, `sonarqube` or `sonarqube-db`; without it, the command
applies to all services.

| Task                                                   | Command                                          |
|--------------------------------------------------------|--------------------------------------------------|
| Start everything / apply changes to `.env` or `docker-compose.yml` | `docker compose up -d`               |
| Apply changes to `jenkins/` (Dockerfile, plugins, `casc.yaml`) | `docker compose up -d --build`           |
| Apply a changed **secret** in `.env`                   | `docker compose up -d --force-recreate jenkins`  |
| Status and health                                      | `docker compose ps`                              |
| Logs (last 100 lines / follow live, Ctrl + C to stop)  | `docker compose logs --tail 100 <service>` / `docker compose logs -f <service>` |
| Restart one service                                    | `docker compose restart <service>`               |
| Stop everything (frees memory, keeps everything)       | `docker compose stop`                            |
| Start again after `stop`                               | `docker compose start`                           |
| Remove the containers (keeps the data)                 | `docker compose down`                            |
| Open a shell in a container                            | `docker compose exec jenkins bash`               |
| Restart Jenkins after the running builds finish        | http://localhost:8079/safeRestart                |
| Deployed application: status / log                     | `docker ps --filter name=simple-spring-boot-app` / `docker logs simple-spring-boot-app` |
| Free disk space (images no container uses) – **while the stack is running** | `docker image prune -a`     |

**`restart` vs `up -d`:** `restart` only restarts the existing container – it does **not** apply changes to `.env`,
`docker-compose.yml` or the image. To apply changes, use `up -d` (with `--build` or `--force-recreate` as in the table).

**`docker compose down`** prints `Network cicd-network Resource is still in use` while the deployed application is
running. That is expected: the application container uses the network, so Docker keeps it, and the next `up` reuses it.

---

## Changing settings and rotating tokens

| What you change                                   | Where                              | Then run                                          |
|---------------------------------------------------|------------------------------------|---------------------------------------------------|
| Port, URL, repository, branch, user names         | `.env`                             | `docker compose up -d`                            |
| A password or token (`JENKINS_ADMIN_PASSWORD`, `DOCKERHUB_TOKEN`, `SONAR_TOKEN`, `GITHUB_TOKEN`, `GITHUB_WEBHOOK_SECRET`, `SONAR_WEBHOOK_SECRET`) | `.env` | `docker compose up -d --force-recreate jenkins` |
| Jenkins settings, credentials, the job            | `jenkins/casc.yaml`                | `docker compose up -d --build`                    |
| Plugins                                           | `jenkins/plugins.txt`              | `docker compose up -d --build`                    |
| The pipeline stages                               | `Jenkinsfile` (project root)       | commit and push – the next build uses it          |
| SonarQube settings, quality gates, webhook, users | SonarQube web UI                   | nothing – stored in the database                  |

**Renewing a token** (Docker Hub, SonarQube, GitHub): create the new token, put it into `.env`, run
`docker compose up -d --force-recreate jenkins`, then revoke the old token. Change the webhook secret in SonarQube and
in `.env` at the same time.

**Changing the Jenkins admin password:** in `.env` (`JENKINS_ADMIN_PASSWORD`) – a password changed in the web UI is
reset at the next start.

**Changing `SONARQUBE_DB_PASSWORD`:** PostgreSQL reads it only when the database is first created. To change it later:

```powershell
docker compose exec sonarqube-db psql -U sonar -d sonar -c "ALTER USER sonar PASSWORD 'the-new-password';"
```

Then put the new password into `.env` and run `docker compose up -d`.

---

## Backup and restore

A backup contains the Jenkins data (`jenkins_home.tar.gz`) and the SonarQube database (`sonarqube_db.dump`), in
`cicd/backups/<date_time>/` (time in UTC). Keep copies somewhere else as well – for example a network drive or S3.
The folder contains your credentials: store it as carefully as `.env`.

**Back up** (Jenkins is stopped for about a minute so that no build writes files during the backup):

```powershell
docker compose stop jenkins
docker compose run --rm backup
docker compose start jenkins
```

Expected output:

```text
Jenkins data -> backups/2026-11-03_0930/jenkins_home.tar.gz
SonarQube database -> backups/2026-11-03_0930/sonarqube_db.dump
Backup finished: cicd/backups/2026-11-03_0930 (time in UTC)
```

**Restore** – **replaces** the current Jenkins data and SonarQube database with the backup:

```powershell
docker compose stop jenkins sonarqube
docker compose run --rm backup restore.sh 2026-11-03_0930
docker compose start jenkins sonarqube
```

SonarQube then rebuilds its search index, which takes a minute or two longer than a normal start.

**Restore on a new machine** (for example EC2): first `docker compose up -d` once so the volumes and the database
exist, then the three commands above – see [AWS-EC2-GUIDE.md](AWS-EC2-GUIDE.md#backups-and-moving-to-a-new-instance).

> On Linux the backup files belong to `root` (they are written by a container). Delete old backups with `sudo rm -r backups/<folder>`.

---

## Upgrading

Always [make a backup](#backup-and-restore) first.

**Jenkins** – check https://www.jenkins.io/changelog-stable/ for the new LTS version, then change the version in two
places: `FROM jenkins/jenkins:<version>-lts-jdk21` in `jenkins/Dockerfile` and `image: cicd-jenkins:<version>` in
`docker-compose.yml`. Run `docker compose up -d --build`.

**Plugins** – **Manage Jenkins** → **Plugins** → **Updates** lists newer versions. Copy the new version numbers into
`jenkins/plugins.txt` and run `docker compose up -d --build`. (A plugin updated only in the web UI works, but isn't
recorded in Git – the next machine built from the files wouldn't have it.) After a Jenkins upgrade, you can also write
`latest` instead of a version, build, read the installed versions under **Installed plugins**, and pin them again.

**SonarQube** – change the `sonarqube:` image tag in `docker-compose.yml`, run `docker compose up -d`. If
http://localhost:9000 then says it is under maintenance, open http://localhost:9000/setup and start the database
upgrade. Read the upgrade notes of the new version first: https://docs.sonarsource.com/sonarqube-community-build/

**PostgreSQL 17.x** (bug and security fixes): `docker compose pull sonarqube-db` then `docker compose up -d`.
A new **major** version (for example 18) can't read the old data files: back up, change both `postgres:17` tags
(`sonarqube-db` and `backup`), `docker compose down`, `docker volume rm cicd_sonarqube_db`, `docker compose up -d`,
then restore. Check the new image's notes first – PostgreSQL 18 images use a different data folder.

**Docker CLI in the Jenkins image** – `docker:29.9.2-cli` in `jenkins/Dockerfile`. Update it when the host's Docker
Engine gets a new major version (`docker version` → Server).

**Application base image** – `FROM eclipse-temurin:<version>-jre-resolute@sha256:<digest>` in the project's
`Dockerfile`. Java gets security updates four times a year (January, April, July, October). Find the new tag on
https://hub.docker.com/_/eclipse-temurin/tags (name filter `21.0.`, ending in `-jre-resolute`), copy its **index
digest** (`sha256:…`), change both in the `Dockerfile`, commit and push – the Image Scan checks the result. Also update
it when the Image Scan reports fixable vulnerabilities in `ubuntu`.

**Trivy** – `TRIVY_IMAGE` in the `Jenkinsfile` (tag **and** digest). Check the release notes and security advisories
first (https://github.com/aquasecurity/trivy/releases, https://github.com/aquasecurity/trivy/security/advisories);
versions 0.69.4–0.69.6 were malicious (March 2026 compromise). Take the digest from
https://hub.docker.com/r/aquasec/trivy/tags.

---

## Troubleshooting

**Where to look:**

1. `docker compose ps` – which service isn't `Up (healthy)`?
2. `docker compose logs --tail 200 <service>` – the reason is usually in the last lines.
3. Jenkins build page → **Console Output** – the **first** `ERROR` is usually the real cause.
4. SonarQube → **Administration** → **Configuration** → **Webhooks** → **⋮** → **Show recent deliveries**.
5. GitHub → repository **Settings** → **Webhooks** → **Recent Deliveries**.

| Symptom / error message                                                         | Cause                                                              | Solution |
|---------------------------------------------------------------------------------|--------------------------------------------------------------------|----------|
| `Bind for 0.0.0.0:8079 failed: port is already allocated` (or `:9000`)          | The old Jenkins service or the old `sonarqube` container is still running | [Step 2](#step-2--retire-the-old-windows-setup) |
| `required variable … is missing a value`                                        | A required value is empty in `.env`                                | Fill it in; `docker compose config --quiet` checks the file |
| `environment variable "…" required by secret "…" is not set`                    | A line was deleted from `.env`                                     | Add it again (empty is fine) – compare with `.env.example` |
| Jenkins: login fails; `docker compose logs jenkins` shows `Found unresolved variable 'jenkins_admin_password'` | `JENKINS_ADMIN_PASSWORD` is empty | Set it, then `docker compose up -d --force-recreate jenkins` |
| Jenkins: login fails after changing the password in the web UI                  | `casc.yaml` set the `.env` password again at the restart           | Use the password from `.env`; change it there |
| Jenkins doesn't start; log shows `ConfiguratorException` or `Invalid configuration elements` | Mistake in `casc.yaml` (often indentation – use spaces, never tabs) | Fix the line named in the message, `docker compose up -d --build` |
| A setting changed in the Jenkins UI is back to the old value                    | `casc.yaml` is applied at every start                              | Change it in `casc.yaml` |
| New `.env` token has no effect (`401`, `unauthorized`)                         | Compose doesn't recreate a container when only a secret changes    | `docker compose up -d --force-recreate jenkins` |
| `permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock` | `DOCKER_GID` doesn't match the socket's group | Windows: `DOCKER_GID=0`. Ubuntu: `getent group docker \| cut -d: -f3` → `DOCKER_GID`, then `docker compose up -d` |
| `./mvnw: Permission denied`                                                     | `mvnw` isn't executable in Git                                     | `git update-index --chmod=+x mvnw`, commit, push |
| `/usr/bin/env: 'sh\r': No such file or directory`, `bad interpreter`, `$'\r': command not found` | A script has Windows line endings | Keep `.gitattributes`; to repair checked-out files: `git add --renormalize .` and commit |
| `fatal: Couldn't find any revision to build`                                    | `GITHUB_BRANCH` doesn't exist                                      | Set the right branch in `.env` (`master`), `docker compose up -d` |
| `remote: Repository not found` / `Authentication failed`                        | Private repository without (valid) token                           | `GITHUB_USERNAME` / `GITHUB_TOKEN` in `.env`, `--force-recreate jenkins` |
| SonarQube Analysis: `HTTP 401` / `Not authorized`                               | `SONAR_TOKEN` empty, wrong or expired                              | [Step 7.4](#step-7--set-up-sonarqube-one-time) + [Step 8](#step-8--give-jenkins-the-sonarqube-token) |
| SonarQube Analysis: `Connection refused` / `UnknownHostException: sonarqube`    | SonarQube is not running or still starting                         | `docker compose ps`; wait for `(healthy)`; `docker compose logs sonarqube` |
| Creating the webhook: `Invalid URL: loopback, wildcard, link-local, site-local … are not allowed` | Local webhook validation is on                 | Switch off **Enable local webhooks validation** ([Step 7.2](#step-7--set-up-sonarqube-one-time)) |
| Quality Gate waits, then `Timeout has been exceeded`                            | The webhook didn't arrive                                          | Webhook URL exactly `http://jenkins:8080/sonarqube-webhook/`; look at its **recent deliveries** |
| Webhook delivery fails; Jenkins log shows `Invalid payload` / `signature`        | The secret in SonarQube and `SONAR_WEBHOOK_SECRET` differ          | Make them equal, `docker compose up -d --force-recreate jenkins` |
| Links in the build log point to `http://sonarqube:9000/...`                     | SonarQube's **Server base URL** isn't set                          | [Step 7.2](#step-7--set-up-sonarqube-one-time) |
| `Pipeline aborted due to quality gate failure: ERROR`                           | The code failed the quality gate – the gate is working             | Open the SonarQube dashboard, fix the listed conditions, push |
| SonarQube stops; log: `max virtual memory areas vm.max_map_count [65530] is too low` | Kernel limit not set (Ubuntu)                                  | `sudo bash scripts/setup-ubuntu-host.sh` ([AWS-EC2-GUIDE.md](AWS-EC2-GUIDE.md#troubleshooting-aws-specific)) |
| A container stops with exit code **137**, or `OutOfMemoryError`                 | Not enough memory                                                  | Docker Desktop: [Step 1](#step-1--docker-desktop). EC2: a larger instance (8 GiB+) |
| Smoke Test: `Could not resolve host: simple-spring-boot-app`                    | The application container isn't in `cicd-network`                 | Check `DOCKER_NETWORK = 'cicd-network'` in the Jenkinsfile (`startApp` uses it) |
| Image Scan fails; the table lists `HIGH` / `CRITICAL` vulnerabilities           | The image contains a known vulnerability that already has a fix    | In `ubuntu`: update the base image ([Upgrading](#upgrading)). In `app/app.jar`: update the library (usually the Spring Boot version in `pom.xml`). The table names the package and the fixed version |
| Image Scan: `failed to download vulnerability DB` / `context deadline exceeded` | No internet access to `mirror.gcr.io`                              | Check the network; run the build again (the database is cached in `trivy-cache` once downloaded) |
| Candidate Test fails after all retries; the log ends with the candidate's `docker logs` | The new image doesn't start or isn't healthy                 | Read the printed log lines (the running application was not changed); reproduce with `docker run --rm -p 8081:8080 manivannanbgi/simple-spring-boot-app:<tag>` |
| Smoke Test fails, then `ROLLBACK: starting the previous version …`              | The new version failed after the switch                            | The previous version is running again (`ROLLBACK done`). The new version's log is printed just before the rollback |
| `No previous version to roll back to - the failed container was removed`         | The very first deployment failed                                   | Fix the cause (log above that line), push again |
| `WARNING: the previous version … does not answer either`                         | The rollback started, but the old version doesn't answer           | `docker logs simple-spring-boot-app`; usually a shared problem (network, memory) rather than the code |
| `Unable to find image '…' locally` during a rollback                            | The previous image was deleted on the host                         | Nothing to do – Docker downloads it from Docker Hub, where all versions are kept |
| `denied: requested access to the resource is denied` (push)                     | `DOCKER_IMAGE` isn't under your Docker Hub user, or the token is read-only | Fix `DOCKER_IMAGE` in the Jenkinsfile; **Read & Write** token |
| GitHub delivery shows **200** but no build starts                               | The job never ran, or the push was to another branch               | Run the job once by hand ([Step 10](#step-10--run-the-pipeline)); push to `GITHUB_BRANCH` |
| GitHub delivery shows **403**                                                   | The Payload URL is only the ngrok address, without `/github-webhook/` (Jenkins' login page answers) | Payload URL `https://<name>.ngrok-free.app/github-webhook/`, then **Redeliver** |
| GitHub delivery shows **400**                                                   | The webhook's Secret is empty or differs from `GITHUB_WEBHOOK_SECRET` | Copy the value from `.env` into the webhook's **Secret**, then **Redeliver** |
| GitHub delivery fails (`failed to connect`, timeout)                            | PC: ngrok not running. EC2: security group closed, or the address changed | `docker compose --profile tunnel up -d` / check the security group and the Elastic IP |
| ngrok log: the endpoint is already online                                       | Another ngrok (e.g. the old one on Windows) uses your domain       | Stop the other ngrok |
| Jenkins warning "Building on the built-in node can be a security issue"         | Builds run on the Jenkins container itself                         | Expected in this setup – see [Security notes](#security-notes) |
| Jenkins log: `entry for admin … duplicates one seen earlier for admin`          | Harmless message from creating the user through `casc.yaml`        | Nothing to do |
| `docker compose down` prints `Network cicd-network … Resource is still in use` | The deployed application uses the network                          | Expected – the next `up` reuses it |
| Git Bash: `cannot open C:/Program Files/Git/...` when running a command with a `/path` | Git Bash converts paths that start with `/`                   | Use PowerShell, or put `MSYS_NO_PATHCONV=1` in front of the command |

---

## Security notes

- **Secrets** are only in `.env` (not in Git, `chmod 600` on Linux) and in Jenkins' encrypted credential store. Inside
  the Jenkins container they are files in `/run/secrets/`, not environment variables, and builds see them only inside
  `withCredentials`, masked as `****`. `docker logout` after every build removes the Docker Hub login.
- **The Docker socket gives full control over the host.** Jenkins needs it to build and run images, which means that
  whoever can change the `Jenkinsfile` or configure Jenkins can control the Docker host. Keep it that way only for a
  trusted team: protect the `master` branch on GitHub, give Jenkins accounts only to the team, and never open Jenkins to
  the internet without its login. The next step for a larger team is a separate **build agent** (a second machine or
  container that runs the builds), so the Jenkins controller itself never runs build commands.
- **Network:** the database has no published port and sits in an internal network; only Jenkins (8079), SonarQube
  (9000) and the application (8080) are published. On EC2, the security group decides who reaches them.
- **Webhooks:** both webhooks into Jenkins are signed – GitHub → Jenkins (`GITHUB_WEBHOOK_SECRET`) and SonarQube →
  Jenkins (`SONAR_WEBHOOK_SECRET`); Jenkins rejects unsigned or forged requests.
- **HTTPS:** plain HTTP is fine on your PC and through an SSH tunnel. Before Jenkins or SonarQube are used over the
  internet with real accounts, put HTTPS in front of them ([AWS-EC2-GUIDE.md – Future](AWS-EC2-GUIDE.md#future-other-aws-deployment-environments)).
- **Users:** Jenkins, SonarQube and the application all run as non-root users inside their containers.
- **Exact versions** of every image and plugin: a rebuild never changes anything by surprise, and an upgrade is a
  deliberate, reviewable change in Git. The application's base image and the Trivy scanner are pinned by **digest**,
  so even a re-pushed tag can't change them.
- **Vulnerability scan:** every image is scanned by Trivy before it is pushed; fixable HIGH and CRITICAL findings stop
  the build. Trivy gets the image as a file and no access to the Docker socket.
