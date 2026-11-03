# SonarQube நிறுவல் மற்றும் Jenkins Pipeline இணைப்பு வழிகாட்டி – Windows

> **இந்த வழிகாட்டி யாருக்கு?** [JENKINS_SETUP_AND_PIPELINE_GUIDE_TAMIL.md](JENKINS_SETUP_AND_PIPELINE_GUIDE_TAMIL.md)-ல் உள்ளபடி Jenkins pipeline ஏற்கனவே வேலை செய்பவர்களுக்கு.
>
> **முடிவில் என்ன கிடைக்கும்?** ஒவ்வொரு build-லும் SonarQube code-ஐச் சோதிக்கும்: bugs, பாதுகாப்புப் பிரச்சினைகள் (vulnerabilities), மோசமான நடைமுறைகள் ("code smells"), மீண்டும் மீண்டும் வரும் code (duplication), unit tests எவ்வளவு code-ஐச் சோதிக்கின்றன (coverage). Code **quality gate**-ல் தோல்வியடைந்தால், Docker image உருவாக்கும் முன்பே build நின்றுவிடும்.

இந்த ஆவணம் `simple-spring-boot-app` project-ஐ அடிப்படையாகக் கொண்டது. ஆங்கில வழிகாட்டி: [SONARQUBE-GUIDE.md](SONARQUBE-GUIDE.md).

> ⚠️ **SonarQube stages உள்ள Jenkinsfile-ஐ push செய்யும் முன், பிரிவுகள் 5–8-ஐ (Jenkins அமைப்பு, webhook) முடித்துவிடுங்கள்.** இல்லையெனில் அடுத்த build **SonarQube Analysis** stage-ல் தோல்வியடையும்.

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
   Package JAR ▶ Docker Build ▶ … ▶ Smoke Test   build நிற்கும் (FAILURE); ஓடும் application மாறாது
```

---

## உள்ளடக்கம்

- [0. தொடங்கும் முன்](#section-0)
- [1. Docker மூலம் SonarQube நிறுவுதல்](#section-1)
- [2. Login செய்து admin password-ஐ மாற்றுதல்](#section-2)
- [3. Jenkins-க்கு token உருவாக்குதல்](#section-3)
- [4. உங்கள் கணினியிலிருந்து முதல் analysis](#section-4)
- [5. Jenkins-ல் SonarQube Scanner plugin நிறுவுதல்](#section-5)
- [6. Token-ஐ Jenkins-ல் சேமித்தல்](#section-6)
- [7. SonarQube எங்கே உள்ளது என்று Jenkins-க்குச் சொல்லுதல்](#section-7)
- [8. Quality gate முடிவை Jenkins-க்குத் திருப்பி அனுப்புதல் (webhook)](#section-8)
- [9. Push செய்து pipeline-ஐச் சரிபார்த்தல்](#section-9)
- [10. பயிற்சி: quality gate தோல்வியைப் பார்த்தல் (விருப்பம்)](#section-10)
- [11. Project files விளக்கம்](#section-11)
- [12. தினசரி பயன்பாடு](#section-12)
- [13. பிழைத்திருத்தம் (Troubleshooting)](#section-13)

---

<a id="section-0"></a>
## 0. தொடங்கும் முன்

### 0.1 SonarQube சொற்கள்

| சொல் | பொருள் |
|------|--------|
| **Quality gate** | ஒவ்வொரு analysis-க்குமான தேர்ச்சி / தோல்வி விதிகள். உள்ளமைந்த **Sonar way** gate **புதிய code**-ஐச் சோதிக்கிறது: புதிய issues இல்லை, புதிய security hotspots அனைத்தும் review செய்யப்பட்டவை, குறைந்தது 80% coverage, அதிகபட்சம் 3% duplicated lines |
| **Issue** | Code-ல் கண்டறிந்த பிரச்சினை. **Security**, **Reliability** (bugs), **Maintainability** (code smells) எனப் பிரிக்கப்படும் |
| **Security hotspot** | பாதுகாப்போடு தொடர்புடைய code (உ.தா. cookies, passwords) — ஒருவர் பார்த்து உறுதிசெய்ய வேண்டும் |
| **Coverage** | Unit tests இயக்கும் code வரிகளின் சதவீதம் (**JaCoCo** அளவிடுகிறது) |
| **New code** | முந்தைய version-க்குப் பின் மாறிய code. பழைய பிரச்சினைகள் ஒவ்வொரு build-ஐயும் நிறுத்தாமல் இருக்க, quality gate இதை மட்டும் பார்க்கிறது |

### 0.2 இந்த ஆவணத்தில் பயன்படுத்தும் மதிப்புகள்

| பெயர் | மதிப்பு | குறிப்பு |
|-------|--------|---------|
| SonarQube | Community Build **26.10.0.133078** | Docker container பெயர்: `sonarqube` |
| SonarQube முகவரி | `http://localhost:9000` | |
| SonarQube data | Docker volumes `sonarqube_data`, `sonarqube_extensions`, `sonarqube_logs` | Container நீக்கப்பட்டாலும் data இருக்கும் |
| Database | உள்ளமைந்த H2 database | ஒரு கணினிக்குப் போதும்; ஆனால் upgrade செய்ய முடியாது ([12](#section-12)) |
| Jenkins முகவரி | `http://localhost:8079` | SonarQube container-க்குள்ளிருந்து: `http://host.docker.internal:8079` |
| Maven scanner | `sonar-maven-plugin` 5.8.0.7211 | `pom.xml`-ல் |
| Coverage | JaCoCo 0.8.15 | `mvnw test`-க்குப் பின் `target\site\jacoco\jacoco.xml` |
| Project key | `simple-spring-boot-app` | http://localhost:9000/dashboard?id=simple-spring-boot-app |
| Jenkins credential ID | `sonarqube-token` | Token சேமிக்கும் இடம் |
| Jenkins server பெயர் | `SonarQube` | Jenkinsfile-ல் `withSonarQubeEnv('SonarQube')` |

> Ports: Jenkins **8079**, application **8080**, SonarQube **9000**.

---

<a id="section-1"></a>
## 1. Docker மூலம் SonarQube நிறுவுதல்

> இந்தக் கணினியில் இது **ஏற்கனவே முடிந்துவிட்டது** (`sonarqube` container இயங்குகிறது). வேறு கணினியில் அல்லது மீண்டும் நிறுவும் போது இந்தப் படிகள் தேவை.

**தேவைகள்:**

- Docker Desktop இயங்க வேண்டும்.
- Docker-க்கு குறைந்தது **4 GB** memory (SonarQube சுமார் 2 GB பயன்படுத்தும்). சரிபார்க்க: `docker info --format "{{.MemTotal}}"` (bytes-ல்).
- Port 9000 காலியாக இருக்க வேண்டும்: `netstat -ano | findstr :9000` எதையும் காட்டக் கூடாது.

**நிறுவுதல்** — PowerShell-ல்:

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

| பகுதி | பொருள் |
|-------|--------|
| `docker volume create …` | Container-க்கு வெளியே சேமிப்பிடம் — container நீக்கப்பட்டாலும் data அழியாது |
| `-d` | பின்னணியில் (detached) இயக்கு |
| `-p 9000:9000` | உங்கள் கணினியின் 9000 port → container-ன் 9000 port |
| `--restart unless-stopped` | Docker Desktop தொடங்கும் போதெல்லாம், நீங்கள் நிறுத்தும் வரை, தானாகத் தொடங்கும் |
| `-v sonarqube_data:/opt/sonarqube/data` | Analyses, settings, users, tokens இங்கே சேமிக்கப்படும் |
| `sonarqube:26.10.0.133078-community` | சரியான version — மீண்டும் நிறுவினாலும் அதே SonarQube கிடைக்கும் (`community` tag எப்போதும் புதிய version-ஐ எடுக்கும்) |

முதல் முறை image download ஆகும் (சுமார் 1 GB). பிறகு SonarQube தொடங்க 1–2 நிமிடங்கள் ஆகும். நிலையைப் பார்க்க:

```powershell
curl.exe http://localhost:9000/api/system/status
```

`"status":"STARTING"` → சிறிது நேரம் காத்திருந்து மீண்டும் முயலுங்கள். தயாரானதும்:

```json
{"id":"…","version":"26.10.0.133078","status":"UP"}
```

✅ **சரிபார்ப்பு:** `docker ps --filter name=sonarqube` → container **Up**, `0.0.0.0:9000->9000/tcp`.

---

<a id="section-2"></a>
## 2. Login செய்து admin password-ஐ மாற்றுதல்

1. Browser-ல் http://localhost:9000 திறங்கள்.
2. **Login:** `admin`, **Password:** `admin`.
3. Password-ஐ மாற்றச் சொல்லும்: பழைய password `admin`, புதிய வலுவான password இரண்டு முறை → **Update**. அதை password manager-ல் சேமியுங்கள்.

```text
┌─ Update your password ───────────────────────────────────────┐
│  Old Password:          admin                                │
│  New Password:          ••••••••••••                         │
│  Confirm Password:      ••••••••••••                         │
│                                              [ Update ]      │
└──────────────────────────────────────────────────────────────┘
```

Project-ஐக் கைமுறையாக உருவாக்க வேண்டியதில்லை — முதல் analysis ([4](#section-4)) அதை உருவாக்கும்.

✅ **சரிபார்ப்பு:** Logout செய்து புதிய password-உடன் மீண்டும் login செய்ய முடிகிறது.

---

<a id="section-3"></a>
## 3. Jenkins-க்கு token உருவாக்குதல்

Jenkins-ம் உங்கள் கணினியும் password-க்குப் பதிலாக **token** மூலம் SonarQube-ல் login செய்கின்றன.

1. வலது மேலே உள்ள avatar → **My Account** → **Security** tab.
2. **Generate Tokens** பகுதியில்:

   ```text
   ┌─ Generate Tokens ────────────────────────────────────────────┐
   │  Name:        jenkins                                        │
   │  Type:        User Token                                     │
   │  Expires in:  90 days                                        │
   │                                            [ Generate ]      │
   └──────────────────────────────────────────────────────────────┘
   ```

   - **User Token** = analysis-க்கும், quality gate முடிவைப் படிக்கவும் வேலை செய்யும்.
   - காலாவதி தேதியைக் குறித்துக்கொள்ளுங்கள்; அதற்கு முன் புதுப்பிக்க வேண்டும் ([12](#section-12)).
3. **Generate** → token-ஐ copy செய்யுங்கள் (`squ_`-ல் தொடங்கும்). இது **ஒரு முறை மட்டுமே** காட்டப்படும்.

✅ **சரிபார்ப்பு:** **Security** பக்கத்தில் `jenkins` token தெரியும், **Last use: Never**.

---

<a id="section-4"></a>
## 4. உங்கள் கணினியிலிருந்து முதல் analysis

Jenkins இல்லாமலே SonarQube வேலை செய்கிறதா என்று இது நிரூபிக்கிறது; project-ம் உருவாகிறது. PowerShell-ல், project folder-ல்:

```powershell
$env:SONAR_HOST_URL = "http://localhost:9000"
$env:SONAR_TOKEN    = Read-Host "SonarQube token"     # பிரிவு 3-ன் token-ஐ paste செய்து Enter
.\mvnw.cmd clean verify sonar:sonar
```

- `Read-Host` → token PowerShell history-ல் சேமிக்கப்படாது. இரண்டு variables-ம் இந்த window-ஐ மூடும் வரை மட்டுமே இருக்கும்.
- `verify` → unit tests (coverage உடன்), integration tests இயங்கும்; பிறகு `sonar:sonar` அனைத்தையும் SonarQube-க்கு அனுப்பும்.
- ⚠️ **`SONAR_HOST_URL` இல்லாவிட்டால்** scanner internet-ல் உள்ள SonarQube **Cloud**-ஐ அழைத்து `You must define the following mandatory properties: sonar.organization` என்று தோல்வியடையும்.

**எதிர்பார்க்கும் output (இறுதியில்):**

```text
[INFO] ANALYSIS SUCCESSFUL, you can find the results at: http://localhost:9000/dashboard?id=simple-spring-boot-app
[INFO] BUILD SUCCESS
```

✅ **சரிபார்ப்பு:** http://localhost:9000/dashboard?id=simple-spring-boot-app திறங்கள்:

- **Quality Gate: Passed** (முதல் analysis-ல் "new code" இன்னும் இல்லை, அதனால் தேர்ச்சி).
- **Coverage** சுமார் **67%**: `HelloController`-ன் எல்லா வரிகளும் சோதிக்கப்படுகின்றன; `DemoApplication.main` மட்டும் இல்லை (tests application-ஐ `main` மூலம் தொடங்குவதில்லை).
- **Issues** tab-ல் சில கண்டுபிடிப்புகள் இருக்கலாம் — ஒன்றைக் கிளிக் செய்தால் ஏன் முக்கியம், எப்படிச் சரிசெய்வது என்று காட்டும்.

---

<a id="section-5"></a>
## 5. Jenkins-ல் SonarQube Scanner plugin நிறுவுதல்

1. Jenkins (http://localhost:8079) → **Manage Jenkins** → **Plugins** → **Available plugins**.
2. **SonarQube Scanner** என்று தேடி → tick → **Install**.
3. கேட்டால் **Restart Jenkins when installation is complete and no jobs are running** ✓.

இந்த plugin Jenkinsfile-க்கு `withSonarQubeEnv`, `waitForQualityGate` ஆகியவற்றையும், பிரிவு 8-ல் SonarQube அழைக்கும் `/sonarqube-webhook/` முகவரியையும் சேர்க்கிறது.

✅ **சரிபார்ப்பு:** **Manage Jenkins** → **Plugins** → **Installed plugins** → **SonarQube Scanner** தெரியும் (enabled).

---

<a id="section-6"></a>
## 6. Token-ஐ Jenkins-ல் சேமித்தல்

**Manage Jenkins** → **Credentials** → **System** → **Global credentials (unrestricted)** → **Add Credentials**:

```text
┌─ New credentials ────────────────────────────────────────────┐
│  Kind:         Secret text                                   │
│  Scope:        Global                                        │
│  Secret:       ••••••••••   (பிரிவு 3-ன் SonarQube token)     │
│  ID:           sonarqube-token                               │
│  Description:  SonarQube token for Jenkins                   │
│                                                [ Create ]    │
└──────────────────────────────────────────────────────────────┘
```

> ⚠️ **ID சரியாக `sonarqube-token`** என்று இருக்க வேண்டும் — பிரிவு 7-ல் இதைத் தேர்ந்தெடுப்போம்.

✅ **சரிபார்ப்பு:** `dockerhub-credentials`-உடன் `sonarqube-token`-ம் பட்டியலில் தெரியும்.

---

<a id="section-7"></a>
## 7. SonarQube எங்கே உள்ளது என்று Jenkins-க்குச் சொல்லுதல்

1. **Manage Jenkins** → **System** → **SonarQube servers** பகுதிக்குச் செல்லுங்கள்.
2. **Environment variables** ✓ ("Enable injection of SonarQube server configuration as build environment variables").
3. **Add SonarQube** → நிரப்புங்கள்:

   ```text
   ┌─ SonarQube servers ──────────────────────────────────────────┐
   │  [✓] Environment variables                                   │
   │  Name:                         SonarQube                     │
   │  Server URL:                   http://localhost:9000         │
   │  Server authentication token:  sonarqube-token  ▼            │
   └──────────────────────────────────────────────────────────────┘
   ```

4. **Save**.

> ⚠️ **Name சரியாக `SonarQube`** (பெரிய S, பெரிய Q) — Jenkinsfile `withSonarQubeEnv('SonarQube')` மூலம் இதைத் தேடுகிறது. Jenkins உங்கள் கணினியில் இயங்குவதால், இங்கே `localhost` சரி.

✅ **சரிபார்ப்பு:** **Manage Jenkins** → **System**-ஐ மீண்டும் திறந்தால் `SonarQube` server, token உடன் சேமிக்கப்பட்டிருக்கும்.

---

<a id="section-8"></a>
## 8. Quality gate முடிவை Jenkins-க்குத் திருப்பி அனுப்புதல் (webhook)

Analysis முடிந்த பின் SonarQube அதைச் செயலாக்க சில விநாடிகள் எடுக்கும். **Quality Gate** stage, SonarQube Jenkins-ஐ அழைத்து முடிவைச் சொல்லும் வரை காத்திருக்கும். அந்த அழைப்பே **webhook**.

1. SonarQube → **Administration** → **Configuration** → **Webhooks** → **Create**.
2. நிரப்புங்கள்:

   ```text
   ┌─ Create Webhook ─────────────────────────────────────────────┐
   │  Name:    Jenkins                                            │
   │  URL:     http://host.docker.internal:8079/sonarqube-webhook/│
   │  Secret:  (காலியாக விடுங்கள்)                                 │
   │                                              [ Create ]      │
   └──────────────────────────────────────────────────────────────┘
   ```

3. **Create**.

> ⚠️ URL-ன் இறுதியில் **`/sonarqube-webhook/`** (கடைசி `/` உட்பட) கட்டாயம்.
>
> **ஏன் `localhost` இல்லை?** SonarQube ஒரு **container-க்குள்** இயங்குகிறது; அங்கே `localhost` என்றால் அந்த container தான். `host.docker.internal` = Docker Desktop உங்கள் கணினிக்குக் கொடுக்கும் பெயர்.

✅ **சரிபார்ப்பு:** பிரிவு 9-ன் முதல் Jenkins build-க்குப் பிறகு webhook-ன் **Last delivery**-ல் பச்சை ✓. **⋮** → **Show recent deliveries** → response **200**.

---

<a id="section-9"></a>
## 9. Push செய்து pipeline-ஐச் சரிபார்த்தல்

SonarQube-க்குத் தேவையான அனைத்தும் project-ல் ஏற்கனவே உள்ளன ([11](#section-11)). மாற்றங்களை commit செய்து push செய்யுங்கள் — GitHub webhook build-ஐத் தொடங்கும் (அல்லது **Build Now**).

✅ **சரிபார்ப்பு:** Build பச்சை ✅, **13 stages**:

| Stage | Log-ல் வெற்றி இப்படித் தெரியும் |
|-------|-------------------------------|
| SonarQube Analysis | `ANALYSIS SUCCESSFUL, you can find the results at: http://localhost:9000/dashboard?id=simple-spring-boot-app` |
| Quality Gate | `SonarQube task '…' status is 'SUCCESS'`, பிறகு `SonarQube task '…' completed. Quality gate is 'OK'` |

மேலும்:

- Build page-ல் **SonarQube Quality Gate** badge, dashboard இணைப்புடன் தெரியும்.
- SonarQube → project → **Activity**-ல் புதிய analysis தெரியும்.
- Webhook recent deliveries → **200** (பிரிவு 8).

---

<a id="section-10"></a>
## 10. பயிற்சி: quality gate தோல்வியைப் பார்த்தல் (விருப்பம்)

Code-ஐ மாற்றாமலே, தற்காலிகமாகக் கடுமையான gate-ஐப் பயன்படுத்தி pipeline நிற்பதைப் பாருங்கள்.

1. SonarQube → **Quality Gates** → **Create** → **Name:** `Strict demo` → **Save**.
2. **Add Condition** → **On Overall Code** → **Coverage** → **is less than** `90` → **Add Condition**. (Project-ன் coverage சுமார் 67%.)
3. Project → **Project Settings** → **Quality Gate** → **Always use a specific quality gate** → `Strict demo` → **Save**.
4. Jenkins → job → **Build Now**.

✅ **சரிபார்ப்பு:** **Quality Gate** stage சிவப்பு; log-ன் இறுதியில்:

```text
SonarQube task '…' completed. Quality gate is 'ERROR'
ERROR: Pipeline aborted due to quality gate failure: ERROR
```

Package JAR, Docker, Deploy stages இயங்காது — முந்தைய build-ன் container தொடர்ந்து ஓடும். SonarQube dashboard **Failed** என்றும், தோல்வியடைந்த condition-ஐயும் காட்டும்.

**மீட்டமைக்க:** Project → **Project Settings** → **Quality Gate** → **Always use the instance default** → **Save** → மீண்டும் **Build Now** → பச்சை ✅.

---

<a id="section-11"></a>
## 11. Project files விளக்கம்

**`pom.xml`** — மூன்று சேர்க்கைகள்:

```xml
<!-- Project key in SonarQube -->
<sonar.projectKey>simple-spring-boot-app</sonar.projectKey>
```

- **`jacoco-maven-plugin`** — `prepare-agent` unit tests-உடன் JaCoCo-வை இணைக்கிறது; `report` (`test` phase-ல்) `mvnw test`-க்குப் பின் உடனே `target\site\jacoco\jacoco.xml`-ஐ உருவாக்குகிறது. SonarQube இந்த file-ஐத் தானாகப் படிக்கிறது. `target\site\jacoco\index.html`-ஐ browser-ல் திறந்தால் coverage-ஐ நீங்களே பார்க்கலாம்.
- **`sonar-maven-plugin`** (`pluginManagement`-ல்) — scanner version-ஐ மட்டும் நிர்ணயிக்கிறது. `sonar:sonar` அழைக்கும் போது மட்டுமே இயங்கும்.

**`Jenkinsfile`** — Integration Tests-க்குப் பின் இரண்டு புதிய stages:

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

| பகுதி | பொருள் |
|-------|--------|
| `withSonarQubeEnv('SonarQube')` | பிரிவு 7-ன் server URL, token-ஐ scanner-க்குத் தருகிறது. Token Jenkinsfile-லோ Git-லோ log-லோ தெரியாது |
| `sonar:sonar` | முந்தைய stages `target`-ல் விட்டவற்றை (compiled classes, test reports, `jacoco.xml`) பயன்படுத்துகிறது — மீண்டும் compile / test செய்வதில்லை |
| Coverage | Unit tests-லிருந்து மட்டும். Integration Tests stage failsafe goals-ஐ நேரடியாக இயக்குவதால் அங்கே JaCoCo இணைவதில்லை; unit tests ஏற்கனவே controller முழுவதையும் சோதிக்கின்றன |
| `waitForQualityGate abortPipeline: true` | Gate தோல்வியானால் build **FAILURE**; அடுத்த stages இயங்காது |
| `timeout(time: 5, unit: 'MINUTES')` | Webhook வரவில்லை என்றால் 5 நிமிடத்தில் காத்திருப்பை நிறுத்தும் |

---

<a id="section-12"></a>
## 12. தினசரி பயன்பாடு

- **ஒவ்வொரு Jenkins build-ன் போதும் SonarQube இயங்க வேண்டும்.** Docker Desktop உடன் தானாகத் தொடங்கும். சரிபார்க்க: `docker ps --filter name=sonarqube`; தொடங்க: `docker start sonarqube` → `UP` வரும் வரை காத்திருங்கள் (பிரிவு 1).
- **நிறுத்த** (சுமார் 2 GB memory மிச்சம்): `docker stop sonarqube`. Data volumes-ல் பத்திரமாக இருக்கும்.
- **Log:** `docker logs sonarqube` (நேரலையாக: `docker logs -f sonarqube`).
- ⚠️ **தவறுதலாக data-வை அழிக்காதீர்கள்.** இவை எல்லா analyses, settings-ஐயும் (password, token, webhook) அழிக்கும்:
  - `docker volume rm sonarqube_data …`
  - `sonarqube` container **நிறுத்தப்பட்டிருக்கும் / நீக்கப்பட்டிருக்கும்** போது `docker system prune --volumes`

  `docker image prune -a` பாதுகாப்பானது — container பயன்படுத்தும் image-ஐ அது நீக்காது.
- **Token புதுப்பித்தல்:** காலாவதியாகும் முன் புதிய token உருவாக்கி (பிரிவு 3), Jenkins-ல் `sonarqube-token`-ஐ update செய்யுங்கள் (**Credentials** → credential → **Update**).
- **புதிய SonarQube version:** உள்ளமைந்த H2 database-ஐ **upgrade செய்ய முடியாது**. புதிதாகத் தொடங்க வேண்டும்: `docker rm -f sonarqube`, `docker volume rm sonarqube_data sonarqube_extensions sonarqube_logs`, பிறகு புதிய tag உடன் பிரிவு 1, மீண்டும் பிரிவுகள் 2, 3, 6 (secret update), 8. பழைய analysis வரலாறு போய்விடும். வரலாற்றை வைத்துக்கொள்ள PostgreSQL database தேவை — அதிகாரப்பூர்வ ஆவணம்: https://docs.sonarsource.com/sonarqube-community-build/

---

<a id="section-13"></a>
## 13. பிழைத்திருத்தம் (Troubleshooting)

**முதலில் எங்கே பார்ப்பது?** Jenkins-ல் சிவப்பு stage-ன் **Console Output**; `docker logs sonarqube`; SonarQube **Administration** → **Configuration** → **Webhooks** → **Show recent deliveries**.

#### ❌ `No such DSL method 'withSonarQubeEnv'` / `No such DSL method 'waitForQualityGate'`
- **காரணம்:** SonarQube Scanner plugin இல்லை.
- **தீர்வு:** பிரிவு [5](#section-5).

#### ❌ `SonarQube installation defined in this job (SonarQube) does not match any configured installation`
- **காரணம்:** Jenkins-ல் சரியாக `SonarQube` என்ற பெயரில் server இல்லை.
- **தீர்வு:** பிரிவு [7](#section-7) — பெயரைச் சரிபாருங்கள் (பெரிய S, பெரிய Q).

#### ❌ `Failed to query server version: … failed with HTTP 401 Unauthorized`
- **காரணம்:** Token இல்லை, தவறு, காலாவதியானது அல்லது நீக்கப்பட்டது.
- **தீர்வு:** புதிய token ([3](#section-3)) → Jenkins-ல் `sonarqube-token` update ([6](#section-6)). உங்கள் கணினியில்: `SONAR_TOKEN` அமைக்கவும் ([4](#section-4)).

#### ❌ `Communicating with SonarQube Cloud` … `You must define the following mandatory properties: sonar.organization`
- **காரணம்:** Scanner-க்கு server URL கிடைக்கவில்லை, அதனால் SonarQube Cloud-ஐ அழைத்தது.
- **தீர்வு:** உங்கள் கணினியில் `SONAR_HOST_URL` அமைக்கவும் ([4](#section-4)). Jenkins-ல்: command `withSonarQubeEnv` block-க்குள் இருக்க வேண்டும்; server URL அமைக்கப்பட்டிருக்க வேண்டும் ([7](#section-7)).

#### ❌ `Failed to query server version` … `Connection refused` / `ConnectException`
- **காரணம்:** SonarQube இயங்கவில்லை (அல்லது இன்னும் தொடங்கிக்கொண்டிருக்கிறது).
- **தீர்வு:** `docker start sonarqube`; `/api/system/status` → `UP` வரும் வரை காத்திருங்கள்.

#### ❌ Quality Gate stage `status is 'PENDING'` / `'IN_PROGRESS'`-லேயே நின்று, பிறகு `Timeout has been exceeded`
- **காரணம்:** SonarQube, Jenkins-ஐத் திருப்பி அழைக்கவில்லை.
- **தீர்வு:** Webhook URL-ஐச் சரிபாருங்கள் ([8](#section-8)): `host.docker.internal`, port `8079`, இறுதி `/`.

#### ❌ Webhook recent deliveries-ல் **403** அல்லது **404**
- **காரணம்:** Plugin இன்னும் நிறுவப்படவில்லை, அல்லது நிறுவிய பின் Jenkins restart ஆகவில்லை.
- **தீர்வு:** பிரிவு [5](#section-5); Jenkins restart: http://localhost:8079/safeRestart

#### ❌ Webhook recent deliveries-ல் `Server Unreachable` / `Failed to connect`
- **காரணம்:** Jenkins இயங்கவில்லை, அல்லது வேறு port.
- **தீர்வு:** http://localhost:8079 திறக்கிறதா பாருங்கள்; webhook URL-ல் port-ஐச் சரிசெய்யுங்கள்.

#### ❌ `ERROR: Pipeline aborted due to quality gate failure: ERROR`
- **காரணம்:** Code quality gate-ல் தோல்வி — இது gate சரியாக வேலை செய்வதைக் காட்டுகிறது.
- **தீர்வு:** Project dashboard → தோல்வியடைந்த conditions தெரியும் → code-ஐ (அல்லது tests-ஐ) சரிசெய்து push செய்யுங்கள்.

#### ❌ Coverage **0%** அல்லது "—"
- **காரணம்:** `sonar:sonar` இயங்கிய போது `target\site\jacoco\jacoco.xml` இல்லை.
- **தீர்வு:** `mvnw test`-க்குப் பின் analysis இயக்குங்கள் (pipeline அப்படியே செய்கிறது); உங்கள் கணினியில் `.\mvnw.cmd clean verify sonar:sonar`.

#### ❌ Container நின்றுவிடுகிறது; `docker logs sonarqube`-ல் `max virtual memory areas vm.max_map_count [65530] is too low`
- **காரணம்:** SonarQube-ன் search engine-க்கு அதிக Linux வரம்பு தேவை (இந்தக் கணினியில் ஏற்கனவே 262144).
- **தீர்வு:** `%USERPROFILE%\.wslconfig` file உருவாக்கி இந்த இரண்டு வரிகளைச் சேருங்கள்: `[wsl2]`, `kernelCommandLine = "sysctl.vm.max_map_count=262144"` → `wsl --shutdown` → Docker Desktop-ஐ மீண்டும் தொடங்குங்கள்.

#### ❌ Container exit code **137**, அல்லது log-ல் `OutOfMemoryError`
- **காரணம்:** Docker-க்கு memory போதவில்லை.
- **தீர்வு:** Docker-க்கு குறைந்தது 4 GB கொடுங்கள்; மற்ற containers-ஐ நிறுத்துங்கள்.

#### ❌ Container தொடங்கும் போது port 9000 already in use
- **காரணம்:** வேறு program 9000 port-ஐப் பயன்படுத்துகிறது.
- **தீர்வு:** வேறு port: `-p 9001:9000`; பிரிவு 7-ல் `http://localhost:9001`.

---

> ஆங்கில வழிகாட்டி: [SONARQUBE-GUIDE.md](SONARQUBE-GUIDE.md) · Jenkins வழிகாட்டி: [JENKINS_SETUP_AND_PIPELINE_GUIDE_TAMIL.md](JENKINS_SETUP_AND_PIPELINE_GUIDE_TAMIL.md) · Project விவரங்கள்: [README.md](README.md)
