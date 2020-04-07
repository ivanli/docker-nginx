#!/usr/bin/env bash

echo "Waiting for quiet period..."
while inotifywait -t 60 -r -e create -e modify -e delete /etc/letsencrypt /conf /etc/docker/environment
do
  echo "... more changes detected, waiting again..."
done
echo "... no more file changes detected."

echo "Reloading nginx..."
/docker-entrypoint.sh /usr/sbin/nginx -s reload
if [ $? -ne 0 ]; then
  echo "... failed to reload nginx, killing nginx to force restart"
  kill -SIGQUIT $(cat /var/run/nginx.pid || echo 1)
  exit 1
fi

sleep 10

if [ $(pidof nginx | grep -o '[0-9]\+' | wc -l) -lt 3 ]; then
  echo "... failed to detect 3+ nginx processes, killing nginx to force restart"
  kill -SIGQUIT $(cat /var/run/nginx.pid || echo 1)
  exit 1
fi

echo "... nginx reloaded successfully."