$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectDirectory = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectDirectory "scripts\OmniRoute.Setup.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $projectDirectory "scripts\Achilles.Setup.psm1") -Force -DisableNameChecking
$testRoot = Join-Path $projectDirectory ".test-home"
$originalUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$originalGitHubToken = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "Process")
$originalGhToken = [Environment]::GetEnvironmentVariable("GH_TOKEN", "Process")

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) { throw "ASSERT FAILED: $Message. Expected='$Expected'; Actual='$Actual'" }
}

function Assert-Utf8WithoutBom {
    param([string]$Path, [string]$Message)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasUtf8Bom = $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True (-not $hasUtf8Bom) $Message
}

if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
New-Item -ItemType Directory -Path $testRoot | Out-Null

try {
    $envPath = Join-Path $testRoot ".env"
    Set-EnvValue $envPath "PORT" "20128"
    Set-EnvValue $envPath "SECRET" "first"
    Set-EnvValue $envPath "SECRET" "second"
    Assert-Equal "second" (Get-EnvValue $envPath "SECRET") "Set-EnvValue deve atualizar"
    Assert-Equal 1 (@(Get-Content $envPath | Where-Object { $_ -match "^SECRET=" }).Count) "Variável não pode duplicar"
    Set-EnvValue $envPath "OPENHANDS_VERSION" "legacy"
    Set-EnvValue $envPath "GITHUB_TOKEN" "legacy-secret"
    Remove-EnvValue $envPath @("OPENHANDS_VERSION", "GITHUB_TOKEN")
    Assert-True ($null -eq (Get-EnvValue $envPath "OPENHANDS_VERSION")) "Configuração legada deve ser removida"
    Assert-True ($null -eq (Get-EnvValue $envPath "GITHUB_TOKEN")) "Segredo legado não pode permanecer no ambiente"

    $combos = Get-Content (Join-Path $projectDirectory "combos-config.json") -Raw | ConvertFrom-Json
    Assert-Equal $true $combos.enabled "Combos declarativos devem nascer habilitados"
    Assert-Equal 3 @($combos.combos).Count "Instalador deve provisionar os três combos do projeto"
    Assert-True (@($combos.combos | ForEach-Object name) -contains "combo-coding") "Manifesto deve criar combo-coding"
    Assert-True (@($combos.combos | ForEach-Object strategy | Select-Object -Unique) -notcontains "auto") "Combos não devem usar estratégia auto"
    Assert-True (@($combos.combos | Where-Object { $_.strategy -ne "lkgp" }).Count -eq 0) "Combos de chat devem manter afinidade com o último destino saudável"
    Assert-True (@($combos.combos | Where-Object { $_.config.failoverBeforeRetry }).Count -eq 0) "Combos devem tentar preservar o destino atual antes do failover"
    Assert-Equal $false $combos.allowGlobalFallbackChains "Fallback chains globais devem ficar desativadas"
    Assert-True (@($combos.combos | Where-Object { $_.config.handoffModel -ne "" }).Count -eq 0) "Combos não podem fazer handoff para modelo externo"
    Assert-True (@($combos.combos | Where-Object { $_.config.zeroLatencyOptimizationsEnabled -or $_.config.hedging -or $_.config.explorationRate -ne 0 }).Count -eq 0) "Combos não podem fazer roteamento especulativo"
    Assert-True (@($combos.combos | ForEach-Object { $_.config.compressionMode } | Select-Object -Unique) -notcontains "stacked") "Combos OmniRoute não devem habilitar Caveman"
    $configuredModels = @($combos.combos | ForEach-Object models)
    Assert-True (@($configuredModels | Where-Object { $_ -like "claude/*" }).Count -gt 0) "Combos devem manter modelos da conta Claude"
    Assert-True (@($configuredModels | Where-Object { $_ -like "github/*" }).Count -gt 0) "Combos devem manter modelos da conta GitHub Copilot"
    Assert-True (@($configuredModels | Where-Object { $_ -like "antigravity/*" -or $_ -like "cx/*" }).Count -eq 0) "Combos não devem depender de providers fora de Claude e GitHub Copilot"
    Assert-True (@($combos.managedNames) -contains "combo-coding") "Manifesto deve reconhecer e limpar combos legados"
    $normalizedModels = @(
        [pscustomobject]@{ kind = "model"; providerId = "github"; model = "github/gpt-5.3-codex" },
        [pscustomobject]@{ kind = "model"; providerId = "claude"; model = "claude-sonnet-4-6" }
    )
    Assert-True (Test-ComboModelSequence `
        -Expected @("github/gpt-5.3-codex", "claude/claude-sonnet-4-6") `
        -Actual $normalizedModels) "Validação deve aceitar a normalização oficial dos modelos"
    Assert-True (-not (Test-ComboModelSequence `
        -Expected @("github/gpt-5.3-codex", "claude/claude-sonnet-4-6") `
        -Actual @($normalizedModels[0], [pscustomobject]@{ model = "claude/claude-sonnet-5" }))) `
        "Validação deve rejeitar modelo caro inserido fora do combo"
    Assert-True (Test-Path (Join-Path $projectDirectory "benchmarks\README.md")) "Matriz de benchmark deve estar versionada"

    Assert-Equal "C:\Tools" (Get-PathWithEntry -CurrentPath $null -Entry "C:\Tools") "PATH nulo deve ser suportado"
    Assert-Equal "C:\Windows;C:\Tools" (Get-PathWithEntry -CurrentPath "C:\Windows" -Entry "C:\Tools") "Entrada deve ser adicionada"
    Assert-Equal "C:\Windows;C:\Tools" (Get-PathWithEntry -CurrentPath "C:\Windows;C:\Tools" -Entry "c:\tools\") "Entrada não pode duplicar"
    Assert-Equal "https://github.com/nio-internet/agents-templates.git" `
        (Resolve-SkillsRepositoryUrl "nio-internet/agents-templates") `
        "Slug corporativo deve ser convertido para HTTPS"
    Assert-Equal "https://git.example.com/team/skills.git" `
        (Resolve-SkillsRepositoryUrl "https://git.example.com/team/skills.git") `
        "URL Git completa deve ser preservada"

    [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $null, "Process")
    [Environment]::SetEnvironmentVariable("GH_TOKEN", $null, "Process")
    Set-Content -LiteralPath $envPath -Value "PORT=20128" -Encoding utf8
    Assert-True ($null -eq (Resolve-SkillsGitHubToken -EnvPath $envPath -NonInteractive $true)) `
        "Repositório público não deve exigir token"
    [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", "environment-test-token", "Process")
    Assert-Equal "environment-test-token" `
        (Resolve-SkillsGitHubToken -EnvPath $envPath -NonInteractive $true) `
        "GITHUB_TOKEN do processo deve ser reutilizado"
    [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $null, "Process")
    Set-EnvValue $envPath "GITHUB_TOKEN" "persisted-test-token"
    Assert-Equal "persisted-test-token" `
        (Resolve-SkillsGitHubToken -EnvPath $envPath -NonInteractive $true) `
        "Token persistido deve sobreviver à atualização do instalador"

    $testLauncher = Join-Path $testRoot ".achilles\Achilles.ps1"
    New-Item -ItemType Directory -Path (Split-Path -Parent $testLauncher) -Force | Out-Null
    Set-Content -LiteralPath $testLauncher -Value "param()" -Encoding utf8
    $achillesCommand = Install-AchillesCommand -HomeDirectory $testRoot -LauncherPath $testLauncher
    Assert-True (Test-Path -LiteralPath $achillesCommand -PathType Leaf) "Comando achilles deve ser criado"
    Assert-True ((Get-Content -LiteralPath $achillesCommand -Raw) -match '%\*') "Comando deve encaminhar argumentos"
    Assert-True (@([Environment]::GetEnvironmentVariable("Path", "User") -split ";" |
        Where-Object { $_ -ieq (Split-Path -Parent $achillesCommand) }).Count -eq 1) "Comando deve entrar no PATH do usuário uma única vez"
    Install-AchillesCommand -HomeDirectory $testRoot -LauncherPath $testLauncher | Out-Null
    Assert-True (@([Environment]::GetEnvironmentVariable("Path", "User") -split ";" |
        Where-Object { $_ -ieq (Split-Path -Parent $achillesCommand) }).Count -eq 1) "Reexecução não pode duplicar PATH"

    $junctionRoot = Join-Path $testRoot "junction-install"
    $junctionVersion = Join-Path $junctionRoot "0.2.41-test"
    New-Item -ItemType Directory -Path $junctionVersion -Force | Out-Null
    $junctionExecutable = Join-Path $junctionVersion "Achilles.exe"
    Set-Content -LiteralPath $junctionExecutable -Value "stable-version" -Encoding ascii
    $achillesModule = Get-Module Achilles.Setup
    $stableExecutable = & $achillesModule {
        param($Root, $Version, $Executable)
        Set-AchillesCurrentLink -InstallRoot $Root -VersionDirectory $Version -ExecutablePath $Executable
    } $junctionRoot $junctionVersion $junctionExecutable
    Assert-Equal (Join-Path $junctionRoot "current\Achilles.exe") $stableExecutable `
        "Ativação deve retornar caminho independente da versão"
    Assert-True ((Get-Content -LiteralPath $stableExecutable -Raw) -match "stable-version") `
        "Junction current deve resolver o executável ativo"
    $generatedLauncher = & $achillesModule {
        param($Home, $Root)
        New-AchillesLauncher -HomeDirectory $Home -InstallRoot $Root
    } $testRoot $junctionRoot
    try {
        [void][scriptblock]::Create((Get-Content -LiteralPath $generatedLauncher -Raw))
    } catch {
        throw "ASSERT FAILED: launcher com atualização de PATH deve ter sintaxe válida. $($_.Exception.Message)"
    }

    $achillesConfig = Write-AchillesConfiguration -HomeDirectory $testRoot `
        -OmniRoutePort 20128
    Assert-Utf8WithoutBom $achillesConfig `
        "Config do Achilles deve ser UTF-8 sem BOM para o JSON.parse do Node"
    $achillesSettings = Get-Content -LiteralPath $achillesConfig -Raw | ConvertFrom-Json
    Assert-Equal "http://127.0.0.1:20128/v1" $achillesSettings.omnirouteBaseUrl "IDE deve usar loopback do host"
    Assert-Equal "http://127.0.0.1:20128/v1/models" $achillesSettings.omnirouteCatalogUrl "IDE deve consultar catálogo dinâmico"
    Assert-Equal "OMNIROUTE_API_KEY" $achillesSettings.apiKeyEnvironmentVariable "Config não deve duplicar segredo"
    Assert-Equal "dynamic" $achillesSettings.modelSelection "Seleção não pode ser hardcoded no instalador"
    Assert-Equal $true $achillesSettings.configuredProvidersOnly "IDE deve listar apenas providers conectados"
    Assert-True ($null -eq $achillesSettings.PSObject.Properties["workspace"]) "IDE não deve fixar uma pasta de trabalho"
    Assert-True ($null -eq $achillesSettings.PSObject.Properties["allowedCombos"]) "Config não deve fixar combos"
    Assert-True (-not (Get-Content -LiteralPath $achillesConfig -Raw).Contains("sk-")) "Config da IDE não deve conter chave"

    $legacyStateDirectory = Join-Path $testRoot ".openrouterai"
    New-Item -ItemType Directory -Path (Join-Path $legacyStateDirectory "conversations") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $legacyStateDirectory "conversations\history.json") -Value '{"preserved":true}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $legacyStateDirectory "user-preferences.json") -Value '{"theme":"dark"}' -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $legacyStateDirectory "workspace-storage") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $legacyStateDirectory "workspace-storage\layout.json") -Value '{"title":"OpenRouterAI"}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $legacyStateDirectory "OpenRouterAI.ps1") -Value "legacy launcher" -Encoding utf8
    Assert-True (Copy-AchillesLegacyState -HomeDirectory $testRoot) "Estado legado deve ser detectado"
    Assert-True (Test-Path (Join-Path $testRoot ".achilles\conversations\history.json")) "Conversas devem ser copiadas"
    Assert-True (Test-Path (Join-Path $testRoot ".achilles\user-preferences.json")) "Preferências devem ser copiadas"
    Assert-True (Test-Path (Join-Path $legacyStateDirectory "conversations\history.json")) "Estado legado deve permanecer para rollback"
    Assert-True (-not (Test-Path (Join-Path $testRoot ".achilles\workspace-storage"))) "Layout legado não deve contaminar a marca Achilles"
    Assert-True (-not (Test-Path (Join-Path $testRoot ".achilles\OpenRouterAI.ps1"))) "Launcher legado não deve ser migrado"
    Set-Content -LiteralPath (Join-Path $testRoot ".achilles\user-preferences.json") -Value '{"theme":"custom"}' -Encoding utf8
    Assert-True (Copy-AchillesLegacyState -HomeDirectory $testRoot) "Migração deve ser reexecutável"
    Assert-True ((Get-Content -LiteralPath (Join-Path $testRoot ".achilles\user-preferences.json") -Raw) -match "custom") "Reexecução não deve sobrescrever estado novo"
    Assert-Equal "0.1.0" (Get-AchillesVersion -ArtifactPath "Achilles-win-x64-0.1.0.zip" -ManifestPath "") "Versão deve vir do artefato"
    $artifactPath = Join-Path $testRoot "Achilles-win-x64-0.1.0.zip"
    Set-Content -LiteralPath $artifactPath -Value "safe-test-artifact" -Encoding ascii
    $artifactHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sumsPath = Join-Path $testRoot "SHA256SUMS"
    Set-Content -LiteralPath $sumsPath -Value "$artifactHash  Achilles-win-x64-0.1.0.zip" -Encoding ascii
    Assert-Equal $artifactHash (Test-AchillesArtifact -ArtifactPath $artifactPath -Sha256SumsPath $sumsPath) "Checksum válido deve ser aceito"
    Set-Content -LiteralPath $sumsPath -Value "$("0" * 64)  Achilles-win-x64-0.1.0.zip" -Encoding ascii
    $checksumRejected = $false
    try {
        Test-AchillesArtifact -ArtifactPath $artifactPath -Sha256SumsPath $sumsPath | Out-Null
    } catch {
        $checksumRejected = $_.Exception.Message -match "^Checksum "
    }
    Assert-True $checksumRejected "Checksum adulterado deve ser rejeitado"

    $setupSource = Get-Content (Join-Path $projectDirectory "setup-interativo.ps1") -Raw
    $bootstrapPath = Join-Path $projectDirectory "install.ps1"
    $bootstrapSource = Get-Content $bootstrapPath -Raw
    Assert-Utf8WithoutBom $bootstrapPath `
        "Bootstrap executado por irm | iex deve ser UTF-8 sem BOM"
    try {
        [void][scriptblock]::Create($bootstrapSource)
    } catch {
        throw "ASSERT FAILED: conteúdo do bootstrap deve ser aceito por irm | iex. $($_.Exception.Message)"
    }
    $envExampleSource = Get-Content (Join-Path $projectDirectory ".env.example") -Raw
    $moduleSource = Get-Content (Join-Path $projectDirectory "scripts\OmniRoute.Setup.psm1") -Raw
    $achillesModuleSource = Get-Content (Join-Path $projectDirectory "scripts\Achilles.Setup.psm1") -Raw
    $composeSource = Get-Content (Join-Path $projectDirectory "docker-compose.yml") -Raw
    $skillsSyncSource = Get-Content (Join-Path $projectDirectory "skills-sync\sync-lib.sh") -Raw
    Assert-True ($moduleSource -notmatch "taskkill\s+/F\s+/IM\s+node") "Não pode encerrar todos os processos Node"
    Assert-True ($moduleSource -notmatch "Remove-Item.+sqlite") "Reexecução não pode apagar SQLite"
    Assert-True ($setupSource -notmatch "Read-Host.+APPKEY") "APPKEY deve ser automática"
    Assert-True ($setupSource -match 'SkillsRepository = "nio-internet/agents-templates"') "Setup deve usar o repositório corporativo de skills por padrão"
    Assert-True ($moduleSource -match 'function Resolve-SkillsRepositoryUrl') "Setup deve aceitar owner/repo e URL Git completa"
    Assert-True ($moduleSource -match 'https://github\.com/\$slug\.git') "Slug GitHub deve ser normalizado para clone HTTPS"
    Assert-True ($bootstrapSource -match 'releases/latest') "Bootstrap deve instalar um release estável"
    Assert-True ($bootstrapSource -match 'AchillesVersion = "latest"') "Bootstrap deve encaminhar latest explicitamente por padrão"
    Assert-True ($bootstrapSource -match '"\.omniroute"') "Bootstrap deve usar o estado persistente do OmniRoute"
    Assert-True ($bootstrapSource -match '\$installDirectory.+Join-Path \$stateDirectory "setup"') "Bootstrap deve persistir os arquivos para reexecução"
    Assert-True ($bootstrapSource -match '\$relativePath -ne "\.env"') "Bootstrap deve preservar o ambiente existente"
    Assert-True ($bootstrapSource -match 'Get-ChildItem.+-File -Recurse') "Atualização deve sobrepor arquivos individualmente sem aninhar módulos antigos"
    Assert-True ($bootstrapSource -match 'ExecutionPolicy"?,?\s+"?Bypass') "Bootstrap deve funcionar sem alterar a policy do usuário"
    Assert-True ($bootstrapSource -match '\[switch\]\$SkipAchilles') "Bootstrap deve aceitar SkipAchilles diretamente"
    Assert-True ($bootstrapSource -match '\$setupArguments \+= "-\$switchName"') "Bootstrap deve encaminhar switches ao setup interno"
    Assert-True ($envExampleSource -match '(?m)^OMNIROUTE_SKILLS_REPO=\s*$') "Exemplo de ambiente não deve sugerir repositório de skills"
    Assert-True ($envExampleSource -match '(?m)^OMNIROUTE_SKILLS_PATH=\s*$') "Caminho de skills deve ser opcional e autodetectável"
    Assert-True ($composeSource -match 'SKILLS_PATH:\s+\$\{OMNIROUTE_SKILLS_PATH:-\}') "Compose deve encaminhar o caminho configurado ao sincronizador"
    Assert-True ($setupSource -notmatch 'ProjectsPath|WorkspacePath') "Setup não deve solicitar uma pasta de projetos"
    Assert-True ($moduleSource -notmatch 'Set-EnvValue.+PROJECTS_DIR') "Setup não deve criar uma raiz artificial de projetos"
    Assert-True ($moduleSource -match 'Read-Host "APPKEY do OmniRoute"') "Setup deve aceitar APPKEY manual como fallback"
    Assert-True ($moduleSource -match 'Test-RegisteredAppKey') "APPKEY existente precisa estar registrada no dashboard"
    Assert-True ($moduleSource -match '\{"name":"omniroute-setup","label":"omniroute-setup"') "Criação da APPKEY deve suportar os schemas real e documentado"
    Assert-True ($moduleSource -match 'x-omniroute-cli-token') "Container deve criar a primeira AppKey pelo canal CLI local"
    Assert-True ($moduleSource -match 'scopes:\s+\["manage"\]') "AppKey do setup deve receber escopo de gestão"
    Assert-True ($moduleSource -match 'status\.setupComplete \|\| status\.hasPassword') "Fallback de onboarding só pode operar em instância nova"
    Assert-True ($moduleSource -match 'AppKey criada, mas a proteção de login não foi restaurada') "Bootstrap deve restaurar a proteção de login"
    Assert-True ($moduleSource -match 'PATCH[\s\S]+scopes:\s+\["manage"\]') "Bootstrap deve aplicar o escopo manage antes de restaurar o login"
    Assert-True ($moduleSource -match 'Restart-ContainerGateway[\s\S]+compose", "restart", "omniroute"') "Gateway deve recarregar o cache de escopos após o bootstrap"
    Assert-True ($moduleSource -notmatch 'Install-OpenCode|Set-OpenHands|Start-PodmanOpenHands|Install-OpenHands') "Setup não deve conter integrações legadas"
    Assert-True ($composeSource -notmatch '(?i)openhands|opencode') "Compose não deve conter clientes legados"
    Assert-True ($envExampleSource -notmatch '(?i)openhands|opencode') "Ambiente não deve conter opções legadas"
    Assert-Equal 0 @(Get-ChildItem (Join-Path $projectDirectory "openhands") -File -ErrorAction SilentlyContinue).Count "Imagem customizada legada deve ser removida"
    Assert-True ($moduleSource -match 'Remove-DuplicateSetupAppKeys') "Setup deve consolidar suas AppKeys duplicadas"
    Assert-True ($moduleSource -match 'PSObject\.Properties\[\$propertyName\]') "Leitura de AppKeys deve tolerar campos opcionais"
    Assert-True ($moduleSource -notmatch 'GitHub\.cli|gh auth') "Setup não deve depender do GitHub CLI"
    Assert-True ($moduleSource -match 'Resolve-SkillsGitHubToken') "Setup deve resolver token sem GitHub CLI"
    Assert-True ($moduleSource -match '\$env:GITHUB_TOKEN') "Setup deve aceitar GITHUB_TOKEN"
    Assert-True ($moduleSource -match '\$env:GH_TOKEN') "Setup deve aceitar GH_TOKEN"
    Assert-True ($moduleSource -match 'Read-Host "Token GitHub \(opcional\)" -AsSecureString') "Prompt interativo deve ocultar o token"
    Assert-True ($moduleSource -match 'COMPOSE_CONVERT_WINDOWS_PATHS = "0"') "Compose não deve converter o socket Linux"
    Assert-True ($moduleSource -match 'Remove-UnmanagedPodmanContainer') "Reexecução deve corrigir containers fora do Compose"
    Assert-True ($moduleSource -match '"rm", "--force", \$ContainerName') "Correção deve remover somente o container incompatível"
    Assert-True ($moduleSource -match 'volumes persistentes serão preservados') "Correção deve informar que os volumes são preservados"
    Assert-True ($moduleSource -match 'Set-ConfiguredProvidersOnly') "Setup deve convergir providers configurados"
    Assert-True ($moduleSource -match 'blockedProviders') "Providers no-auth devem ser bloqueados pela configuração oficial"
    Assert-True ($moduleSource -match '\$noAuthProviderIds\s*=\s*@\(\s*"auto"') "Auto Zero Config deve ser bloqueado por padrão"
    Assert-True ($moduleSource -match 'catálogo ainda anuncia rotas auto/\*') "Setup deve validar que Auto Zero Config saiu do catálogo"
    Assert-True ($moduleSource -match 'PSObject\.Properties\["blockedProviders"\]') "Ausência inicial de blockedProviders deve ser tratada sem enviar null"
    Assert-True ($moduleSource -notmatch 'Method Delete.+api/providers') "Conexões do usuário nunca devem ser apagadas"
    Assert-True ($moduleSource -match 'Set-TokenEfficiencyDefaults') "Setup deve aplicar otimizações de tokens"
    Assert-True ($moduleSource -match 'existingByName\.ContainsKey\(\$combo\.name\)[\s\S]+-Method Put') "Reexecução deve atualizar combos gerenciados já existentes"
    Assert-True ($moduleSource -match 'api/combos" -Method Post') "Instalação nova deve criar combos gerenciados ausentes"
    Assert-True ($moduleSource -match 'lista estrita de modelos') "Convergência deve confirmar o contrato estrito dos combos gerenciados"
    Assert-True ($moduleSource -match 'combos do usuário foram preservados') "Convergência deve preservar combos não gerenciados quando o modo declarativo for desativado"
    Assert-True ($moduleSource -match 'não confirmou a estratégia') "Convergência deve validar a estratégia persistida pelo OmniRoute"
    Assert-True ($moduleSource -match 'Test-AchillesInstallation') "Setup deve validar o Achilles após instalar"
    Assert-True ($moduleSource -match 'Install-Achilles') "Setup deve instalar Achilles"
    Assert-True ($achillesModuleSource -match 'Microsoft\\Windows\\Start Menu\\Programs') "Achilles deve ser localizado pela pesquisa do Windows"
    Assert-True ($achillesModuleSource -match 'achilles\.cmd') "Setup deve criar o comando achilles"
    Assert-True ($achillesModuleSource -notmatch 'ProjectsDirectory') "Launcher não deve impor uma pasta padrão"
    Assert-True ($achillesModuleSource -match 'IsNullOrWhiteSpace\(`\$_\)') "Launcher deve ignorar argumentos vazios do PowerShell 5"
    Assert-True ($achillesModuleSource -match 'launcher-error\.log') "Falhas ocultas do launcher devem deixar diagnóstico"
    Assert-True ($achillesModuleSource -match 'NODE_EXTRA_CA_CERTS') "Launcher deve propagar a cadeia Netskope para o Node do Achilles"
    Assert-True ($achillesModuleSource -match 'GetEnvironmentVariable\("Path", "Machine"\)') "Launcher deve reler o PATH atual da máquina"
    Assert-True ($achillesModuleSource -match 'GetEnvironmentVariable\("Path", "User"\)') "Launcher deve reler o PATH atual do usuário"
    Assert-True ($achillesModuleSource -match '\$seenPaths\.ContainsKey') "Launcher deve consolidar PATH sem entradas duplicadas"
    Assert-True ($achillesModuleSource -match 'netskope-ca\.pem') "Achilles deve reutilizar somente a cadeia corporativa detectada pelo setup"
    Assert-True ($achillesModuleSource -match 'System32\\wscript\.exe') "Atalhos devem abrir sem janela de terminal"
    Assert-True ($achillesModuleSource -match 'GraphicalLauncher') "Instalação deve validar o launcher gráfico"
    Assert-True ($achillesModuleSource -match 'function Set-AchillesCurrentLink') "Instalação deve ativar a versão por um caminho estável"
    Assert-True ($achillesModuleSource -match 'New-Item -ItemType Junction') "Caminho current deve ser um junction para a versão ativa"
    Assert-True ($achillesModuleSource -match 'installDirectory = \$versionDirectory') "Estado deve identificar a pasta física para limpeza segura"
    Assert-True ($achillesModuleSource -match 'User Pinned\\TaskBar') "Atualização deve reparar atalhos fixados na barra de tarefas"
    Assert-True ($achillesModuleSource -match 'Achilles\*\.lnk') "Todos os atalhos Achilles fixados existentes devem ser reparados"
    Assert-True ($setupSource -match 'AchillesArtifactPath') "Setup deve aceitar artefato local para validação"
    Assert-True ($setupSource -match 'Alias\("OpenRouterAIArtifactPath"\)') "Automação anterior deve continuar aceita durante a migração"
    Assert-True ($achillesModuleSource -match '\$installedExecutables = @\(if') "Reexecução com um executável deve preservar sem erro de Count"
    Assert-True ($achillesModuleSource -match 'Copy-AchillesLegacyState') "Instalador deve migrar o estado legado"
    Assert-True ($achillesModuleSource -match 'legacyStatePreserved = \$true') "Migração deve documentar rollback"
    Assert-True ($achillesModuleSource -match '\^Achilles-win-x64-') "Release deve selecionar somente artefatos Achilles"
    Assert-True ($achillesModuleSource -match 'pmacedo25/Achilles-Releases') "Instalador deve usar o repositório público de binários"
    Assert-True ($setupSource -match 'AchillesRepository = "pmacedo25/Achilles-Releases"') "Script principal deve encaminhar o repositório público"
    Assert-True ($envExampleSource -match 'ACHILLES_REPOSITORY=pmacedo25/Achilles-Releases') "Exemplo de ambiente deve usar o repositório público"
    Assert-True ($achillesModuleSource -match 'api\.github\.com/repos/\$Repository/releases') "Release público deve ser consultado sem GitHub CLI"
    Assert-True ($achillesModuleSource -match 'function Set-Utf8JsonFile') "JSONs do Achilles devem usar escritor UTF-8 sem BOM"
    Assert-True ($achillesModuleSource -match '\$artifactAsset\.digest') "Checksum deve usar o digest oficial do asset no GitHub"
    Assert-True ($achillesModuleSource -match 'Remove-Item.+SHA256SUMS') "Metadados de checksum de releases anteriores devem ser removidos"
    Assert-True ($achillesModuleSource -match 'Achilles-win-x64-\*\.zip') "Artefatos antigos não podem participar da resolução de latest"
    Assert-True ($achillesModuleSource -match 'Cache-Control.+no-cache') "Consulta de latest deve evitar cache HTTP obsoleto"
    Assert-True ($achillesModuleSource -match 'cacheBust=\$cacheBust') "Consulta de latest deve usar uma URL nova a cada execução"
    Assert-True ($achillesModuleSource -match 'não corresponde ao release') "Tag e versão do artefato devem ser consistentes"
    Assert-True ($achillesModuleSource -notmatch 'GitHub CLI é necessário para baixar') "Download público do Achilles não deve exigir autenticação"
    Assert-True ($achillesModuleSource -match 'não contém um build Achilles para Windows x64') "Release legado deve produzir erro acionável"
    Assert-True ($achillesModuleSource -match 'AchillesArtifactPath') "Erro de release deve indicar o fluxo com artefato local"
    Assert-True ($achillesModuleSource -notmatch 'allowedCombos') "Instalador não deve manter lista hardcoded de modelos"
    $omniSource = Get-Content (Join-Path $projectDirectory "scripts\omni.ps1") -Raw
    Assert-True ($omniSource -match '"ide"') "Comando omni deve abrir a IDE"
    Assert-True ($omniSource -match '\.achilles\\current\.json') "Doctor deve diagnosticar a IDE"
    Assert-True ($moduleSource -match 'defaultMode = "rtk"') "RTK deve ser o único modo padrão"
    Assert-True ($moduleSource -match 'autoTriggerMode = "off"') "Compressão automática não deve encadear motores"
    Assert-True ($moduleSource -match 'session-dedup.+enabled = \$false') "Deduplicação duplicada deve nascer desligada"
    Assert-True ($moduleSource -match 'caveman.+enabled = \$false') "Caveman deve ficar fora do OmniRoute"
    Assert-True ($moduleSource -match 'CorporateCAPath') "CA explícito deve ser aceito para Netskope corporativo"
    Assert-True ($moduleSource -match '\$inspectionPatterns = @\("\*Netskope\*", "\*goskope\*"\)') "Detecção automática deve usar somente a cadeia Netskope corporativa"
    Assert-True ($moduleSource -notmatch '\$certs \| Sort-Object Thumbprint') "A ordem da cadeia corporativa não deve ser alterada por thumbprint"
    Assert-True ($moduleSource -notmatch 'Zscaler|Fortinet|Palo Alto|Blue Coat|Symantec Web') "Instalador não deve coletar CAs corporativos genéricos"
    Assert-True ($composeSource -notmatch 'NODE_EXTRA_CA_CERTS') "Compose base não deve injetar CA sem detecção"
    Assert-True ($envExampleSource -match '(?m)^OMNIROUTE_API_KEY=\s*$') "Ambiente deve declarar uma única AppKey"
    Assert-True ($envExampleSource -notmatch 'OMNIROUTE_MANAGEMENT_API_KEY') "Ambiente não deve criar uma segunda AppKey administrativa"
    Assert-True ($moduleSource -match 'function Save-SharedAppKey') "Setup deve compartilhar a AppKey rastreável com o Achilles"
    Assert-True ($moduleSource -match 'SetEnvironmentVariable\("OMNIROUTE_API_KEY", \$AppKey, "User"\)') "A AppKey criada no bootstrap deve alimentar a IDE"
    Assert-True ($achillesModuleSource -match 'GetEnvironmentVariable\("OMNIROUTE_API_KEY", "User"\)') "Atualização da IDE deve usar a AppKey atual do usuário, não uma cópia obsoleta do processo"
    Assert-True ($achillesModuleSource -match '`\$env:OMNIROUTE_API_KEY = `\$currentApiKey') "Launcher deve substituir AppKey herdada pela chave atual do usuário"
    Assert-True ($achillesModuleSource -match '`\$env:OPENAI_API_KEY = `\$currentApiKey') "Compatibilidade OpenAI deve usar a mesma AppKey atual"
    Assert-True ($moduleSource -notmatch 'Ensure-AchillesAppKey|AppKey do Achilles') "Instalador não deve solicitar uma segunda AppKey"
    Assert-True ($composeSource -notmatch 'condition:\s+service_healthy|OMNIROUTE_URL|/api/skills') "Skills não devem depender da API do OmniRoute"
    Assert-True ($composeSource -match 'CAVEMAN_SKILLS_DIR') "Skills devem ser materializadas no diretório global do Caveman"
    Assert-True ($moduleSource -match 'Start-ValidatedSkillsSync[\s\S]+SKILLS_SYNC_ONCE=true') "Instalador deve validar a primeira sincronização no container"
    Assert-True ($skillsSyncSource -notmatch 'mv "\$staging_skills/\$id"') "Publicação não deve mover arquivos Linux diretamente para o volume Windows"
    Assert-True ($skillsSyncSource -match 'cp -R "\$staging_skills/\$id/\." "\$incoming/"') "Publicação deve copiar sem preservar ownership Unix"
    Assert-True ($skillsSyncSource -match 'skill_tree_hash') "Mudanças em assets também devem atualizar a skill"
    Assert-True ($moduleSource -match 'autorização SSO do token') "Erro de repositório INTERNAL deve orientar sobre autorização organizacional"
    Assert-True ($moduleSource -match "source: '\$\{yamlAbsPath\}'") "Mount do CA deve citar o caminho Windows"
    Assert-True ($moduleSource -match 'type: bind[\s\S]+target: /certs/corporate-ca\.pem[\s\S]+read_only: true') "Mount do CA deve usar sintaxe longa compatível com Docker e Podman"
    Assert-True ($moduleSource -match "managedCount.+-eq 0") "Instalação deve falhar quando nenhuma skill for publicada"
    Assert-True ($moduleSource -notmatch 'Remove-LegacyOmniSkills|/api/skills') "Setup não deve depender do executor de skills do OmniRoute"
    Assert-True ($composeSource -notmatch 'omniroute-skills') "Compose não deve recriar o volume omniroute-skills removido"
    Assert-True ($composeSource -match '3\.8\.49') "Container deve usar a release atual do OmniRoute"
    Assert-True ($moduleSource -match 'Set-EnvValue \$envPath "OMNIROUTE_VERSION" "3\.8\.49"') "Reexecução deve atualizar instalações preservadas para 3.8.49"
    Assert-True ($setupSource -notmatch '\bMode\b|SkillsPath') "Setup público deve expor somente a instalação em container e autodetectar skills"
    Assert-True ($moduleSource -notmatch 'Start-LocalMode|Ensure-LocalDependencies|Sync-SkillsRepository|ScheduledTask') "Implementação local deve ser removida"
    Assert-True ($bootstrapSource -match 'Console\]::OutputEncoding = \$utf8') "Bootstrap deve forçar saída UTF-8"
    Assert-True ($setupSource -match 'Console\]::OutputEncoding = \$utf8') "Setup deve forçar saída UTF-8"
    Assert-True ($moduleSource -match 'compose", "up"[\s\S]+"omniroute"') "Gateway deve iniciar antes do sincronizador que depende da AppKey"
    Assert-True ($composeSource -match '"\$\{PORT:-20128\}:\$\{PORT:-20128\}"') "OmniRoute deve ficar acessível no host"
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $projectDirectory "setup-interativo.ps1"), [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-Equal 0 @($parseErrors).Count "Script principal precisa ter sintaxe válida"

    Write-Host "PASS: todos os testes foram aprovados." -ForegroundColor Green
} finally {
    [Environment]::SetEnvironmentVariable("Path", $originalUserPath, "User")
    [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $originalGitHubToken, "Process")
    [Environment]::SetEnvironmentVariable("GH_TOKEN", $originalGhToken, "Process")
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
