$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script:AchillesConfigSchemaVersion = 2
$script:AchillesDefaultRepository = "pmacedo25/Achilles-Releases"
$script:AchillesLegacyStateDirectoryName = ".openrouterai"
$script:AchillesStateDirectoryName = ".achilles"
$script:AchillesLegacyProductName = "OpenRouterAI"

function Write-AchillesMessage {
    param([string]$Message, [ValidateSet("INFO", "OK", "WARN")][string]$Level = "INFO")
    $color = switch ($Level) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Set-Utf8JsonFile {
    param([string]$Path, [string]$Json)
    # Node's JSON.parse does not ignore a UTF-8 BOM. Windows PowerShell 5 adds
    # one for `Set-Content -Encoding utf8`, so write JSON explicitly without it.
    [System.IO.File]::WriteAllText(
        $Path,
        $Json,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Get-AchillesArchitecture {
    $architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    if ($architecture -ne "x64") {
        throw "O protótipo Achilles suporta somente Windows x64; arquitetura detectada: $architecture."
    }
    return $architecture
}

function Write-AchillesConfiguration {
    param(
        [string]$HomeDirectory,
        [int]$OmniRoutePort
    )
    $stateDirectory = Join-Path $HomeDirectory $script:AchillesStateDirectoryName
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $configuration = [ordered]@{
        schemaVersion = $script:AchillesConfigSchemaVersion
        omnirouteBaseUrl = "http://127.0.0.1:$OmniRoutePort/v1"
        omnirouteHealthUrl = "http://127.0.0.1:$OmniRoutePort/api/monitoring/health"
        omnirouteCatalogUrl = "http://127.0.0.1:$OmniRoutePort/v1/models"
        apiKeyEnvironmentVariable = "OMNIROUTE_API_KEY"
        modelSelection = "dynamic"
        configuredProvidersOnly = $true
        telemetry = $false
    }
    $configPath = Join-Path $stateDirectory "config.json"
    $temporaryPath = "$configPath.new"
    Set-Utf8JsonFile -Path $temporaryPath `
        -Json ($configuration | ConvertTo-Json -Depth 10)
    Move-Item -LiteralPath $temporaryPath -Destination $configPath -Force
    return $configPath
}

function Write-AchillesSettings {
    param(
        [string]$HomeDirectory,
        [int]$OmniRoutePort
    )
    $stateDirectory = Join-Path $HomeDirectory $script:AchillesStateDirectoryName
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $baseUrl = "http://127.0.0.1:$OmniRoutePort/v1"
    $apiKey = [Environment]::GetEnvironmentVariable("OMNIROUTE_API_KEY", "User")
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        $apiKey = $env:OMNIROUTE_API_KEY
    }
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "OMNIROUTE_API_KEY não está configurada para o Achilles."
    }
    $models = @(
        [ordered]@{ id = "combo-coding"; name = "combo-coding"; url = $baseUrl; apiKey = $apiKey; enableStreaming = $true },
        [ordered]@{ id = "combo-refining"; name = "combo-refining"; url = $baseUrl; apiKey = $apiKey; enableStreaming = $true },
        [ordered]@{ id = "combo-testing"; name = "combo-testing"; url = $baseUrl; apiKey = $apiKey; enableStreaming = $true }
    )
    $settings = [ordered]@{
        "ai-features.chat.bypassModelRequirement" = $true
        "ai-features.chat.toolConfirmation" = [ordered]@{}
        "ai-features.openAiCustom.customOpenAiModels" = $models
    }
    $settingsPath = Join-Path $stateDirectory "settings.json"
    $temporaryPath = "$settingsPath.new"
    Set-Utf8JsonFile -Path $temporaryPath `
        -Json ($settings | ConvertTo-Json -Depth 10)
    Move-Item -LiteralPath $temporaryPath -Destination $settingsPath -Force
    return $settingsPath
}

function Copy-AchillesLegacyState {
    [CmdletBinding()]
    param([string]$HomeDirectory)

    $legacyStateDirectory = Join-Path $HomeDirectory $script:AchillesLegacyStateDirectoryName
    $stateDirectory = Join-Path $HomeDirectory $script:AchillesStateDirectoryName
    if (-not (Test-Path -LiteralPath $legacyStateDirectory -PathType Container)) {
        return $false
    }

    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    # Caches, UI layout and old launchers carry serialized product branding and
    # executable paths. They are safe to regenerate and must not contaminate the
    # renamed application state.
    $transientLegacyEntries = @(
        "globalStorage",
        "localization-cache",
        "logs",
        "plugin-storage",
        "workspace-metadata",
        "workspace-storage",
        "OpenRouterAI.ico",
        "OpenRouterAI.ps1",
        "current.json",
        "downloads"
    )
    Get-ChildItem -LiteralPath $legacyStateDirectory -Force | ForEach-Object {
        if ($_.Name -notin $transientLegacyEntries) {
            $destination = Join-Path $stateDirectory $_.Name
            if (-not (Test-Path -LiteralPath $destination)) {
                Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
            }
        }
    }

    $migrationPath = Join-Path $stateDirectory "migration.json"
    if (-not (Test-Path -LiteralPath $migrationPath -PathType Leaf)) {
        $migrationRecord = [ordered]@{
            source = $legacyStateDirectory
            migratedAt = [DateTime]::UtcNow.ToString("o")
            legacyStatePreserved = $true
        }
        Set-Utf8JsonFile -Path "$migrationPath.new" `
            -Json ($migrationRecord | ConvertTo-Json)
        Move-Item -LiteralPath "$migrationPath.new" -Destination $migrationPath
    }
    return $true
}

function Get-AchillesRelease {
    param(
        [string]$Repository,
        [string]$Version,
        [string]$Destination
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    # Downloads persist between releases. Metadata from an older release must
    # never be used to validate a newer artifact.
    Remove-Item -LiteralPath (Join-Path $Destination "SHA256SUMS") `
        -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $Destination "release-manifest.json") `
        -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $Destination -Filter "Achilles-win-x64-*.zip" `
        -File -ErrorAction SilentlyContinue | Remove-Item -Force
    $headers = @{
        Accept = "application/vnd.github+json"
        "User-Agent" = "OmniRoute-Setup"
        "Cache-Control" = "no-cache"
        Pragma = "no-cache"
    }
    $resolvedRequest = if ([string]::IsNullOrWhiteSpace($Version)) { "latest" } else { $Version.Trim() }
    $releaseEndpoint = if ($resolvedRequest -eq "latest") {
        $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        "https://api.github.com/repos/$Repository/releases/latest?cacheBust=$cacheBust"
    } else {
        $tag = if ($resolvedRequest.StartsWith("v")) { $resolvedRequest } else { "v$resolvedRequest" }
        "https://api.github.com/repos/$Repository/releases/tags/$([uri]::EscapeDataString($tag))"
    }
    try {
        $release = Invoke-RestMethod -Uri $releaseEndpoint -Headers $headers -Method Get
    } catch {
        throw "Não foi possível consultar o release público '$resolvedRequest' de '$Repository': $($_.Exception.Message)"
    }
    $releaseVersion = ([string]$release.tag_name).TrimStart("v")
    if ($releaseVersion -notmatch '^\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?$') {
        throw "O release retornado possui uma tag inválida: '$($release.tag_name)'."
    }
    $artifactAssets = @($release.assets | Where-Object {
        $_.name -match "^Achilles-win-x64-\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?\.zip$"
    })
    if ($artifactAssets.Count -eq 0) {
        $availableNames = @($release.assets | ForEach-Object { $_.name }) -join ", "
        throw "O release '$($release.tag_name)' não contém um build Achilles para Windows x64. Artefatos disponíveis: $availableNames. Publique uma build validada ou informe -AchillesArtifactPath."
    }
    if ($artifactAssets.Count -gt 1) {
        $matchingNames = @($artifactAssets | ForEach-Object { $_.name }) -join ", "
        throw "O release '$($release.tag_name)' contém builds Achilles duplicadas para Windows x64: $matchingNames."
    }
    $artifactAsset = $artifactAssets[0]
    if ($artifactAsset.name -notmatch '^Achilles-win-x64-(?<version>\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?)\.zip$' -or
        $Matches.version -ne $releaseVersion) {
        throw "O artefato '$($artifactAsset.name)' não corresponde ao release '$($release.tag_name)'."
    }
    Write-AchillesMessage "Release Achilles resolvido: $($release.tag_name) ($($artifactAsset.name))." "INFO"
    $apiDigest = [string]$artifactAsset.digest
    $hasApiDigest = $apiDigest -match '^sha256:[a-fA-F0-9]{64}$'
    $assetsToDownload = @($artifactAsset)
    $assetsToDownload += @($release.assets | Where-Object {
        $_.name -eq "release-manifest.json" -or
        ($_.name -eq "SHA256SUMS" -and -not $hasApiDigest)
    })
    foreach ($asset in $assetsToDownload) {
        $destinationPath = Join-Path $Destination $asset.name
        try {
            Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $destinationPath -UseBasicParsing
        } catch {
            throw "Falha ao baixar '$($asset.name)' do release '$($release.tag_name)': $($_.Exception.Message)"
        }
    }
    $artifactName = $artifactAssets[0].name
    $artifactPath = Join-Path $Destination $artifactName
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "O download terminou sem criar o artefato esperado '$artifactName'."
    }
    if ($hasApiDigest) {
        $digestHash = $apiDigest.Substring("sha256:".Length).ToLowerInvariant()
        Set-Content -LiteralPath (Join-Path $Destination "SHA256SUMS") `
            -Value "$digestHash  $artifactName" -Encoding ascii
    }
    return $artifactPath
}

function Test-AchillesArtifact {
    param([string]$ArtifactPath, [string]$Sha256SumsPath)
    if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
        throw "Artefato Achilles não encontrado: $ArtifactPath"
    }
    $actualHash = (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($Sha256SumsPath) -and
        (Test-Path -LiteralPath $Sha256SumsPath -PathType Leaf)) {
        $artifactName = Split-Path -Leaf $ArtifactPath
        $checksumPattern = '^\s*([a-fA-F0-9]{{64}})\s+\*?{0}\s*$' -f `
            [regex]::Escape($artifactName)
        $matchingLine = @(Get-Content -LiteralPath $Sha256SumsPath | Where-Object {
            $_ -match $checksumPattern
        })
        if ($matchingLine.Count -ne 1) {
            throw "SHA256SUMS não contém uma entrada única para '$artifactName'."
        }
        $expectedHash = ([regex]::Match($matchingLine[0], "[a-fA-F0-9]{64}").Value).ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Checksum inválido para '$artifactName'."
        }
    }
    return $actualHash
}

function Get-AchillesVersion {
    param([string]$ArtifactPath, [string]$ManifestPath)
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath) -and
        (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        if ($manifest.version -and "$($manifest.version)" -match "^\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$") {
            return "$($manifest.version)"
        }
    }
    $name = Split-Path -Leaf $ArtifactPath
    if ($name -match "Achilles-win-x64-(?<version>\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?)\.zip") {
        return $Matches.version
    }
    throw "Não foi possível determinar a versão SemVer do artefato '$name'."
}

function New-AchillesLauncher {
    param(
        [string]$HomeDirectory,
        [string]$InstallRoot
    )
    $stateDirectory = Join-Path $HomeDirectory ".achilles"
    $launcherPath = Join-Path $stateDirectory "Achilles.ps1"
    $launcher = @"
param([Parameter(ValueFromRemainingArguments = `$true)][string[]]`$WorkspaceArguments)
`$ErrorActionPreference = "Stop"
`$stateDirectory = "$stateDirectory"
`$current = Get-Content -LiteralPath (Join-Path `$stateDirectory "current.json") -Raw | ConvertFrom-Json
`$executable = [IO.Path]::GetFullPath(`$current.executable)
`$allowedRoot = [IO.Path]::GetFullPath("$InstallRoot").TrimEnd("\") + "\"
if (-not `$executable.StartsWith(`$allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Achilles executable outside the managed install directory."
}
if (-not (Test-Path -LiteralPath `$executable -PathType Leaf)) {
    throw "Achilles executable not found. Re-run the OmniRoute installer."
}
`$env:ACHILLES_CONFIG = Join-Path `$stateDirectory "config.json"
`$currentApiKey = [Environment]::GetEnvironmentVariable("OMNIROUTE_API_KEY", "User")
if ([string]::IsNullOrWhiteSpace(`$currentApiKey)) {
    throw "OMNIROUTE_API_KEY is not configured for the current user. Re-run the OmniRoute installer."
}
`$env:OMNIROUTE_API_KEY = `$currentApiKey
`$env:OPENAI_API_KEY = `$currentApiKey
`$corporateCAPath = Join-Path (Split-Path -Parent `$stateDirectory) ".omniroute\setup\skills-sync\netskope-ca.pem"
if ((Test-Path -LiteralPath `$corporateCAPath -PathType Leaf) -and
    (Get-Item -LiteralPath `$corporateCAPath).Length -gt 0) {
    # NODE_EXTRA_CA_CERTS is read only when Node starts, so it must be present
    # before Electron launches. Keep the Windows trust-store fallback in the IDE
    # as a second layer for machines whose corporate chain changes later.
    `$env:NODE_EXTRA_CA_CERTS = `$corporateCAPath
}
`$arguments = @(`$WorkspaceArguments | Where-Object {
    -not [string]::IsNullOrWhiteSpace(`$_)
})
try {
    if (`$arguments.Count -gt 0) {
        Start-Process -FilePath `$executable -ArgumentList `$arguments -ErrorAction Stop
    } else {
        Start-Process -FilePath `$executable -ErrorAction Stop
    }
} catch {
    `$errorRecord = "`${([DateTime]::Now.ToString('s'))} `$(`$_.Exception.Message)"
    Set-Content -LiteralPath (Join-Path `$stateDirectory "launcher-error.log") `
        -Value `$errorRecord -Encoding utf8
    throw
}
"@
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding utf8
    $graphicalLauncherPath = [IO.Path]::ChangeExtension($launcherPath, ".vbs")
    $escapedPowerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe".Replace('"', '""')
    $escapedLauncherPath = $launcherPath.Replace('"', '""')
    $graphicalLauncher = @"
Set shell = CreateObject("WScript.Shell")
command = """$escapedPowerShellPath"" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$escapedLauncherPath"""
For Each argument In WScript.Arguments
    command = command & " """ & Replace(argument, """", """""") & """"
Next
shell.Run command, 0, False
"@
    Set-Content -LiteralPath $graphicalLauncherPath -Value $graphicalLauncher -Encoding ascii
    return $launcherPath
}

function Install-AchillesCommand {
    param(
        [string]$HomeDirectory,
        [string]$LauncherPath
    )
    $commandDirectory = Join-Path $HomeDirectory ".omniroute\bin"
    New-Item -ItemType Directory -Path $commandDirectory -Force | Out-Null
    $commandPath = Join-Path $commandDirectory "achilles.cmd"
    $command = @"
@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$LauncherPath" %*
"@
    Set-Content -LiteralPath $commandPath -Value $command -Encoding ascii

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = @($userPath -split ";" | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
    if (@($pathEntries | Where-Object {
        $_.TrimEnd("\") -ieq $commandDirectory.TrimEnd("\")
    }).Count -eq 0) {
        $updatedPath = (@($pathEntries) + $commandDirectory) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $updatedPath, "User")
    }
    if (@($env:PATH -split ";" | Where-Object {
        $_.TrimEnd("\") -ieq $commandDirectory.TrimEnd("\")
    }).Count -eq 0) {
        $env:PATH = "$commandDirectory;$env:PATH"
    }
    return $commandPath
}

function New-AchillesShortcuts {
    param(
        [string]$LauncherPath,
        [string]$GraphicalLauncherPath,
        [string]$IconPath,
        [string]$WorkingDirectory
    )
    $desktopDirectory = [Environment]::GetFolderPath("Desktop")
    $startMenuDirectory = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null
    $wscriptPath = "$env:SystemRoot\System32\wscript.exe"
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutPath in @(
        (Join-Path $desktopDirectory "Achilles.lnk"),
        (Join-Path $startMenuDirectory "Achilles.lnk")
    )) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $wscriptPath
        $shortcut.Arguments = "`"$GraphicalLauncherPath`""
        $shortcut.WorkingDirectory = $WorkingDirectory
        $shortcut.WindowStyle = 1
        $shortcut.IconLocation = "$IconPath,0"
        $shortcut.Description = "Achilles via OmniRoute"
        $shortcut.Save()
    }

    foreach ($legacyShortcutPath in @(
        (Join-Path $desktopDirectory "$($script:AchillesLegacyProductName).lnk"),
        (Join-Path $startMenuDirectory "$($script:AchillesLegacyProductName).lnk")
    )) {
        Remove-Item -LiteralPath $legacyShortcutPath -Force -ErrorAction SilentlyContinue
    }
    return @(
        (Join-Path $desktopDirectory "Achilles.lnk"),
        (Join-Path $startMenuDirectory "Achilles.lnk")
    )
}

function Install-Achilles {
    [CmdletBinding()]
    param(
        [string]$HomeDirectory,
        [int]$OmniRoutePort,
        [string]$Repository = $script:AchillesDefaultRepository,
        [string]$Version = "latest",
        [AllowEmptyString()][string]$ArtifactPath,
        [string]$FallbackIconPath
    )
    [void](Get-AchillesArchitecture)
    $legacyStateMigrated = Copy-AchillesLegacyState -HomeDirectory $HomeDirectory
    $stateDirectory = Join-Path $HomeDirectory $script:AchillesStateDirectoryName
    $installRoot = Join-Path $env:LOCALAPPDATA "Programs\Achilles"
    $downloadDirectory = Join-Path $stateDirectory "downloads"
    New-Item -ItemType Directory -Path $stateDirectory, $installRoot, $downloadDirectory -Force | Out-Null

    if ([string]::IsNullOrWhiteSpace($ArtifactPath)) {
        $ArtifactPath = Get-AchillesRelease -Repository $Repository -Version $Version `
            -Destination $downloadDirectory
    } else {
        $ArtifactPath = [IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($ArtifactPath)
        )
    }
    $artifactDirectory = Split-Path -Parent $ArtifactPath
    $sumsPath = Join-Path $artifactDirectory "SHA256SUMS"
    $manifestPath = Join-Path $artifactDirectory "release-manifest.json"
    [void](Test-AchillesArtifact -ArtifactPath $ArtifactPath -Sha256SumsPath $sumsPath)
    $resolvedVersion = Get-AchillesVersion -ArtifactPath $ArtifactPath -ManifestPath $manifestPath
    $versionDirectory = Join-Path $installRoot $resolvedVersion
    $stagingDirectory = Join-Path $installRoot ".staging-$resolvedVersion"

    $installedExecutables = @(if (Test-Path -LiteralPath $versionDirectory) {
        @(Get-ChildItem -LiteralPath $versionDirectory -Recurse -Filter "Achilles.exe" -File)
    } else {
        @()
    })
    if ($installedExecutables.Count -eq 1) {
        $executablePath = $installedExecutables[0].FullName
    } else {
        if (Test-Path -LiteralPath $stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
        }
        New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
        Expand-Archive -LiteralPath $ArtifactPath -DestinationPath $stagingDirectory -Force
        $executables = @(Get-ChildItem -LiteralPath $stagingDirectory -Recurse -Filter "Achilles.exe" -File)
        if ($executables.Count -ne 1) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
            throw "O artefato deve conter exatamente um Achilles.exe."
        }
        if (Test-Path -LiteralPath $versionDirectory) {
            Remove-Item -LiteralPath $versionDirectory -Recurse -Force
        }
        $relativeExecutable = $executables[0].FullName.Substring($stagingDirectory.Length).TrimStart("\")
        Move-Item -LiteralPath $stagingDirectory -Destination $versionDirectory
        $executablePath = Join-Path $versionDirectory $relativeExecutable
    }

    $configPath = Write-AchillesConfiguration -HomeDirectory $HomeDirectory `
        -OmniRoutePort $OmniRoutePort
    Write-AchillesSettings -HomeDirectory $HomeDirectory -OmniRoutePort $OmniRoutePort | Out-Null
    $currentPath = Join-Path $stateDirectory "current.json"
    $currentTemporaryPath = "$currentPath.new"
    $currentRecord = [ordered]@{
        version = $resolvedVersion
        executable = $executablePath
        config = $configPath
        installedAt = [DateTime]::UtcNow.ToString("o")
    }
    Set-Utf8JsonFile -Path $currentTemporaryPath `
        -Json ($currentRecord | ConvertTo-Json)
    Move-Item -LiteralPath $currentTemporaryPath -Destination $currentPath -Force

    $iconPath = Join-Path $stateDirectory "Achilles.ico"
    if (Test-Path -LiteralPath $FallbackIconPath -PathType Leaf) {
        Copy-Item -LiteralPath $FallbackIconPath -Destination $iconPath -Force
    } else {
        $iconPath = $executablePath
    }
    $launcherPath = New-AchillesLauncher -HomeDirectory $HomeDirectory `
        -InstallRoot $installRoot
    $graphicalLauncherPath = [IO.Path]::ChangeExtension($launcherPath, ".vbs")
    $commandPath = Install-AchillesCommand -HomeDirectory $HomeDirectory `
        -LauncherPath $launcherPath
    $shortcutPaths = @(New-AchillesShortcuts -LauncherPath $launcherPath `
        -GraphicalLauncherPath $graphicalLauncherPath -IconPath $iconPath `
        -WorkingDirectory $HomeDirectory
    )
    Write-AchillesMessage "Achilles $resolvedVersion instalado sem elevação." "OK"
    if ($legacyStateMigrated) {
        Write-AchillesMessage "Configurações do OpenRouterAI foram copiadas; o estado original foi preservado para rollback." "OK"
    }
    Write-AchillesMessage "Abra uma pasta ou workspace no Achilles; o chat e as ferramentas usarão o contexto aberto na janela." "INFO"
    return [pscustomobject]@{
        Version = $resolvedVersion
        Executable = $executablePath
        Config = $configPath
        Launcher = $launcherPath
        GraphicalLauncher = $graphicalLauncherPath
        Command = $commandPath
        Shortcuts = $shortcutPaths
    }
}

function Test-AchillesInstallation {
    param(
        [Parameter(Mandatory)][string]$HomeDirectory,
        [Parameter(Mandatory)][pscustomobject]$Installation
    )
    $currentPath = Join-Path $HomeDirectory ".achilles\current.json"
    if (-not (Test-Path -LiteralPath $Installation.Executable -PathType Leaf)) {
        throw "A instalação do Achilles não criou o executável esperado: $($Installation.Executable)"
    }
    if (-not (Test-Path -LiteralPath $Installation.Config -PathType Leaf)) {
        throw "A instalação do Achilles não criou a configuração esperada: $($Installation.Config)"
    }
    if (-not (Test-Path -LiteralPath $Installation.Launcher -PathType Leaf)) {
        throw "A instalação do Achilles não criou o launcher esperado: $($Installation.Launcher)"
    }
    if (-not (Test-Path -LiteralPath $Installation.GraphicalLauncher -PathType Leaf)) {
        throw "A instalação do Achilles não criou o launcher gráfico esperado: $($Installation.GraphicalLauncher)"
    }
    if (-not (Test-Path -LiteralPath $Installation.Command -PathType Leaf)) {
        throw "A instalação do Achilles não criou o comando esperado: $($Installation.Command)"
    }
    if (@($Installation.Shortcuts).Count -ne 2 -or
        @($Installation.Shortcuts | Where-Object {
            -not (Test-Path -LiteralPath $_ -PathType Leaf)
        }).Count -gt 0) {
        throw "A instalação do Achilles não criou os atalhos do Desktop e Menu Iniciar."
    }
    $commandDirectory = Split-Path -Parent $Installation.Command
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (@($userPath -split ";" | Where-Object {
        $_.TrimEnd("\") -ieq $commandDirectory.TrimEnd("\")
    }).Count -eq 0) {
        throw "O diretório do comando Achilles não foi incluído no PATH do usuário."
    }
    if (-not (Test-Path -LiteralPath $currentPath -PathType Leaf)) {
        throw "A instalação do Achilles não registrou a versão ativa."
    }
    $configuration = Get-Content -LiteralPath $Installation.Config -Raw | ConvertFrom-Json
    if ($configuration.modelSelection -ne "dynamic" -or
        $configuration.configuredProvidersOnly -ne $true -or
        $configuration.apiKeyEnvironmentVariable -ne "OMNIROUTE_API_KEY") {
        throw "A configuração do Achilles não atende ao contrato OmniRoute."
    }
    return $true
}

Export-ModuleMember -Function Write-AchillesConfiguration, Write-AchillesSettings, Copy-AchillesLegacyState, Test-AchillesArtifact, Get-AchillesVersion, Install-AchillesCommand, Install-Achilles, Test-AchillesInstallation
