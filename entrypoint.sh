#!/bin/bash
set -e

echo "=========================================================="
echo "[+] Iniciando Container do OmniRoute Gateway (Edição 2026)"
echo "=========================================================="

# 1. Garantia de STORAGE_ENCRYPTION_KEY e Persistência do Banco SQLite
mkdir -p "/root/.omniroute"
ENV_FILE="/root/.omniroute/.env"

if [ ! -f "$ENV_FILE" ] || ! grep -q "STORAGE_ENCRYPTION_KEY=" "$ENV_FILE"; then
    echo "[>] [Container] Gerando STORAGE_ENCRYPTION_KEY para proteger o banco SQLite no volume..."
    HEX_KEY=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "STORAGE_ENCRYPTION_KEY=$HEX_KEY" >> "$ENV_FILE"
    echo "[OK] [Container] Chave de criptografia registrada em $ENV_FILE!"
fi

# Exporta variáveis do arquivo .env do contêiner
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# Link simbólico para garantir que o SQLite em /app aponte para o volume persistido em /root/.omniroute
if [ -f "/root/.omniroute/storage.sqlite" ]; then
    ln -sf "/root/.omniroute/storage.sqlite" "/app/storage.sqlite" 2>/dev/null || true
fi
echo "[OK] [Container] Volume persistente montado em /root/.omniroute."

# 2. Sincronização do Repositório de Skills via Git Clone Direto
SKILLS_REPO=${GITHUB_SKILLS_REPO:-${OMNIROUTE_SKILLS_REPO:-"https://github.com/pmacedo25/project-agents-templates.git"}}
SKILLS_DIR="/root/.omniroute/skills"

echo "[>] Configurando repositório vivo de Skills em: $SKILLS_REPO"
mkdir -p "$SKILLS_DIR"

if [ -d "$SKILLS_DIR/.git" ]; then
    echo "[>] Repositório de Skills detectado em $SKILLS_DIR. Executando git pull..."
    git -C "$SKILLS_DIR" pull origin ${GITHUB_BRANCH:-main} --quiet || echo "[WARN] Aviso: Falha no git pull (offline?). Mantendo cache local."
else
    echo "[>] Clonando repositório de Skills diretamente para $SKILLS_DIR..."
    find "$SKILLS_DIR" -mindepth 1 -delete 2>/dev/null || true
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch ${GITHUB_BRANCH:-main} "$SKILLS_REPO" "$SKILLS_DIR" 2>/dev/null || echo "[WARN] Aviso: Falha ao clonar repo. Mantendo diretório ativo."
fi

# Verificação do índice AGENTS.md e sub-skills
if [ -f "$SKILLS_DIR/AGENTS.md" ]; then
    echo "[INFO] Índice Maestro 'AGENTS.md' ativo no diretório de skills!"
fi

if [ -d "$SKILLS_DIR/.agents" ]; then
    SUB_COUNT=$(find "$SKILLS_DIR/.agents" -type f \( -name "*.md" -o -name "SKILL.md" \) | wc -l)
    echo "[OK] Pasta '.agents/' ativa com $SUB_COUNT sub-skills detectadas."
fi

# 3. Agendador Automático em Background (Git Pull de HORA EM HORA dentro do Container)
(
    while true; do
        sleep 3600 # 1 hora em segundos (3600s)
        if [ -d "$SKILLS_DIR/.git" ]; then
            echo "[Auto-Sync] [>] Executando atualização horária automática (git pull) em $SKILLS_DIR..."
            git -C "$SKILLS_DIR" pull origin ${GITHUB_BRANCH:-main} --quiet || true
        fi
    done
) &
echo "[OK] Sincronizador contínuo de Skills em segundo plano ativo (Atualização de hora em hora)."

# 4. Verificando ativação de otimizadores de token
if [ "$ENABLE_RTK" = "true" ]; then
    echo "[INFO] RTK Token Saver ATIVADO: Saídas verbosas de terminal serão comprimidas."
fi

if [ "$CAVEMAN_MODE" = "true" ]; then
    echo "[INFO] Caveman Mode ATIVADO: Modelos responderão de forma ultraconcisa."
fi

# 5. Sincronizador de Combos Padrão via API REST no Container
if [ -n "$OMNIROUTE_API_KEY" ] && [ -f "/app/combos-config.json" ]; then
    (
        sleep 6
        echo "[>] [Container] APPKEY detectada. Cadastrando Default Combos no Gateway via API REST..."
        curl -s -X POST http://127.0.0.1:${PORT:-20128}/api/settings/combo-defaults \
             -H "Authorization: Bearer $OMNIROUTE_API_KEY" \
             -H "Content-Type: application/json" \
             -d '{"defaultCombo":"combo-coding","autoMapping":true}' >/dev/null 2>&1 || true
    ) &
fi

# 6. Inicia o servidor Gateway em loop de resiliência permanente (Garante que o contêiner NUNCA cai)
echo "=========================================================="
echo "[+] Servidor OmniRoute Gateway ativo em modo permanente."
echo "=========================================================="

while true; do
    echo "[OmniRoute] Subindo servidor na porta ${PORT:-20128} (http://0.0.0.0:${PORT:-20128})..."
    if command -v omniroute >/dev/null 2>&1; then
        omniroute serve --port ${PORT:-20128} --host 0.0.0.0 --no-open || true
    else
        echo "[INFO] Binário global não encontrado no PATH, executando via npx..."
        npx -y omniroute@latest serve --port ${PORT:-20128} --host 0.0.0.0 --no-open || true
    fi
    echo "[WARN] Processo do Gateway suspenso. Reabrindo em 2 segundos..."
    sleep 2
done
