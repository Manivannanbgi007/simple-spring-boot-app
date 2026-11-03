#!/bin/sh
# Restores a backup made by backup.sh. REPLACES the current Jenkins data and SonarQube database.
# Runs inside the 'backup' container of docker-compose.yml. From the cicd folder:
#
#   docker compose stop jenkins sonarqube
#   docker compose run --rm backup restore.sh 2026-11-03_0930     # a folder name in cicd/backups/
#   docker compose start jenkins sonarqube
set -eu

STAMP="${1:?Usage: restore.sh <folder name in cicd/backups, for example 2026-11-03_0930>}"
DIR="/backups/$STAMP"
[ -f "$DIR/jenkins_home.tar.gz" ] && [ -f "$DIR/sonarqube_db.dump" ] || {
    echo "ERROR: backups/$STAMP does not contain jenkins_home.tar.gz and sonarqube_db.dump"
    exit 1
}

echo "Jenkins data <- backups/$STAMP/jenkins_home.tar.gz"
find /var/jenkins_home -mindepth 1 -delete
tar -xzf "$DIR/jenkins_home.tar.gz" --numeric-owner -C /var/jenkins_home

echo "SonarQube database <- backups/$STAMP/sonarqube_db.dump"
pg_restore --clean --if-exists --no-owner --dbname="$PGDATABASE" "$DIR/sonarqube_db.dump"

echo "Deleting SonarQube's search index - SonarQube rebuilds it from the database at the next start"
find /sonarqube_data -mindepth 1 -delete

echo "Restore finished. Start the services: docker compose start jenkins sonarqube"
