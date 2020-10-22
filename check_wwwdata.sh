#!/usr/bin/env bash

function permission() {

  if [[ $(find ${NGINX_DOCROOT} ! -perm 775 -type d | wc -l) -gt 0 ]] || [[ $(find ${NGINX_DOCROOT} ! -perm 664 -type f | wc -l) -gt 0 ]]; then
    echo "ERROR: There are permissions issues with directories and/or files within ${NGINX_DOCROOT}"
    #/usr/bin/env bash -c 'find {{NGINX_DOCROOT}} -type d -exec chmod 775 {} \; && find {{NGINX_DOCROOT}} -type f -exec chmod 664 {} \;'
    exit 1
  else
    echo "OK: Permissions 775 (dir) and 664 (files) look correct on ${NGINX_DOCROOT}"
  fi

}

function owner() {

  if [[ $(find ${NGINX_DOCROOT} ! -user www-data | wc -l) -gt 0 ]]; then
    echo "ERROR: Incorrect user:group are set within ${NGINX_DOCROOT}"
    #/usr/bin/env bash -c 'find /usr/share/nginx/html -type d -exec chown www-data:www-data {} \; && find {{NGINX_DOCROOT}} -type f -exec chown www-data:www-data {} \;'
    exit 1
  else
    echo "OK: www-data (user:group) ownership looks correct on ${NGINX_DOCROOT}"
  fi

}

"$@"
