FROM node:22-slim

# Evita avisos de frontend debconf e configura o npm para silencio de warnings
ENV DEBIAN_FRONTEND=noninteractive
ENV NPM_CONFIG_LOGLEVEL=error

# Instala Git (para clonar skills), curl, ca-certificates e build-essential (python3, make, g++) para compilação nativa C++
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Define diretório de trabalho
WORKDIR /app

# Instala o OmniRoute globalmente com resolução limpa de peer-deps sem warnings
RUN npm install -g omniroute@latest --legacy-peer-deps --no-fund --no-audit

# Cria diretórios para persistência e skills
RUN mkdir -p /root/.omniroute/skills /root/.omniroute/data /app/skills-repo

# Copia o script de inicialização e o arquivo de configuração
COPY entrypoint.sh /app/entrypoint.sh
COPY combos-config.json /app/combos-config.json

RUN chmod +x /app/entrypoint.sh

EXPOSE 20128

ENTRYPOINT ["/app/entrypoint.sh"]
