param(
    [ValidateSet("qwen3.8-27b")][string]$Model
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Write-Phase "1/11" "Checking Docker"
Assert-Docker

Write-Phase "2/11" "Checking requested model"
if ($Model -eq "qwen3.8-27b") {
    $qwenProfilePath = Join-Path $Script:RepoRoot "models/qwen3.8-27b/models.json"
    $qwenProfile = Get-Content -LiteralPath $qwenProfilePath -Raw | ConvertFrom-Json
    $qwenProvider = $qwenProfile.providers.'llamacpp-wsl'
    $qwenHostBaseUrl = $qwenProvider.baseUrl.Replace("host.docker.internal", "localhost")
    $qwenModelId = $qwenProvider.models[0].id
    $headers = @{ Authorization = "Bearer $($qwenProvider.apiKey)" }
    try {
        $models = Invoke-RestMethod -Method Get -Uri "$qwenHostBaseUrl/models" -Headers $headers -TimeoutSec 10
    } catch {
        throw "Qwen3.8 llama-server is unavailable at $qwenHostBaseUrl. Start scripts/models/qwen3.8-27b/serve.sh in WSL2, then retry. $($_.Exception.Message)"
    }
    $modelIds = @($models.data | ForEach-Object { $_.id })
    if ($modelIds -notcontains $qwenModelId) {
        throw "The llama.cpp endpoint responded, but model alias '$qwenModelId' was not listed."
    }
    Write-Host "Found model alias: $qwenModelId"
} else {
    Write-Host "No explicit model profile requested; continuing with Pi model selection."
}

if (-not (Test-Path -LiteralPath $Script:EnvFile)) {
    Copy-Item (Join-Path $Script:RepoRoot ".env.example") $Script:EnvFile
    Write-Host "Created $Script:EnvFile from .env.example"
}

Write-Phase "3/11" "Building Generation 0 substrate"
Invoke-Docker @("compose", "--project-directory", $Script:RepoRoot, "--file", (Join-Path $Script:RepoRoot "compose.yaml"), "build", "pi")

Write-Phase "4/11" "Creating persistent volumes"
foreach ($volume in @($Script:SourceVolume, $Script:AgentVolume, $Script:EvolutionVolume)) {
    if (-not (Test-DockerVolume $volume)) { Invoke-Docker @("volume", "create", $volume) }
}

$mounts = Get-BaseMountArguments
$dockerArguments = @("run", "--rm", "--user", "root", "--entrypoint", "bash") + $mounts + @(
    $Script:PiImage, "-lc",
    "mkdir -p /pi /home/pi/.pi-agent/bin /evolution/generations /evolution/observations /evolution/evaluations && chown -R pi:pi /pi /home/pi/.pi-agent /evolution"
)
Invoke-Docker $dockerArguments

Write-Phase "5/11" "Initializing persistent Pi source"
$containerScripts = Join-Path $Script:RepoRoot "scripts/container"
$dockerArguments = @("run", "--rm", "--entrypoint", "bash") + $mounts + @(
    "--env", "PI_GIT_NAME=$Script:PiGitName", "--env", "PI_GIT_EMAIL=$Script:PiGitEmail",
    "--volume", "${containerScripts}:/opt/pi-evolving:ro",
    $Script:PiImage, "/opt/pi-evolving/init-source.sh"
)
Invoke-Docker $dockerArguments

Write-Phase "6/11" "Installing Pi dependencies"
Invoke-Maintenance "cd /pi && npm install --ignore-scripts"
Write-Phase "7/11" "Building Pi"
Invoke-Maintenance "cd /pi && npm run build"
Write-Phase "8/11" "Running Pi checks"
Invoke-Maintenance "cd /pi && npm run check"

Write-Phase "9/11" "Installing evolution policy and recording Generation 0"
$policyPath = (Join-Path $Script:RepoRoot "config/AGENTS.md")
$hostPlatform = [System.Environment]::OSVersion.Platform.ToString()
$dockerArguments = @("run", "--rm", "--entrypoint", "bash") + $mounts + @(
    "--volume", "${containerScripts}:/opt/pi-evolving:ro",
    "--volume", "${policyPath}:/tmp/pi-evolving-AGENTS.md:ro",
    "--env", "PI_HOST_PLATFORM=$hostPlatform",
    $Script:PiImage, "/opt/pi-evolving/install-policy.sh"
)
Invoke-Docker $dockerArguments

Write-Phase "10/11" "Installing agent evolution capabilities"
if ($Script:PiAgentEvolutionPath) {
    Install-AgentEvolutionIfConfigured
} else {
    Write-Host "No agent evolution repository configured."
}

Write-Phase "11/11" "Configuring requested model"
if ($Model -eq "qwen3.8-27b") {
    & (Join-Path $PSScriptRoot "local-model.ps1") -Profile "qwen3.8-27b" -SmokeTest
} else {
    Write-Host "No explicit model profile requested."
}

Write-Host "`nSetup complete.`n  Run Pi:  .\pi.ps1 C:\path\to\project`n  Shell:   .\shell.ps1`n  Tests:   .\test.ps1"
