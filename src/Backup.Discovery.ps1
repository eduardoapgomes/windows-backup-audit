function Get-PersonalFolderCandidates {
    $profile = [Environment]::GetFolderPath('UserProfile')
    [pscustomobject]@{Path=$profile;Kind='Perfil do usuário atual'}
    foreach ($name in @('Desktop','MyDocuments','MyPictures','MyMusic','MyVideos')) {
        $path = [Environment]::GetFolderPath($name)
        if ($path) { [pscustomobject]@{Path=$path;Kind="Pasta pessoal: $name"} }
    }
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $downloads = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
    if ($downloads) { [pscustomobject]@{Path=[Environment]::ExpandEnvironmentVariables($downloads);Kind='Downloads'} }
    foreach ($path in @($env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial)) {
        if ($path) { [pscustomobject]@{Path=$path;Kind='OneDrive'} }
    }
}
function Get-AutomaticBackupPlan {
    $rows = New-Object 'Collections.Generic.List[object]'
    $sources = New-Object 'Collections.Generic.List[object]'
    $exclusions = New-Object 'Collections.Generic.List[string]'
    $candidates = New-Object 'Collections.Generic.List[object]'
    Write-Host 'Descobrindo volumes internos para varredura completa de dados, incluindo Users...'
    try { foreach ($item in Get-PersonalFolderCandidates) { $candidates.Add($item) } }
    catch { $rows.Add([pscustomobject]@{Path='Pastas pessoais';Status='ERROR';Reason=$_.Exception.Message}) }
    try {
        foreach ($volume in Get-Volume -ErrorAction Stop) {
            if (-not $volume.DriveLetter) { continue }
            $path = "$($volume.DriveLetter):\"
            try {
                $disk = Get-StorageIdentity $path
                if ($disk.BusType -in @('SATA','ATA','NVMe','SAS','SCSI','RAID') -and
                    -not $disk.IsOffline) {
                    $candidates.Add([pscustomobject]@{Path=$path;Kind='Varredura do volume interno (dados fora e dentro de Users)'})
                    foreach ($name in @('$RECYCLE.BIN','System Volume Information','Recovery','Windows','Program Files','Program Files (x86)','Boot','EFI','Config.Msi','pagefile.sys','swapfile.sys','hiberfil.sys','bootmgr','DumpStack.log','DumpStack.log.tmp')) {
                        $exclusions.Add(([IO.Path]::Combine($path, $name)))
                    }
                } else {
                    $rows.Add([pscustomobject]@{Path=$path;Status='EXCLUDED';Reason='Mídia externa, volume offline ou tipo não habilitado. Não é origem automática.'})
                }
            } catch { $rows.Add([pscustomobject]@{Path=$path;Status='ERROR';Reason=$_.Exception.Message}) }
        }
    } catch { $rows.Add([pscustomobject]@{Path='Volumes';Status='ERROR';Reason=$_.Exception.Message}) }
    $profile = [Environment]::GetFolderPath('UserProfile')
    if ($profile) {
        foreach ($name in @('NTUSER.DAT','ntuser.dat.LOG1','ntuser.dat.LOG2')) { $exclusions.Add(([IO.Path]::Combine($profile, $name))) }
    }
    # Parents first; known folders outside the profile remain separate roots.
    foreach ($candidate in ($candidates | Sort-Object @{Expression={$_.Path.Length}},Path)) {
        $path = $candidate.Path
        try {
            Assert-PlainPath $path -AllowCloudSource
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw 'Pasta não encontrada.' }
            $covered = @($sources | Where-Object { Test-PathWithin $path $_.Path }).Count -gt 0
            $excluded = @($exclusions | Where-Object { Test-PathWithin $path $_ }).Count -gt 0
            if ($excluded) {
                $rows.Add([pscustomobject]@{Path=$path;Status='EXCLUDED';Reason='Pasta de software/sistema excluída explicitamente.'})
            } elseif ($covered) {
                $rows.Add([pscustomobject]@{Path=$path;Status='COVERED';Reason='Incluída em uma raiz já descoberta.'})
            } else {
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $id = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($path.ToUpperInvariant()))).Replace('-','').Substring(0,16) }
                finally { $sha.Dispose() }
                $sources.Add([pscustomobject]@{Id="AUTO_$id";Path=$path})
                $rows.Add([pscustomobject]@{Path=$path;Status='INCLUDED';Reason=$candidate.Kind})
            }
        } catch { $rows.Add([pscustomobject]@{Path=$path;Status='ERROR';Reason=$_.Exception.Message}) }
    }
    foreach ($path in $exclusions) { $rows.Add([pscustomobject]@{Path=$path;Status='EXCLUDED';Reason='Exclusão automática explícita: sistema/aplicativos. Não representa backup desses dados.'}) }
    if (-not $sources.Count) { throw 'Nenhuma origem automática disponível. Configure origens manualmente.' }
    $rows | Format-Table Path,Status,Reason -AutoSize | Out-Host
    [pscustomobject]@{Destination='';Sources=$sources.ToArray();Discovery=$rows.ToArray();ExcludedPaths=$exclusions.ToArray()}
}
