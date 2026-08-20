Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:RepoRoot = Split-Path -Parent $PSScriptRoot
$Script:EnvFile = Join-Path $Script:RepoRoot ".env"

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $parts = $trimmed.Split("=", 2)
        if ($parts.Count -ne 2) { continue }
        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') {
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

Import-DotEnv $Script:EnvFile

$Script:PiImage = if ($env:PI_IMAGE) { $env:PI_IMAGE } else { "pi-evolving:local" }
$Script:PiProvider = if ($env:PI_PROVIDER) { $env:PI_PROVIDER } else { "" }
$Script:PiModel = if ($env:PI_MODEL) { $env:PI_MODEL } else { "" }
$Script:PiHostPort = if ($env:PI_HOST_PORT) { $env:PI_HOST_PORT } else { "9191" }
$Script:PiContainerPort = if ($env:PI_CONTAINER_PORT) { $env:PI_CONTAINER_PORT } else { "9191" }
$Script:PiGitName = if ($env:PI_GIT_NAME) { $env:PI_GIT_NAME } else { "Pi Evolving Agent" }
$Script:PiGitEmail = if ($env:PI_GIT_EMAIL) { $env:PI_GIT_EMAIL } else { "pi-evolving@local" }
$Script:PiAgentEvolutionPath = if ($env:PI_AGENT_EVOLUTION_PATH) { $env:PI_AGENT_EVOLUTION_PATH } else { "" }
$Script:PiAgentAutoInstall = if ($env:PI_AGENT_AUTO_INSTALL) { $env:PI_AGENT_AUTO_INSTALL } else { "1" }
$Script:SourceVolume = "pi-evolving-source"
$Script:AgentVolume = "pi-evolving-agent-state"
$Script:EvolutionVolume = "pi-evolving-evolution-state"
$Script:ContainerName = "pi-evolving"

function Write-Phase {
    param([string]$Number, [string]$Message)
    Write-Host "`n[$Number] $Message"
}

function Invoke-Docker {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed with exit code $LASTEXITCODE." }
}

function Assert-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker is not installed or is not on PATH."
    }
    & docker version *> $null
    if ($LASTEXITCODE -ne 0) { throw "Docker is installed, but its daemon is unavailable." }
}

function Test-DockerImage {
    param([Parameter(Mandatory)][string]$Reference)
    $imageIds = @(& docker image ls --quiet $Reference)
    if ($LASTEXITCODE -ne 0) { throw "Could not query Docker images." }
    return $imageIds.Count -gt 0
}

function Test-DockerVolume {
    param([Parameter(Mandatory)][string]$Name)
    $volumeNames = @(& docker volume ls --quiet --filter "name=$Name")
    if ($LASTEXITCODE -ne 0) { throw "Could not query Docker volumes." }
    return $volumeNames -contains $Name
}

function Assert-Initialized {
    Assert-Docker
    if (-not (Test-DockerImage $Script:PiImage)) {
        throw "Image '$Script:PiImage' is missing. Run .\setup.ps1 first."
    }
    if (-not (Test-DockerVolume $Script:SourceVolume)) {
        throw "Pi source volume is missing. Run .\setup.ps1 first."
    }
}

function Get-BaseMountArguments {
    $arguments = @(
        "--add-host", "host.docker.internal:host-gateway",
        "--volume", "${Script:SourceVolume}:/pi",
        "--volume", "${Script:AgentVolume}:/home/pi/.pi-agent",
        "--volume", "${Script:EvolutionVolume}:/evolution"
    )
    if ($Script:PiAgentEvolutionPath) {
        if (-not [System.IO.Path]::IsPathFullyQualified($Script:PiAgentEvolutionPath)) {
            throw "PI_AGENT_EVOLUTION_PATH must be an absolute path."
        }
        if (-not (Test-Path -LiteralPath $Script:PiAgentEvolutionPath -PathType Container)) {
            throw "Agent evolution directory does not exist: $Script:PiAgentEvolutionPath"
        }
        $agentPath = (Resolve-Path -LiteralPath $Script:PiAgentEvolutionPath).Path
        $arguments += @("--volume", "${agentPath}:/agent")
    }
    return $arguments
}

function Invoke-Maintenance {
    param([Parameter(Mandatory)][string]$Command)
    $dockerArguments = @("run", "--rm", "--entrypoint", "bash")
    $dockerArguments += Get-BaseMountArguments
    $dockerArguments += @($Script:PiImage, "-lc", $Command)
    Invoke-Docker $dockerArguments
}

function Invoke-ContainerScript {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$ScriptArguments = @()
    )
    $containerScripts = Join-Path $Script:RepoRoot "scripts/container"
    $dockerArguments = @("run", "--rm", "--entrypoint", "bash")
    $dockerArguments += Get-BaseMountArguments
    $dockerArguments += @(
        "--volume", "${containerScripts}:/opt/pi-evolving:ro",
        $Script:PiImage, "/opt/pi-evolving/$Name"
    )
    $dockerArguments += $ScriptArguments
    Invoke-Docker $dockerArguments
}

function Install-AgentEvolutionIfConfigured {
    if (-not $Script:PiAgentEvolutionPath) { return }
    switch -Regex ($Script:PiAgentAutoInstall) {
        '^(1|true|yes)$' { Invoke-ContainerScript -Name "agent-evolution.sh" -ScriptArguments @("install"); return }
        '^(0|false|no)$' { Write-Host "Agent evolution auto-install is disabled."; return }
        default { throw "PI_AGENT_AUTO_INSTALL must be 1 or 0 (also accepts true/false or yes/no)." }
    }
}
