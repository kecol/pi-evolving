param([switch]$Rebase)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Assert-Initialized
if ($Rebase) {
    Invoke-ContainerScript "update.sh" @("--rebase")
} else {
    Invoke-ContainerScript "update.sh"
}
