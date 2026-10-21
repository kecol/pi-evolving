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

function Add-ReadOnlyMount {
    param(
        [Parameter(Mandatory)][string]$HostPath,
        [Parameter(Mandatory)][string]$ContainerPath
    )
    if (-not (Test-Path -LiteralPath $HostPath -PathType Container)) {
        throw "Read-only host directory does not exist: $HostPath"
    }
    if (-not $ContainerPath.StartsWith("/") -or $ContainerPath.StartsWith("//") -or
        $ContainerPath.Contains(":") -or
        $ContainerPath.Contains("\") -or
        "/$ContainerPath/".Contains("/../") -or "/$ContainerPath/".Contains("/./")) {
        throw "Read-only container path must be an absolute normalized Linux path: $ContainerPath"
    }
    $normalizedTarget = $ContainerPath.TrimEnd("/")
    if (-not $normalizedTarget) { $normalizedTarget = "/" }
    if ($normalizedTarget -eq "/" -or
        $normalizedTarget -match '^/(pi|agent|workspace|evolution)(/|$)' -or
        $normalizedTarget -match '^/home/pi(/|$)') {
        throw "Read-only container path overlaps a managed Pi location: $normalizedTarget"
    }
    if (-not $readOnlyTargets.Add($normalizedTarget)) {
        throw "Duplicate read-only container path: $normalizedTarget"
    }
    $resolvedHostPath = (Resolve-Path -LiteralPath $HostPath).Path
    return @("--volume", "${resolvedHostPath}:${normalizedTarget}:ro")
}

$readOnlyMountArguments = @()
$readOnlyTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
if ($Script:PiReadonlyHostPath -or $Script:PiReadonlyContainerPath) {
    if (-not $Script:PiReadonlyHostPath -or -not $Script:PiReadonlyContainerPath) {
        throw "PI_READONLY_HOST_PATH and PI_READONLY_CONTAINER_PATH must be configured together."
    }
    $environmentHostPath = if ([System.IO.Path]::IsPathRooted($Script:PiReadonlyHostPath)) {
        $Script:PiReadonlyHostPath
    } else {
        Join-Path $Script:RepoRoot $Script:PiReadonlyHostPath
    }
    $readOnlyMountArguments += Add-ReadOnlyMount $environmentHostPath $Script:PiReadonlyContainerPath
}

$forwardedArguments = @()
for ($index = 0; $index -lt @($PiArguments).Count;) {
    $argument = $PiArguments[$index]
    if ($argument -eq "--read-only-mount") {
        if ($index + 2 -ge @($PiArguments).Count) {
            throw "--read-only-mount requires a host path and a container path."
        }
        $readOnlyMountArguments += Add-ReadOnlyMount $PiArguments[$index + 1] $PiArguments[$index + 2]
        $index += 3
    } elseif ($argument -eq "--") {
        if ($index + 1 -lt @($PiArguments).Count) {
            $forwardedArguments += $PiArguments[($index + 1)..(@($PiArguments).Count - 1)]
        }
        break
    } else {
        $forwardedArguments += $argument
        $index++
    }
}

Assert-Initialized
Install-AgentEvolutionIfConfigured

$dockerArguments = @("run", "--rm", "-it", "--name", $Script:ContainerName)
$dockerArguments += Get-BaseMountArguments
$dockerArguments += $readOnlyMountArguments
$dockerArguments += @(
    "--volume", "${workspacePath}:/workspace",
    "--publish", "127.0.0.1:${Script:PiHostPort}:${Script:PiContainerPort}",
    "--env", "PI_SKIP_VERSION_CHECK=1",
    $Script:PiImage
)
if ($Script:PiProvider) { $dockerArguments += @("--provider", $Script:PiProvider) }
if ($Script:PiModel) { $dockerArguments += @("--model", $Script:PiModel) }
if ($forwardedArguments) { $dockerArguments += $forwardedArguments }
Invoke-Docker $dockerArguments
