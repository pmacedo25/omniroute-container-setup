# OpenRouterAI — plano de implementação multiagente

## 1. Objetivo e limites

Construir um protótipo descartável e validável de uma IDE desktop Windows baseada
no Eclipse Theia. O objetivo é testar a integração OmniRoute + IDE customizada,
os três combos e a economia de tokens. Não é objetivo inicial criar uma
distribuição pública, serviço SaaS ou produto que exija manutenção contínua.

O OpenRouterAI:

- roda como aplicativo Electron no Windows, sem contêiner;
- abre diretamente `%USERPROFILE%\workspace`;
- usa Git, `gh`, Node, Python, C++ e demais ferramentas instaladas no host;
- fala apenas com o OmniRoute local pela API OpenAI-compatible;
- exibe somente `combo-testing`, `combo-coding` e `combo-refining`;
- permite selecionar combo e esforço de raciocínio no chat;
- é instalado e configurado pelo instalador atual do OmniRoute sem elevação;
- mantém projetos e configuração fora da pasta da aplicação;
- não incorpora nem inicia outra cópia do OmniRoute.

## 2. Decisão arquitetural

O chamado “plugin OmniRoute” é uma extensão Theia embutida no build do
OpenRouterAI. Ela não contém o gateway. Suas responsabilidades são:

1. descobrir `http://localhost:20128`;
2. ler a AppKey do ambiente/configuração gerenciada pelo instalador;
3. registrar um único provider OpenAI-compatible chamado `OmniRoute`;
4. fornecer um catálogo fechado com os três combos;
5. mapear agentes para combos e defaults de reasoning;
6. testar `/api/monitoring/health` e `/v1/models`;
7. mostrar erros acionáveis sem revelar a AppKey;
8. coletar métricas locais de benchmark sem enviar telemetria externa.

```text
OpenRouterAI (Electron/Theia)
  ├─ workspace local e terminal Windows
  ├─ extensão openrouterai-omniroute
  ├─ agentes Explorer/Coder/Tester/Reviewer/Architect
  └─ HTTP OpenAI-compatible → OmniRoute localhost:20128
                                  └─ providers e combos
```

## 3. Repositórios

### Repositório novo: `OpenRouterAI`

Contém a aplicação Theia, extensões, identidade visual, testes e workflow que
gera o ZIP portátil e o instalador por usuário.

Estrutura desejada:

```text
OpenRouterAI/
  applications/electron/
  extensions/openrouterai-product/
  extensions/openrouterai-omniroute/
  extensions/openrouterai-benchmark/
  resources/icons/
  scripts/
  tests/unit/
  tests/e2e/
  package.json
  electron-builder.yml
  README.md
```

### Repositório existente: `omniroute-container-setup`

Continua dono do provisionamento. Receberá:

- versão e URL do artefato OpenRouterAI;
- download com checksum;
- instalação em escopo de usuário;
- configuração inicial;
- atalhos;
- atualização/reinstalação idempotente;
- diagnóstico e remoção opcional.

O repositório remoto `OpenRouterAI` precisa ser identificado por URL antes do
primeiro push. Não criar automaticamente outro repositório com o mesmo nome.

## 4. Contratos entre os repositórios

### Arquivo gerenciado pelo instalador

`%USERPROFILE%\.openrouterai\config.json`

```json
{
  "schemaVersion": 1,
  "omnirouteBaseUrl": "http://localhost:20128/v1",
  "omnirouteHealthUrl": "http://localhost:20128/api/monitoring/health",
  "apiKeyEnvironmentVariable": "OMNIROUTE_API_KEY",
  "workspace": "%USERPROFILE%\\workspace",
  "defaultCombo": "combo-coding",
  "allowedCombos": [
    "combo-testing",
    "combo-coding",
    "combo-refining"
  ],
  "telemetry": false
}
```

A AppKey não será duplicada nesse JSON. A IDE a recebe pela variável de usuário
`OMNIROUTE_API_KEY`, já gerenciada pelo instalador.

### Contrato de release

Cada release privada do OpenRouterAI publica:

- `OpenRouterAI-win-x64-<version>.zip`, obrigatório para instalação sem elevação;
- `OpenRouterAI-Setup-<version>.exe`, útil para instalação manual;
- `SHA256SUMS`;
- `release-manifest.json`, contendo versão, URL, SHA-256 e versão mínima do setup.

Para o protótipo, o script usa preferencialmente o ZIP portátil e extrai em
`%LOCALAPPDATA%\Programs\OpenRouterAI\<version>`. Um arquivo `current.json`
aponta a versão ativa. Isso evita UAC e facilita rollback.

## 5. Plano por agentes

Cada agente trabalha em branch própria, possui caminhos exclusivos e entrega
commits pequenos. Nenhum agente altera o contrato de configuração sem avisar o
agente integrador.

### Agente 0 — bootstrap e decisões

Dependências: URL do repositório privado.

Entregas:

- clonar o template `eclipse-theia/theia-ide` em versão fixa;
- renomear pacotes e produto para OpenRouterAI;
- fixar Node, Yarn e Theia;
- habilitar build Electron x64 com esbuild;
- registrar comandos de build reproduzíveis;
- gerar SBOM e inventário de licenças;
- criar `ARCHITECTURE.md` e ADRs curtos.

Aceite:

- `yarn install --immutable` funciona;
- build Electron abre uma janela;
- nenhuma dependência usa faixa `latest`;
- CI recompila do zero.

### Agente 1 — branding e empacotamento

Caminhos exclusivos: `resources/`, extensão de produto e `electron-builder.yml`.

Entregas:

- aplicar nome OpenRouterAI, ícones, splash e About;
- gerar PNGs 16/24/32/48/64/128/256/512 e ICO multi-resolução;
- configurar AppUserModelID `OpenRouterAI.Desktop`;
- empacotar ZIP portátil e EXE NSIS por usuário;
- impedir instalação em `Program Files`;
- desabilitar telemetria upstream por padrão.

Aceite:

- transparência preservada em todos os PNGs e no ICO;
- ícone correto no executável, atalho e barra de tarefas;
- app inicia sem privilégios administrativos;
- assets não contêm fundo cromático.

### Agente 2 — provider OmniRoute

Caminho exclusivo: `extensions/openrouterai-omniroute/`.

Entregas:

- implementar serviço de configuração e health check;
- registrar somente o provider OmniRoute;
- catálogo fechado dos três combos;
- seletor no chat e comando “OpenRouterAI: Select Combo”;
- reasoning Off/Low/Medium/High, com defaults por agente;
- mascarar segredos em logs e erros;
- mensagens de reparo que apontem para `omni doctor`.

Aceite:

- nenhum provider externo aparece na UI;
- cada combo gera request com o `model` correto;
- mudança de combo vale imediatamente para chat novo;
- timeout e indisponibilidade produzem mensagem útil;
- AppKey nunca aparece em snapshot, log ou telemetria.

### Agente 3 — agentes e economia de contexto

Caminhos exclusivos: agentes, prompts e configuração de AI.

Entregas:

- Explorer → `combo-testing`, reasoning Low;
- Tester → `combo-testing`, reasoning Low;
- Coder → `combo-coding`, reasoning Medium;
- Reviewer → `combo-refining`, reasoning Medium;
- Architect → `combo-refining`, reasoning High;
- prompts curtos, reutilizáveis e versionados;
- seleção explícita de arquivos, sem anexar workspace inteiro;
- remover reasoning histórico do contexto quando suportado;
- comandos para resumir e iniciar chat limpo.

Aceite:

- prompts têm testes de snapshot;
- orçamento de system prompt definido e medido;
- ferramentas mínimas por agente;
- um agente barato não escala silenciosamente para outro combo;
- o usuário sempre enxerga combo e reasoning ativos.

### Agente 4 — workspace e ferramentas do host

Caminhos exclusivos: integração de workspace, terminal e diagnóstico.

Entregas:

- abrir `%USERPROFILE%\workspace` no primeiro uso;
- respeitar workspace escolhido no instalador;
- validar Git, `gh`, Node, Python e compiladores;
- reutilizar PATH e ambiente do usuário;
- comandos de diagnóstico não destrutivos;
- Workspace Trust habilitado por confirmação, não ignorado.

Aceite:

- arquivos criados aparecem diretamente no Windows;
- `gh auth status`, `node --version` e `python --version` rodam no terminal;
- não existe caminho `/workspace` ou `/projects` de contêiner;
- IDE funciona mesmo sem uma ferramenta opcional.

### Agente 5 — benchmark

Caminho exclusivo: `extensions/openrouterai-benchmark/` e `benchmarks/`.

Entregas:

- importar a matriz do repositório de setup;
- registrar combo, modelo efetivo, failover, latência e tokens;
- exportar JSON/CSV local;
- IDs de execução reprodutíveis;
- painel simples por tarefa e custo por sucesso;
- nunca armazenar prompts/arquivos por padrão.

Aceite:

- métricas distinguem provider, família, modelo e combo;
- chamadas com falha também entram no custo;
- cache e compressão aparecem separadamente;
- exportação não contém AppKey nem conteúdo do projeto.

### Agente 6 — instalador OmniRoute

Caminho exclusivo: repositório `omniroute-container-setup`.

Entregas:

- `Install-OpenRouterAI`, `Update-OpenRouterAI` e `Test-OpenRouterAI`;
- baixar release privada via `gh release download` ou URL autenticada;
- aceitar `-OpenRouterAIArtifactPath` para testes locais sem GitHub;
- validar SHA-256 antes de extrair;
- instalar em `%LOCALAPPDATA%` sem UAC;
- escrita atômica de `current.json`;
- criar atalhos `.lnk` com ícone próprio;
- preservar versão anterior para rollback;
- configurar workspace, endpoint e variável AppKey;
- incluir OpenRouterAI no `omni doctor`.

Aceite:

- primeira instalação e reexecução produzem o mesmo estado;
- download interrompido não quebra a versão ativa;
- checksum inválido bloqueia instalação;
- atalhos continuam funcionando após atualização;
- nenhuma chave é passada na linha de comando;
- desinstalação do app não apaga projetos nem OmniRoute.

### Agente 7 — testes e segurança

Atua após contratos estabilizados, sem reescrever implementações.

Entregas:

- unitários para config, catálogo, masking e seleção;
- E2E Electron no Windows;
- servidor OmniRoute fake para cenários previsíveis;
- smoke test opcional contra OmniRoute real;
- testes do instalador em home temporária;
- análise de dependências e segredos.

Aceite:

- provider único e três combos verificados por UI e rede;
- caminhos com espaços e Unicode testados;
- AppKey ausente, inválida e rotacionada testadas;
- rollback testado;
- suite não depende de conta paga para o caminho padrão.

### Agente 8 — integração e release

Responsável por resolver contratos, não por absorver todo o desenvolvimento.

Entregas:

- integrar branches na ordem definida;
- executar testes, empacotar e assinar manifest;
- publicar prerelease privada;
- executar instalação limpa e upgrade;
- gerar relatório de benchmark inicial;
- registrar limitações conhecidas.

Aceite:

- commit e artefatos correspondem;
- hashes publicados são reproduzíveis;
- instalação ponta a ponta funciona em usuário sem admin;
- OpenRouterAI abre o workspace e completa uma tarefa simples.

## 6. Ordem e paralelismo

```text
Fase A: Agente 0
          ├─ Agente 1 (branding)
          ├─ Agente 2 (provider)
          ├─ Agente 4 (host/workspace)
          └─ Agente 6 (contrato preliminar do instalador)

Fase B: Agente 2 concluído
          ├─ Agente 3 (agentes/contexto)
          └─ Agente 5 (benchmark)

Fase C: builds integrados
          ├─ Agente 7 (testes)
          └─ Agente 6 (instalador real)

Fase D: Agente 8 (release e validação)
```

O máximo recomendado é quatro agentes simultâneos. Branding, provider, host e
instalador preliminar podem avançar em paralelo após o bootstrap.

## 7. Uso opcional do Antigravity CLI

Pode ser usado para:

- comparar implementação de providers;
- gerar casos adicionais de teste;
- revisar prompts de agentes;
- investigar incompatibilidades de tool calling.

Não deve:

- alterar contratos compartilhados diretamente;
- receber AppKeys em prompts ou logs;
- publicar releases;
- decidir sozinho mudanças de arquitetura;
- editar os mesmos caminhos de outro agente.

Todo resultado do CLI precisa virar diff revisável e passar pelos mesmos testes.

## 8. Estratégia de atualização sem manutenção pesada

- Fixar uma versão Theia durante todo o experimento.
- Não criar atualização automática do framework no MVP.
- Atualização do OpenRouterAI ocorre apenas quando publicarmos nova release.
- `electron-updater` fica fora do primeiro protótipo; o script OmniRoute controla
  download, ativação e rollback.
- Manter no máximo duas versões locais.
- Só atualizar Theia se houver bug bloqueante ou vulnerabilidade relevante.
- Encerrar o experimento com decisão explícita: arquivar, continuar ou substituir.

O repositório privado exige `gh auth status` válido para baixar releases; tokens
jamais serão embutidos. Sem assinatura de código, Windows SmartScreen pode
alertar no protótipo. O ZIP reduz a cerimônia, mas não cria reputação para o
executável. Atualizações são lado a lado porque arquivos do Electron podem estar
bloqueados enquanto a IDE estiver aberta.

## 8.1. Riscos arquiteturais

- A API Theia AI ainda evolui: isolá-la atrás do adaptador próprio e fixar versão.
- Providers do template precisam ser removidos e cobertos por teste negativo.
- Tool calling varia entre famílias: anunciar capabilities pelo menor denominador
  comum e testar streaming, cancelamento, 401, 429 e 500.
- Não guardar AppKey em preferências Theia, que podem ser texto claro.
- Bundled extensions aumentam tamanho e superfície: manter conjunto mínimo.
- Nunca construir Theia na máquina final; apenas baixar artefato pronto.
- Preservar `appId` e IDs de preferências entre releases.
- Desabilitar o `electron-updater` do template para não competir com o setup.
- `OpenRouterAI` pode ser confundido com o serviço OpenRouter; o README deve
  declarar que não há afiliação e o nome deve ser revisto antes de distribuição.

Essa abordagem reduz o custo de manter um fork e atende ao caráter experimental.

## 9. Marcos

### M0 — prova técnica (2–4 dias)

Theia abre, usa `combo-coding`, edita arquivo e executa terminal local.

### M1 — MVP instalável (5–10 dias úteis)

Provider único, três combos, agentes básicos, ícones, ZIP privado e instalação
idempotente pelo setup.

### M2 — validação (3–5 dias úteis)

Benchmark, E2E, rollback e relatório comparando OpenRouterAI com OpenHands.

## 10. Critério de encerramento do experimento

Prosseguir somente se:

- tool calling concluir pelo menos 8/10 casos;
- custo por tarefa for mensurável e inferior ou justificável;
- troca de combo for clara;
- instalação e reexecução forem confiáveis;
- workspace e ferramentas locais funcionarem sem contorno manual.

Caso contrário, arquivar o repositório e preservar apenas os resultados.
