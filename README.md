# OmniRoute Setup para Windows

Instalador idempotente do OmniRoute para dois cenários:

- `container`: OmniRoute em contêiner, acessível no host em
  `http://localhost:20128`.
- `local`: OmniRoute como tarefa agendada em background.

Nos dois modos, o setup também instala o **Achilles**, uma IDE desktop
experimental baseada no Eclipse Theia. Ela trabalha diretamente na pasta local
de projetos e consulta dinamicamente os combos e modelos do OmniRoute.

O instalador preserva o banco, a APPKEY e as skills em reexecuções. Nenhum
processo Node genérico ou banco existente é apagado.

## Execução

Instalação direta pelo GitHub, sem clonar o repositório e sem precisar de Git:

```powershell
irm https://raw.githubusercontent.com/pmacedo25/omniroute-container-setup/master/install.ps1 | iex
```

O bootstrap consulta o release público mais recente, baixa o código-fonte
diretamente do GitHub e mantém a cópia operacional em
`%USERPROFILE%\.omniroute\setup`. O `.env` existente é preservado nas
atualizações, portanto o mesmo comando pode ser reexecutado com segurança.

Modo assistido:

```powershell
.\setup-interativo.ps1
```

Nesse modo o instalador exige a URL do repositório GitHub de skills, sem
preencher um repositório padrão. Nenhuma pasta de projetos é criada: o Achilles
abre como uma IDE comum e trabalha com as pastas ou workspaces escolhidos em
cada janela.

Modo automático em contêiner:

```powershell
.\setup-interativo.ps1 -Mode container -NonInteractive `
  -SkillsRepository "https://github.com/sua-organizacao/seu-repositorio-skills.git" `
  -SkipProviderLogin
```

Modo local:

```powershell
.\setup-interativo.ps1 -Mode local
```

Parâmetros úteis:

- `-SkillsRepository <URL>` e `-SkillsBranch <nome>`
- `-Port 20128`
- `-SkipAchilles` para instalar somente o gateway
- `-AchillesVersion <semver|latest>`
- `-AchillesArtifactPath <zip>` para validar um build local sem GitHub
- `-NonInteractive` para CI/provisionamento; exige `-SkillsRepository`

A autenticação OAuth dos provedores continua dependendo do consentimento no
navegador. Todo o restante, incluindo APPKEY, três combos, persistência,
background e configuração do Achilles, é automático.

No modo container, o setup também instala o GitHub CLI quando necessário e
verifica `gh auth status`, permitindo que o sincronizador acesse um repositório
privado de skills. Em `-NonInteractive`, o instalador informa o comando de login
e pode ser reexecutado depois sem perder o restante da configuração.

## Arquitetura

No modo container:

- `diegosouzapw/omniroute:3.8.48`: imagem oficial, sem toolchains de build.
- `omniroute-skills-sync:1`: Alpine + Git, atualiza as skills a cada hora.
- volumes nomeados preservam banco e skills do OmniRoute.
- a porta `20128` fica disponível no host. A APPKEY continua obrigatória.
- reexecuções mantêm apenas uma AppKey chamada `omniroute-setup`; duplicatas
  antigas criadas pelo próprio instalador são removidas sem afetar chaves de
  terceiros.

No modo local:

- instala Node LTS e Git via winget somente quando faltarem;
- fixa OmniRoute `3.8.48`;
- executa o gateway pela tarefa agendada `OmniRoute Gateway`.

Python e Microsoft C++ Build Tools são instalados sob demanda se o npm precisar
compilar um módulo nativo. Quando os binários pré-compilados funcionam, esse
toolchain pesado não é instalado. Nenhuma ferramenta de build entra nas imagens
de runtime.

## Achilles

O Achilles é instalado nos modos container e local em escopo de usuário,
sem UAC. O setup baixa o release público do repositório exclusivo de binários, valida o SHA-256 e
extrai versões lado a lado em `%LOCALAPPDATA%\Programs\Achilles`.
Também cria o comando estável `achilles` em `%USERPROFILE%\.omniroute\bin`,
inclui esse diretório no PATH do usuário e registra atalhos na Área de Trabalho
e no Menu Iniciar. Assim, um novo terminal pode executar `achilles` e a pesquisa
do Windows encontra o aplicativo sem MSI ou permissões administrativas.

Projetos permanecem onde o usuário escolher, e a configuração do aplicativo
fica em `%USERPROFILE%\.achilles`. A AppKey não é duplicada no
JSON: o processo lê `OMNIROUTE_API_KEY` do ambiente do usuário. O setup é a
única autoridade de atualização e ativa versões por `current.json`.

Ao detectar OpenRouterAI, o setup copia conversas, preferências e demais
configurações persistentes de `%USERPROFILE%\.openrouterai` para `%USERPROFILE%\.achilles`.
Caches, layouts temporários e launchers com a marca antiga são regenerados.
Arquivos já existentes no estado novo não são sobrescritos, e a origem
permanece intacta para rollback. Os atalhos antigos só são removidos depois da
criação bem-sucedida dos atalhos Achilles.

O catálogo de IA não é congelado no instalador. Achilles consulta `/v1/models`
do OmniRoute e permite escolher dinamicamente os combos e modelos expostos pelo
gateway, sem alterar `combos-config.json`. O resultado é cruzado com
`/api/providers`: combos continuam disponíveis, mas modelos diretos aparecem
somente para providers conectados pelo usuário.

Ao final da instalação, o setup valida executável, launcher, versão ativa,
configuração dinâmica, origem da AppKey e filtro de providers. Uma falha nessa
etapa interrompe o fluxo em vez de anunciar uma instalação incompleta.

## Operação

Depois de abrir um novo PowerShell:

```powershell
omni.ps1 status
omni.ps1 dashboard
omni.ps1 ide
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
