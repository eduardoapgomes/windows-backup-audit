#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config,
    [ValidateSet('Audit','Backup')][string]$Mode = 'Audit',
    [switch]$SelectDestination
)
cd $PSScriptRoot
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\src\Backup.Core.psm1" -Force
try {
    if ([string]::IsNullOrWhiteSpace($Config)) {
        $Config = Join-Path -Path $PSScriptRoot -ChildPath 'backup.local.json'
    } elseif (-not [IO.Path]::IsPathRooted($Config)) {
        $Config = Join-Path -Path $PSScriptRoot -ChildPath $Config
    }
    if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
        throw "Configuração não encontrada: $Config. Copie backup.example.json para backup.local.json e ajuste suas pastas."
    }
    Assert-BackupDependencies $Mode
    $plan = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
    $destination = $null
    if ($plan.PSObject.Properties['Destination']) { $destination = [string]$plan.Destination }
    if ($SelectDestination -or [string]::IsNullOrWhiteSpace($destination)) {
        $destination = Select-BackupDestination @($plan.Sources | ForEach-Object { $_.Path })
    }
    Invoke-BackupPlan -Sources $plan.Sources -Destination $destination -Mode $Mode
} catch { Write-Error $_ -ErrorAction Continue; exit 2 }
