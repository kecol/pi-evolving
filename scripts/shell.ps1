Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Assert-Initialized

$runningNames = @(& docker ps --format '{{.Names}}')
if ($LASTEXITCODE -ne 0) { throw "Could not query running Docker containers." }
if ($runningNames -contains $Script:ContainerName) {
    Invoke-Docker @("exec", "-it", $Script:ContainerName, "bash")
    exit
}
$dockerArguments = @("run", "--rm", "-it", "--entrypoint", "bash")
$dockerArguments += Get-BaseMountArguments
$dockerArguments += $Script:PiImage
Invoke-Docker $dockerArguments
