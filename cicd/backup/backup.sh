#!/bin/sh
# Backs up the Jenkins data (volume jenkins_home) and the SonarQube database into cicd/backups/<date_time>/.
# Runs inside the 'backup' container of docker-compose.yml. From the cicd folder:
#
#   docker compose stop jenkins          # no build may write files during the backup
#   docker compose run --rm backup
#   docker compose start jenkins
#
# Restore: restore.sh in this folder.
set -eu

STAMP=$(date -u +%Y-%m-%d_%H%M)
DIR="/backups/$STAMP"
mkdir -p "$DIR"

echo "Jenkins data -> backups/$STAMP/jenkins_home.tar.gz"
# Keep jobs, build history, credentials and settings. Leave out what is recreated automatically:
#   workspace (build folders), .m2 / .sonar / .cache / caches (downloads), war (Jenkins program files),
#   plugins (installed again from the image, see jenkins/plugins.txt)
tar -czf "$DIR/jenkins_home.tar.gz" --numeric-owner -C /var/jenkins_home \
    --exclude=./workspace --exclude=./.m2 --exclude=./.sonar --exclude=./.cache --exclude=./caches \
    --exclude=./war --exclude=./plugins .

echo "SonarQube database -> backups/$STAMP/sonarqube_db.dump"
# The search index (volume sonarqube_data) is not needed: SonarQube rebuilds it from the database
pg_dump --format=custom --file="$DIR/sonarqube_db.dump"

ls -lh "$DIR"
echo "Backup finished: cicd/backups/$STAMP (time in UTC)"
