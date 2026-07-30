#!/bin/sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/source/.agents/task-workflows" "$test_root/output"
cat > "$test_root/source/.agents/task-workflows/testing.md" <<'EOF'
# Testes

Use este guia quando criar e revisar testes.
EOF
cat > "$test_root/source/AGENTS.md" <<'EOF'
# AGENTS.md

Carregue contexto em camadas.
EOF

SKILLS_SOURCE_DIR="$test_root/source"
SKILLS_OUTPUT_DIR="$test_root/output"
OMNIROUTE_SKILLS_REPO="fixture"
export SKILLS_SOURCE_DIR SKILLS_OUTPUT_DIR OMNIROUTE_SKILLS_REPO

# shellcheck source=./sync-lib.sh
. "$script_dir/sync-lib.sh"
run_sync

catalog="$test_root/output/.project-agents-templates/catalog.json"
test "$(jq -r '.schemaVersion' "$catalog")" = "1"
test "$(jq -r '.skills | length' "$catalog")" = "2"
test "$(jq -r '.skills[] | select(.id == "pat-task-workflows-testing") | .name' "$catalog")" = "Testes"
grep -q '^name: "pat-task-workflows-testing"$' \
    "$test_root/output/pat-task-workflows-testing/SKILL.md"
grep -q '^description: "Use este guia quando criar e revisar testes\."$' \
    "$test_root/output/pat-task-workflows-testing/SKILL.md"
grep -q '^disable-model-invocation: false$' \
    "$test_root/output/pat-task-workflows-testing/SKILL.md"
grep -q '^disable-model-invocation: true$' \
    "$test_root/output/pat-project-governance/SKILL.md"
grep -q '^  tags: \["task","workflows","testing"\]$' \
    "$test_root/output/pat-task-workflows-testing/SKILL.md"

# Skills not managed by this repository must survive updates.
mkdir -p "$test_root/output/user-owned"
printf '%s\n' '# User skill' > "$test_root/output/user-owned/SKILL.md"
run_sync
test -f "$test_root/output/user-owned/SKILL.md"

# A source failure must preserve the last valid catalog instead of publishing
# an empty replacement.
previous_hash="$(sha256sum "$catalog" | awk '{print $1}')"
SKILLS_SOURCE_DIR="$test_root/missing"
export SKILLS_SOURCE_DIR
if run_sync; then
    log "Fonte ausente deveria falhar."
    exit 1
fi
test "$previous_hash" = "$(sha256sum "$catalog" | awk '{print $1}')"

log "Testes de conversão concluídos."
