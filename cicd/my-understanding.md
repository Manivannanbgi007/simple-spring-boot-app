What you need to do
Fill in two values in cicd/.env by editing the file directly, not pasting them here:
DOCKERHUB_TOKEN=: a Docker Hub access token with Read & Write, from Docker Hub → Account settings → Personal access tokens.
NGROK_AUTHTOKEN=: from https://dashboard.ngrok.com → Your Authtoken. A free account is enough.
Restart Jenkins and start the tunnel. In the cicd folder:

docker compose up -d --force-recreate jenkins
docker compose --profile tunnel up -d
docker compose logs ngrok
Find the url=https://<name>.ngrok-free.app line in the log. That's Jenkins' public address.
Create the webhook in GitHub. Go to your repo → Settings → Webhooks → Add webhook:
Payload URL: https://<name>.ngrok-free.app/github-webhook/. The trailing /github-webhook/ is required.
Content type: application/json
Secret: the GITHUB_WEBHOOK_SECRET value from cicd/.env
Events: Just the push event, with Active ticked
Check it. Under Recent Deliveries, the ping should show 200. Then click Build Now once in Jenkins to redo build #6 with the Docker Hub token. After that, every push should start a build within seconds, labelled Started by GitHub push by ….
Tell me when steps 1 and 2 are done if you'd like me to check the tunnel and the first delivery.

Some notes:

The tunnel makes your Jenkins login page reachable from the internet. Stop it when you don't need it: docker compose --profile tunnel stop ngrok.
On EC2 you won't need ngrok. Point the webhook at the server's own address, ideally over HTTPS.
Commit the 4 changed cicd/ files: git add cicd/jenkins/casc.yaml cicd/docker-compose.yml cicd/.env.example cicd/README.md. Leave out .env, which Git already ignores, and the target/ files.