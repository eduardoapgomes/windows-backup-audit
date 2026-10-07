# Progress belongs to the host stream, never to inventory/function output.
$script:BackupProgress = $null
function Start-BackupProgress {
    param([string]$Mode)
    $script:BackupProgress = @{Started=[DateTime]::UtcNow;LastHost=[DateTime]::MinValue;LastBar=[DateTime]::MinValue;Files=0;Bytes=[long]0;Phase=$Mode;AuditFiles=0;AuditBytes=[long]0;Results=@{};LastPartial=[DateTime]::MinValue}
    Write-Host "[$Mode] Iniciando. Ctrl+C interrompe a execução; uma execução interrompida não confirma cobertura."
}
function Show-BackupProgress {
    param([string]$Phase, [string]$Path='', [long]$ReadBytes=0, [long]$TotalBytes=0, [switch]$FileCompleted)
    if ($null -eq $script:BackupProgress) { return }
    $state = $script:BackupProgress
    if ($FileCompleted) { $state.Files++; $state.Bytes += $TotalBytes }
    $now = [DateTime]::UtcNow
    $changed = $Phase -ne $state.Phase
    $state.Phase = $Phase
    if (($now - $state.LastPartial).TotalSeconds -ge 5) {
        Write-BackupPartial -Phase $Phase -Path $Path -ReadBytes $ReadBytes -TotalBytes $TotalBytes
        $state.LastPartial=$now
    }
    if (($now - $state.LastBar).TotalMilliseconds -ge 500) {
        $percent = if ($TotalBytes -gt 0) { [int][math]::Min(100, 100.0 * $ReadBytes / $TotalBytes) } else { -1 }
        $status = "Leituras concluídas: $($state.Files) | Decorrido: $(([TimeSpan]($now - $state.Started)).ToString('hh\:mm\:ss'))"
        Write-Progress -Id 1 -Activity $Phase -Status $status -CurrentOperation $Path -PercentComplete $percent
        $state.LastBar = $now
    }
    if (($now - $state.LastHost).TotalSeconds -ge 5) {
        Write-Host ("[{0:HH:mm:ss}] {1} | {2} leituras | leitura atual {3:N1}/{4:N1} MiB | {5}" -f (Get-Date),$Phase,$state.Files,($ReadBytes/1MB),($TotalBytes/1MB),$Path)
        $state.LastHost = $now
    }
}
function Stop-BackupProgress {
    if ($null -ne $script:BackupProgress) {
        Write-Progress -Id 1 -Activity 'Execução encerrada' -Completed
        $script:BackupProgress = $null
    }
}
