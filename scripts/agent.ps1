param(
    [ValidateSet("status", "install", "history")]
    [Parameter(Position = 0)][string]$Command = "status",
    [switch]$WorkingTree
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

if (-not $Script:PiAgentEvolutionPath) {
    throw "Set PI_AGENT_EVOLUTION_PATH in .env to your agent-evolution repository."
}
if ($WorkingTree -and $Command -ne "install") {
    throw "-WorkingTree is valid only with the install command."
}
Assert-Initialized
$agentArguments = @($Command)
if ($WorkingTree) { $agentArguments += "--working-tree" }
Invoke-ContainerScript -Name "agent-evolution.sh" -ScriptArguments $agentArguments
