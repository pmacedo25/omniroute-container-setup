#!/bin/sh
set -eu

# shellcheck source=/usr/local/lib/skills-sync.sh
. /usr/local/lib/skills-sync.sh

interval="${SKILLS_SYNC_INTERVAL_SECONDS:-3600}"

while :; do
    sync_status=0
    if ! run_sync; then
        sync_status=1
        log "Sincronização falhou; o catálogo publicado anteriormente foi preservado."
    fi

    if [ "${SKILLS_SYNC_ONCE:-false}" = "true" ]; then
        exit "$sync_status"
    fi

    sleep "$interval" &
    wait $! || true
done
