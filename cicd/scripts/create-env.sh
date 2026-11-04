#!/usr/bin/env bash
# Creates cicd/.env from cicd/.env.example and fills in everything that can be filled in automatically:
#   - new random passwords and secrets for this machine:
#       JENKINS_ADMIN_PASSWORD, SONARQUBE_DB_PASSWORD, GITHUB_WEBHOOK_SECRET, SONAR_WEBHOOK_SECRET
#   - DOCKER_GID: the group that owns this machine's Docker socket
#   - optional, from environment variables of the same name:
#       JENKINS_PUBLIC_URL, GITHUB_REPO_URL, GITHUB_BRANCH, DOCKERHUB_USERNAME
#     example:  JENKINS_PUBLIC_URL=http://203.0.113.10:8079/ bash cicd/scripts/create-env.sh
#
# A secret that already has a value is never changed, so the script is safe to run again.
# You still enter DOCKERHUB_TOKEN (and later SONAR_TOKEN) yourself - see cicd/AWS-EC2-GUIDE.md.
#
# Run it as the user who runs docker compose (not with sudo):  bash cicd/scripts/create-env.sh
set -euo pipefail

CICD_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$CICD_DIR/.env"
EXAMPLE="$CICD_DIR/.env.example"

umask 077   # files created from here on are readable only by their owner
if [ -f "$ENV_FILE" ]; then
    echo "$ENV_FILE already exists - only empty values are filled in"
else
    cp "$EXAMPLE" "$ENV_FILE"
    echo "Created $ENV_FILE from .env.example"
fi
chmod 600 "$ENV_FILE"

# Current value of a variable in .env (empty if it has no value)
get() { sed -n "s/^$1=//p" "$ENV_FILE" | head -n 1; }

# Sets a variable in .env. Values here never contain '|', so it works as the sed separator.
set_value() {
    local name="$1" value="$2"
    if grep -q "^$name=" "$ENV_FILE"; then
        sed -i "s|^$name=.*|$name=$value|" "$ENV_FILE"
    else
        echo "$name=$value" >> "$ENV_FILE"
    fi
}

# Sets a variable only if it is still empty
fill_if_empty() {
    if [ -z "$(get "$1")" ]; then
        set_value "$1" "$2"; echo "  $1: generated"
    else
        echo "  $1: already set - unchanged"
    fi
}

random_hex()      { openssl rand -hex 32; }                                  # 64 characters 0-9a-f
random_password() { openssl rand -base64 24 | tr '+/' '-_' | tr -d '=\n'; }  # 32 characters, no special shell characters

echo "Secrets (new and random for this machine):"
fill_if_empty JENKINS_ADMIN_PASSWORD "$(random_password)"
fill_if_empty SONARQUBE_DB_PASSWORD  "$(random_password)"
fill_if_empty GITHUB_WEBHOOK_SECRET  "$(random_hex)"
fill_if_empty SONAR_WEBHOOK_SECRET   "$(random_hex)"

echo "Machine settings:"
# The group that owns the Docker socket - Jenkins needs to be in it to run docker commands
gid="$(stat -c %g /var/run/docker.sock 2>/dev/null || getent group docker | cut -d: -f3 || true)"
if [ -n "$gid" ]; then
    set_value DOCKER_GID "$gid"; echo "  DOCKER_GID: $gid"
else
    echo "  DOCKER_GID: Docker not found - left at $(get DOCKER_GID). Run setup-ubuntu-host.sh first."
fi

# Optional settings passed in as environment variables
for name in JENKINS_PUBLIC_URL GITHUB_REPO_URL GITHUB_BRANCH DOCKERHUB_USERNAME; do
    if [ -n "${!name:-}" ]; then
        set_value "$name" "${!name}"; echo "  $name: ${!name}"
    fi
done

echo
echo "Still to fill in yourself (nano $ENV_FILE):"
missing="no"
[ -n "$(get DOCKERHUB_TOKEN)" ] || { echo "  - DOCKERHUB_TOKEN: Docker Hub access token (Read & Write)"; missing="yes"; }
[ -n "$(get SONAR_TOKEN)" ]     || { echo "  - SONAR_TOKEN: create it in SonarQube after the first start (guide, Step 9)"; missing="yes"; }
[ "$missing" = "yes" ] || echo "  nothing"
echo
echo "Jenkins login: user '$(get JENKINS_ADMIN_USER)', password = JENKINS_ADMIN_PASSWORD in $ENV_FILE"
echo "Check the file:  cd $CICD_DIR && docker compose config --quiet   (prints nothing when it is complete)"
