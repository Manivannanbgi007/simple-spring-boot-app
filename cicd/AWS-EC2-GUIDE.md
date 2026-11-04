# DevOps on AWS EC2 – Jenkins, SonarQube and PostgreSQL with one Docker Compose command

This guide sets up the complete CI/CD environment of `simple-spring-boot-app` on an **Ubuntu EC2 instance** in AWS –
the same environment you run on Windows with Docker Desktop. Everything comes from this GitHub repository: on a new
instance you **clone the repository, fill in a few settings and run one command**:

```bash
docker compose up -d --build
```

It is written for junior developers: every step says *what* to do, *why*, and how to *check* that it worked.
Time needed the first time: about 1 hour (most of it waiting for downloads).

> Reference for every file, setting, backup, upgrade and error message: [cicd/README.md](README.md).
> This guide covers the AWS part and the order of the steps.

---

## Contents

- [1. What you will build](#1-what-you-will-build)
- [2. How your requirements are met](#2-how-your-requirements-are-met)
- [3. The repository – folder structure](#3-the-repository--folder-structure)
- [4. Before you start](#4-before-you-start)
- **Part A – AWS**
  - [Step 1 – Create a key pair](#step-1--create-a-key-pair)
  - [Step 2 – Create the security group (firewall)](#step-2--create-the-security-group-firewall)
  - [Step 3 – Launch the instance (with automatic setup)](#step-3--launch-the-instance-with-automatic-setup)
  - [Step 4 – Give the instance a fixed address (Elastic IP)](#step-4--give-the-instance-a-fixed-address-elastic-ip)
- **Part B – The server**
  - [Step 5 – Connect with SSH and check the automatic setup](#step-5--connect-with-ssh-and-check-the-automatic-setup)
  - [Step 6 – Complete the `.env` file](#step-6--complete-the-env-file)
  - [Step 7 – Start everything with one command](#step-7--start-everything-with-one-command)
  - [Step 8 – Open Jenkins and SonarQube safely (SSH tunnel)](#step-8--open-jenkins-and-sonarqube-safely-ssh-tunnel)
  - [Step 9 – SonarQube: one-time setup](#step-9--sonarqube-one-time-setup)
  - [Step 10 – Jenkins: check the configuration and run the first build](#step-10--jenkins-check-the-configuration-and-run-the-first-build)
  - [Step 11 – Build on every push (GitHub webhook)](#step-11--build-on-every-push-github-webhook)
  - [Step 12 – Open the application](#step-12--open-the-application)
- [Everyday operations](#everyday-operations)
- [Backups and moving to a new instance](#backups-and-moving-to-a-new-instance)
- [Security checklist](#security-checklist)
- [Troubleshooting (AWS-specific)](#troubleshooting-aws-specific)
- [Future: other AWS deployment environments](#future-other-aws-deployment-environments)
- [Appendix A – Create the AWS resources with the AWS CLI](#appendix-a--create-the-aws-resources-with-the-aws-cli)
- [Appendix B – Without user data (manual server setup)](#appendix-b--without-user-data-manual-server-setup)

---

## 1. What you will build

```text
 Your PC                                  AWS – one Ubuntu EC2 instance (Docker Engine + Docker Compose)
 ┌──────────────┐  SSH (port 22)          ┌────────────────────────────────────────────────────────────────┐
 │ browser      │ ─ tunnel for the UIs ─▶ │  docker compose up -d --build  (in ~/simple-spring-boot-app/cicd)
 │ ssh / scp    │                         │                                                                │
 └──────────────┘                         │  ┌───────────┐ analysis  ┌───────────┐  SQL  ┌──────────────┐   │
                                          │  │  jenkins  │ ────────▶ │ sonarqube │ ────▶ │ sonarqube-db │   │
 GitHub ── webhook (port 8079) ─────────▶ │  │           │ ◀──────── │           │       │ (PostgreSQL) │   │
   ▲  Jenkins clones the code             │  └─────┬─────┘ quality   └───────────┘       └──────────────┘   │
   └──────────────────────────────────────│        │ docker build / scan / push / run (pipeline)           │
                                          │        ▼                                                       │
 Users ── http://<address>:8080 ───────▶  │  ┌────────────────────────┐                                    │
                                          │  │ simple-spring-boot-app │  (deployed by the pipeline)        │
                                          │  └────────────────────────┘                                    │
                                          └────────────────────────────────────────────────────────────────┘
                                                   │ docker push / pull
                                                   ▼
                                               Docker Hub
```

- **Jenkins** runs the pipeline (`Jenkinsfile`, 13 stages: build, tests, SonarQube, quality gate, image, vulnerability
  scan, push, test of the new image, deploy, smoke test – with automatic rollback).
- **SonarQube** checks the code quality; **PostgreSQL** stores SonarQube's data.
- The **application** is started by the pipeline on the same instance, on port 8080.
- All of them are **Docker containers**. The instance itself needs only Docker – no Jenkins, SonarQube, PostgreSQL,
  Maven or Java installation.

---

## 2. How your requirements are met

| Your requirement | How this setup does it |
|------------------|------------------------|
| 1. Launch and configure an Ubuntu EC2 instance | [Steps 1–4](#part-a--aws) in the AWS console (or [Appendix A](#appendix-a--create-the-aws-resources-with-the-aws-cli) with the AWS CLI). The **user data** script [`aws/user-data.sh`](aws/user-data.sh) configures the server automatically at its first start |
| 2. Install Java 21, Docker Engine, Docker Compose | [`scripts/setup-ubuntu-host.sh`](scripts/setup-ubuntu-host.sh) installs Docker Engine and the Compose plugin from Docker's repository. **Java 21 is inside the containers** (the Jenkins image `jenkins/jenkins:…-jdk21` builds and tests with it; the application image has its own Java 21 runtime), so the server doesn't need it. Want it anyway – for example to run `./mvnw` on the server? Add `--with-java` ([Appendix B](#appendix-b--without-user-data-manual-server-setup)) |
| 3. Configure and run Docker Compose | [`docker-compose.yml`](docker-compose.yml) describes all services; [`.env`](.env.example) holds this machine's settings. One command starts everything ([Step 7](#step-7--start-everything-with-one-command)) |
| 4. Jenkins, SonarQube, PostgreSQL and other tools as containers | Services `jenkins`, `sonarqube`, `sonarqube-db`, plus `backup` (on demand) and `ngrok` (only on a PC). The pipeline adds Trivy (scanner) and the application containers |
| 5. Preconfigured plugins, GitHub, SonarQube, credentials | [`jenkins/plugins.txt`](jenkins/plugins.txt) (exact plugin versions, built into the image) and [`jenkins/casc.yaml`](jenkins/casc.yaml) (*Jenkins Configuration as Code*: admin user, credentials, SonarQube server, GitHub webhook secret, the pipeline job) |
| 6. Automated – no manual installation or configuration | Server: user data + two scripts. Jenkins: fully automatic from the files. **One-time manual steps remain** – only where a secret must be created by you: the Docker Hub token, SonarQube's first password and its token, and the webhooks in GitHub and SonarQube ([why](#what-stays-manual-and-why)) |
| Everything in GitHub | All files are in the repository **except `.env`** (secrets) and `backups/`, which `.gitignore` keeps out |
| Reusable, secure, ready for other AWS environments | Same files on Windows and EC2; all machine-specific values in `.env`; exact versions everywhere; secrets never in Git; see [Security checklist](#security-checklist) and [Future](#future-other-aws-deployment-environments) |

### What stays manual, and why

| One-time step | Why it can't be in Git |
|---------------|------------------------|
| Docker Hub access token → `.env` | It's a password for your Docker Hub account – it must never be in Git or in AWS user data |
| SonarQube admin password, token, webhook | SonarQube creates the token itself after its first start; the token is a secret |
| GitHub webhook | It's configured in GitHub's website and needs the server's address |

Everything else – the Jenkins user, plugins, credentials store, SonarQube connection, job, passwords for the database
and the webhook secrets – is created automatically.

---

## 3. The repository – folder structure

```text
simple-spring-boot-app/                    ← the GitHub repository
├── Jenkinsfile                            the pipeline (13 stages, with scan and rollback)
├── Jenkinsfile.backup                     the previous, simpler pipeline
├── Dockerfile                             the application's image (Java 21, pinned by digest)
├── pom.xml, mvnw, src/                    the application and its tests
├── .gitattributes                         keeps Linux line endings for scripts (needed in Linux containers)
└── cicd/                                  ← the whole DevOps environment
    ├── AWS-EC2-GUIDE.md                   this guide
    ├── README.md                          reference: every file and setting, backup, upgrade, troubleshooting
    ├── docker-compose.yml                 Jenkins + SonarQube + PostgreSQL (+ backup, ngrok)
    ├── .env.example                       template with every setting – in Git, contains no secrets
    ├── .env                               this machine's settings and secrets – created on the server, never in Git
    ├── .gitignore                         keeps .env and backups/ out of Git
    ├── jenkins/
    │   ├── Dockerfile                     Jenkins LTS + Java 21 + Docker CLI + plugins + casc.yaml
    │   ├── plugins.txt                    the Jenkins plugins, with exact versions
    │   └── casc.yaml                      Jenkins configuration as code (users, credentials, SonarQube, job)
    ├── scripts/
    │   ├── setup-ubuntu-host.sh           prepares Ubuntu: Docker, Compose, kernel settings, swap, log rotation
    │   └── create-env.sh                  creates .env with new random passwords and secrets
    ├── aws/
    │   └── user-data.sh                   EC2 user data: clones the repo and runs both scripts at the first boot
    ├── backup/
    │   ├── backup.sh, restore.sh          backup and restore of Jenkins data and the SonarQube database
    └── backups/                           created by the first backup – never in Git
```

**Where each kind of setting lives:**

| Setting | File | Changed by |
|---------|------|-----------|
| Which containers, ports, volumes, networks | `docker-compose.yml` | commit + `docker compose up -d` |
| Passwords, tokens, addresses of *this* machine | `.env` (only on the machine) | edit + `docker compose up -d --force-recreate jenkins` |
| Jenkins version, Docker CLI, plugins | `jenkins/Dockerfile`, `jenkins/plugins.txt` | commit + `docker compose up -d --build` |
| Jenkins settings, credentials, job | `jenkins/casc.yaml` | commit + `docker compose up -d --build` |
| Pipeline stages | `Jenkinsfile` | commit + push – the next build uses it |

---

## 4. Before you start

**Accounts and tools**

| What | Notes |
|------|-------|
| AWS account | Sign in as an **IAM user** (or IAM Identity Center user) with EC2 permissions – not as the root user. Create an **AWS Budget** with an e-mail alert (Billing → Budgets) so a forgotten instance can't surprise you |
| AWS region | One close to you, for example **Asia Pacific (Mumbai) ap-south-1**. Every step happens in the same region (top right of the console) |
| Docker Hub access token | Docker Hub → Account settings → Personal access tokens → **Read & Write**. Create a **new** token for the server, so you can revoke it alone |
| SSH client | Windows 10/11 include `ssh` and `scp` (PowerShell) |

**Costs** (check the [AWS Pricing Calculator](https://calculator.aws/) for your region): the instance is billed per
second while it runs; the disk and the Elastic IP are billed even while the instance is stopped (AWS charges for every
public IPv4 address). Stop the instance when you don't need it – see [Everyday operations](#everyday-operations).

**The repository must contain the new files.** The instance clones the repository from GitHub, so commit and push
first (on your PC, in the project folder):

```powershell
git add Jenkinsfile Jenkinsfile.backup Dockerfile README.md cicd/
git status                       # .env must NOT be listed (cicd/.gitignore excludes it)
git commit -m "Add AWS EC2 setup: user data, host setup and .env scripts"
git push
```

**Check:** on GitHub you see `cicd/scripts/`, `cicd/aws/` and `cicd/AWS-EC2-GUIDE.md` – and no `cicd/.env`.

> The repository is public, so the instance can clone it without a password. For a private repository, use
> [Appendix B](#appendix-b--without-user-data-manual-server-setup) and clone with a GitHub token.

---

## Part A – AWS

### Step 1 – Create a key pair

The key pair is your "key" to log in to the server with SSH. AWS keeps the public half; you download the private half.

1. AWS console → **EC2** → left menu **Network & Security** → **Key Pairs** → **Create key pair**.
2. **Name:** `devops-key` – **Key pair type:** **ED25519** – **Private key file format:** **.pem** → **Create key pair**.
3. The browser downloads `devops-key.pem`. Move it to a safe folder, for example `C:\Users\<you>\.ssh\devops-key.pem`.
   AWS can't give it to you again.
4. Windows' SSH refuses a key file that other users may read. In **PowerShell**, allow only yourself:

   ```powershell
   $key = "$env:USERPROFILE\.ssh\devops-key.pem"
   icacls $key /inheritance:r /grant:r "$($env:USERNAME):(R)"
   ```

**Check:** `icacls $key` lists only your user, with `(R)`.

### Step 2 – Create the security group (firewall)

A security group decides **who may connect to which port** of the instance. Everything not listed is blocked.

1. **EC2** → **Network & Security** → **Security Groups** → **Create security group**.
2. **Name:** `devops-sg` – **Description:** `Jenkins, SonarQube and app server` – **VPC:** the default VPC.
3. **Inbound rules** → **Add rule** for each line:

   | Type | Port | Source | Why |
   |------|------|--------|-----|
   | SSH | 22 | **My IP** | You log in, and reach the Jenkins/SonarQube web pages through SSH ([Step 8](#step-8--open-jenkins-and-sonarqube-safely-ssh-tunnel)) |
   | Custom TCP | 8079 | `192.30.252.0/22` | GitHub's webhook servers ([Step 11](#step-11--build-on-every-push-github-webhook)) |
   | Custom TCP | 8079 | `185.199.108.0/22` | – " – |
   | Custom TCP | 8079 | `140.82.112.0/20` | – " – |
   | Custom TCP | 8079 | `143.55.64.0/20` | – " – |
   | Custom TCP | 8079 | `9.234.106.48/28` | – " – |
   | Custom TCP | 8079 | `9.234.98.160/28` | – " – |
   | Custom TCP | 8079 | `9.234.98.176/28` | – " – |
   | Custom TCP | 8080 | **Anywhere-IPv4** (`0.0.0.0/0`) – or **My IP** while testing | The deployed application |

4. **Outbound rules:** leave the default (all traffic) – the server downloads images, plugins and code.
5. **Create security group**.

> **Ports 9000 (SonarQube) and 8079 for yourself are deliberately not open.** You reach both web pages through the
> encrypted SSH connection instead, so your passwords never travel over the internet unencrypted.
>
> GitHub publishes its webhook addresses under `hooks` at https://api.github.com/meta (the list above is from November
> 2026). If webhook deliveries start failing one day, compare the list and add new ranges.
>
> **My IP** is your current internet address. At home it can change – then SSH stops working until you edit the
> rule ([Troubleshooting](#troubleshooting-aws-specific)).

**Check:** the group `devops-sg` shows 9 inbound rules.

### Step 3 – Launch the instance (with automatic setup)

**EC2** → **Instances** → **Launch instances**, then fill in:

| Section | Setting | Value | Why |
|---------|---------|-------|-----|
| Name and tags | Name | `devops-server` | |
| Application and OS Images | AMI | **Ubuntu** → **Ubuntu Server 26.04 LTS** (24.04 LTS works too) – Architecture **64-bit (x86)** | Long-term support; the scripts are tested with both. x86 matches your PC, so the images built here also run there |
| Instance type | | **t3.large** (2 vCPU, 8 GiB) at least; **t3.xlarge** (16 GiB) for a team or faster builds | SonarQube alone uses 2–3 GiB, a build another 2–3 GiB. `t3.medium` (4 GiB) is too small |
| Key pair (login) | | `devops-key` (Step 1) | |
| Network settings → **Edit** | Auto-assign public IP | **Enable** | Needed until the Elastic IP is attached |
| | Firewall | **Select existing security group** → `devops-sg` (Step 2) | |
| Configure storage | | **40 GiB**, **gp3** – **Advanced** → **Encrypted: Yes** | Images, Maven cache, build history, Trivy's database. Encryption protects the data at rest |
| Advanced details | Metadata version | **V2 only (token required)** | The more secure instance-metadata version (IMDSv2) |
| | **User data** | the **complete content** of [`cicd/aws/user-data.sh`](aws/user-data.sh) – open it on GitHub → **Raw** → copy → paste | Runs once at the first start: installs Docker, clones the repository, creates `.env` |

Click **Launch instance**.

**What the user data does** (you can watch it in Step 5):

1. installs Git and clones the repository into `/home/ubuntu/simple-spring-boot-app`,
2. runs `scripts/setup-ubuntu-host.sh` – Docker Engine, the Compose plugin, `vm.max_map_count` for SonarQube,
   log rotation for all containers, a 4 GiB swap file, and lets the user `ubuntu` run `docker`,
3. runs `scripts/create-env.sh` – creates `cicd/.env` with **new random** passwords and secrets for this machine
   (readable only by `ubuntu`), the Docker socket's group number (`DOCKER_GID`) and the Jenkins address for the SSH
   tunnel (`JENKINS_PUBLIC_URL`).

It does **not** start the containers yet – you add the Docker Hub token first (Step 6).

> **Never put tokens or passwords into user data.** Anyone who may view the instance's settings in AWS can read it.
> That is why the scripts generate the secrets on the server, and you add the Docker Hub token yourself.

**Check:** **Instances** → `devops-server` → **Instance state: Running**, **Status checks: 3/3 checks passed**
(after 1–2 minutes).

### Step 4 – Give the instance a fixed address (Elastic IP)

A normal public address changes every time the instance is stopped and started. The GitHub webhook and your SSH
command need an address that stays the same.

1. **EC2** → **Network & Security** → **Elastic IPs** → **Allocate Elastic IP address** → **Allocate**.
2. Select the new address → **Actions** → **Associate Elastic IP address** → **Instance:** `devops-server` →
   **Associate**.
3. Note the address, for example `13.234.56.78`. This guide calls it `<elastic-ip>`.

**Check:** the instance's **Public IPv4 address** is now the Elastic IP.

---

## Part B – The server

### Step 5 – Connect with SSH and check the automatic setup

In PowerShell on your PC:

```powershell
ssh -i "$env:USERPROFILE\.ssh\devops-key.pem" ubuntu@<elastic-ip>
```

The first time, SSH asks *"Are you sure you want to continue connecting?"* → type `yes`. You are now on the server:
the prompt looks like `ubuntu@ip-172-31-…:~$`. Everything from here runs **on the server** unless it says "on your PC".

Watch the automatic setup (it takes 3–5 minutes after the first boot):

```bash
tail -f /var/log/cloud-init-output.log        # Ctrl + C to stop watching
```

It is finished when the file `/var/log/devops-setup.done` exists:

```bash
cat /var/log/devops-setup.done                # "DevOps host setup finished at …"
```

**Log out and in again once** (`exit`, then the `ssh` command again) – the new `docker` group membership only applies
to new logins.

**Check:**

```bash
docker version                                 # shows a Client and a Server section
docker compose version                         # Docker Compose version v2.30 or newer
docker run --rm hello-world                    # "Hello from Docker!"
sysctl vm.max_map_count                        # vm.max_map_count = 524288
swapon --show                                  # /swapfile ... 4G
ls -l ~/simple-spring-boot-app/cicd/.env       # -rw------- 1 ubuntu ubuntu ... .env
```

> If `/var/log/devops-setup.done` doesn't appear, read the end of `/var/log/cloud-init-output.log` – the last lines
> show the error. You can always run the two scripts by hand: [Appendix B](#appendix-b--without-user-data-manual-server-setup).

### Step 6 – Complete the `.env` file

```bash
cd ~/simple-spring-boot-app/cicd
nano .env
```

(In `nano`: move with the arrow keys, **Ctrl + O** then **Enter** saves, **Ctrl + X** exits.)

Already filled in for you – **don't change them**:

| Variable | Value |
|----------|-------|
| `JENKINS_ADMIN_PASSWORD` | random, 32 characters – your Jenkins login password |
| `SONARQUBE_DB_PASSWORD` | random – used only between SonarQube and PostgreSQL. Never change it after the first start |
| `GITHUB_WEBHOOK_SECRET`, `SONAR_WEBHOOK_SECRET` | random – you copy them into GitHub (Step 11) and SonarQube (Step 9) |
| `DOCKER_GID` | the Docker socket's group number on this server, for example `988` |
| `JENKINS_PUBLIC_URL` | `http://localhost:18079/` – the address you'll open Jenkins at, through the SSH tunnel (Step 8) |
| `GITHUB_REPO_URL`, `GITHUB_BRANCH`, `DOCKERHUB_USERNAME` | from `.env.example` – change them if you use a fork |

**You fill in:**

| Variable | Value |
|----------|-------|
| `DOCKERHUB_TOKEN` | the Docker Hub token for the server (see [Before you start](#4-before-you-start)) |
| `SONAR_TOKEN` | **leave empty for now** – SonarQube creates it in Step 9 |
| `NGROK_AUTHTOKEN` | leave empty – the server doesn't need ngrok |

**Keep every line in the file**, even when its value is empty.

**Check:**

```bash
docker compose config --quiet        # prints nothing = the file is complete
grep -c '^[A-Z_]*=' .env             # 17
```

### Step 7 – Start everything with one command

```bash
cd ~/simple-spring-boot-app/cicd
docker compose up -d --build
```

- `up` creates and starts all containers; `-d` runs them in the background; `--build` builds the Jenkins image from
  `jenkins/Dockerfile` (Jenkins LTS + Java 21 + Docker CLI + plugins + `casc.yaml`).
- The first start downloads about 3 GB and takes 5–10 minutes. Later starts take seconds.

**Check:**

```bash
docker compose ps
```

Wait until all three show **`(healthy)`** (`(health: starting)` means "still starting"):

```text
NAME                  IMAGE                                SERVICE        STATUS
cicd-jenkins-1        cicd-jenkins:2.580.2                 jenkins        Up 3 minutes (healthy)
cicd-sonarqube-1      sonarqube:26.10.0.133078-community   sonarqube      Up 3 minutes (healthy)
cicd-sonarqube-db-1   postgres:17                          sonarqube-db   Up 3 minutes (healthy)
```

If one stays unhealthy: `docker compose logs --tail 100 sonarqube` (or `jenkins`) shows why.

> From now on the containers start automatically whenever the instance starts: Docker starts at boot, and every
> service has `restart: unless-stopped`.

### Step 8 – Open Jenkins and SonarQube safely (SSH tunnel)

Ports 8079 and 9000 are closed to the internet (Step 2). An **SSH tunnel** carries the web pages through your
encrypted SSH connection. Open a **second** PowerShell window **on your PC** and keep it open while you work:

```powershell
ssh -i "$env:USERPROFILE\.ssh\devops-key.pem" -N -L 18079:localhost:8079 -L 19000:localhost:9000 ubuntu@<elastic-ip>
```

- `-L 18079:localhost:8079` = "port 18079 on my PC → port 8079 on the server". Local ports 18079/19000 avoid a clash
  with the Jenkins (8079) and SonarQube (9000) running on your PC.
- `-N` = only the tunnel, no command line. The window looks idle – that is correct. **Ctrl + C** closes the tunnel.

Now, on your PC: **Jenkins** = http://localhost:18079, **SonarQube** = http://localhost:19000.

**Check:** http://localhost:18079 shows the Jenkins login page with the message *"This Jenkins is configured by
cicd/jenkins/casc.yaml"*.

### Step 9 – SonarQube: one-time setup

Open **http://localhost:19000**.

**9.1 Admin password.** Log in with `admin` / `admin` → SonarQube asks for a new password → choose a strong one and
keep it in your password manager.

**9.2 Two settings.** **Administration** → **Configuration** → **General Settings**:

| Category | Setting | Value | Why |
|----------|---------|-------|-----|
| General | **Server base URL** | `http://localhost:19000` | Links in Jenkins and in the build log point here (through the tunnel) |
| Security | **Enable local webhooks validation** | **off** | Otherwise SonarQube refuses the webhook to the `jenkins` container's private address |

Click **Save** after each change.

**9.3 Webhook to Jenkins.** **Administration** → **Configuration** → **Webhooks** → **Create**:

| Field | Value |
|-------|-------|
| Name | `Jenkins` |
| URL | `http://jenkins:8080/sonarqube-webhook/` – the final `/` is required |
| Secret | the value of `SONAR_WEBHOOK_SECRET` – show it on the server with `grep SONAR_WEBHOOK_SECRET ~/simple-spring-boot-app/cicd/.env` |

The URL uses the container name `jenkins` and Jenkins' port **inside** the container (8080), because the call goes
from container to container. It is the same on every machine.

**9.4 Token for Jenkins.** Avatar (top right) → **My Account** → **Security** → **Generate Tokens**: **Name** `jenkins`,
**Type** **User Token**, **Expires in** for example 90 days → **Generate** → copy the token (`squ_…`).

**9.5 Give Jenkins the token** – on the server:

```bash
cd ~/simple-spring-boot-app/cicd
nano .env                                    # SONAR_TOKEN=squ_...
docker compose up -d --force-recreate jenkins
```

> `--force-recreate` is needed because Docker Compose doesn't notice when only a secret in `.env` changes. Jenkins'
> jobs and history are in the `jenkins_home` volume and are not affected.

**Check:** **Webhooks** lists `Jenkins`; after about a minute `docker compose ps` shows `jenkins` as `(healthy)` again.

### Step 10 – Jenkins: check the configuration and run the first build

Open **http://localhost:18079** and log in as `admin` with the password from `.env`:

```bash
grep JENKINS_ADMIN_PASSWORD ~/simple-spring-boot-app/cicd/.env
```

Everything is already configured by `jenkins/casc.yaml`:

| Where | What you should see |
|-------|---------------------|
| Dashboard | The job **simple-spring-boot-app** |
| **Manage Jenkins** → **Credentials** | `dockerhub-credentials`, `github-credentials`, `github-webhook-secret`, `sonarqube-token`, `sonarqube-webhook-secret` |
| **Manage Jenkins** → **System** → *SonarQube servers* | `SonarQube` – `http://sonarqube:9000` |
| **Manage Jenkins** → **Plugins** → **Installed plugins** | Configuration as Code, Job DSL, Pipeline, Git, GitHub, Credentials Binding, JUnit, Pipeline Graph View, SonarQube Scanner |

> **Change settings in the files, not in the web UI.** Jenkins applies `casc.yaml` at every start, so a change made
> only in the web UI is lost at the next restart.

Now job **simple-spring-boot-app** → **Build Now**. The first build takes longer: Maven downloads all dependencies and
Trivy downloads its vulnerability database once (both are cached in Docker volumes for later builds).

**Check:** the build turns green with **13 stages**. What each stage prints:
[cicd/README.md, Step 12](README.md#step-12--check-every-stage).

### Step 11 – Build on every push (GitHub webhook)

GitHub calls Jenkins on every push – directly at the Elastic IP; no ngrok needed on AWS.

1. GitHub → the repository → **Settings** → **Webhooks** → **Add webhook**:

   | Field | Value |
   |-------|-------|
   | Payload URL | `http://<elastic-ip>:8079/github-webhook/` – the final `/github-webhook/` is required |
   | Content type | `application/json` |
   | Secret | the value of `GITHUB_WEBHOOK_SECRET` (`grep GITHUB_WEBHOOK_SECRET ~/simple-spring-boot-app/cicd/.env`) |
   | Which events | **Just the push event** |
   | Active | ticked |

2. If your PC's Jenkins should stop building this repository, delete or deactivate **its** webhook (the ngrok
   address) – otherwise both build every push.

**Check:**

1. **Recent Deliveries** → the "ping" shows a green tick and **200**. (**400** = the Secret differs from `.env`;
   a timeout = the security group's GitHub rules from Step 2 are missing.)
2. Push a small change on your PC – within seconds a new build starts: **Started by GitHub push by …**.

> The secret makes GitHub sign every delivery; Jenkins ignores requests that aren't signed with it.

### Step 12 – Open the application

On your PC: **http://\<elastic-ip\>:8080/api/hello** →
`{"message":"Hello! Spring Boot application is running successfully."}`

**Your DevOps environment on AWS is complete.**

---

## Everyday operations

Always run `docker compose` commands **in the `cicd` folder**: `cd ~/simple-spring-boot-app/cicd`.

| Task | Command |
|------|---------|
| Status of all services | `docker compose ps` |
| Log of a service | `docker compose logs --tail 200 jenkins` (or `sonarqube`, `sonarqube-db`) |
| The deployed application | `docker ps --filter name=simple-spring-boot-app` / `docker logs simple-spring-boot-app` |
| Apply changed files from GitHub | `git pull` then `docker compose up -d --build` |
| Apply a changed secret in `.env` | `docker compose up -d --force-recreate jenkins` |
| Stop / start the services | `docker compose stop` / `docker compose start` |
| Disk usage | `df -h /` and `docker system df` |
| Security updates of Ubuntu | Installed automatically every day (*unattended-upgrades*). Check monthly: `sudo apt-get update && sudo apt-get upgrade -y`; if `/var/run/reboot-required` exists, `sudo reboot` |

**Save money:** **EC2** → the instance → **Instance state** → **Stop instance** when nobody needs it (evenings,
weekends). **Start instance** later: the Elastic IP stays, and all containers – including the deployed application –
start by themselves. Data in the volumes is kept. (**Terminate** would delete the instance *and* its disk.)

> Don't run `docker system prune --volumes` or `docker volume rm …` – they delete Jenkins' history and SonarQube's
> database. `docker image prune` (unused images) is safe.

---

## Backups and moving to a new instance

The data that matters is in Docker volumes on the instance's disk: Jenkins' build history (`cicd_jenkins_home`) and
SonarQube's database (`cicd_sonarqube_db`). Everything else is recreated from the repository.

**Make a backup** (about 1 minute; Jenkins pauses):

```bash
cd ~/simple-spring-boot-app/cicd
docker compose stop jenkins
docker compose run --rm backup           # writes backups/<date_time>/
docker compose start jenkins
```

**Keep a copy off the instance** – a backup on the same disk doesn't help if the instance is lost. On your PC:

```powershell
scp -i "$env:USERPROFILE\.ssh\devops-key.pem" -r ubuntu@<elastic-ip>:~/simple-spring-boot-app/cicd/backups .
```

(Automatic copies to Amazon S3 are in [Future](#future-other-aws-deployment-environments). Also consider EBS
snapshots: **EC2** → **Volumes** → the volume → **Actions** → **Create snapshot**, or automatically with *Amazon Data
Lifecycle Manager*.)

**Move to a new instance** (new region, bigger instance type, or after a failure):

1. Do Steps 1–7 for the new instance (Steps 1–2 only if the key pair and security group don't exist in that region).
2. Copy the backup to the new instance and restore it:

   ```powershell
   # on your PC
   scp -i "$env:USERPROFILE\.ssh\devops-key.pem" -r backups\2026-11-04_0930 ubuntu@<new-elastic-ip>:~/simple-spring-boot-app/cicd/backups/
   ```

   ```bash
   # on the new instance
   cd ~/simple-spring-boot-app/cicd
   docker compose stop jenkins sonarqube
   docker compose run --rm backup restore.sh 2026-11-04_0930
   docker compose start jenkins sonarqube
   ```

3. The SonarQube database now comes from the old machine: log in with the **old** SonarQube admin password, and put
   the **old** `SONAR_TOKEN` and `SONAR_WEBHOOK_SECRET` into the new `.env`
   (`docker compose up -d --force-recreate jenkins`). Skip Step 9 – it's already in the restored database.
4. Point the GitHub webhook at the new Elastic IP (Step 11).

The backup also works between your Windows PC and EC2 in both directions – details in
[cicd/README.md, Backup and restore](README.md#backup-and-restore).

---

## Security checklist

| ✔ | Measure | Where |
|---|---------|-------|
| ☐ | AWS: work as an IAM user, not root; MFA on; a budget alert | AWS console |
| ☐ | SSH only from **My IP**; the `.pem` file only readable by you | Step 1, Step 2 |
| ☐ | Jenkins and SonarQube **not** open to the internet – reached through the SSH tunnel; port 8079 open only for GitHub's webhook ranges | Step 2, Step 8 |
| ☐ | Disk encrypted; IMDSv2 required | Step 3 |
| ☐ | No secrets in Git or in user data; `.env` is `chmod 600` | `.gitignore`, `create-env.sh` |
| ☐ | New passwords and tokens for each machine (`create-env.sh` generates them); a separate Docker Hub token per machine | Step 6 |
| ☐ | Both webhooks signed with a secret | Step 9, Step 11 |
| ☐ | Exact versions of every image and plugin; the application's base image and Trivy pinned by digest | `docker-compose.yml`, `plugins.txt`, `Dockerfile`, `Jenkinsfile` |
| ☐ | Every application image scanned for vulnerabilities before it is pushed | `Jenkinsfile` (Image Scan) |
| ☐ | Ubuntu security updates (automatic) and a monthly check | [Everyday operations](#everyday-operations) |
| ☐ | Backups copied off the instance | [Backups](#backups-and-moving-to-a-new-instance) |
| ☐ | Tokens renewed before they expire (SonarQube token: 90 days) | [cicd/README.md – rotating tokens](README.md#changing-settings-and-rotating-tokens) |

**Known limits of a single-instance setup** (fine for learning and a small team; plan them before real production):

- Jenkins uses the server's Docker socket, so whoever can change the `Jenkinsfile` controls the server. Protect the
  `master` branch on GitHub and give Jenkins accounts only to the team. The next step is a separate build agent.
- The application runs on the CI server itself. For production it belongs on its own server or service.
- Plain HTTP through the SSH tunnel is encrypted by SSH; for a team that uses the web pages directly, add HTTPS
  ([Future](#future-other-aws-deployment-environments)).

---

## Troubleshooting (AWS-specific)

For errors inside Jenkins, SonarQube or the pipeline, see [cicd/README.md – Troubleshooting](README.md#troubleshooting).

| Symptom | Cause | Solution |
|---------|-------|----------|
| `ssh`: `WARNING: UNPROTECTED PRIVATE KEY FILE!` | Other users may read the `.pem` file | Step 1, point 4 (`icacls`) |
| `ssh`: `Permission denied (publickey)` | Wrong user or key | User is `ubuntu`; use the key the instance was launched with |
| `ssh`: `Connection timed out` | Your internet address changed, or the instance is stopped | Security group → SSH rule → **My IP** again; check the instance is **Running** |
| Tunnel: `bind [127.0.0.1]:18079: Address already in use` | Another tunnel or program uses the local port | Close the other tunnel, or use other local ports (e.g. `-L 28079:localhost:8079`) |
| No `/var/log/devops-setup.done` after 10 minutes | The user data failed or wasn't pasted | `sudo tail -50 /var/log/cloud-init-output.log`; run the scripts by hand ([Appendix B](#appendix-b--without-user-data-manual-server-setup)). User data runs only at the **first** boot |
| `permission denied while trying to connect to the Docker daemon socket` | The `docker` group isn't active in this login yet | Log out and in again |
| `docker compose`: `no configuration file provided` | Not in the `cicd` folder | `cd ~/simple-spring-boot-app/cicd` |
| Jenkins log: `permission denied … /var/run/docker.sock` during a build | `DOCKER_GID` in `.env` doesn't match | `bash ~/simple-spring-boot-app/cicd/scripts/create-env.sh` sets it again, then `docker compose up -d --force-recreate jenkins` |
| SonarQube restarts; log: `max virtual memory areas vm.max_map_count [65530] is too low` | Kernel setting missing | `sudo bash ~/simple-spring-boot-app/cicd/scripts/setup-ubuntu-host.sh` (sets it permanently) |
| A container stops with exit code **137**, builds are very slow, `OutOfMemoryError` | Not enough memory | `free -h`; use a bigger instance type: stop the instance → **Actions** → **Instance settings** → **Change instance type** → `t3.xlarge` → start |
| GitHub delivery: `failed to connect` / timeout | GitHub's ranges missing in the security group, or a wrong address | Step 2 rules for port 8079; Payload URL with the **Elastic IP** |
| `toomanyrequests: You have reached your pull rate limit` | Docker Hub limits anonymous downloads per address | On the server, log in once as `ubuntu`: `docker login -u <docker-hub-username>` (token as password) |
| `no space left on device` | The disk is full | `docker image prune -a` (keeps images in use); or enlarge the volume: **EC2** → **Volumes** → **Modify** → e.g. 60 GiB, then on the server `sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1` (`lsblk` shows the names) |
| The application isn't reachable on port 8080 | Security group rule missing, or the last deploy failed | Step 2 rule for 8080; `docker ps --filter name=simple-spring-boot-app` |

---

## Future: other AWS deployment environments

The setup is built so that each part can be replaced by an AWS service later **without starting over**: all
machine-specific values are in `.env`, all configuration is in files, and the data is in named volumes.

| Today (one EC2 instance) | Next step on AWS | What changes |
|--------------------------|------------------|--------------|
| AWS resources created by hand (Part A) | **Terraform**, **AWS CloudFormation** or **AWS CDK** – the instance, security group and Elastic IP as code in this repository | A new folder, e.g. `infra/`; the user data stays the same |
| `.env` file on the instance | **AWS Secrets Manager** or **SSM Parameter Store** – the instance reads the secrets with an IAM role at boot | `create-env.sh` fetches the values (`aws ssm get-parameter …`) instead of generating them |
| SSH on port 22 | **AWS Systems Manager Session Manager** – log in and tunnel through AWS, no open port 22 | Instance gets an IAM role with `AmazonSSMManagedInstanceCore`; security group without port 22 |
| HTTP through the SSH tunnel | **Application Load Balancer** with an **ACM** certificate (HTTPS) and your domain | Security group allows 8079/9000 only from the load balancer; `JENKINS_PUBLIC_URL` = the HTTPS address |
| Backups copied by hand | **Amazon S3** (e.g. nightly cron: `aws s3 sync backups s3://<bucket>/cicd-backups/`) plus **EBS snapshots** / **AWS Backup** | Instance IAM role with S3 write access to that bucket; if a container must call AWS, set the instance's metadata *hop limit* to 2 |
| `sonarqube-db` container | **Amazon RDS for PostgreSQL** (managed backups, updates, failover) | `SONAR_JDBC_URL` in `docker-compose.yml` → RDS endpoint; remove the `sonarqube-db` service; restore the dump into RDS |
| Docker Hub | **Amazon ECR** (private registry next to your instances) | `DOCKER_IMAGE` in the `Jenkinsfile`; login with the instance's IAM role (`aws ecr get-login-password`) instead of a token |
| Builds on the Jenkins container | **Jenkins agents** on separate EC2 instances or ECS (Jenkins *EC2* or *Amazon ECS* plugin) | `plugins.txt` + a cloud section in `casc.yaml`; the controller no longer needs the Docker socket |
| Application deployed on the CI server | Its own **EC2** instance, **Amazon ECS (Fargate)** or **Amazon EKS** – a staging environment first, then production after an approval | The **Deploy** stage: e.g. `aws ecs update-service …` or `helm upgrade …`, plus an `input` step before production |
| Jenkins + SonarQube on one instance | Each on its own instance, or SonarQube Cloud / a managed CI service | `docker-compose.yml` split per machine; Jenkins' SonarQube URL in `casc.yaml` |

A good order for a junior team: **1)** S3 backups, **2)** Session Manager instead of SSH, **3)** HTTPS with a load
balancer, **4)** Terraform for Part A, **5)** a separate place for the application, **6)** build agents.

---

## Appendix A – Create the AWS resources with the AWS CLI

Optional – the same as Part A, but with commands, so a new instance takes one copy-and-paste. Run them in
**AWS CloudShell** (the `>_` icon in the AWS console – already logged in, AWS CLI included) or in Git Bash with the
AWS CLI configured. In CloudShell, first get the repository: `git clone https://github.com/Manivannanbgi007/simple-spring-boot-app.git && cd simple-spring-boot-app`.

> These commands follow the AWS CLI documentation but were not run against an AWS account while writing this guide.
> Run them one by one and read each result. In the console, check that the resources look like Part A.

```bash
REGION=ap-south-1                                   # your region
export AWS_DEFAULT_REGION=$REGION

# Step 1 - key pair (keep the .pem file; in CloudShell: Actions -> Download file)
aws ec2 create-key-pair --key-name devops-key --key-type ed25519 \
  --query KeyMaterial --output text > devops-key.pem && chmod 400 devops-key.pem

# Step 2 - security group in the default VPC
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG_ID=$(aws ec2 create-security-group --group-name devops-sg \
  --description "Jenkins, SonarQube and app server" --vpc-id "$VPC_ID" --query GroupId --output text)
MY_IP="$(curl -s https://checkip.amazonaws.com)/32"     # in CloudShell this is CloudShell's address - use your PC's instead
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MY_IP"
for CIDR in 192.30.252.0/22 185.199.108.0/22 140.82.112.0/20 143.55.64.0/20 9.234.106.48/28 9.234.98.160/28 9.234.98.176/28; do
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 8079 --cidr "$CIDR"
done
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 8080 --cidr 0.0.0.0/0

# Step 3 - the newest Ubuntu 26.04 LTS image (published by Canonical), then the instance with the user data
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query Parameter.Value --output text)
INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI_ID" --instance-type t3.large \
  --key-name devops-key --security-group-ids "$SG_ID" \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=40,VolumeType=gp3,Encrypted=true}' \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --user-data file://cicd/aws/user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=devops-server}]' \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# Step 4 - Elastic IP
ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$ALLOC_ID"
aws ec2 describe-addresses --allocation-ids "$ALLOC_ID" --query 'Addresses[0].PublicIp' --output text
```

Then continue with [Step 5](#step-5--connect-with-ssh-and-check-the-automatic-setup).

---

## Appendix B – Without user data (manual server setup)

Use this when the user data wasn't pasted, failed, or the repository is private. Connect with SSH (Step 5), then:

```bash
# 1. Get the repository (private repository: use https://<github-username>:<token>@github.com/... or an SSH deploy key)
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/Manivannanbgi007/simple-spring-boot-app.git
cd simple-spring-boot-app

# 2. Prepare the server - Docker, Compose, kernel settings, swap, log rotation
sudo bash cicd/scripts/setup-ubuntu-host.sh              # add --with-java to also install Java 21
exit                                                     # log out and in again (docker group)

# 3. After logging in again: create .env with new random secrets (and the Jenkins address for the SSH tunnel)
cd ~/simple-spring-boot-app
JENKINS_PUBLIC_URL=http://localhost:18079/ bash cicd/scripts/create-env.sh
```

Then continue with [Step 6](#step-6--complete-the-env-file).

**What the scripts change on the server** (both are safe to run again – each step checks first):

| Script | Changes |
|--------|---------|
| `setup-ubuntu-host.sh` | Docker's apt repository (`/etc/apt/sources.list.d/docker.list`) and packages `docker-ce`, `docker-compose-plugin`, `docker-buildx-plugin`; Docker enabled at boot; `/etc/docker/daemon.json` (log rotation, only if the file doesn't exist); user added to group `docker`; `/etc/sysctl.d/99-sonarqube.conf`; `/swapfile` + `/etc/fstab` (only if there is no swap yet); with `--with-java`: package `openjdk-21-jdk-headless` |
| `create-env.sh` | Only `cicd/.env` (created from `.env.example` if missing, mode 600): fills **empty** secrets with random values, sets `DOCKER_GID`; never changes a secret that already has a value |
