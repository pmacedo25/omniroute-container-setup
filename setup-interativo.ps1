[CmdletBinding()]
param(
    [ValidateSet("container", "local")]
    [string]$Mode,
    [string]$SkillsRepository,
    [string]$SkillsBranch = "main",
    [Alias("WorkspacePath")]
    [string]$ProjectsPath,
    [int]$Port = 20128,
    [Alias("OpenRouterAIRepository")]
    [string]$AchillesRepository = "pmacedo25/Achilles",
    [Alias("OpenRouterAIVersion")]
    [string]$AchillesVersion = "latest",
    [Alias("OpenRouterAIArtifactPath")]
    [string]$AchillesArtifactPath,
    [switch]$NonInteractive,
    [switch]$SkipDesktopApp,
    [Alias("SkipOpenRouterAI")]
    [switch]$SkipAchilles,
    [switch]$SkipProviderLogin
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

$defaultProjectsPath = Join-Path $env:USERPROFILE "workspace"
if ([string]::IsNullOrWhiteSpace($ProjectsPath)) {
    if ($NonInteractive) {
        $ProjectsPath = $defaultProjectsPath
    } else {
        Write-Host "Informe a pasta local onde os projetos serão criados"
        $projectsInput = Read-Host "Path (padrão: $defaultProjectsPath)"
        $ProjectsPath = if ([string]::IsNullOrWhiteSpace($projectsInput)) {
            $defaultProjectsPath
        } else {
            $projectsInput.Trim().Trim('"')
        }
    }
}

$defaultSkillsRepository = "https://github.com/pmacedo25/project-agents-templates.git"
if ([string]::IsNullOrWhiteSpace($SkillsRepository)) {
    if ($NonInteractive) {
        $SkillsRepository = $defaultSkillsRepository
    } else {
        Write-Host "Informe a URL Git do repositório de skills"
        $repositoryInput = Read-Host "URL (padrão: $defaultSkillsRepository)"
        $SkillsRepository = if ([string]::IsNullOrWhiteSpace($repositoryInput)) {
            $defaultSkillsRepository
        } else {
            $repositoryInput.Trim()
        }
    }
}

$setupOptions = @{
    Mode              = $Mode
    SetupDirectory    = $PSScriptRoot
    SkillsRepository  = $SkillsRepository
    SkillsBranch      = $SkillsBranch
    ProjectsPath      = $ProjectsPath
    Port              = $Port
    AchillesRepository = $AchillesRepository
    AchillesVersion = $AchillesVersion
    AchillesArtifactPath = $AchillesArtifactPath
    NonInteractive    = $NonInteractive.IsPresent
    SkipDesktopApp    = $SkipDesktopApp.IsPresent
    SkipAchilles  = $SkipAchilles.IsPresent
    SkipProviderLogin = $SkipProviderLogin.IsPresent
}

Invoke-OmniRouteSetup @setupOptions
