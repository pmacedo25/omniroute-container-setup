$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectDirectory = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectDirectory "scripts\OmniRoute.Setup.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $projectDirectory "scripts\Achilles.Setup.psm1") -Force -DisableNameChecking
$testRoot = Join-Path $projectDirectory ".test-home"

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

    $combos = Get-Content (Join-Path $projectDirectory "combos-config.json") -Raw | ConvertFrom-Json
    Assert-Equal 3 @($combos.combos).Count "Devem existir três combos"
    Assert-Equal 3 @($combos.combos | Select-Object -ExpandProperty name -Unique).Count "Nomes devem ser únicos"
    foreach ($combo in $combos.combos) {
        Assert-True (@($combo.models).Count -gt 0) "Combo $($combo.name) precisa ter modelos"
        Assert-True ($combo.strategy -in @("priority", "round-robin")) "Estratégia inválida em $($combo.name)"
        Assert-Equal "stacked" $combo.config.compressionMode "Combos devem usar RTK + Caveman"
        Assert-True $combo.context_cache_protection "Combos devem proteger o cache de contexto"
        Assert-Equal 0 $combo.config.maxRetries "Retry do gateway duplicaria chamadas pagas"
    }
    Assert-True (-not (@($combos.combos.models) -join "," -match "gpt-5\.6|claude-opus")) "Combos padrão não devem usar modelos premium"
    Assert-True (Test-Path (Join-Path $projectDirectory "benchmarks\README.md")) "Matriz de benchmark deve estar versionada"

    Write-OpenCodeConfiguration -HomeDirectory $testRoot -Port 20128
    $openCodePath = Join-Path $testRoot ".config\opencode\opencode.json"
    $openCode = Get-Content $openCodePath -Raw | ConvertFrom-Json
    Assert-Equal "omniroute/combo-coding" $openCode.model "Modelo principal OpenCode"
    Assert-Equal "http://localhost:20128/v1" $openCode.provider.omniroute.options.baseURL "Endpoint OpenCode"
    Assert-Equal "{env:OMNIROUTE_API_KEY}" $openCode.provider.omniroute.options.apiKey "APPKEY não deve ser gravada no JSON"
    Assert-Equal 1 @($openCode.enabled_providers).Count "OpenCode deve permitir somente um provedor"
    Assert-Equal "omniroute" $openCode.enabled_providers[0] "OpenCode deve permitir somente OmniRoute"
    Assert-Equal 1 @($openCode.provider.PSObject.Properties).Count "OpenCode não deve configurar outros provedores"

    Assert-Equal "C:\Tools" (Get-PathWithEntry -CurrentPath $null -Entry "C:\Tools") "PATH nulo deve ser suportado"
    Assert-Equal "C:\Windows;C:\Tools" (Get-PathWithEntry -CurrentPath "C:\Windows" -Entry "C:\Tools") "Entrada deve ser adicionada"
    Assert-Equal "C:\Windows;C:\Tools" (Get-PathWithEntry -CurrentPath "C:\Windows;C:\Tools" -Entry "c:\tools\") "Entrada não pode duplicar"

    $achillesConfig = Write-AchillesConfiguration -HomeDirectory $testRoot `
        -ProjectsDirectory "C:\Users\test\workspace" -OmniRoutePort 20128
    $achillesSettings = Get-Content -LiteralPath $achillesConfig -Raw | ConvertFrom-Json
    Assert-Equal "http://127.0.0.1:20128/v1" $achillesSettings.omnirouteBaseUrl "IDE deve usar loopback do host"
    Assert-Equal "http://127.0.0.1:20128/v1/models" $achillesSettings.omnirouteCatalogUrl "IDE deve consultar catálogo dinâmico"
    Assert-Equal "OMNIROUTE_API_KEY" $achillesSettings.apiKeyEnvironmentVariable "Config não deve duplicar segredo"
    Assert-Equal "dynamic" $achillesSettings.modelSelection "Seleção não pode ser hardcoded no instalador"
    Assert-Equal $true $achillesSettings.configuredProvidersOnly "IDE deve listar apenas providers conectados"
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
    $moduleSource = Get-Content (Join-Path $projectDirectory "scripts\OmniRoute.Setup.psm1") -Raw
    $achillesModuleSource = Get-Content (Join-Path $projectDirectory "scripts\Achilles.Setup.psm1") -Raw
    $composeSource = Get-Content (Join-Path $projectDirectory "docker-compose.yml") -Raw
    Assert-True ($moduleSource -notmatch "taskkill\s+/F\s+/IM\s+node") "Não pode encerrar todos os processos Node"
    Assert-True ($moduleSource -notmatch "Remove-Item.+sqlite") "Reexecução não pode apagar SQLite"
    Assert-True ($setupSource -notmatch "Read-Host.+APPKEY") "APPKEY deve ser automática"
    Assert-True ($setupSource -match "URL.+repositório de skills") "Setup deve solicitar o repositório de skills"
    Assert-True ($setupSource -match 'Informe a pasta local onde os projetos serão criados') "Setup deve solicitar a raiz local dos projetos"
    Assert-True ($setupSource -match 'Join-Path \$env:USERPROFILE "workspace"') "Setup deve oferecer a raiz padrão dos projetos"
    Assert-True ($moduleSource -match 'Read-Host "APPKEY do OmniRoute"') "Setup deve aceitar APPKEY manual como fallback"
    Assert-True ($moduleSource -match 'Test-RegisteredAppKey') "APPKEY existente precisa estar registrada no dashboard"
    Assert-True ($moduleSource -match '\{"name":"omniroute-setup","label":"omniroute-setup"\}') "Criação da APPKEY deve suportar os schemas real e documentado"
    Assert-True ($moduleSource -match "OpenHands Desktop\.lnk") "Setup deve criar o atalho Desktop do OpenHands"
    Assert-True ($moduleSource -match 'favicon\.ico') "Atalho deve usar o ícone próprio do OpenHands"
    Assert-True ($moduleSource -match '"--app=`\$url"') "OpenHands deve abrir em modo Web App"
    Assert-True ($moduleSource -notmatch 'user-data-dir') "Launcher não deve gerar argumentos de perfil com aspas frágeis"
    Assert-True ($moduleSource -match 'openhands-desktop\.log') "Falhas do launcher devem deixar diagnóstico"
    Assert-True ($moduleSource -match "use o ícone 'OpenHands Desktop'") "Output deve explicar como abrir o OpenHands"
    Assert-True ($moduleSource -match '/api/v1/settings') "Setup deve persistir settings pela API Web V1"
    Assert-True ($moduleSource -notmatch 'agent_settings\.json') "Setup não deve usar configuração exclusiva do CLI"
    Assert-True ($moduleSource -match '/run/podman/podman\.sock:/var/run/docker\.sock') "Podman deve montar o socket Linux diretamente"
    Assert-True ($moduleSource -match 'SANDBOX_VOLUMES=\$sandboxVolumes') "Sandbox deve montar o workspace local do Windows"
    Assert-True ($moduleSource -match 'OPENHANDS_HOME_DIR') "Estado do OpenHands deve ter diretório próprio"
    Assert-True ($moduleSource -match 'Move-OpenHandsStateToHost') "Estado legado do OpenHands deve ser migrado sem perda"
    Assert-True ($moduleSource -notmatch '"openhands-data:/.openhands"') "OpenHands não deve manter estado apenas em volume interno"
    Assert-True ($moduleSource -match ':/workspace:rw') "Workspace local deve ser gravável pelo agente"
    Assert-True ($moduleSource -notmatch '/home/openhands/\.config/gh:ro') "GitHub CLI não deve bloquear a pasta .config do sandbox"
    Assert-True ($moduleSource -match 'SANDBOX_ENV_GH_TOKEN=\$gitHubToken') "Token do GitHub CLI deve chegar ao sandbox"
    Assert-True ($moduleSource -match 'Remove-DuplicateSetupAppKeys') "Setup deve consolidar suas AppKeys duplicadas"
    Assert-True ($moduleSource -match 'PSObject\.Properties\[\$propertyName\]') "Leitura de AppKeys deve tolerar campos opcionais"
    Assert-True ($moduleSource -match 'Request-OpenHandsPwaInstallation') "Setup deve solicitar a instalação PWA"
    Assert-True ($moduleSource -match 'GitHub\.cli') "Setup deve instalar o GitHub CLI quando necessário"
    Assert-True ($moduleSource -match 'gh auth login') "Setup deve orientar o login do GitHub CLI em modo não interativo"
    Assert-True ($moduleSource -match '"auth", "login"') "Setup interativo deve iniciar o login do GitHub CLI"
    Assert-True ($moduleSource -match '"--git-protocol", "https", "--web"') "Login do GitHub CLI deve usar navegador e HTTPS"
    Assert-True ($moduleSource -match 'COMPOSE_CONVERT_WINDOWS_PATHS = "0"') "Compose não deve converter o socket Linux"
    Assert-True ($moduleSource -match 'Remove-UnmanagedPodmanContainer') "Reexecução deve corrigir containers fora do Compose"
    Assert-True ($moduleSource -match '"rm", "--force", \$ContainerName') "Correção deve remover somente o container incompatível"
    Assert-True ($moduleSource -match 'volumes persistentes serão preservados') "Correção deve informar que os volumes são preservados"
    Assert-True ($moduleSource -match '"pull", "ghcr\.io/openhands/agent-server:\$agentTag"') "Imagem de sandbox deve ser pré-baixada"
    Assert-True ($moduleSource -match 'app-conversations/search\?limit=1') "Setup deve validar a API de conversas"
    Assert-True ($moduleSource -match '/api/providers/\$\(\$connection\.id\)/models') "Combos devem ser filtrados pelos modelos realmente disponíveis"
    Assert-True ($moduleSource -match 'Nenhum provedor de IA ativo') "Setup deve explicar quando não há provedor conectado"
    Assert-True ($moduleSource -match 'num_retries = 1') "OpenHands não deve aguardar vários retries quando o provedor falhar"
    Assert-True ($moduleSource -match 'max_input_tokens = 272000') "OpenHands deve limitar contexto excessivo"
    Assert-True ($moduleSource -match 'max_output_tokens = 16000') "OpenHands deve limitar respostas excessivas"
    Assert-True ($moduleSource -match 'Set-TokenEfficiencyDefaults') "Setup deve aplicar otimizações de tokens"
    Assert-True ($moduleSource -match 'Test-AchillesInstallation') "Setup deve validar o Achilles após instalar"
    Assert-True ($moduleSource -match 'Install-Achilles') "Setup deve instalar Achilles nos dois modos"
    Assert-True ($setupSource -match 'AchillesArtifactPath') "Setup deve aceitar artefato local para validação"
    Assert-True ($setupSource -match 'Alias\("OpenRouterAIArtifactPath"\)') "Automação anterior deve continuar aceita durante a migração"
    Assert-True ($achillesModuleSource -match '\$installedExecutables = @\(if') "Reexecução com um executável deve preservar sem erro de Count"
    Assert-True ($achillesModuleSource -match 'Copy-AchillesLegacyState') "Instalador deve migrar o estado legado"
    Assert-True ($achillesModuleSource -match 'legacyStatePreserved = \$true') "Migração deve documentar rollback"
    Assert-True ($achillesModuleSource -match '\^Achilles-win-x64-') "Release deve selecionar somente artefatos Achilles"
    Assert-True ($achillesModuleSource -match 'pmacedo25/Achilles-Releases') "Instalador deve usar o repositório público de binários"
    Assert-True ($achillesModuleSource -match 'api\.github\.com/repos/\$Repository/releases') "Release público deve ser consultado sem GitHub CLI"
    Assert-True ($achillesModuleSource -notmatch 'GitHub CLI é necessário para baixar') "Download público do Achilles não deve exigir autenticação"
    Assert-True ($achillesModuleSource -match 'não contém um build Achilles para Windows x64') "Release legado deve produzir erro acionável"
    Assert-True ($achillesModuleSource -match 'AchillesArtifactPath') "Erro de release deve indicar o fluxo com artefato local"
    Assert-True ($achillesModuleSource -notmatch 'allowedCombos') "Instalador não deve manter lista hardcoded de modelos"
    $omniSource = Get-Content (Join-Path $projectDirectory "scripts\omni.ps1") -Raw
    Assert-True ($omniSource -match '"ide"') "Comando omni deve abrir a IDE"
    Assert-True ($omniSource -match '\.achilles\\current\.json') "Doctor deve diagnosticar a IDE"
    Assert-True ($moduleSource -match 'defaultMode = "stacked"') "RTK e Caveman devem vir habilitados em pipeline"
    Assert-True ($moduleSource -match 'session-dedup.+enabled = \$true') "Deduplicação de sessão deve vir habilitada"
    Assert-True ($moduleSource -match 'A alteração vale para novas conversas') "Setup deve explicar como trocar de combo"
    Assert-True ($moduleSource -match '"--publish", "\$\{openHandsPort\}:3000"') "OpenHands deve aceitar callbacks dos contêineres de agente"
    Assert-True ($composeSource -match '"\$\{PORT:-20128\}:\$\{PORT:-20128\}"') "OmniRoute deve aceitar chamadas dos contêineres de agente"
    Assert-True ($composeSource -match '"\$\{OPENHANDS_PORT:-3000\}:3000"') "Compose deve aceitar callbacks dos contêineres de agente"
    Assert-Equal "/mnt/c/Users/test/workspace" (ConvertTo-PodmanMachinePath "C:\Users\test\workspace") "Workspace deve ser visível na VM Podman"

    $catalogSource = Get-Content (Join-Path $projectDirectory "openhands\omniroute_model_service.py") -Raw
    Assert-Equal 3 ([regex]::Matches($catalogSource, 'LLMModel\(provider="omniroute"').Count) "Catálogo deve conter três combos"
    Assert-True ($catalogSource -notmatch 'anthropic|gemini|bedrock') "Catálogo não deve expor outros provedores"

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $projectDirectory "setup-interativo.ps1"), [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-Equal 0 @($parseErrors).Count "Script principal precisa ter sintaxe válida"

    Write-Host "PASS: todos os testes foram aprovados." -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
