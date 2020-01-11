#!/usr/bin/env bash

while inotifywait -t 60 -r -e create -e modify -e delete /etc/letsencrypt /conf /etc/docker/environment
do
  echo "... more changes detected, waiting again..."
done

/usr/bin/env bash -c '/usr/sbin/nginx -s reload'