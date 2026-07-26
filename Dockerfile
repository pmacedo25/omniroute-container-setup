FROM node:20-slim

# Instala Git (para clonar as skills do GitHub), curl e utilitários básicos
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Define diretório de trabalho
WORKDIR /app

# Instala o OmniRoute globalmente
RUN npm install -g omniroute@latest

# Cria diretórios para persistência e skills
RUN mkdir -p /root/.omniroute/skills /root/.omniroute/data /app/skills-repo

# Copia o script de inicialização e o arquivo de configuração
COPY entrypoint.sh /app/entrypoint.sh
COPY combos-config.json /app/combos-config.json

RUN chmod +x /app/entrypoint.sh

EXPOSE 20128

ENTRYPOINT ["/app/entrypoint.sh"]
