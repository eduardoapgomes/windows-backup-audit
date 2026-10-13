# =============================================================================
# Destino: só aceita um HD/SSD externo USB, NTFS, gravável, que não seja o disco
# do sistema e que esteja em disco FÍSICO diferente de todas as origens.
# Não existe opção para desligar essas verificações.
# =============================================================================

$script:CacheDisco = @{}

function Clear-CacheDisco { $script:CacheDisco = @{} }

function Get-LetraUnidade {
    param([Parameter(Mandatory)][string]$Caminho)
    if ($Caminho -match '^([A-Za-z]):') { return $Matches[1].ToUpperInvariant() }
    throw "Caminho sem letra de unidade: $Caminho"
}

function Get-InfoDisco {
    # Consulta o Windows (módulo Storage) uma vez por unidade em cada execução.
    param([Parameter(Mandatory)][string]$Letra)
    $Letra = $Letra.Substring(0, 1).ToUpperInvariant()
    if ($script:CacheDisco.ContainsKey($Letra)) { return $script:CacheDisco[$Letra] }
    $particoes = @(Get-Partition -DriveLetter $Letra -ErrorAction Stop)
    if ($particoes.Count -ne 1) { throw "Não foi possível identificar a partição da unidade ${Letra}:." }
    $disco = Get-Disk -Number $particoes[0].DiskNumber -ErrorAction Stop
    $volume = Get-Volume -DriveLetter $Letra -ErrorAction Stop
    $info = [pscustomobject]@{
        Letra           = $Letra
        DiscoId         = [string]$disco.UniqueId
        Modelo          = [string]$disco.FriendlyName
        Barramento      = [string]$disco.BusType
        DiscoDoSistema  = [bool]($disco.IsBoot -or $disco.IsSystem)
        Offline         = [bool]$disco.IsOffline
        SomenteLeitura  = [bool]$disco.IsReadOnly
        SistemaArquivos = [string]$volume.FileSystem
        Rotulo          = [string]$volume.FileSystemLabel
        Tamanho         = [long]$volume.Size
    }
    $script:CacheDisco[$Letra] = $info
    return $info
}

function Assert-SemLinks {
    # Nenhuma pasta no caminho do destino pode ser junction/link: a gravação iria para outro lugar.
    param([Parameter(Mandatory)][string]$Caminho)
    $atual = $Caminho
    while ($atual -and $atual -ne [IO.Path]::GetPathRoot($atual)) {
        $estado = [WindowsBackupAudit.Nativo]::Info($atual)
        if ($null -ne $estado -and ($estado.Atributos -band 0x400)) {
            throw "O caminho do destino passa por um link ou junção: $atual. Escolha uma pasta comum no HD externo."
        }
        $pai = [IO.Path]::GetDirectoryName($atual)
        if (-not $pai -or $pai -eq $atual) { break }
        $atual = $pai
    }
}

function Assert-DestinoSeguro {
    param([Parameter(Mandatory)][string]$Destino, [string[]]$Origens = @(), [switch]$PermitirRaiz)
    $letra = Get-LetraUnidade $Destino
    $info = Get-InfoDisco $letra
    if (-not $info.DiscoId) { throw "O Windows não informou a identidade do disco ${letra}:. Por segurança ele não será usado." }
    if ($info.Barramento -ne 'USB') {
        throw "A unidade ${letra}: não é um HD externo USB (tipo informado: $($info.Barramento)). Use um HD ou SSD externo USB."
    }
    if ($info.DiscoDoSistema) { throw "A unidade ${letra}: está no disco onde o Windows está instalado." }
    if ($info.Offline -or $info.SomenteLeitura) { throw "A unidade ${letra}: está desconectada ou protegida contra gravação." }
    if ($info.SistemaArquivos -ne 'NTFS') {
        throw "A unidade ${letra}: usa $($info.SistemaArquivos); o destino precisa ser NTFS. O programa não formata discos: veja docs\GUIA-RAPIDO.md."
    }
    foreach ($o in $Origens) {
        $io = Get-InfoDisco (Get-LetraUnidade $o)
        if (-not $io.DiscoId) { throw "O Windows não informou a identidade do disco da origem $o." }
        if ($io.DiscoId -eq $info.DiscoId) {
            throw "A origem $o está no mesmo disco físico que o destino ${letra}:. O backup precisa ficar em outro disco."
        }
    }
    if (-not $PermitirRaiz) {
        $cheio = Resolve-CaminhoLocal $Destino
        if ($cheio -eq [IO.Path]::GetPathRoot($cheio)) { throw 'Escolha uma pasta dentro do HD externo, não a raiz do disco.' }
        foreach ($o in $Origens) {
            if ((Test-Dentro $cheio $o) -or (Test-Dentro $o $cheio)) { throw "Origem e destino não podem estar um dentro do outro: $o" }
        }
        Assert-SemLinks $cheio
    }
    return $info
}

function Test-PastaDeBackup {
    # Pasta criada por esta versão (_CONTROLE) ou pela versão anterior (_RELATORIOS).
    param([Parameter(Mandatory)][string]$Caminho)
    return (Test-Path -LiteralPath (Join-Path $Caminho '_CONTROLE') -PathType Container) -or
           (Test-Path -LiteralPath (Join-Path $Caminho '_RELATORIOS') -PathType Container)
}

function Get-UnidadesProntas {
    return @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.Name -match '^[A-Za-z]:' } |
        ForEach-Object { $_.Name.Substring(0, 1).ToUpperInvariant() })
}

function Resolve-Destino {
    # A letra de um HD USB pode mudar (E: hoje, F: amanhã). Procura a mesma pasta em
    # todas as unidades; se houver exatamente uma, usa. Se não houver nenhuma, usa o
    # caminho configurado (primeiro backup), desde que a unidade esteja conectada.
    param([string]$Configurado, [string[]]$Origens = @(), [switch]$Automatico)
    if (-not $Configurado) { throw 'Nenhum HD de destino configurado. Abra Iniciar.cmd e escolha Configurar.' }
    $cheio = Resolve-CaminhoLocal $Configurado
    $resto = $cheio.Substring(2)
    $achados = New-Object 'Collections.Generic.List[string]'
    $recusas = New-Object 'Collections.Generic.List[string]'
    foreach ($letra in Get-UnidadesProntas) {
        $candidato = "${letra}:$resto"
        if (-not (Test-PastaDeBackup $candidato)) { continue }
        try { $null = Assert-DestinoSeguro $candidato $Origens; $achados.Add($candidato) }
        catch { $recusas.Add("${letra}: $($_.Exception.Message)") }
    }
    if ($achados.Count -eq 1) { return $achados[0] }
    if ($achados.Count -gt 1) {
        if ($Automatico) { throw "Há mais de um HD de backup conectado ($($achados -join ', ')). Deixe só um conectado." }
        Write-Host 'Encontrei mais de um HD com este backup:'
        for ($i = 0; $i -lt $achados.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $achados[$i]) }
        $resposta = Read-Host 'Digite o número do HD que deseja usar'
        $n = 0
        if ([int]::TryParse($resposta, [ref]$n) -and $n -ge 1 -and $n -le $achados.Count) { return $achados[$n - 1] }
        throw 'Nenhum HD escolhido. Nada foi feito.'
    }
    if ($recusas.Count) { throw ("O backup foi encontrado, mas o disco foi recusado:`n  " + ($recusas -join "`n  ")) }
    if (Test-Path -LiteralPath $cheio.Substring(0, 3)) {
        $null = Assert-DestinoSeguro $cheio $Origens
        return $cheio
    }
    throw "HD de backup não encontrado ($cheio). Conecte o HD externo e tente de novo."
}

function Get-DiscosCandidatos {
    # Lista as unidades e diz quais podem receber o backup (e por que as outras não).
    param([string[]]$Origens = @())
    foreach ($letra in Get-UnidadesProntas) {
        $drive = New-Object IO.DriveInfo "${letra}:\"
        $linha = [ordered]@{ Letra = $letra; Rotulo = $drive.VolumeLabel; TotalGB = [math]::Round($drive.TotalSize / 1GB, 1)
            LivreGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1); Ok = $false; Motivo = '' }
        try { $null = Assert-DestinoSeguro "${letra}:\" $Origens -PermitirRaiz; $linha.Ok = $true }
        catch { $linha.Motivo = $_.Exception.Message }
        [pscustomobject]$linha
    }
}

function Select-DestinoInterativo {
    param([string[]]$Origens = @())
    Clear-CacheDisco
    $discos = @(Get-DiscosCandidatos $Origens)
    $ok = @($discos | Where-Object Ok)
    foreach ($d in @($discos | Where-Object { -not $_.Ok })) { Write-Host "  [não serve] $($d.Letra): $($d.Rotulo) - $($d.Motivo)" -ForegroundColor DarkGray }
    if (-not $ok.Count) {
        throw 'Nenhum HD externo USB/NTFS disponível. Conecte o HD e tente de novo (veja docs\GUIA-RAPIDO.md).'
    }
    Write-Host ''
    Write-Host 'HDs que podem receber o backup:'
    for ($i = 0; $i -lt $ok.Count; $i++) {
        Write-Host ("  {0}. {1}:  {2}  ({3} GB livres de {4} GB)" -f ($i + 1), $ok[$i].Letra, $ok[$i].Rotulo, $ok[$i].LivreGB, $ok[$i].TotalGB)
    }
    $resposta = Read-Host 'Digite o número do HD'
    $n = 0
    if (-not ([int]::TryParse($resposta, [ref]$n) -and $n -ge 1 -and $n -le $ok.Count)) { throw 'Nenhum HD escolhido.' }
    $usuario = ($env:USERNAME -replace '[<>:"/\\|?*]', '_')
    return "$($ok[$n - 1].Letra):\BACKUP_WINDOWS\$($env:COMPUTERNAME)-$usuario"
}
