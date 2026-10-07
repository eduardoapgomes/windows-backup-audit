function Assert-BackupDependencies {
    param([ValidateSet('Audit','Backup')][string]$Mode)
    if ($env:OS -ne 'Windows_NT') { throw 'Este projeto exige Windows e PowerShell 5.1 ou superior.' }
    foreach ($command in @('Get-FileHash','ConvertFrom-Json','Export-Csv','Get-Disk','Get-Partition','Get-Volume')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Dependência ausente: $command" }
    }
    if ($Mode -eq 'Backup' -and -not (Get-Command robocopy.exe -ErrorAction SilentlyContinue)) {
        throw 'Robocopy ausente. Ele acompanha o Windows; verifique a instalação/PATH antes do backup.'
    }
}

function ConvertTo-ReviewText {
    param([object]$Value)
    # Keep filenames from injecting Markdown rows, HTML or new paragraphs.
    [Net.WebUtility]::HtmlEncode([string]$Value).Replace('|','&#124;').Replace("`r",' ').Replace("`n",' ')
}

function Write-BackupReview {
    param([string]$Run, [object[]]$Sources, [string]$Mode, [int]$Errors)
    $csv = Join-Path $Run 'inventario.csv'
    $count = 0; $bytes = [long]0; $statuses = @{}
    if (Test-Path -LiteralPath $csv) {
        Import-Csv -LiteralPath $csv | ForEach-Object {
            $count++; $bytes += [long]$_.Bytes
            if (-not $statuses.ContainsKey($_.Status)) { $statuses[$_.Status] = 0 }
            $statuses[$_.Status]++
        }
    }
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.Add('# Revisão da execução de backup')
    $lines.Add('')
    $lines.Add("Modo: **$Mode**. Arquivos encontrados: **$count**. Tamanho lógico: **$bytes bytes**.")
    $lines.Add("Erros registrados: **$Errors**. Data UTC: $([DateTime]::UtcNow.ToString('o')).")
    if ($Mode -eq 'Audit') {
        $lines.Add('**Esta auditoria não copiou arquivos. Comparou conteúdo por SHA-256: NEEDS_COPY ainda precisa de cópia; SKIP_IDENTICAL/REUSED_EXISTING já têm uma cópia verificada na pasta selecionada.**')
    } else {
        $lines.Add('VERIFIED: cópia validada por SHA-256. SKIP_IDENTICAL: mesmo caminho já válido. REUSED_EXISTING: conteúdo reutilizado em outro caminho. ERROR: arquivo não confirmado.')
    }
    $lines.Add('')
    $lines.Add('## Pastas configuradas para esta execução')
    $lines.Add('')
    $lines.Add('| Identificador | Origem |')
    $lines.Add('|---|---|')
    foreach ($source in $Sources) {
        $lines.Add('| ' + (ConvertTo-ReviewText $source.Id) + ' | ' + (ConvertTo-ReviewText $source.Path) + ' |')
    }
    $lines.Add('')
    $lines.Add('## Cobertura da descoberta')
    $coveragePath = Join-Path $Run 'cobertura.csv'
    if (Test-Path -LiteralPath $coveragePath) {
        foreach ($entry in (Import-Csv -LiteralPath $coveragePath)) {
            $lines.Add('- ' + (ConvertTo-ReviewText $entry.Status) + ': ' + (ConvertTo-ReviewText $entry.Path) + ' — ' + (ConvertTo-ReviewText $entry.Reason))
        }
    }
    $lines.Add('Consulte falhas-enumeracao.csv para pastas/links inacessíveis. Exclusões não são dados protegidos pelo backup.')
    $lines.Add('## Resultados por status')
    $lines.Add('O índice cobre somente a pasta de backup escolhida. Duplicatas manuais existentes não são apagadas. Falhas na leitura interrompem a confirmação de cobertura.')
    foreach ($status in ($statuses.Keys | Sort-Object)) { $lines.Add("- ${status}: $($statuses[$status])") }
    $lines.Add('')
    $lines.Add('## Como avaliar este relatório')
    $lines.Add('1. Confira se todas as pastas pessoais e de trabalho estão na lista acima. Só as raízes configuradas foram examinadas.')
    $lines.Add('2. Abra inventario.csv no Excel e filtre Source, Destination e Status. Destination é a cópia real verificada; PlannedDestination é apenas o caminho proposto. Guarde este CSV para restauração: conteúdos iguais podem compartilhar a mesma cópia. Não mova nem apague cópias reutilizadas.')
    $lines.Add('3. Confira Documentos, Área de Trabalho, Downloads, fotos, tese/projetos e dados em outros discos; use os caminhos reais, inclusive pastas redirecionadas.')
    $lines.Add('4. Se houver erro, abra erros.txt e a coluna Error do CSV. A raiz pode estar parcialmente examinada: contagem e tamanho não são completos.')
    $lines.Add('5. OneDrive online-only, junctions, pastas protegidas e arquivos bloqueados exigem revisão. Materialize arquivos em nuvem e configure pastas reais.')
    $lines.Add('6. Feche aplicações. Bancos, WSL, Docker, VMs e certificados precisam de exportação própria e teste de recuperação; este inventário não prova consistência.')
    $lines.Add('7. Depois da auditoria revisada, execute o comando Backup do README. Confira seu novo relatório e restaure uma amostra em pasta vazia.')
    $lines.Add('8. Mantenha uma segunda cópia independente dos itens críticos antes de formatar. Este relatório não autoriza formatação.')
    $lines.Add('')
    $lines.Add('O tamanho é uma estimativa lógica dos arquivos encontrados, não espaço adicional necessário. Versões anteriores, staging e metadados podem exigir mais espaço.')
    $lines.Add('Relatórios contêm nomes e caminhos pessoais. Não publique nem envie integralmente para uma IA sem revisão.')
    if (Test-Path -LiteralPath (Join-Path $Run 'erros.txt')) {
        $lines.Add('')
        $lines.Add('## Erros de enumeração')
        foreach ($errorLine in Get-Content -LiteralPath (Join-Path $Run 'erros.txt')) {
            $lines.Add('- ' + (ConvertTo-ReviewText $errorLine))
        }
    }
    $markdown = $lines -join "`r`n"
    $markdown | Set-Content -LiteralPath (Join-Path $Run 'LEIA-ME.md') -Encoding UTF8
    Write-BackupHtml -Run $Run -Sources $Sources -Mode $Mode -Errors $Errors
}
