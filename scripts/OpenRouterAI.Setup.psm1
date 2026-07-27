$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$script:OpenRouterAIConfigSchemaVersion = 1
$script:OpenRouterAIDefaultRepository = "pmacedo25/OpenRouterAI"

function Write-OpenRouterAIMessage {
    param([string]$Message, [ValidateSet("INFO", "OK", "WARN")][string]$Level = "INFO")
    $color = switch ($Level) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        default { "Cyan" }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Get-OpenRouterAIArchitecture {
    $architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    if ($architecture -ne "x64") {
        throw "O protótipo OpenRouterAI suporta somente Windows x64; arquitetura detectada: $architecture."
    }
    return $architecture
}

function Write-OpenRouterAIConfiguration {
    param(
        [string]$HomeDirectory,
        [string]$ProjectsDirectory,
        [int]$OmniRoutePort
    )
    $stateDirectory = Join-Path $HomeDirectory ".openrouterai"
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $configuration = [ordered]@{
        schemaVersion = $script:OpenRouterAIConfigSchemaVersion
        omnirouteBaseUrl = "http://127.0.0.1:$OmniRoutePort/v1"
        omnirouteHealthUrl = "http://127.0.0.1:$OmniRoutePort/api/monitoring/health"
        apiKeyEnvironmentVariable = "OMNIROUTE_API_KEY"
        workspace = $ProjectsDirectory
        defaultCombo = "combo-coding"
        allowedCombos = @("combo-testing", "combo-coding", "combo-refining")
        telemetry = $false
    }
    $configPath = Join-Path $stateDirectory "config.json"
    $temporaryPath = "$configPath.new"
    $configuration | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporaryPath -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $configPath -Force
    return $configPath
}

function Get-OpenRouterAIRelease {
    param(
        [string]$Repository,
        [string]$Version,
        [string]$Destination
    )
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        throw "GitHub CLI é necessário para baixar o release privado do OpenRouterAI."
    }
    & $gh.Source auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI não está autenticado. Execute 'gh auth login --git-protocol https --web' e reexecute."
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $arguments = @(
        "release", "download", "--repo", $Repository,
        "--pattern", "OpenRouterAI-win-x64-*.zip",
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
    $artifacts = @(Get-ChildItem -LiteralPath $Destination -Filter "OpenRouterAI-win-x64-*.zip" -File)
    if ($artifacts.Count -ne 1) {
        throw "O release deve conter exatamente um artefato OpenRouterAI-win-x64-*.zip."
    }
    return $artifacts[0].FullName
}

function Test-OpenRouterAIArtifact {
    param([string]$ArtifactPath, [string]$Sha256SumsPath)
    if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
        throw "Artefato OpenRouterAI não encontrado: $ArtifactPath"
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

function Get-OpenRouterAIVersion {
    param([string]$ArtifactPath, [string]$ManifestPath)
    if (-not [string]::IsNullOrWhiteSpace($ManifestPath) -and
        (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        if ($manifest.version -and "$($manifest.version)" -match "^\d+\.\d+\.\d+([-.][0-9A-Za-z.-]+)?$") {
            return "$($manifest.version)"
        }
    }
    $name = Split-Path -Leaf $ArtifactPath
    if ($name -match "OpenRouterAI-win-x64-(?<version>\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?)\.zip") {
        return $Matches.version
    }
    throw "Não foi possível determinar a versão SemVer do artefato '$name'."
}

function New-OpenRouterAILauncher {
    param(
        [string]$HomeDirectory,
        [string]$InstallRoot,
        [string]$ProjectsDirectory
    )
    $stateDirectory = Join-Path $HomeDirectory ".openrouterai"
    $launcherPath = Join-Path $stateDirectory "OpenRouterAI.ps1"
    $launcher = @"
`$ErrorActionPreference = "Stop"
`$stateDirectory = "$stateDirectory"
`$current = Get-Content -LiteralPath (Join-Path `$stateDirectory "current.json") -Raw | ConvertFrom-Json
`$executable = [IO.Path]::GetFullPath(`$current.executable)
`$allowedRoot = [IO.Path]::GetFullPath("$InstallRoot").TrimEnd("\") + "\"
if (-not `$executable.StartsWith(`$allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OpenRouterAI executable outside the managed install directory."
}
if (-not (Test-Path -LiteralPath `$executable -PathType Leaf)) {
    throw "OpenRouterAI executable not found. Re-run the OmniRoute installer."
}
`$env:OPENROUTERAI_CONFIG = Join-Path `$stateDirectory "config.json"
`$env:OPENAI_API_KEY = `$env:OMNIROUTE_API_KEY
Start-Process -FilePath `$executable -ArgumentList @("$ProjectsDirectory")
"@
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding utf8
    return $launcherPath
}

function New-OpenRouterAIShortcuts {
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
        (Join-Path $desktopDirectory "OpenRouterAI.lnk"),
        (Join-Path $startMenuDirectory "OpenRouterAI.lnk")
    )) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $powerShellPath
        $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LauncherPath`""
        $shortcut.WorkingDirectory = $WorkingDirectory
        $shortcut.WindowStyle = 1
        $shortcut.IconLocation = "$IconPath,0"
        $shortcut.Description = "OpenRouterAI via OmniRoute"
        $shortcut.Save()
    }
}

function Install-OpenRouterAI {
    [CmdletBinding()]
    param(
        [string]$HomeDirectory,
        [string]$ProjectsDirectory,
        [int]$OmniRoutePort,
        [string]$Repository = $script:OpenRouterAIDefaultRepository,
        [string]$Version = "latest",
        [AllowEmptyString()][string]$ArtifactPath,
        [string]$FallbackIconPath
    )
    [void](Get-OpenRouterAIArchitecture)
    $stateDirectory = Join-Path $HomeDirectory ".openrouterai"
    $installRoot = Join-Path $env:LOCALAPPDATA "Programs\OpenRouterAI"
    $downloadDirectory = Join-Path $stateDirectory "downloads"
    New-Item -ItemType Directory -Path $stateDirectory, $installRoot, $downloadDirectory -Force | Out-Null

    if ([string]::IsNullOrWhiteSpace($ArtifactPath)) {
        $ArtifactPath = Get-OpenRouterAIRelease -Repository $Repository -Version $Version `
            -Destination $downloadDirectory
    } else {
        $ArtifactPath = [IO.Path]::GetFullPath(
            [Environment]::ExpandEnvironmentVariables($ArtifactPath)
        )
    }
    $artifactDirectory = Split-Path -Parent $ArtifactPath
    $sumsPath = Join-Path $artifactDirectory "SHA256SUMS"
    $manifestPath = Join-Path $artifactDirectory "release-manifest.json"
    [void](Test-OpenRouterAIArtifact -ArtifactPath $ArtifactPath -Sha256SumsPath $sumsPath)
    $resolvedVersion = Get-OpenRouterAIVersion -ArtifactPath $ArtifactPath -ManifestPath $manifestPath
    $versionDirectory = Join-Path $installRoot $resolvedVersion
    $stagingDirectory = Join-Path $installRoot ".staging-$resolvedVersion"

    $installedExecutables = @(if (Test-Path -LiteralPath $versionDirectory) {
        @(Get-ChildItem -LiteralPath $versionDirectory -Recurse -Filter "OpenRouterAI.exe" -File)
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
        $executables = @(Get-ChildItem -LiteralPath $stagingDirectory -Recurse -Filter "OpenRouterAI.exe" -File)
        if ($executables.Count -ne 1) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
            throw "O artefato deve conter exatamente um OpenRouterAI.exe."
        }
        if (Test-Path -LiteralPath $versionDirectory) {
            Remove-Item -LiteralPath $versionDirectory -Recurse -Force
        }
        $relativeExecutable = $executables[0].FullName.Substring($stagingDirectory.Length).TrimStart("\")
        Move-Item -LiteralPath $stagingDirectory -Destination $versionDirectory
        $executablePath = Join-Path $versionDirectory $relativeExecutable
    }

    $configPath = Write-OpenRouterAIConfiguration -HomeDirectory $HomeDirectory `
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

    $iconPath = Join-Path $stateDirectory "OpenRouterAI.ico"
    if (Test-Path -LiteralPath $FallbackIconPath -PathType Leaf) {
        Copy-Item -LiteralPath $FallbackIconPath -Destination $iconPath -Force
    } else {
        $iconPath = $executablePath
    }
    $launcherPath = New-OpenRouterAILauncher -HomeDirectory $HomeDirectory `
        -InstallRoot $installRoot -ProjectsDirectory $ProjectsDirectory
    New-OpenRouterAIShortcuts -LauncherPath $launcherPath -IconPath $iconPath `
        -WorkingDirectory $ProjectsDirectory
    Write-OpenRouterAIMessage "OpenRouterAI $resolvedVersion instalado sem elevação." "OK"
    Write-OpenRouterAIMessage "Na primeira abertura, confirme a confiança no workspace para habilitar agentes, tarefas e ferramentas." "INFO"
    return [pscustomobject]@{
        Version = $resolvedVersion
        Executable = $executablePath
        Config = $configPath
        Launcher = $launcherPath
    }
}

Export-ModuleMember -Function Write-OpenRouterAIConfiguration, Test-OpenRouterAIArtifact, Get-OpenRouterAIVersion, Install-OpenRouterAI
