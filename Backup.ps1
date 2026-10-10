#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config,
    [ValidateSet('Plan','Audit','Backup')][string]$Mode = 'Audit',
    [switch]$SelectDestination,
    [switch]$Setup,
    [switch]$OpenReport,
    [switch]$AutoDiscover,
    [ValidateSet('Auto','Exclude','Include')][string]$DependencyPolicy='Auto'
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
    if (-not $AutoDiscover -and -not (Test-Path -LiteralPath $Config -PathType Leaf)) {
        throw "Configuração não encontrada: $Config. Execute Iniciar.cmd e escolha Configurar, ou use -Setup para selecionar suas pastas."
    }
    if ($Mode -ne 'Plan') { Assert-BackupDependencies $Mode }
    $options = @{}
    if ($AutoDiscover) {
        $plan = Get-AutomaticBackupPlan
        $options = @{Discovery=$plan.Discovery;ExcludedPaths=$plan.ExcludedPaths;Scope='Descoberta automática'}
    } else { $plan = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json }
    if ($Mode -eq 'Plan') {
        Write-Host ''
        Write-Host 'PLANO RAPIDO (somente metadados de pastas; nenhum hash, copia ou USB necessario):'
        $plan.Sources | Format-Table Id,Path -AutoSize | Out-Host
        Write-Host 'IMPORTANTE: o plano nao garante cobertura. Confira pastas fora da lista, arquivos soltos e dados de aplicativos.'
        Write-Host 'Para acrescentar outras pastas, use a configuracao manual do menu.'
        exit 0
    }
    $destination = $null
    if ($plan.PSObject.Properties['Destination']) { $destination = [string]$plan.Destination }
    if ($SelectDestination -or [string]::IsNullOrWhiteSpace($destination)) {
        $destination = Select-BackupDestination @($plan.Sources | ForEach-Object { $_.Path })
    }
    $report = Invoke-BackupPlan -Sources $plan.Sources -Destination $destination -Mode $Mode -OpenReport:$OpenReport -DependencyPolicy $DependencyPolicy @options

    $report
} catch { Write-Error $_ -ErrorAction Continue; exit 2 }
