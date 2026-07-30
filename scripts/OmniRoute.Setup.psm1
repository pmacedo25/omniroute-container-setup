Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot "Achilles.Setup.psm1") -Force -DisableNameChecking

function Add-KnownToolPaths {
    $paths = @(
        "$env:LOCALAPPDATA\Programs\Podman",
        "$env:ProgramFiles\RedHat\Podman",
        "$env:ProgramFiles\GitHub CLI",
        "$env:APPDATA\Python\Python314\Scripts",
        "$env:APPDATA\Python\Python313\Scripts",
        "$env:APPDATA\Python\Python312\Scripts"
    )
    foreach ($path in $paths) {
        if ((Test-Path -LiteralPath $path) -and
            @($env:PATH -split ";" | Where-Object { $_ -ieq $path }).Count -eq 0) {
            $env:PATH = "$path;$env:PATH"
        }
    }
}

Add-KnownToolPaths

function Write-SetupMessage {
    param([string]$Message, [ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level = "INFO")
    $color = @{ INFO = "Cyan"; OK = "Green"; WARN = "Yellow"; ERROR = "Red" }[$Level]
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Set-EnvValue {
    param([string]$Path, [string]$Name, [AllowEmptyString()][string]$Value)
    $lines = if (Test-Path -LiteralPath $Path) { @(Get-Content -LiteralPath $Path) } else { @() }
    $replacement = "$Name=$Value"
    $found = $false
    $updated = foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Name))=") {
            if (-not $found) { $replacement }
            $found = $true
        } else {
            $line
        }
    }
    if (-not $found) { $updated = @($updated) + $replacement }
    Set-Content -LiteralPath $Path -Value $updated -Encoding utf8
}

function Remove-EnvValue {
    param([string]$Path, [string[]]$Names)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $namePattern = ($Names | ForEach-Object { [regex]::Escape($_) }) -join "|"
    $updated = @(Get-Content -LiteralPath $Path | Where-Object {
        $_ -notmatch "^\s*(?:$namePattern)="
    })
    Set-Content -LiteralPath $Path -Value $updated -Encoding utf8
}

function Get-EnvValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))=" } | Select-Object -Last 1
    if ($null -eq $line) { return $null }
    return ($line -split "=", 2)[1]
}

function Invoke-External {
    param([string]$Command, [string[]]$Arguments, [string]$FailureMessage)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$FailureMessage (código $LASTEXITCODE)." }
}

function Install-WingetPackage {
    param([string]$Id, [string]$DisplayName)
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "$DisplayName não foi encontrado e o winget não está disponível."
    }
    Write-SetupMessage "Instalando $DisplayName..."
    Invoke-External "winget" @("install", "--exact", "--id", $Id, "--silent", "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity") "Falha ao instalar $DisplayName"
}

function Get-ContainerEngine {
    foreach ($candidate in @("podman", "docker")) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            & $candidate info *> $null
            if ($LASTEXITCODE -eq 0) { return $candidate }
        }
    }
    return $null
}

function Ensure-ContainerEngine {
    $engine = Get-ContainerEngine
    if ($engine) { return $engine }

    Install-WingetPackage -Id "RedHat.Podman" -DisplayName "Podman"
    $candidatePaths = @(
        "$env:ProgramFiles\RedHat\Podman",
        "$env:LOCALAPPDATA\Programs\Podman"
    )
    foreach ($candidatePath in $candidatePaths) {
        if ((Test-Path -LiteralPath $candidatePath) -and ($env:PATH -notlike "*$candidatePath*")) {
            $env:PATH = "$candidatePath;$env:PATH"
        }
    }

    if (Get-Command podman -ErrorAction SilentlyContinue) {
        & podman machine inspect *> $null
        if ($LASTEXITCODE -ne 0) { Invoke-External "podman" @("machine", "init", "--now") "Falha ao criar a máquina Podman" }
        else { & podman machine start *> $null }
    }

    $engine = Get-ContainerEngine
    if (-not $engine) { throw "Podman foi instalado, mas o motor ainda não está disponível. Reinicie o Windows e reexecute o instalador." }
    if ($engine -eq "podman" -and -not (Get-Command podman-compose -ErrorAction SilentlyContinue)) {
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
            Install-WingetPackage -Id "Python.Python.3.12" -DisplayName "Python 3.12"
            Add-KnownToolPaths
        }
        Invoke-External "python" @("-m", "pip", "install", "--user", "podman-compose") "Falha ao instalar podman-compose"
        Add-KnownToolPaths
    }
    return $engine
}

function Ensure-LocalDependencies {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Install-WingetPackage -Id "Git.Git" -DisplayName "Git"
    }
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    $nodeMajor = if ($nodeCommand) { [int]((& node --version).TrimStart("v").Split(".")[0]) } else { 0 }
    if ($nodeMajor -notin @(22, 24, 25, 26)) {
        Install-WingetPackage -Id "OpenJS.NodeJS.LTS" -DisplayName "Node.js LTS"
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "npm não foi encontrado após a instalação do Node.js. Reabra o terminal e reexecute."
    }
}

function Ensure-GitHubCliAuthentication {
    param([bool]$NonInteractive)
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Install-WingetPackage -Id "GitHub.cli" -DisplayName "GitHub CLI"
        Add-KnownToolPaths
    }
    $gitHubCli = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gitHubCli) {
        throw "GitHub CLI foi instalado, mas ainda não está disponível. Reabra o terminal e reexecute o instalador."
    }

    & $gitHubCli.Source auth status --hostname github.com *> $null
    if ($LASTEXITCODE -ne 0) {
        if ($NonInteractive) {
            Write-SetupMessage "GitHub CLI não está autenticado. Execute 'gh auth login --hostname github.com --git-protocol https --web' e reexecute." "WARN"
            return $null
        }
        Write-SetupMessage "O GitHub CLI precisa de autorização para acessar skills, sandboxes e releases privados."
        Write-Host "O navegador será aberto pelo GitHub CLI. Conclua o login e autorize os repositórios necessários."
        Invoke-External $gitHubCli.Source @(
            "auth", "login", "--hostname", "github.com",
            "--git-protocol", "https", "--web"
        ) "Falha ao autenticar o GitHub CLI"
    }

    $token = (& $gitHubCli.Source auth token --hostname github.com 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "GitHub CLI está conectado, mas não forneceu um token para o sandbox."
    }
    Write-SetupMessage "GitHub CLI autenticado para os recursos privados necessários." "OK"
    return ([string]$token).Trim()
}

function Install-NativeBuildTools {
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Install-WingetPackage -Id "Python.Python.3.12" -DisplayName "Python 3.12"
    }
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "Microsoft C++ Build Tools é necessário, mas winget não está disponível."
        }
        Write-SetupMessage "Instalando Microsoft C++ Build Tools após falha de módulo nativo..."
        Invoke-External "winget" @(
            "install", "--exact", "--id", "Microsoft.VisualStudio.2022.BuildTools",
            "--silent", "--accept-package-agreements", "--accept-source-agreements",
            "--override", "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
        ) "Falha ao instalar Microsoft C++ Build Tools"
    }
}

function Sync-SkillsRepository {
    param([string]$Repository, [string]$Branch, [string]$Destination)
    if (Test-Path -LiteralPath (Join-Path $Destination ".git")) {
        Invoke-External "git" @("-C", $Destination, "remote", "set-url", "origin", $Repository) "Falha ao atualizar a origem das skills"
        Invoke-External "git" @("-C", $Destination, "fetch", "--depth", "1", "origin", $Branch) "Falha ao baixar as skills"
        Invoke-External "git" @("-C", $Destination, "reset", "--hard", "origin/$Branch") "Falha ao atualizar as skills"
        return
    }
    if ((Test-Path -LiteralPath $Destination) -and @(Get-ChildItem -LiteralPath $Destination -Force).Count -gt 0) {
        throw "O diretório de skills '$Destination' não é um repositório Git. Ele foi preservado; mova-o ou escolha outro destino."
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Invoke-External "git" @("clone", "--depth", "1", "--branch", $Branch, $Repository, $Destination) "Falha ao clonar as skills"
}

function Wait-HttpReady {
    param([string]$Url, [int]$TimeoutSeconds = 120)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -lt 500) { return }
        } catch {
            Start-Sleep -Seconds 2
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "O serviço não ficou disponível em '$Url' após $TimeoutSeconds segundos."
}

function Test-AppKey {
    param([string]$BaseUrl, [string]$AppKey)
    if ([string]::IsNullOrWhiteSpace($AppKey)) { return $false }
    try {
        Invoke-RestMethod -Uri "$BaseUrl/api/keys" -Headers @{ Authorization = "Bearer $AppKey" } -TimeoutSec 10 | Out-Null
        return $true
    } catch { return $false }
}

function Test-AppKeyMetadataSuffix {
    param($Metadata, [string]$Suffix)
    foreach ($propertyName in @("keyPreview", "key")) {
        $property = $Metadata.PSObject.Properties[$propertyName]
        if ($null -ne $property -and [string]$property.Value -like "*$Suffix") {
            return $true
        }
    }
    return $false
}

function Test-RegisteredAppKey {
    param([string]$BaseUrl, [string]$AppKey)
    if (-not (Test-AppKey -BaseUrl $BaseUrl -AppKey $AppKey)) { return $false }
    try {
        $response = Invoke-RestMethod -Uri "$BaseUrl/api/keys" `
            -Headers @{ Authorization = "Bearer $AppKey" } -TimeoutSec 10
        $suffix = if ($AppKey.Length -gt 4) { $AppKey.Substring($AppKey.Length - 4) } else { $AppKey }
        return @($response.keys | Where-Object {
            $_.isActive -and (Test-AppKeyMetadataSuffix -Metadata $_ -Suffix $suffix)
        }).Count -gt 0
    } catch { return $false }
}

function Remove-DuplicateSetupAppKeys {
    param([string]$BaseUrl, [string]$AppKey)
    $headers = @{ Authorization = "Bearer $AppKey" }
    $response = Invoke-RestMethod -Uri "$BaseUrl/api/keys" -Headers $headers -TimeoutSec 10
    $suffix = if ($AppKey.Length -gt 4) { $AppKey.Substring($AppKey.Length - 4) } else { $AppKey }
    $setupKeys = @($response.keys | Where-Object {
        ($_.PSObject.Properties["name"]  -and $_.name  -eq "omniroute-setup") -or
        ($_.PSObject.Properties["label"] -and $_.label -eq "omniroute-setup")
    })
    $current = @($setupKeys | Where-Object {
        Test-AppKeyMetadataSuffix -Metadata $_ -Suffix $suffix
    } | Select-Object -First 1)
    if ($current.Count -eq 0) { return }

    foreach ($duplicate in @($setupKeys | Where-Object { $_.id -ne $current[0].id })) {
        Invoke-RestMethod -Uri "$BaseUrl/api/keys/$($duplicate.id)" -Method Delete `
            -Headers $headers -TimeoutSec 10 | Out-Null
    }
    if ($setupKeys.Count -gt 1) {
        Write-SetupMessage "AppKeys duplicadas do instalador foram removidas; uma chave ativa foi preservada." "OK"
    }
}

function New-ContainerSetupAppKey {
    param([string]$Engine)

    # Management endpoints cannot be bootstrapped with an inference AppKey.
    # OmniRoute's supported local CLI channel derives a machine-bound token and
    # accepts it only over loopback. Execute the request inside the container so
    # the bootstrap secret never crosses the container boundary or reaches logs.
    $script = @'
import crypto from "node:crypto";
const machineIdModule = await import("node-machine-id");
const machineIdSync =
  machineIdModule.machineIdSync || machineIdModule.default?.machineIdSync;
if (typeof machineIdSync !== "function") {
  throw new Error("node-machine-id não expõe machineIdSync nesta imagem");
}
const cliToken = crypto
  .createHmac("sha256", machineIdSync(true))
  .update(process.env.OMNIROUTE_CLI_SALT || "omniroute-cli-auth-v1")
  .digest("hex");
const baseUrl = "http://127.0.0.1:" + (process.env.PORT || "20128");
const createBody = JSON.stringify({
    name: "omniroute-setup",
    label: "omniroute-setup",
    scopes: ["manage"]
});
const createKey = () => fetch(baseUrl + "/api/keys", {
  method: "POST",
  headers: {
    "x-omniroute-cli-token": cliToken,
    "x-omniroute-peer-locality": "loopback",
    "content-type": "application/json"
  },
  body: createBody
});

let response = await createKey();
let onboardingWindow = false;
if (response.status === 401) {
  // The 3.8.48 standalone image can package node-machine-id in a shape that
  // makes its bundled CLI token helper return an empty token. The public
  // onboarding endpoint is allowed only while setupComplete=false.
  const statusResponse = await fetch(baseUrl + "/api/settings/require-login");
  const status = await statusResponse.json();
  if (status.setupComplete || status.hasPassword) {
    throw new Error("management auth is required on an initialized instance");
  }
  const openResponse = await fetch(baseUrl + "/api/settings/require-login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ requireLogin: false })
  });
  if (!openResponse.ok) {
    throw new Error("could not open the local onboarding bootstrap window");
  }
  onboardingWindow = true;
  response = await createKey();
}

const body = await response.text();
if (!response.ok) {
  if (onboardingWindow) {
    await fetch(baseUrl + "/api/settings/require-login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ requireLogin: true })
    });
  }
  throw new Error("HTTP " + response.status + ": " + body);
}
if (onboardingWindow) {
  const created = JSON.parse(body);
  if (!created.id) {
    throw new Error("AppKey criada sem ID; não é possível aplicar o escopo manage");
  }
  const scopeResponse = await fetch(baseUrl + "/api/keys/" + encodeURIComponent(created.id), {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ scopes: ["manage"] })
  });
  if (!scopeResponse.ok) {
    throw new Error("AppKey criada, mas não foi possível aplicar o escopo manage");
  }
  const closeResponse = await fetch(baseUrl + "/api/settings/require-login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ requireLogin: true })
  });
  if (!closeResponse.ok) {
    throw new Error("AppKey criada, mas a proteção de login não foi restaurada");
  }
}
process.stdout.write(body);
'@
    $output = & $Engine @(
        "exec", "--user", "node", "omniroute", "node", "--input-type=module", "--eval", $script
    ) 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Falha no bootstrap local da AppKey: $($output -join [Environment]::NewLine)"
    }
    try {
        $created = ($output -join [Environment]::NewLine) | ConvertFrom-Json
    } catch {
        throw "O bootstrap local da AppKey retornou uma resposta inválida."
    }
    if ([string]::IsNullOrWhiteSpace([string]$created.key)) {
        throw "O bootstrap local da AppKey não retornou o campo 'key'."
    }
    return [string]$created.key
}

function Save-SharedAppKey {
    param([string]$EnvPath, [string]$AppKey)
    # A mesma AppKey identifica tanto as chamadas administrativas quanto as
    # inferências. O OmniRoute atribui usage_history e custo pelo ID da chave,
    # independentemente de ela também possuir o escopo `manage`.
    Set-EnvValue -Path $EnvPath -Name "OMNIROUTE_API_KEY" -Value $AppKey
    Remove-EnvValue -Path $EnvPath -Names @("OMNIROUTE_MANAGEMENT_API_KEY")
    [Environment]::SetEnvironmentVariable("OMNIROUTE_API_KEY", $AppKey, "User")
    $env:OMNIROUTE_API_KEY = $AppKey
}

function Ensure-AppKey {
    param(
        [string]$BaseUrl,
        [string]$EnvPath,
        [bool]$NonInteractive,
        [AllowEmptyString()][string]$ContainerEngine
    )
    $existing = Get-EnvValue -Path $EnvPath -Name "OMNIROUTE_API_KEY"
    if ([string]::IsNullOrWhiteSpace($existing)) {
        # Migração da instalação que separava desnecessariamente a chave de
        # gestão da chave de inferência.
        $existing = Get-EnvValue -Path $EnvPath -Name "OMNIROUTE_MANAGEMENT_API_KEY"
    }
    if (Test-RegisteredAppKey -BaseUrl $BaseUrl -AppKey $existing) {
        Save-SharedAppKey -EnvPath $EnvPath -AppKey $existing
        Remove-DuplicateSetupAppKeys -BaseUrl $BaseUrl -AppKey $existing
        return $existing
    }

    try {
        if (-not [string]::IsNullOrWhiteSpace($ContainerEngine)) {
            $appKey = New-ContainerSetupAppKey -Engine $ContainerEngine
        } else {
            $headers = @{}
            if (Test-AppKey -BaseUrl $BaseUrl -AppKey $existing) {
                $headers.Authorization = "Bearer $existing"
            }
            # OmniRoute 3.8.48 validates `name`, while its bundled OpenAPI declares
            # `label`. Sending both keeps the installer compatible with both shapes.
            $created = Invoke-RestMethod -Uri "$BaseUrl/api/keys" -Method Post `
                -Headers $headers -ContentType "application/json" `
                -Body '{"name":"omniroute-setup","label":"omniroute-setup","scopes":["manage"]}' -TimeoutSec 20
            if ([string]::IsNullOrWhiteSpace([string]$created.key)) {
                throw "A API não retornou o campo 'key'."
            }
            $appKey = [string]$created.key
        }
    } catch {
        Write-SetupMessage "Não foi possível criar a APPKEY automaticamente: $($_.Exception.Message)" "WARN"
        if ($NonInteractive) {
            throw "Informe OMNIROUTE_API_KEY no arquivo '$EnvPath' e reexecute, ou execute sem -NonInteractive."
        }

        Write-Host ""
        Write-Host "Crie uma chave em $BaseUrl/dashboard/api-manager e informe-a abaixo."
        Start-Process "$BaseUrl/dashboard/api-manager"
        do {
            $secureKey = Read-Host "APPKEY do OmniRoute" -AsSecureString
            $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
            try {
                $appKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)
            } finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
            }
            if ([string]::IsNullOrWhiteSpace($appKey)) {
                Write-SetupMessage "A APPKEY não pode ficar vazia." "WARN"
                continue
            }
            if (-not (Test-AppKey -BaseUrl $BaseUrl -AppKey $appKey)) {
                Write-SetupMessage "A APPKEY não foi aceita pelo endpoint /v1/models. Confira a chave e tente novamente." "WARN"
                $appKey = $null
            }
        } while ([string]::IsNullOrWhiteSpace($appKey))
    }

    Save-SharedAppKey -EnvPath $EnvPath -AppKey $appKey
    Remove-DuplicateSetupAppKeys -BaseUrl $BaseUrl -AppKey $appKey
    return $appKey
}

function Set-ConfiguredCombos {
    param([string]$BaseUrl, [string]$ConfigPath, [string]$AppKey)
    $headers = @{ Authorization = "Bearer $AppKey" }
    $configuration = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    $existingResponse = Invoke-RestMethod -Uri "$BaseUrl/api/combos" -Headers $headers -TimeoutSec 20
    $existingByName = @{}
    foreach ($item in @($existingResponse.combos)) { $existingByName[$item.name] = $item }

    if ($configuration.PSObject.Properties["enabled"] -and -not $configuration.enabled) {
        if ($configuration.deleteManagedWhenDisabled) {
            foreach ($name in @($configuration.managedNames)) {
                if ($existingByName.ContainsKey($name)) {
                    Invoke-RestMethod -Uri "$BaseUrl/api/combos/$($existingByName[$name].id)" `
                        -Method Delete -Headers $headers -TimeoutSec 20 | Out-Null
                }
            }
        }
        Write-SetupMessage "Combos automáticos desativados; combos do usuário foram preservados." "OK"
        return
    }

    foreach ($combo in $configuration.combos) {
        if ([string]::IsNullOrWhiteSpace([string]$combo.name) -or @($combo.models).Count -eq 0) {
            throw "Todo combo declarado precisa de nome e ao menos um modelo."
        }
        if ([string]$combo.strategy -eq "auto") {
            throw "A estratégia 'auto' não é permitida nos combos declarativos."
        }
        $body = $combo | ConvertTo-Json -Depth 20
        if ($existingByName.ContainsKey($combo.name)) {
            Invoke-RestMethod -Uri "$BaseUrl/api/combos/$($existingByName[$combo.name].id)" -Method Put -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 20 | Out-Null
        } else {
            Invoke-RestMethod -Uri "$BaseUrl/api/combos" -Method Post -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 20 | Out-Null
        }
    }
}

function Set-ConfiguredProvidersOnly {
    param([string]$BaseUrl, [string]$AppKey)
    $headers = @{ Authorization = "Bearer $AppKey" }
    $noAuthProviderIds = @(
        "opencode", "duckduckgo-web", "felo-web", "theoldllm", "chipotle",
        "veoaifree-web", "mimocode", "auggie", "aihorde"
    )
    $providerResponse = Invoke-RestMethod -Uri "$BaseUrl/api/providers" -Headers $headers -TimeoutSec 20
    $connections = if ($providerResponse.PSObject.Properties["connections"]) {
        @($providerResponse.connections)
    } elseif ($providerResponse.PSObject.Properties["providers"]) {
        @($providerResponse.providers)
    } else {
        @($providerResponse)
    }
    $userProviderIds = @($connections | ForEach-Object {
        if ($_.PSObject.Properties["provider"]) { [string]$_.provider }
        elseif ($_.PSObject.Properties["providerId"]) { [string]$_.providerId }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    $current = Invoke-RestMethod -Uri "$BaseUrl/api/settings" -Headers $headers `
        -TimeoutSec 20 -ErrorAction Stop
    $currentBlocked = if ($current.PSObject.Properties["blockedProviders"]) {
        @($current.blockedProviders | Where-Object {
            $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_)
        })
    } else {
        @()
    }
    $blocked = @(
        $currentBlocked +
        @($noAuthProviderIds | Where-Object { $_ -notin $userProviderIds })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    $body = @{ blockedProviders = @($blocked) } | ConvertTo-Json -Depth 5
    $saved = Invoke-RestMethod -Uri "$BaseUrl/api/settings" -Method Patch `
        -Headers $headers -ContentType "application/json" -Body $body `
        -TimeoutSec 20 -ErrorAction Stop
    if (-not $saved.PSObject.Properties["blockedProviders"]) {
        throw "O OmniRoute aceitou a configuração, mas não retornou blockedProviders para validação."
    }
    $missing = @($noAuthProviderIds | Where-Object {
        $_ -notin $userProviderIds -and $_ -notin @($saved.blockedProviders)
    })
    if ($missing.Count -gt 0) {
        throw "O OmniRoute não confirmou o bloqueio dos providers padrão: $($missing -join ', ')."
    }
    Write-SetupMessage "Providers sem autenticação foram bloqueados; $($userProviderIds.Count) conexão(ões) do usuário preservada(s)." "OK"
}

function Set-TokenEfficiencyDefaults {
    param([string]$BaseUrl, [string]$AppKey)
    $headers = @{ Authorization = "Bearer $AppKey" }
    $settings = [ordered]@{
        enabled = $true
        defaultMode = "rtk"
        autoTriggerMode = "off"
        autoTriggerTokens = 0
        cacheMinutes = 60
        preserveSystemPrompt = $true
        preserveSystemPromptMode = "always"
        mcpDescriptionCompressionEnabled = $true
        stackedPipeline = @()
        engines = [ordered]@{
            "session-dedup" = @{ enabled = $false }
            ccr = @{ enabled = $false }
            lite = @{ enabled = $false }
            rtk = @{ enabled = $true; level = "standard" }
            headroom = @{ enabled = $false }
            relevance = @{ enabled = $false }
            caveman = @{ enabled = $false; level = "full" }
            aggressive = @{ enabled = $false }
            llmlingua = @{ enabled = $false }
            ultra = @{ enabled = $false }
            omniglyph = @{ enabled = $false }
        }
        cavemanConfig = @{
            enabled = $false
            compressRoles = @()
            skipRules = @()
            minMessageLength = 50
            preservePatterns = @()
            intensity = "full"
        }
        cavemanOutputMode = @{
            enabled = $false
            intensity = "lite"
            autoClarity = $true
        }
        rtkConfig = @{
            enabled = $true
            intensity = "standard"
            applyToToolResults = $true
            applyToCodeBlocks = $false
            applyToAssistantMessages = $false
            enabledFilters = @()
            disabledFilters = @()
            maxLinesPerResult = 80
            maxCharsPerResult = 8000
            deduplicateThreshold = 3
            customFiltersEnabled = $true
            trustProjectFilters = $false
            rawOutputRetention = "never"
            rawOutputMaxBytes = 1048576
            enableGrouping = $true
            groupingThreshold = 3
            stripCodeComments = $false
            preserveDocstrings = $true
            enableRenderers = $true
        }
        languageConfig = @{
            enabled = $true
            defaultLanguage = "pt-BR"
            autoDetect = $true
            enabledPacks = @("en", "pt-BR")
        }
        contextEditing = @{ enabled = $false }
    }
    Invoke-RestMethod -Uri "$BaseUrl/api/settings/compression" -Method Put `
        -Headers $headers -ContentType "application/json" `
        -Body ($settings | ConvertTo-Json -Depth 20) -TimeoutSec 20 | Out-Null
    $saved = Invoke-RestMethod -Uri "$BaseUrl/api/settings/compression" `
        -Headers $headers -TimeoutSec 20
    if (-not $saved.enabled -or $saved.defaultMode -ne "rtk" -or
        -not $saved.rtkConfig.enabled -or $saved.cavemanConfig.enabled -or
        $saved.engines."session-dedup".enabled -or $saved.engines.ccr.enabled -or
        $saved.engines.headroom.enabled) {
        throw "O OmniRoute não confirmou os padrões de economia de tokens."
    }
}

function Get-PathWithEntry {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CurrentPath,
        [string]$Entry
    )
    $pathEntries = @($CurrentPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $alreadyPresent = @($pathEntries | Where-Object { $_.TrimEnd("\") -ieq $Entry.TrimEnd("\") }).Count -gt 0
    if ($alreadyPresent) { return ($pathEntries -join ";") }
    return (@($pathEntries) + $Entry -join ";")
}

function Install-OmniCommand {
    param([string]$SetupDirectory, [string]$HomeDirectory)
    $binDirectory = Join-Path $HomeDirectory ".omniroute\bin"
    New-Item -ItemType Directory -Path $binDirectory -Force | Out-Null
    $source = Join-Path $SetupDirectory "scripts\omni.ps1"
    Copy-Item -LiteralPath $source -Destination (Join-Path $binDirectory "omni.ps1") -Force
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $updatedUserPath = Get-PathWithEntry -CurrentPath $userPath -Entry $binDirectory
    if ($updatedUserPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable("Path", $updatedUserPath, "User")
    }
    if (@($env:PATH -split ";" | Where-Object { $_.TrimEnd("\") -ieq $binDirectory.TrimEnd("\") }).Count -eq 0) {
        $env:PATH = Get-PathWithEntry -CurrentPath $env:PATH -Entry $binDirectory
    }
}

function Invoke-CorporateCAInjection {
    param(
        [string]$SetupDirectory,
        [AllowEmptyString()][string]$CorporateCAPath
    )

    $caDestination = Join-Path $SetupDirectory "skills-sync\netskope-ca.pem"
    $overridePath  = Join-Path $SetupDirectory "docker-compose.override.yml"
    $certificateCount = 0
    $sourceDescription = ""

    # This setup is intentionally tied to the corporate Netskope chain.
    # Do not collect unrelated enterprise or public CAs from the host.
    $inspectionPatterns = @("*Netskope*", "*goskope*")

    if (-not [string]::IsNullOrWhiteSpace($CorporateCAPath)) {
        if (-not (Test-Path -LiteralPath $CorporateCAPath -PathType Leaf)) {
            throw "O CA corporativo informado não existe: '$CorporateCAPath'."
        }
        $pem = Get-Content -LiteralPath $CorporateCAPath -Raw
        if ($pem -notmatch "-----BEGIN CERTIFICATE-----") {
            throw "O CA corporativo informado precisa estar no formato PEM."
        }
        [System.IO.File]::WriteAllText($caDestination, $pem)
        $certificateCount = ([regex]::Matches($pem, "-----BEGIN CERTIFICATE-----")).Count
        $sourceDescription = "arquivo explícito"
    } else {
        $seen  = @{}
        $certs = @()
        foreach ($storeLocation in @("LocalMachine", "CurrentUser")) {
            foreach ($storeName in @("Root", "CA")) {
                $store = "Cert:\$storeLocation\$storeName"
                foreach ($pattern in $inspectionPatterns) {
                    Get-ChildItem $store -ErrorAction SilentlyContinue |
                        Where-Object {
                            $_.NotBefore -le (Get-Date) -and $_.NotAfter -gt (Get-Date) -and
                            ($_.Subject -like $pattern -or $_.Issuer -like $pattern)
                        } |
                        ForEach-Object {
                            if (-not $seen.ContainsKey($_.Thumbprint)) {
                                $seen[$_.Thumbprint] = $true
                                $certs += $_
                            }
                        }
                }
            }
        }
        if ($certs.Count -gt 0) {
            # Preserve Windows store discovery order. Sorting by thumbprint breaks
            # the original corporate chain order on machines with intermediates.
            $pem = ($certs | ForEach-Object {
                "-----BEGIN CERTIFICATE-----`n" +
                [Convert]::ToBase64String($_.RawData, [Base64FormattingOptions]::InsertLineBreaks) +
                "`n-----END CERTIFICATE-----"
            }) -join "`n"
            [System.IO.File]::WriteAllText($caDestination, $pem)
            $certificateCount = $certs.Count
            $sourceDescription = "cadeia Netskope do repositório de certificados do Windows"
        }
    }

    if ($certificateCount -gt 0) {
        # docker-compose resolves relative bind-mount paths inconsistently on Windows/Podman.
        # Write an override with the absolute path so the CA reaches the Node.js runtime.
        $absPath = (Resolve-Path $caDestination).Path.Replace('\', '/')
        $overrideContent = @"
services:
  omniroute:
    environment:
      NODE_EXTRA_CA_CERTS: /certs/corporate-ca.pem
    volumes:
      - ${absPath}:/certs/corporate-ca.pem:ro
"@
        [System.IO.File]::WriteAllText($overridePath, $overrideContent)
        Write-SetupMessage "CA corporativo carregado de $sourceDescription ($certificateCount certificado(s)); injetado somente no container." "OK"
    } else {
        # Empty file keeps the Dockerfile COPY valid on environments without SSL inspection
        [System.IO.File]::WriteAllText($caDestination, "")
        if (Test-Path $overridePath) { Remove-Item $overridePath -Force }
        Write-SetupMessage "Nenhuma cadeia Netskope/goskope detectada; build padrão." "INFO"
    }
}

function Remove-UnmanagedPodmanContainer {
    param([string]$ContainerName, [string]$ExpectedComposeProject)
    & podman container exists $ContainerName
    if ($LASTEXITCODE -ne 0) { return }

    # Use JSON output to avoid Go template quoting issues on Windows
    $inspectJson = & podman inspect $ContainerName --format json 2>$null
    $composeProject = $null
    if ($LASTEXITCODE -eq 0 -and $inspectJson) {
        $data   = $inspectJson | ConvertFrom-Json
        $labels = if ($data -is [array]) { $data[0].Config.Labels } else { $data.Config.Labels }
        if ($null -ne $labels -and $labels.PSObject.Properties["com.docker.compose.project"]) {
            $composeProject = $labels."com.docker.compose.project"
        }
    }
    if ([string]$composeProject -eq $ExpectedComposeProject) { return }

    Write-SetupMessage "Substituindo o container '$ContainerName' sem metadados do Compose; os volumes persistentes serão preservados." "WARN"
    Invoke-External "podman" @("rm", "--force", $ContainerName) `
        "Falha ao substituir o container incompatível '$ContainerName'"
}

function Start-ContainerMode {
    param([string]$Engine, [string]$SetupDirectory)
    Push-Location $SetupDirectory
    $previousPathConversion = $env:COMPOSE_CONVERT_WINDOWS_PATHS
    try {
        if ($Engine -eq "podman") {
            # podman-compose on Windows must pass Linux VM socket paths verbatim.
            $env:COMPOSE_CONVERT_WINDOWS_PATHS = "0"
            # A run interrupted or an older installer may leave the fixed-name
            # gateway outside Compose. Remove only that disposable container;
            # its named database and skills volumes remain untouched.
            Remove-UnmanagedPodmanContainer -ContainerName "omniroute" `
                -ExpectedComposeProject "omniroute-setup"
        }
        # The synchronizer needs the AppKey created after the gateway starts.
        # Start only the gateway here; the mandatory first sync runs later.
        $arguments = @("compose", "up", "-d", "--pull", "missing", "omniroute")
        Invoke-External $Engine $arguments "Falha ao iniciar os contêineres"
    } finally {
        $env:COMPOSE_CONVERT_WINDOWS_PATHS = $previousPathConversion
        Pop-Location
    }
}

function Start-ValidatedSkillsSync {
    param(
        [string]$Engine,
        [string]$SetupDirectory,
        [string]$SkillsDirectory
    )
    Push-Location $SetupDirectory
    $previousPathConversion = $env:COMPOSE_CONVERT_WINDOWS_PATHS
    try {
        if ($Engine -eq "podman") {
            $env:COMPOSE_CONVERT_WINDOWS_PATHS = "0"
        }
        Invoke-External $Engine @("compose", "build", "skills-sync") `
            "Falha ao preparar o sincronizador de skills"
        Invoke-External $Engine @("compose", "run", "--rm", "--no-deps", "-e", "SKILLS_SYNC_ONCE=true", "skills-sync") `
            "O container não conseguiu acessar e materializar o repositório de skills. Verifique o login do GitHub e o acesso ao repositório."
        $managedCount = @(Get-ChildItem -LiteralPath $SkillsDirectory -Directory -Filter "pat-*" |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") }).Count
        if ($managedCount -eq 0) {
            throw "A sincronização terminou sem criar skills em '$SkillsDirectory'. Confira se o repositório contém AGENTS.md ou arquivos .agents/**/*.md."
        }
        Invoke-External $Engine @("compose", "up", "-d", "--no-deps", "--force-recreate", "skills-sync") `
            "A primeira sincronização funcionou, mas não foi possível iniciar a atualização periódica"
        Write-SetupMessage "$managedCount skill(s) do Caveman materializadas e atualização periódica habilitada." "OK"
    } finally {
        $env:COMPOSE_CONVERT_WINDOWS_PATHS = $previousPathConversion
        Pop-Location
    }
}

function Remove-LegacyOmniSkills {
    param([string]$BaseUrl, [string]$AppKey)
    $headers = @{ Authorization = "Bearer $AppKey" }
    $response = Invoke-RestMethod -Uri "$BaseUrl/api/skills?source=local&limit=200" `
        -Headers $headers -TimeoutSec 20 -ErrorAction Stop
    $legacy = @($response.skills | Where-Object { $_.name -like "pat-*" })
    foreach ($skill in $legacy) {
        Invoke-RestMethod -Uri "$BaseUrl/api/skills/$($skill.id)" -Method Delete `
            -Headers $headers -TimeoutSec 20 -ErrorAction Stop | Out-Null
    }
    if ($legacy.Count -gt 0) {
        Write-SetupMessage "$($legacy.Count) skill(s) instrucionais legadas removidas do executor Omni Skills." "OK"
    }
}

function Restart-ContainerGateway {
    param([string]$Engine, [string]$SetupDirectory)
    Push-Location $SetupDirectory
    try {
        Invoke-External $Engine @("compose", "restart", "omniroute") `
            "A AppKey foi criada, mas não foi possível recarregar o gateway"
    } finally {
        Pop-Location
    }
}

function Start-LocalMode {
    param([string]$HomeDirectory, [int]$Port, [string]$EnvPath)
    try {
        Invoke-External "npm" @("install", "--global", "omniroute@3.8.48", "--no-audit", "--no-fund") "Falha ao instalar o OmniRoute"
    } catch {
        Write-SetupMessage "O pacote exigiu compilação nativa; instalando Python/C++ e tentando novamente." "WARN"
        Install-NativeBuildTools
        Invoke-External "npm" @("install", "--global", "omniroute@3.8.48", "--no-audit", "--no-fund") "Falha ao instalar o OmniRoute após preparar o toolchain"
    }
    $taskName = "OmniRoute Gateway"
    $omnirouteCommand = (Get-Command omniroute -ErrorAction Stop).Source
    if ([IO.Path]::GetExtension($omnirouteCommand) -in @(".cmd", ".bat")) {
        $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument "/d /c `"$omnirouteCommand`" --port $Port --no-open"
    } else {
        $action = New-ScheduledTaskAction -Execute $omnirouteCommand -Argument "--port $Port --no-open"
    }
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "OmniRoute em background" -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
}

function Invoke-OmniRouteSetup {
    [CmdletBinding()]
    param(
        [ValidateSet("container", "local")][string]$Mode,
        [string]$SetupDirectory,
        [string]$SkillsRepository,
        [string]$SkillsBranch,
        [int]$Port,
        [string]$AchillesRepository,
        [string]$AchillesVersion,
        [AllowEmptyString()][string]$AchillesArtifactPath,
        [bool]$NonInteractive,
        [bool]$SkipAchilles,
        [bool]$SkipProviderLogin,
        [AllowEmptyString()][string]$CorporateCAPath
    )
    $homeDirectory = $env:USERPROFILE
    $stateDirectory = Join-Path $homeDirectory ".omniroute"
    $envPath = if ($Mode -eq "container") { Join-Path $SetupDirectory ".env" } else { Join-Path $stateDirectory ".env" }
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    if (-not (Test-Path -LiteralPath $envPath)) { Copy-Item (Join-Path $SetupDirectory ".env.example") $envPath }
    Remove-EnvValue -Path $envPath -Names @(
        "OPENHANDS_PORT",
        "OPENHANDS_VERSION",
        "OPENHANDS_AGENT_SERVER_TAG",
        "OPENHANDS_HOME_DIR",
        "OPENHANDS_SETTINGS_FILE",
        "SANDBOX_VOLUMES",
        "CONTAINER_SOCKET",
        "PROJECTS_DIR"
    )
    Set-EnvValue $envPath "PORT" ([string]$Port)
    Set-EnvValue $envPath "OMNIROUTE_SKILLS_REPO" $SkillsRepository
    Set-EnvValue $envPath "OMNIROUTE_SKILLS_BRANCH" $SkillsBranch
    $cavemanSkillsDirectory = Join-Path $homeDirectory ".cave\skills"
    New-Item -ItemType Directory -Path $cavemanSkillsDirectory -Force | Out-Null
    Set-EnvValue $envPath "CAVEMAN_SKILLS_DIR" $cavemanSkillsDirectory.Replace('\', '/')
    if ($Mode -eq "container") {
        $githubToken = Ensure-GitHubCliAuthentication -NonInteractive $NonInteractive
        if (![string]::IsNullOrWhiteSpace($githubToken)) {
            Set-EnvValue $envPath "GITHUB_TOKEN" $githubToken
        }
    }
    Write-SetupMessage "Preparando o modo $Mode. Reexecuções preservam banco, APPKEY e configurações."
    if ($Mode -eq "container") {
        New-Item -ItemType File -Path (Join-Path $stateDirectory "mode.container") -Force | Out-Null
        $engine = Ensure-ContainerEngine
        Invoke-CorporateCAInjection -SetupDirectory $SetupDirectory -CorporateCAPath $CorporateCAPath
        Start-ContainerMode -Engine $engine -SetupDirectory $SetupDirectory
    } else {
        Remove-Item -LiteralPath (Join-Path $stateDirectory "mode.container") -Force -ErrorAction SilentlyContinue
        Ensure-LocalDependencies
        Sync-SkillsRepository -Repository $SkillsRepository -Branch $SkillsBranch -Destination (Join-Path $stateDirectory "skills")
        Start-LocalMode -HomeDirectory $homeDirectory -Port $Port -EnvPath $envPath
    }

    $baseUrl = "http://localhost:$Port"
    Wait-HttpReady -Url "$baseUrl/api/monitoring/health"
    $containerEngine = if ($Mode -eq "container") { $engine } else { "" }
    $appKey = Ensure-AppKey -BaseUrl $baseUrl -EnvPath $envPath `
        -NonInteractive $NonInteractive -ContainerEngine $containerEngine
    $env:OMNIROUTE_API_KEY = $appKey
    if ($Mode -eq "container") {
        # The API-key metadata cache in 3.8.48 is not invalidated when scopes
        # are patched during onboarding. Restart before the first management call.
        Restart-ContainerGateway -Engine $engine -SetupDirectory $SetupDirectory
        Wait-HttpReady -Url "$baseUrl/api/monitoring/health"
        # Validate GitHub access from the same container/network used in normal
        # operation and require a non-empty first publication.
        Start-ValidatedSkillsSync -Engine $engine -SetupDirectory $SetupDirectory `
            -SkillsDirectory $cavemanSkillsDirectory
    }
    Remove-LegacyOmniSkills -BaseUrl $baseUrl -AppKey $appKey
    Set-TokenEfficiencyDefaults -BaseUrl $baseUrl -AppKey $appKey

    if (-not $SkipProviderLogin -and -not $NonInteractive) {
        Start-Process "$baseUrl/dashboard/providers"
        Read-Host "Conecte os provedores de IA no Dashboard e pressione ENTER para continuar"
    }
    Set-ConfiguredProvidersOnly -BaseUrl $baseUrl -AppKey $appKey
    Set-ConfiguredCombos -BaseUrl $baseUrl -ConfigPath (Join-Path $SetupDirectory "combos-config.json") -AppKey $appKey

    if (-not $SkipAchilles) {
        $achillesInstallation = Install-Achilles -HomeDirectory $homeDirectory `
            -OmniRoutePort $Port `
            -Repository $AchillesRepository -Version $AchillesVersion `
            -ArtifactPath $AchillesArtifactPath `
            -FallbackIconPath (Join-Path $SetupDirectory "design\achilles\achilles.ico")
        Test-AchillesInstallation -HomeDirectory $homeDirectory `
            -Installation $achillesInstallation | Out-Null
        [Environment]::SetEnvironmentVariable("ACHILLES_CONFIG", $achillesInstallation.Config, "User")
        $env:ACHILLES_CONFIG = $achillesInstallation.Config
        Write-SetupMessage "Abra o Achilles pelo ícone da Área de Trabalho ou Menu Iniciar." "OK"
    }

    Install-OmniCommand -SetupDirectory $SetupDirectory -HomeDirectory $homeDirectory

    Write-SetupMessage "OmniRoute disponível em $baseUrl; configuração concluída." "OK"
}

Export-ModuleMember -Function Set-EnvValue, Remove-EnvValue, Get-EnvValue, Get-ContainerEngine, Sync-SkillsRepository, Test-AppKey, Ensure-AppKey, Set-TokenEfficiencyDefaults, Set-ConfiguredProvidersOnly, Set-ConfiguredCombos, Get-PathWithEntry, Invoke-CorporateCAInjection, Invoke-OmniRouteSetup
