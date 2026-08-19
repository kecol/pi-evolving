param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet("agent-state", "source", "evolution", "all")]
    [string]$Target
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Assert-Docker

$volumes = switch ($Target) {
    "agent-state" { @($Script:AgentVolume) }
    "source" { @($Script:SourceVolume) }
    "evolution" { @($Script:EvolutionVolume) }
    "all" { @($Script:SourceVolume, $Script:AgentVolume, $Script:EvolutionVolume) }
}
Write-Host "This will permanently delete $Target persistent data. The workspace will not be touched."
$confirmation = Read-Host "Type '$Target' to confirm"
if ($confirmation -ne $Target) { throw "Reset cancelled." }

$containerNames = & docker ps -a --format '{{.Names}}'
if ($containerNames -contains $Script:ContainerName) {
    throw "Container '$Script:ContainerName' exists. Stop it before resetting state."
}
foreach ($volume in $volumes) {
    if (Test-DockerVolume $volume) { Invoke-Docker @("volume", "rm", $volume) }
}
Write-Host "Reset complete. Run .\setup.ps1 to recreate required state."
