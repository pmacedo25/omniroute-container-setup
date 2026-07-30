param([ValidateSet("status", "dashboard", "ide", "logs", "restart", "pull", "doctor")][string]$Action = "status")

$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$global:OutputEncoding = $utf8
$engine = if (Get-Command podman -ErrorAction SilentlyContinue) { "podman" } else { "docker" }

switch ($Action) {
    "status" {
        try {
            Invoke-RestMethod "http://localhost:20128/api/monitoring/health" -TimeoutSec 5 | ConvertTo-Json -Depth 5
        } catch { Write-Error "OmniRoute indisponível: $($_.Exception.Message)" }
    }
    "dashboard" { Start-Process "http://localhost:20128/dashboard" }
    "ide" {
        $launcher = Join-Path $env:USERPROFILE ".achilles\Achilles.ps1"
        if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
            throw "Achilles não está instalado. Reexecute o setup sem -SkipAchilles."
        }
        & $launcher
    }
    "logs" {
        & $engine logs --tail 100 -f omniroute
    }
    "restart" {
        & $engine restart omniroute
    }
    "pull" {
        & $engine restart omniroute-setup-skills-sync-1
    }
    "doctor" {
        & $engine exec omniroute node healthcheck.mjs
        $current = Join-Path $env:USERPROFILE ".achilles\current.json"
        if (Test-Path -LiteralPath $current -PathType Leaf) {
            $ide = Get-Content -LiteralPath $current -Raw | ConvertFrom-Json
            Write-Host "Achilles $($ide.version): $($ide.executable)"
        } else {
            Write-Warning "Achilles ainda não foi instalado."
        }
    }
}
