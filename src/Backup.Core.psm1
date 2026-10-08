#Requires -Version 5.1
Set-StrictMode -Version Latest
. "$PSScriptRoot\Backup.Html.ps1"
. "$PSScriptRoot\Backup.Review.ps1"
. "$PSScriptRoot\Backup.Cloud.ps1"
. "$PSScriptRoot\Backup.Storage.ps1"
. "$PSScriptRoot\Backup.Setup.ps1"
. "$PSScriptRoot\Backup.Partial.ps1"
. "$PSScriptRoot\Backup.Progress.ps1"
. "$PSScriptRoot\Backup.Discovery.ps1"
. "$PSScriptRoot\Backup.Policy.ps1"
. "$PSScriptRoot\Backup.Merkle.ps1"

function Test-PathWithin {
    param([string]$Path, [string]$Root)
    $p = [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $r = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    return $p.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or
        $p.StartsWith($r + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-BackupFiles {
    param([string]$Root, [switch]$ExistingBackup, [string[]]$ExcludedPaths=@(),
        [Collections.Generic.List[object]]$Issues,
        [ValidateSet('Auto','Exclude','Include')][string]$DependencyPolicy='Include',
        [Collections.Generic.List[object]]$Dependencies, [string]$OwnerId='', [string]$OwnerRoot='')
    Assert-PlainPath $Root -AllowCloudSource:(-not $ExistingBackup)
    $stack = New-Object 'Collections.Generic.Stack[string]'
    $stack.Push($Root)
    while ($stack.Count) {
        $directory = $stack.Pop()
        Show-BackupProgress -Phase 'Enumerando pastas' -Path $directory
        try {
            Assert-PlainPath $directory -AllowCloudSource:(-not $ExistingBackup)
            if ($DependencyPolicy -ne 'Include') {
                $decision=Get-DependencyFolder $directory
                if ($null -ne $decision) {
                    $decision.OwnerId=$OwnerId; $decision.OwnerRoot=$OwnerRoot
                    $decision.Decision=if ($ExistingBackup) {'INDEX_NOT_SCANNED'} elseif ($DependencyPolicy -eq 'Exclude') {'EXCLUDED_BY_POLICY'} else {'DEFERRED'}
                    if ($null -ne $Dependencies) { $Dependencies.Add($decision) }
                    Save-BackupDecisions
                    continue
                }
            }
            $items = @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)
        } catch {
            if ($ExistingBackup -or $null -eq $Issues) { throw }
            $Issues.Add([pscustomobject]@{Path=$directory;Status='ERROR';Reason=$_.Exception.Message})
            continue
        }
        $directories=New-Object 'Collections.Generic.List[string]'
        foreach ($item in $items) {
            if (@($ExcludedPaths | Where-Object { Test-PathWithin $item.FullName $_ }).Count) { continue }
            if ($ExistingBackup -and ($item.Name -eq '_RELATORIOS' -or $item.Name -eq '.backup.lock' -or
                $item.Name -like '.stage-*' -or $item.Name -like '.history-*')) { continue }
            try {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    Assert-PlainPath $item.FullName -AllowCloudSource:(-not $ExistingBackup)
                }
                if ($item.PSIsContainer) { $directories.Add($item.FullName) } else { $item }
            } catch {
                if ($ExistingBackup -or $null -eq $Issues) { throw }
                $Issues.Add([pscustomobject]@{Path=$item.FullName;Status='ERROR';Reason=$_.Exception.Message})
            }
        }
        # LIFO: push lower-priority directories first so personal folders run first.
        foreach ($child in ($directories | Sort-Object @{Expression={Get-DirectoryPriority $_};Descending=$true}, @{Expression={$_};Descending=$true})) { $stack.Push($child) }
    }
}

function Get-BackupHash {
    param([string]$Path, [switch]$Source)
    if ($Source) { Assert-SourceFileAvailable $Path } else { Assert-PlainPath $Path }
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    $sha = [Security.Cryptography.SHA256]::Create()
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $buffer = New-Object byte[] ([int][Math]::Max(1, [Math]::Min(4MB, $stream.Length)))
        $readTotal = [long]0
        Show-BackupProgress -Phase 'Calculando SHA-256' -Path $Path -TotalBytes $stream.Length
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $null = $sha.TransformBlock($buffer, 0, $read, $buffer, 0)
            $readTotal += $read
            Show-BackupProgress -Phase 'Calculando SHA-256' -Path $Path -ReadBytes $readTotal -TotalBytes $stream.Length
        }
        $null = $sha.TransformFinalBlock($buffer, 0, 0)
        Show-BackupProgress -Phase 'Calculando SHA-256' -Path $Path -ReadBytes $readTotal -TotalBytes $stream.Length -FileCompleted
        return [BitConverter]::ToString($sha.Hash).Replace('-','')
    }
    finally {
        $timer.Stop()
        if ($null -ne $script:BackupProgress) { $script:BackupProgress.HashSeconds += $timer.Elapsed.TotalSeconds }
        $sha.Dispose(); $stream.Dispose()
    }
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
            '/COPY:DAT', '/Z', '/XJ', '/R:2', '/W:2', '/IS', '/IT', '/TEE', "/LOG+:$Log")
        Show-BackupProgress -Phase 'Copiando com Robocopy' -Path $Source
        & robocopy.exe @arguments | Out-Host
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
    param([string]$Destination, [string]$DependencyPolicy='Include', [Collections.Generic.List[object]]$Dependencies)
    $index = @{}
    if (Test-Path -LiteralPath $Destination) {
        Get-BackupFiles $Destination -ExistingBackup -DependencyPolicy $DependencyPolicy -Dependencies $Dependencies | ForEach-Object {
            $key = '@size|' + ([string]$_.Length)
            if ($null -ne $script:BackupProgress) { $script:BackupProgress.DestinationIndexedFiles++ }
            if (-not $index.ContainsKey($key)) { $index[$key] = New-Object 'Collections.Generic.List[string]' }
            $index[$key].Add($_.FullName)
        }
    }
    return $index
}

function Find-ExistingContent {
    param([string]$SourceHash, [long]$Length, [hashtable]$Index)
    $pending = '@size|' + ([string]$Length)
    if ($Index.ContainsKey($pending)) {
        # Resolve only lengths requested by a source; unrelated destination contents stay unread.
        foreach ($candidate in $Index[$pending]) {
            Assert-PlainPath $candidate
            if ((Get-Item -LiteralPath $candidate -ErrorAction Stop).Length -ne $Length) { continue }
            $candidateHash = Get-BackupHash $candidate
            $candidateKey = ([string]$Length) + '|' + $candidateHash
            if (-not $Index.ContainsKey($candidateKey)) { $Index[$candidateKey] = New-Object 'Collections.Generic.List[string]' }
            $Index[$candidateKey].Add($candidate)
            if ($null -ne $script:BackupProgress) { $script:BackupProgress.DestinationHashCandidates++ }
        }
        $Index.Remove($pending)
        if ($null -ne $script:BackupProgress) { $script:BackupProgress.SizeBucketsResolved++ }
    }
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
    param([object[]]$Sources, [string]$Destination, [ValidateSet('Audit','Backup')][string]$Mode = 'Audit',
        [object[]]$Discovery=@(), [string[]]$ExcludedPaths=@(), [string]$Scope='Configuração manual', [switch]$OpenReport,
        [ValidateSet('Auto','Exclude','Include')][string]$DependencyPolicy='Auto')
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
    Start-BackupProgress $Mode
    try {
        $run = Join-Path $destinationPath ('_RELATORIOS\' + [guid]::NewGuid().ToString('N'))
        $null = Assert-ExternalDestination $run $sourcePaths $identity
        New-Item -ItemType Directory -Path $run -Force -ErrorAction Stop | Out-Null
        $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $errors = @($Discovery | Where-Object Status -eq ERROR).Count
        $issues = New-Object 'Collections.Generic.List[object]'
        $dependencies=New-Object 'Collections.Generic.List[object]'
        $indexSkipped=New-Object 'Collections.Generic.List[object]'
        $csv = Join-Path $run 'inventario.csv'
        $Discovery | Export-Csv -LiteralPath (Join-Path $run 'cobertura.csv') -NoTypeInformation -Encoding UTF8
        [pscustomobject]@{Scope=$Scope;Sources=$Sources;ExcludedPaths=$ExcludedPaths;Discovery=$Discovery;DependencyPolicy=$DependencyPolicy} |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'plano.json') -Encoding UTF8
        $script:BackupProgress.Run=$run
        $script:BackupProgress.Identity=$identity
        $script:BackupProgress.SourcePaths=$sourcePaths
        $script:BackupProgress.EnumerationIssues=$issues
        $script:BackupProgress.Dependencies=$dependencies
        $script:BackupProgress.IndexSkipped=$indexSkipped
        Write-Host "Acompanhamento parcial: $(Join-Path $run 'ANDAMENTO.html')"
        Write-BackupPartial -Phase 'Iniciando comparação' -Path $destinationPath
        if ($OpenReport) {
            try { Start-Process -FilePath (Join-Path $run 'ANDAMENTO.html') }
            catch { Write-Warning "Abra manualmente o acompanhamento em $run. O navegador não pôde ser iniciado." }
        }
        Show-BackupProgress -Phase 'Indexando backup existente' -Path $destinationPath
        # Enumerate the destination safely before copying; hash size-matched candidates on demand.
        try { $index = Get-ExistingBackupIndex $destinationPath -DependencyPolicy $DependencyPolicy -Dependencies $indexSkipped }
        catch {
            $null = Assert-ExternalDestination $run $sourcePaths $identity
            $_.Exception.Message | Set-Content -LiteralPath (Join-Path $run 'erros.txt') -Encoding UTF8
            Write-BackupReview -Run $run -Sources $Sources -Mode $Mode -Errors 1
            Write-BackupPartial -Phase 'Índice incompleto' -Finished
            throw "Índice do backup incompleto; nenhuma cópia iniciada. Consulte $run"
        }
        $optionalIndexed=$false
        $tasks=New-Object 'Collections.Generic.List[object]'
        foreach ($source in $Sources) { $tasks.Add([pscustomobject]@{Id=$source.Id;Path=$source.Path;BasePath=$source.Path;Optional=$false;Decision=$null}) }
        for ($taskNumber=0; $taskNumber -lt $tasks.Count; $taskNumber++) {
            $source=$tasks[$taskNumber]
            $root = [IO.Path]::GetFullPath($source.BasePath).TrimEnd('\')
            try {
                $optionalFiles=$null
                if ($source.Optional) {
                    if ($errors -gt 0 -or $issues.Count -gt 0) {
                        $source.Decision.Decision='NOT_COPIED_ESSENTIAL_OR_PREVIOUS_ERRORS'; Save-BackupDecisions; continue
                    }
                    Show-BackupProgress -Phase 'Dimensionando bibliotecas opcionais' -Path $source.Path
                    $optionalFiles=@(Get-BackupFiles $source.Path -Issues $issues)
                    $estimated=[long](($optionalFiles | Measure-Object Length -Sum).Sum)
                    $source.Decision.EstimatedBytes=$estimated
                    if ($issues.Count -gt 0) { $source.Decision.Decision='NOT_COPIED_ENUMERATION_ERRORS'; Save-BackupDecisions; continue }
                    $space=Assert-ExternalDestination $destinationPath $sourcePaths $identity
                    if ($space.FreeBytes -lt ($estimated + 256MB)) {
                        $source.Decision.Decision='NOT_COPIED_SPACE'; Save-BackupDecisions; continue
                    }
                    if (-not $optionalIndexed) {
                        foreach ($skipped in $indexSkipped) {
                            $extra=Get-ExistingBackupIndex $skipped.Path
                            foreach ($key in $extra.Keys) {
                                if (-not $index.ContainsKey($key)) { $index[$key]=New-Object 'Collections.Generic.List[string]' }
                                foreach ($candidate in $extra[$key]) { $index[$key].Add($candidate) }
                            }
                        }
                        $optionalIndexed=$true
                    }
                    $source.Decision.Decision='COPYING_OPTIONAL'; Save-BackupDecisions
                }
                $getFiles = {
                    if ($source.Optional) { $optionalFiles }
                    else { Get-BackupFiles $source.Path -ExcludedPaths $ExcludedPaths -Issues $issues -DependencyPolicy $DependencyPolicy -Dependencies $dependencies -OwnerId $source.Id -OwnerRoot $source.BasePath }
                }
                & $getFiles | ForEach-Object {
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
                            SHA256=$hash; Status=$status; Error=$message; Category=(Get-BackupCategory $file.FullName); Priority=$(if ($source.Optional) {'OPTIONAL_DEPENDENCY'} else {'ESSENTIAL'})} |
                            Export-Csv -LiteralPath $csv -Append -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                        $script:BackupProgress.AuditFiles++
                        $script:BackupProgress.AuditBytes += $file.Length
                        if (-not $script:BackupProgress.Results.ContainsKey($status)) { $script:BackupProgress.Results[$status]=0 }
                        $script:BackupProgress.Results[$status]++
                        Show-BackupProgress -Phase 'Comparando arquivos' -Path $file.FullName
                    }
                }
            } catch {
                $errors++
                $null = Assert-ExternalDestination $run $sourcePaths $identity
                $_.Exception.Message | Add-Content -LiteralPath (Join-Path $run 'erros.txt') -ErrorAction Stop
            }
            if ($source.Optional) { $source.Decision.Decision=if ($errors -or $issues.Count) {'OPTIONAL_INCOMPLETE'} else {'OPTIONAL_VERIFIED'} }
            if ($taskNumber -eq ($Sources.Count - 1) -and $Mode -eq 'Backup' -and $DependencyPolicy -eq 'Auto') {
                foreach ($decision in $dependencies) {
                    $tasks.Add([pscustomobject]@{Id=$decision.OwnerId;Path=$decision.Path;BasePath=$decision.OwnerRoot;Optional=$true;Decision=$decision})
                }
            }
            Save-BackupDecisions
        }
        Save-BackupDecisions
        $null = Assert-ExternalDestination $run $sourcePaths $identity
        if ($issues.Count) {
            $errors += $issues.Count
            $issues | Export-Csv -LiteralPath (Join-Path $run 'falhas-enumeracao.csv') -NoTypeInformation -Encoding UTF8
        }
        try {
            Write-BackupManifest -Run $run -Sources $Sources -ExcludedPaths $ExcludedPaths -DependencyPolicy $DependencyPolicy -Errors $errors -Dependencies $dependencies
        } catch {
            $errors++
            $_.Exception.Message | Add-Content -LiteralPath (Join-Path $run 'erros.txt') -ErrorAction Stop
        }
        [pscustomobject]@{HashReads=$script:BackupProgress.Files;HashBytes=$script:BackupProgress.Bytes;
            HashSeconds=$script:BackupProgress.HashSeconds;DestinationIndexedFiles=$script:BackupProgress.DestinationIndexedFiles;
            DestinationHashCandidates=$script:BackupProgress.DestinationHashCandidates;SizeBucketsResolved=$script:BackupProgress.SizeBucketsResolved;
            ElapsedSeconds=([DateTime]::UtcNow-$script:BackupProgress.Started).TotalSeconds} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'metricas.json') -Encoding UTF8
        [pscustomobject]@{Mode=$Mode; Errors=$errors; Report=$run; FormattingDecision='NOT_ASSESSED';
            DiskId=$identity.DiskId; VolumeId=$identity.VolumeId; DependencyPolicy=$DependencyPolicy; DependencyFolders=$dependencies.Count} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'resumo.json') -Encoding UTF8
        Write-BackupReview -Run $run -Sources $Sources -Mode $Mode -Errors $errors
        Write-BackupPartial -Phase 'Execução encerrada' -Finished
        Write-Host "Relatório para revisão: $(Join-Path $run 'LEIA-ME.html')"
        if ($errors) { throw "$errors erro(s). Consulte $run" }
        return $run
    } finally { $lock.Dispose(); Stop-BackupProgress }
}

Export-ModuleMember -Function Assert-BackupDependencies, Write-BackupReview, Test-PathWithin,
    Get-BackupFiles, Get-BackupHash, Copy-VerifiedFile, Invoke-BackupPlan,
    Assert-PlainPath, Get-StorageIdentity, Assert-ExternalDestination, Select-BackupDestination,
    Get-ExistingBackupIndex, Find-ExistingContent, New-BackupConfiguration,
    Get-ReparseTag, Test-CloudReparseTag, Assert-SourceFileAvailable, Get-AutomaticBackupPlan,
    Start-BackupProgress, Show-BackupProgress, Stop-BackupProgress, Get-DependencyFolder, Get-MerkleDigest, Write-BackupManifest, Compare-BackupManifest
