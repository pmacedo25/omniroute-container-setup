[CmdletBinding()]
param(
    [string]$SkillsRepository = "nio-internet/agents-templates",
    [string]$SkillsBranch = "main",
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
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$global:OutputEncoding = $utf8

Import-Module (Join-Path $PSScriptRoot "scripts\OmniRoute.Setup.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot "scripts\Achilles.Setup.psm1") -Force -DisableNameChecking

$setupOptions = @{
    SetupDirectory    = $PSScriptRoot
    SkillsRepository  = $SkillsRepository
    SkillsBranch      = $SkillsBranch
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
