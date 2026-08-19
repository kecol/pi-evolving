Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "scripts/shell.ps1") @args
exit $LASTEXITCODE
