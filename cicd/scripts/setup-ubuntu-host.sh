#!/usr/bin/env bash
# Prepares a fresh Ubuntu server (for example an AWS EC2 instance) for the CI/CD environment in cicd/:
#   - Docker Engine and the Docker Compose plugin, from Docker's own apt repository
#   - lets one user run docker without sudo
#   - the kernel settings SonarQube's search engine needs
#   - log rotation for all containers, and a swap file (protects a small server from running out of memory)
#   - optional: Java 21 - only needed to run Maven on the server itself; the pipeline brings its own Java
#
# Run it once on the server, with sudo. Running it again is safe: every step checks first.
#   sudo bash cicd/scripts/setup-ubuntu-host.sh                  # for the user who runs sudo
#   sudo bash cicd/scripts/setup-ubuntu-host.sh --with-java      # also install Java 21
# Options:  --user <name>   --swap <size, e.g. 4G; 0 = no swap file>   --with-java
#
# On AWS, cicd/aws/user-data.sh runs this script automatically when the instance is created.
# Guide: cicd/AWS-EC2-GUIDE.md
set -euo pipefail

TARGET_USER="${SUDO_USER:-ubuntu}"
SWAP_SIZE="4G"
WITH_JAVA="no"

while [ $# -gt 0 ]; do
    case "$1" in
        --user)      TARGET_USER="$2"; shift 2 ;;
        --swap)      SWAP_SIZE="$2"; shift 2 ;;
        --with-java) WITH_JAVA="yes"; shift ;;
        -h|--help)   sed -n '2,15p' "$0"; exit 0 ;;
        *)           echo "Unknown option: $1 (see --help)"; exit 1 ;;
    esac
done

[ "$(id -u)" -eq 0 ] || { echo "Please run with sudo: sudo bash $0 $*"; exit 1; }
# shellcheck source=/dev/null
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || { echo "This script is for Ubuntu (this machine: ${ID:-unknown})"; exit 1; }
id "$TARGET_USER" >/dev/null 2>&1 || { echo "User '$TARGET_USER' does not exist (use --user <name>)"; exit 1; }

step() { echo; echo "==> $*"; }
# systemd runs on a real server; in a test container it doesn't, so services are left alone there
has_systemd() { [ -d /run/systemd/system ]; }
export DEBIAN_FRONTEND=noninteractive

step "Base packages"
apt-get update -q
apt-get install -y -q ca-certificates curl git openssl

step "Docker Engine + Docker Compose (Docker's apt repository)"
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    echo "already installed"
else
    # Ubuntu's own Docker packages conflict with Docker's packages - remove them if present
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        apt-get remove -y -q "$pkg" >/dev/null 2>&1 || true
    done
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -q
    apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

step "Log rotation for all containers (at most 3 files of 10 MB each)"
# Without it, a container's log grows until the disk is full
daemon_changed="no"
if [ -f /etc/docker/daemon.json ]; then
    echo "/etc/docker/daemon.json already exists - left unchanged"
else
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
    daemon_changed="yes"
    echo "written: /etc/docker/daemon.json"
fi

step "Start Docker now and at every boot"
if has_systemd; then
    systemctl enable --now containerd docker
    [ "$daemon_changed" = "no" ] || systemctl restart docker
    systemctl is-active docker
else
    echo "no systemd (test container?) - skipped"
fi

step "Allow '$TARGET_USER' to run docker without sudo"
usermod -aG docker "$TARGET_USER"
echo "added to group 'docker' (takes effect at the next login)"

step "Kernel settings for SonarQube (Elasticsearch)"
cat > /etc/sysctl.d/99-sonarqube.conf <<'EOF'
# Required by SonarQube's search engine (Elasticsearch)
vm.max_map_count=524288
fs.file-max=131072
EOF
sysctl --system >/dev/null
sysctl vm.max_map_count fs.file-max

step "Swap file ($SWAP_SIZE)"
if [ "$SWAP_SIZE" = "0" ]; then
    echo "skipped (--swap 0)"
elif [ -n "$(swapon --show --noheadings)" ]; then
    echo "swap is already active - left unchanged"
else
    fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    # Use the swap file only when memory is really short
    echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
    sysctl -p /etc/sysctl.d/99-swappiness.conf >/dev/null
    swapon --show
fi

if [ "$WITH_JAVA" = "yes" ]; then
    step "Java 21 (OpenJDK)"
    apt-get install -y -q openjdk-21-jdk-headless
    java -version
fi

step "Done"
docker --version
docker compose version
echo "Group number of the Docker socket (DOCKER_GID in cicd/.env): $(getent group docker | cut -d: -f3)"
echo "Log out and in again, so that '$TARGET_USER' can run docker without sudo."
