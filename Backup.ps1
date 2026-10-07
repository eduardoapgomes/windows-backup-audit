#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = "$PSScriptRoot\backup.local.json",
    [ValidateSet('Audit','Backup')][string]$Mode = 'Audit',
    [switch]$SelectDestination
)
cd $PSScriptRoot
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\src\Backup.Core.psm1" -Force
try {
    Assert-BackupDependencies $Mode
    $plan = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
    $destination = $null
    if ($plan.PSObject.Properties['Destination']) { $destination = [string]$plan.Destination }
    if ($SelectDestination -or [string]::IsNullOrWhiteSpace($destination)) {
        $destination = Select-BackupDestination @($plan.Sources | ForEach-Object { $_.Path })
    }
    Invoke-BackupPlan -Sources $plan.Sources -Destination $destination -Mode $Mode
} catch { Write-Error $_ -ErrorAction Continue; exit 2 }
