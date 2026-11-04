#!/bin/bash
# EC2 "user data": AWS runs this script once, as root, when a new instance starts for the first time.
# Paste the whole file into  EC2 -> Launch instance -> Advanced details -> User data
# (or pass it with the AWS CLI: --user-data file://cicd/aws/user-data.sh).
#
# What it does - so the instance is ready when you log in:
#   1. clones this repository into /home/ubuntu/simple-spring-boot-app
#   2. runs cicd/scripts/setup-ubuntu-host.sh  (Docker, Docker Compose, kernel settings, swap, log rotation)
#   3. runs cicd/scripts/create-env.sh         (cicd/.env with new random passwords and secrets)
# It does NOT start the containers: first you add your Docker Hub token to .env (guide, Step 6).
#
# Never put tokens or passwords into user data - anyone who may view the instance's settings can read it.
# Progress and errors: /var/log/cloud-init-output.log on the instance. Guide: cicd/AWS-EC2-GUIDE.md
set -euxo pipefail

# ---- Settings: change them if you use a fork, another branch or another Linux user -------------------
REPO_URL="https://github.com/Manivannanbgi007/simple-spring-boot-app.git"
BRANCH="master"
APP_USER="ubuntu"          # the default user of Ubuntu AMIs
SWAP_SIZE="4G"             # 0 = no swap file
# The address you open Jenkins at - through the SSH tunnel of the guide (Step 8). Used for links in Jenkins.
JENKINS_PUBLIC_URL="http://localhost:18079/"
# -------------------------------------------------------------------------------------------------------

REPO_DIR="/home/$APP_USER/simple-spring-boot-app"

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q git

if [ ! -d "$REPO_DIR/.git" ]; then
    sudo -u "$APP_USER" git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

bash "$REPO_DIR/cicd/scripts/setup-ubuntu-host.sh" --user "$APP_USER" --swap "$SWAP_SIZE"
sudo -u "$APP_USER" env JENKINS_PUBLIC_URL="$JENKINS_PUBLIC_URL" bash "$REPO_DIR/cicd/scripts/create-env.sh"

echo "DevOps host setup finished at $(date -u '+%Y-%m-%d %H:%M UTC')" | tee /var/log/devops-setup.done
