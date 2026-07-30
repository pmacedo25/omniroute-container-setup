$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectDirectory = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectDirectory "scripts\OmniRoute.Setup.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $projectDirectory "scripts\Achilles.Setup.psm1") -Force -DisableNameChecking
$testRoot = Join-Path $projectDirectory ".test-home"
$originalUserPath = [Environment]::GetEnvironmentVariable("Path", "User")

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) { throw "ASSERT FAILED: $Message. Expected='$Expected'; Actual='$Actual'" }
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
    Assert-True (@($combos.combos | ForEach-Object { $_.config.compressionMode } | Select-Object -Unique) -notcontains "stacked") "Combos OmniRoute não devem habilitar Caveman"
    $configuredModels = @($combos.combos | ForEach-Object models)
    Assert-True (@($configuredModels | Where-Object { $_ -like "claude/*" }).Count -gt 0) "Combos devem manter modelos da conta Claude"
    Assert-True (@($configuredModels | Where-Object { $_ -like "github/*" }).Count -gt 0) "Combos devem manter modelos da conta GitHub Copilot"
    Assert-True (@($configuredModels | Where-Object { $_ -like "antigravity/*" -or $_ -like "cx/*" }).Count -eq 0) "Combos não devem depender de providers fora de Claude e GitHub Copilot"
    Assert-True (@($combos.managedNames) -contains "combo-coding") "Manifesto deve reconhecer e limpar combos legados"
    Assert-True (Test-Path (Join-Path $projectDirectory "benchmarks\README.md")) "Matriz de benchmark deve estar versionada"

    Assert-Equal "C:\Tools" (Get-PathWithEntry -CurrentPath $null -Entry "C:\Tools") "PATH nulo deve ser suportado"
    Assert-Equal "C:\Windows;C:\Tools" (Get-PathWithEntry -CurrentPath "C:\Windows" -Entry "C:\Tools") "Entrada deve ser adicionada"
    Assert-Equal "C:\Windows;C:\Tools" (Get-PathWithEntry -CurrentPath "C:\Windows;C:\Tools" -Entry "c:\tools\") "Entrada não pode duplicar"

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

    $achillesConfig = Write-AchillesConfiguration -HomeDirectory $testRoot `
        -OmniRoutePort 20128
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
        $checksumRejected = $_.Exception.Message -match "Checksum inválido"
    }
    Assert-True $checksumRejected "Checksum adulterado deve ser rejeitado"

    $setupSource = Get-Content (Join-Path $projectDirectory "setup-interativo.ps1") -Raw
    $bootstrapSource = Get-Content (Join-Path $projectDirectory "install.ps1") -Raw
    $envExampleSource = Get-Content (Join-Path $projectDirectory ".env.example") -Raw
    $moduleSource = Get-Content (Join-Path $projectDirectory "scripts\OmniRoute.Setup.psm1") -Raw
    $achillesModuleSource = Get-Content (Join-Path $projectDirectory "scripts\Achilles.Setup.psm1") -Raw
    $composeSource = Get-Content (Join-Path $projectDirectory "docker-compose.yml") -Raw
    Assert-True ($moduleSource -notmatch "taskkill\s+/F\s+/IM\s+node") "Não pode encerrar todos os processos Node"
    Assert-True ($moduleSource -notmatch "Remove-Item.+sqlite") "Reexecução não pode apagar SQLite"
    Assert-True ($setupSource -notmatch "Read-Host.+APPKEY") "APPKEY deve ser automática"
    Assert-True ($setupSource -match "URL.+repositório de skills") "Setup deve solicitar o repositório de skills"
    Assert-True ($setupSource -match 'SkillsRepository é obrigatório no modo não interativo') "Modo automático deve exigir o repositório de skills"
    Assert-True ($setupSource -match 'do \{[\s\S]+Read-Host "URL"[\s\S]+\} while') "Modo assistido deve repetir a pergunta até receber uma URL"
    Assert-True ($setupSource -notmatch 'defaultSkillsRepository') "Setup não deve manter repositório padrão de skills"
    Assert-True ($bootstrapSource -match 'releases/latest') "Bootstrap deve instalar um release estável"
    Assert-True ($bootstrapSource -match '"\.omniroute"') "Bootstrap deve usar o estado persistente do OmniRoute"
    Assert-True ($bootstrapSource -match '\$installDirectory.+Join-Path \$stateDirectory "setup"') "Bootstrap deve persistir os arquivos para reexecução"
    Assert-True ($bootstrapSource -match '\$_.Name -ne "\.env"') "Bootstrap deve preservar o ambiente existente"
    Assert-True ($bootstrapSource -match 'ExecutionPolicy Bypass') "Bootstrap deve funcionar sem alterar a policy do usuário"
    Assert-True ($envExampleSource -match '(?m)^OMNIROUTE_SKILLS_REPO=\s*$') "Exemplo de ambiente não deve sugerir repositório de skills"
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
    Assert-True ($moduleSource -match 'GitHub\.cli') "Setup deve instalar o GitHub CLI quando necessário"
    Assert-True ($moduleSource -match 'gh auth login') "Setup deve orientar o login do GitHub CLI em modo não interativo"
    Assert-True ($moduleSource -match '"auth", "login"') "Setup interativo deve iniciar o login do GitHub CLI"
    Assert-True ($moduleSource -match '"--git-protocol", "https", "--web"') "Login do GitHub CLI deve usar navegador e HTTPS"
    Assert-True ($moduleSource -match 'COMPOSE_CONVERT_WINDOWS_PATHS = "0"') "Compose não deve converter o socket Linux"
    Assert-True ($moduleSource -match 'Remove-UnmanagedPodmanContainer') "Reexecução deve corrigir containers fora do Compose"
    Assert-True ($moduleSource -match '"rm", "--force", \$ContainerName') "Correção deve remover somente o container incompatível"
    Assert-True ($moduleSource -match 'volumes persistentes serão preservados') "Correção deve informar que os volumes são preservados"
    Assert-True ($moduleSource -match 'Set-ConfiguredProvidersOnly') "Setup deve convergir providers configurados"
    Assert-True ($moduleSource -match 'blockedProviders') "Providers no-auth devem ser bloqueados pela configuração oficial"
    Assert-True ($moduleSource -match 'PSObject\.Properties\["blockedProviders"\]') "Ausência inicial de blockedProviders deve ser tratada sem enviar null"
    Assert-True ($moduleSource -notmatch 'Method Delete.+api/providers') "Conexões do usuário nunca devem ser apagadas"
    Assert-True ($moduleSource -match 'Set-TokenEfficiencyDefaults') "Setup deve aplicar otimizações de tokens"
    Assert-True ($moduleSource -match 'Test-AchillesInstallation') "Setup deve validar o Achilles após instalar"
    Assert-True ($moduleSource -match 'Install-Achilles') "Setup deve instalar Achilles nos dois modos"
    Assert-True ($achillesModuleSource -match 'Microsoft\\Windows\\Start Menu\\Programs') "Achilles deve ser localizado pela pesquisa do Windows"
    Assert-True ($achillesModuleSource -match 'achilles\.cmd') "Setup deve criar o comando achilles"
    Assert-True ($achillesModuleSource -notmatch 'ProjectsDirectory') "Launcher não deve impor uma pasta padrão"
    Assert-True ($achillesModuleSource -match 'IsNullOrWhiteSpace\(`\$_\)') "Launcher deve ignorar argumentos vazios do PowerShell 5"
    Assert-True ($achillesModuleSource -match 'launcher-error\.log') "Falhas ocultas do launcher devem deixar diagnóstico"
    Assert-True ($achillesModuleSource -match 'System32\\wscript\.exe') "Atalhos devem abrir sem janela de terminal"
    Assert-True ($achillesModuleSource -match 'GraphicalLauncher') "Instalação deve validar o launcher gráfico"
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
    Assert-True ($moduleSource -match "managedCount.+-eq 0") "Instalação deve falhar quando nenhuma skill for publicada"
    Assert-True ($moduleSource -match 'Remove-LegacyOmniSkills') "Setup deve limpar entradas instrucionais antigas do Omni Skills"
    Assert-True ($moduleSource -match 'compose", "up"[\s\S]+"omniroute"') "Gateway deve iniciar antes do sincronizador que depende da AppKey"
    Assert-True ($composeSource -match '"\$\{PORT:-20128\}:\$\{PORT:-20128\}"') "OmniRoute deve ficar acessível no host"
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $projectDirectory "setup-interativo.ps1"), [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-Equal 0 @($parseErrors).Count "Script principal precisa ter sintaxe válida"

    Write-Host "PASS: todos os testes foram aprovados." -ForegroundColor Green
} finally {
    [Environment]::SetEnvironmentVariable("Path", $originalUserPath, "User")
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
