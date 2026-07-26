param([ValidateSet("status", "dashboard", "ide", "logs", "restart", "pull", "doctor")][string]$Action = "status")

$stateDirectory = Join-Path $env:USERPROFILE ".omniroute"
$mode = if (Test-Path (Join-Path $stateDirectory "mode.container")) { "container" } else { "local" }
$engine = if (Get-Command podman -ErrorAction SilentlyContinue) { "podman" } else { "docker" }

switch ($Action) {
    "status" {
        try {
            Invoke-RestMethod "http://localhost:20128/api/monitoring/health" -TimeoutSec 5 | ConvertTo-Json -Depth 5
        } catch { Write-Error "OmniRoute indisponível: $($_.Exception.Message)" }
    }
    "dashboard" { Start-Process "http://localhost:20128/dashboard" }
    "ide" {
        $launcher = Join-Path $env:USERPROFILE ".openrouterai\OpenRouterAI.ps1"
        if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
            throw "OpenRouterAI não está instalado. Reexecute o setup sem -SkipOpenRouterAI."
        }
        & $launcher
    }
    "logs" {
        if ($mode -eq "container") { & $engine logs --tail 100 -f omniroute }
        else { Get-ScheduledTaskInfo -TaskName "OmniRoute Gateway" }
    }
    "restart" {
        if ($mode -eq "container") { & $engine restart omniroute }
        else { Stop-ScheduledTask "OmniRoute Gateway" -ErrorAction SilentlyContinue; Start-ScheduledTask "OmniRoute Gateway" }
    }
    "pull" {
        if ($mode -eq "container") { & $engine restart omniroute-setup-skills-sync-1 }
        else { git -C (Join-Path $stateDirectory "skills") pull --ff-only }
    }
    "doctor" {
        if ($mode -eq "container") { & $engine exec omniroute node healthcheck.mjs }
        else { & omniroute doctor --json }
        $current = Join-Path $env:USERPROFILE ".openrouterai\current.json"
        if (Test-Path -LiteralPath $current -PathType Leaf) {
            $ide = Get-Content -LiteralPath $current -Raw | ConvertFrom-Json
            Write-Host "OpenRouterAI $($ide.version): $($ide.executable)"
        } else {
            Write-Warning "OpenRouterAI ainda não foi instalado."
        }
    }
}
