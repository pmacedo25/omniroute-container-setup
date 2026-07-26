# OmniRoute Setup para Windows

Instalador idempotente do OmniRoute para dois cenários:

- `container`: OmniRoute e OpenHands em contêineres, acessíveis no host em
  `http://localhost:20128` e `http://localhost:3000`.
- `local`: OmniRoute como tarefa agendada em background e OpenCode configurado
  exclusivamente para o gateway local.

Nos dois modos, o setup também instala o **OpenRouterAI**, uma IDE desktop
experimental baseada no Eclipse Theia. Ela trabalha diretamente na pasta local
de projetos e expõe somente os três combos do OmniRoute.

O instalador preserva o banco, a APPKEY e as skills em reexecuções. Nenhum
processo Node genérico ou banco existente é apagado.

## Execução

Modo assistido:

```powershell
.\setup-interativo.ps1
```

Nesse modo o instalador pergunta a raiz local dos projetos e a URL do
repositório GitHub de skills. Pressionar Enter usa (e cria quando necessário)
`%USERPROFILE%\workspace`. Os projetos ficam diretamente dentro dessa pasta,
sem uma subpasta `projects`. Conversas e configurações do OpenHands ficam
separadas em `%USERPROFILE%\.openhands`.

Modo automático em contêiner:

```powershell
.\setup-interativo.ps1 -Mode container -NonInteractive -SkipProviderLogin
```

Modo local:

```powershell
.\setup-interativo.ps1 -Mode local
```

Parâmetros úteis:

- `-SkillsRepository <URL>` e `-SkillsBranch <nome>`
- `-ProjectsPath "D:\projetos"` para escolher a raiz dos projetos
- `-Port 20128`
- `-SkipDesktopApp` para instalar somente o gateway
- `-SkipOpenRouterAI` para manter os clientes antigos sem instalar a nova IDE
- `-OpenRouterAIVersion <semver|latest>`
- `-OpenRouterAIArtifactPath <zip>` para validar um build local sem GitHub
- `-NonInteractive` para CI/provisionamento

A autenticação OAuth dos provedores continua dependendo do consentimento no
navegador. Todo o restante, incluindo APPKEY, três combos, persistência,
background e configuração do cliente, é automático.

No modo container, o setup também instala o GitHub CLI quando necessário e
verifica `gh auth status`. Se ainda não houver uma sessão, o modo interativo
executa o login web do GitHub e aguarda sua conclusão. O token resultante é
repassado como `GH_TOKEN` somente aos sandboxes do OpenHands, sem montar a
pasta `.config` e interferir nas ferramentas Browser Use. Em
`-NonInteractive`, o instalador informa o comando de login e pode ser
reexecutado depois sem perder o restante da configuração.

## Arquitetura

No modo container:

- `diegosouzapw/omniroute:3.8.48`: imagem oficial, sem toolchains de build.
- `omniroute-skills-sync:1`: Alpine + Git, atualiza as skills a cada hora.
- `docker.openhands.dev/openhands/openhands:1.7`: perfil `openhands`.
- volumes nomeados preservam banco e skills do OmniRoute; o estado do OpenHands
  fica visível no host em `%USERPROFILE%\.openhands`.
- as portas `20128` e `3000` também ficam disponíveis no gateway interno do
  Podman/Docker, pois os sandboxes do OpenHands precisam acessar o OmniRoute,
  o endpoint MCP e os webhooks. A APPKEY continua obrigatória no OmniRoute.
- o atalho `OpenHands Desktop` usa o ícone oficial, inicia o contêiner quando
  necessário e abre `http://localhost:3000` como Web App, sem abas ou barra de
  endereço.
- no modo interativo, o Edge também abre a confirmação para instalar o
  OpenHands como PWA, dando ao aplicativo identidade e ícone próprios no
  Windows.
- no Podman para Windows, somente o OpenHands é iniciado por `podman run`, pois
  o `podman-compose` converte incorretamente o socket Linux necessário aos
  sandboxes. Docker continua usando o perfil Compose.
- a imagem `agent-server` é pré-baixada antes do primeiro boot, evitando
  timeouts e respostas 500 enquanto o OpenHands prepara seus sandboxes.
- as configurações são persistidas pela API Web V1 do OpenHands
  (`/api/v1/settings`) com OmniRoute, APPKEY e `combo-coding` como padrão.
- um layer mínimo sobre a imagem oficial restringe o catálogo visual ao provedor
  `OmniRoute` e aos modelos `combo-coding`, `combo-refining` e `combo-testing`.
- os clientes trabalham em modo provedor único: OpenCode usa a allowlist
  `enabled_providers: ["omniroute"]`; o catálogo do OpenHands também contém
  somente o OmniRoute.
- reexecuções mantêm apenas uma AppKey chamada `omniroute-setup`; duplicatas
  antigas criadas pelo próprio instalador são removidas sem afetar chaves de
  terceiros.

No modo local:

- instala Node LTS e Git via winget somente quando faltarem;
- fixa OmniRoute `3.8.48` e OpenCode `1.18.5`;
- executa o gateway pela tarefa agendada `OmniRoute Gateway`;
- grava `~/.config/opencode/opencode.json` com os outros provedores desativados.

Python e Microsoft C++ Build Tools são instalados sob demanda se o npm precisar
compilar um módulo nativo. Quando os binários pré-compilados funcionam, esse
toolchain pesado não é instalado. Nenhuma ferramenta de build entra nas imagens
de runtime.

## OpenRouterAI

O OpenRouterAI é instalado nos modos container e local em escopo de usuário,
sem UAC. O setup baixa o release privado com GitHub CLI, valida o SHA-256 e
extrai versões lado a lado em `%LOCALAPPDATA%\Programs\OpenRouterAI`.

Projetos permanecem em `%USERPROFILE%\workspace` (ou `-ProjectsPath`) e a
configuração fica em `%USERPROFILE%\.openrouterai`. A AppKey não é duplicada no
JSON: o processo lê `OMNIROUTE_API_KEY` do ambiente do usuário. O setup é a
única autoridade de atualização e ativa versões por `current.json`.

## Operação

Depois de abrir um novo PowerShell:

```powershell
omni.ps1 status
omni.ps1 dashboard
omni.ps1 logs
omni.ps1 restart
omni.ps1 pull
omni.ps1 doctor
```

## Testes

Os testes são locais e não instalam pacotes nem iniciam contêineres:

```powershell
.\tests\run-tests.ps1
```

Validação opcional do Compose (requer Docker ou Podman):

```powershell
docker compose config
# ou
podman compose config
```
