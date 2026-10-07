#Requires -Version 5.1
[CmdletBinding()]
param([string]$Config = "$PSScriptRoot\backup.local.json", [ValidateSet('Audit','Backup')][string]$Mode = 'Audit')
cd $PSScriptRoot
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\src\Backup.Core.psm1" -Force
try {
    $plan = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
    Invoke-BackupPlan -Sources $plan.Sources -Destination $plan.Destination -Mode $Mode
} catch { Write-Error $_ -ErrorAction Continue; exit 2 }
