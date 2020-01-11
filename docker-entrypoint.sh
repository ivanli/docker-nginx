#!/usr/bin/env bash

set -xu

#---------------------------------------------------------------------
# configure environment
#---------------------------------------------------------------------

function environment() {


  # Set the ROOT directory for apps and content
  if [[ -z ${NGINX_DOCROOT} ]]; then NGINX_DOCROOT=/usr/share/nginx/html && export NGINX_DOCROOT && mkdir -p "${NGINX_DOCROOT}"; fi
  if [[ -z ${NGINX_PROXY_UPSTREAM} ]]; then NGINX_PROXY_UPSTREAM="localhost:8080;" && export NGINX_PROXY_UPSTREAM; fi

  source /etc/docker/environment/default.env

  if [[ -z ${DOMAINS} ]]; then echo "Required variable DOMAINS not set" && exit 1; fi
  if [[ -z ${NGINX_PHP_FPM_URL} ]]; then echo "Required variable NGINX_PHP_FPM_URL not set" && exit 1; fi
  if [[ -z ${NGINX_REDIS_URL} ]]; then echo "Required variable NGINX_REDIS_URL not set" && exit 1; fi

}

#---------------------------------------------------------------------
# setup monit configuration
#---------------------------------------------------------------------

function monit() {
  {
    echo 'set daemon 10'
    echo '    with START DELAY 15'
    echo 'set pidfile /run/monit.pid'
    echo 'set statefile /run/monit.state'
    echo 'set httpd port 2849 and'
    echo '    use address localhost'
    echo '    allow localhost'
    echo 'set log /var/log/monit'
    echo 'set eventqueue'
    echo '    basedir /var/monit'
    echo '    slots 100'
    echo 'include /etc/monit.d/*.conf'
  } | tee /etc/monitrc

  local IFS=";"
  for server_name in ${DOMAINS}; do
    echo "###   Creating monit config for ${server_name}..."
    cp /etc/monit.d/check_site.conf.template /etc/monit.d/${server_name}.conf
    sed -i -e 's|{{SERVER_NAME}}|'"${server_name}"'|g' /etc/monit.d/${server_name}.conf
  done

  chmod 700 /etc/monitrc
  RUN="monit -c /etc/monitrc" && /usr/bin/env bash -c "${RUN}"
}

#---------------------------------------------------------------------
# set variables
#---------------------------------------------------------------------

function config() {

  # Copy the configs to the main nginx and monit conf directories
  echo "### Syncing configurations"
  rsync -av --ignore-missing-args /conf/nginx/* ${CONF_PREFIX}/
  rsync -av --ignore-missing-args /conf/monit/* /etc/monit.d/

  echo "### Creating assets..."

  local IFS=";"
  for server_name in ${DOMAINS}; do
    if [[ ! -d ${NGINX_CERTROOT}/live/${server_name} ]] || [[ ! -d ${NGINX_CERTROOT}/live/www.${server_name} ]]; then
      echo "###   Certificates not found for ${server_name}, skipping..."
      continue
    fi

    # Initialise directory if it doesn't exist, install default server files
    if [[ ! -d ${NGINX_DOCROOT}/${server_name} ]]; then
      echo "###   DOCROOT for ${server_name} doesn't exist, creating..."
      mkdir -p ${NGINX_DOCROOT}/${server_name}
      mkdir -p ${NGINX_DOCROOT}/${server_name}/testing/
      mkdir -p ${NGINX_DOCROOT}/${server_name}/error/

      rsync -av --ignore-missing-args /tmp/test/* ${NGINX_DOCROOT}/${server_name}/testing/
      rsync -av --ignore-missing-args /tmp/error/* ${NGINX_DOCROOT}/${server_name}/error/
    fi

    # Create a new vhost file if it doesn't exist.
    if [[ ! -f ${CONF_PREFIX}/sites-available/${server_name}.vhost ]]; then
      echo "###   Creating .vhost for ${server_name}..."
      cp ${CONF_PREFIX}/sites-available/site-https.vhost.template ${CONF_PREFIX}/sites-available/${server_name}.vhost
      sed -i -e 's|{{SERVER_NAME}}|'"${server_name}"'|g' ${CONF_PREFIX}/sites-available/${server_name}.vhost
    fi
  done

  rm ${CONF_PREFIX}/sites-available/site-https.vhost.template

  # Replace all variables
  # Set the ENV variables in all configs
  find "${CONF_PREFIX}" -maxdepth 5 -type f -exec sed -i -e 's|{{NGINX_DOCROOT}}|'"${NGINX_DOCROOT}"'|g' {} \;
  find "${CONF_PREFIX}" -maxdepth 5 -type f -exec sed -i -e 's|{{NGINX_CERTROOT}}|'"${NGINX_CERTROOT}"'|g' {} \;
  find "${CONF_PREFIX}" -maxdepth 5 -type f -exec sed -i -e 's|{{CACHE_PREFIX}}|'"${CACHE_PREFIX}"'|g' {} \;
  find "${CONF_PREFIX}" -maxdepth 5 -type f -exec sed -i -e 's|{{LOG_PREFIX}}|'"${LOG_PREFIX}"'|g' {} \;

  # Replace Upstream servers
  find "${CONF_PREFIX}" -maxdepth 5 -type f -exec sed -i -e 's|{{NGINX_PROXY_UPSTREAM}}|'"${NGINX_PROXY_UPSTREAM}"'|g' {} \;
  find "${CONF_PREFIX}" -maxdepth 5 -type f -exec sed -i -e 's|{{NGINX_PHP_FPM_URL}}|'"${NGINX_PHP_FPM_URL}"'|g' {} \;
  find "${CONF_PREFIX}" -maxdepth 5 -type f -exec sed -i -e 's|{{NGINX_REDIS_URL}}|'"${NGINX_REDIS_URL}"'|g' {} \;
  find "${CONF_PREFIX}" -maxdepth 5 -type f -exec sed -i -e 's|{{NGINX_CERTBOT_URL}}|'"${NGINX_CERTBOT_URL}"'|g' {} \;

  # Replace monit variables
  find "/etc/monit.d" -maxdepth 3 -type f -exec sed -i -e 's|{{NGINX_DOCROOT}}|'"${NGINX_DOCROOT}"'|g' {} \;
  find "/etc/monit.d" -maxdepth 3 -type f -exec sed -i -e 's|{{CACHE_PREFIX}}|'"${CACHE_PREFIX}"'|g' {} \;
}

#---------------------------------------------------------------------
# install self-signed SSL certs for local dev
#---------------------------------------------------------------------

function dev() {
  local IFS=";"
  for server_name in ${DOMAINS}; do
    # Typically these will be mounted via volume, but in case someone
    # needs a dev context this will set the certs so the server will
    # have the basics it needs to run
    if [[ ! -f /etc/letsencrypt/live/${server_name}/privkey.pem ]] || [[ ! -f /etc/letsencrypt/live/${server_name}/fullchain.pem ]]; then
      echo "OK: Installing development SSL certificates for ${server_name}..."
      mkdir -p /etc/letsencrypt/live/${server_name}
      /usr/bin/env bash -c "openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj /C=US/ST=MA/L=Boston/O=ACMECORP/CN=${server_name} -keyout /etc/letsencrypt/live/${server_name}/privkey.pem -out /etc/letsencrypt/live/${server_name}/fullchain.pem"
      cp /etc/letsencrypt/live/${server_name}/fullchain.pem  /etc/letsencrypt/live/${server_name}/chain.pem
    fi
    if [[ ! -f /etc/letsencrypt/live/www.${server_name}/privkey.pem ]] || [[ ! -f /etc/letsencrypt/live/www.${server_name}/fullchain.pem ]]; then
      echo "OK: Installing development SSL certificates for www.${server_name}..."
      mkdir -p /etc/letsencrypt/live/www.${server_name}
      /usr/bin/env bash -c "openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj /C=US/ST=MA/L=Boston/O=ACMECORP/CN=www.${server_name} -keyout /etc/letsencrypt/live/www.${server_name}/privkey.pem -out /etc/letsencrypt/live/www.${server_name}/fullchain.pem"
      cp /etc/letsencrypt/live/www.${server_name}/fullchain.pem  /etc/letsencrypt/live/www.${server_name}/chain.pem
    fi
  done
}


#---------------------------------------------------------------------
# install bad bot protection
#---------------------------------------------------------------------

function bots() {
  # https://github.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker

  mkdir -p /etc/nginx/sites-available
  cd /usr/sbin || exit
  wget https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/master/install-ngxblocker -O install-ngxblocker
  wget https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/master/setup-ngxblocker -O setup-ngxblocker
  wget https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/master/update-ngxblocker -O update-ngxblocker
  chmod +x install-ngxblocker
  chmod +x setup-ngxblocker
  chmod +x update-ngxblocker
  install-ngxblocker -x
  setup-ngxblocker -x -w ${NGINX_DOCROOT}
  echo "OK: Clean up variables..."
  sed -i -e 's|^variables_hash_max_|#variables_hash_max_|g' /etc/nginx/conf.d/botblocker-nginx-settings.conf
}

#---------------------------------------------------------------------
# configure SSL
#---------------------------------------------------------------------

function openssl() {

  # The first argument is the bit depth of the dhparam, or 2048 if unspecified
  DHPARAM_BITS=${1:-2048}

  # If a dhparam file is not available, use the pre-generated one and generate a new one in the background.
  PREGEN_DHPARAM_FILE=${CERTS_PREFIX}/dhparam.pem.default
  DHPARAM_FILE=${CERTS_PREFIX}/dhparam.pem
  GEN_LOCKFILE=/tmp/dhparam_generating.lock

  if [[ ! -f ${PREGEN_DHPARAM_FILE} ]]; then
     echo "OK: NO PREGEN_DHPARAM_FILE is present. Generate ${PREGEN_DHPARAM_FILE}..."
     nice -n +5 openssl dhparam -out ${DHPARAM_FILE} 2048 2>&1
  fi

  if [[ ! -f ${DHPARAM_FILE} ]]; then
     # Put the default dhparam file in place so we can start immediately
     echo "OK: NO DHPARAM_FILE present. Copy ${PREGEN_DHPARAM_FILE} to ${DHPARAM_FILE}..."
     cp ${PREGEN_DHPARAM_FILE} ${DHPARAM_FILE}
     touch ${GEN_LOCKFILE}

     # The hash of the pregenerated dhparam file is used to check if the pregen dhparam is already in use
     PREGEN_HASH=$(md5sum ${PREGEN_DHPARAM_FILE} | cut -d" " -f1)
     CURRENT_HASH=$(md5sum ${DHPARAM_FILE} | cut -d" " -f1)
     if [[ "${PREGEN_HASH}" != "${CURRENT_HASH}" ]]; then
      nice -n +5 openssl dhparam -out ${DHPARAM_FILE} ${DHPARAM_BITS} 2>&1
      rm ${GEN_LOCKFILE}
    fi
  fi

  # Add Let's Encrypt CA in case it is needed
  mkdir -p /etc/ssl/private
  cd /etc/ssl/private || exit
  wget -O - https://letsencrypt.org/certs/isrgrootx1.pem https://letsencrypt.org/certs/lets-encrypt-x1-cross-signed.pem https://letsencrypt.org/certs/letsencryptauthorityx1.pem https://www.identrust.com/certificates/trustid/root-download-x3.html | tee -a ca-certs.pem> /dev/null

}

function run() {
  environment
  openssl
  if [[ ${NGINX_DEV_INSTALL} = "true" ]]; then dev; fi
  config
  bots
  monit
}

run

exec "$@"
