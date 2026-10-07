#Requires -Version 5.1
Set-StrictMode -Version Latest
. "$PSScriptRoot\Backup.Review.ps1"

function Test-PathWithin {
    param([string]$Path, [string]$Root)
    $p = [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $r = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    return $p.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or
        $p.StartsWith($r + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-BackupFiles {
    param([string]$Root)
    $stack = New-Object 'Collections.Generic.Stack[string]'
    $stack.Push($Root)
    while ($stack.Count) {
        $directory = $stack.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse point precisa de revisão/materialização: $($item.FullName)"
            }
            if ($item.PSIsContainer) { $stack.Push($item.FullName) }
            else { $item }
        }
    }
}

function Get-BackupHash {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Copy-VerifiedFile {
    param([string]$Source, [string]$Destination, [string]$Log)
    $before = Get-BackupHash $Source
    if (Test-Path -LiteralPath $Destination) {
        if ((Get-BackupHash $Destination) -eq $before) { return 'SKIP_IDENTICAL' }
    }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    # Stage in the same directory: replacement happens only after verification.
    $stage = Join-Path $parent ('.stage-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -ErrorAction Stop | Out-Null
    try {
        $arguments = @((Split-Path -Parent $Source), $stage, (Split-Path -Leaf $Source),
            '/COPY:DAT', '/Z', '/XJ', '/R:2', '/W:2', '/IS', '/IT', '/NP', "/LOG+:$Log")
        & robocopy.exe @arguments | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Robocopy: $LASTEXITCODE" }
        $temporary = Join-Path $stage (Split-Path -Leaf $Source)
        if ((Get-BackupHash $temporary) -ne $before -or (Get-BackupHash $Source) -ne $before) {
            throw 'Conteúdo mudou ou verificação falhou; destino anterior preservado.'
        }
        if (Test-Path -LiteralPath $Destination) {
            $history = Join-Path $parent ('.history-' + [guid]::NewGuid().ToString('N'))
            [IO.File]::Replace($temporary, $Destination, $history)
        } else { [IO.File]::Move($temporary, $Destination) }
        return 'VERIFIED'
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop
    }
}

function Invoke-BackupPlan {
    param([object[]]$Sources, [string]$Destination, [ValidateSet('Audit','Backup')][string]$Mode = 'Audit')
    Assert-BackupDependencies -Mode $Mode
    if (-not $Sources -or $Sources.Count -eq 0) { throw 'Configure pelo menos uma origem.' }
    $destinationPath = [IO.Path]::GetFullPath($Destination)
    $ids = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($source in $Sources) {
        if ($source.Id -notmatch '^[A-Za-z0-9_-]+$' -or -not $ids.Add($source.Id)) {
            throw 'Cada origem precisa de Id único, contendo letras, números, _ ou -.'
        }
        if (-not (Test-Path -LiteralPath $source.Path -PathType Container)) { throw "Origem ausente: $($source.Path)" }
        $rootItem = Get-Item -LiteralPath $source.Path -Force
        if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Raiz reparse não permitida.' }
        if ((Test-PathWithin $destinationPath $source.Path) -or (Test-PathWithin $source.Path $destinationPath)) {
            throw 'Origem e destino precisam ser árvores independentes.'
        }
    }
    New-Item -ItemType Directory -Path $destinationPath -Force -ErrorAction Stop | Out-Null
    $lock = [IO.File]::Open((Join-Path $destinationPath '.backup.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $run = Join-Path $destinationPath ('_RELATORIOS\' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $run -Force | Out-Null
        $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $errors = 0
        $csv = Join-Path $run 'inventario.csv'
        foreach ($source in $Sources) {
            $root = [IO.Path]::GetFullPath($source.Path).TrimEnd('\','/')
            try {
                Get-BackupFiles $root | ForEach-Object {
                    $file = $_
                    if ($seen.Add($file.FullName)) {
                        $relative = $file.FullName.Substring($root.Length + 1)
                        $target = Join-Path (Join-Path $destinationPath $source.Id) $relative
                        $status = 'AUDITED'; $hash = ''; $message = ''
                        try {
                            if ($Mode -eq 'Backup') {
                                $status = Copy-VerifiedFile $file.FullName $target (Join-Path $run 'robocopy.log')
                                $hash = Get-BackupHash $target
                            }
                        } catch { $status = 'ERROR'; $message = $_.Exception.Message; $errors++ }
                        [pscustomobject]@{Source=$file.FullName; Destination=$target; Bytes=$file.Length;
                            SHA256=$hash; Status=$status; Error=$message} |
                            Export-Csv -LiteralPath $csv -Append -NoTypeInformation -Encoding UTF8
                    }
                }
            } catch {
                $errors++
                $_.Exception.Message | Add-Content -LiteralPath (Join-Path $run 'erros.txt')
            }
        }
        [pscustomobject]@{Mode=$Mode; Errors=$errors; Report=$run; FormattingDecision='NOT_ASSESSED'} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'resumo.json') -Encoding UTF8
        Write-BackupReview -Run $run -Sources $Sources -Mode $Mode -Errors $errors
        Write-Host "Relatório para revisão: $(Join-Path $run 'LEIA-ME.html')"
        if ($errors) { throw "$errors erro(s). Consulte $run" }
        return $run
    } finally { $lock.Dispose() }
}

Export-ModuleMember -Function Assert-BackupDependencies, Write-BackupReview, Test-PathWithin, Get-BackupFiles, Get-BackupHash, Copy-VerifiedFile, Invoke-BackupPlan
