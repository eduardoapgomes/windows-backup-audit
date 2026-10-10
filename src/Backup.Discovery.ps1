# Descoberta orientada a dados: nunca inclui a raiz do perfil ou do disco automaticamente.
function Get-PersonalFolderCandidates {
    $profile = [Environment]::GetFolderPath('UserProfile')
    foreach ($name in @('Desktop','MyDocuments','MyPictures','MyMusic','MyVideos','Favorites')) {
        $path = [Environment]::GetFolderPath($name)
        if ($path) { [pscustomobject]@{Path=$path;Kind="Pasta pessoal: $name"} }
    }
    $downloads = $null
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $downloads = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
    } catch { Write-Warning 'Downloads não pôde ser consultado no registro; tentando o caminho padrão.' }
    if ($downloads) { $downloads = [Environment]::ExpandEnvironmentVariables($downloads) }
    elseif ($profile) { $downloads = Join-Path $profile 'Downloads' }
    if ($downloads) { [pscustomobject]@{Path=$downloads;Kind='Downloads'} }
    foreach ($path in @($env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial)) {
        if ($path) { [pscustomobject]@{Path=$path;Kind='OneDrive'} }
    }
    if ($profile) {
        foreach ($name in @('Projetos','Projects','Code','Codigo','Código','Repos','Git','Trabalho','Work','Estudos','Dados','Data','Notebooks','Jupyter','Saved Games')) {
            $path = Join-Path $profile $name
            if (Test-Path -LiteralPath $path -PathType Container) {
                [pscustomobject]@{Path=$path;Kind='Pasta de dados/projetos no perfil'}
            }
        }
    }
}

function Get-AutomaticBackupPlan {
    $rows = New-Object 'Collections.Generic.List[object]'
    $sources = New-Object 'Collections.Generic.List[object]'
    $candidates = New-Object 'Collections.Generic.List[object]'
    Write-Host 'Descoberta por pastas de dados: sem varredura integral de C:\, Users ou programas.'
    try { foreach ($item in Get-PersonalFolderCandidates) { $candidates.Add($item) } }
    catch { $rows.Add([pscustomobject]@{Path='Pastas pessoais';Status='ERROR';Reason=$_.Exception.Message}) }

    # Um nível lógico de seleção: testar apenas nomes de pastas de dados no topo
    # dos volumes internos. Outras pastas e arquivos soltos ficam para revisão.
    $dataFolders = @('Projetos','Projects','Code','Codigo','Código','Repos','Repositories',
        'Dados','Data','Documentos','Documents','Trabalho','Work','Estudos',
        'Fotos','Pictures','Imagens','Videos','Vídeos','Arquivos','Notebooks','Jupyter')
    try {
        foreach ($volume in Get-Volume -ErrorAction Stop) {
            if (-not $volume.DriveLetter) { continue }
            $root = "$($volume.DriveLetter):\"
            try {
                $disk = Get-StorageIdentity $root
                if ($disk.BusType -notin @('SATA','ATA','NVMe','SAS','SCSI','RAID') -or $disk.IsOffline) {
                    $rows.Add([pscustomobject]@{Path=$root;Status='EXCLUDED';Reason='Volume externo, offline ou não habilitado como origem automática.'})
                    continue
                }
                $rows.Add([pscustomobject]@{Path=$root;Status='REVIEW';Reason='Raiz não examinada: arquivos soltos e pastas com outros nomes exigem inclusão manual. Não é cobertura integral do volume.'})
                foreach ($name in $dataFolders) {
                    $path = Join-Path $root $name
                    if (Test-Path -LiteralPath $path -PathType Container) {
                        $candidates.Add([pscustomobject]@{Path=$path;Kind='Pasta de dados identificada no volume interno'})
                    }
                }
            } catch { $rows.Add([pscustomobject]@{Path=$root;Status='ERROR';Reason=$_.Exception.Message}) }
        }
    } catch { $rows.Add([pscustomobject]@{Path='Volumes';Status='ERROR';Reason=$_.Exception.Message}) }

    $profile = [Environment]::GetFolderPath('UserProfile')
    foreach ($candidate in ($candidates | Sort-Object @{Expression={$_.Path.Length}},Path)) {
        $path = [string]$candidate.Path
        try {
            Assert-PlainPath $path -AllowCloudSource
            $normalized = [IO.Path]::GetFullPath($path).TrimEnd('\','/')
            $root = [IO.Path]::GetPathRoot($normalized).TrimEnd('\','/')
            if ($normalized -eq $root -or ($profile -and $normalized -ieq $profile.TrimEnd('\','/'))) {
                $rows.Add([pscustomobject]@{Path=$path;Status='REVIEW';Reason='Raiz ampla demais; escolha subpastas de dados explicitamente.'})
                continue
            }
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                $rows.Add([pscustomobject]@{Path=$path;Status='NOT_FOUND';Reason='Pasta opcional ausente; confira se há dados em outro local.'})
                continue
            }
            $covered = @($sources | Where-Object { Test-PathWithin $path $_.Path }).Count -gt 0
            if ($covered) {
                $rows.Add([pscustomobject]@{Path=$path;Status='COVERED';Reason='Incluída em outra pasta de dados já selecionada.'})
                continue
            }
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $id = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized.ToUpperInvariant()))).Replace('-','').Substring(0,16) }
            finally { $sha.Dispose() }
            $sources.Add([pscustomobject]@{Id="AUTO_$id";Path=$path})
            $rows.Add([pscustomobject]@{Path=$path;Status='INCLUDED';Reason=$candidate.Kind})
        } catch { $rows.Add([pscustomobject]@{Path=$path;Status='ERROR';Reason=$_.Exception.Message}) }
    }
    if (-not $sources.Count) { throw 'Nenhuma pasta de dados encontrada. Use a opção 3 para selecionar suas pastas manualmente.' }
    $rows | Format-Table Path,Status,Reason -AutoSize | Out-Host
    [pscustomobject]@{Destination='';Sources=$sources.ToArray();Discovery=$rows.ToArray();ExcludedPaths=@()}
}
