#!/bin/sh
# idle.sh IMAGE NAME [-e VAR=VALUE ...]: runs the image as Atlas does (1 CPU, 2 GiB), with no database, and reports what it holds idle
image=$1; name=$2; shift 2
docker rm -f "$name" >/dev/null 2>&1
docker run -d --name "$name" --cpus 1 --memory 2g -e DB_HOST=127.0.0.1 -e DB_NAME=none -e DB_USER=none -e DB_PASS=none "$@" "$image" >/dev/null || exit 1
sleep 6
sleep 12
stat() { docker exec "$name" cat /sys/fs/cgroup/memory.stat | awk -v k="$1" '$1==k {printf "%.0f", $2/1048576}'; }
echo "anon $(stat anon) MiB | file $(stat file) MiB | threads $(docker exec "$name" sh -c 'ls /proc/1/task | wc -l')"
