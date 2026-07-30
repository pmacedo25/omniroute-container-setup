#!/bin/sh
set -eu

log() {
    printf '[skills] %s\n' "$*" >&2
}

slugify() {
    printf '%s' "$1" |
        tr '[:upper:]_' '[:lower:]-' |
        sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

git_with_auth() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        # GitHub's smart-HTTP Git endpoint expects HTTP Basic authentication.
        # Keep the credential in an ephemeral header instead of writing it to
        # the clone URL or a credential store.
        basic_auth="$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\r\n')"
        git -c "http.extraHeader=Authorization: Basic ${basic_auth}" "$@"
    else
        git "$@"
    fi
}

sync_source_repository() {
    repository="${SKILLS_REPOSITORY:-${OMNIROUTE_SKILLS_REPO:-}}"
    repository="${repository:?SKILLS_REPOSITORY is required}"
    branch="${SKILLS_BRANCH:-${OMNIROUTE_SKILLS_BRANCH:-main}}"
    source_dir="${SKILLS_SOURCE_DIR:-/state/source}"

    if [ -n "${SKILLS_SOURCE_DIR:-}" ]; then
        [ -d "$source_dir" ] || {
            log "SKILLS_SOURCE_DIR não existe: $source_dir"
            return 1
        }
        return
    fi

    if [ -d "$source_dir/.git" ]; then
        git -C "$source_dir" remote set-url origin "$repository"
        git_with_auth -C "$source_dir" fetch --depth 1 origin "$branch"
        git -C "$source_dir" reset --hard "origin/$branch"
        return
    fi

    [ ! -e "$source_dir" ] || {
        log "Staging de origem existe sem .git; preservado: $source_dir"
        return 1
    }
    mkdir -p "$(dirname "$source_dir")"
    git_with_auth clone --depth 1 --branch "$branch" "$repository" "$source_dir"
}

extract_title() {
    title="$(sed -n -E 's/^#[[:space:]]+//p' "$1" | head -n 1)"
    if [ -n "$title" ]; then
        printf '%s' "$title"
    else
        basename "$1" .md | tr '-' ' '
    fi
}

extract_summary() {
    awk '
        /^---[[:space:]]*$/ { frontmatter = !frontmatter; next }
        frontmatter { next }
        /^#/ { next }
        /^[[:space:]]*$/ { next }
        /^<!--/ { next }
        { gsub(/^[[:space:]]*[-*][[:space:]]*/, ""); print; exit }
    ' "$1" | cut -c1-320
}

skill_description() {
    source_file="$1"
    relative_path="$2"
    title="$3"

    case "$relative_path" in
        AGENTS.md)
            printf '%s' 'Governança global e roteador automático de contexto. Use para identificar o workflow, stack e arquitetura relevantes e carregar somente as instruções necessárias para a tarefa.'
            ;;
        *)
            summary="$(extract_summary "$source_file")"
            [ -n "$summary" ] && printf '%s' "$summary" ||
                printf 'Instruções especializadas de %s. Carregue automaticamente quando a tarefa corresponder a este contexto.' "$title"
            ;;
    esac
}

disable_model_invocation() {
    case "$1" in
        AGENTS.md|.agents/documentation-templates/*|.agents/stack-guides/new-stack-guide-template.md)
            printf '%s' 'true'
            ;;
        *)
            printf '%s' 'false'
            ;;
    esac
}

derive_tags() {
    relative_path="$1"
    printf '%s' "$relative_path" |
        sed -E 's#^\.agents/##; s#\.md$##; s#[/_-]+# #g' |
        tr '[:upper:]' '[:lower:]' |
        awk '{
            for (i = 1; i <= NF; i++) {
                if (length($i) >= 3 && !seen[$i]++) {
                    printf "%s%s", separator, $i
                    separator=","
                }
            }
        }'
}

write_canonical_skill() {
    source_file="$1"
    relative_path="$2"
    output_root="$3"
    id="$4"
    title="$(extract_title "$source_file")"
    summary="$(skill_description "$source_file" "$relative_path" "$title")"
    model_invocation_disabled="$(disable_model_invocation "$relative_path")"
    tags="$(derive_tags "$relative_path")"
    skill_dir="$output_root/$id"
    mkdir -p "$skill_dir"

    {
        printf '%s\n' '---'
        printf 'name: %s\n' "$(printf '%s' "$id" | jq -Rs .)"
        printf 'description: %s\n' "$(printf '%s' "$summary" | jq -Rs .)"
        printf 'disable-model-invocation: %s\n' "$model_invocation_disabled"
        printf 'metadata:\n'
        printf '  source: %s\n' "$(printf '%s' "$relative_path" | jq -Rs .)"
        printf '  tags: %s\n' "$(printf '%s' "$tags" | jq -Rsc 'split(",") | map(select(length > 0))')"
        printf '%s\n\n' '---'
        cat "$source_file"
    } > "$skill_dir/SKILL.md"

    hash="$(sha256sum "$skill_dir/SKILL.md" | awk '{print $1}')"
    jq -nc \
        --arg id "$id" \
        --arg name "$title" \
        --arg description "$summary" \
        --arg tags "$tags" \
        --arg sourcePath "$relative_path" \
        --arg contentPath "$id/SKILL.md" \
        --arg contentSha256 "$hash" \
        '{
            id: $id,
            name: $name,
            description: $description,
            tags: ($tags | split(",") | map(select(length > 0))),
            sourcePath: $sourcePath,
            contentPath: $contentPath,
            contentSha256: $contentSha256
        }'
}

frontmatter_value() {
    field="$1"
    file="$2"
    awk -v field="$field" '
        NR == 1 && $0 ~ /^---[[:space:]]*$/ { frontmatter = 1; next }
        frontmatter && $0 ~ /^---[[:space:]]*$/ { exit }
        frontmatter && index($0, field ":") == 1 {
            value = substr($0, length(field) + 2)
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            gsub(/^["'\'']|["'\'']$/, "", value)
            print value
            exit
        }
    ' "$file"
}

write_existing_skill() {
    source_file="$1"
    relative_path="$2"
    output_root="$3"
    id="$4"
    title="$(frontmatter_value name "$source_file")"
    [ -n "$title" ] || title="$(basename "$(dirname "$source_file")" | tr '-' ' ')"
    summary="$(frontmatter_value description "$source_file")"
    [ -n "$summary" ] || summary="$(extract_summary "$source_file")"
    [ -n "$summary" ] ||
        summary="Skill especializada de $title. Carregue automaticamente quando a tarefa corresponder a este contexto."
    tags="$(derive_tags "$relative_path")"
    skill_dir="$output_root/$id"
    mkdir -p "$skill_dir"
    cp "$source_file" "$skill_dir/SKILL.md"

    hash="$(sha256sum "$skill_dir/SKILL.md" | awk '{print $1}')"
    jq -nc \
        --arg id "$id" \
        --arg name "$title" \
        --arg description "$summary" \
        --arg tags "$tags" \
        --arg sourcePath "$relative_path" \
        --arg contentPath "$id/SKILL.md" \
        --arg contentSha256 "$hash" \
        '{
            id: $id,
            name: $name,
            description: $description,
            tags: ($tags | split(",") | map(select(length > 0))),
            sourcePath: $sourcePath,
            contentPath: $contentPath,
            contentSha256: $contentSha256
        }'
}

build_catalog() {
    source_dir="${SKILLS_SOURCE_DIR:-/state/source}"
    published_root="${SKILLS_OUTPUT_DIR:-/skills}"
    staging_root="$(mktemp -d)"
    staging_skills="$staging_root/skills"
    records="$staging_root/records.jsonl"
    mkdir -p "$staging_skills"
    : > "$records"

    requested_path="${SKILLS_PATH:-${OMNIROUTE_SKILLS_PATH:-}}"
    scan_root="$source_dir"
    if [ -n "$requested_path" ]; then
        case "$requested_path" in
            /*|*..*)
                log "SKILLS_PATH deve ser relativo e não pode conter '..': $requested_path"
                return 1
                ;;
        esac
        if [ -d "$source_dir/$requested_path" ]; then
            scan_root="$source_dir/$requested_path"
        else
            log "SKILLS_PATH não existe no repositório: $requested_path"
            return 1
        fi
    elif [ -d "$source_dir/.github/skills" ]; then
        scan_root="$source_dir/.github/skills"
    elif [ -d "$source_dir/.agents" ]; then
        scan_root="$source_dir/.agents"
    fi

    canonical_list="$staging_root/canonical-files.txt"
    find "$scan_root" -type f -name 'SKILL.md' -print 2>/dev/null |
        LC_ALL=C sort > "$canonical_list"

    if [ -s "$canonical_list" ]; then
        while IFS= read -r source_file; do
            relative_path="${source_file#"$source_dir"/}"
            skill_path="${source_file#"$scan_root"/}"
            skill_name="$(printf '%s' "$skill_path" | sed -E 's#/SKILL\.md$##; s#^SKILL\.md$#skill#')"
            id="pat-$(slugify "$skill_name")"
            write_existing_skill "$source_file" "$relative_path" "$staging_skills" "$id" >> "$records"
        done < "$canonical_list"
    else
        find "$scan_root" -type f -name '*.md' -print 2>/dev/null |
            LC_ALL=C sort |
            while IFS= read -r source_file; do
                relative_path="${source_file#"$source_dir"/}"
                skill_path="${source_file#"$scan_root"/}"
                id="pat-$(slugify "$(printf '%s' "$skill_path" | sed -E 's/\.md$//')")"
                write_canonical_skill "$source_file" "$relative_path" "$staging_skills" "$id" >> "$records"
            done
    fi

    if [ -f "$source_dir/AGENTS.md" ] && [ "$scan_root" != "$source_dir" ]; then
        write_canonical_skill \
            "$source_dir/AGENTS.md" \
            "AGENTS.md" \
            "$staging_skills" \
            "pat-project-governance" >> "$records"
    fi

    revision="local"
    if [ -d "$source_dir/.git" ]; then
        revision="$(git -C "$source_dir" rev-parse HEAD)"
    fi

    jq -sc \
        --arg repository "${SKILLS_REPOSITORY:-${OMNIROUTE_SKILLS_REPO:-local}}" \
        --arg branch "${SKILLS_BRANCH:-${OMNIROUTE_SKILLS_BRANCH:-main}}" \
        --arg revision "$revision" \
        --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            schemaVersion: 1,
            generatedAt: $generatedAt,
            source: {
                repository: $repository,
                branch: $branch,
                revision: $revision
            },
            skills: .
        }' "$records" > "$staging_root/catalog.json"

    mkdir -p "$published_root"
    state_dir="$published_root/.project-agents-templates"
    old_catalog="$state_dir/catalog.json"

    # Publish only the namespace managed by this repository. User-created
    # Caveman skills in the same global directory are never touched.
    jq -r '.skills[].id' "$staging_root/catalog.json" |
        while IFS= read -r id; do
            desired_hash="$(jq -r --arg id "$id" \
                '.skills[] | select(.id == $id) | .contentSha256' \
                "$staging_root/catalog.json")"
            current_hash=""
            if [ -f "$published_root/$id/SKILL.md" ]; then
                current_hash="$(sha256sum "$published_root/$id/SKILL.md" | awk '{print $1}')"
            fi
            if [ "$desired_hash" = "$current_hash" ]; then
                rm -rf "$staging_skills/$id"
                continue
            fi

            rm -rf "$published_root/$id.previous"
            if [ -d "$published_root/$id" ]; then
                mv "$published_root/$id" "$published_root/$id.previous"
            fi
            if ! mv "$staging_skills/$id" "$published_root/$id"; then
                [ ! -d "$published_root/$id.previous" ] ||
                    mv "$published_root/$id.previous" "$published_root/$id"
                return 1
            fi
            rm -rf "$published_root/$id.previous"
        done

    if [ -f "$old_catalog" ]; then
        jq -r '.skills[].id' "$old_catalog" |
            while IFS= read -r old_id; do
                if ! jq -e --arg id "$old_id" '.skills[] | select(.id == $id)' \
                    "$staging_root/catalog.json" >/dev/null; then
                    case "$old_id" in
                        pat-*) rm -rf "$published_root/$old_id" ;;
                    esac
                fi
            done
    fi

    mkdir -p "$state_dir"
    mv "$staging_root/catalog.json" "$old_catalog"
    rm -rf "$staging_root"
    log "Catálogo Caveman gerado com $(jq '.skills | length' "$old_catalog") skills."
}

run_sync() {
    # An error must stop the transaction. This is deliberately an explicit
    # chain because `run_sync` is called below `if ! ...`, where shell `set -e`
    # alone does not reliably abort nested functions.
    sync_source_repository &&
        build_catalog
}
