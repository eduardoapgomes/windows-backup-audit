<#
.SYNOPSIS
Mede o tempo do backup (primeira execução, execução sem mudanças e com poucas mudanças)
e, opcionalmente, compara com a versão 1 do programa.

.DESCRIPTION
Usa pastas temporárias e Robocopy real. A verificação física do HD USB é desligada
SOMENTE dentro deste processo de medição (o servidor de testes não tem HD USB). Na
versão 1, a verificação de disco simulada remove o seu custo por arquivo, o que
favorece a versão 1 na comparação.

.EXAMPLE
.\tests\Comparar-Desempenho.ps1 -Arquivos 1500
.\tests\Comparar-Desempenho.ps1 -VersaoAnterior C:\temp\v1   # pasta com src\ da versão 1
#>
[CmdletBinding()]
param([int]$Arquivos = 1500, [int]$Grandes = 4, [int]$MBGrande = 25, [string]$VersaoAnterior = '')
$ErrorActionPreference = 'Stop'
$raiz = Join-Path ([IO.Path]::GetTempPath()) ('wba-desempenho-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
$origem = Join-Path $raiz 'origem'
$aleatorio = New-Object Random 11
$conteudo = New-Object byte[] 8192
for ($i = 0; $i -lt $Arquivos; $i++) {
    $pasta = Join-Path $origem ('pasta{0:D3}' -f ($i % 30))
    if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Force -Path $pasta | Out-Null }
    $aleatorio.NextBytes($conteudo)
    [IO.File]::WriteAllBytes((Join-Path $pasta "arquivo$i.bin"), $conteudo)
}
$grande = New-Object byte[] ($MBGrande * 1MB)
for ($i = 0; $i -lt $Grandes; $i++) {
    $aleatorio.NextBytes($grande)
    [IO.File]::WriteAllBytes((Join-Path $origem "video$i.mp4"), $grande)
}
$totalMB = [math]::Round(($Arquivos * 8KB + $Grandes * $MBGrande * 1MB) / 1MB)
Write-Host "Conjunto: $($Arquivos + $Grandes) arquivos, $totalMB MB"

function Measure-Segundos([scriptblock]$Bloco) {
    $relogio = [Diagnostics.Stopwatch]::StartNew()
    $null = & $Bloco
    return [math]::Round($relogio.Elapsed.TotalSeconds, 1)
}
function Set-PoucasMudancas {
    for ($i = 0; $i -lt 10; $i++) {
        $p = Join-Path (Join-Path $origem ('pasta{0:D3}' -f ($i % 30))) "arquivo$i.bin"
        [IO.File]::AppendAllText($p, 'mudou')
    }
}

$resultados = [ordered]@{}

# ----- versão 2 (esta)
Import-Module (Join-Path $PSScriptRoot '..\src\Backup.Core.psm1') -Force -DisableNameChecking
& (Get-Module Backup.Core) {
    function script:Assert-DestinoSeguro { param($Destino, $Origens, [switch]$PermitirRaiz) [pscustomobject]@{ DiscoId = 'medicao'; Modelo = 'medição'; Rotulo = ''; Letra = 'C' } }
}
$destino2 = Join-Path $raiz 'hd-v2\BACKUP'
$config = ConvertFrom-TextoConfig (New-TextoConfig -Destino $destino2 -Origens @([pscustomobject]@{ Caminho = $origem; Nome = 'Dados' }))
Assert-Configuracao $config
$resultados['v2: primeiro backup'] = Measure-Segundos { Invoke-BackupWBA -Config $config -Destino $destino2 -Modo Backup 6>$null }
$resultados['v2: sem mudanças'] = Measure-Segundos { Invoke-BackupWBA -Config $config -Destino $destino2 -Modo Backup 6>$null }
Set-PoucasMudancas
$resultados['v2: 10 arquivos alterados'] = Measure-Segundos { Invoke-BackupWBA -Config $config -Destino $destino2 -Modo Backup 6>$null }
Remove-Module Backup.Core

# ----- versão 1 (opcional)
if ($VersaoAnterior) {
    try {
        Import-Module (Join-Path $VersaoAnterior 'src\Backup.Core.psm1') -Force -DisableNameChecking
        & (Get-Module Backup.Core) {
            function script:Assert-ExternalDestination { param($Destination, $Sources, $ExpectedIdentity) @{ DiskId = 'medicao'; VolumeId = 'medicao'; FreeBytes = 1TB; Drive = 'Z:\' } }
        }
        $destino1 = Join-Path $raiz 'hd-v1\BACKUP'
        $fontes = @(@{ Id = 'Dados'; Path = $origem })
        $resultados['v1: primeiro backup'] = Measure-Segundos { Invoke-BackupPlan -Sources $fontes -Destination $destino1 -Mode Backup 6>$null }
        $resultados['v1: sem mudanças'] = Measure-Segundos { Invoke-BackupPlan -Sources $fontes -Destination $destino1 -Mode Backup 6>$null }
        Set-PoucasMudancas
        $resultados['v1: 10 arquivos alterados'] = Measure-Segundos { Invoke-BackupPlan -Sources $fontes -Destination $destino1 -Mode Backup 6>$null }
    } catch { $resultados['v1: falhou'] = $_.Exception.Message }
}

Remove-Item -LiteralPath $raiz -Recurse -Force -ErrorAction SilentlyContinue
$linha = ($resultados.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value) s" }) -join ' | '
Write-Host ''
$resultados.GetEnumerator() | ForEach-Object { Write-Host ('{0,-28} {1} s' -f $_.Key, $_.Value) }
if ($env:GITHUB_ACTIONS) { Write-Host "::notice title=Desempenho - $($Arquivos + $Grandes) arquivos e $totalMB MB::$linha" }
