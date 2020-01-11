#!/usr/bin/env bash

while inotifywait -t 30 -r -e create -e modify -e delete /etc/letsencrypt /conf /etc/docker/environment
do
  echo "... more changes detected, waiting again..."
done

/docker-entrypoint.sh /usr/sbin/nginx -s reload
