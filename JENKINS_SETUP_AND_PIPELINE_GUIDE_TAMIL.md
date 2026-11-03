# Jenkins நிறுவல் மற்றும் CI/CD Pipeline வழிகாட்டி – Windows

> **இந்த வழிகாட்டி யாருக்கு?** Jenkins, Docker-ஐ புதிதாகக் கற்கும் beginners மற்றும் junior developers-க்கு.
>
> **முடிவில் என்ன கிடைக்கும்?** GitHub-க்கு code push செய்தவுடன் Jenkins தானாகவே: code எடுக்கும் → build செய்யும் → tests இயக்கும் → JAR உருவாக்கும் → Docker image உருவாக்கும் → Docker Hub-க்கு push செய்யும் → மீண்டும் pull செய்யும் → container-ஆக இயக்கும் → application சரியாக இயங்குகிறதா என்று சரிபார்க்கும்.

இந்த ஆவணம் `simple-spring-boot-app` project-ஐ அடிப்படையாகக் கொண்டது (Java 21, Spring Boot 4.1.2, `GET /api/hello` endpoint). இதில் உள்ள `Jenkinsfile`, `Dockerfile` இரண்டும் project folder-ல் உள்ள அதே files.

```text
 git push ──▶ GitHub ──webhook──▶ Jenkins
                                     │
   Checkout ▶ Build ▶ Unit Tests ▶ Package JAR ▶ Docker Build ▶ Docker Login ▶ Docker Push ──▶ Docker Hub
                                                                                                 │
                                        Smoke Test ◀ Deploy (docker run) ◀ Docker Pull ◀─────────┘
```

> 📌 **திரை வடிவங்கள் பற்றி:** இந்த ஆவணத்தில் உள்ள பெட்டி வடிவப் படங்கள் (┌──┐) உண்மையான screenshots அல்ல. Jenkins, GitHub, Docker Hub திரைகளில் நீங்கள் நிரப்ப வேண்டிய fields-ஐ text வடிவில் காட்டுகின்றன. Menu, button பெயர்கள் திரையில் உள்ளபடியே ஆங்கிலத்தில் **bold** எழுத்தில் கொடுக்கப்பட்டுள்ளன — திரையில் அதே பெயரைத் தேடுங்கள்.

---

## உள்ளடக்கம்

- [0. தொடங்கும் முன்](#section-0)
- [1. Windows-ல் Jenkins நிறுவுதல்](#section-1)
- [2. Jenkins Plugins நிறுவுதல்](#section-2)
- [3. Jenkins-ல் Git அமைப்பு](#section-3)
- [4. Jenkins-ல் Maven மற்றும் JDK அமைப்பு](#section-4)
- [5. Jenkins-ல் Docker அமைப்பு](#section-5)
- [6. Docker Hub அமைப்பு](#section-6)
- [7. Jenkins Pipeline செயல்படுத்துதல்](#section-7)
- [8. பிழைத்திருத்தம் (Troubleshooting)](#section-8)
- [பின்னிணைப்பு: விரைவு Command பட்டியல்](#appendix)

---

<a id="section-0"></a>
## 0. தொடங்கும் முன்

### 0.1 தேவையான மென்பொருட்கள் மற்றும் கணக்குகள்

| என்ன | எதற்கு | இணைப்பு |
|------|--------|---------|
| Windows 10 / 11 (64-bit) | – | – |
| JDK 21 | Jenkins-ம் Spring Boot application-ம் Java-வில் இயங்குகின்றன | https://adoptium.net/temurin/releases/?version=21 (அல்லது Oracle JDK 21: https://www.oracle.com/java/technologies/downloads/#java21) |
| Git for Windows | Code-ஐ GitHub-க்கு push செய்ய; Jenkins code எடுக்க | https://git-scm.com/download/win |
| Jenkins (LTS) | CI/CD pipeline இயக்க | https://www.jenkins.io/download/ |
| Docker Desktop | Docker image உருவாக்க, container இயக்க | https://www.docker.com/products/docker-desktop/ |
| GitHub கணக்கு | Source code சேமிக்க | https://github.com/signup |
| Docker Hub கணக்கு | Docker image சேமிக்க | https://hub.docker.com/ |
| ngrok (விருப்பம்) | GitHub webhook உங்கள் கணினியை அடைய | https://ngrok.com/download |

> **Maven-ஐ தனியாக நிறுவ வேண்டியதில்லை.** Project-ல் உள்ள Maven Wrapper (`mvnw.cmd`) சரியான Maven version-ஐ (3.9.16) தானாக download செய்யும் (பிரிவு 4).

### 0.2 இந்த ஆவணத்தில் பயன்படுத்தும் மதிப்புகள்

| பெயர் | மதிப்பு | குறிப்பு |
|-------|--------|---------|
| Jenkins முகவரி | `http://localhost:8079` | Application 8080-ஐப் பயன்படுத்துவதால் Jenkins-க்கு 8079 |
| Application முகவரி | `http://localhost:8080/api/hello` | |
| Jenkins data folder (`JENKINS_HOME`) | `C:\ProgramData\Jenkins\.jenkins` | Jobs, builds, credentials இங்கே |
| Jenkins install folder | `C:\Program Files\Jenkins` | இந்தக் கணினியில்: `D:\Jenkins` |
| Jenkins job பெயர் | `simple-spring-boot-app` | |
| Docker Hub credential ID | `dockerhub-credentials` | Jenkinsfile இந்த ID-ஐப் பயன்படுத்துகிறது |
| GitHub credential ID | `github-credentials` | Private repository-க்கு மட்டும் |
| `<github-username>` | உங்கள் GitHub username | **நீங்கள் மாற்ற வேண்டும்** |
| `<docker-hub-username>` | உங்கள் Docker Hub username (சிறிய எழுத்துகள்) | **நீங்கள் மாற்ற வேண்டும்** |
| `YOURDOMAIN\yourname` | உங்கள் Windows கணக்கு (`whoami` output) | **நீங்கள் மாற்ற வேண்டும்** |

### 0.3 PowerShell / Command Prompt திறப்பது எப்படி?

- **சாதாரண PowerShell:** Start → `PowerShell` என type செய்யுங்கள் → **Windows PowerShell**.
- **Administrator PowerShell:** Start → `PowerShell` → வலது click → **Run as administrator**. ("Administrator" என்று குறிப்பிட்ட commands-க்கு மட்டும் இது தேவை.)
- **Command Prompt (CMD):** Start → `cmd` → **Command Prompt**.

Project commands-ஐ `simple-spring-boot-app` folder-க்குள் (`pom.xml` உள்ள folder) இயக்க வேண்டும். உதாரணம்:

```powershell
cd "D:\Drive E\dev\spring-jenkins\simple-spring-boot-app"
```

---

<a id="section-1"></a>
## 1. Windows-ல் Jenkins நிறுவுதல்

### 1.1 JDK 21 நிறுவுதல்

Jenkins ஒரு Java application. எனவே முதலில் JDK 21 தேவை.

1. https://adoptium.net/temurin/releases/?version=21 திறந்து **Operating System: Windows**, **Architecture: x64**, **Package Type: JDK** → **.msi** file-ஐ download செய்யுங்கள்.
2. Installer-ஐ இயக்குங்கள். **Custom Setup** திரையில் **Set JAVA_HOME variable** என்பதை **Will be installed on local hard drive** என மாற்றுங்கள் → **Next** → **Install**.
3. Oracle JDK பயன்படுத்தினால், அல்லது `JAVA_HOME` அமையவில்லை என்றால் — **Administrator PowerShell**-ல் (உங்கள் JDK folder பெயரைச் சரியாகக் கொடுங்கள்):

   ```powershell
   [Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Java\jdk-21.0.12.1', 'Machine')
   ```

   அல்லது GUI மூலம்: Start → `environment variables` → **Edit the system environment variables** → **Environment Variables…** → **System variables** பகுதியில் **New…** → Variable name: `JAVA_HOME`, Variable value: JDK folder → **OK**.

4. **புதிய** PowerShell window திறந்து சரிபார்க்கவும்:

   ```powershell
   java -version
   $env:JAVA_HOME
   ```

   **எதிர்பார்க்கும் output:**

   ```text
   java version "21.0.12.1" 2026-08-18 LTS
   Java(TM) SE Runtime Environment (build 21.0.12.1+1-LTS-4)
   Java HotSpot(TM) 64-Bit Server VM (build 21.0.12.1+1-LTS-4, mixed mode, sharing)
   C:\Program Files\Java\jdk-21.0.12.1
   ```

   Version **21** என்று இருந்தால் சரி ✅.

> ⚠️ `JAVA_HOME`-ஐ **System variables**-ல் அமைக்க வேண்டும் (User variables-ல் அல்ல). Jenkins ஒரு Windows service — அது system variables-ஐப் படிக்கும்.

### 1.2 Jenkins பதிவிறக்கம் (Download)

1. https://www.jenkins.io/download/ திறக்கவும்.
2. **Download Jenkins … LTS for:** பட்டியலில் **Windows** கிளிக் செய்யுங்கள் → `jenkins.msi` download ஆகும்.

> **LTS** (Long-Term Support) = நிலையான, பாதுகாப்பான version. Beginners **Weekly** version-ஐத் தவிர்க்கவும்.
>
> Windows நிறுவல் பற்றிய அதிகாரப்பூர்வ ஆவணம்: https://www.jenkins.io/doc/book/installing/windows/

### 1.3 Jenkins நிறுவுதல் (Installer படிகள்)

`jenkins.msi`-ஐ double-click செய்யுங்கள்:

| Installer திரை | என்ன செய்ய வேண்டும் |
|----------------|---------------------|
| **Welcome** | **Next** |
| **Destination Folder** | இயல்புநிலை `C:\Program Files\Jenkins\` → **Next** |
| **Service Logon Credentials** | **Run service as local or domain user** தேர்வு → Account: `YOURDOMAIN\yourname`, Password: உங்கள் Windows password → **Test Credentials** → **Next** (ஏன்? பிரிவு [5.2](#section-5-2)) |
| **Port Selection** | `8079` → **Test Port** (பச்சை ✓ வர வேண்டும்) → **Next** |
| **Select Java home directory** | JDK 21 folder, உ.தா. `C:\Program Files\Java\jdk-21.0.12.1\` → **Next** |
| **Custom Setup** | இயல்புநிலை → **Next** |
| **Ready to install** | **Install** → (Windows அனுமதி கேட்டால் **Yes**) → **Finish** |

```text
┌─ Jenkins Setup › Service Logon Credentials ──────────────────┐
│  ( ) Run service as LocalSystem (not recommended)            │
│  (•) Run service as local or domain user                     │
│        Account:   YOURDOMAIN\yourname                        │
│        Password:  ••••••••••                                 │
│                                     [ Test Credentials ]     │
│                             [ Back ]  [ Next ]  [ Cancel ]   │
└──────────────────────────────────────────────────────────────┘
```

> 💡 உங்கள் `YOURDOMAIN\yourname` என்ன என்று அறிய PowerShell-ல் `whoami` இயக்குங்கள்.
>
> 💡 Jenkins ஏற்கனவே **LocalSystem** கணக்கில் நிறுவப்பட்டிருந்தால் மீண்டும் நிறுவ வேண்டாம் — பிரிவு [5.3](#section-5-3)-ல் service கணக்கை மாற்றும் முறை உள்ளது.

நிறுவல் முடிந்ததும் Jenkins ஒரு Windows service-ஆகத் தானாகத் தொடங்கும். சரிபார்க்க:

```powershell
Get-Service Jenkins
```

**எதிர்பார்க்கும் output:**

```text
Status   Name               DisplayName
------   ----               -----------
Running  Jenkins            Jenkins
```

### 1.4 முதல் முறை அமைப்பு (Unlock Jenkins)

1. Browser-ல் http://localhost:8079 திறக்கவும். **Unlock Jenkins** திரை வரும்.
2. ஆரம்ப admin password-ஐ எடுக்க — **Administrator PowerShell**:

   ```powershell
   Get-Content "C:\ProgramData\Jenkins\.jenkins\secrets\initialAdminPassword"
   ```

   32 எழுத்துகள் கொண்ட ஒரு password வரும் (உ.தா. `3f9c2a7d…`). அதை copy செய்து **Administrator password** பெட்டியில் paste → **Continue**.

3. **Customize Jenkins** திரையில் **Install suggested plugins** கிளிக் செய்யுங்கள். Plugins install ஆக சில நிமிடங்கள் ஆகும் (internet தேவை).

```text
┌─ Customize Jenkins ──────────────────────────────────────────┐
│                                                              │
│   [ Install suggested plugins ]   [ Select plugins to install ]
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 1.5 Administrator கணக்கை அமைத்தல்

Plugins முடிந்ததும் **Create First Admin User** திரை வரும்:

```text
┌─ Create First Admin User ────────────────────────────────────┐
│  Username:          admin                                    │
│  Password:          ••••••••••                               │
│  Confirm password:  ••••••••••                               │
│  Full name:         Jenkins Admin                            │
│  E-mail address:    you@example.com                          │
│                                      [ Save and Continue ]   │
└──────────────────────────────────────────────────────────────┘
```

1. Username, **வலுவான** password, பெயர், email நிரப்பி → **Save and Continue**.
2. **Instance Configuration** → **Jenkins URL:** `http://localhost:8079/` → **Save and Finish**.
3. **Start using Jenkins** → Jenkins Dashboard திறக்கும் 🎉.

> 🔐 இந்த admin username, password-ஐ மறக்காதீர்கள். மறந்தால் பிரிவு [8.2](#section-8-2) பார்க்கவும்.

**பாதுகாப்பு அமைப்புகளைச் சரிபார்த்தல்:** **Manage Jenkins** → **Security**:

| அமைப்பு | மதிப்பு |
|---------|--------|
| **Security Realm** | Jenkins' own user database |
| **Allow users to sign up** | ☐ (tick வேண்டாம் — யாரும் தானாகக் கணக்கு உருவாக்கக் கூடாது) |
| **Authorization** | Logged-in users can do anything |
| **Allow anonymous read access** | ☐ (tick வேண்டாம்) |

→ **Save**.

**கூடுதல் பயனர் / password மாற்றம்:** **Manage Jenkins** → **Users** → **Create User** (புதிய பயனர்), அல்லது ஏற்கனவே உள்ள user-ஐ கிளிக் செய்து password-ஐ மாற்றலாம்.

### 1.6 Jenkins service-ஐ நிர்வகித்தல்

| செயல் | எப்படி |
|-------|--------|
| நிலை பார்க்க | `Get-Service Jenkins` |
| Restart (Administrator PowerShell) | `Restart-Service Jenkins` |
| Stop / Start (Administrator PowerShell) | `Stop-Service Jenkins` / `Start-Service Jenkins` |
| GUI மூலம் | **Win + R** → `services.msc` → **Jenkins** → வலது click → **Start** / **Stop** / **Restart** |
| Browser மூலம் பாதுகாப்பான restart | `http://localhost:8079/safeRestart` (ஓடும் builds முடிந்த பின் restart ஆகும்) |

✅ **சரிபார்ப்பு:** http://localhost:8079 → admin கணக்கில் login → Dashboard தெரிகிறது.

---

<a id="section-2"></a>
## 2. Jenkins Plugins நிறுவுதல்

### 2.1 Plugin என்றால் என்ன?

Plugin என்பது Jenkins-க்குப் புதிய திறன்களைச் சேர்க்கும் add-on. உதாரணமாக, GitHub-லிருந்து code எடுக்க **Git** plugin தேவை.

### 2.2 தேவையான Plugins

நம் pipeline Maven, Docker-ஐ நேரடி commands மூலம் (`mvnw.cmd`, `docker`) இயக்குகிறது. அதனால் குறைவான plugins போதும். **Install suggested plugins** தேர்வு செய்திருந்தால் இவை பெரும்பாலும் ஏற்கனவே நிறுவப்பட்டிருக்கும் (சில, மற்ற plugins-ன் dependency-ஆக வரும்) — சரிபார்த்தால் போதும்.

| Plugin | பயன் (எதற்கு?) | Pipeline-ல் எங்கே | அமைப்பு (Configuration) |
|--------|-----------------|--------------------|--------------------------|
| **Pipeline** | `Jenkinsfile`-ஐ இயக்கும் அடிப்படை plugin | முழு pipeline | தேவையில்லை |
| **Git** | GitHub repository-லிருந்து code checkout | Checkout stage | பிரிவு [3.2](#section-3-2) (Tools → Git) |
| **GitHub** | GitHub webhook-ஐ ஏற்று build தொடங்க | Triggers | பிரிவு [7.6](#section-7-6) |
| **Credentials** மற்றும் **Credentials Binding** | Token / password-ஐ பாதுகாப்பாகச் சேமித்து `withCredentials` மூலம் பயன்படுத்த | Docker Login stage | பிரிவு [6.4](#section-6-4) |
| **JUnit** | Unit test முடிவுகளை build page-ல் காட்ட | Unit Tests stage | தேவையில்லை |
| **Pipeline Graph View** (அல்லது பழைய **Pipeline: Stage View**) | Stages-ஐ படமாகக் காட்ட | Job page, Build page | பிரிவு [2.4](#section-2-4) (Appearance) |

**Maven, Docker, Docker Hub-க்குத் தனி plugin தேவையா?**

| Plugin | தேவையா? | காரணம் |
|--------|---------|--------|
| **Maven Integration** | ❌ தேவையில்லை | அது "Maven project" வகை job-க்கு மட்டும். Pipeline-ல் `mvnw.cmd` command போதும். |
| **Docker Pipeline** | ❌ தேவையில்லை (விருப்பம்) | `docker.build()` போன்ற Groovy methods தருகிறது. நாம் `docker build` command-ஐ நேரடியாகப் பயன்படுத்துகிறோம் — terminal-ல் நீங்கள் type செய்வது போலவே இருப்பதால் புரிந்துகொள்ள எளிது. |
| **Docker** (cloud) | ❌ தேவையில்லை | Docker containers-ஐ Jenkins agents-ஆகப் பயன்படுத்த — நமக்குத் தேவையில்லை. |
| Docker Hub-க்கு | ❌ தனி plugin இல்லை | **Credentials Binding** + `docker login` command போதும். |

> JDK, Maven-ஐ Jenkins-ல் அமைப்பது plugin மூலம் அல்ல — **Tools** பக்கத்தில் (பிரிவு 4).

### 2.3 Plugin நிறுவும் முறை

1. **Manage Jenkins** → **Plugins**.
2. **Installed plugins** tab → search பெட்டியில் plugin பெயரை (உ.தா. `JUnit`) type செய்யுங்கள். பட்டியலில் இருந்தால் ஏற்கனவே நிறுவப்பட்டுள்ளது ✅.
3. இல்லையெனில் **Available plugins** tab → search → plugin-க்கு அருகில் உள்ள checkbox-ஐ tick → **Install**.
4. Download திரையில் **Restart Jenkins when installation is complete and no jobs are running** என்பதை tick செய்யுங்கள்.
5. Restart முடிந்ததும் மீண்டும் login செய்து **Installed plugins**-ல் சரிபார்க்கவும்.

```text
┌─ Plugins › Available plugins ────────────────────────────────┐
│  Search: [ junit                        ]        [ Install ] │
│  [✓] JUnit    Allows JUnit-format test results to be ...     │
└──────────────────────────────────────────────────────────────┘
```

> 🏢 **அலுவலக network (proxy) பயன்படுத்தினால்:** plugins download ஆகவில்லை என்றால் **Manage Jenkins** → **Plugins** → **Advanced settings** → **HTTP Proxy Configuration**-ல் proxy server, port கொடுத்து **Submit** செய்யுங்கள் (விவரங்களை உங்கள் IT குழுவிடம் கேளுங்கள்).

<a id="section-2-4"></a>
### 2.4 Pipeline Graph View-ஐ job page-ல் காட்டுதல்

**Pipeline Graph View** நிறுவியிருந்தாலும், அது job page-ல் தானாகத் தெரியாது — இந்த setting இயல்பாக (default) off-ல் இருக்கும். அதுவரை job page-ல் பழைய **Stage View** அட்டவணை மட்டுமே தெரியும்.

1. **Manage Jenkins** → **Appearance**.
2. **Pipeline Stages** பகுதியில் **Show pipeline stages on job page**-ஐ tick செய்யுங்கள் (விருப்பம்: **Show stage names by default**, **Show stage durations by default**-ஐயும் tick செய்யலாம்).
3. **Pipeline Graph** பகுதியில் **Show pipeline graph on build page**-ஐ tick செய்யுங்கள்.
4. **Save** — restart தேவையில்லை.

```text
┌─ Manage Jenkins › Appearance ────────────────────────────────┐
│  Pipeline Stages                                             │
│  [✓] Show pipeline stages on job page                        │
│  [✓] Show stage names by default                             │
│  [✓] Show stage durations by default                         │
│  Pipeline Graph                                              │
│  [✓] Show pipeline graph on build page                       │
│                                                     [ Save ] │
└──────────────────────────────────────────────────────────────┘
```

முதல் build-க்குப் பிறகு job page-ல் புதிய **Stages** card தெரியும்.

> **பழைய Stage View அட்டவணையை நீக்க (விருப்பம்):** **Manage Jenkins** → **Plugins** → **Installed plugins** → `Pipeline: Stage View` → toggle-ஐ off செய்யுங்கள் → Jenkins restart (http://localhost:8079/safeRestart). Toggle சாம்பல் நிறத்தில் (greyed out) இருந்தால், வேறு plugin அதைச் சார்ந்துள்ளது — அப்படியே விட்டுவிடுங்கள்; job page-ல் இரண்டும் தெரியும்.

✅ **சரிபார்ப்பு:** மேலே உள்ள பட்டியலின் plugins அனைத்தும் **Installed plugins**-ல் உள்ளன.

---

<a id="section-3"></a>
## 3. Jenkins-ல் Git அமைப்பு

### 3.1 Git நிறுவுதல் மற்றும் சரிபார்த்தல்

1. https://git-scm.com/download/win → installer download → இயல்புநிலை options உடன் install செய்யுங்கள்.
2. புதிய PowerShell-ல்:

   ```powershell
   git --version
   where.exe git
   ```

   **எதிர்பார்க்கும் output:**

   ```text
   git version 2.xx.x.windows.1
   C:\Program Files\Git\cmd\git.exe
   ```

3. உங்கள் பெயர், email-ஐ அமைக்கவும் (commits-ல் இவை தெரியும்):

   ```powershell
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   ```

> 💡 `where.exe git` output `C:\Users\<you>\AppData\Local\Programs\Git\...` என்று இருந்தால், Git உங்கள் user-க்கு மட்டும் நிறுவப்பட்டுள்ளது. அப்போது Jenkins service உங்கள் Windows கணக்கில் இயங்க வேண்டும் (பிரிவு [5.3](#section-5-3)).

<a id="section-3-2"></a>
### 3.2 Jenkins-க்கு Git இருப்பிடத்தைச் சொல்லுதல்

1. **Manage Jenkins** → **Tools** → **Git installations**.
2. **Name:** `Default`
3. **Path to Git executable:** `git.exe` (Git, `PATH`-ல் இருந்தால் இது போதும்). வேலை செய்யவில்லை என்றால் `where.exe git` காட்டும் முழு path-ஐக் கொடுங்கள், உ.தா. `C:\Program Files\Git\cmd\git.exe`.
4. **Save**.

```text
┌─ Tools › Git installations ──────────────────────────────────┐
│  Name:                    Default                            │
│  Path to Git executable:  git.exe                            │
│  [ ] Install automatically                                   │
└──────────────────────────────────────────────────────────────┘
```

**(விருப்பம்) Jenkins-க்கான Git பயனர் பெயர்:** **Manage Jenkins** → **System** → **Git plugin** பகுதி → **Global Config user.name Value:** `Jenkins`, **Global Config user.email Value:** `jenkins@localhost` → **Save**. (Jenkins தானே commit / tag உருவாக்கினால் மட்டுமே இது தேவை; நம் pipeline-க்குத் தேவையில்லை.)

### 3.3 Project-ஐ GitHub-க்கு upload செய்தல்

**a) முதலில் — Docker Hub image பெயரை அமைத்தல்:** `Jenkinsfile`-ல் இந்த வரியை உங்கள் Docker Hub username-க்கு மாற்றுங்கள்:

```groovy
DOCKER_IMAGE   = 'your-dockerhub-username/simple-spring-boot-app'
```

உதாரணம்: Docker Hub username `johndoe` என்றால் → `'johndoe/simple-spring-boot-app'`.

**b) GitHub repository உருவாக்குதல்:**

1. https://github.com → வலது மேல் மூலையில் **+** → **New repository**.
2. **Repository name:** `simple-spring-boot-app`
3. **Public** (எளிது — Jenkins-க்கு GitHub credentials தேவையில்லை) அல்லது **Private**.
4. **Add a README file**, **.gitignore**, **license** — எதையும் tick செய்ய வேண்டாம் (project-ல் ஏற்கனவே உள்ளன).
5. **Create repository** → repository URL-ஐ copy செய்யுங்கள்: `https://github.com/<github-username>/simple-spring-boot-app.git`

**c) Code-ஐ push செய்தல்** — `simple-spring-boot-app` folder-க்குள் (`pom.xml` உள்ள folder) PowerShell-ல்:

```powershell
git init
git add .
git commit -m "Initial commit: Spring Boot app with Jenkins CI/CD"
git branch -M main
git remote add origin https://github.com/<github-username>/simple-spring-boot-app.git
git push -u origin main
```

முதல் push-ன் போது GitHub login-க்காக ஒரு browser window திறக்கும் (Git Credential Manager — Git for Windows-உடன் வருகிறது). Login செய்தால் போதும்; பிறகு Git அதை நினைவில் வைத்துக்கொள்ளும்.

**எதிர்பார்க்கும் output (கடைசி வரிகள்):**

```text
To https://github.com/<github-username>/simple-spring-boot-app.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

✅ **சரிபார்ப்பு:** GitHub repository page-ல் `pom.xml`, `mvnw.cmd`, `Jenkinsfile`, `Dockerfile` **முதல் நிலையிலேயே (root)** தெரிய வேண்டும். `target` folder இருக்கக் கூடாது (`.gitignore` அதைத் தவிர்க்கிறது).

> ⚠️ Parent folder-ஐ (`spring-jenkins`) push செய்ய வேண்டாம். Repository root-ல் `pom.xml` இருக்க வேண்டும்; இல்லையெனில் Jenkins-ல் `'.\mvnw.cmd' is not recognized` பிழை வரும்.

<a id="section-3-4"></a>
### 3.4 Authentication credentials (Private repository-க்கு மட்டும்)

Jenkins உங்கள் browser login-ஐப் பயன்படுத்த முடியாது. Private repository-க்கு **Personal Access Token (PAT)** தேவை.

**a) GitHub-ல் token உருவாக்குதல்:**

1. GitHub → உங்கள் profile படம் → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**.
2. **Token name:** `jenkins`; **Expiration:** உ.தா. 90 days (காலாவதியானால் புதுப்பிக்க வேண்டும்).
3. **Repository access:** **Only select repositories** → `simple-spring-boot-app`.
4. **Permissions** → **Repository permissions** → **Contents:** **Read-only**.
5. **Generate token** → token-ஐ **உடனே** copy செய்யுங்கள் (ஒருமுறை மட்டுமே காட்டப்படும்).

**b) Jenkins-ல் token-ஐச் சேமித்தல்:** **Manage Jenkins** → **Credentials** → (Stores scoped to Jenkins) **System** → **Global credentials (unrestricted)** → **Add Credentials**:

```text
┌─ New credentials ────────────────────────────────────────────┐
│  Kind:         Username with password                        │
│  Scope:        Global (Jenkins, nodes, items, all child items)│
│  Username:     <github-username>                             │
│  Password:     ••••••••••   (GitHub token)                   │
│  ID:           github-credentials                            │
│  Description:  GitHub token for Jenkins                      │
│                                                [ Create ]    │
└──────────────────────────────────────────────────────────────┘
```

<a id="section-3-5"></a>
### 3.5 Jenkins job-ல் repository URL அமைத்து code checkout செய்தல்

Pipeline job உருவாக்கும் போது (முழுப் படிகள்: பிரிவு [7.3](#section-7-3)) **Pipeline** பகுதியில்:

```text
┌─ Pipeline ───────────────────────────────────────────────────┐
│  Definition:         Pipeline script from SCM                │
│  SCM:                Git                                     │
│    Repository URL:   https://github.com/<github-username>/simple-spring-boot-app.git
│    Credentials:      - none -    (private என்றால்: github-credentials)
│    Branch Specifier: */main                                  │
│  Script Path:        Jenkinsfile                             │
│  [✓] Lightweight checkout                                    │
└──────────────────────────────────────────────────────────────┘
```

**இது எப்படி வேலை செய்கிறது?**

1. Jenkins முதலில் repository-லிருந்து `Jenkinsfile`-ஐ மட்டும் படிக்கிறது.
2. பிறகு Jenkinsfile-ன் **Checkout** stage-ல் உள்ள `checkout scm` command, மேலே அமைத்த அதே URL, branch, credentials-ஐப் பயன்படுத்தி முழு code-ஐ Jenkins **workspace**-க்கு clone செய்கிறது: `C:\ProgramData\Jenkins\.jenkins\workspace\simple-spring-boot-app`.

**மாற்று வழி — Pipeline script-ஐ Jenkins-ல் நேரடியாக paste செய்தால்** (Definition: **Pipeline script**): அங்கே `checkout scm` வேலை செய்யாது. பதிலாக:

```groovy
git branch: 'main',
    url: 'https://github.com/<github-username>/simple-spring-boot-app.git',
    credentialsId: 'github-credentials'   // public repository என்றால் இந்த வரியை நீக்கவும்
```

**எதிர்பார்க்கும் Console Output (Checkout stage):**

```text
Cloning the remote Git repository
Cloning repository https://github.com/<github-username>/simple-spring-boot-app.git
 > git.exe init C:\ProgramData\Jenkins\.jenkins\workspace\simple-spring-boot-app
 ...
Checking out Revision 1a2b3c4d5e... (refs/remotes/origin/main)
Commit message: "Initial commit: Spring Boot app with Jenkins CI/CD"
```

✅ **சரிபார்ப்பு:** Checkout stage பச்சை நிறம்; "Checking out Revision" எண், GitHub-ல் உள்ள கடைசி commit-ஓடு பொருந்துகிறது.

---

<a id="section-4"></a>
## 4. Jenkins-ல் Maven மற்றும் JDK அமைப்பு

### 4.1 Maven Wrapper — Maven-ஐ நிறுவாமலே build செய்தல்

Project-ல் **Maven Wrapper** உள்ளது:

| File | பயன் |
|------|------|
| `mvnw.cmd` | Windows-க்கான Maven Wrapper script |
| `mvnw` | Linux / macOS-க்கான script |
| `.mvn\wrapper\maven-wrapper.properties` | எந்த Maven version (3.9.16) பயன்படுத்த வேண்டும் என்பதை நிர்ணயிக்கிறது |

`mvnw.cmd` முதல் முறை இயங்கும் போது Maven 3.9.16-ஐத் தானாக download செய்கிறது.

**பலன்:** Jenkins-லும் ஒவ்வொரு developer கணினியிலும் **ஒரே Maven version** — "என் கணினியில் வேலை செய்கிறது, Jenkins-ல் இல்லை" என்ற பிரச்சினை குறையும். **நம் Jenkinsfile இந்த வழியையே பயன்படுத்துகிறது.**

```powershell
.\mvnw.cmd -v
```

**எதிர்பார்க்கும் output:**

```text
Apache Maven 3.9.16 (2bdd9fddda4b155ebf8000e807eb73fd829a51d5)
Maven home: C:\Users\<you>\.m2\wrapper\dists\apache-maven-3.9.16\...
Java version: 21.0.12.1, vendor: Oracle Corporation, runtime: C:\Program Files\Java\jdk-21.0.12.1
```

<a id="section-4-2"></a>
### 4.2 JDK-ஐ Jenkins-ல் அமைத்தல்

**எளிய வழி (பரிந்துரை):** `JAVA_HOME` **System variable** JDK 21-ஐக் காட்டினால் (பிரிவு [1.1](#section-1)), Jenkins அதைத் தானாகப் பயன்படுத்தும். வேறு எந்த அமைப்பும் தேவையில்லை.

> ⚠️ `JAVA_HOME`-ஐ மாற்றிய பின் **Jenkins service-ஐ restart** செய்யுங்கள் (Administrator PowerShell: `Restart-Service Jenkins`). Service தொடங்கும் போது மட்டுமே environment variables-ஐப் படிக்கும்.

**Tools மூலம் (பல JDK versions இருந்தால் — விருப்பம்):**

1. **Manage Jenkins** → **Tools** → **JDK installations** → **Add JDK**.
2. **Name:** `JDK21`; **Install automatically:** ☐ (tick எடுங்கள்); **JAVA_HOME:** `C:\Program Files\Java\jdk-21.0.12.1`.
3. **Save**.

```text
┌─ Tools › JDK installations ──────────────────────────────────┐
│  Name:       JDK21                                           │
│  JAVA_HOME:  C:\Program Files\Java\jdk-21.0.12.1             │
│  [ ] Install automatically                                   │
└──────────────────────────────────────────────────────────────┘
```

Jenkinsfile-ல் பயன்படுத்த: `tools { jdk 'JDK21' }` (கீழே 4.3-ல் உதாரணம்).

### 4.3 Maven-ஐ Jenkins Tools-ல் அமைத்தல் (விருப்பம்)

Maven Wrapper பயன்படுத்துவதால் **இது தேவையில்லை**. ஆனால் Maven-ஐ Jenkins நிர்வகிக்க வேண்டும் என்றால்:

1. **Manage Jenkins** → **Tools** → **Maven installations** → **Add Maven**.
2. **Name:** `Maven-3.9.16`
3. கீழே உள்ள இரண்டில் **ஒன்றை** தேர்வு செய்யுங்கள்:
   - **Install automatically** ✓ → **Install from Apache** → **Version:** `3.9.16` (Jenkins தானாக download செய்யும்), **அல்லது**
   - **Install automatically** ☐ → **MAVEN_HOME:** `C:\Program Files\Apache\apache-maven-3.9.16` (கணினியில் Maven ஏற்கனவே நிறுவப்பட்டிருந்தால்).
4. **Save**.

```text
┌─ Tools › Maven installations ────────────────────────────────┐
│  Name:  Maven-3.9.16                                         │
│  [✓] Install automatically                                   │
│       Install from Apache   Version: [ 3.9.16 ▼ ]            │
└──────────────────────────────────────────────────────────────┘
```

Jenkinsfile-ல் பயன்பாடு (உதாரணம் மட்டும்):

```groovy
pipeline {
    agent any
    tools {
        jdk   'JDK21'
        maven 'Maven-3.9.16'
    }
    stages {
        stage('Build') {
            steps {
                bat 'mvn -B clean package'
            }
        }
    }
}
```

> ஒரு project-ல் **ஒரு வழியை மட்டும்** பயன்படுத்துங்கள்: `mvnw.cmd` (நம் Jenkinsfile) **அல்லது** `tools { maven ... }` + `mvn`.

### 4.4 Spring Boot application-ஐ build செய்து executable JAR உருவாக்குதல்

**உங்கள் கணினியில்** (project folder-ல்):

```powershell
.\mvnw.cmd clean package
```

**எதிர்பார்க்கும் output:**

```text
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
[INFO] Building jar: D:\...\simple-spring-boot-app\target\simple-spring-boot-app-v0.jar
[INFO] BUILD SUCCESS
```

**Jenkins-ல்** pipeline இதை மூன்று stages-ஆகப் பிரிக்கிறது — எந்தப் படியில் தோல்வி என்பது தெளிவாகத் தெரியும்:

| Stage | Command | விளைவு |
|-------|---------|--------|
| Build | `.\mvnw.cmd -B clean compile` | பழைய `target` நீக்கப்பட்டு code compile ஆகிறது |
| Unit Tests | `.\mvnw.cmd -B test` | Tests இயங்குகின்றன |
| Package JAR | `.\mvnw.cmd -B package -DskipTests -DbuildNumber=%BUILD_NUMBER%` | `target\simple-spring-boot-app-v<N>.jar` உருவாகிறது |

- `-B` = batch mode — log சுத்தமாக இருக்கும்.
- `-DskipTests` = Unit Tests stage-ல் ஏற்கனவே tests ஓடியதால் மீண்டும் இயக்க வேண்டாம்.
- `-DbuildNumber=%BUILD_NUMBER%` = Jenkins build எண் JAR பெயரில் வரும் (build #42 → `simple-spring-boot-app-v42.jar`). Developer கணினியில் இது `v0`.
- **Executable JAR:** `pom.xml`-ல் உள்ள `spring-boot-maven-plugin`, application + அனைத்து dependencies + Tomcat server-ஐ ஒரே JAR-ல் சேர்க்கிறது. அதனால் `java -jar` மூலம் நேரடியாக இயக்கலாம்:

  ```powershell
  java -jar target\simple-spring-boot-app-v0.jar
  ```

- Jenkins இந்த JAR-ஐ **archive** செய்கிறது → build page → **Build Artifacts**-ல் download செய்யலாம்.

### 4.5 Unit tests இயக்கி முடிவுகளைச் சரிபார்த்தல்

**உங்கள் கணினியில்:**

```powershell
.\mvnw.cmd test
```

**எதிர்பார்க்கும் output:**

```text
[INFO] Running com.example.demo.controller.HelloControllerTest
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 1.9 s -- in com.example.demo.controller.HelloControllerTest
[INFO] Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

> Mockito அல்லது "A Java agent has been loaded dynamically" என்ற `WARNING` வரிகள் Java 21-ல் சாதாரணம் — பிரச்சினை இல்லை.

Test அறிக்கைகள் `target\surefire-reports\` folder-ல் XML files-ஆக உருவாகின்றன.

**Jenkins-ல்:** Unit Tests stage-ல் உள்ள `junit 'target/surefire-reports/*.xml'` அந்த XML files-ஐப் படித்து:

- Build page → **Test Result**: எத்தனை tests ஓடின, எது தோல்வி, ஏன்.
- Job page → **Test Result Trend** வரைபடம் (2 builds-க்குப் பிறகு தெரியும்).

<a id="section-4-6"></a>
### 4.6 Build தோல்வியைக் கையாளுதல்

**ஒரு stage தோல்வியடைந்தால் என்ன நடக்கும்?**

- அந்த stage **சிவப்பு** நிறமாகும்; அடுத்த stages இயங்காது (skip); build நிலை **FAILURE**.
- **Deploy** stage கடைசியில் இருப்பதால், தோல்வியான build ஏற்கனவே ஓடிக்கொண்டிருக்கும் (வேலை செய்யும்) container-ஐ மாற்றாது.
- `post { failure { ... } }` பகுதி ஒரு வழிகாட்டும் செய்தியை log-ல் காட்டும்.
- 30 நிமிடத்துக்கு மேல் ஓடும் build தானாக நிறுத்தப்படும் (`timeout`).

**பயிற்சி — test தோல்வியை வேண்டுமென்றே உருவாக்கிப் பாருங்கள்:**

1. `src\test\java\com\example\demo\controller\HelloControllerTest.java`-ல் எதிர்பார்க்கும் செய்தியின் கடைசி `.`-ஐ `!` என மாற்றுங்கள் (`successfully.` → `successfully!`).
2. Commit செய்து push → Jenkins build தொடங்கும்.
3. **Unit Tests** stage சிவப்பாகும். Console Output-ல்:

   ```text
   [ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0, Time elapsed: 1.904 s <<< FAILURE! -- in com.example.demo.controller.HelloControllerTest
   [ERROR] Failures:
   [ERROR]   HelloControllerTest.sayHello_returnsOkWithSuccessMessage:26 JSON path "$.message" expected:<Hello! Spring Boot application is running successfully!> but was:<Hello! Spring Boot application is running successfully.>
   [INFO] BUILD FAILURE
   ```

   பொருள்: test file-ன் 26-வது வரியில், எதிர்பார்த்தது `…successfully!`, ஆனால் application தந்தது `…successfully.`.

4. Build page → **Test Result**-லும் இதே விவரம் தெரியும்.
5. மாற்றத்தைத் திருப்பி (revert) push செய்யுங்கள் → build மீண்டும் பச்சை ✅.

**தோல்விக்குப் பிறகு செய்ய வேண்டியவை:**

1. Build page → **Pipeline Overview** (அல்லது **Stage View**) → சிவப்பு stage-ஐ கிளிக் → அதன் log.
2. **Console Output** → **Ctrl + F** → `ERROR` என்று தேடுங்கள் → **முதல்** ERROR தான் பெரும்பாலும் உண்மையான காரணம்.
3. Code-ஐச் சரிசெய்து push → புதிய build தானாகத் தொடங்கும்.
4. Jenkinsfile மாற்றத்தை commit செய்யாமலே சோதிக்க: build page → **Replay**.
5. தோல்வியான stage-லிருந்து மட்டும் மீண்டும் தொடங்க: build page → **Restart from Stage**.
6. பொதுவான Maven பிழைகளுக்கு: பிரிவு [8.4](#section-8-4).

---

<a id="section-5"></a>
## 5. Jenkins-ல் Docker அமைப்பு

### 5.1 Docker Desktop நிறுவுதல் மற்றும் அமைத்தல்

**a) Virtualization இயக்கத்தில் உள்ளதா?** Task Manager (**Ctrl + Shift + Esc**) → **Performance** → **CPU** → **Virtualization: Enabled** என்று இருக்க வேண்டும். **Disabled** என்றால் BIOS/UEFI-ல் Intel VT-x / AMD-V-ஐ enable செய்ய வேண்டும் (உங்கள் IT குழுவின் உதவி பெறுங்கள்).

**b) WSL 2 நிறுவுதல்** — **Administrator PowerShell**:

```powershell
wsl --install
```

முடிந்ததும் கணினியை **restart** செய்யுங்கள். பிறகு சரிபார்க்க:

```powershell
wsl --status
```

`Default Version: 2` என்று வர வேண்டும்.

**c) Docker Desktop நிறுவுதல்:**

1. https://www.docker.com/products/docker-desktop/ → **Download for Windows – AMD64**.
2. Installer-ஐ இயக்குங்கள் → **Use WSL 2 instead of Hyper-V (recommended)** ✓ → **OK** → முடிந்ததும் **Close and restart** (அல்லது sign out செய்து மீண்டும் sign in).
3. Docker Desktop-ஐத் திறந்து license-ஐ ஏற்றுக்கொள்ளுங்கள். (விருப்பம்) Docker Hub கணக்கில் sign in செய்யுங்கள்.

அதிகாரப்பூர்வ நிறுவல் வழிகாட்டி: https://docs.docker.com/desktop/setup/install/windows-install/

**d) அமைப்புகள்:**

- **Settings** → **General** → **Start Docker Desktop when you sign in to your computer** ✓ → **Apply**.
- **Linux containers** mode (இயல்புநிலை) — system tray-ல் Docker icon-ஐ வலது click செய்தால் "Switch to Windows containers…" என்று தெரிந்தால், நீங்கள் Linux mode-ல் உள்ளீர்கள் ✅.

**e) சரிபார்ப்பு:**

```powershell
docker version
docker run --rm hello-world
```

**எதிர்பார்க்கும் output (சுருக்கம்):**

```text
Client:
 Version:           29.x.x
 ...
Server: Docker Desktop 4.x.x
 Engine:
  Version:          29.x.x
  OS/Arch:          linux/amd64
...
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

**Client**, **Server** இரண்டும் தெரிய வேண்டும். **Server** பகுதி இல்லையெனில் Docker Desktop இயங்கவில்லை.

> ⚠️ நீங்கள் Windows-ல் sign in செய்திருக்கும் வரை மட்டுமே Docker Desktop இயங்கும். அப்போது மட்டுமே pipeline-ன் Docker stages வேலை செய்யும்.

<a id="section-5-2"></a>
### 5.2 Jenkins ஏன் Git, Docker-ஐப் பார்க்க முடியாது?

Jenkins installer-ல் இயல்புநிலையாக service **LocalSystem** என்ற சிறப்பு Windows கணக்கில் இயங்குகிறது. ஆனால்:

- Git, Docker Desktop உங்கள் user-க்கு மட்டும் நிறுவப்பட்டிருக்கலாம் — அவற்றின் folders உங்கள் `PATH`-ல் மட்டுமே இருக்கும்.
- Docker-ன் image build கருவி (`buildx`), Docker settings, Docker Hub login — அனைத்தும் உங்கள் user profile-ல் (`C:\Users\<you>\.docker`) உள்ளன.

LocalSystem இவற்றைப் பார்க்க முடியாது → `'docker' is not recognized`, `'git' is not recognized` போன்ற பிழைகள் வரும்.

**தீர்வு:** Jenkins service-ஐ **உங்கள் Windows கணக்கில்** இயக்குவது. அப்போது terminal-ல் நீங்கள் பயன்படுத்தும் அதே Git, Docker, Maven cache-ஐ Jenkins-உம் பயன்படுத்தும்.

<a id="section-5-3"></a>
### 5.3 Jenkins service-ஐ உங்கள் Windows கணக்கில் இயக்குதல்

> Installer-ல் ஏற்கனவே **Run service as local or domain user** தேர்வு செய்திருந்தால் இந்தப் பகுதியைத் தவிர்த்து நேரடியாக [5.4](#section-5-4) சரிபார்ப்புக்குச் செல்லுங்கள்.

**a) உங்கள் கணக்குப் பெயர்** — **சாதாரண** PowerShell:

```powershell
whoami
```

Output `yourdomain\yourname` போல இருக்கும். இதைக் கீழே பயன்படுத்துங்கள்.

**b) Jenkins folders-க்கு அனுமதி வழங்குதல்** — **Administrator PowerShell** (`YOURDOMAIN\yourname`-ஐ மாற்றவும்):

```powershell
icacls "C:\ProgramData\Jenkins" /grant "YOURDOMAIN\yourname:(OI)(CI)F" /T
icacls "C:\Program Files\Jenkins" /grant "YOURDOMAIN\yourname:(OI)(CI)F" /T
```

> இந்தக் கணினியில் Jenkins `D:\Jenkins`-ல் நிறுவப்பட்டுள்ளது — எனவே இரண்டாவது command-ல் `"D:\Jenkins"` பயன்படுத்துங்கள்.

`(OI)(CI)F` = folder, அதன் sub-folders, files அனைத்துக்கும் முழு அனுமதி (Full control). **எதிர்பார்க்கும் output:**

```text
Successfully processed 1234 files; Failed processing 0 files
```

**c) Service கணக்கை மாற்றுதல்:**

1. **Win + R** → `services.msc` → **Enter**.
2. **Jenkins** → வலது click → **Properties** → **Log On** tab.
3. **This account** → `YOURDOMAIN\yourname`, **Password**, **Confirm password** → **OK**.
4. "The account … has been granted the Log On As A Service right" என்ற செய்தி வந்தால் **OK**.
5. **Jenkins** → வலது click → **Restart**. ஒரு நிமிடம் காத்திருந்து http://localhost:8079 திறக்கவும்.

```text
┌─ Jenkins Properties (Local Computer) › Log On ───────────────┐
│  ( ) Local System account                                    │
│  (•) This account:      YOURDOMAIN\yourname    [ Browse… ]   │
│      Password:          ••••••••••                           │
│      Confirm password:  ••••••••••                           │
│                                 [ OK ]  [ Cancel ]  [ Apply ]│
└──────────────────────────────────────────────────────────────┘
```

> ⚠️ உங்கள் Windows password மாறும் போது, இந்த **Log On** tab-லும் புதிய password கொடுக்க வேண்டும் — இல்லையெனில் அடுத்த restart-ல் Jenkins தொடங்காது.

<a id="section-5-4"></a>
### 5.4 சரிபார்ப்பு: "tools-check" pipeline

1. Jenkins → **New Item** → name: `tools-check` → **Pipeline** → **OK**.
2. **Pipeline** பகுதியில் **Definition: Pipeline script** என்றே வைத்து, கீழே உள்ளதை paste செய்யுங்கள்:

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

3. **Save** → **Build Now** → build எண்ணைக் கிளிக் → **Console Output**.

**எதிர்பார்க்கும் output (சுருக்கம்):**

```text
C:\ProgramData\Jenkins\.jenkins\workspace\tools-check>whoami
yourdomain\yourname

C:\ProgramData\Jenkins\.jenkins\workspace\tools-check>echo JAVA_HOME=C:\Program Files\Java\jdk-21.0.12.1
JAVA_HOME=C:\Program Files\Java\jdk-21.0.12.1

C:\ProgramData\Jenkins\.jenkins\workspace\tools-check>git --version
git version 2.xx.x.windows.1

C:\ProgramData\Jenkins\.jenkins\workspace\tools-check>docker version
Client: ...
Server: Docker Desktop ...

C:\ProgramData\Jenkins\.jenkins\workspace\tools-check>docker buildx version
github.com/docker/buildx v0.xx.x ...
Finished: SUCCESS
```

- `whoami` → **உங்கள்** கணக்கு (`nt authority\system` அல்ல).
- அனைத்தும் version காட்டினால் ✅. பிறகு `tools-check` job-ஐ நீக்கிவிடலாம்.

**`whoami` சரி, ஆனால் `git` அல்லது `docker` "not recognized" என்றால்:**

1. உங்கள் terminal-ல் `where.exe git`, `where.exe docker` இயக்கி, folder பகுதியைக் குறித்துக்கொள்ளுங்கள்.
2. **Manage Jenkins** → **System** → **Global properties** → **Environment variables** ✓ → **Add**:
   - **Name:** `PATH+TOOLS`
   - **Value:** இரண்டு folders-ஐ `;` கொண்டு பிரித்து, உ.தா. `C:\Program Files\Git\cmd;C:\Program Files\Docker\Docker\resources\bin`
3. **Save** → `tools-check`-ஐ மீண்டும் இயக்குங்கள். (`PATH+TOOLS` = "இந்த folders-ஐ `PATH`-ன் முன்னால் சேர்")

### 5.5 Spring Boot application-க்கான Dockerfile

Project root-ல் (`pom.xml` அருகில்) உள்ள `Dockerfile`:

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

| வரி | விளக்கம் |
|-----|---------|
| `FROM eclipse-temurin:21-jre` | Java 21 runtime (JRE) கொண்ட அதிகாரப்பூர்வ base image. JAR-ஐ ஏற்கனவே Maven build செய்துவிட்டதால் JDK, Maven தேவையில்லை — image சிறியதாகும். |
| `RUN groupadd … && useradd …` | `spring` என்ற சாதாரண (root அல்லாத) user-ஐ உருவாக்குகிறது — பாதுகாப்புக்காக. |
| `WORKDIR /app` | Container-க்குள் வேலை செய்யும் folder. |
| `COPY target/*.jar app.jar` | Maven உருவாக்கிய `simple-spring-boot-app-v<N>.jar`-ஐ `app.jar` என்ற நிலையான பெயரில் copy செய்கிறது. |
| `USER spring` | இனி application `spring` user-ஆக (root அல்லாமல்) இயங்கும். |
| `EXPOSE 8080` | Application 8080 port-ல் கேட்கிறது என்று குறிக்கிறது (`application.yml`-ன் `server.port`). |
| `ENTRYPOINT ["java", "-jar", "app.jar"]` | Container தொடங்கும் போது இயங்கும் command. |

**`.dockerignore`** (அதே folder-ல்):

```text
*
!target/*.jar
```

`*` = அனைத்தையும் தவிர்; `!target/*.jar` = JAR-ஐ மட்டும் அனுமதி. அதனால் Docker build-க்கு சுமார் 20 MB JAR மட்டுமே அனுப்பப்படும் — build வேகமாகும், source code image-க்குள் செல்லாது.

**உங்கள் கணினியில் சோதித்தல்** (project folder-ல்):

```powershell
.\mvnw.cmd clean package
docker build -t simple-spring-boot-app:local .
docker run -d --name simple-spring-boot-app-local -p 8080:8080 simple-spring-boot-app:local
Start-Sleep -Seconds 10
curl.exe http://localhost:8080/api/hello
docker rm -f simple-spring-boot-app-local
```

**எதிர்பார்க்கும் output (முக்கிய வரிகள்):**

```text
#6 transferring context: 19.97MB 1.3s done
#10 naming to docker.io/library/simple-spring-boot-app:local done
{"message":"Hello! Spring Boot application is running successfully."}
```

> 💡 PowerShell-ல் `curl.exe` என்று `.exe` சேர்த்து எழுதுங்கள். வெறும் `curl` என்பது Windows PowerShell-ல் வேறு command (`Invoke-WebRequest`).

### 5.6 Jenkins Docker image-ஐ எப்படி உருவாக்குகிறது?

Pipeline-ன் **Docker Build** stage:

```groovy
bat 'docker build -t %DOCKER_IMAGE%:%IMAGE_TAG% -t %DOCKER_IMAGE%:latest .'
```

1. அதற்கு முன் **Package JAR** stage `target\simple-spring-boot-app-v<N>.jar`-ஐ உருவாக்கியுள்ளது.
2. `docker build … .` — Jenkins workspace-ல் உள்ள `Dockerfile`-ஐப் படிக்கிறது. கடைசி `.` = build context (தற்போதைய folder).
3. `.dockerignore` காரணமாக JAR மட்டுமே Docker-க்கு அனுப்பப்படுகிறது.
4. Image-க்கு இரண்டு **tags** வழங்கப்படுகின்றன:
   - `<docker-hub-username>/simple-spring-boot-app:v<N>` — இந்த build-ன் நிலையான version (உ.தா. `v42`).
   - `<docker-hub-username>/simple-spring-boot-app:latest` — எப்போதும் புதிய version.

**எதிர்பார்க்கும் output:**

```text
#1 [internal] load build definition from Dockerfile
...
#6 [internal] load build context
#6 transferring context: 19.97MB 1.3s done
...
#10 naming to docker.io/<docker-hub-username>/simple-spring-boot-app:v42 done
#10 naming to docker.io/<docker-hub-username>/simple-spring-boot-app:latest done
```

✅ **சரிபார்ப்பு:** `docker images <docker-hub-username>/simple-spring-boot-app` → `v42`, `latest` tags தெரியும்.

---

<a id="section-6"></a>
## 6. Docker Hub அமைப்பு

### 6.1 Docker Hub கணக்கு உருவாக்குதல்

1. https://hub.docker.com → **Sign up**.
2. **Username** (சிறிய எழுத்துகள் மட்டும் — image பெயரின் முதல் பகுதி இதுவே), email, password கொடுத்து கணக்கை உருவாக்குங்கள்.
3. உங்கள் email-க்கு வரும் இணைப்பைக் கிளிக் செய்து கணக்கை உறுதிப்படுத்துங்கள் (verify).

### 6.2 Repository உருவாக்குதல்

1. Docker Hub → **Repositories** → **Create a repository**.
2. **Namespace:** உங்கள் username; **Repository Name:** `simple-spring-boot-app`; **Visibility:** **Public** → **Create**.

```text
┌─ Create repository ──────────────────────────────────────────┐
│  Namespace:        <docker-hub-username>                     │
│  Repository Name:  simple-spring-boot-app                    │
│  Visibility:       (•) Public    ( ) Private                 │
│                                                [ Create ]    │
└──────────────────────────────────────────────────────────────┘
```

> Repository-ஐ நீங்கள் உருவாக்காவிட்டாலும், முதல் push-ன் போது Docker Hub அதைத் தானாக உருவாக்கும்.

### 6.3 Access token உருவாக்குதல்

Jenkins உங்கள் Docker Hub password-க்குப் பதிலாக **access token**-ஐப் பயன்படுத்தும். (Password-ஐ மாற்றாமலே token-ஐ எப்போது வேண்டுமானாலும் ரத்து செய்யலாம்.)

1. Docker Hub → வலது மேல் மூலையில் avatar → **Account settings** → **Personal access tokens** → **Generate new token**.
2. **Access token description:** `jenkins`; **Expiration date:** உங்கள் விருப்பம்; **Access permissions:** **Read & Write** (push செய்ய Write அனுமதி தேவை).
3. **Generate** → token-ஐ (`dckr_pat_…`) **உடனே** copy செய்யுங்கள் (ஒருமுறை மட்டுமே காட்டப்படும்).

<a id="section-6-4"></a>
### 6.4 Jenkins-ல் Docker Hub credentials-ஐப் பாதுகாப்பாகச் சேமித்தல்

**Manage Jenkins** → **Credentials** → **System** → **Global credentials (unrestricted)** → **Add Credentials**:

```text
┌─ New credentials ────────────────────────────────────────────┐
│  Kind:         Username with password                        │
│  Scope:        Global                                        │
│  Username:     <docker-hub-username>                         │
│  Password:     ••••••••••   (Docker Hub access token)        │
│  ID:           dockerhub-credentials                         │
│  Description:  Docker Hub token for Jenkins                  │
│                                                [ Create ]    │
└──────────────────────────────────────────────────────────────┘
```

**இது ஏன் பாதுகாப்பானது?**

- Jenkins credentials-ஐ **encrypt** செய்து சேமிக்கிறது; சேமித்த பின் திரையில் மீண்டும் காட்டாது.
- Token `Jenkinsfile`-லோ Git-லோ இல்லை — `dockerhub-credentials` என்ற **ID** மட்டுமே Jenkinsfile-ல் உள்ளது.
- `withCredentials { … }` block-க்குள் மட்டுமே token கிடைக்கும்; log-ல் `****` என்று மறைக்கப்படும்.

> ⚠️ **ID சரியாக `dockerhub-credentials`** என்று இருக்க வேண்டும் — Jenkinsfile இந்த ID-ஐத் தேடுகிறது.

**Token-ஐப் புதுப்பிக்க (rotate):** **Credentials** → `dockerhub-credentials` → **Update** → புதிய token → **Save**. Jenkinsfile-ல் எந்த மாற்றமும் தேவையில்லை.

### 6.5 Docker Hub-ல் authenticate செய்து image-ஐ push செய்தல்

**Pipeline-ல் — Docker Login stage:**

```groovy
withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials',
                                  usernameVariable: 'DOCKERHUB_USER',
                                  passwordVariable: 'DOCKERHUB_TOKEN')]) {
    bat 'echo %DOCKERHUB_TOKEN%| docker login -u %DOCKERHUB_USER% --password-stdin'
}
```

- `withCredentials` → credential-ன் username-ஐ `DOCKERHUB_USER`, token-ஐ `DOCKERHUB_TOKEN` என்ற variables-ஆக **தற்காலிகமாக** தருகிறது.
- `--password-stdin` → token command line-ல் தெரியாமல், உள்ளீடாக (stdin) அனுப்பப்படுகிறது.
- `%DOCKERHUB_TOKEN%|` — `|`-க்கு முன் **இடைவெளி (space) வைக்காதீர்கள்**. வைத்தால் Windows token-ன் இறுதியில் ஒரு space சேர்த்துவிடும் → login தோல்வியடையும்.

**Docker Push stage:**

```groovy
bat 'docker push %DOCKER_IMAGE%:%IMAGE_TAG%'
bat 'docker push %DOCKER_IMAGE%:latest'
```

**எதிர்பார்க்கும் output:**

```text
Login Succeeded
...
The push refers to repository [docker.io/<docker-hub-username>/simple-spring-boot-app]
...
v42: digest: sha256:3c1e… size: 856
...
latest: digest: sha256:3c1e… size: 856
```

**உங்கள் terminal-ல் கைமுறையாகச் சோதிக்க** (5.5-ல் உருவாக்கிய `simple-spring-boot-app:local` image-ஐப் பயன்படுத்தி):

```powershell
docker login -u <docker-hub-username>
# "Password:" கேட்கும் போது access token-ஐ paste செய்து Enter (திரையில் தெரியாது)
docker tag simple-spring-boot-app:local <docker-hub-username>/simple-spring-boot-app:manual-test
docker push <docker-hub-username>/simple-spring-boot-app:manual-test
```

✅ **சரிபார்ப்பு:** browser-ல் `https://hub.docker.com/r/<docker-hub-username>/simple-spring-boot-app/tags` → `v42`, `latest` (மற்றும் `manual-test`) tags தெரியும்.

### 6.6 Docker Hub-லிருந்து image-ஐ pull செய்தல்

**Pipeline-ல் — Docker Pull stage:**

```groovy
bat 'docker rmi %DOCKER_IMAGE%:%IMAGE_TAG% %DOCKER_IMAGE%:latest'
bat 'docker pull %DOCKER_IMAGE%:%IMAGE_TAG%'
```

முதலில் local copy நீக்கப்படுகிறது (`docker rmi`) — அதனால் அடுத்த `docker pull` உண்மையிலேயே Docker Hub-லிருந்து download செய்கிறது. (உண்மையான projects-ல் pull, run இரண்டும் வேறொரு server-ல் நடக்கும்; இங்கே அதே கணினியில் அதை அப்படியே செய்து பார்க்கிறோம்.)

**எதிர்பார்க்கும் output:**

```text
Untagged: <docker-hub-username>/simple-spring-boot-app:v42
Untagged: <docker-hub-username>/simple-spring-boot-app:latest
...
v42: Pulling from <docker-hub-username>/simple-spring-boot-app
...
Status: Downloaded newer image for <docker-hub-username>/simple-spring-boot-app:v42
docker.io/<docker-hub-username>/simple-spring-boot-app:v42
```

**Docker உள்ள வேறு எந்தக் கணினியிலும்:**

```powershell
docker pull <docker-hub-username>/simple-spring-boot-app:latest
docker run -d --name simple-spring-boot-app -p 8080:8080 <docker-hub-username>/simple-spring-boot-app:latest
```

(Public repository-க்கு login தேவையில்லை. Private என்றால் முதலில் `docker login`.)

---

<a id="section-7"></a>
## 7. Jenkins Pipeline செயல்படுத்துதல்

### 7.1 Pipeline-ன் 10 stages

| # | Stage (Jenkinsfile-ல் பெயர்) | என்ன செய்கிறது |
|---|------------------------------|----------------|
| 1 | **Checkout** | GitHub-லிருந்து source code-ஐ எடுக்கிறது |
| 2 | **Build** | Maven மூலம் Spring Boot application-ஐ compile செய்கிறது |
| 3 | **Unit Tests** | Unit tests இயக்கி முடிவுகளைப் பதிவு செய்கிறது |
| 4 | **Package JAR** | Executable JAR-ஐ உருவாக்கி archive செய்கிறது |
| 5 | **Docker Build** | JAR-லிருந்து Docker image உருவாக்குகிறது |
| 6 | **Docker Login** | Docker Hub-ல் authenticate செய்கிறது |
| 7 | **Docker Push** | Image-ஐ Docker Hub-க்கு push செய்கிறது |
| 8 | **Docker Pull** | Image-ஐ Docker Hub-லிருந்து pull செய்கிறது |
| 9 | **Deploy** | Image-ஐ container-ஆக இயக்குகிறது |
| 10 | **Smoke Test** | Application வெற்றிகரமாக இயங்குகிறதா என்று சரிபார்க்கிறது |

### 7.2 தொடங்கும் முன் சரிபார்ப்புப் பட்டியல் (Checklist)

- [ ] Jenkins service உங்கள் Windows கணக்கில் இயங்குகிறது; `tools-check` வெற்றி ([5.3](#section-5-3), [5.4](#section-5-4))
- [ ] தேவையான plugins நிறுவப்பட்டுள்ளன ([2](#section-2))
- [ ] `Jenkinsfile`-ல் `DOCKER_IMAGE` மாற்றப்பட்டு GitHub-க்கு push செய்யப்பட்டுள்ளது ([3.3](#section-3))
- [ ] `dockerhub-credentials` சேமிக்கப்பட்டுள்ளது ([6.4](#section-6-4)); private repository என்றால் `github-credentials`-ம் ([3.4](#section-3-4))
- [ ] Docker Desktop இயங்குகிறது ([5.1](#section-5))
- [ ] Port 8080 காலியாக உள்ளது — `netstat -ano | findstr :8080` எதையும் காட்டக் கூடாது

<a id="section-7-3"></a>
### 7.3 Pipeline job உருவாக்குதல்

1. Jenkins Dashboard → **New Item**.
2. **Enter an item name:** `simple-spring-boot-app` → **Pipeline** → **OK**.
3. **Triggers** பகுதி: **GitHub hook trigger for GITScm polling** ✓ (பிரிவு [7.6](#section-7-6)).
4. **Pipeline** பகுதி ([3.5](#section-3-5)-ல் உள்ளபடி):
   - **Definition:** Pipeline script from SCM
   - **SCM:** Git
   - **Repository URL:** `https://github.com/<github-username>/simple-spring-boot-app.git`
   - **Credentials:** - none - (private என்றால் `github-credentials`)
   - **Branch Specifier:** `*/main`
   - **Script Path:** `Jenkinsfile`
5. **Save** → **Build Now**.

முதல் build சில நிமிடங்கள் ஆகும் (Maven, dependencies, Java base image download ஆகின்றன). Webhook வேலை செய்ய **முதல் build-ஐ கைமுறையாக** இயக்க வேண்டும்.

### 7.4 முழு Jenkinsfile

இது project root-ல் உள்ள `Jenkinsfile`-ன் அதே உள்ளடக்கம்:

```groovy
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

### 7.5 Jenkinsfile — ஒவ்வொரு பகுதியின் விளக்கம்

#### பொதுவான பகுதிகள்

**`agent any`** — Jenkins-ன் எந்தக் கணினியிலும் (இங்கே உங்கள் Windows கணினி) pipeline-ஐ இயக்கலாம்.

**`environment`** — பல stages பயன்படுத்தும் மதிப்புகள், ஒரே இடத்தில்:

| Variable | மதிப்பு | பொருள் |
|----------|--------|--------|
| `DOCKER_IMAGE` | `<docker-hub-username>/simple-spring-boot-app` | Docker Hub repository — **நீங்கள் மாற்ற வேண்டியது** |
| `IMAGE_TAG` | `v${env.BUILD_NUMBER}` | Build #42 → `v42` (JAR பெயரிலும் அதே எண்) |
| `CONTAINER_NAME` | `simple-spring-boot-app` | இயங்கும் container-ன் பெயர் |
| `HOST_PORT` | `8080` | உங்கள் கணினியில் application கிடைக்கும் port |

**`options`:**

| Option | பொருள் |
|--------|--------|
| `skipDefaultCheckout()` | Jenkins தானாகச் செய்யும் checkout-ஐ நிறுத்துகிறது — நம் **Checkout** stage அதைச் செய்வதால், stage view-ல் தனியாகத் தெரியும் |
| `timeout(time: 30, unit: 'MINUTES')` | 30 நிமிடத்துக்கு மேல் ஓடும் build நிறுத்தப்படும் |
| `buildDiscarder(logRotator(numToKeepStr: '10'))` | கடைசி 10 builds மட்டும் வைக்கப்படும் (disk இடம் மிச்சம்) |

**`bat` commands பற்றி சில விதிகள்:**

- `bat` = Windows Command Prompt-ல் command இயக்குகிறது.
- `%NAME%` = Windows-ல் variable மதிப்பைப் படிக்கும் முறை (உ.தா. `%DOCKER_IMAGE%`, Jenkins தரும் `%BUILD_NUMBER%`).
- **Single quotes** `'…'` = Jenkins உரையை மாற்றாமல் அப்படியே Windows-க்கு அனுப்புகிறது; Windows `%NAME%`-ஐ மதிப்பால் மாற்றுகிறது.
- `'.\\mvnw.cmd'` = Groovy-ல் `\`-ஐ இரண்டு முறை எழுத வேண்டும்; Windows-க்கு `.\mvnw.cmd` ("இந்த folder-ல் உள்ள `mvnw.cmd`") என்று போய்ச் சேரும்.

#### Stage 1 – Checkout

```groovy
checkout scm
```

- **என்ன செய்கிறது:** Jenkins job-ல் அமைத்த GitHub repository-லிருந்து (URL, branch, credentials) சமீபத்திய code-ஐ workspace-க்கு எடுக்கிறது.
- **வெற்றி:** `Checking out Revision 1a2b3c… (refs/remotes/origin/main)`
- **தோல்வியானால்:** பிரிவு [8.3](#section-8-3) (Git பிழைகள்).

#### Stage 2 – Build

```groovy
bat '.\\mvnw.cmd -B clean compile'
```

- **என்ன செய்கிறது:** பழைய `target` folder-ஐ நீக்கி (`clean`), Java code-ஐ compile செய்கிறது.
- **வெற்றி:** `BUILD SUCCESS`
- **தோல்வியானால்:** `COMPILATION ERROR` + file பெயர், வரி எண் → code-ஐச் சரிசெய்யுங்கள். JDK / Maven பிழைகள் → [8.4](#section-8-4).

#### Stage 3 – Unit Tests

```groovy
bat '.\\mvnw.cmd -B test'
...
post { always { junit 'target/surefire-reports/*.xml' } }
```

- **என்ன செய்கிறது:** Unit tests-ஐ இயக்குகிறது. `post { always { … } }` = tests தோல்வியடைந்தாலும் முடிவுகள் Jenkins-ல் பதிவாகும்.
- **வெற்றி:** `Tests run: 1, Failures: 0, Errors: 0, Skipped: 0`; build page → **Test Result**.
- **தோல்வியானால்:** [4.6](#section-4-6).

#### Stage 4 – Package JAR

```groovy
bat '.\\mvnw.cmd -B package -DskipTests -DbuildNumber=%BUILD_NUMBER%'
archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
```

- **என்ன செய்கிறது:** `target\simple-spring-boot-app-v<N>.jar` என்ற executable JAR-ஐ உருவாக்குகிறது. `archiveArtifacts` → JAR-ஐ build உடன் சேமிக்கிறது (**Build Artifacts**). `fingerprint: true` → எந்த build இந்த JAR-ஐ உருவாக்கியது என்று Jenkins கண்காணிக்கும்.
- **வெற்றி:** `Building jar: …\target\simple-spring-boot-app-v42.jar`

#### Stage 5 – Docker Build

```groovy
bat 'docker build -t %DOCKER_IMAGE%:%IMAGE_TAG% -t %DOCKER_IMAGE%:latest .'
```

- **என்ன செய்கிறது:** `Dockerfile` மூலம் JAR-லிருந்து image உருவாக்கி, `v<N>`, `latest` என்ற இரண்டு tags வழங்குகிறது (விவரம்: [5.6](#section-5)).
- **வெற்றி:** `naming to docker.io/<docker-hub-username>/simple-spring-boot-app:v42 done`

#### Stage 6 – Docker Login

```groovy
withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', ...)]) {
    bat 'echo %DOCKERHUB_TOKEN%| docker login -u %DOCKERHUB_USER% --password-stdin'
}
```

- **என்ன செய்கிறது:** Jenkins-ல் சேமித்த token மூலம் Docker Hub-ல் login செய்கிறது (விவரம்: [6.5](#section-6)).
- **வெற்றி:** `Login Succeeded`. Log-ல் username, token இரண்டும் `****` என்று மறைக்கப்படும்.

#### Stage 7 – Docker Push

```groovy
bat 'docker push %DOCKER_IMAGE%:%IMAGE_TAG%'
bat 'docker push %DOCKER_IMAGE%:latest'
```

- **என்ன செய்கிறது:** இரண்டு tags-ஐயும் Docker Hub-க்கு upload செய்கிறது.
- **வெற்றி:** `v42: digest: sha256:…` மற்றும் `latest: digest: sha256:…`; Docker Hub-ன் **Tags** பக்கத்தில் தெரியும்.

#### Stage 8 – Docker Pull

```groovy
bat 'docker rmi %DOCKER_IMAGE%:%IMAGE_TAG% %DOCKER_IMAGE%:latest'
bat 'docker pull %DOCKER_IMAGE%:%IMAGE_TAG%'
```

- **என்ன செய்கிறது:** Local copy-ஐ நீக்கி, Docker Hub-லிருந்து அதே version-ஐ மீண்டும் download செய்கிறது — Docker Hub-ல் உள்ள image சரியாக உள்ளது என்பதை நிரூபிக்கிறது.
- **வெற்றி:** `Status: Downloaded newer image for <docker-hub-username>/simple-spring-boot-app:v42`

#### Stage 9 – Deploy (Container-ஆக இயக்குதல்)

```groovy
bat 'docker rm -f %CONTAINER_NAME% || exit /b 0'
bat 'docker run -d --name %CONTAINER_NAME% -p %HOST_PORT%:8080 --restart unless-stopped %DOCKER_IMAGE%:%IMAGE_TAG%'
```

| பகுதி | பொருள் |
|-------|--------|
| `docker rm -f %CONTAINER_NAME%` | முந்தைய build-ன் container-ஐ நிறுத்தி நீக்குகிறது |
| `\|\| exit /b 0` | Container இல்லை என்றால் (முதல் build) வரும் பிழையைப் புறக்கணிக்கிறது |
| `-d` | பின்னணியில் (detached) இயக்கு |
| `--name %CONTAINER_NAME%` | Container-க்குப் பெயர் |
| `-p %HOST_PORT%:8080` | உங்கள் கணினியின் 8080 port → container-ன் 8080 port |
| `--restart unless-stopped` | கணினி அல்லது Docker restart ஆனாலும், நீங்கள் நீக்கும் வரை container தானாகத் தொடங்கும் |
| `%DOCKER_IMAGE%:%IMAGE_TAG%` | இப்போது pull செய்த சரியான version (உ.தா. `v42`) |

- **வெற்றி:** 64 எழுத்துகள் கொண்ட container ID; `docker ps` → `Up`, `0.0.0.0:8080->8080/tcp`.

#### Stage 10 – Smoke Test (Application சரிபார்ப்பு)

```groovy
bat 'curl --fail --silent --show-error --retry 10 --retry-delay 3 --retry-all-errors http://localhost:%HOST_PORT%/api/hello'
```

| பகுதி | பொருள் |
|-------|--------|
| `--fail` | HTTP பிழை (404, 500) வந்தால் stage தோல்வியடையும் |
| `--silent --show-error` | தேவையற்ற progress காட்டாது; பிழை மட்டும் காட்டும் |
| `--retry 10 --retry-delay 3 --retry-all-errors` | Application தொடங்க சில விநாடிகள் ஆகும் — 3 விநாடி இடைவெளியில் 10 முறை (சுமார் 30 விநாடி) முயற்சிக்கும் |

- **வெற்றி:**

  ```text
  curl: (52) Empty reply from server
  {"message":"Hello! Spring Boot application is running successfully."}
  ```

  முதல் வரி `curl: (52) …` சாதாரணம் — அப்போது application இன்னும் தொடங்கிக்கொண்டிருந்தது; curl மீண்டும் முயன்று வெற்றி பெற்றது.

#### `post` பகுதி

- `success` → "Deployed … open http://localhost:8080/api/hello" என்று log-ல் காட்டும்.
- `failure` → Console Output-ல் முதல் ERROR-ஐப் பார்க்கச் சொல்லும் செய்தி.

> **ஏன் `docker logout` இல்லை?** Jenkins உங்கள் Windows கணக்கில் இயங்குவதால் உங்கள் Docker login-ஐப் பகிர்ந்துகொள்கிறது. Logout செய்தால் உங்கள் Docker Desktop-ம் sign out ஆகிவிடும். தனி build server-ல் `post { always { bat 'docker logout' } }` சேர்க்கலாம்.

<a id="section-7-6"></a>
### 7.6 GitHub-க்கு push செய்தவுடன் தானாக build (Webhook)

GitHub internet-ல் உள்ளது; ஆனால் `http://localhost:8079` உங்கள் கணினியில் மட்டுமே உள்ளது. எனவே GitHub உங்கள் Jenkins-ஐ அடைய ஒரு **public URL** தேவை. **ngrok** அதை இலவசமாகத் தருகிறது.

**வழி A — ngrok + GitHub webhook (பரிந்துரை):**

1. https://ngrok.com-ல் இலவசக் கணக்கு உருவாக்கி, ngrok-ஐ நிறுவுங்கள் (https://ngrok.com/download, அல்லது PowerShell-ல் `winget install ngrok.ngrok`).
2. உங்கள் கணக்குடன் இணைக்க (token: ngrok dashboard → **Your Authtoken**):

   ```powershell
   ngrok config add-authtoken <your-ngrok-token>
   ```

3. Jenkins-க்கு tunnel தொடங்குங்கள் — **இந்த window-ஐ மூடாதீர்கள்**:

   ```powershell
   ngrok http 8079
   ```

   **எதிர்பார்க்கும் output (உதாரணம்):**

   ```text
   Forwarding    https://abcd-1234.ngrok-free.app -> http://localhost:8079
   ```

   > இலவசக் கணக்கில் ஒரு **static domain** கிடைக்கும் (ngrok dashboard → **Domains**) — அதைப் பயன்படுத்தினால் URL ஒவ்வொரு முறையும் மாறாது. இல்லையெனில் ngrok restart ஆகும் போதெல்லாம் webhook URL-ஐ மாற்ற வேண்டும்.

4. GitHub repository → **Settings** → **Webhooks** → **Add webhook**:

   ```text
   ┌─ Webhooks › Add webhook ─────────────────────────────────────┐
   │  Payload URL:   https://abcd-1234.ngrok-free.app/github-webhook/
   │  Content type:  application/json                             │
   │  Secret:        (காலியாக விடுங்கள்)                           │
   │  Which events would you like to trigger this webhook?        │
   │     (•) Just the push event.                                 │
   │  [✓] Active                                                  │
   │                                          [ Add webhook ]     │
   └──────────────────────────────────────────────────────────────┘
   ```

   > ⚠️ Payload URL-ன் இறுதியில் **`/github-webhook/`** (கடைசி `/` உட்பட) கட்டாயம்.

5. Jenkins job-ல் **GitHub hook trigger for GITScm polling** ✓ என்று உறுதிசெய்யுங்கள் ([7.3](#section-7-3)).

✅ **சரிபார்ப்பு:**

1. GitHub → **Settings** → **Webhooks** → உங்கள் webhook → **Recent Deliveries**: பச்சை ✓, response **200** (GitHub ஒரு test "ping" அனுப்பும்).
2. ஏதாவது சிறிய மாற்றம் செய்து (உ.தா. README) commit, push → சில விநாடிகளில் புதிய build தொடங்கும்; build page-ல் **Started by GitHub push by <your-name>** என்று தெரியும்.

> 🔐 ngrok உங்கள் Jenkins-ஐ internet-க்குத் திறக்கிறது. வலுவான admin password வைத்திருங்கள்; தேவையில்லாத போது ngrok-ஐ நிறுத்துங்கள் (**Ctrl + C**).

**வழி B — Poll SCM (கூடுதல் கருவி இல்லாமல்):**

Job → **Configure** → **Triggers** → **GitHub hook trigger for GITScm polling** ☐ (tick எடுங்கள்) → **Poll SCM** ✓ → **Schedule:**

```text
H/2 * * * *
```

→ **Save**. Jenkins சுமார் 2 நிமிடத்துக்கு ஒருமுறை GitHub-ஐச் சரிபார்த்து, புதிய commit இருந்தால் மட்டும் build செய்யும்.

### 7.7 முடிவைச் சரிபார்த்தல்

1. Build page → **Pipeline Overview** (அல்லது **Stage View**) → **10 stages** அனைத்தும் பச்சை ✅.
2. Browser: http://localhost:8080/api/hello →

   ```json
   {"message":"Hello! Spring Boot application is running successfully."}
   ```

3. PowerShell:

   ```powershell
   docker ps
   docker logs simple-spring-boot-app
   ```

   **எதிர்பார்க்கும் `docker ps` output:**

   ```text
   CONTAINER ID   IMAGE                                              COMMAND               STATUS         PORTS                    NAMES
   cde2dc2c5cd3   <docker-hub-username>/simple-spring-boot-app:v42   "java -jar app.jar"   Up 2 minutes   0.0.0.0:8080->8080/tcp   simple-spring-boot-app
   ```

4. Docker Hub → **Repositories** → `simple-spring-boot-app` → **Tags** → `v42`, `latest`.
5. Jenkins build page → **Test Result**, **Build Artifacts** (JAR).

---

<a id="section-8"></a>
## 8. பிழைத்திருத்தம் (Troubleshooting)

### 8.1 முதலில் எங்கே பார்ப்பது?

1. **Build page → Pipeline Overview / Stage View** — எந்த stage சிவப்பு?
2. **Console Output** — **Ctrl + F** → `ERROR` அல்லது `FAILURE` → **முதல்** பிழை தான் பெரும்பாலும் உண்மையான காரணம்.
3. **Test Result** — எந்த test, ஏன் தோல்வி.
4. **`docker logs simple-spring-boot-app`** — container-க்குள் application ஏன் பதில் தரவில்லை.
5. **Manage Jenkins → System Log** — Jenkins-ன் சொந்தப் பிழைகள்.
6. **Event Viewer → Windows Logs → System** — Jenkins *service* ஏன் தொடங்கவில்லை. Service-ன் log files (`*.log`) Jenkins install folder-ல் இருக்கும் (இந்தக் கணினியில் `D:\Jenkins`).

<a id="section-8-2"></a>
### 8.2 Jenkins பிழைகள்

#### ❌ Installer-ல் "Test Port" தோல்வி / port already in use
- **காரணம்:** அந்த port-ஐ வேறு program பயன்படுத்துகிறது (8080 பெரும்பாலும் பயன்பாட்டில் இருக்கும்).
- **தீர்வு:**
  1. வேறு port கொடுங்கள் — உ.தா. `8079` → **Test Port**.
  2. எந்த program port-ஐப் பயன்படுத்துகிறது என்று பார்க்க: `netstat -ano | findstr :8079` (கடைசி column = PID) → `tasklist /FI "PID eq <PID>"`.

#### ❌ Installer-ல் "Test Credentials" தோல்வி / "doesn't have Log On As A Service right"
- **காரணம்:** உங்கள் கணக்குக்கு Windows service-ஆக இயங்கும் அனுமதி இல்லை.
- **தீர்வு:**
  1. **Win + R** → `secpol.msc` → **Local Policies** → **User Rights Assignment** → **Log on as a service** → **Add User or Group…** → உங்கள் கணக்கு → **OK**.
  2. Installer-ல் மீண்டும் **Test Credentials**.
  3. இந்த அமைப்பு நிறுவனக் கொள்கையால் (domain group policy) பூட்டப்பட்டிருந்தால் IT குழுவை அணுகுங்கள்.

#### ❌ http://localhost:8079 திறக்கவில்லை
- **காரணம்:** Jenkins service இயங்கவில்லை, அல்லது இன்னும் தொடங்கிக்கொண்டிருக்கிறது.
- **தீர்வு:**
  1. `Get-Service Jenkins` → `Stopped` என்றால் Administrator PowerShell-ல் `Start-Service Jenkins`.
  2. 1–2 நிமிடம் காத்திருந்து browser-ஐ refresh செய்யுங்கள்.
  3. தொடங்கவில்லை என்றால் அடுத்த பிழையைப் பாருங்கள்.

#### ❌ Log On கணக்கை மாற்றிய பின் Jenkins service தொடங்கவில்லை
- **காரணம்:** தவறான password, Jenkins folders-க்கு அனுமதி இல்லை, அல்லது "Log on as a service" அனுமதி இல்லை.
- **தீர்வு:**
  1. `services.msc` → Jenkins → **Log On** → password-ஐ மீண்டும் சரியாகக் கொடுங்கள்.
  2. [5.3](#section-5-3)-ன் **b)** படியை (icacls) மீண்டும் இயக்குங்கள்.
  3. மேலே உள்ள "Log On As A Service" தீர்வைப் பாருங்கள்.
  4. **Event Viewer** → **Windows Logs** → **System** → "Service Control Manager" பிழைச் செய்தியைப் படியுங்கள்.

#### ❌ Admin password மறந்துவிட்டது
- **காரணம்:** –
- **தீர்வு** (கவனமாக, விரைவாகச் செய்யுங்கள்):
  1. Jenkins service-ஐ நிறுத்துங்கள்: `Stop-Service Jenkins` (Administrator).
  2. `C:\ProgramData\Jenkins\.jenkins\config.xml`-ஐ **backup** எடுங்கள் (copy).
  3. `config.xml`-ஐ Notepad-ல் (Administrator) திறந்து `<useSecurity>true</useSecurity>` என்பதை `<useSecurity>false</useSecurity>` என மாற்றி save செய்யுங்கள்.
  4. `Start-Service Jenkins` → http://localhost:8079 இப்போது login இல்லாமல் திறக்கும் ⚠️ (இந்த நேரத்தில் யார் வேண்டுமானாலும் அணுகலாம்).
  5. **Manage Jenkins** → **Security** → **Security Realm:** Jenkins' own user database, **Authorization:** Logged-in users can do anything → **Save**.
  6. **Manage Jenkins** → **Users** → உங்கள் admin user → புதிய password → **Save**. பிறகு logout செய்து புதிய password-ல் login செய்து சரிபார்க்கவும்.

#### ❌ Plugins download ஆகவில்லை (`UnknownHostException`, `Connection timed out`)
- **காரணம்:** Internet இல்லை, அல்லது அலுவலக proxy.
- **தீர்வு:**
  1. Browser-ல் https://updates.jenkins.io திறக்கிறதா என்று பாருங்கள்.
  2. Proxy இருந்தால்: **Manage Jenkins** → **Plugins** → **Advanced settings** → **HTTP Proxy Configuration** → server, port → **Submit**.
  3. **Manage Jenkins** → **Plugins** → **Available plugins** → மீண்டும் முயற்சி.

#### ❌ `No such DSL method 'junit'` / `No such DSL method 'withCredentials'`
- **காரணம்:** தேவையான plugin நிறுவப்படவில்லை.
- **தீர்வு:** **JUnit** / **Credentials Binding** plugin-ஐ நிறுவுங்கள் ([2.3](#section-2)) → Jenkins restart → மீண்டும் build.

#### ❌ `WorkflowScript: … expecting '}'` / `Expected a step` (Jenkinsfile syntax பிழை)
- **காரணம்:** Jenkinsfile-ல் அடைப்புக்குறி (`{ }`) அல்லது quotes தவறு.
- **தீர்வு:**
  1. பிழைச் செய்தியில் உள்ள வரி எண்ணைப் பாருங்கள் (`WorkflowScript: 45:` என்றால் 45-வது வரி).
  2. [7.4](#section-7) Jenkinsfile-ஐ மீண்டும் சரியாக copy செய்யுங்கள்.
  3. Commit செய்யாமல் சோதிக்க: கடைசி build → **Replay** → திருத்தி → **Run**.

#### ❌ `ERROR: Could not find credentials entry with ID 'dockerhub-credentials'`
- **காரணம்:** Jenkins-ல் சேமித்த credential-ன் ID வேறு பெயரில் உள்ளது.
- **தீர்வு:** **Manage Jenkins** → **Credentials** → ID சரியாக `dockerhub-credentials` என்று உள்ளதா பாருங்கள். இல்லையெனில் புதிய credential-ஐ சரியான ID-உடன் உருவாக்குங்கள் ([6.4](#section-6-4)).

<a id="section-8-3"></a>
### 8.3 Git பிழைகள்

#### ❌ `Cannot run program "git.exe"` / `'git' is not recognized as an internal or external command`
- **காரணம்:** Jenkins service-க்கு Git எங்கே என்று தெரியவில்லை (பெரும்பாலும் service LocalSystem-ஆக இயங்குகிறது).
- **தீர்வு:**
  1. Jenkins service-ஐ உங்கள் கணக்கில் இயக்குங்கள் ([5.3](#section-5-3)).
  2. **Manage Jenkins** → **Tools** → **Git installations** → **Path to Git executable**-ல் முழு path ([3.2](#section-3-2)).
  3. இன்னும் தீரவில்லை என்றால்: `PATH+TOOLS` ([5.4](#section-5-4)).

#### ❌ `remote: Repository not found` / `Authentication failed for 'https://github.com/…'`
- **காரணம்:** தவறான URL, அல்லது private repository-க்கு credentials இல்லை / token காலாவதியானது.
- **தீர்வு:**
  1. Job → **Configure** → Repository URL-ஐ GitHub-ல் உள்ளதுடன் ஒப்பிடுங்கள்.
  2. Private repository என்றால் **Credentials:** `github-credentials` தேர்வு செய்யுங்கள்.
  3. Token காலாவதியானால் புதிய token உருவாக்கி ([3.4](#section-3-4)) **Credentials** → `github-credentials` → **Update**.

#### ❌ `ERROR: Couldn't find any revision to build`
- **காரணம்:** Branch பெயர் பொருந்தவில்லை.
- **தீர்வு:** **Branch Specifier:** `*/main` (உங்கள் branch `master` என்றால் `*/master`). GitHub-ல் branch பெயரைச் சரிபார்க்கவும்.

#### ❌ `SSL certificate problem: unable to get local issuer certificate`
- **காரணம்:** அலுவலக network SSL certificates-ஐ மாற்றுகிறது; Git அதை நம்பவில்லை.
- **தீர்வு:** Windows certificate store-ஐப் பயன்படுத்த Git-க்குச் சொல்லுங்கள்:

  ```powershell
  git config --global http.sslBackend schannel
  ```

  (Jenkins உங்கள் கணக்கில் இயங்குவதால் இதே அமைப்பு Jenkins-க்கும் பொருந்தும்.)

#### ❌ `git push` → `! [rejected] main -> main (fetch first)`
- **காரணம்:** GitHub-ல் உங்கள் கணினியில் இல்லாத commits உள்ளன.
- **தீர்வு:**

  ```powershell
  git pull --rebase origin main
  git push
  ```

<a id="section-8-4"></a>
### 8.4 Maven பிழைகள்

#### ❌ `'.\mvnw.cmd' is not recognized as an internal or external command`
- **காரணம்:** Repository root-ல் `mvnw.cmd` இல்லை (தவறான folder push செய்யப்பட்டது, அல்லது `mvnw.cmd` / `.mvn` commit ஆகவில்லை).
- **தீர்வு:**
  1. GitHub-ல் repository root-ல் `mvnw.cmd`, `pom.xml`, `.mvn` folder உள்ளதா பாருங்கள்.
  2. இல்லையெனில் `simple-spring-boot-app` folder-க்குள் இருந்து மீண்டும் push செய்யுங்கள் ([3.3](#section-3)).

#### ❌ `JAVA_HOME environment variable is not defined correctly` / `JAVA_HOME not found`
- **காரணம்:** Jenkins-க்கு JDK கிடைக்கவில்லை.
- **தீர்வு:**
  1. `JAVA_HOME`-ஐ **System variable**-ஆக JDK 21 folder-க்கு அமைக்கவும் ([1.1](#section-1)).
  2. `Restart-Service Jenkins` (Administrator).

#### ❌ `error: release version 21 not supported`
- **காரணம்:** `JAVA_HOME` பழைய JDK-ஐ (உ.தா. 8 அல்லது 17) காட்டுகிறது.
- **தீர்வு:** `JAVA_HOME`-ஐ JDK 21-க்கு மாற்றி Jenkins-ஐ restart செய்யுங்கள். `tools-check` ([5.4](#section-5-4)) மூலம் சரிபார்க்கவும்.

#### ❌ `Tests run: 1, Failures: 1` (Unit Tests stage சிவப்பு)
- **காரணம்:** ஒரு test தோல்வியடைந்தது.
- **தீர்வு:** [4.6](#section-4-6)-ல் உள்ளபடி **Test Result** பார்த்து code-ஐ (அல்லது test-ஐ) சரிசெய்து push செய்யுங்கள்.

#### ❌ `COMPILATION ERROR` … `[25,13] cannot find symbol`
- **காரணம்:** Java code-ல் பிழை.
- **தீர்வு:** `[வரி,நெடுவரிசை]` எண்ணில் உள்ள file-ஐத் திறந்து சரிசெய்யுங்கள். உங்கள் கணினியில் `.\mvnw.cmd compile` வெற்றி பெற்ற பின் push செய்யுங்கள்.

#### ❌ `illegal character: '\ufeff'`
- **காரணம்:** Java file "UTF-8 with BOM" ஆக save ஆகியுள்ளது (Windows PowerShell 5.1-ன் `Set-Content -Encoding utf8` அல்லது சில editors இப்படிச் செய்யும்).
- **தீர்வு:** VS Code-ல் file-ஐத் திறந்து → கீழ் status bar-ல் **UTF-8 with BOM** → **Save with Encoding** → **UTF-8** → commit, push.

#### ❌ `Could not transfer artifact … Connect timed out` / `PKIX path building failed`
- **காரணம்:** Maven internet-ஐ அடைய முடியவில்லை (அலுவலக proxy அல்லது SSL inspection).
- **தீர்வு:**
  1. Proxy இருந்தால் `C:\Users\<you>\.m2\settings.xml` file-ஐ உருவாக்குங்கள் (மதிப்புகளை IT குழுவிடம் கேளுங்கள்):

     ```xml
     <settings>
       <proxies>
         <proxy>
           <id>company-proxy</id>
           <active>true</active>
           <protocol>http</protocol>
           <host>proxy.company.com</host>
           <port>8080</port>
           <nonProxyHosts>localhost|127.0.0.1</nonProxyHosts>
         </proxy>
       </proxies>
     </settings>
     ```

  2. `PKIX path building failed` என்றால் அலுவலக root certificate-ஐ JDK-ல் சேர்க்க வேண்டும் (Administrator PowerShell; certificate file-ஐ IT குழு தரும்):

     ```powershell
     & "$env:JAVA_HOME\bin\keytool.exe" -importcert -cacerts -alias company-root -file C:\certs\company-root.cer
     ```

     Password கேட்டால் இயல்புநிலை `changeit`. பிறகு Jenkins-ஐ restart செய்யுங்கள்.

<a id="section-8-5"></a>
### 8.5 Docker பிழைகள்

#### ❌ `'docker' is not recognized as an internal or external command`
- **காரணம்:** Jenkins service-க்கு Docker எங்கே என்று தெரியவில்லை.
- **தீர்வு:** [5.3](#section-5-3) (service கணக்கு) → [5.4](#section-5-4) (`tools-check`, தேவைப்பட்டால் `PATH+TOOLS`).

#### ❌ `ERROR: BuildKit is enabled but the buildx component is missing or broken`
- **காரணம்:** `buildx` உங்கள் user profile-ல் உள்ளது; Jenkins வேறு கணக்கில் இயங்குகிறது.
- **தீர்வு:** [5.3](#section-5-3).

#### ❌ `error during connect: … open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified`
- **காரணம்:** Docker Desktop இயங்கவில்லை.
- **தீர்வு:**
  1. Docker Desktop-ஐத் திறந்து, "Engine running" என்று வரும் வரை காத்திருங்கள்.
  2. **Start Docker Desktop when you sign in** ✓ ([5.1](#section-5)).
  3. Build-ஐ மீண்டும் இயக்குங்கள்.

#### ❌ Docker Desktop: `WSL 2 installation is incomplete` / `WSL needs updating`
- **தீர்வு:** Administrator PowerShell → `wsl --update` → கணினியை restart → Docker Desktop-ஐத் திறக்கவும்.

#### ❌ Docker Desktop: `Virtualization support not detected`
- **தீர்வு:** BIOS/UEFI-ல் Intel VT-x / AMD-V-ஐ enable செய்யுங்கள் (IT குழுவின் உதவி). Task Manager → Performance → CPU → **Virtualization: Enabled** என்று சரிபார்க்கவும்.

#### ❌ `COPY failed: no source files were specified` / `"/target": not found`
- **காரணம்:** `target` folder-ல் JAR இல்லை.
- **தீர்வு:** **Package JAR** stage வெற்றி பெற்றதா என்று பாருங்கள். `.dockerignore`-ஐ மாற்ற வேண்டாம் (அது `target/*.jar`-ஐ அனுமதிக்க வேண்டும்).

#### ❌ `When using COPY with more than one source file, the destination must be a directory`
- **காரணம்:** `target`-ல் ஒன்றுக்கு மேற்பட்ட JAR files உள்ளன.
- **தீர்வு:** `clean` உடன் build செய்யுங்கள் (pipeline அதைச் செய்கிறது). உங்கள் கணினியில்: `.\mvnw.cmd clean package`.

#### ❌ `Bind for 0.0.0.0:8080 failed: port is already allocated`
- **காரணம்:** 8080 port-ஐ வேறு ஏதோ பயன்படுத்துகிறது (உ.தா. நீங்கள் `mvnw` மூலம் application-ஐ இயக்கியிருக்கிறீர்கள், அல்லது வேறு container).
- **தீர்வு:**
  1. கண்டுபிடிக்க:

     ```powershell
     netstat -ano | findstr :8080
     docker ps
     ```

  2. அந்த program-ஐ நிறுத்துங்கள் (`mvnw` window-ல் **Ctrl + C**, அல்லது `docker rm -f <container-name>`).
  3. அல்லது Jenkinsfile-ல் `HOST_PORT = '8081'` என மாற்றி push செய்யுங்கள் (பிறகு application `http://localhost:8081/api/hello`-ல் கிடைக்கும்).

#### ❌ `Conflict. The container name "/simple-spring-boot-app" is already in use`
- **காரணம்:** பழைய container-ஐ நீக்க முடியவில்லை.
- **தீர்வு:** `docker rm -f simple-spring-boot-app` → build-ஐ மீண்டும் இயக்குங்கள்.

#### ❌ `conflict: unable to remove repository reference … container … is using its referenced image` (Docker Pull stage)
- **காரணம்:** நீங்கள் கைமுறையாகத் தொடங்கிய ஒரு container அதே image tag-ஐப் பயன்படுத்துகிறது.
- **தீர்வு:** `docker ps -a` → அந்த container-ஐ `docker rm -f <name>` மூலம் நீக்கி, build-ஐ மீண்டும் இயக்குங்கள்.

#### ❌ Smoke Test: எல்லா முயற்சிகளுக்குப் பிறகும் `curl: (7) Failed to connect` / `curl: (22) The requested URL returned error: 404`
- **காரணம்:** Container-க்குள் application தொடங்கவில்லை, அல்லது தவறான URL.
- **தீர்வு:**
  1. `docker ps -a` → container நிலை `Exited` என்றால்:
  2. `docker logs simple-spring-boot-app` → Java exception / பிழைச் செய்தியைப் படியுங்கள்.
  3. URL `http://localhost:<HOST_PORT>/api/hello` சரியா என்று பாருங்கள்.

#### ❌ Disk இடம் நிரம்பியது
- **காரணம்:** ஒவ்வொரு build-ம் புதிய image version-ஐச் சேர்க்கிறது.
- **தீர்வு:**

  ```powershell
  docker system df        # Docker எவ்வளவு இடம் பயன்படுத்துகிறது
  docker image prune -a   # எந்த container-ம் பயன்படுத்தாத images-ஐ நீக்கும்
  ```

<a id="section-8-6"></a>
### 8.6 Docker Hub பிழைகள்

#### ❌ `unauthorized: incorrect username or password`
- **காரணம்:** `dockerhub-credentials`-ல் தவறான username / token, token காலாவதியானது அல்லது ரத்து செய்யப்பட்டது, அல்லது Jenkinsfile-ல் `|`-க்கு முன் space.
- **தீர்வு:**
  1. உங்கள் terminal-ல் `docker login -u <docker-hub-username>` → token-ஐ paste செய்து சோதியுங்கள்.
  2. வேலை செய்தால், அதே username, token-ஐ **Credentials** → `dockerhub-credentials` → **Update**-ல் கொடுங்கள்.
  3. Jenkinsfile-ல் `echo %DOCKERHUB_TOKEN%| docker login` — `|`-க்கு முன் space இல்லை என்று உறுதிசெய்யுங்கள்.

#### ❌ `denied: requested access to the resource is denied` (push)
- **காரணம்:** `DOCKER_IMAGE` உங்கள் Docker Hub username-உடன் தொடங்கவில்லை, அல்லது token **Read-only**.
- **தீர்வு:**
  1. Jenkinsfile → `DOCKER_IMAGE = '<docker-hub-username>/simple-spring-boot-app'` (உங்கள் சரியான username).
  2. Token-க்கு **Read & Write** அனுமதி உள்ளதா பாருங்கள்; இல்லையெனில் புதிய token ([6.3](#section-6)).

#### ❌ `invalid reference format` / `repository name must be lowercase`
- **காரணம்:** `DOCKER_IMAGE`-ல் பெரிய எழுத்துகள் அல்லது space.
- **தீர்வு:** சிறிய எழுத்துகள் மட்டும், உ.தா. `johndoe/simple-spring-boot-app`.

#### ❌ `Error saving credentials: error storing credentials … A specified logon session does not exist`
- **காரணம்:** Jenkins service இன்னும் LocalSystem கணக்கில் இயங்குகிறது; Windows credential store அதற்குக் கிடைக்கவில்லை.
- **தீர்வு:** [5.3](#section-5-3) — service-ஐ உங்கள் கணக்கில் இயக்குங்கள்.

#### ❌ `toomanyrequests: You have reached your pull rate limit`
- **காரணம்:** Docker Hub, login இல்லாத pulls-ஐக் கட்டுப்படுத்துகிறது (base image `eclipse-temurin` pull செய்யும் போது வரலாம்).
- **தீர்வு:** Docker Desktop-ல் உங்கள் Docker Hub கணக்கில் sign in செய்யுங்கள், அல்லது terminal-ல் ஒருமுறை `docker login`. Jenkins உங்கள் கணக்கில் இயங்குவதால் அதே login-ஐப் பயன்படுத்தும். சிறிது நேரம் காத்திருந்து மீண்டும் build செய்யுங்கள்.

#### ❌ `manifest for …:v42 not found` / `pull access denied` (Docker Pull stage)
- **காரணம்:** Push வெற்றி பெறவில்லை, image பெயரில் எழுத்துப் பிழை, அல்லது private repository-க்கு login இல்லை.
- **தீர்வு:** Docker Push stage log, Docker Hub **Tags** பக்கம், `DOCKER_IMAGE` மதிப்பு — மூன்றையும் சரிபார்க்கவும்.

<a id="section-8-7"></a>
### 8.7 Webhook பிழைகள்

#### ❌ GitHub **Recent Deliveries**-ல் சிவப்பு குறி / `failed to connect to host`
- **காரணம்:** ngrok இயங்கவில்லை, அல்லது ngrok URL மாறிவிட்டது.
- **தீர்வு:** `ngrok http 8079` மீண்டும் தொடங்குங்கள்; புதிய URL என்றால் GitHub webhook-ன் **Payload URL**-ஐ update செய்யுங்கள் ([7.6](#section-7-6)). Static domain பயன்படுத்தினால் இது தேவையில்லை.

#### ❌ Response **404**
- **காரணம்:** Payload URL-ன் இறுதியில் `/github-webhook/` இல்லை.
- **தீர்வு:** `https://<your-ngrok-url>/github-webhook/` என்று சரிசெய்யுங்கள் → **Redeliver** மூலம் சோதிக்கவும்.

#### ❌ Response **200**, ஆனால் build தொடங்கவில்லை
- **காரணம்:** Trigger tick செய்யப்படவில்லை, job ஒருமுறையும் கைமுறையாக இயக்கப்படவில்லை, அல்லது வேறு branch-க்கு push.
- **தீர்வு:**
  1. Job → **Configure** → **GitHub hook trigger for GITScm polling** ✓.
  2. ஒருமுறை **Build Now** கைமுறையாக இயக்குங்கள்.
  3. `main` branch-க்கு push செய்யுங்கள்.

---

<a id="appendix"></a>
## பின்னிணைப்பு: விரைவு Command பட்டியல்

| நோக்கம் | Command |
|---------|---------|
| Java version | `java -version` |
| Git version | `git --version` |
| Maven (wrapper) version | `.\mvnw.cmd -v` |
| Build + tests + JAR | `.\mvnw.cmd clean package` |
| Tests மட்டும் | `.\mvnw.cmd test` |
| JAR-ஐ இயக்க | `java -jar target\simple-spring-boot-app-v0.jar` |
| Docker நிலை | `docker version` |
| Image உருவாக்க | `docker build -t simple-spring-boot-app:local .` |
| Container இயக்க | `docker run -d --name simple-spring-boot-app -p 8080:8080 <image>` |
| இயங்கும் containers | `docker ps` |
| Container log | `docker logs simple-spring-boot-app` |
| Container நீக்க | `docker rm -f simple-spring-boot-app` |
| Images பட்டியல் | `docker images` |
| பயன்படாத images நீக்க | `docker image prune -a` |
| Docker Hub login | `docker login -u <docker-hub-username>` |
| API சோதனை | `curl.exe http://localhost:8080/api/hello` |
| Jenkins service நிலை | `Get-Service Jenkins` |
| Jenkins restart (Administrator) | `Restart-Service Jenkins` |
| Port யார் பயன்படுத்துகிறார்கள் | `netstat -ano \| findstr :8080` |
| Webhook tunnel | `ngrok http 8079` |

> ஆங்கில வழிகாட்டி: [CICD-GUIDE.md](CICD-GUIDE.md) · Project விவரங்கள்: [README.md](README.md)
