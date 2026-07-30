[CmdletBinding()]
param(
    [ValidateSet("container", "local")]
    [string]$Mode,
    [string]$SkillsRepository = "nio-internet/agents-templates",
    [string]$SkillsBranch = "main",
    [string]$SkillsPath,
    [int]$Port = 20128,
    [Alias("OpenRouterAIRepository")]
    [string]$AchillesRepository = "pmacedo25/Achilles-Releases",
    [Alias("OpenRouterAIVersion")]
    [string]$AchillesVersion = "latest",
    [Alias("OpenRouterAIArtifactPath")]
    [string]$AchillesArtifactPath,
    [switch]$NonInteractive,
    [Alias("SkipOpenRouterAI")]
    [switch]$SkipAchilles,
    [switch]$SkipProviderLogin,
    [string]$CorporateCAPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot "scripts\OmniRoute.Setup.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "scripts\Achilles.Setup.psm1") -Force -DisableNameChecking

if ([string]::IsNullOrWhiteSpace($Mode)) {
    if ($NonInteractive) {
        $Mode = "container"
    } else {
        Write-Host "OmniRoute: selecione o modo [1=container, 2=local] (padrão: 1)"
        $selection = Read-Host
        $Mode = if ($selection -eq "2") { "local" } else { "container" }
    }
}

$setupOptions = @{
    Mode              = $Mode
    SetupDirectory    = $PSScriptRoot
    SkillsRepository  = $SkillsRepository
    SkillsBranch      = $SkillsBranch
    SkillsPath        = $SkillsPath
    Port              = $Port
    AchillesRepository = $AchillesRepository
    AchillesVersion = $AchillesVersion
    AchillesArtifactPath = $AchillesArtifactPath
    NonInteractive    = $NonInteractive.IsPresent
    SkipAchilles  = $SkipAchilles.IsPresent
    SkipProviderLogin = $SkipProviderLogin.IsPresent
    CorporateCAPath = $CorporateCAPath
}

Invoke-OmniRouteSetup @setupOptions
