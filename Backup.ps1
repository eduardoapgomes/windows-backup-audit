#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config,
    [ValidateSet('Audit','Backup')][string]$Mode = 'Audit',
    [switch]$SelectDestination,
    [switch]$Setup,
    [switch]$OpenReport
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
    if ($Setup) { New-BackupConfiguration -Path $Config; exit 0 }
    if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
        throw "Configuração não encontrada: $Config. Execute Iniciar.cmd e escolha Configurar, ou use -Setup para selecionar suas pastas."
    }
    Assert-BackupDependencies $Mode
    $plan = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
    $destination = $null
    if ($plan.PSObject.Properties['Destination']) { $destination = [string]$plan.Destination }
    if ($SelectDestination -or [string]::IsNullOrWhiteSpace($destination)) {
        $destination = Select-BackupDestination @($plan.Sources | ForEach-Object { $_.Path })
    }
    $report = Invoke-BackupPlan -Sources $plan.Sources -Destination $destination -Mode $Mode
    if ($OpenReport -and $report -and (Test-Path -LiteralPath (Join-Path $report 'LEIA-ME.html'))) {
        Start-Process -FilePath (Join-Path $report 'LEIA-ME.html')
    }
    $report
} catch { Write-Error $_ -ErrorAction Continue; exit 2 }
