# SonarQube Guide – simple-spring-boot-app

> **Replaced:** SonarQube (with a PostgreSQL database) and Jenkins now run with Docker Compose – follow
> [cicd/README.md](cicd/README.md). This guide describes the previous setup (`docker run` with the embedded H2
> database, Jenkins as a Windows service).

This guide installs **SonarQube** on your PC and adds it to the Jenkins pipeline. On every build, SonarQube checks the code for bugs, security problems, bad practices ("code smells") and duplicated code, and records how much of it the unit tests cover. If the code fails the **quality gate**, the build stops before anything is built into a Docker image or deployed.

It continues [CICD-GUIDE.md](CICD-GUIDE.md) (Jenkins on Windows + Docker Desktop). Follow the steps in order; each step ends with a way to check that it worked. Tamil version: [SONARQUBE_GUIDE_TAMIL.md](SONARQUBE_GUIDE_TAMIL.md).

> ⚠️ **Do Steps 5–8 in Jenkins before you push the Jenkinsfile with the SonarQube stages.** Otherwise the next build fails at the SonarQube Analysis stage.

---

## Contents

- [How SonarQube fits into the pipeline](#how-sonarqube-fits-into-the-pipeline)
- [Your setup at a glance](#your-setup-at-a-glance)
- [Step 1 – Install SonarQube with Docker](#step-1--install-sonarqube-with-docker)
- [Step 2 – Log in and change the admin password](#step-2--log-in-and-change-the-admin-password)
- [Step 3 – Create a token for Jenkins](#step-3--create-a-token-for-jenkins)
- [Step 4 – Run the first analysis from your PC](#step-4--run-the-first-analysis-from-your-pc)
- [Step 5 – Install the SonarQube Scanner plugin in Jenkins](#step-5--install-the-sonarqube-scanner-plugin-in-jenkins)
- [Step 6 – Store the token in Jenkins](#step-6--store-the-token-in-jenkins)
- [Step 7 – Tell Jenkins where SonarQube is](#step-7--tell-jenkins-where-sonarqube-is)
- [Step 8 – Send the quality gate result back to Jenkins (webhook)](#step-8--send-the-quality-gate-result-back-to-jenkins-webhook)
- [Step 9 – Push and check the pipeline](#step-9--push-and-check-the-pipeline)
- [Step 10 – Try a failing quality gate (optional)](#step-10--try-a-failing-quality-gate-optional)
- [The project files explained](#the-project-files-explained)
- [Everyday use](#everyday-use)
- [Troubleshooting](#troubleshooting)

---

## How SonarQube fits into the pipeline

```text
 Jenkins (http://localhost:8079)                               SonarQube (Docker container, http://localhost:9000)

   Checkout ▶ Build ▶ Unit Tests ▶ Integration Tests
                                         │
                                         ▼
                               SonarQube Analysis ──── code + test results + coverage ────▶ analysis
                                                                                               │
                               Quality Gate ◀──────────── result (webhook) ◀──── quality gate ◀┘
                                    │
                    Passed ─────────┴───────── Failed
                       │                          │
                       ▼                          ▼
   Package JAR ▶ Docker Build ▶ … ▶ Smoke Test   build stops (FAILURE); the running application is not replaced
```

| Stage              | What happens                                                                                   | Command (in the `Jenkinsfile`)                          |
|--------------------|------------------------------------------------------------------------------------------------|---------------------------------------------------------|
| SonarQube Analysis | Sends the code, the test results and the coverage report to SonarQube                          | `withSonarQubeEnv('SonarQube') { mvnw.cmd -B sonar:sonar }` |
| Quality Gate       | Waits (up to 5 minutes) for SonarQube's verdict; stops the build if the quality gate failed    | `waitForQualityGate abortPipeline: true`                |

**Words you will see in SonarQube:**

| Term              | Meaning                                                                                                    |
|-------------------|------------------------------------------------------------------------------------------------------------|
| Quality gate      | Pass/fail rules for each analysis. The built-in gate **Sonar way** checks the **new code**: no new issues, all new security hotspots reviewed, at least 80% coverage and at most 3% duplicated lines |
| Issue             | A problem found in the code. Grouped by **Security**, **Reliability** (bugs) and **Maintainability** (code smells) |
| Security hotspot  | Code that touches security (for example, cookies or passwords) and must be reviewed by a person            |
| Coverage          | The share of code lines the unit tests run (measured by **JaCoCo**)                                        |
| New code          | Code changed since the previous version; quality gates focus on it so that old problems don't block every build |

---

## Your setup at a glance

| Item              | Value                                                                                       |
|-------------------|---------------------------------------------------------------------------------------------|
| SonarQube         | Community Build **26.10.0.133078** – Docker container `sonarqube` – http://localhost:9000  |
| SonarQube data    | Docker volumes `sonarqube_data`, `sonarqube_extensions`, `sonarqube_logs`                  |
| Database          | The embedded H2 database (fine for one PC, but it can't be upgraded – see [Everyday use](#everyday-use)) |
| Jenkins           | http://localhost:8079 – from inside the SonarQube container: http://host.docker.internal:8079 |
| Maven scanner     | `sonar-maven-plugin` 5.8.0.7211 (in `pom.xml`)                                              |
| Coverage          | JaCoCo 0.8.15 → `target/site/jacoco/jacoco.xml` after `mvnw test`                          |
| Project key       | `simple-spring-boot-app` → http://localhost:9000/dashboard?id=simple-spring-boot-app       |

> Ports: Jenkins **8079**, application **8080**, SonarQube **9000**.

---

## Step 1 – Install SonarQube with Docker

> On this PC this step is **already done** (container `sonarqube` is running). Read it anyway – you need it on another PC or after a reinstall.

**Before you start:**

- Docker Desktop is running.
- Docker has at least **4 GB** of memory (SonarQube uses about 2 GB). Check: `docker info --format "{{.MemTotal}}"` (bytes).
- Port 9000 is free: `netstat -ano | findstr :9000` shows nothing.

**Install** – in PowerShell:

```powershell
docker volume create sonarqube_data
docker volume create sonarqube_extensions
docker volume create sonarqube_logs

docker run -d --name sonarqube -p 9000:9000 --restart unless-stopped `
  -v sonarqube_data:/opt/sonarqube/data `
  -v sonarqube_extensions:/opt/sonarqube/extensions `
  -v sonarqube_logs:/opt/sonarqube/logs `
  sonarqube:26.10.0.133078-community
```

| Part                                 | Meaning                                                                                    |
|--------------------------------------|--------------------------------------------------------------------------------------------|
| `docker volume create …`             | Storage outside the container, so the data survives when the container is removed           |
| `-d`                                 | Run in the background                                                                      |
| `-p 9000:9000`                       | Port 9000 on your PC → port 9000 in the container                                          |
| `--restart unless-stopped`           | Starts again automatically whenever Docker Desktop starts, until you stop it yourself      |
| `-v sonarqube_data:/opt/sonarqube/data` | Analyses, settings, users and tokens                                                    |
| `sonarqube:26.10.0.133078-community` | An exact version, so a reinstall gives the same SonarQube (the tag `community` would always pull the newest) |

The first run downloads the image (about 1 GB). SonarQube then needs 1–2 minutes to start. Check its status:

```powershell
curl.exe http://localhost:9000/api/system/status
```

`"status":"STARTING"` → wait and try again. Ready:

```json
{"id":"…","version":"26.10.0.133078","status":"UP"}
```

**Check:** `docker ps --filter name=sonarqube` shows the container as **Up** with `0.0.0.0:9000->9000/tcp`.

---

## Step 2 – Log in and change the admin password

1. Open http://localhost:9000.
2. Log in with **Login** `admin`, **Password** `admin`.
3. SonarQube asks you to change the password: enter `admin` as the old password and a strong new password twice → **Update**. Keep it in your password manager.

You don't need to create the project by hand – the first analysis (Step 4) creates it.

**Check:** you can log out and log in again with the new password.

---

## Step 3 – Create a token for Jenkins

Jenkins and your PC log in to SonarQube with a **token** instead of the password.

1. Click your avatar (top right) → **My Account** → **Security** tab.
2. Under **Generate Tokens**:
   - **Name:** `jenkins`
   - **Type:** **User Token** (works for the analysis and for reading the quality gate result)
   - **Expires in:** for example **90 days** – note the date; renew the token before it expires
3. Click **Generate** and copy the token (it starts with `squ_`). It is shown **only once**.

**Check:** the token `jenkins` is listed under **Security**, with **Last use: Never**.

---

## Step 4 – Run the first analysis from your PC

This proves SonarQube works before Jenkins is involved, and creates the project. In PowerShell, in the project folder:

```powershell
$env:SONAR_HOST_URL = "http://localhost:9000"
$env:SONAR_TOKEN    = Read-Host "SonarQube token"     # paste the token from Step 3, then Enter
.\mvnw.cmd clean verify sonar:sonar
```

- `Read-Host` keeps the token out of the PowerShell history. Both variables last only until you close this window.
- `verify` runs the unit tests (with coverage) and the integration tests; `sonar:sonar` then sends everything to SonarQube.
- **Without `SONAR_HOST_URL`** the scanner tries SonarQube **Cloud** on the internet and fails with `You must define the following mandatory properties: sonar.organization`.

**Expected output** (at the end):

```text
[INFO] ANALYSIS SUCCESSFUL, you can find the results at: http://localhost:9000/dashboard?id=simple-spring-boot-app
[INFO] BUILD SUCCESS
```

**Check:** open http://localhost:9000/dashboard?id=simple-spring-boot-app:

- **Quality Gate: Passed** (the first analysis has no "new code" yet, so it passes).
- **Coverage** about **67%**: every line of `HelloController` is covered; only `DemoApplication.main` is not (tests don't start the application through `main`).
- The **Issues** tab may list a few findings – click one to see why it matters and how to fix it.

---

## Step 5 – Install the SonarQube Scanner plugin in Jenkins

1. Jenkins (http://localhost:8079) → **Manage Jenkins** → **Plugins** → **Available plugins**.
2. Search **SonarQube Scanner** → tick it → **Install**.
3. If Jenkins asks, tick **Restart Jenkins when installation is complete and no jobs are running**.

The plugin adds `withSonarQubeEnv` and `waitForQualityGate` to the Jenkinsfile, and the address `/sonarqube-webhook/` that SonarQube calls in Step 8.

**Check:** **Manage Jenkins** → **Plugins** → **Installed plugins** → **SonarQube Scanner** is listed and enabled.

---

## Step 6 – Store the token in Jenkins

**Manage Jenkins** → **Credentials** → under *Stores scoped to Jenkins*, click **System** → **Global credentials (unrestricted)** → **Add Credentials**:

| Field       | Value                              |
|-------------|------------------------------------|
| Kind        | **Secret text**                    |
| Scope       | Global                             |
| Secret      | the SonarQube token from Step 3    |
| ID          | `sonarqube-token`                  |
| Description | SonarQube token for Jenkins        |

**Check:** `sonarqube-token` appears in the list next to `dockerhub-credentials`.

---

## Step 7 – Tell Jenkins where SonarQube is

1. **Manage Jenkins** → **System** → scroll to **SonarQube servers**.
2. Tick **Environment variables** ("Enable injection of SonarQube server configuration as build environment variables").
3. Click **Add SonarQube** and fill in:

   | Field                        | Value                    |
   |------------------------------|--------------------------|
   | Name                         | `SonarQube`              |
   | Server URL                   | `http://localhost:9000`  |
   | Server authentication token  | `sonarqube-token`        |

4. Click **Save**.

The **Name must be exactly `SonarQube`** – the Jenkinsfile looks it up with `withSonarQubeEnv('SonarQube')`. Jenkins (running on your PC) reaches SonarQube through the published port, so `localhost` is right here.

**Check:** open **Manage Jenkins** → **System** again – the server `SonarQube` is still there with the token selected.

---

## Step 8 – Send the quality gate result back to Jenkins (webhook)

After an analysis, SonarQube needs a few seconds to process it. The **Quality Gate** stage waits until SonarQube calls Jenkins back with the result. That call is a **webhook**.

1. SonarQube → **Administration** → **Configuration** → **Webhooks** → **Create**.
2. Fill in:
   - **Name:** `Jenkins`
   - **URL:** `http://host.docker.internal:8079/sonarqube-webhook/` – the final **`/`** is required
   - **Secret:** leave empty
3. Click **Create**.

> Why not `localhost`? SonarQube runs **inside a container**, where `localhost` means the container itself. `host.docker.internal` is Docker Desktop's name for your PC.

**Check:** after the first Jenkins build in Step 9, the webhook's **Last delivery** shows a green tick. Click **⋮** → **Show recent deliveries** to see the response code **200**.

---

## Step 9 – Push and check the pipeline

The project already contains everything SonarQube needs (see [The project files explained](#the-project-files-explained)). Commit and push the changes; the webhook from [CICD-GUIDE.md Step 10](CICD-GUIDE.md#step-10--build-automatically-on-every-push-webhook) starts the build (or click **Build Now**).

**Check:** the build turns green and shows **13 stages**:

| Stage              | Success looks like this in the log                                                                 |
|--------------------|----------------------------------------------------------------------------------------------------|
| SonarQube Analysis | `ANALYSIS SUCCESSFUL, you can find the results at: http://localhost:9000/dashboard?id=simple-spring-boot-app` |
| Quality Gate       | `SonarQube task '…' status is 'SUCCESS'` and `SonarQube task '…' completed. Quality gate is 'OK'`  |

Also check:

- The build page shows a **SonarQube Quality Gate** badge with a link to the dashboard.
- SonarQube → project → **Activity** lists the new analysis.
- The webhook's recent deliveries show **200** (Step 8).

---

## Step 10 – Try a failing quality gate (optional)

See the pipeline stop on bad quality, without changing any code: use a stricter gate for a moment.

1. SonarQube → **Quality Gates** → **Create** → **Name:** `Strict demo` → **Save**.
2. **Add Condition** → **On Overall Code** → **Coverage** → **is less than** `90` → **Add Condition**. (The project has about 67%.)
3. Open the project → **Project Settings** → **Quality Gate** → **Always use a specific quality gate** → `Strict demo` → **Save**.
4. Jenkins → job → **Build Now**.

**Check:** the **Quality Gate** stage is red and the log ends with:

```text
SonarQube task '…' completed. Quality gate is 'ERROR'
ERROR: Pipeline aborted due to quality gate failure: ERROR
```

Package JAR, Docker and Deploy are skipped – the container from the previous build keeps running. The SonarQube dashboard shows **Failed** and the condition that failed.

**Undo:** project → **Project Settings** → **Quality Gate** → **Always use the instance default** → **Save**, then **Build Now** again – green.

---

## The project files explained

**`pom.xml`** – three additions:

```xml
<!-- Project key in SonarQube -->
<sonar.projectKey>simple-spring-boot-app</sonar.projectKey>
```

- **`jacoco-maven-plugin`** – `prepare-agent` attaches JaCoCo to the unit tests; `report` (bound to the `test` phase) writes `target/site/jacoco/jacoco.xml` right after `mvnw test`. SonarQube reads this file automatically. Open `target/site/jacoco/index.html` in a browser to see the coverage yourself.
- **`sonar-maven-plugin`** in `pluginManagement` – only fixes the scanner version. It runs only when you call `sonar:sonar`.

**`Jenkinsfile`** – two new stages after Integration Tests:

```groovy
stage('SonarQube Analysis') {
    steps {
        withSonarQubeEnv('SonarQube') {
            bat '.\\mvnw.cmd -B sonar:sonar'
        }
    }
}

stage('Quality Gate') {
    steps {
        timeout(time: 5, unit: 'MINUTES') {
            waitForQualityGate abortPipeline: true
        }
    }
}
```

**Key points:**

- **`withSonarQubeEnv('SonarQube')`** – passes the server URL and token from Step 7 to the scanner. The token never appears in the Jenkinsfile, in Git, or in the log.
- **`sonar:sonar`** reuses what the earlier stages left in `target`: the compiled classes, the test reports and `jacoco.xml`. Nothing is compiled or tested again.
- **Coverage comes from the unit tests.** The Integration Tests stage runs the failsafe goals directly (see [CICD-GUIDE.md](CICD-GUIDE.md#jenkinsfile-complete)), so JaCoCo isn't attached there. The unit tests already cover the whole controller.
- **`waitForQualityGate abortPipeline: true`** – a failed gate marks the build **FAILURE** and skips the remaining stages. `timeout` stops the wait after 5 minutes if the webhook never arrives.

---

## Everyday use

- **SonarQube must be running for every Jenkins build.** It starts with Docker Desktop. Check with `docker ps --filter name=sonarqube`; start it with `docker start sonarqube` and wait for `UP` (Step 1).
- **Stop it** when you don't need it (frees about 2 GB of memory): `docker stop sonarqube`. The data stays in the volumes.
- **Its log:** `docker logs sonarqube` (follow live: `docker logs -f sonarqube`).
- **Don't delete the data by accident.** These commands delete all analyses and settings (password, token, webhook):
  - `docker volume rm sonarqube_data …`
  - `docker system prune --volumes` while the `sonarqube` container is **stopped or removed**

  `docker image prune -a` (from the CI/CD housekeeping) is safe: it keeps images that a container uses.
- **Token renewal:** before the token expires, create a new one (Step 3) and update `sonarqube-token` in Jenkins (**Credentials** → the credential → **Update**).
- **Newer SonarQube version:** the embedded H2 database **cannot be upgraded**. To move to a newer version, start fresh: `docker rm -f sonarqube`, `docker volume rm sonarqube_data sonarqube_extensions sonarqube_logs`, then Step 1 with the new tag and Steps 2, 3, 6 (update the secret) and 8 again. The analysis history is lost. To keep history across upgrades, SonarQube needs a PostgreSQL database – see the official docs: https://docs.sonarsource.com/sonarqube-community-build/

---

## Troubleshooting

Where to look: the **Console Output** of the red stage in Jenkins, `docker logs sonarqube`, and in SonarQube **Administration** → **Configuration** → **Webhooks** → **Show recent deliveries**.

| Error message                                                                                     | Cause                                                                          | Solution                                                                                   |
|---------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------|
| `No such DSL method 'withSonarQubeEnv'` / `'waitForQualityGate'`                                   | The SonarQube Scanner plugin is missing                                        | [Step 5](#step-5--install-the-sonarqube-scanner-plugin-in-jenkins)                         |
| `SonarQube installation defined in this job (SonarQube) does not match any configured installation` | No server named exactly `SonarQube` in Jenkins                                | [Step 7](#step-7--tell-jenkins-where-sonarqube-is) – check the name (capital S and Q)      |
| `Failed to query server version: … failed with HTTP 401 Unauthorized`                             | Token missing, mistyped, expired or revoked                                    | New token ([Step 3](#step-3--create-a-token-for-jenkins)); update `sonarqube-token` ([Step 6](#step-6--store-the-token-in-jenkins)); on your PC set `SONAR_TOKEN` ([Step 4](#step-4--run-the-first-analysis-from-your-pc)) |
| `Communicating with SonarQube Cloud` … `You must define the following mandatory properties: sonar.organization` | The scanner got no server URL, so it tried SonarQube Cloud           | On your PC: set `SONAR_HOST_URL` (Step 4). In Jenkins: the command must be inside `withSonarQubeEnv`, and the server URL must be set (Step 7) |
| `Failed to query server version` … `Connection refused` / `ConnectException`                     | SonarQube isn't running (or is still starting)                                 | `docker start sonarqube`; wait until `/api/system/status` shows `UP`                       |
| Quality Gate stage stays at `status is 'PENDING'` / `'IN_PROGRESS'`, then `Timeout has been exceeded` | SonarQube never called Jenkins back                                        | Check the webhook URL ([Step 8](#step-8--send-the-quality-gate-result-back-to-jenkins-webhook)): `host.docker.internal`, port `8079`, final `/` |
| Webhook recent deliveries show **403** or **404**                                                 | The plugin isn't installed yet, or Jenkins hasn't restarted after installing it | [Step 5](#step-5--install-the-sonarqube-scanner-plugin-in-jenkins); restart Jenkins (http://localhost:8079/safeRestart) |
| Webhook recent deliveries show `Server Unreachable` / `Failed to connect`                         | Jenkins isn't running, or it uses another port                                 | Open http://localhost:8079; fix the port in the webhook URL                                |
| `ERROR: Pipeline aborted due to quality gate failure: ERROR`                                       | The code failed the quality gate – this is the gate working                    | Open the project dashboard → it lists the failed conditions → fix the code (or tests) and push again |
| Coverage shows **0%** or "—"                                                                       | No `target/site/jacoco/jacoco.xml` when `sonar:sonar` ran                      | Run the analysis after `mvnw test` (the pipeline does); locally use `.\mvnw.cmd clean verify sonar:sonar` |
| Container stops; `docker logs sonarqube` shows `max virtual memory areas vm.max_map_count [65530] is too low` | SonarQube's search engine needs a higher Linux limit (this PC already has 262144) | Create `%USERPROFILE%\.wslconfig` with the two lines `[wsl2]` and `kernelCommandLine = "sysctl.vm.max_map_count=262144"`, run `wsl --shutdown`, restart Docker Desktop |
| Container stops with exit code **137**, or the log shows `OutOfMemoryError`                       | Docker has too little memory                                                   | Give Docker at least 4 GB; stop other containers                                           |
| Port 9000 already in use when starting the container                                              | Another program uses port 9000                                                 | Use another port: `-p 9001:9000`, and use `http://localhost:9001` in Step 7                |
