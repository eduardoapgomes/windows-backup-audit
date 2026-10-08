# Merkle describes freshly observed inventory content; never authorizes skipping source reads.
function Get-MerkleDigest {
    param([string[]]$Parts)
    $stream=New-Object IO.MemoryStream
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        foreach ($part in $Parts) {
            $bytes=[Text.Encoding]::UTF8.GetBytes($part)
            $prefix=[Text.Encoding]::ASCII.GetBytes(([string]$bytes.Length)+':')
            $stream.Write($prefix,0,$prefix.Length); $stream.Write($bytes,0,$bytes.Length)
        }
        return [BitConverter]::ToString($sha.ComputeHash($stream.ToArray())).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose(); $stream.Dispose() }
}
function Add-MerkleDirectory {
    param([string]$Path,[hashtable]$Nodes,[hashtable]$Children)
    if ($Nodes.ContainsKey($Path)) { return }
    $Nodes[$Path]=[ordered]@{Kind='directory';Hash='';Valid=$true;Children=@()}
    $Children[$Path]=@{}
    if ($Path -ne '@') {
        $separator=$Path.LastIndexOf('/')
        $parent=if($separator -lt 0){'@'}else{$Path.Substring(0,$separator)}
        $name=if($separator -lt 0){$Path}else{$Path.Substring($separator+1)}
        Add-MerkleDirectory $parent $Nodes $Children
        $Children[$parent][$name]=$Path
    }
}
function Compare-BackupManifest {
    param([object]$Current,[object]$Previous)
    $result=New-Object 'Collections.Generic.List[object]'
    if ($Current.Format -ne $Previous.Format -or $Current.ScopeHash -ne $Previous.ScopeHash) {
        $result.Add([pscustomobject]@{Path='';Status='SCOPE_CHANGED';Note='Escopo/formato mudou; comparação de subárvores indisponível.'})
        return $result.ToArray()
    }
    $currentNodes=@{}; $previousNodes=@{}
    foreach ($property in $Current.Nodes.PSObject.Properties) { $currentNodes[$property.Name]=$property.Value }
    foreach ($property in $Previous.Nodes.PSObject.Properties) { $previousNodes[$property.Name]=$property.Value }
    $stack=New-Object 'Collections.Generic.Stack[string]'; $stack.Push('@')
    while($stack.Count) {
        $path=$stack.Pop(); $a=$currentNodes[$path]; $b=$previousNodes[$path]
        if ($null -eq $a -or $null -eq $b) {
            $status=if($null -eq $a){'NOT_OBSERVED_NOW'}else{'NEWLY_OBSERVED'}
            $result.Add([pscustomobject]@{Path=$path;Status=$status;Note='Não implica exclusão física nem cobertura completa.'}); continue
        }
        if ($a.Valid -and $b.Valid -and $a.Hash -eq $b.Hash) {
            $result.Add([pscustomobject]@{Path=$path;Status='SAME_OBSERVED_SUBTREE';Note='Conteúdo observado igual; não dispensa leitura no próximo backup.'}); continue
        }
        if($a.Kind -eq 'directory' -and $b.Kind -eq 'directory') {
            $names=@(@($a.Children)+@($b.Children) | Select-Object -Unique)
            foreach($name in $names) { $child=if($path -ne '@'){$path+'/'+$name}else{$name}; $stack.Push($child) }
        } else {
            $status=if(-not $a.Valid -or -not $b.Valid){'UNVERIFIED'}else{'CONTENT_CHANGED'}
            $result.Add([pscustomobject]@{Path=$path;Status=$status;Note='Comparação entre registros de inventário.'})
        }
    }
    return $result.ToArray()
}
function Write-BackupManifest {
    param([string]$Run,[object[]]$Sources,[string[]]$ExcludedPaths,[string]$DependencyPolicy,[int]$Errors,[object[]]$Dependencies)
    $nodes=@{}; $children=@{}
    Add-MerkleDirectory '@' $nodes $children
    foreach($source in $Sources) { Add-MerkleDirectory $source.Id $nodes $children }
    $inventory=Join-Path $Run 'inventario.csv'
    if(Test-Path -LiteralPath $inventory) {
        Import-Csv -LiteralPath $inventory | ForEach-Object {
            Show-BackupProgress -Phase 'Construindo manifesto Merkle' -Path $_.Source
            $relative=$_.RelativePath.Substring(2).Replace('\','/')
            $path=$_.RootId+'/'+$relative
            $split=$path.LastIndexOf('/'); $parent=$path.Substring(0,$split); $name=$path.Substring($split+1)
            Add-MerkleDirectory $parent $nodes $children
            $valid=$_.SHA256 -match '^[0-9a-fA-F]{64}$' -and $_.Status -ne 'ERROR'
            $content=if($valid){$_.SHA256.ToLowerInvariant()}else{'UNREAD'}
            $nodes[$path]=[ordered]@{Kind='file';Hash=(Get-MerkleDigest @('file',[string]$_.Bytes,$content));Valid=$valid;
                Bytes=[long]$_.Bytes;SHA256=$content;Source=$_.Source;Destination=$_.Destination;Status=$_.Status}
            $children[$parent][$name]=$path
        }
    }
    foreach($path in @($children.Keys | Sort-Object @{Expression={if($_ -eq '@'){-1}else{($_ -split '/').Count}}} -Descending)) {
        [string[]]$names=@($children[$path].Keys); [Array]::Sort($names,[StringComparer]::Ordinal)
        $parts=New-Object 'Collections.Generic.List[string]'; $parts.Add('directory')
        foreach($name in $names) {
            $node=$nodes[$children[$path][$name]]
            $parts.Add($name); $parts.Add($node.Hash)
            if(-not $node.Valid) { $nodes[$path].Valid=$false }
        }
        $nodes[$path].Children=@($names)
        $nodes[$path].Hash=Get-MerkleDigest $parts.ToArray()
    }
    $scopeParts=New-Object 'Collections.Generic.List[string]'; $scopeParts.Add('scope-v1'); $scopeParts.Add($DependencyPolicy)
    foreach($source in ($Sources | Sort-Object Id)) { $scopeParts.Add([string]$source.Id);$scopeParts.Add([string]$source.Path) }
    foreach($excluded in ($ExcludedPaths | Sort-Object)) { $scopeParts.Add($excluded) }
    $manifest=[ordered]@{Format='windows-backup-merkle-v1';Scope='OBSERVED_FILES_ONLY';ScopeHash=(Get-MerkleDigest $scopeParts.ToArray());
        ContentRoot=$nodes['@'].Hash;ObservedHashesComplete=$nodes['@'].Valid;CoverageComplete=$false;Errors=$Errors;
        Dependencies=@($Dependencies | Select-Object Path,Decision);Nodes=$nodes;
        Warning='Não inclui pastas vazias, arquivos não enumerados ou dados excluídos. Não é snapshot transacional nem cache confiável de mudanças.'}
    $null=Assert-ExternalDestination $Run $script:BackupProgress.SourcePaths $script:BackupProgress.Identity
    $manifestPath=Join-Path $Run 'merkle.json'
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    (Get-BackupHash $manifestPath) | Set-Content -LiteralPath (Join-Path $Run 'merkle.sha256') -Encoding ASCII
    $current=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $previousRun=Get-ChildItem -LiteralPath (Split-Path -Parent $Run) -Directory |
        Where-Object { $_.FullName -ne $Run -and (Test-Path -LiteralPath (Join-Path $_.FullName 'merkle.sha256')) } |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if($previousRun) {
        $previousPath=Join-Path $previousRun.FullName 'merkle.json'
        $checksum=Join-Path $previousRun.FullName 'merkle.sha256'
        Assert-PlainPath $checksum
        if((Get-BackupHash $previousPath) -ne (Get-Content -LiteralPath $checksum -Raw).Trim()) {
            [pscustomobject]@{Path=$previousPath;Status='BASELINE_INVALID';Note='Checksum anterior inválido; nenhuma decisão de cópia depende dele.'} |
                Export-Csv -LiteralPath (Join-Path $Run 'merkle-delta.csv') -NoTypeInformation -Encoding UTF8
        } else {
            $previous=Get-Content -LiteralPath $previousPath -Raw | ConvertFrom-Json
            Compare-BackupManifest $current $previous |
                Export-Csv -LiteralPath (Join-Path $Run 'merkle-delta.csv') -NoTypeInformation -Encoding UTF8
        }
    }
}
