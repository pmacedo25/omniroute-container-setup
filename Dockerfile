FROM node:22-slim

# Evita avisos de debconf e silencia logs excessivos de npm
ENV DEBIAN_FRONTEND=noninteractive
ENV NPM_CONFIG_LOGLEVEL=warn

# Instala apenas Git (para clonar skills), curl e ca-certificates (mantendo a imagem super leve)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Define diretório de trabalho
WORKDIR /app

# Instala o OmniRoute globalmente com limpeza imediata de cache
RUN npm install -g omniroute@latest --legacy-peer-deps --no-fund --no-audit && npm cache clean --force

# Cria diretórios para persistência e skills
RUN mkdir -p /root/.omniroute/skills /root/.omniroute/data /app/skills-repo

# Copia o script de inicialização e o arquivo de configuração
COPY entrypoint.sh /app/entrypoint.sh
COPY combos-config.json /app/combos-config.json

RUN chmod +x /app/entrypoint.sh

EXPOSE 20128

ENTRYPOINT ["/app/entrypoint.sh"]
