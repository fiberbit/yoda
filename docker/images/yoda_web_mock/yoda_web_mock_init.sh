#!/bin/bash

set -e
set -o pipefail
set -u

DATA_VERSION="$1"

if [ -z "$DATA_VERSION" ]
then echo "Error: no data version argument provided."
     exit 1
fi

function before_update {
  echo -e "[...] ${1}"
}

function progress_update {
  GREEN='\033[0;32m'
  RESET='\033[0m'
  echo -e "[ ${GREEN}\xE2\x9C\x94${RESET} ] ${1}"
}

function start_service {
  apache2ctl -D FOREGROUND || true
  echo "Error: Apache either terminated or would not start. Keeping container running for troubleshooting purposes."
  sleep infinity
}

if [ -f "/container_initialized" ]
then echo "Container has already been initialized. Starting service."
     start_service
fi

# Download and install certificates
before_update "Downloading certificate bundle"
mkdir /download
wget -q "https://yoda.uu.nl/yoda-docker/${DATA_VERSION}.certbundle.tar.gz" -O "/download/${DATA_VERSION}.certbundle.tar.gz"
progress_update "Downloaded certificate bundle."

# Extract certificate bundle
before_update "Extracting certificate data"
cd /download
tar xvfz "${DATA_VERSION}.certbundle.tar.gz"
install -m 0644 docker.pem /etc/ssl/certs/localhost.crt
install -m 0644 docker.pem /etc/ssl/certs/localhost_and_chain.crt
install -m 0644 docker.key /etc/ssl/private/localhost.key
install -m 0644 dhparam.pem /etc/ssl/private/dhparams.pem
progress_update "Certificate data extracted"

# Configure Vhost with right mock name and FQDN
before_update "Configuring Vhost."
perl -pi.bak -e '$mockname=$ENV{MOCKNAME}; s/MOCKNAME/$mockname/gee' /etc/apache2/sites-available/yoda-web-mock-vhost.conf
perl -pi.bak -e '$mockfqdn=$ENV{MOCKNAME}; s/MOCKFQDN/$mockfqdn/gee' /etc/apache2/sites-available/yoda-web-mock-vhost.conf
progress_update "Vhost configured."

CURRENT_UID="$(id -u yodadeployment)"
if  [[ -f "/var/www/webmock/yoda-web-mock/.docker.gitkeep" ]]
then progress_update "Bind mount detected. Checking if application UID needs to be changed."
     MOUNT_UID="$(stat -c "%u" /var/www/webmock/yoda-web-mock)"
     if [ "$MOUNT_UID" == "0" ]
     then progress_update "Error: bind mount owned by root user. Cannot change application UID. Halting."
          sleep infinity
     elif [ "$MOUNT_UID" == "$CURRENT_UID" ]
     then progress_update "Notice: bind mount UID matches application UID. No need to change application UID."
     else before_update "Updating application UID ${CURRENT_UID} -> ${MOUNT_UID}"
          usermod -u "$MOUNT_UID" yodadeployment
          find / -xdev -user "$CURRENT_UID" -exec chown -h "${MOUNT_UID}" {} \;
          progress_update "Application UID updated."
     fi
     if [[ -d "/var/www/webmock/yoda-web-mock/.git" ]]
     then echo "Git repo detected in bind mounts. Skipping code copy in order not to overwrite local changes."
     else
         before_update "Fixing up permissions before copying application source code."
         find /var/www/webmock/yoda-web-mock-copy -type f -perm 0444 -exec chmod 0666 {} \;
         progress_update "Permission fixes done."
         before_update "Copying application source code to volume."
         cp -Ru /var/www/webmock/yoda-web-mock-copy/. /var/www/webmock/yoda-web-mock
         progress_update "Copying application source code finished."
     fi
else progress_update "Notice: no bind mount detected. Keeping current application UID ${CURRENT_UID}"
fi


# Start Apache
touch /container_initialized

before_update "Initialization complete. Starting Apache"
start_service
