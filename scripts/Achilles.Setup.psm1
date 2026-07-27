$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script:AchillesConfigSchemaVersion = 2
$script:AchillesDefaultRepository = "pmacedo25/Achilles"
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
        [string]$ProjectsDirectory,
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
        workspace = $ProjectsDirectory
        modelSelection = "dynamic"
        telemetry = $false
    }
    $configPath = Join-Path $stateDirectory "config.json"
    $temporaryPath = "$configPath.new"
    $configuration | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $configPath -Force
    return $configPath
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
        [ordered]@{
            source = $legacyStateDirectory
            migratedAt = [DateTime]::UtcNow.ToString("o")
            legacyStatePreserved = $true
        } | ConvertTo-Json | Set-Content -LiteralPath "$migrationPath.new" -Encoding utf8
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
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        throw "GitHub CLI é necessário para baixar o release privado do Achilles."
    }
    & $gh.Source auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI não está autenticado. Execute 'gh auth login --git-protocol https --web' e reexecute."
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $releaseViewArguments = @(
        "release", "view", "--repo", $Repository,
        "--json", "tagName,assets"
    )
    if (-not [string]::IsNullOrWhiteSpace($Version) -and $Version -ne "latest") {
        $releaseViewArguments += $Version
    }
    $releaseJson = & $gh.Source @releaseViewArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Não foi possível consultar o release '$Version' de '$Repository'."
    }
    $release = $releaseJson | ConvertFrom-Json
    $artifactAssets = @($release.assets | Where-Object {
        $_.name -match "^Achilles-win-x64-\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?\.zip$"
    })
    if ($artifactAssets.Count -eq 0) {
        $availableNames = @($release.assets | ForEach-Object { $_.name }) -join ", "
        throw "O release '$($release.tagName)' não contém um build Achilles para Windows x64. Artefatos disponíveis: $availableNames. Publique uma build validada ou informe -AchillesArtifactPath."
    }
    if ($artifactAssets.Count -gt 1) {
        $matchingNames = @($artifactAssets | ForEach-Object { $_.name }) -join ", "
        throw "O release '$($release.tagName)' contém builds Achilles duplicadas para Windows x64: $matchingNames."
    }
    $artifactName = $artifactAssets[0].name
    $arguments = @(
        "release", "download", "--repo", $Repository,
        "--pattern", $artifactName,
        "--pattern", "release-manifest.json",
        "--pattern", "SHA256SUMS",
        "--dir", $Destination,
        "--clobber"
    )
    if (-not [string]::IsNullOrWhiteSpace($Version) -and $Version -ne "latest") {
        $arguments += $Version
    }
    & $gh.Source @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao baixar o release '$Version' de '$Repository'."
    }
    $artifactPath = Join-Path $Destination $artifactName
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "O download terminou sem criar o artefato esperado '$artifactName'."
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
        $matchingLine = @(Get-Content -LiteralPath $Sha256SumsPath | Where-Object {
            $_ -match "^\s*([a-fA-F0-9]{64})\s+\*?$([regex]::Escape($artifactName))\s*$"
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
        [string]$InstallRoot,
        [string]$ProjectsDirectory
    )
    $stateDirectory = Join-Path $HomeDirectory ".achilles"
    $launcherPath = Join-Path $stateDirectory "Achilles.ps1"
    $launcher = @"
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
`$env:OPENAI_API_KEY = `$env:OMNIROUTE_API_KEY
Start-Process -FilePath `$executable -ArgumentList @("$ProjectsDirectory")
"@
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding utf8
    return $launcherPath
}

function New-AchillesShortcuts {
    param(
        [string]$LauncherPath,
        [string]$IconPath,
        [string]$WorkingDirectory
    )
    $desktopDirectory = [Environment]::GetFolderPath("Desktop")
    $startMenuDirectory = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null
    $powerShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutPath in @(
        (Join-Path $desktopDirectory "Achilles.lnk"),
        (Join-Path $startMenuDirectory "Achilles.lnk")
    )) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $powerShellPath
        $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LauncherPath`""
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
}

function Install-Achilles {
    [CmdletBinding()]
    param(
        [string]$HomeDirectory,
        [string]$ProjectsDirectory,
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
        -ProjectsDirectory $ProjectsDirectory -OmniRoutePort $OmniRoutePort
    $currentPath = Join-Path $stateDirectory "current.json"
    $currentTemporaryPath = "$currentPath.new"
    [ordered]@{
        version = $resolvedVersion
        executable = $executablePath
        config = $configPath
        installedAt = [DateTime]::UtcNow.ToString("o")
    } | ConvertTo-Json | Set-Content -LiteralPath $currentTemporaryPath -Encoding utf8
    Move-Item -LiteralPath $currentTemporaryPath -Destination $currentPath -Force

    $iconPath = Join-Path $stateDirectory "Achilles.ico"
    if (Test-Path -LiteralPath $FallbackIconPath -PathType Leaf) {
        Copy-Item -LiteralPath $FallbackIconPath -Destination $iconPath -Force
    } else {
        $iconPath = $executablePath
    }
    $launcherPath = New-AchillesLauncher -HomeDirectory $HomeDirectory `
        -InstallRoot $installRoot -ProjectsDirectory $ProjectsDirectory
    New-AchillesShortcuts -LauncherPath $launcherPath -IconPath $iconPath `
        -WorkingDirectory $ProjectsDirectory
    Write-AchillesMessage "Achilles $resolvedVersion instalado sem elevação." "OK"
    if ($legacyStateMigrated) {
        Write-AchillesMessage "Configurações do OpenRouterAI foram copiadas; o estado original foi preservado para rollback." "OK"
    }
    Write-AchillesMessage "Na primeira abertura, confirme a confiança no workspace para habilitar agentes, tarefas e ferramentas." "INFO"
    return [pscustomobject]@{
        Version = $resolvedVersion
        Executable = $executablePath
        Config = $configPath
        Launcher = $launcherPath
    }
}

Export-ModuleMember -Function Write-AchillesConfiguration, Copy-AchillesLegacyState, Test-AchillesArtifact, Get-AchillesVersion, Install-Achilles
