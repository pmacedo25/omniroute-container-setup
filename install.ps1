$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repository = "pmacedo25/omniroute-container-setup"
$releaseApi = "https://api.github.com/repos/$repository/releases/latest"
$stateDirectory = Join-Path $env:USERPROFILE ".omniroute"
$installDirectory = Join-Path $stateDirectory "setup"
$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) (
    "omniroute-setup-" + [Guid]::NewGuid().ToString("N")
)
$archivePath = Join-Path $temporaryDirectory "source.zip"
$extractDirectory = Join-Path $temporaryDirectory "source"

Write-Host "OmniRoute: preparando o instalador mais recente..." -ForegroundColor Cyan

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    New-Item -ItemType Directory -Path $temporaryDirectory, $extractDirectory -Force | Out-Null
    $release = Invoke-RestMethod -Uri $releaseApi -Headers @{
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    if ([string]::IsNullOrWhiteSpace([string]$release.zipball_url)) {
        throw "O release público mais recente não informou um pacote de código-fonte."
    }

    Write-Host "Baixando OmniRoute Setup $($release.tag_name) do GitHub..."
    Invoke-WebRequest -Uri $release.zipball_url -OutFile $archivePath -Headers @{
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDirectory -Force

    $sourceDirectory = @(Get-ChildItem -LiteralPath $extractDirectory -Directory)
    if ($sourceDirectory.Count -ne 1) {
        throw "O pacote do release deve conter exatamente um diretório raiz."
    }
    $sourceDirectory = $sourceDirectory[0].FullName
    $requiredFiles = @(
        "setup-interativo.ps1",
        "docker-compose.yml",
        "combos-config.json",
        ".env.example",
        "scripts\OmniRoute.Setup.psm1",
        "scripts\Achilles.Setup.psm1",
        "skills-sync\Dockerfile",
        "skills-sync\entrypoint.sh",
        "skills-sync\sync-lib.sh"
    )
    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceDirectory $requiredFile) -PathType Leaf)) {
            throw "Pacote de instalação inválido: arquivo ausente '$requiredFile'."
        }
    }

    New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceDirectory -Force | ForEach-Object {
        # O .env local contém a AppKey e sempre prevalece em atualizações.
        if ($_.Name -ne ".env") {
            Copy-Item -LiteralPath $_.FullName `
                -Destination (Join-Path $installDirectory $_.Name) -Recurse -Force
        }
    }

    $setupPath = Join-Path $installDirectory "setup-interativo.ps1"
    $windowsPowerShell = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
        $windowsPowerShell = "powershell.exe"
    }

    Write-Host "Iniciando o instalador assistido..." -ForegroundColor Green
    & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File $setupPath
    if ($LASTEXITCODE -ne 0) {
        throw "O instalador terminou com o código $LASTEXITCODE."
    }
} finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
