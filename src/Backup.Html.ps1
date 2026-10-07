function ConvertTo-BackupHtmlText {
    param([object]$Value)
    [Net.WebUtility]::HtmlEncode([string]$Value)
}
function Format-BackupSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GiB' -f ($Bytes/1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MiB' -f ($Bytes/1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KiB' -f ($Bytes/1KB)) }
    return "$Bytes bytes"
}
function Write-BackupHtml {
    param([string]$Run, [object[]]$Sources, [string]$Mode, [int]$Errors)
    $counts=@{}; $sizes=@{}; $roots=@{}; $total=[long]0; $count=0
    $largest=@(); $failures=New-Object 'Collections.Generic.List[object]'
    $csv=Join-Path $Run 'inventario.csv'
    if (Test-Path -LiteralPath $csv) {
        Import-Csv -LiteralPath $csv | ForEach-Object {
            $row=$_; $size=[long]$row.Bytes; $total+=$size; $count++
            if (-not $counts.ContainsKey($row.Status)) { $counts[$row.Status]=0; $sizes[$row.Status]=[long]0 }
            $counts[$row.Status]++; $sizes[$row.Status]+=$size
            if (-not $roots.ContainsKey($row.RootId)) { $roots[$row.RootId]=@{Count=0;Bytes=[long]0;Errors=0} }
            $roots[$row.RootId].Count++; $roots[$row.RootId].Bytes+=$size
            if ($row.Status -eq 'ERROR') {
                $roots[$row.RootId].Errors++
                if ($failures.Count -lt 100) { $failures.Add([pscustomobject]@{Path=$row.Source;Reason=$row.Error}) }
            }
            $largest=@(($largest + $row) | Sort-Object {[long]$_.Bytes} -Descending | Select-Object -First 10)
        }
    }
    $scope='Configuração manual'; $coverage=@()
    $planPath=Join-Path $Run 'plano.json'
    if (Test-Path -LiteralPath $planPath) {
        $plan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
        $scope=$plan.Scope
    }
    $coveragePath=Join-Path $Run 'cobertura.csv'
    if (Test-Path -LiteralPath $coveragePath) { $coverage=@(Import-Csv -LiteralPath $coveragePath) }
    $enumerationPath=Join-Path $Run 'falhas-enumeracao.csv'
    if (Test-Path -LiteralPath $enumerationPath) {
        Import-Csv -LiteralPath $enumerationPath | ForEach-Object {
            if ($failures.Count -lt 100) { $failures.Add($_) }
        }
    }
    foreach ($row in ($coverage | Where-Object Status -eq ERROR)) { if ($failures.Count -lt 100) { $failures.Add($row) } }
    $needs=0
    if ($counts.ContainsKey('NEEDS_COPY')) { $needs=$counts['NEEDS_COPY'] }
    $decision=if ($Errors) { 'INCOMPLETO — há falhas que precisam de revisão' } elseif ($Mode -eq 'Audit') { 'AUDITORIA CONCLUÍDA — nenhuma cópia nova realizada' } else { 'EXECUÇÃO CONCLUÍDA — revise a cobertura e teste a restauração' }
    $html=New-Object Text.StringBuilder
    $null=$html.Append(@'
<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Auditoria e revisão do backup</title>
<style>body{margin:0;background:#f3f5f8;color:#172336;font:16px/1.55 system-ui,Segoe UI,sans-serif}main{max-width:1100px;margin:auto;padding:30px 20px}h1{font-size:32px;margin:0}h2{margin-top:30px;font-size:23px}.banner{padding:16px;background:#e0edff;border-left:5px solid #245ec7;margin:20px 0}.cards{display:flex;gap:12px;flex-wrap:wrap}.card{background:white;padding:18px;border:1px solid #d8e0eb;border-radius:8px;flex:1;min-width:150px}.card strong{display:block;font-size:26px}table{border-collapse:collapse;width:100%;background:white}th,td{border:1px solid #d8e0eb;padding:10px;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#e7edf5}.scroll{overflow-x:auto}a{color:#164ba3}.muted{color:#4c5d73}code{overflow-wrap:anywhere}li{margin:8px 0}@media print{body{background:white}.card{break-inside:avoid}h2{break-after:avoid}}</style></head><body><main><h1>Revisão do backup</h1>
'@)
    $null=$html.Append('<p class="muted">Modo: <strong>'+(ConvertTo-BackupHtmlText $Mode)+'</strong> · '+(ConvertTo-BackupHtmlText $scope)+' · '+[DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm')+' UTC</p>')
    $null=$html.Append('<div class="banner">'+(ConvertTo-BackupHtmlText $decision)+'</div><div class="cards">')
    foreach ($card in @(@('Arquivos encontrados',$count),@('Tamanho lógico',(Format-BackupSize $total)),@('Ainda precisam de cópia',$needs),@('Falhas',$Errors))) {
        $null=$html.Append('<div class="card">'+$card[0]+'<strong>'+(ConvertTo-BackupHtmlText $card[1])+'</strong></div>')
    }
    $null=$html.Append('</div><p>Contagem e tamanho representam somente os arquivos encontrados. Erros de acesso podem ocultar arquivos adicionais. Zero erros não significa que todos os dados do computador foram incluídos.</p>')
    if ($Scope -eq 'Configuração manual' -and $Sources.Count -eq 1) {
        $null=$html.Append('<div class="banner">Atenção: somente uma pasta foi configurada. Para procurar dados pessoais automaticamente, use a opção Auditoria automática no Iniciar.cmd.</div>')
    }
    $null=$html.Append('<h2>Pastas examinadas</h2><div class="scroll"><table><thead><tr><th>Origem</th><th>Arquivos encontrados</th><th>Tamanho</th><th>Falhas de arquivos</th></tr></thead><tbody>')
    foreach ($source in $Sources) {
        $stat=@{Count=0;Bytes=0;Errors=0}; if ($roots.ContainsKey($source.Id)) { $stat=$roots[$source.Id] }
        $null=$html.Append('<tr><td>'+(ConvertTo-BackupHtmlText $source.Path)+'</td><td>'+$stat.Count+'</td><td>'+(Format-BackupSize $stat.Bytes)+'</td><td>'+$stat.Errors+'</td></tr>')
    }
    $null=$html.Append('</tbody></table></div><p>Falhas de enumeração aparecem abaixo e em falhas-enumeracao.csv; uma pasta com zero arquivos pode estar vazia ou inacessível.</p><h2>Comparação por conteúdo</h2><table><thead><tr><th>Resultado</th><th>Arquivos</th><th>Tamanho lógico</th></tr></thead><tbody>')
    $labels=@{NEEDS_COPY='Precisa de cópia';SKIP_IDENTICAL='Já existe no caminho esperado';REUSED_EXISTING='Cópia manual existente reutilizável';VERIFIED='Cópia realizada e verificada';ERROR='Arquivo não confirmado'}
    foreach ($status in ($counts.Keys | Sort-Object)) {
        $label=$status; if ($labels.ContainsKey($status)) { $label=$labels[$status] }
        $null=$html.Append('<tr><td>'+(ConvertTo-BackupHtmlText $label)+'</td><td>'+$counts[$status]+'</td><td>'+(Format-BackupSize $sizes[$status])+'</td></tr>')
    }
    $null=$html.Append('</tbody></table><p>São tamanhos lógicos, não previsão de espaço adicional. Conteúdos iguais podem compartilhar uma cópia. A auditoria não copia arquivos; duplicatas existentes não são apagadas.</p><h2>Cobertura e exclusões</h2>')
    if ($coverage.Count) {
        $null=$html.Append('<div class="scroll"><table><thead><tr><th>Caminho</th><th>Situação</th><th>Motivo</th></tr></thead><tbody>')
        $translations=@{INCLUDED='Incluído';COVERED='Incluído em outra raiz';EXCLUDED='Não examinado';ERROR='Falha de descoberta'}
        foreach ($row in $coverage) {
            $label=$row.Status; if ($translations.ContainsKey($label)) { $label=$translations[$label] }
            $null=$html.Append('<tr><td>'+(ConvertTo-BackupHtmlText $row.Path)+'</td><td>'+(ConvertTo-BackupHtmlText $label)+'</td><td>'+(ConvertTo-BackupHtmlText $row.Reason)+'</td></tr>')
        }
        $null=$html.Append('</tbody></table></div>')
    } else { $null=$html.Append('<p>Execução manual: somente as origens listadas foram examinadas. Nenhuma descoberta automática foi solicitada.</p>') }
    $null=$html.Append('<p>Não é uma imagem do Windows. Diretórios de Windows e programas listados nas exclusões não são copiados. Users, AppData, ProgramData e pastas próprias dos volumes incluídos são examinados; perfis protegidos podem gerar falhas de acesso. Rede e volumes sem letra não são descobertos automaticamente. Exporte separadamente bancos, e-mail local, certificados, WSL, Docker e máquinas virtuais quando aplicável.</p><h2>Pendências de leitura</h2>')
    if ($failures.Count) {
        $null=$html.Append('<p>Até 100 pendências exibidas; consulte os CSVs para a lista completa.</p><table><thead><tr><th>Caminho</th><th>Como identificar a falha</th></tr></thead><tbody>')
        foreach ($row in $failures) { $null=$html.Append('<tr><td>'+(ConvertTo-BackupHtmlText $row.Path)+'</td><td>'+(ConvertTo-BackupHtmlText $row.Reason)+'</td></tr>') }
        $null=$html.Append('</tbody></table>')
    } else { $null=$html.Append('<p>Nenhuma pendência detalhada nos CSVs. Confira também erros.txt, se existir.</p>') }
    $null=$html.Append('<h2>Maiores arquivos encontrados</h2><table><thead><tr><th>Arquivo</th><th>Tamanho</th></tr></thead><tbody>')
    foreach ($row in $largest) { $null=$html.Append('<tr><td>'+(ConvertTo-BackupHtmlText $row.Source)+'</td><td>'+(Format-BackupSize ([long]$row.Bytes))+'</td></tr>') }
    $null=$html.Append('</tbody></table><h2>Próximos passos</h2><ol><li>Confira as pastas e exclusões acima; inclua manualmente o que estiver faltando.</li><li>Resolva as falhas. Para OneDrive somente online, escolha Sempre manter neste dispositivo e aguarde o download antes de repetir.</li><li>Após revisar a auditoria, execute Backup usando o mesmo modo de descoberta e a mesma pasta de destino.</li><li>Guarde inventario.csv: Destination aponta para a cópia real, inclusive quando reutilizada. Restaure uma amostra em uma pasta vazia e compare os arquivos.</li><li>Mantenha outra cópia independente dos dados críticos. Este relatório não autoriza formatação.</li></ol><h2>Arquivos da execução</h2><p><a href="inventario.csv">Inventário completo (CSV)</a> · <a href="LEIA-ME.md">Versão Markdown</a> · <a href="plano.json">Plano utilizado</a> · <a href="cobertura.csv">Cobertura (CSV)</a></p><p class="muted">Os relatórios contêm caminhos pessoais. Revise antes de compartilhar.</p></main></body></html>')
    $html.ToString() | Set-Content -LiteralPath (Join-Path $Run 'LEIA-ME.html') -Encoding UTF8
}
