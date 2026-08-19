Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Write-Phase "1/8" "Checking Docker"
Assert-Docker

if (-not (Test-Path -LiteralPath $Script:EnvFile)) {
    Copy-Item (Join-Path $Script:RepoRoot ".env.example") $Script:EnvFile
    Write-Host "Created $Script:EnvFile from .env.example"
}

Write-Phase "2/8" "Building Generation 0 substrate"
Invoke-Docker @("compose", "--project-directory", $Script:RepoRoot, "--file", (Join-Path $Script:RepoRoot "compose.yaml"), "build", "pi")

Write-Phase "3/8" "Creating persistent volumes"
foreach ($volume in @($Script:SourceVolume, $Script:AgentVolume, $Script:EvolutionVolume)) {
    if (-not (Test-DockerVolume $volume)) { Invoke-Docker @("volume", "create", $volume) }
}

$mounts = Get-BaseMountArguments
$dockerArguments = @("run", "--rm", "--user", "root", "--entrypoint", "bash") + $mounts + @(
    $Script:PiImage, "-lc",
    "mkdir -p /pi /home/pi/.pi-agent/bin /evolution/generations /evolution/observations /evolution/evaluations && chown -R pi:pi /pi /home/pi/.pi-agent /evolution"
)
Invoke-Docker $dockerArguments

Write-Phase "4/8" "Initializing persistent Pi source"
$containerScripts = Join-Path $Script:RepoRoot "scripts/container"
$dockerArguments = @("run", "--rm", "--entrypoint", "bash") + $mounts + @(
    "--env", "PI_GIT_NAME=$Script:PiGitName", "--env", "PI_GIT_EMAIL=$Script:PiGitEmail",
    "--volume", "${containerScripts}:/opt/pi-evolving:ro",
    $Script:PiImage, "/opt/pi-evolving/init-source.sh"
)
Invoke-Docker $dockerArguments

Write-Phase "5/8" "Installing Pi dependencies"
Invoke-Maintenance "cd /pi && npm install --ignore-scripts"
Write-Phase "6/8" "Building Pi"
Invoke-Maintenance "cd /pi && npm run build"
Write-Phase "7/8" "Running Pi checks"
Invoke-Maintenance "cd /pi && npm run check"

Write-Phase "8/8" "Installing evolution policy and recording Generation 0"
$policyPath = (Join-Path $Script:RepoRoot "config/AGENTS.md")
$hostPlatform = [System.Environment]::OSVersion.Platform.ToString()
$dockerArguments = @("run", "--rm", "--entrypoint", "bash") + $mounts + @(
    "--volume", "${containerScripts}:/opt/pi-evolving:ro",
    "--volume", "${policyPath}:/tmp/pi-evolving-AGENTS.md:ro",
    "--env", "PI_HOST_PLATFORM=$hostPlatform",
    $Script:PiImage, "/opt/pi-evolving/install-policy.sh"
)
Invoke-Docker $dockerArguments

Write-Host "`nSetup complete.`n  Run Pi:  .\pi.ps1 C:\path\to\project`n  Shell:   .\shell.ps1`n  Tests:   .\test.ps1"
