# =============================================================================
# Relatórios: RELATORIO.html (para ler), detalhes.tsv (abre no Excel) e
# resumo.json (para scripts), em _CONTROLE\execucoes\<data>\.
# =============================================================================

function ConvertTo-TextoHtml { param([string]$Texto) return [Net.WebUtility]::HtmlEncode($Texto) }

$script:EstiloHtml = @'
<style>
:root{--fundo:#f4f6f9;--cartao:#fff;--texto:#18212f;--suave:#5b6577;--borda:#d8dde6;--ok:#17803d;--aviso:#a15c00;--erro:#b42318}
@media (prefers-color-scheme:dark){:root{--fundo:#12161d;--cartao:#1b212b;--texto:#e7ebf1;--suave:#9aa5b5;--borda:#2e3746;--ok:#4cc27a;--aviso:#f0a940;--erro:#ff7b6e}}
body{margin:0;background:var(--fundo);color:var(--texto);font:16px/1.55 "Segoe UI",system-ui,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px}
section{background:var(--cartao);border:1px solid var(--borda);border-radius:10px;padding:18px 22px;margin:16px 0}
h1{font-size:1.6em;margin:.2em 0}h2{font-size:1.2em;margin:.2em 0 .6em}
.faixa{border-left:6px solid var(--cor);padding-left:14px}.faixa p{margin:.3em 0}
.OK{--cor:var(--ok)}.AVISOS{--cor:var(--aviso)}.ERROS,.INTERROMPIDO{--cor:var(--erro)}
.selo{color:var(--cor);font-weight:700}
table{border-collapse:collapse;width:100%;font-size:.93em}
th,td{border-bottom:1px solid var(--borda);padding:6px 8px;text-align:left;vertical-align:top}
td.n,th.n{text-align:right;white-space:nowrap}
code{overflow-wrap:anywhere;font-size:.92em}
.suave{color:var(--suave)}
.rolar{overflow-x:auto}
dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 16px;margin:0}dt{color:var(--suave)}dd{margin:0;overflow-wrap:anywhere}
</style>
'@

function New-PaginaHtml {
    param([string]$Titulo, [string]$Situacao, [string]$Corpo)
    return "<!doctype html><html lang=""pt-BR""><head><meta charset=""utf-8""><meta name=""viewport"" content=""width=device-width,initial-scale=1"">" +
        "<title>$(ConvertTo-TextoHtml $Titulo)</title>$script:EstiloHtml</head><body><main class=""$Situacao"">$Corpo</main></body></html>"
}

function New-TabelaHtml {
    param([string[]]$Colunas, [object[]]$Linhas, [int[]]$Numericas = @())
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('<div class="rolar"><table><thead><tr>')
    for ($i = 0; $i -lt $Colunas.Count; $i++) {
        $classe = if ($Numericas -contains $i) { ' class="n"' } else { '' }
        [void]$sb.Append("<th$classe>$(ConvertTo-TextoHtml $Colunas[$i])</th>")
    }
    [void]$sb.Append('</tr></thead><tbody>')
    foreach ($linha in $Linhas) {
        [void]$sb.Append('<tr>')
        for ($i = 0; $i -lt $linha.Count; $i++) {
            $classe = if ($Numericas -contains $i) { ' class="n"' } else { '' }
            [void]$sb.Append("<td$classe>$(ConvertTo-TextoHtml ([string]$linha[$i]))</td>")
        }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table></div>')
    return $sb.ToString()
}

function Save-Html {
    param([string]$Caminho, [string]$Html)
    [IO.File]::WriteAllText($Caminho, $Html, (New-Object Text.UTF8Encoding($false)))
}

function Write-AtalhoUltimoRelatorio {
    # _CONTROLE\ULTIMO-RELATORIO.html abre o relatório mais recente.
    param([string]$Controle, [string]$Relativo)
    $alvo = ($Relativo -replace '\\', '/')
    $html = "<!doctype html><html lang=""pt-BR""><head><meta charset=""utf-8""><meta http-equiv=""refresh"" content=""0;url=$alvo""><title>Último relatório</title></head>" +
        "<body><p><a href=""$alvo"">Abrir o último relatório</a></p></body></html>"
    Save-Html (Join-Path $Controle 'ULTIMO-RELATORIO.html') $html
}

function Get-InfoDestinoHtml {
    param([string]$Destino, $Disco, [datetime]$Inicio)
    $duracao = (Get-Date) - $Inicio
    $hd = (@($Disco.Modelo, $Disco.Rotulo) | Where-Object { $_ }) -join ' - '
    return '<dl>' +
        "<dt>Início</dt><dd>$($Inicio.ToString('dd/MM/yyyy HH:mm:ss'))</dd>" +
        "<dt>Duração</dt><dd>$([int]$duracao.TotalHours)h $($duracao.Minutes)min $($duracao.Seconds)s</dd>" +
        "<dt>Destino</dt><dd><code>$(ConvertTo-TextoHtml $Destino)</code></dd>" +
        "<dt>HD</dt><dd>$(ConvertTo-TextoHtml $hd)</dd>" +
        "<dt>Computador</dt><dd>$(ConvertTo-TextoHtml "$env:COMPUTERNAME / $env:USERNAME")</dd>" +
        "<dt>Programa</dt><dd>windows-backup-audit $script:Versao</dd></dl>"
}

function Write-RelatorioBackup {
    param([string]$Execucao, [string]$Controle, [string]$Destino, $Disco, [string]$Situacao, [string]$Falha,
        [datetime]$Inicio, [object[]]$Contagens, [object[]]$Contextos)
    $limite = 300
    $erros = New-Object 'Collections.Generic.List[object]'
    $nuvem = New-Object 'Collections.Generic.List[object]'
    $totalErros = 0; $totalNuvem = 0
    foreach ($ctx in $Contextos) {
        $nome = $ctx.Origem.Nome
        foreach ($e in $ctx.Plano.Origem.Erros) { $totalErros++; if ($erros.Count -lt $limite) { $erros.Add(@($nome, $e[0], $e[1])) } }
        foreach ($lista in @($ctx.Plano.Novos, $ctx.Plano.Alterados, $ctx.Plano.Conferir)) {
            foreach ($a in $lista) {
                $msg = $null
                if ($a.Estado -eq 'ERRO') { $msg = $a.Mensagem }
                elseif (-not $a.Estado -and $Situacao -ne 'INTERROMPIDO') { $msg = 'Não foi processado.' }
                if ($null -ne $msg) { $totalErros++; if ($erros.Count -lt $limite) { $erros.Add(@($nome, $a.Relativo, $msg)) } }
            }
        }
        foreach ($a in $ctx.Plano.Nuvem) { $totalNuvem++; if ($nuvem.Count -lt $limite) { $nuvem.Add(@($nome, $a.Relativo, (Format-Tamanho $a.Bytes))) } }
    }

    switch ($Situacao) {
        'OK' { $titulo = 'Backup concluído e conferido'; $texto = 'Todos os arquivos das pastas configuradas estão no HD, conferidos por SHA-256.' }
        'AVISOS' { $titulo = 'Backup concluído com avisos'; $texto = "Há $totalNuvem arquivo(s) que estão só na nuvem e não foram copiados (lista abaixo). Todo o resto foi conferido." }
        'ERROS' { $titulo = 'Backup concluído com ERROS'; $texto = "$totalErros arquivo(s) ou pasta(s) NÃO estão no backup. Veja a lista abaixo e execute de novo depois de corrigir." }
        default { $titulo = 'Backup INTERROMPIDO'; $texto = "A execução parou antes do fim: $Falha Execute de novo: o que já foi conferido não será lido de novo." }
    }

    $linhas = New-Object 'Collections.Generic.List[object]'
    foreach ($c in $Contagens) {
        $linhas.Add(@($c.Nome, $c.Origem, ('{0:N0}' -f $c.Arquivos), (Format-Tamanho $c.Bytes), ('{0:N0}' -f $c.SemMudanca),
            ('{0:N0}' -f $c.Copiados), ('{0:N0}' -f $c.Atualizados), ('{0:N0}' -f $c.Movidos), ('{0:N0}' -f $c.Conferidos),
            ('{0:N0}' -f $c.Nuvem), ('{0:N0}' -f $c.Erros)))
    }
    $copiadoBytes = [long]0
    foreach ($c in $Contagens) { $copiadoBytes += $c.BytesCopiados }

    $corpo = New-Object Text.StringBuilder
    [void]$corpo.Append("<section class=""faixa""><h1 class=""selo"">$(ConvertTo-TextoHtml $titulo)</h1><p>$(ConvertTo-TextoHtml $texto)</p>")
    [void]$corpo.Append("<p class=""suave"">Copiado nesta execução: $(Format-Tamanho $copiadoBytes). Nada foi apagado na origem nem no backup.</p></section>")
    [void]$corpo.Append("<section>$(Get-InfoDestinoHtml $Destino $Disco $Inicio)</section>")
    [void]$corpo.Append('<section><h2>Pastas</h2>')
    [void]$corpo.Append((New-TabelaHtml @('Pasta no backup', 'Origem', 'Arquivos', 'Tamanho', 'Sem mudança', 'Copiados', 'Atualizados', 'Movidos', 'Conferidos', 'Só na nuvem', 'Erros') $linhas.ToArray() @(2, 3, 4, 5, 6, 7, 8, 9, 10)))
    [void]$corpo.Append('<p class="suave"><b>Sem mudança</b>: já estavam no backup, iguais (não foram lidos de novo). <b>Copiados</b>: novos. ' +
        '<b>Atualizados</b>: mudaram; a versão anterior está em <code>_VERSOES_ANTERIORES</code>. <b>Movidos</b>: só mudaram de pasta ou de nome. ' +
        '<b>Conferidos</b>: já estavam no HD e foram conferidos por SHA-256.</p></section>')
    if ($totalErros) {
        [void]$corpo.Append("<section><h2>Erros ($totalErros)</h2>")
        [void]$corpo.Append((New-TabelaHtml @('Pasta', 'Arquivo ou pasta', 'Motivo') $erros.ToArray()))
        if ($totalErros -gt $limite) { [void]$corpo.Append("<p class=""suave"">Mostrando $limite. A lista completa está em detalhes.tsv.</p>") }
        [void]$corpo.Append('<p>Causas comuns: arquivo aberto em outro programa (feche e execute de novo), pasta sem permissão ' +
            '(se não precisar dela, coloque o caminho em [EXCLUIR_PASTAS]) ou HD desconectado.</p></section>')
    }
    if ($totalNuvem) {
        [void]$corpo.Append("<section><h2>Só na nuvem, não copiados ($totalNuvem)</h2>")
        [void]$corpo.Append('<p>Esses arquivos existem no OneDrive (ou similar), mas não estão baixados neste computador. Para incluí-los: no Explorador de Arquivos, ' +
            'clique com o botão direito na pasta &gt; <b>Sempre manter neste dispositivo</b>, aguarde o download e execute o backup de novo.</p>')
        [void]$corpo.Append((New-TabelaHtml @('Pasta', 'Arquivo', 'Tamanho') $nuvem.ToArray() @(2)))
        [void]$corpo.Append('</section>')
    }
    [void]$corpo.Append('<section><h2>Próximos passos</h2><ul>')
    if ($Situacao -ne 'OK') { [void]$corpo.Append('<li>Resolva os itens acima e execute o backup de novo. Só o que falta será copiado.</li>') }
    [void]$corpo.Append('<li>De vez em quando, abra alguns arquivos direto do HD para ter certeza de que consegue restaurar (docs\RESTAURAR.md).</li>')
    [void]$corpo.Append('<li>Uma vez por mês, use <b>Verificar integridade</b> no menu: relê o HD e confere cada arquivo.</li>')
    [void]$corpo.Append('<li>Tenha um segundo HD e alterne entre os dois; guarde um deles fora de casa.</li></ul>')
    [void]$corpo.Append('<p class="suave">Nesta pasta: <a href="detalhes.tsv">detalhes.tsv</a> (cada arquivo tratado, abre no Excel), ' +
        '<a href="resumo.json">resumo.json</a> e os logs do Robocopy (robocopy-*.log).</p></section>')

    $caminho = Join-Path $Execucao 'RELATORIO.html'
    Save-Html $caminho (New-PaginaHtml $titulo $Situacao $corpo.ToString())
    [ordered]@{
        Programa = "windows-backup-audit $script:Versao"; Situacao = $Situacao; Falha = $Falha
        Inicio = $Inicio.ToString('o'); Fim = (Get-Date).ToString('o'); Destino = $Destino
        Disco = $Disco; Erros = $totalErros; SoNaNuvem = $totalNuvem; Origens = $Contagens
    } | ConvertTo-Json -Depth 4 | ForEach-Object { Save-Html (Join-Path $Execucao 'resumo.json') $_ }
    Write-AtalhoUltimoRelatorio $Controle ("execucoes\" + (Split-Path -Leaf $Execucao) + '\RELATORIO.html')
    return $caminho
}

function Write-RelatorioVerificacao {
    param([string]$Execucao, [string]$Controle, [string]$Destino, $Disco, [string]$Situacao, [string]$Falha,
        [datetime]$Inicio, [object[]]$Linhas, [int]$Amostra)
    $problemas = 0
    foreach ($l in $Linhas) { $problemas += $l.Problemas }
    switch ($Situacao) {
        'OK' { $titulo = 'Backup íntegro'; $texto = 'Cada arquivo conferido no HD tem o mesmo SHA-256 registrado quando foi copiado.' }
        'ERROS' { $titulo = 'Problemas encontrados no backup'; $texto = "$problemas arquivo(s) ausente(s) ou alterado(s) no HD. Execute o backup: eles serão copiados de novo (a cópia com problema vai para _VERSOES_ANTERIORES)." }
        default { $titulo = 'Verificação interrompida'; $texto = "A verificação parou antes do fim: $Falha" }
    }
    if ($Amostra -lt 100) { $texto += " Verificação por amostragem: cerca de $Amostra% dos arquivos." }
    $tabela = New-Object 'Collections.Generic.List[object]'
    foreach ($l in $Linhas) { $tabela.Add(@($l.Nome, ('{0:N0}' -f $l.Registros), ('{0:N0}' -f $l.Conferidos), (Format-Tamanho $l.Bytes), ('{0:N0}' -f $l.Problemas))) }
    $corpo = "<section class=""faixa""><h1 class=""selo"">$(ConvertTo-TextoHtml $titulo)</h1><p>$(ConvertTo-TextoHtml $texto)</p></section>" +
        "<section>$(Get-InfoDestinoHtml $Destino $Disco $Inicio)</section>" +
        '<section><h2>Pastas</h2>' + (New-TabelaHtml @('Pasta no backup', 'Arquivos registrados', 'Conferidos OK', 'Lidos', 'Com problema') $tabela.ToArray() @(1, 2, 3, 4)) +
        '<p class="suave">A lista de problemas está em <a href="detalhes.tsv">detalhes.tsv</a>.</p></section>'
    $caminho = Join-Path $Execucao 'RELATORIO.html'
    Save-Html $caminho (New-PaginaHtml $titulo $Situacao $corpo)
    [ordered]@{ Programa = "windows-backup-audit $script:Versao"; Tipo = 'Verificacao'; Situacao = $Situacao; Falha = $Falha
        Inicio = $Inicio.ToString('o'); Fim = (Get-Date).ToString('o'); Destino = $Destino; Amostra = $Amostra; Problemas = $problemas; Origens = $Linhas
    } | ConvertTo-Json -Depth 4 | ForEach-Object { Save-Html (Join-Path $Execucao 'resumo.json') $_ }
    Write-AtalhoUltimoRelatorio $Controle ("execucoes\" + (Split-Path -Leaf $Execucao) + '\RELATORIO.html')
    return $caminho
}

function Show-Resumo {
    # Resumo final no console, com uma frase clara sobre o resultado.
    param([Parameter(Mandatory)]$Resumo)
    $cor = switch ($Resumo.Situacao) { 'OK' { 'Green' } 'AVISOS' { 'Yellow' } default { 'Red' } }
    $texto = switch ($Resumo.Situacao) {
        'OK' { if ($Resumo.Modo -eq 'Simular') { 'SIMULAÇÃO CONCLUÍDA. Nada foi gravado no HD.' } elseif ($Resumo.Modo -eq 'Verificar') { 'BACKUP ÍNTEGRO.' } else { 'BACKUP CONCLUÍDO E CONFERIDO.' } }
        'AVISOS' { 'CONCLUÍDO COM AVISOS: há arquivos só na nuvem que não foram copiados.' }
        'ERROS' { if ($Resumo.Modo -eq 'Verificar') { 'HÁ PROBLEMAS NO BACKUP: execute o backup para copiá-los de novo.' } else { 'CONCLUÍDO COM ERROS: alguns arquivos NÃO estão no backup.' } }
        default { "INTERROMPIDO: $($Resumo.Falha)" }
    }
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor $cor
    Write-Host " $texto" -ForegroundColor $cor
    if ($Resumo.Modo -ne 'Verificar') {
        foreach ($o in $Resumo.Origens) {
            if ($Resumo.Modo -eq 'Simular') { continue }
            Write-Host (' {0,-22} copiados {1,7:N0}  atualizados {2,6:N0}  movidos {3,6:N0}  conferidos {4,7:N0}  sem mudança {5,8:N0}  erros {6,5:N0}' -f `
                $o.Nome, $o.Copiados, $o.Atualizados, $o.Movidos, $o.Conferidos, $o.SemMudanca, $o.Erros)
        }
    }
    $d = $Resumo.Duracao
    Write-Host (' Duração: {0}h {1}min {2}s' -f [int]$d.TotalHours, $d.Minutes, $d.Seconds)
    if ($Resumo.Relatorio) { Write-Host " Relatório: $($Resumo.Relatorio)" }
    Write-Host ('=' * 72) -ForegroundColor $cor
}

function Open-UltimoRelatorio {
    param([Parameter(Mandatory)][string]$Destino)
    $atalho = Join-Path (Join-Path $Destino '_CONTROLE') 'ULTIMO-RELATORIO.html'
    if (-not (Test-Path -LiteralPath $atalho)) { throw "Ainda não há relatório neste HD ($Destino). Faça um backup primeiro." }
    Start-Process -FilePath $atalho
}
