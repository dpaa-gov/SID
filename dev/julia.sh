#!/bin/sh
# Runs Julia with DB_* from .env: the host's Julia 1.13 if there is one,
# otherwise a container on the dev network.
#
#   dev/julia.sh -e 'using SIDServer; SIDServer.main()'
#   dev/julia.sh -e 'using Pkg; Pkg.test()'                # server tests (need ARDS)
#   PROJECT=SIDJ dev/julia.sh -e 'using Pkg; Pkg.test()'   # SIDJ tests
set -eu
cd "$(dirname "$0")/.."
PATH="$HOME/.juliaup/bin:$PATH"

if [ "${USE_DOCKER:-0}" != 1 ] && command -v julia >/dev/null 2>&1 && julia +1.13 --version >/dev/null 2>&1; then
    if [ -f .env ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in '#'*) continue ;; *=*) export "${line%%=*}=${line#*=}" ;; esac
        done < .env
    fi
    # .env names the ARDS container; from the host it is the published port
    [ "${DB_HOST:-}" = ards-db ] && export DB_HOST=127.0.0.1
    exec julia +1.13 --project="${PROJECT:-server}" --threads=2,1 "$@"
fi

depot="${XDG_CACHE_HOME:-$HOME/.cache}/sid/julia-depot"
mkdir -p "$depot"
exec docker run --rm -i --network sid-dev $([ -f .env ] && echo "--env-file .env") \
    --user "$(id -u):$(id -g)" -e HOME=/tmp -e JULIA_DEPOT_PATH=/depot \
    ${PUBLISH:+-p 127.0.0.1:$PUBLISH:3838} \
    -v "$depot:/depot:z" -v "$PWD:/app:z" -w /app \
    julia:1.13 julia --project="${PROJECT:-server}" --threads=2,1 "$@"
