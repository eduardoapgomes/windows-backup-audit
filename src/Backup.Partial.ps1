function Write-BackupPartial {
    param([string]$Phase, [string]$Path='', [long]$ReadBytes=0, [long]$TotalBytes=0, [switch]$Finished)
    $state=$script:BackupProgress
    if ($null -eq $state -or -not $state.ContainsKey('Run')) { return }
    $null=Assert-ExternalDestination $state.Run $state.SourcePaths $state.Identity
    Save-BackupDecisions
    $now=[DateTime]::UtcNow
    $enumerationErrors=0
    if ($state.ContainsKey('EnumerationIssues')) { $enumerationErrors=$state.EnumerationIssues.Count }
    $status=if ($Finished) {'ENCERRADO — abra o relatório final para verificar falhas'} else {'PARCIAL — auditoria/backup ainda não confirmado'}
    $stats=@{UpdatedUtc=$now.ToString('o');Status=$status;Phase=$Phase;CurrentPath=$Path;
        EnumerationErrors=$enumerationErrors;InventoriedFiles=$state.AuditFiles;InventoriedBytes=$state.AuditBytes;ReadBytes=$ReadBytes;TotalBytes=$TotalBytes;Results=$state.Results}
    $stats | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $state.Run 'andamento.json') -Encoding UTF8
    $refresh=if ($Finished) {'<meta http-equiv="refresh" content="0;url=LEIA-ME.html">'} else {'<meta http-equiv="refresh" content="10">'}
    $rows=($state.Results.Keys | Sort-Object | ForEach-Object {
        '<tr><td>'+(ConvertTo-BackupHtmlText $_)+'</td><td>'+$state.Results[$_]+'</td></tr>'
    }) -join ''
    $html='<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">'+$refresh+'<title>Andamento do backup</title><style>body{max-width:1000px;margin:32px auto;padding:20px;font:17px/1.6 system-ui;background:#f3f5f8;color:#172336}section{background:white;padding:20px;border-radius:10px}td,th{padding:8px;border:1px solid #ccd}table{border-collapse:collapse}code{overflow-wrap:anywhere}</style></head><body><section><h1>'+$status+'</h1><p>Atualizado em '+$now.ToString('yyyy-MM-dd HH:mm:ss')+' UTC. Esta página atualiza a cada 10 segundos.</p><p>Etapa: <strong>'+(ConvertTo-BackupHtmlText $Phase)+'</strong></p><p>Arquivo/pasta: <code>'+(ConvertTo-BackupHtmlText $Path)+'</code></p><p>Arquivos inventariados: <strong>'+$state.AuditFiles+'</strong> · Tamanho encontrado: '+(Format-BackupSize $state.AuditBytes)+'</p><p>Falhas de enumeração registradas até agora: '+$enumerationErrors+'</p><p>Leitura atual: '+(Format-BackupSize $ReadBytes)+' / '+(Format-BackupSize $TotalBytes)+'</p><table><tr><th>Resultado parcial</th><th>Arquivos</th></tr>'+$rows+'</table><p>Totais ainda incompletos. Se o horário parar de mudar, a execução pode estar aguardando o disco/provedor ou ter sido interrompida; isso não significa conclusão.</p><p><a href="inventario.csv">Inventário parcial</a> · <a href="cobertura.csv">Escopo e exclusões</a> · <a href="dependencias.csv">Bibliotecas opcionais</a> · <a href="falhas-enumeracao.csv">Falhas de enumeração</a> · <a href="LEIA-ME.html">Relatório final (quando disponível)</a></p></section></body></html>'
    $html | Set-Content -LiteralPath (Join-Path $state.Run 'ANDAMENTO.html') -Encoding UTF8
}
