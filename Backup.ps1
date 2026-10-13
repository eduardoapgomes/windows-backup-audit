#Requires -Version 5.1
<#
.SYNOPSIS
Backup sistemático de pastas pessoais para um HD externo, conferido por SHA-256.

.DESCRIPTION
Ações (-Acao):
  Backup      copia o que é novo ou mudou e confere cada cópia (padrão)
  Simular     mostra o que seria feito, sem gravar nada no HD
  Verificar   relê o HD e confere cada arquivo com o SHA-256 registrado
  Configurar  cria ou edita configuracao.txt (pastas e HD)
  Agendar     cria ou remove o backup automático no Agendador de Tarefas
  Relatorio   abre o último relatório gravado no HD

Códigos de saída: 0 tudo certo; 1 avisos (arquivos só na nuvem); 2 erros ou
interrompido; 3 não executado (configuração, HD ausente ou cancelado).

O programa nunca apaga arquivos: nem na origem, nem no HD de backup.

.EXAMPLE
.\Backup.ps1 -Acao Simular

.EXAMPLE
.\Backup.ps1 -Acao Backup

.EXAMPLE
.\Backup.ps1 -Acao Verificar -Amostra 10
Confere cerca de 10% dos arquivos do HD, escolhidos ao acaso.
#>
[CmdletBinding()]
param(
    [ValidateSet('Backup', 'Simular', 'Verificar', 'Configurar', 'Agendar', 'Relatorio')][string]$Acao = 'Backup',
    [string]$Config,
    [ValidateRange(1, 128)][int]$Threads = 8,
    [ValidateRange(1, 100)][int]$Amostra = 100,
    [switch]$Automatico,
    [switch]$SemAbrirRelatorio
)
$ErrorActionPreference = 'Stop'
$codigo = 3
$motivo = ''
$transcricao = $false
try {
    $modulo = Join-Path (Join-Path $PSScriptRoot 'src') 'Backup.Core.psm1'
    if (-not (Test-Path -LiteralPath $modulo -PathType Leaf)) {
        throw "Arquivo do programa ausente: $modulo. Extraia o ZIP completo em uma pasta nova (docs\ATUALIZAR.md)."
    }
    Import-Module $modulo -Force -DisableNameChecking
    if (-not $Config) { $Config = Join-Path $PSScriptRoot 'configuracao.txt' }
    elseif (-not [IO.Path]::IsPathRooted($Config)) { $Config = Join-Path $PSScriptRoot $Config }

    if ($Automatico) {
        # Execução agendada: guarda um log local, mesmo que o HD não esteja conectado.
        $pastaLog = Join-Path (Join-Path $env:LOCALAPPDATA 'WindowsBackupAudit') 'logs'
        New-Item -ItemType Directory -Force -Path $pastaLog | Out-Null
        Start-Transcript -Path (Join-Path $pastaLog ('{0:yyyy-MM-dd_HH-mm-ss}.log' -f (Get-Date))) | Out-Null
        $transcricao = $true
    }

    if ($Acao -eq 'Configurar') {
        Invoke-AssistenteConfiguracao -Caminho $Config -PastaPrograma $PSScriptRoot
        $codigo = 0
    } elseif ($Acao -eq 'Agendar') {
        Invoke-AssistenteAgendamento -Script $PSCommandPath
        $codigo = 0
    } else {
        if (-not (Test-Path -LiteralPath $Config -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'backup.local.json'))) {
            throw 'Esta versão usa configuracao.txt. Abra Iniciar.cmd e escolha Configurar: suas pastas da versão anterior serão importadas.'
        }
        $cfg = Read-Configuracao $Config
        $origens = [string[]]@($cfg.Origens | ForEach-Object { $_.Caminho })
        $destino = Resolve-Destino -Configurado $cfg.Destino -Origens $origens -Automatico:$Automatico
        if ($destino -ne $cfg.Destino) { Write-Etapa "O HD de backup foi encontrado em $($destino.Substring(0, 2))" Cyan }
        $resumo = $null
        switch ($Acao) {
            'Relatorio' { Open-UltimoRelatorio $destino; $codigo = 0 }
            'Verificar' {
                $resumo = Invoke-VerificacaoWBA -Destino $destino -Origens $origens -Amostra $Amostra
            }
            'Simular' {
                Write-Etapa 'SIMULAÇÃO: nada será gravado no HD.' Cyan
                $resumo = Invoke-BackupWBA -Config $cfg -Destino $destino -Modo Simular -PastaSimulacao (Join-Path $PSScriptRoot 'relatorios')
            }
            'Backup' {
                $continuar = $true
                if (-not (Test-PastaDeBackup $destino)) {
                    if ($Automatico) { throw "Ainda não há backup em $destino. Faça o primeiro backup pelo menu (Iniciar.cmd)." }
                    Write-Host "Primeiro backup neste HD. Será criada a pasta: $destino" -ForegroundColor Cyan
                    $continuar = (Read-Host 'Continuar? (S/N)') -match '^[sS]'
                }
                if ($continuar) {
                    $resumo = Invoke-BackupWBA -Config $cfg -Destino $destino -Modo Backup -Threads $Threads
                } else { $motivo = 'Cancelado. Nada foi feito.'; Write-Host $motivo }
            }
        }
        if ($null -ne $resumo) {
            Show-Resumo $resumo
            $codigo = $resumo.CodigoSaida
            $motivo = $resumo.Falha
            if ($resumo.Modo -ne 'Simular' -and $resumo.Relatorio -and -not $Automatico -and -not $SemAbrirRelatorio) {
                try { Start-Process -FilePath $resumo.Relatorio } catch { Write-Host "Abra o relatório: $($resumo.Relatorio)" }
            }
        }
    }
} catch {
    $motivo = $_.Exception.Message
    Write-Host ''
    Write-Host "NÃO EXECUTADO: $motivo" -ForegroundColor Red
    $codigo = 3
} finally {
    if ($transcricao) { try { Stop-Transcript | Out-Null } catch { Write-Verbose 'transcrição já encerrada' } }
}

if ($Automatico -and $codigo -ne 0 -and [Environment]::UserInteractive) {
    # Backup agendado com problema: avisa na tela (ninguém está olhando o console).
    $mensagem = switch ($codigo) {
        1 { 'Backup concluído com avisos: há arquivos só na nuvem que não foram copiados. Veja o relatório no HD.' }
        2 { "O backup terminou com ERROS ou foi interrompido. Abra Iniciar.cmd > Abrir o último relatório.`n$motivo" }
        default { "O backup agendado NÃO foi feito.`n$motivo" }
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($mensagem, 'Windows Backup Audit', 'OK', 'Warning')
    } catch { Write-Verbose 'Sem interface para o aviso.' }
}
exit $codigo
