function Assert-PlainPath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':')) {
        throw 'Use um caminho local absoluto com letra de unidade; UNC, relativo e ADS não são aceitos.'
    }
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current -ErrorAction Stop) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Caminho redirecionado (junction/link/mount point): $current"
            }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
}

function Get-StorageIdentity {
    param([string]$Path)
    Assert-PlainPath $Path
    $letter = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)).Substring(0,1)
    $partitions = @(Get-Partition -DriveLetter $letter -ErrorAction Stop)
    if ($partitions.Count -ne 1) { throw 'Não foi possível identificar uma partição única.' }
    $disk = Get-Disk -Number $partitions[0].DiskNumber -ErrorAction Stop
    $volume = Get-Volume -DriveLetter $letter -ErrorAction Stop
    [pscustomobject]@{
        DiskId = [string]$disk.UniqueId; VolumeId = [string]$volume.UniqueId
        DiskNumber = $disk.Number; BusType = [string]$disk.BusType
        IsBoot = $disk.IsBoot; IsSystem = $disk.IsSystem
        IsOffline = $disk.IsOffline; IsReadOnly = $disk.IsReadOnly
        FileSystem = [string]$volume.FileSystem; FreeBytes = [long]$volume.SizeRemaining
        Label = [string]$volume.FileSystemLabel; Drive = "${letter}:\"
    }
}

function Assert-ExternalDestination {
    param([string]$Destination, [string[]]$Sources = @(), [object]$ExpectedIdentity)
    $identity = Get-StorageIdentity $Destination
    if ([string]::IsNullOrWhiteSpace($identity.DiskId) -or [string]::IsNullOrWhiteSpace($identity.VolumeId)) {
        throw 'Identidade do disco/volume não confirmada.'
    }
    if ($identity.BusType -ne 'USB' -or $identity.IsBoot -or $identity.IsSystem -or
        $identity.IsOffline -or $identity.IsReadOnly) {
        throw 'Destino bloqueado: exige USB externo gravável, sem sistema/boot.'
    }
    if ($identity.FileSystem -ne 'NTFS') { throw 'Destino deve ser NTFS. O programa não formata discos.' }
    if ($ExpectedIdentity -and ($identity.DiskId -ne $ExpectedIdentity.DiskId -or
        $identity.VolumeId -ne $ExpectedIdentity.VolumeId)) { throw 'O disco de destino foi trocado ou desconectado.' }
    foreach ($source in $Sources) {
        $sourceDisk = Get-StorageIdentity $source
        if ($sourceDisk.DiskId -eq $identity.DiskId) { throw 'Origem e destino estão no mesmo disco físico.' }
    }
    return $identity
}

function Select-BackupDestination {
    param([string[]]$Sources)
    if (-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
        throw 'Interface requer Windows PowerShell Desktop. Use powershell.exe -STA ou um Destination explícito validado.'
    }
    $candidates = @(foreach ($volume in Get-Volume -ErrorAction Stop) {
        if ($volume.DriveLetter) {
            try {
                $identity = Assert-ExternalDestination "$($volume.DriveLetter):\" $Sources
                [pscustomobject]@{Unidade=$identity.Drive; Nome=$identity.Label;
                    LivreGB=[math]::Round($identity.FreeBytes / 1GB,2); Identidade=$identity}
            } catch { Write-Verbose $_.Exception.Message }
        }
    })
    if (-not $candidates.Count) { throw 'Nenhum destino USB/NTFS seguro disponível. Consulte docs/SAFETY.md.' }
    $selection = $candidates | Out-GridView -Title 'Selecione o disco USB externo (Cancelar interrompe)' -OutputMode Single
    if ($null -eq $selection) { throw 'Seleção cancelada. Nenhum backup iniciado.' }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    try {
        $dialog.Description = 'Selecione a pasta que contém seu backup parcial. Para backup novo, selecione a raiz do USB.'
        $dialog.SelectedPath = $selection.Unidade
        $dialog.ShowNewFolderButton = $false
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw 'Seleção cancelada.' }
        $path = $dialog.SelectedPath
        if ([IO.Path]::GetFullPath($path).TrimEnd('\') -eq $selection.Unidade.TrimEnd('\')) {
            $path = Join-Path $path "BACKUP_WINDOWS\$env:COMPUTERNAME-$env:USERNAME"
        }
        $null = Assert-ExternalDestination $path $Sources $selection.Identidade
        return $path
    } finally { $dialog.Dispose() }
}
