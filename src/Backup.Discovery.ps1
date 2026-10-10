# Descoberta conservadora: dados primeiro, sem percorrer o disco inteiro.
# O modo automatico seleciona pastas conhecidas e pastas de trabalho na superficie
# dos volumes. Outras localizacoes exigem revisao e inclusao manual.
function Get-PersonalFolderCandidates {
    foreach ($name in @('Desktop','MyDocuments','MyPictures','MyMusic','MyVideos')) {
        $path = [Environment]::GetFolderPath($name)
        if ($path) { [pscustomobject]@{Path=$path;Kind="Pasta pessoal: $name"} }
    }
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    try {
        $downloads = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($downloads) {
            [pscustomobject]@{Path=[Environment]::ExpandEnvironmentVariables($downloads);Kind='Downloads'}
        }
    } catch {
        # Um Windows sem esta entrada ainda pode usar as outras pastas conhecidas.
        $fallback = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
        if (Test-Path -LiteralPath $fallback -PathType Container) {
            [pscustomobject]@{Path=$fallback;Kind='Downloads (caminho convencional; confirme redirecionamentos)'}
        }
    }
    foreach ($path in @($env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial)) {
        if ($path) { [pscustomobject]@{Path=$path;Kind='OneDrive (arquivos disponiveis localmente)'} }
    }
}

function Get-DataFolderNames {
    # Somente nomes de pastas de dados no primeiro nivel. Nao sao regras
    # para ignorar arquivos dentro de um projeto nem para apagar conteudo.
    return @('Projetos','Projects','Repos','Repositories','Workspace','Workspaces',
        'Trabalho','Estudos','Research','Pesquisa','Code','Codigo','Código',
        'Source','Sources','src','GitHub','GitLab','Jupyter','Notebooks',
        'Dados','Data','Arquivos','Documentos','Documents','Downloads',
        'Desktop','Pictures','Imagens','Fotos','Videos','Vídeos','Music',
        'Música','Notes','Notas')
}

function Get-AutomaticBackupPlan {
    $rows = New-Object 'Collections.Generic.List[object]'
    $sources = New-Object 'Collections.Generic.List[object]'
    $candidates = New-Object 'Collections.Generic.List[object]'
    $exclusions = New-Object 'Collections.Generic.List[string]'
    $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in Get-DataFolderNames) { $null = $names.Add($name) }

    Write-Host 'Descoberta rapida: pastas pessoais e pastas de dados no primeiro nivel dos discos.'
    try {
        foreach ($item in Get-PersonalFolderCandidates) { $candidates.Add($item) }
    } catch {
        $rows.Add([pscustomobject]@{Path='Pastas pessoais';Status='ERROR';Reason=$_.Exception.Message})
    }

    $profile = [Environment]::GetFolderPath('UserProfile')
    if ($profile -and (Test-Path -LiteralPath $profile -PathType Container)) {
        $rows.Add([pscustomobject]@{Path=$profile;Status='REVIEW_REQUIRED';Reason='O perfil inteiro (AppData, programas, caches e arquivos soltos) nao e varrido. Inclua manualmente dados especiais.'})
        try {
            # Um unico nivel de diretorios; nao percorre AppData nem instalacoes.
            foreach ($dir in (Get-ChildItem -LiteralPath $profile -Directory -Force -ErrorAction Stop)) {
                if ($names.Contains($dir.Name) -or $dir.Name -in @('.ssh','.gnupg','.jupyter','.ipython')) {
                    $candidates.Add([pscustomobject]@{Path=$dir.FullName;Kind='Pasta de dados na raiz do perfil'})
                }
            }
        } catch {
            $rows.Add([pscustomobject]@{Path=$profile;Status='ERROR';Reason='Nao foi possivel listar o primeiro nivel: ' + $_.Exception.Message})
        }
    }

    try {
        foreach ($volume in Get-Volume -ErrorAction Stop) {
            if (-not $volume.DriveLetter) { continue }
            $root = "$($volume.DriveLetter):\"
            try {
                $disk = Get-StorageIdentity $root
                if ($disk.BusType -notin @('SATA','ATA','NVMe','SAS','SCSI','RAID') -or $disk.IsOffline) {
                    $rows.Add([pscustomobject]@{Path=$root;Status='EXCLUDED';Reason='Volume nao interno, offline ou nao elegivel como origem automatica.'})
                    continue
                }
                $rows.Add([pscustomobject]@{Path=$root;Status='REVIEW_REQUIRED';Reason='Disco nao varrido integralmente. Somente pastas de dados no primeiro nivel; confira outras localizacoes manualmente.'})
                try {
                    foreach ($dir in (Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction Stop)) {
                        if ($names.Contains($dir.Name)) {
                            $candidates.Add([pscustomobject]@{Path=$dir.FullName;Kind='Pasta de dados no primeiro nivel do volume interno'})
                        }
                    }
                } catch {
                    $rows.Add([pscustomobject]@{Path=$root;Status='ERROR';Reason='Nao foi possivel listar o primeiro nivel: ' + $_.Exception.Message})
                }
            } catch {
                $rows.Add([pscustomobject]@{Path=$root;Status='ERROR';Reason='Nao foi possivel identificar o volume: ' + $_.Exception.Message})
            }
        }
    } catch {
        $rows.Add([pscustomobject]@{Path='Volumes';Status='ERROR';Reason=$_.Exception.Message})
    }

    # Prefere raizes menores quando sao independentes; nao duplica subpastas.
    foreach ($candidate in ($candidates | Sort-Object @{Expression={$_.Path.Length}},Path)) {
        $path = [string]$candidate.Path
        try {
            Assert-PlainPath $path -AllowCloudSource
            if (-not (Test-Path -LiteralPath $path -PathType Container)) {
                throw 'Pasta descoberta nao encontrada.'
            }
            if (@($sources | Where-Object { Test-PathWithin $path $_.Path }).Count -gt 0) {
                $rows.Add([pscustomobject]@{Path=$path;Status='COVERED';Reason='Incluida em outra raiz de dados ja selecionada.'})
                continue
            }
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $id = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($path.ToUpperInvariant()))).Replace('-','').Substring(0,16)
            } finally { $sha.Dispose() }
            $sources.Add([pscustomobject]@{Id="AUTO_$id";Path=$path})
            $rows.Add([pscustomobject]@{Path=$path;Status='INCLUDED';Reason=$candidate.Kind})
        } catch {
            $rows.Add([pscustomobject]@{Path=$path;Status='ERROR';Reason=$_.Exception.Message})
        }
    }
    if (-not $sources.Count) { throw 'Nenhuma pasta de dados encontrada. Configure suas pastas manualmente.' }
    Write-Host 'AVISO: descoberta parcial. Pastas nao selecionadas, dados de aplicativos e arquivos soltos exigem revisao.'
    $rows | Format-Table Path,Status,Reason -AutoSize | Out-Host
    [pscustomobject]@{Destination='';Sources=$sources.ToArray();Discovery=$rows.ToArray();ExcludedPaths=$exclusions.ToArray()}
}
