function Get-DependencyFolder {
    param([string]$Path)
    $name=[IO.Path]::GetFileName($Path.TrimEnd('\'))
    $parent=[IO.Path]::GetDirectoryName($Path.TrimEnd('\'))
    if (-not $parent) { return $null }
    # Caches regeneráveis conhecidos: decisão por diretório, sem visitar milhares
    # de arquivos .pyc e índices. -DependencyPolicy Include permite auditoria total.
    if ($name -in @('__pycache__','.pytest_cache','.mypy_cache','.ruff_cache')) {
        return [pscustomobject]@{Path=$Path;Kind='Cache gerado';Evidence='Nome padrão de cache';Decision='DEFERRED';
            EstimatedBytes=$null;OwnerRoot='';OwnerId='';
            Note='Cache regenerável não é incluído por padrão. Use Include se você guardou dados próprios aqui.'}
    }
    $evidence=$null; $kind=$null
    if ($name -ieq 'node_modules') {
        foreach ($marker in @((Join-Path $parent 'package.json'),(Join-Path $Path '.package-lock.json'))) {
            if (Test-Path -LiteralPath $marker -PathType Leaf) { $evidence=$marker; $kind='Node dependencies'; break }
        }
    } elseif ($name -ieq 'site-packages' -and [IO.Path]::GetFileName($parent) -ieq 'Lib') {
        $environment=[IO.Path]::GetDirectoryName($parent)
        foreach ($marker in @((Join-Path $environment 'pyvenv.cfg'),(Join-Path $environment 'conda-meta\history'))) {
            if (Test-Path -LiteralPath $marker -PathType Leaf) { $evidence=$marker; $kind='Python dependencies'; break }
        }
        if (-not $evidence -and (Test-Path -LiteralPath (Join-Path $environment 'Scripts\activate.bat') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $environment 'Scripts\python.exe') -PathType Leaf)) {
            $evidence=Join-Path $environment 'Scripts\activate.bat'; $kind='Python dependencies'
        }
    }
    if ($evidence) {
        # Metadata marker only. Never execute a discovered Python, npm or Conda.
        Assert-PlainPath $evidence -AllowCloudSource
        return [pscustomobject]@{Path=$Path;Kind=$kind;Evidence=$evidence;Decision='DEFERRED';
            EstimatedBytes=$null;OwnerRoot='';OwnerId='';
            Note='Bibliotecas opcionais. Reinstalação exige manifests/lockfiles e disponibilidade dos pacotes; alterações locais aqui não são dados essenciais pela política escolhida.'}
    }
    return $null
}

function Get-DirectoryPriority {
    param([string]$Path)
    switch ([IO.Path]::GetFileName($Path).ToLowerInvariant()) {
        {$_ -in @('users','documents','documentos','desktop','área de trabalho','pictures','imagens','downloads','projetos','projects','jupyter')} { return 0 }
        'onedrive' { return 1 }
        {$_ -in @('appdata','programdata','node_modules','site-packages')} { return 9 }
        default { return 5 }
    }
}

function Save-BackupDecisions {
    if ($null -eq $script:BackupProgress -or -not $script:BackupProgress.ContainsKey('Dependencies')) { return }
    $state=$script:BackupProgress
    $null=Assert-ExternalDestination $state.Run $state.SourcePaths $state.Identity
    if ($state.Dependencies.Count) {
        $state.Dependencies | Export-Csv -LiteralPath (Join-Path $state.Run 'dependencias.csv') -NoTypeInformation -Encoding UTF8
    }
    if ($state.IndexSkipped.Count) {
        $state.IndexSkipped | Export-Csv -LiteralPath (Join-Path $state.Run 'indice-excluido.csv') -NoTypeInformation -Encoding UTF8
    }
    if ($state.EnumerationIssues.Count) {
        $state.EnumerationIssues | Export-Csv -LiteralPath (Join-Path $state.Run 'falhas-enumeracao.csv') -NoTypeInformation -Encoding UTF8
    }
}
