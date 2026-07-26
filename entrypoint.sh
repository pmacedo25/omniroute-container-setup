#!/bin/bash
set -e

echo "=========================================================="
echo "🚀 Iniciando Container do OmniRoute Gateway (Edição 2026)"
echo "=========================================================="

# 1. Sincronização do Repositório de Skills via Git Clone Direto
SKILLS_REPO=${GITHUB_SKILLS_REPO:-${OMNIROUTE_SKILLS_REPO:-"https://github.com/pmacedo25/project-agents-templates.git"}}
SKILLS_DIR="/root/.omniroute/skills"

echo "📦 Configurando repositório vivo de Skills em: $SKILLS_REPO"
mkdir -p "$SKILLS_DIR"

if [ -d "$SKILLS_DIR/.git" ]; then
    echo "🔄 Repositório de Skills detectado em $SKILLS_DIR. Executando git pull..."
    git -C "$SKILLS_DIR" pull origin ${GITHUB_BRANCH:-main} --quiet || echo "⚠️ Aviso: Falha no git pull (offline?). Mantendo cache local."
else
    echo "📥 Clonando repositório de Skills diretamente para $SKILLS_DIR..."
    rm -rf "$SKILLS_DIR" && mkdir -p "$SKILLS_DIR"
    git clone --branch ${GITHUB_BRANCH:-main} "$SKILLS_REPO" "$SKILLS_DIR" || echo "⚠️ Aviso: Falha ao clonar repo. Verifique a URL."
fi

# Verificação do índice AGENTS.md e sub-skills
if [ -f "$SKILLS_DIR/AGENTS.md" ]; then
    echo "🎯 Índice Maestro 'AGENTS.md' ativo no diretório de skills!"
fi

if [ -d "$SKILLS_DIR/.agents" ]; then
    SUB_COUNT=$(find "$SKILLS_DIR/.agents" -type f \( -name "*.md" -o -name "SKILL.md" \) | wc -l)
    echo "✅ Pasta '.agents/' ativa com $SUB_COUNT sub-skills detectadas."
fi

# 2. Agendador Automático em Background (Git Pull a cada 6 horas dentro do Container)
(
    while true; do
        sleep 21600 # 6 horas em segundos
        if [ -d "$SKILLS_DIR/.git" ]; then
            echo "[AutoUpdate] ⏰ Executando atualização automática (git pull) em $SKILLS_DIR..."
            git -C "$SKILLS_DIR" pull origin ${GITHUB_BRANCH:-main} --quiet || true
        fi
    done
) &
echo "⏰ Sincronizador contínuo em segundo plano ativo (Atualização a cada 6 horas)."

# 3. Verificando ativação de otimizadores de token
if [ "$ENABLE_RTK" = "true" ]; then
    echo "🛡️ RTK Token Saver ATIVADO: Saídas verbosas de terminal serão comprimidas."
fi

if [ "$CAVEMAN_MODE" = "true" ]; then
    echo "🪨 Caveman Mode ATIVADO: Modelos responderão de forma ultraconcisa."
fi

# 4. Sincronizador de Combos Padrão (Caso APPKEY seja fornecida via .env no Container)
if [ -n "$OMNIROUTE_API_KEY" ] && [ -f "/app/combos-config.json" ]; then
    (
        sleep 6
        echo "🎯 [Container] APPKEY detectada. Cadastrando Default Combos no Gateway via API REST..."
        curl -s -X POST http://127.0.0.1:${PORT:-20128}/api/settings/combo-defaults \
             -H "Authorization: Bearer $OMNIROUTE_API_KEY" \
             -H "Content-Type: application/json" \
             -d '{"defaultCombo":"combo-coding","autoMapping":true}' >/dev/null 2>&1 || true
    ) &
fi

echo "=========================================================="
echo "🌐 Subindo servidor na porta ${PORT:-20128} (http://0.0.0.0:${PORT:-20128})"
echo "=========================================================="

# 5. Inicia o servidor Gateway (Sem --daemon para manter o container em foreground limpo)
if command -v omniroute >/dev/null 2>&1; then
    exec omniroute serve --port ${PORT:-20128} --host 0.0.0.0 --no-open
elif command -v 9router >/dev/null 2>&1; then
    exec 9router serve --port ${PORT:-20128} --host 0.0.0.0 --no-open
else
    echo "ℹ️ Binário global não encontrado no PATH, executando via npx..."
    exec npx -y omniroute@latest serve --port ${PORT:-20128} --host 0.0.0.0 --no-open
fi
