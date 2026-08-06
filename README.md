# OmniRoute Setup para Windows

Instalador idempotente do OmniRoute em contêiner, acessível no host em
`http://localhost:20128`.

O setup também instala o **Achilles**, uma IDE desktop
experimental baseada no Eclipse Theia. Ela trabalha diretamente na pasta local
de projetos e consulta dinamicamente os combos e modelos do OmniRoute.

O instalador preserva o banco, a APPKEY e as skills em reexecuções. Nenhum
processo Node genérico ou banco existente é apagado.

## Instalação recomendada

Abra o **PowerShell** como usuário normal e execute:

```powershell
irm https://raw.githubusercontent.com/pmacedo25/omniroute-container-setup/master/install.ps1 | iex
```

Para atualizar somente OmniRoute, skills e configurações, sem baixar ou
reinstalar o Achilles:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/pmacedo25/omniroute-container-setup/master/install.ps1))) -SkipAchilles
```

Esse é o fluxo recomendado para primeira instalação e atualização. Não é
necessário clonar o repositório, instalar Git previamente ou abrir o terminal
como administrador. O comando usa somente endpoints públicos do GitHub:

1. baixa o bootstrap por `raw.githubusercontent.com`;
2. consulta o release estável mais recente pela API pública;
3. baixa e valida a estrutura do pacote de código-fonte;
4. mantém a cópia operacional em `%USERPROFILE%\.omniroute\setup`;
5. inicia o instalador assistido.

O `.env` existente é preservado nas atualizações. Portanto, o mesmo comando
pode ser reexecutado depois de uma falha ou para buscar uma versão nova sem
perder AppKey e configurações já criadas.

Na reexecução, os combos declarados são reconciliados pelo nome: os existentes
são atualizados, os ausentes são criados e os demais combos do usuário são
preservados. Para atualizar também o runtime e a afinidade de sessão do
Achilles, use o comando completo sem `-SkipAchilles`.

Os combos gerenciados usam somente a lista ordenada de modelos declarada em
`combos-config.json`. O setup desativa handoff, hedging, exploração e fallback
chains globais, valida o estado retornado pelo OmniRoute e recria apenas um
combo gerenciado que ainda contenha destinos antigos. Uma falha de todos os
modelos do combo retorna erro; ela nunca autoriza selecionar um modelo externo.
O provider de sistema **Auto (Zero Config)** também é incluído em
`Settings → Security → Blocked Providers` e precisa desaparecer de `/v1/models`
antes de a instalação ser considerada concluída.

Os logins OAuth que exigem consentimento continuam sendo abertos pelo próprio
instalador.

## Execução a partir do código-fonte

Os comandos abaixo são voltados ao desenvolvimento do instalador ou a cenários
em que o repositório já está disponível localmente.

Modo assistido:

```powershell
.\setup-interativo.ps1
```

O repositório corporativo `nio-internet/agents-templates` é usado por padrão,
mas pode ser substituído por parâmetro. Nenhuma pasta de projetos é criada: o
Achilles abre como uma IDE comum e trabalha com as pastas ou workspaces
escolhidos em cada janela.

Modo automático:

```powershell
.\setup-interativo.ps1 -NonInteractive `
  -SkillsRepository "nio-internet/agents-templates" `
  -SkipProviderLogin
```

Parâmetros úteis:

- `-SkillsRepository <owner/repo|URL>` (padrão:
  `nio-internet/agents-templates`) e `-SkillsBranch <nome>`
- `-Port 20128`
- `-SkipAchilles` para instalar somente o gateway
- `-AchillesVersion <semver|latest>`
- `-AchillesArtifactPath <zip>` para validar um build local sem GitHub
- `-CorporateCAPath <cadeia-netskope.pem>` quando a cadeia corporativa Netskope
  não puder ser descoberta no repositório de certificados do Windows
- `-NonInteractive` para CI/provisionamento

A autenticação OAuth dos provedores continua dependendo do consentimento no
navegador. Todo o restante, incluindo APPKEY, bloqueio dos providers sem
autenticação, persistência, sincronização das skills e configuração do Achilles,
é automático. Os três combos gerenciados são criados ou atualizados conforme
`combos-config.json`; combos adicionais permanecem sob controle do usuário.

O setup cria uma única AppKey `omniroute-setup`, com escopo `manage`, e a grava
como `OMNIROUTE_API_KEY` no `.env` privado e no ambiente do usuário. O escopo
administrativo não desativa a contabilização: inferências feitas pelo Achilles
continuam atribuídas ao ID dessa chave, incluindo requisições, tokens e custo.
Assim o mesmo segredo atende setup e IDE sem uma segunda etapa manual.

O setup não depende do GitHub CLI. Para um repositório privado ou `INTERNAL`,
ele reutiliza `GITHUB_TOKEN`/`GH_TOKEN` do ambiente ou o token já preservado no
`.env`; no modo interativo também permite informá-lo em um prompt oculto. Para
repositórios públicos, basta deixar o token vazio. O token precisa de acesso de
leitura ao repositório e, quando aplicável, autorização SSO da organização.
Depois de criar a AppKey, o instalador executa uma sincronização obrigatória
dentro do próprio container. A instalação falha com diagnóstico acionável se o
token não acessar o repositório ou se nenhuma entrada `pat-*` aparecer na API;
só então a atualização periódica é iniciada.

## Arquitetura

Na instalação:

- `diegosouzapw/omniroute:3.8.49`: imagem oficial, sem toolchains de build.
- `agent-skills-sync:1`: converte o repositório de governança em skills
  canônicas globais do Caveman e reconcilia a cada hora.
- o volume nomeado preserva o banco do OmniRoute; as skills ficam no diretório
  global `~/.cave/skills` do host.
- a porta `20128` fica disponível no host. A APPKEY continua obrigatória.
- reexecuções mantêm apenas uma AppKey chamada `omniroute-setup`; duplicatas
  antigas criadas pelo próprio instalador são removidas sem afetar chaves de
  terceiros.
- RTK é o único compressor habilitado no gateway; Caveman e os demais motores
  permanecem desligados para não comprimir duas vezes.
- a CA corporativa só é montada quando detectada ou fornecida explicitamente.

## Achilles

O Achilles é instalado em escopo de usuário, sem UAC. O setup baixa o release
público do repositório exclusivo de binários, valida o SHA-256 e
extrai versões lado a lado em `%LOCALAPPDATA%\Programs\Achilles`.
Também cria o comando estável `achilles` em `%USERPROFILE%\.omniroute\bin`,
inclui esse diretório no PATH do usuário e registra atalhos na Área de Trabalho
e no Menu Iniciar. A versão ativa é exposta pelo caminho estável `current`; o
setup também corrige atalhos Achilles já fixados na barra de tarefas para não
prendê-los a uma versão. Assim, um novo terminal pode executar `achilles` e a pesquisa
do Windows encontra o aplicativo sem MSI ou permissões administrativas.

Projetos permanecem onde o usuário escolher, e a configuração do aplicativo
fica em `%USERPROFILE%\.achilles`. A AppKey não é duplicada no
JSON: o processo lê `OMNIROUTE_API_KEY` do ambiente do usuário. O setup é a
mesma ativação estável é usada pelo setup e pelo atualizador integrado. A versão
anterior é removida automaticamente depois que a nova IDE inicia.

Ao detectar OpenRouterAI, o setup copia conversas, preferências e demais
configurações persistentes de `%USERPROFILE%\.openrouterai` para `%USERPROFILE%\.achilles`.
Caches, layouts temporários e launchers com a marca antiga são regenerados.
Arquivos já existentes no estado novo não são sobrescritos, e a origem
permanece intacta para rollback. Os atalhos antigos só são removidos depois da
criação bem-sucedida dos atalhos Achilles.

O catálogo de IA não é congelado no instalador. Achilles consulta `/v1/models`
do OmniRoute e permite escolher dinamicamente os combos declarados e modelos
expostos pelo gateway. Ofertas sem autenticação ficam em `blockedProviders`;
conexões e combos criados pelo usuário são preservados.

O sincronizador não instala, remove nem publica documentos em `/api/skills` do
OmniRoute e não usa o antigo volume `omniroute-skills`. Ele materializa
`pat-*/SKILL.md` em `~/.cave/skills`, onde o Caveman faz descoberta
progressiva nativa: nome e descrição para seleção, conteúdo completo somente sob
demanda. Nenhum projeto consumidor precisa clonar o repositório de templates.

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
