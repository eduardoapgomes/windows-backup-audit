# =============================================================================
# Procurar arquivos fora do backup (menu 8, -Acao Cobertura).
#
# Lista arquivos pessoais (documentos, planilhas, fotos, código...) em pastas que
# não estão em [ORIGENS], agrupados por pasta. Em AppData e nas pastas ocultas do
# perfil (.vscode, .conda...) procura só o que não pode ser perdido: carteiras de
# criptomoedas, cofres de senha, chaves SSH/GPG e arquivos de e-mail (.pst).
# Só lê nomes, tamanhos e datas. Não precisa do HD e não grava nada fora da pasta
# do programa.
# =============================================================================

$script:TiposPessoais = @{}
foreach ($par in @(
        @('Documento', '.doc .docx .odt .rtf .pdf .txt .md .tex .bib .epub .djvu'),
        @('Planilha', '.xls .xlsx .xlsm .ods .csv'),
        @('Apresentação', '.ppt .pptx .odp'),
        @('Imagem', '.jpg .jpeg .png .heic .gif .bmp .tif .tiff .webp .raw .cr2 .nef .arw .dng .psd .svg .ai .eps'),
        @('Vídeo', '.mp4 .mov .mkv .avi .wmv .m4v .mts'),
        @('Áudio', '.mp3 .wav .flac .m4a .aac .ogg .wma'),
        @('Código e dados', '.py .ipynb .m .mat .slx .mdl .r .rmd .jl .c .cpp .h .java .js .ts .cs .ps1 .sql .atp .dss .h5 .hdf5 .parquet .drawio'),
        @('Compactado', '.zip .7z .rar'))) {
    foreach ($e in $par[1].Split(' ')) { $script:TiposPessoais[$e] = $par[0] }
}
$script:TipoCritico = 'Carteira, senha, chave ou e-mail'
$script:ExtensoesCriticas = @('.kdbx', '.kdb', '.pst', '.ppk', '.wallet', '.keystore')
$script:NomesCriticos = @('wallet.dat', 'id_rsa', 'id_ed25519', 'id_ecdsa', 'secring.gpg', 'pubring.kbx')

# Pastas da raiz dos discos que são do Windows ou de programas.
$script:PastasDoSistema = @('Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users',
    'Documents and Settings', '$Recycle.Bin', '$WinREAgent', '$SysReset', '$Windows.~BT', '$Windows.~WS',
    '$GetCurrent', 'System Volume Information', 'Recovery', 'PerfLogs', 'Config.Msi', 'MSOCache', 'OneDriveTemp',
    'Intel', 'AMD', 'NVIDIA', 'inetpub', 'ESD', 'Drivers')

function Get-TipoPessoal {
    # Categoria do arquivo pelo nome; $null se não for um tipo procurado.
    param([Parameter(Mandatory)][string]$Nome, [switch]$SoCriticos)
    $nome = [IO.Path]::GetFileName($Nome).ToLowerInvariant()
    $ext = [IO.Path]::GetExtension($nome)
    if ($script:NomesCriticos -contains $nome -or $script:ExtensoesCriticas -contains $ext) { return $script:TipoCritico }
    if ($SoCriticos -or -not $ext) { return $null }
    return $script:TiposPessoais[$ext]
}

function Get-RaizesCobertura {
    # Onde procurar. Nivel = quantas pastas abaixo da raiz formam o grupo do relatório.
    param([string]$Perfil = $env:USERPROFILE, [string[]]$AppData = @($env:APPDATA, $env:LOCALAPPDATA), [switch]$SemDiscos)
    $comuns = New-Object 'Collections.Generic.List[object]'
    $criticas = New-Object 'Collections.Generic.List[object]'
    if ($Perfil -and (Test-Path -LiteralPath $Perfil -PathType Container)) {
        $comuns.Add([pscustomobject]@{ Caminho = $Perfil; Nivel = 1 })
        # Pastas ocultas do perfil (.vscode, .conda, .ssh...): só o que é crítico.
        foreach ($p in @(Get-ChildItem -LiteralPath $Perfil -Directory -Force -Filter '.*' -ErrorAction SilentlyContinue)) {
            if ($p.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $criticas.Add([pscustomobject]@{ Caminho = $p.FullName; Nivel = 0 })
        }
        $publica = Join-Path (Split-Path -Parent $Perfil) 'Public'
        if (Test-Path -LiteralPath $publica -PathType Container) { $comuns.Add([pscustomobject]@{ Caminho = $publica; Nivel = 1 }) }
    }
    foreach ($a in $AppData) {
        if ($a -and (Test-Path -LiteralPath $a -PathType Container)) { $criticas.Add([pscustomobject]@{ Caminho = $a; Nivel = 1 }) }
    }
    if ($script:EhWindows -and -not $SemDiscos) {
        $sistema = ([string]$env:SystemDrive).ToUpperInvariant()
        foreach ($u in [IO.DriveInfo]::GetDrives()) {
            if ($u.DriveType -ne [IO.DriveType]::Fixed -or -not $u.IsReady) { continue }
            $letra = $u.Name.Substring(0, 2).ToUpperInvariant()
            # HDs USB (inclusive o do backup) ficam de fora. Sem identificar o disco, só o do Windows entra.
            try { $usb = (Get-InfoDisco $letra).Barramento -eq 'USB' } catch { $usb = ($letra -ne $sistema) }
            if ($usb) { continue }
            foreach ($p in @(Get-ChildItem -LiteralPath $u.RootDirectory.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
                if ($script:PastasDoSistema -contains $p.Name -or ($p.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                $comuns.Add([pscustomobject]@{ Caminho = $p.FullName; Nivel = 0 })
            }
        }
    }
    return [pscustomobject]@{ Comuns = $comuns.ToArray(); Criticas = $criticas.ToArray() }
}

function ConvertTo-RaizCobertura {
    # Aceita caminhos (texto) ou objetos { Caminho; Nivel }.
    param([object[]]$Itens, [int]$Nivel)
    foreach ($i in @($Itens)) {
        if ($null -eq $i) { continue }
        if ($i -is [string]) { [pscustomobject]@{ Caminho = $i; Nivel = $Nivel } } else { $i }
    }
}

function Find-ArquivosForaDoBackup {
    <#
    .SYNOPSIS
    Procura arquivos pessoais fora das pastas de [ORIGENS] e devolve um resumo por pasta.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [object[]]$Raizes = $null,           # padrão: perfil, pasta Pública e raiz dos discos internos
        [object[]]$RaizesCriticas = $null,   # padrão: AppData e pastas ocultas do perfil
        [string]$PastaRelatorio = ''
    )
    $inicio = Get-Date
    if ($null -eq $Raizes -or $null -eq $RaizesCriticas) {
        $padrao = Get-RaizesCobertura
        if ($null -eq $Raizes) { $Raizes = $padrao.Comuns }
        if ($null -eq $RaizesCriticas) { $RaizesCriticas = $padrao.Criticas }
    }
    $origens = @($Config.Origens | ForEach-Object { $_.Caminho.TrimEnd('\', '/') })
    $excluir = @($Config.ExcluirPastas | Where-Object { $_ })
    # As origens entram como exclusão por caminho: a listagem nem desce nelas.
    $filtroComum = [WindowsBackupAudit.Filtro]::new([string[]]@($excluir + '.*' + $origens), [string[]]$Config.ExcluirArquivos)
    $filtroCritico = [WindowsBackupAudit.Filtro]::new([string[]]@(@($excluir | Where-Object { $_ -ne 'AppData' }) + $origens), [string[]]@())
    $sep = [IO.Path]::DirectorySeparatorChar
    $achados = New-Object 'Collections.Generic.List[object]'
    $passadas = @(
        @{ Raizes = @(ConvertTo-RaizCobertura $Raizes 1); Filtro = $filtroComum; SoCriticos = $false },
        @{ Raizes = @(ConvertTo-RaizCobertura $RaizesCriticas 1); Filtro = $filtroCritico; SoCriticos = $true })
    foreach ($passada in $passadas) {
        foreach ($r in $passada.Raizes) {
            $raiz = ([string]$r.Caminho).TrimEnd('\', '/')
            if (-not (Test-Path -LiteralPath $raiz -PathType Container)) { continue }
            $coberta = $false
            foreach ($o in $origens) {
                if ($raiz -eq $o -or $raiz.StartsWith($o + $sep, [StringComparison]::OrdinalIgnoreCase)) { $coberta = $true; break }
            }
            if ($coberta) { continue }
            Write-Etapa "Procurando em $raiz"
            $v = [WindowsBackupAudit.Nativo]::Varrer($raiz, $passada.Filtro, $true)
            foreach ($a in $v.Arquivos.Values) {
                $tipo = Get-TipoPessoal $a.Relativo -SoCriticos:$passada.SoCriticos
                if (-not $tipo) { continue }
                $partes = $a.Relativo.Split($sep)
                $n = [math]::Min([int]$r.Nivel, $partes.Count - 1)
                $grupo = if ($n -gt 0) { [IO.Path]::Combine($raiz, ($partes[0..($n - 1)] -join $sep)) } else { $raiz }
                if ($n -lt [int]$r.Nivel) { $grupo += ' (arquivos soltos)' }
                $achados.Add([pscustomobject]@{
                        Grupo = $grupo; Caminho = [IO.Path]::Combine($raiz, $a.Relativo); Tipo = $tipo
                        Bytes = $a.Bytes; Ticks = $a.Modificado; Critico = ($tipo -eq $script:TipoCritico)
                    })
            }
        }
    }
    # Resumo por pasta: críticos primeiro, depois o que foi mexido mais recentemente.
    $porGrupo = @{}
    foreach ($x in $achados) {
        $g = $porGrupo[$x.Grupo]
        if ($null -eq $g) {
            $g = [pscustomobject]@{ Pasta = $x.Grupo; Arquivos = 0; Bytes = [long]0; Ticks = [long]0; Contagem = @{}; Critico = $false }
            $porGrupo[$x.Grupo] = $g
        }
        $g.Arquivos++
        $g.Bytes += $x.Bytes
        if ($x.Ticks -gt $g.Ticks) { $g.Ticks = $x.Ticks }
        $g.Contagem[$x.Tipo] = 1 + [int]$g.Contagem[$x.Tipo]
        if ($x.Critico) { $g.Critico = $true }
    }
    $grupos = @($porGrupo.Values | ForEach-Object {
            $tipos = @($_.Contagem.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 | ForEach-Object { $_.Key })
            [pscustomobject]@{
                Pasta = $_.Pasta; Arquivos = $_.Arquivos; Bytes = $_.Bytes; Critico = $_.Critico
                MaisRecente = [DateTime]::FromFileTimeUtc($_.Ticks).ToLocalTime(); Tipos = ($tipos -join ', ')
            }
        } | Sort-Object @{ Expression = 'Critico'; Descending = $true }, @{ Expression = 'MaisRecente'; Descending = $true })

    $relatorio = ''
    if ($PastaRelatorio -and $achados.Count) {
        New-Item -ItemType Directory -Force -Path $PastaRelatorio | Out-Null
        $relatorio = Join-Path $PastaRelatorio ('fora-do-backup-{0:yyyy-MM-dd_HH-mm-ss}.tsv' -f $inicio)
        $w = New-Object IO.StreamWriter($relatorio, $false, (New-Object Text.UTF8Encoding($true)))
        try {
            $w.WriteLine("pasta`tcaminho`ttipo`tbytes`tmodificado")
            foreach ($x in ($achados | Sort-Object Grupo, Caminho)) {
                $data = [DateTime]::FromFileTimeUtc($x.Ticks).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
                $w.WriteLine(("{0}`t{1}`t{2}`t{3}`t{4}" -f $x.Grupo, $x.Caminho, $x.Tipo, $x.Bytes, $data))
            }
        } finally { $w.Dispose() }
    }
    return [pscustomobject]@{
        Grupos = $grupos; Arquivos = $achados.Count; Criticos = @($achados | Where-Object Critico).Count
        Relatorio = $relatorio; Duracao = (Get-Date) - $inicio
    }
}

function Show-Cobertura {
    param([Parameter(Mandatory)]$Resultado, [int]$Limite = 40)
    Write-Host ''
    if (-not $Resultado.Grupos.Count) {
        Write-Host ('=' * 72) -ForegroundColor Green
        Write-Host ' Nenhum arquivo pessoal encontrado fora das pastas do backup.' -ForegroundColor Green
        Write-Host ('=' * 72) -ForegroundColor Green
        return
    }
    Write-Host ('=' * 72) -ForegroundColor Yellow
    Write-Host (' ARQUIVOS FORA DO BACKUP: {0:N0} em {1:N0} pasta(s). Decida pasta por pasta:' -f $Resultado.Arquivos, $Resultado.Grupos.Count) -ForegroundColor Yellow
    Write-Host ' o que for seu vai para [ORIGENS]; programas e caches podem ficar de fora.' -ForegroundColor Yellow
    Write-Host ('=' * 72) -ForegroundColor Yellow
    Write-Host (' {0,-52} {1,8} {2,10}  {3,-10}  {4}' -f 'Pasta', 'Arquivos', 'Tamanho', 'Alterado', 'Tipos')
    foreach ($g in @($Resultado.Grupos | Select-Object -First $Limite)) {
        $pasta = if ($g.Pasta.Length -gt 52) { '...' + $g.Pasta.Substring($g.Pasta.Length - 49) } else { $g.Pasta }
        $cor = if ($g.Critico) { 'Red' } else { 'Gray' }
        Write-Host (' {0,-52} {1,8:N0} {2,10}  {3:dd/MM/yyyy}  {4}' -f $pasta, $g.Arquivos, (Format-Tamanho $g.Bytes), $g.MaisRecente, $g.Tipos) -ForegroundColor $cor
    }
    if ($Resultado.Grupos.Count -gt $Limite) { Write-Host (' ... e mais {0} pasta(s).' -f ($Resultado.Grupos.Count - $Limite)) }
    if ($Resultado.Criticos) {
        Write-Host ''
        Write-Host (' Em vermelho: {0} arquivo(s) de carteira, senha, chave ou e-mail. Não deixe de fora sem ter certeza.' -f $Resultado.Criticos) -ForegroundColor Red
    }
    if ($Resultado.Relatorio) { Write-Host " Lista completa (abre no Excel): $($Resultado.Relatorio)" }
    Write-Host ('=' * 72) -ForegroundColor Yellow
}
