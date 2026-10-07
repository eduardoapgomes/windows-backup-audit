#Requires -Version 5.1
Set-StrictMode -Version Latest
. "$PSScriptRoot\Backup.Review.ps1"
. "$PSScriptRoot\Backup.Cloud.ps1"
. "$PSScriptRoot\Backup.Storage.ps1"
. "$PSScriptRoot\Backup.Setup.ps1"

function Test-PathWithin {
    param([string]$Path, [string]$Root)
    $p = [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $r = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    return $p.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or
        $p.StartsWith($r + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-BackupFiles {
    param([string]$Root, [switch]$ExistingBackup)
    Assert-PlainPath $Root -AllowCloudSource:(-not $ExistingBackup)
    $stack = New-Object 'Collections.Generic.Stack[string]'
    $stack.Push($Root)
    while ($stack.Count) {
        $directory = $stack.Pop()
        Assert-PlainPath $directory -AllowCloudSource:(-not $ExistingBackup)
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) {
            if ($ExistingBackup -and ($item.Name -eq '_RELATORIOS' -or $item.Name -eq '.backup.lock' -or
                $item.Name -like '.stage-*' -or $item.Name -like '.history-*')) { continue }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                Assert-PlainPath $item.FullName -AllowCloudSource:(-not $ExistingBackup)
            }
            if ($item.PSIsContainer) { $stack.Push($item.FullName) } else { $item }
        }
    }
}

function Get-BackupHash {
    param([string]$Path, [switch]$Source)
    if ($Source) { Assert-SourceFileAvailable $Path } else { Assert-PlainPath $Path }
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Copy-VerifiedFile {
    param([string]$Source, [string]$Destination, [string]$Log, [object]$ExpectedIdentity)
    $identity = Assert-ExternalDestination $Destination @($Source) $ExpectedIdentity
    Assert-PlainPath $Log
    $logIdentity = Assert-ExternalDestination $Log @($Source) $identity
    $null = $logIdentity
    # A read-only shared handle prevents writers/deletion during copy and verification.
    Assert-SourceFileAvailable $Source
    $sourceLock = [IO.File]::Open($Source, 'Open', 'Read', 'Read')
    $stage = $null
    try {
        $before = Get-BackupHash $Source -Source
        if (Test-Path -LiteralPath $Destination) {
            if ((Get-BackupHash $Destination) -eq $before) { return 'SKIP_IDENTICAL' }
        }
        $length = (Get-Item -LiteralPath $Source -ErrorAction Stop).Length
        if ($identity.FreeBytes -lt ($length + 16MB)) { throw 'Espaço insuficiente para staging e margem de segurança.' }
        $parent = Split-Path -Parent $Destination
        $null = Assert-ExternalDestination $parent @($Source) $identity
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        $stage = Join-Path $parent ('.stage-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
        $arguments = @((Split-Path -Parent $Source), $stage, (Split-Path -Leaf $Source),
            '/COPY:DAT', '/Z', '/XJ', '/R:2', '/W:2', '/IS', '/IT', '/NP', "/LOG+:$Log")
        & robocopy.exe @arguments | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Robocopy: $LASTEXITCODE" }
        $temporary = Join-Path $stage (Split-Path -Leaf $Source)
        if ((Get-BackupHash $temporary) -ne $before -or (Get-BackupHash $Source -Source) -ne $before) {
            throw 'Conteúdo mudou ou verificação falhou; destino anterior preservado.'
        }
        $null = Assert-ExternalDestination $Destination @($Source) $identity
        if (Test-Path -LiteralPath $Destination) {
            $history = Join-Path $parent ('.history-' + [guid]::NewGuid().ToString('N'))
            [IO.File]::Replace($temporary, $Destination, $history)
        } else { [IO.File]::Move($temporary, $Destination) }
        return 'VERIFIED'
    } finally {
        $sourceLock.Dispose()
        if ($stage) {
            # A changed disk must never receive cleanup writes.
            $null = Assert-ExternalDestination $stage @($Source) $identity
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop
        }
    }
}

function Get-ExistingBackupIndex {
    param([string]$Destination)
    $index = @{}
    if (Test-Path -LiteralPath $Destination) {
        Get-BackupFiles $Destination -ExistingBackup | ForEach-Object {
            $key = ([string]$_.Length) + '|' + (Get-BackupHash $_.FullName)
            if (-not $index.ContainsKey($key)) { $index[$key] = New-Object 'Collections.Generic.List[string]' }
            $index[$key].Add($_.FullName)
        }
    }
    return $index
}

function Find-ExistingContent {
    param([string]$SourceHash, [long]$Length, [hashtable]$Index)
    $key = ([string]$Length) + '|' + $SourceHash
    if ($Index.ContainsKey($key)) {
        foreach ($candidate in $Index[$key]) {
            # Rehash candidates on every decision; no trusted stale hash cache.
            if ((Get-BackupHash $candidate) -eq $SourceHash) { return $candidate }
        }
    }
    return $null
}

function Invoke-BackupPlan {
    param([object[]]$Sources, [string]$Destination, [ValidateSet('Audit','Backup')][string]$Mode = 'Audit')
    Assert-BackupDependencies -Mode $Mode
    if (-not $Sources -or $Sources.Count -eq 0) { throw 'Configure pelo menos uma origem.' }
    $sourcePaths = @($Sources | ForEach-Object { [string]$_.Path })
    $identity = Assert-ExternalDestination $Destination $sourcePaths
    $destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
    if ($destinationPath -eq $identity.Drive.TrimEnd('\')) { throw 'Escolha uma pasta de backup, não a raiz do disco.' }
    $ids = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($source in $Sources) {
        if ($source.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$' -or
            $source.Id -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$' -or -not $ids.Add($source.Id)) {
            throw 'Id inválido/reservado ou repetido; use letras e números no início, depois _ ou -.'
        }
        Assert-PlainPath $source.Path -AllowCloudSource
        if (-not (Test-Path -LiteralPath $source.Path -PathType Container)) { throw "Origem ausente: $($source.Path)" }
        if ((Test-PathWithin $destinationPath $source.Path) -or (Test-PathWithin $source.Path $destinationPath)) {
            throw 'Origem e destino precisam ser árvores independentes.'
        }
    }
    $null = Assert-ExternalDestination $destinationPath $sourcePaths $identity
    New-Item -ItemType Directory -Path $destinationPath -Force -ErrorAction Stop | Out-Null
    $lockPath = Join-Path $destinationPath '.backup.lock'
    Assert-PlainPath $lockPath
    $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $run = Join-Path $destinationPath ('_RELATORIOS\' + [guid]::NewGuid().ToString('N'))
        $null = Assert-ExternalDestination $run $sourcePaths $identity
        New-Item -ItemType Directory -Path $run -Force -ErrorAction Stop | Out-Null
        $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $errors = 0
        $csv = Join-Path $run 'inventario.csv'
        # Finish indexing the selected backup folder before copying anything.
        try { $index = Get-ExistingBackupIndex $destinationPath }
        catch {
            $null = Assert-ExternalDestination $run $sourcePaths $identity
            $_.Exception.Message | Set-Content -LiteralPath (Join-Path $run 'erros.txt') -Encoding UTF8
            Write-BackupReview -Run $run -Sources $Sources -Mode $Mode -Errors 1
            throw "Índice do backup incompleto; nenhuma cópia iniciada. Consulte $run"
        }
        foreach ($source in $Sources) {
            $root = [IO.Path]::GetFullPath($source.Path).TrimEnd('\')
            try {
                Get-BackupFiles $root | ForEach-Object {
                    $file = $_
                    if ($seen.Add($file.FullName)) {
                        $relative = $file.FullName.Substring($root.Length + 1)
                        $target = Join-Path (Join-Path $destinationPath $source.Id) $relative
                        $status = 'NEEDS_COPY'; $hash = ''; $message = ''; $actual = ''
                        try {
                            $null = Assert-ExternalDestination $target $sourcePaths $identity
                            $hash = Get-BackupHash $file.FullName -Source
                            $existing = Find-ExistingContent $hash $file.Length $index
                            if ($existing) {
                                $actual = $existing
                                $status = if ($existing -eq $target) { 'SKIP_IDENTICAL' } else { 'REUSED_EXISTING' }
                            } elseif ($Mode -eq 'Backup') {
                                $status = Copy-VerifiedFile $file.FullName $target (Join-Path $run 'robocopy.log') $identity
                                if ((Get-BackupHash $target) -ne $hash) { throw 'A origem mudou desde a comparação; execute novamente.' }
                                $actual = $target
                                $key = ([string]$file.Length) + '|' + $hash
                                if (-not $index.ContainsKey($key)) { $index[$key] = New-Object 'Collections.Generic.List[string]' }
                                $index[$key].Add($target)
                            }
                        } catch { $status = 'ERROR'; $message = $_.Exception.Message; $errors++ }
                        $null = Assert-ExternalDestination $csv $sourcePaths $identity
                        [pscustomobject]@{Source=$file.FullName; RelativePath=('.\' + $relative); RootId=$source.Id;
                            PlannedDestination=$target; Destination=$actual; Bytes=$file.Length;
                            SHA256=$hash; Status=$status; Error=$message} |
                            Export-Csv -LiteralPath $csv -Append -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                    }
                }
            } catch {
                $errors++
                $null = Assert-ExternalDestination $run $sourcePaths $identity
                $_.Exception.Message | Add-Content -LiteralPath (Join-Path $run 'erros.txt') -ErrorAction Stop
            }
        }
        $null = Assert-ExternalDestination $run $sourcePaths $identity
        [pscustomobject]@{Mode=$Mode; Errors=$errors; Report=$run; FormattingDecision='NOT_ASSESSED';
            DiskId=$identity.DiskId; VolumeId=$identity.VolumeId} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'resumo.json') -Encoding UTF8
        Write-BackupReview -Run $run -Sources $Sources -Mode $Mode -Errors $errors
        Write-Host "Relatório para revisão: $(Join-Path $run 'LEIA-ME.html')"
        if ($errors) { throw "$errors erro(s). Consulte $run" }
        return $run
    } finally { $lock.Dispose() }
}

Export-ModuleMember -Function Assert-BackupDependencies, Write-BackupReview, Test-PathWithin,
    Get-BackupFiles, Get-BackupHash, Copy-VerifiedFile, Invoke-BackupPlan,
    Assert-PlainPath, Get-StorageIdentity, Assert-ExternalDestination, Select-BackupDestination,
    Get-ExistingBackupIndex, Find-ExistingContent, New-BackupConfiguration,
    Get-ReparseTag, Test-CloudReparseTag, Assert-SourceFileAvailable
