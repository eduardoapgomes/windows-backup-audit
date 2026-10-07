function New-BackupConfiguration {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        throw "Configuração já existe: $Path. Ela foi preservada. Para editar, abra esse arquivo no Bloco de Notas."
    }
    Add-Type -AssemblyName System.Windows.Forms
    $sources = New-Object 'Collections.Generic.List[object]'
    do {
        $dialog = New-Object Windows.Forms.FolderBrowserDialog
        try {
            $dialog.Description = 'Selecione uma pasta de origem (Documentos, Downloads, fotos ou projetos).'
            $dialog.SelectedPath = [Environment]::GetFolderPath('MyDocuments')
            $dialog.ShowNewFolderButton = $false
            if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
                throw 'Configuração cancelada. Nenhum arquivo de configuração foi criado.'
            }
            $source = $dialog.SelectedPath
            Assert-PlainPath $source -AllowCloudSource
            if (@($sources | Where-Object Path -eq $source).Count) { throw 'Pasta repetida; configuração cancelada.' }
            $sources.Add([pscustomobject]@{Id=('PASTA_{0:D2}' -f ($sources.Count + 1));Path=$source})
        } finally { $dialog.Dispose() }
        $more = [Windows.Forms.MessageBox]::Show('Deseja adicionar outra pasta?', 'Origens do backup', 'YesNo')
    } while ($more -eq [Windows.Forms.DialogResult]::Yes)
    $json = [pscustomobject]@{Destination='';Sources=@($sources.ToArray())} | ConvertTo-Json -Depth 5
    # CreateNew prevents overwriting an existing personal configuration.
    $stream = [IO.File]::Open($Path, 'CreateNew', 'Write', 'None')
    $writer = New-Object IO.StreamWriter($stream, (New-Object Text.UTF8Encoding($true)))
    try { $writer.Write($json) } finally { $writer.Dispose() }
    Write-Host "Configuração criada: $Path. Revise as pastas antes da auditoria."
}
