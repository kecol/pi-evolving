param([switch]$SkipCheck)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

Assert-Initialized
$mounts = Get-BaseMountArguments
$containerScripts = Join-Path $Script:RepoRoot "scripts/container"
$modelTemplate = Join-Path $Script:RepoRoot "config/models.llamacpp-wsl.json"
$skipValue = if ($SkipCheck) { "1" } else { "0" }

$dockerArguments = @("run", "--rm", "--entrypoint", "bash") + $mounts + @(
    "--volume", "${containerScripts}:/opt/pi-evolving:ro",
    "--volume", "${modelTemplate}:/tmp/pi-evolving-models.json:ro",
    "--env", "PI_SKIP_LOCAL_MODEL_CHECK=$skipValue",
    $Script:PiImage, "/opt/pi-evolving/install-local-model.sh"
)
Invoke-Docker $dockerArguments

function Set-DotEnvValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    $lines = if (Test-Path -LiteralPath $Path) { @(Get-Content -LiteralPath $Path) } else { @() }
    $found = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^$([regex]::Escape($Name))=") {
            $lines[$index] = "$Name=$Value"
            $found = $true
        }
    }
    if (-not $found) { $lines += "$Name=$Value" }
    $text = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $text, $utf8WithoutBom)
}

Set-DotEnvValue $Script:EnvFile "PI_PROVIDER" "llamacpp-wsl"
Set-DotEnvValue $Script:EnvFile "PI_MODEL" "local-coder"

Write-Host "`nLocal model preset enabled."
Write-Host "Run: .\pi.ps1 C:\path\to\project"
