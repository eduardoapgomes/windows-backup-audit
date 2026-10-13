# =============================================================================
# Assistentes interativos do menu (Configurar e Agendar). Perguntas simples,
# respostas por número. Todo o resto do programa funciona sem perguntas.
# =============================================================================

function Set-DestinoNoTexto {
    # Troca só a linha do destino, preservando o resto do arquivo (comentários e edições).
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Texto, [Parameter(Mandatory)][string]$Destino)
    $linhas = New-Object 'Collections.Generic.List[string]'
    foreach ($l in ($Texto -split "\r?\n")) { $linhas.Add($l) }
    $inicio = -1
    for ($i = 0; $i -lt $linhas.Count; $i++) { if ($linhas[$i].Trim() -match '^\[DESTINO\]$') { $inicio = $i; break } }
    if ($inicio -lt 0) {
        $linhas.Insert(0, '')
        $linhas.Insert(0, $Destino)
        $linhas.Insert(0, '[DESTINO]')
    } else {
        $trocou = $false
        for ($i = $inicio + 1; $i -lt $linhas.Count; $i++) {
            $t = $linhas[$i].Trim()
            if ($t.StartsWith('[')) { break }
            if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
            $linhas[$i] = $Destino; $trocou = $true; break
        }
        if (-not $trocou) { $linhas.Insert($inicio + 1, $Destino) }
    }
    return ($linhas -join "`r`n")
}

function Show-Configuracao {
    param([Parameter(Mandatory)]$Config)
    Write-Host ''
    Write-Host 'DESTINO' -ForegroundColor Cyan
    if ($Config.Destino) { Write-Host "  $($Config.Destino)" } else { Write-Host '  (nenhum HD escolhido)' -ForegroundColor Yellow }
    Write-Host 'PASTAS QUE SERÃO COPIADAS' -ForegroundColor Cyan
    foreach ($o in $Config.Origens) { Write-Host ('  {0,-24} <- {1}' -f $o.Nome, $o.Caminho) }
    Write-Host ("Exclusões: {0} padrões de pasta, {1} de arquivo." -f $Config.ExcluirPastas.Count, $Config.ExcluirArquivos.Count) -ForegroundColor DarkGray
    Write-Host ''
}

function Wait-EdicaoNoBlocoDeNotas {
    param([Parameter(Mandatory)][string]$Caminho)
    if (-not $script:EhWindows) { return }
    # O Bloco de Notas do Windows 11 não informa quando é fechado; por isso perguntamos.
    Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $Caminho + '"')
    Read-Host 'Revise o arquivo no Bloco de Notas, SALVE (Ctrl+S) e pressione Enter aqui' | Out-Null
}

function Test-ConfiguracaoComMensagem {
    param([Parameter(Mandatory)][string]$Caminho)
    try {
        $config = Read-Configuracao $Caminho
        Show-Configuracao $config
        if (-not $config.Destino) {
            Write-Host 'Falta escolher o HD de destino: abra Configurar de novo e escolha "Trocar o HD".' -ForegroundColor Yellow
            return $false
        }
        Write-Host 'Configuração válida. Próximo passo: Simular (mostra o que será copiado) e depois Fazer backup.' -ForegroundColor Green
        return $true
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host 'Abra Configurar de novo para corrigir.' -ForegroundColor Yellow
        return $false
    }
}

function Invoke-AssistenteConfiguracao {
    param([Parameter(Mandatory)][string]$Caminho, [Parameter(Mandatory)][string]$PastaPrograma)
    if (Test-Path -LiteralPath $Caminho -PathType Leaf) {
        $config = $null
        try { $config = Read-Configuracao $Caminho; Show-Configuracao $config }
        catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
        Write-Host "Arquivo: $Caminho"
        Write-Host '  1. Editar as pastas no Bloco de Notas'
        Write-Host '  2. Trocar o HD de destino'
        Write-Host '  0. Voltar'
        switch (Read-Host 'Opção') {
            '1' { Wait-EdicaoNoBlocoDeNotas $Caminho; $null = Test-ConfiguracaoComMensagem $Caminho }
            '2' {
                $origens = @()
                if ($config) { $origens = @($config.Origens | ForEach-Object { $_.Caminho }) }
                $destino = Select-DestinoInterativo $origens
                Save-TextoConfig $Caminho (Set-DestinoNoTexto (Read-TextoConfig $Caminho) $destino)
                Write-Host "Destino: $destino" -ForegroundColor Green
                $null = Test-ConfiguracaoComMensagem $Caminho
            }
        }
        return
    }

    Write-Host 'Procurando suas pastas de dados (só confere se existem; nada é lido)...'
    $sugestao = Get-OrigensSugeridas -ConfigAntiga (Join-Path $PastaPrograma 'backup.local.json')
    if ($sugestao.Importada) { Write-Host 'Importei as pastas da versão anterior (backup.local.json).' -ForegroundColor Green }
    foreach ($o in $sugestao.Origens) { Write-Host "  + $($o.Caminho)" }
    $destino = $sugestao.Destino
    if (-not $destino) {
        Write-Host ''
        Write-Host 'Agora escolha o HD externo que vai receber o backup.'
        try { $destino = Select-DestinoInterativo @($sugestao.Origens | ForEach-Object { $_.Caminho }) }
        catch { Write-Host $_.Exception.Message -ForegroundColor Yellow; $destino = '' }
    }
    Save-TextoConfig $Caminho (New-TextoConfig -Destino $destino -Origens $sugestao.Origens)
    Write-Host ''
    Write-Host "Configuração criada: $Caminho" -ForegroundColor Green
    Write-Host 'Confira a lista de pastas: apague as que não quer e acrescente as que faltam (uma por linha).'
    Wait-EdicaoNoBlocoDeNotas $Caminho
    $null = Test-ConfiguracaoComMensagem $Caminho
}

function Invoke-AssistenteAgendamento {
    param([Parameter(Mandatory)][string]$Script)
    $atual = Get-BackupAgendado
    if ($atual) {
        Write-Host "Backup agendado. Próxima execução: $($atual.ProximaExecucao)" -ForegroundColor Green
        if ($atual.UltimaExecucao -and $atual.UltimaExecucao.Year -gt 2000) { Write-Host "Última execução: $($atual.UltimaExecucao) (código $($atual.UltimoResultado))" }
    } else { Write-Host 'Nenhum backup agendado.' }
    Write-Host ''
    Write-Host '  1. Toda semana'
    Write-Host '  2. Todo dia'
    Write-Host '  3. Remover o agendamento'
    Write-Host '  0. Voltar'
    $opcao = Read-Host 'Opção'
    if ($opcao -eq '3') {
        if (Unregister-BackupAgendado) { Write-Host 'Agendamento removido.' -ForegroundColor Green } else { Write-Host 'Não havia agendamento.' }
        return
    }
    if ($opcao -ne '1' -and $opcao -ne '2') { return }
    $dia = 'Domingo'
    if ($opcao -eq '1') {
        $nomes = @($script:DiasSemana.Keys)
        for ($i = 0; $i -lt $nomes.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $nomes[$i]) }
        $n = 0
        if ([int]::TryParse((Read-Host 'Dia da semana (Enter = 1, domingo)'), [ref]$n) -and $n -ge 1 -and $n -le 7) { $dia = $nomes[$n - 1] }
    }
    $hora = Read-Host 'Horário, por exemplo 20:00 (Enter = 20:00)'
    if (-not $hora) { $hora = '20:00' }
    if ($hora -notmatch '^\d{1,2}:\d{2}$') { throw "Horário inválido: $hora. Use o formato 20:00." }
    $frequencia = if ($opcao -eq '1') { 'Semanal' } else { 'Diario' }
    $tarefa = Register-BackupAgendado -Frequencia $frequencia -Hora $hora -Dia $dia -Script $Script
    Write-Host "Backup agendado. Próxima execução: $($tarefa.ProximaExecucao)" -ForegroundColor Green
    Write-Host 'Deixe o HD conectado nesse horário. Se ele não estiver, aparece um aviso e nada é feito.'
}
