#!/usr/bin/env bash

function permission() {

  if [[ $(find ${NGINX_DOCROOT} ! -perm 775 -type d | wc -l) -gt 0 ]] || [[ $(find ${NGINX_DOCROOT} ! -perm 664 -type f | wc -l) -gt 0 ]]; then
    echo "ERROR: There are permissions issues with directories and/or files within ${NGINX_DOCROOT}"
    exit 1
  else
    echo "OK: Permissions 775 (dir) and 664 (files) look correct on ${NGINX_DOCROOT}"
  fi

}

function owner() {

  if [[ $(find ${NGINX_DOCROOT} ! -user www-data | wc -l) -gt 0 ]]; then
    echo "ERROR: Incorrect user:group are set within ${NGINX_DOCROOT}"
    exit 1
  else
    echo "OK: www-data (user:group) ownership looks corect on ${NGINX_DOCROOT}"
  fi

}

"$@"
