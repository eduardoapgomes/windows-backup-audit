# =============================================================================
# Agendamento: uma tarefa do Agendador de Tarefas do Windows, só para o usuário
# atual (não exige administrador). Se o computador estiver desligado no horário,
# o backup roda quando ele ligar. Se o HD não estiver conectado, aparece um aviso.
# =============================================================================

$script:NomeTarefa = 'Windows Backup Audit'
$script:DiasSemana = [ordered]@{
    Domingo = 'Sunday'; Segunda = 'Monday'; Terca = 'Tuesday'; Quarta = 'Wednesday'
    Quinta = 'Thursday'; Sexta = 'Friday'; Sabado = 'Saturday'
}

function Get-BackupAgendado {
    $tarefa = Get-ScheduledTask -TaskName $script:NomeTarefa -ErrorAction SilentlyContinue
    if (-not $tarefa) { return $null }
    $info = Get-ScheduledTaskInfo -TaskName $script:NomeTarefa -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Nome = $script:NomeTarefa
        Estado = [string]$tarefa.State
        ProximaExecucao = if ($info) { $info.NextRunTime } else { $null }
        UltimaExecucao = if ($info) { $info.LastRunTime } else { $null }
        UltimoResultado = if ($info) { $info.LastTaskResult } else { $null }
    }
}

function Register-BackupAgendado {
    param(
        [ValidateSet('Diario', 'Semanal')][string]$Frequencia = 'Semanal',
        [ValidatePattern('^\d{1,2}:\d{2}$')][string]$Hora = '20:00',
        [ValidateSet('Domingo', 'Segunda', 'Terca', 'Quarta', 'Quinta', 'Sexta', 'Sabado')][string]$Dia = 'Domingo',
        [Parameter(Mandatory)][string]$Script
    )
    $quando = [datetime]::ParseExact($Hora, [string[]]@('H:mm', 'HH:mm'), [Globalization.CultureInfo]::InvariantCulture, 'None')
    if ($Frequencia -eq 'Diario') { $gatilho = New-ScheduledTaskTrigger -Daily -At $quando }
    else { $gatilho = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $script:DiasSemana[$Dia] -At $quando }
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$Script`" -Acao Backup -Automatico"
    $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentos -WorkingDirectory (Split-Path -Parent $Script)
    $opcoes = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 12) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $script:NomeTarefa -Action $acao -Trigger $gatilho -Settings $opcoes -Force `
        -Description 'Backup das pastas configuradas para o HD externo (windows-backup-audit).' | Out-Null
    return Get-BackupAgendado
}

function Unregister-BackupAgendado {
    if (Get-ScheduledTask -TaskName $script:NomeTarefa -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $script:NomeTarefa -Confirm:$false
        return $true
    }
    return $false
}
