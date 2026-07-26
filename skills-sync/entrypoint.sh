#!/bin/sh
set -eu

repository="${OMNIROUTE_SKILLS_REPO:?OMNIROUTE_SKILLS_REPO is required}"
branch="${OMNIROUTE_SKILLS_BRANCH:-main}"
skills_dir="/skills"
interval="${SKILLS_SYNC_INTERVAL_SECONDS:-3600}"

sync_repository() {
    if [ -d "$skills_dir/.git" ]; then
        git -C "$skills_dir" remote set-url origin "$repository"
        git -C "$skills_dir" fetch --depth 1 origin "$branch"
        git -C "$skills_dir" reset --hard "origin/$branch"
        return
    fi

    if [ -n "$(find "$skills_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        echo "[skills] Diretório não vazio e sem .git; preservado para evitar perda de dados." >&2
        return
    fi

    git clone --depth 1 --branch "$branch" "$repository" "$skills_dir"
}

while :; do
    if ! sync_repository; then
        echo "[skills] Sincronização falhou; o conteúdo anterior foi preservado." >&2
    fi
    sleep "$interval" &
    wait $!
done
