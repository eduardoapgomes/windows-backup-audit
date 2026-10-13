# =============================================================================
# Configuração: um arquivo de texto simples (configuracao.txt), editável no
# Bloco de Notas, sem aspas nem barras duplicadas.
#
#   [DESTINO]            pasta no HD externo
#   [ORIGENS]            uma pasta por linha; "C:\pasta > Nome" escolhe o nome no backup
#   [EXCLUIR_PASTAS]     nomes (em qualquer nível) ou caminhos completos; aceita * e ?
#   [EXCLUIR_ARQUIVOS]   nomes ou padrões de arquivo; aceita * e ?
# =============================================================================

$script:SecoesValidas = @('DESTINO', 'ORIGENS', 'EXCLUIR_PASTAS', 'EXCLUIR_ARQUIVOS')

# Pastas regeneráveis ou do sistema. NÃO inclui .git: o histórico local de um
# repositório (commits ainda não enviados, stashes) é dado do usuário.
$script:ExcluirPastasPadrao = @(
    'node_modules', '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', '.venv',
    'AppData', '$RECYCLE.BIN', 'System Volume Information')

# Arquivos temporários: bloqueio do Office (~$...), downloads incompletos, miniaturas.
$script:ExcluirArquivosPadrao = @('~$*', '*.tmp', 'Thumbs.db', '*.crdownload', '*.part', '*.partial')

# Nomes de pastas de dados procurados na criação da configuração (perfil e raiz de discos internos).
$script:NomesPastasDeDados = @('Projetos', 'Projects', 'Code', 'Codigo', 'Código', 'Repos', 'Repositories', 'Git',
    'Trabalho', 'Work', 'Estudos', 'Dados', 'Data', 'Documentos', 'Documents', 'Fotos', 'Imagens', 'Pictures',
    'Videos', 'Vídeos', 'Arquivos', 'Notebooks', 'Jupyter', 'Saved Games')

$script:EhWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

function Read-TextoConfig {
    # O Bloco de Notas pode salvar em UTF-8 (com ou sem BOM), UTF-16 ou ANSI.
    param([Parameter(Mandatory)][string]$Caminho)
    $bytes = [IO.File]::ReadAllBytes($Caminho)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    try { return (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes) }
    catch { return [Text.Encoding]::GetEncoding(1252).GetString($bytes) }
}

function Resolve-CaminhoLocal {
    # Aceita somente caminho absoluto com letra de unidade (C:\...). Rejeita rede (\\servidor),
    # relativo e fluxo alternativo (arquivo:fluxo). Devolve o caminho normalizado, sem barra final.
    param([Parameter(Mandatory)][string]$Caminho)
    $c = $Caminho.Trim().Trim('"').Trim()
    if ($script:EhWindows) {
        if ($c -notmatch '^[A-Za-z]:\\' -or $c.Substring(2).Contains(':')) {
            throw "Use um caminho completo com letra de unidade, por exemplo C:\Users\Nome\Documents (recebido: '$Caminho')."
        }
    } elseif (-not [IO.Path]::IsPathRooted($c)) {
        throw "Use um caminho completo (recebido: '$Caminho')."
    }
    $cheio = [IO.Path]::GetFullPath($c)
    $raiz = [IO.Path]::GetPathRoot($cheio)
    if ($cheio.Length -gt $raiz.Length) { $cheio = $cheio.TrimEnd('\', '/') }
    return $cheio
}

function Test-Dentro {
    # Verdadeiro se $Caminho é $Pasta ou está dentro dela (respeita limites de pasta).
    param([string]$Caminho, [string]$Pasta)
    $c = $Caminho.TrimEnd('\', '/')
    $p = $Pasta.TrimEnd('\', '/')
    if ($c.Equals($p, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $c.StartsWith($p + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Get-NomePadrao {
    # Nome da pasta no backup = nome da pasta de origem, limpo de caracteres reservados.
    param([Parameter(Mandatory)][string]$Caminho)
    $nome = [IO.Path]::GetFileName($Caminho.TrimEnd('\', '/'))
    $nome = $nome -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    $nome = $nome.TrimStart('_', '.', ' ').TrimEnd('.', ' ')
    if ($nome.Length -gt 64) { $nome = $nome.Substring(0, 64).TrimEnd('.', ' ') }
    if (-not $nome) { $nome = 'Pasta' }
    return $nome
}

function Test-NomeValido {
    param([string]$Nome)
    if (-not $Nome -or $Nome.Length -gt 64) { return $false }
    if ($Nome -match '[<>:"/\\|?*\x00-\x1F]') { return $false }
    if ($Nome -match '^[_.\s]' -or $Nome -match '[.\s]$') { return $false }   # "_" e "." são reservados
    if ($Nome -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') { return $false }
    return $true
}

function ConvertFrom-TextoConfig {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Texto, [string]$Arquivo = '')
    $secoes = @{}
    foreach ($s in $script:SecoesValidas) { $secoes[$s] = New-Object 'Collections.Generic.List[object]' }
    $secao = $null
    $numero = 0
    foreach ($bruta in ($Texto -split "\r?\n")) {
        $numero++
        $linha = $bruta.Trim()
        if ($linha.Length -eq 0 -or $linha.StartsWith('#')) { continue }
        if ($linha -match '^\[(.+)\]$') {
            $nome = ($Matches[1].Trim().ToUpperInvariant() -replace '\s+', '_')
            if ($script:SecoesValidas -notcontains $nome) {
                throw "Linha ${numero}: seção desconhecida [$($Matches[1])]. Use [DESTINO], [ORIGENS], [EXCLUIR_PASTAS] ou [EXCLUIR_ARQUIVOS]."
            }
            $secao = $nome
            continue
        }
        if (-not $secao) { throw "Linha ${numero}: '$linha' está fora de uma seção. Coloque-a abaixo de [ORIGENS], por exemplo." }
        $secoes[$secao].Add([pscustomobject]@{ Linha = $numero; Texto = $linha })
    }
    if ($secoes['DESTINO'].Count -gt 1) { throw 'Coloque apenas uma pasta em [DESTINO].' }
    $destino = ''
    if ($secoes['DESTINO'].Count -eq 1) { $destino = $secoes['DESTINO'][0].Texto.Trim('"').Trim() }

    $origens = New-Object 'Collections.Generic.List[object]'
    foreach ($item in $secoes['ORIGENS']) {
        $partes = $item.Texto -split '>', 2
        $nome = ''
        if ($partes.Count -eq 2) { $nome = $partes[1].Trim() }
        $origens.Add([pscustomobject]@{ Linha = $item.Linha; Caminho = $partes[0].Trim().Trim('"').Trim(); Nome = $nome })
    }
    [pscustomobject]@{
        Arquivo         = $Arquivo
        Destino         = $destino
        Origens         = $origens.ToArray()
        ExcluirPastas   = [string[]]@($secoes['EXCLUIR_PASTAS'] | ForEach-Object { $_.Texto.Trim('"') })
        ExcluirArquivos = [string[]]@($secoes['EXCLUIR_ARQUIVOS'] | ForEach-Object { $_.Texto.Trim('"') })
    }
}

function Assert-Configuracao {
    # Confere tudo de uma vez e mostra todos os problemas juntos.
    param([Parameter(Mandatory)]$Config)
    $erros = New-Object 'Collections.Generic.List[string]'
    if ($Config.Origens.Count -eq 0) { $erros.Add('Nenhuma pasta em [ORIGENS]. Adicione pelo menos uma.') }
    $windows = if ($script:EhWindows) { [Environment]::GetFolderPath('Windows') } else { '' }
    $nomes = @{}
    foreach ($o in $Config.Origens) {
        $onde = "Linha $($o.Linha) ($($o.Caminho))"
        try { $o.Caminho = Resolve-CaminhoLocal $o.Caminho }
        catch { $erros.Add("${onde}: $($_.Exception.Message)"); continue }
        if ($o.Caminho -eq [IO.Path]::GetPathRoot($o.Caminho)) {
            $erros.Add("${onde}: não use um disco inteiro. Escolha as pastas com seus dados."); continue
        }
        if ($windows -and (Test-Dentro $o.Caminho $windows)) { $erros.Add("${onde}: a pasta do Windows não é copiada."); continue }
        if (-not (Test-Path -LiteralPath $o.Caminho -PathType Container)) { $erros.Add("${onde}: a pasta não existe."); continue }
        if (-not $o.Nome) { $o.Nome = Get-NomePadrao $o.Caminho }
        if (-not (Test-NomeValido $o.Nome)) {
            $erros.Add("${onde}: nome '$($o.Nome)' inválido para o backup. Use letras, números, espaço, - ou _, sem começar com _ ou ponto."); continue
        }
        if ($nomes.ContainsKey($o.Nome)) {
            $erros.Add("${onde}: o nome '$($o.Nome)' já é usado pela linha $($nomes[$o.Nome].Linha). Escolha outro assim: $($o.Caminho) > OutroNome"); continue
        }
        $nomes[$o.Nome] = $o
    }
    $validas = @($nomes.Values)
    for ($i = 0; $i -lt $validas.Count; $i++) {
        for ($j = 0; $j -lt $validas.Count; $j++) {
            if ($i -ne $j -and (Test-Dentro $validas[$i].Caminho $validas[$j].Caminho)) {
                $erros.Add("Linha $($validas[$i].Linha): $($validas[$i].Caminho) já está dentro de $($validas[$j].Caminho) (linha $($validas[$j].Linha)). Remova uma das duas.")
            }
        }
    }
    if ($erros.Count) {
        throw ("A configuração tem problemas:`n  - " + ($erros -join "`n  - ") + "`nCorrija em: $($Config.Arquivo)")
    }
}

function Read-Configuracao {
    param([Parameter(Mandatory)][string]$Caminho)
    if (-not (Test-Path -LiteralPath $Caminho -PathType Leaf)) {
        throw "Configuração não encontrada: $Caminho. Abra Iniciar.cmd e escolha 'Configurar'."
    }
    $config = ConvertFrom-TextoConfig -Texto (Read-TextoConfig $Caminho) -Arquivo $Caminho
    Assert-Configuracao $config
    return $config
}

function Get-IdVersaoAnterior {
    # Nome que a versão 1 dava às pastas na descoberta automática (AUTO_ + 16 hex do caminho).
    param([Parameter(Mandatory)][string]$Caminho)
    $normalizado = [IO.Path]::GetFullPath($Caminho).TrimEnd('\', '/')
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $h = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalizado.ToUpperInvariant())) }
    finally { $sha.Dispose() }
    return 'AUTO_' + [BitConverter]::ToString($h).Replace('-', '').Substring(0, 16)
}

function Get-OrigensSugeridas {
    # Pastas pessoais conhecidas + pastas de dados com nomes comuns. Nada é varrido: só testa se existem.
    param([string]$ConfigAntiga)
    $sugestoes = New-Object 'Collections.Generic.List[object]'

    if ($ConfigAntiga -and (Test-Path -LiteralPath $ConfigAntiga -PathType Leaf)) {
        # Versão anterior (backup.local.json): mantém os mesmos nomes de pasta no HD, sem recopiar.
        $antiga = Get-Content -LiteralPath $ConfigAntiga -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($s in @($antiga.Sources)) {
            $nome = if (Test-NomeValido ([string]$s.Id)) { [string]$s.Id } else { '' }
            $sugestoes.Add([pscustomobject]@{ Caminho = [string]$s.Path; Nome = $nome })
        }
        return [pscustomobject]@{ Origens = $sugestoes.ToArray(); Destino = [string]$antiga.Destination; Importada = $true }
    }

    $candidatos = New-Object 'Collections.Generic.List[string]'
    foreach ($id in 'MyDocuments', 'Desktop', 'MyPictures', 'MyVideos', 'MyMusic') {
        $p = [Environment]::GetFolderPath($id)
        if ($p) { $candidatos.Add($p) }
    }
    $perfil = [Environment]::GetFolderPath('UserProfile')
    try {
        $chave = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $downloads = (Get-ItemProperty -LiteralPath $chave -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($downloads) { $candidatos.Add([Environment]::ExpandEnvironmentVariables($downloads)) }
    } catch { if ($perfil) { $candidatos.Add((Join-Path $perfil 'Downloads')) } }
    foreach ($p in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) { if ($p) { $candidatos.Add($p) } }
    if ($perfil) { foreach ($n in $script:NomesPastasDeDados) { $candidatos.Add((Join-Path $perfil $n)) } }
    try {
        foreach ($drive in [IO.DriveInfo]::GetDrives()) {
            if (-not $drive.IsReady -or $drive.DriveType -ne 'Fixed') { continue }
            try { $info = Get-InfoDisco $drive.Name.Substring(0, 1) } catch { continue }
            if ($info.Barramento -eq 'USB') { continue }   # discos externos não são origem automática
            foreach ($n in $script:NomesPastasDeDados) { $candidatos.Add([IO.Path]::Combine($drive.Name, $n)) }
        }
    } catch { Write-Verbose $_.Exception.Message }

    $escolhidas = New-Object 'Collections.Generic.List[string]'
    $vistos = @{}
    foreach ($c in ($candidatos | Where-Object { $_ } | Sort-Object { $_.Length }, { $_ })) {
        try { $cheio = Resolve-CaminhoLocal $c } catch { continue }
        if ($vistos.ContainsKey($cheio)) { continue }
        $vistos[$cheio] = $true
        if ($cheio -eq [IO.Path]::GetPathRoot($cheio) -or ($perfil -and $cheio -ieq $perfil.TrimEnd('\'))) { continue }
        if (-not (Test-Path -LiteralPath $cheio -PathType Container)) { continue }
        if (@($escolhidas | Where-Object { Test-Dentro $cheio $_ }).Count) { continue }
        $escolhidas.Add($cheio)
    }
    $usados = @{}
    foreach ($c in $escolhidas) {
        $nome = Get-NomePadrao $c
        if ($usados.ContainsKey($nome)) { $nome = (Get-NomePadrao ($c.Substring(0, 1) + '_' + $nome)) }
        $base = $nome; $n = 2
        while ($usados.ContainsKey($nome)) { $nome = "$base-$n"; $n++ }
        $usados[$nome] = $true
        $sugestoes.Add([pscustomobject]@{ Caminho = $c; Nome = $nome })
    }
    return [pscustomobject]@{ Origens = $sugestoes.ToArray(); Destino = ''; Importada = $false }
}

function New-TextoConfig {
    param([string]$Destino, [object[]]$Origens, [string[]]$ExcluirPastas = $script:ExcluirPastasPadrao,
        [string[]]$ExcluirArquivos = $script:ExcluirArquivosPadrao)
    $linhas = New-Object 'Collections.Generic.List[string]'
    $linhas.Add('# =====================================================================')
    $linhas.Add('#  WINDOWS BACKUP AUDIT - configuração')
    $linhas.Add('#  Linhas que começam com # são comentários. Salve e feche ao terminar.')
    $linhas.Add('#  Guia: docs\GUIA-RAPIDO.md')
    $linhas.Add('# =====================================================================')
    $linhas.Add('')
    $linhas.Add('[DESTINO]')
    $linhas.Add('# Pasta no HD externo (USB, NTFS). Se a letra do HD mudar, o programa')
    $linhas.Add('# procura esta mesma pasta nos outros HDs USB conectados.')
    if ($Destino) { $linhas.Add($Destino) } else { $linhas.Add('# (escolha o HD pelo menu: Configurar)') }
    $linhas.Add('')
    $linhas.Add('[ORIGENS]')
    $linhas.Add('# Uma pasta por linha. Cada uma vira uma pasta no backup com o mesmo nome.')
    $linhas.Add('# Para escolher outro nome:   D:\Fotos > Fotos-D')
    $linhas.Add('# Para deixar de copiar uma pasta, apague a linha ou coloque # no início.')
    foreach ($o in $Origens) {
        if ($o.Nome -and $o.Nome -ne (Get-NomePadrao $o.Caminho)) { $linhas.Add("$($o.Caminho) > $($o.Nome)") }
        else { $linhas.Add($o.Caminho) }
    }
    $linhas.Add('')
    $linhas.Add('[EXCLUIR_PASTAS]')
    $linhas.Add('# Nome de pasta (ignorada em qualquer nível) ou caminho completo. Aceita * e ?.')
    $linhas.Add('# Bibliotecas e caches que podem ser reinstalados. .git NÃO é excluído de propósito.')
    foreach ($p in $ExcluirPastas) { $linhas.Add($p) }
    $linhas.Add('')
    $linhas.Add('[EXCLUIR_ARQUIVOS]')
    $linhas.Add('# Nome ou padrão de arquivo. Aceita * e ?.')
    foreach ($p in $ExcluirArquivos) { $linhas.Add($p) }
    return ($linhas -join "`r`n") + "`r`n"
}

function Save-TextoConfig {
    # UTF-8 com BOM: o Bloco de Notas e o Windows PowerShell 5.1 leem os acentos corretamente.
    param([Parameter(Mandatory)][string]$Caminho, [Parameter(Mandatory)][string]$Texto)
    [IO.File]::WriteAllText($Caminho, $Texto, (New-Object Text.UTF8Encoding($true)))
}
