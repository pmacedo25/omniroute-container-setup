#!/bin/sh
set -eu

# shellcheck source=/usr/local/lib/skills-sync.sh
. /usr/local/lib/skills-sync.sh

interval="${SKILLS_SYNC_INTERVAL_SECONDS:-3600}"

while :; do
    if ! run_sync; then
        log "Sincronização falhou; o catálogo publicado anteriormente foi preservado."
    fi

    if [ "${SKILLS_SYNC_ONCE:-false}" = "true" ]; then
        exit 0
    fi

    sleep "$interval" &
    wait $! || true
done
