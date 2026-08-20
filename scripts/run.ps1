param(
    [Parameter(Mandatory, Position = 0)][string]$Workspace,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$PiArguments
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

if (-not (Test-Path -LiteralPath $Workspace -PathType Container)) {
    throw "Workspace directory does not exist: $Workspace"
}
$workspacePath = (Resolve-Path -LiteralPath $Workspace).Path
Assert-Initialized
Install-AgentEvolutionIfConfigured

$dockerArguments = @("run", "--rm", "-it", "--name", $Script:ContainerName)
$dockerArguments += Get-BaseMountArguments
$dockerArguments += @(
    "--volume", "${workspacePath}:/workspace",
    "--publish", "127.0.0.1:${Script:PiHostPort}:${Script:PiContainerPort}",
    "--env", "PI_SKIP_VERSION_CHECK=1",
    $Script:PiImage
)
if ($Script:PiProvider) { $dockerArguments += @("--provider", $Script:PiProvider) }
if ($Script:PiModel) { $dockerArguments += @("--model", $Script:PiModel) }
if ($PiArguments) { $dockerArguments += $PiArguments }
Invoke-Docker $dockerArguments
