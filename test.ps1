Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "scripts/test.ps1") @args
exit $LASTEXITCODE
