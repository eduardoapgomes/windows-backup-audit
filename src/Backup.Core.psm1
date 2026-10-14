#Requires -Version 5.1
# =============================================================================
# windows-backup-audit - núcleo
#
# Fluxo de um backup (detalhes em docs\COMO-FUNCIONA.md):
#   1. Confere o HD de destino (USB, NTFS, outro disco físico) e trava o backup.
#   2. Lista origem e destino (só metadados) e compara com o manifesto.
#   3. Pasta renomeada/movida: move a cópia no HD em vez de copiar de novo.
#   4. Arquivo alterado: a versão antiga vai para _VERSOES_ANTERIORES (nunca é apagada).
#   5. Robocopy copia SOMENTE arquivos ausentes no destino (/XC /XN /XO: nunca sobrescreve).
#   6. Cada arquivo copiado é conferido por SHA-256 (origem e cópia) e entra no manifesto.
#   7. Relatório em _CONTROLE\execucoes\<data>\RELATORIO.html.
# Nada é apagado: nem na origem, nem no backup.
# =============================================================================
Set-StrictMode -Version Latest

if (-not ('WindowsBackupAudit.Nativo' -as [type])) {
    $codigo = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Nativo.cs'), [Text.Encoding]::UTF8)
    Add-Type -TypeDefinition $codigo -Language CSharp -IgnoreWarnings
}
foreach ($parte in 'Config.ps1', 'Destino.ps1', 'Relatorio.ps1', 'Agendamento.ps1', 'Assistente.ps1') {
    . (Join-Path $PSScriptRoot $parte)
}

$script:Versao = '2.0.1'
$script:MinimoMovido = 64KB      # arquivos menores são simplesmente copiados de novo
$script:LimiteGrande = 8MB       # arquivos grandes são conferidos um por vez (evita disputa no HD)
$script:MargemEspaco = 1GB

# ------------------------------------------------------------------ utilidades
function Write-Etapa {
    param([string]$Texto, [ConsoleColor]$Cor = [ConsoleColor]::Gray)
    Write-Host ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Texto) -ForegroundColor $Cor
}

function Format-Tamanho {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return '{0:N0} bytes' -f $Bytes
}

function Format-Argumento {
    # Aspas para argumentos com espaço; barras antes da aspa final são duplicadas.
    param([string]$Valor)
    if ($Valor -notmatch '[\s"]') { return $Valor }
    return '"' + ($Valor -replace '(\\+)$', '$1$1') + '"'
}

function Get-Carimbo {
    # Nome da pasta da execução (data e hora). Único mesmo com duas execuções no mesmo segundo.
    param([string]$Controle = '', [string]$Sufixo = '')
    $base = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $carimbo = $base + $Sufixo
    $n = 2
    while ($Controle -and (Test-Path -LiteralPath (Join-Path (Join-Path $Controle 'execucoes') $carimbo))) { $carimbo = "$base-$n$Sufixo"; $n++ }
    return $carimbo
}

function New-Detalhes {
    # Lista de arquivos tratados, separada por tabulação (abre no Excel com acentos).
    param([Parameter(Mandatory)][string]$Caminho)
    $w = New-Object IO.StreamWriter($Caminho, $false, (New-Object Text.UTF8Encoding($true)))
    $w.WriteLine("situacao`tpasta`tcaminho`tbytes`tsha256`tmensagem")
    return $w
}

function Add-Detalhe {
    param($Escritor, [string]$Situacao, [string]$Pasta, [string]$Caminho, [long]$Bytes = 0, [string]$Sha = '', [string]$Mensagem = '')
    if ($null -eq $Escritor) { return }
    if ($Caminho -match '^[=+\-@]') { $Caminho = "'" + $Caminho }   # evita fórmula no Excel
    $Escritor.WriteLine(($Situacao, $Pasta, $Caminho, $Bytes, $Sha, ($Mensagem -replace '[\t\r\n]+', ' ')) -join "`t")
}

function Open-Trava {
    param([Parameter(Mandatory)][string]$Destino)
    $caminho = Join-Path $Destino '.backup.lock'
    try { return [IO.File]::Open($caminho, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw 'Outro backup ou verificação está usando este HD agora. Feche a outra janela e tente de novo.' }
}

function Assert-MesmoDisco {
    # Antes de gravar: o HD ainda é o mesmo (não foi trocado nem desconectado)?
    param([string]$Destino, [string[]]$Origens, $Disco)
    Clear-CacheDisco
    $agora = Assert-DestinoSeguro $Destino $Origens
    if ($agora.DiscoId -ne $Disco.DiscoId) { throw 'O HD de destino foi trocado ou desconectado durante a execução.' }
}

function Get-LivreDestino {
    param([string]$Destino)
    return (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Destino))).AvailableFreeSpace
}

function Write-LeiaMeDestino {
    param([string]$Destino)
    $caminho = Join-Path $Destino 'LEIA-ME.txt'
    if (Test-Path -LiteralPath $caminho) { return }
    $texto = @"
BACKUP FEITO PELO WINDOWS BACKUP AUDIT
https://github.com/eduardoapgomes/windows-backup-audit

Cada pasta aqui é uma cópia comum de uma pasta do computador. Para restaurar,
basta copiar os arquivos de volta (Explorador de Arquivos) ou seguir
docs\RESTAURAR.md. Não é preciso instalar nada para ler este backup.

_CONTROLE               manifestos (SHA-256 de cada arquivo) e relatórios de cada execução
_VERSOES_ANTERIORES     versões antigas de arquivos que mudaram depois (por data da execução)

O programa nunca apaga arquivos deste HD. Para liberar espaço, você pode apagar
pastas antigas dentro de _VERSOES_ANTERIORES. Não edite os arquivos de _CONTROLE.
"@
    [IO.File]::WriteAllText($caminho, $texto.Replace("`n", "`r`n").Replace("`r`r", "`r"), (New-Object Text.UTF8Encoding($true)))
}

function Move-PastasVersaoAnterior {
    # A versão 1 (descoberta automática) chamava as pastas de AUTO_<código>. Renomeia para
    # o nome novo, no próprio HD: nada é recopiado e os arquivos são conferidos por SHA-256.
    param([object[]]$Origens, [string]$Destino)
    foreach ($o in $Origens) {
        $novo = Join-Path $Destino $o.Nome
        if (Test-Path -LiteralPath $novo) { continue }
        $antigo = Join-Path $Destino (Get-IdVersaoAnterior $o.Caminho)
        if (Test-Path -LiteralPath $antigo -PathType Container) {
            [IO.Directory]::Move($antigo, $novo)
            Write-Etapa "Pasta da versão anterior renomeada no HD: $(Split-Path -Leaf $antigo) -> $($o.Nome)"
        }
    }
}

# ------------------------------------------------------------------ Robocopy
function Get-ProgressoCopia {
    # Quanto já foi gravado no HD (pela queda do espaço livre). Tudo em [long]/[double]:
    # backups passam facilmente de 2 GB, o limite de um inteiro de 32 bits.
    param([long]$LivreAntes, [long]$LivreAgora, [long]$BytesPrevistos, [double]$Segundos)
    [long]$feito = $LivreAntes - $LivreAgora
    if ($feito -lt 0) { $feito = 0 }
    [double]$tempo = if ($Segundos -lt 1) { 1.0 } else { $Segundos }
    [int]$pct = -1
    if ($BytesPrevistos -gt 0) { $pct = [int][math]::Floor([math]::Min([double]99, 100.0 * $feito / $BytesPrevistos)) }
    [pscustomobject]@{
        Feito = $feito; Percentual = $pct
        Status = '{0} de {1} - {2}/s' -f (Format-Tamanho $feito), (Format-Tamanho $BytesPrevistos), (Format-Tamanho ($feito / $tempo))
    }
}

function Invoke-Robocopy {
    # Copia somente arquivos que NÃO existem no destino. /XC /XN /XO impedem sobrescrever.
    # /XA:O ignora arquivos só na nuvem (não baixa o OneDrive inteiro).
    # Não usa /MIR nem /PURGE: nada é apagado no destino.
    param(
        [Parameter(Mandatory)][string]$Origem,
        [Parameter(Mandatory)][string]$Destino,
        [string[]]$ExcluirPastas = @(),
        [string[]]$ExcluirArquivos = @(),
        [Parameter(Mandatory)][string]$Log,
        [int]$Threads = 8,
        [long]$BytesPrevistos = 0,
        [string]$Rotulo = '',
        # Só estes arquivos da pasta de origem, sem entrar nas subpastas (segunda passada).
        [string[]]$Arquivos = @(),
        # Acrescenta ao log em vez de recriá-lo.
        [switch]$AnexarLog
    )
    $argumentos = New-Object 'Collections.Generic.List[string]'
    $argumentos.Add($Origem); $argumentos.Add($Destino)
    foreach ($a in $Arquivos) { $argumentos.Add($a) }
    if (-not $Arquivos.Count) { $argumentos.Add('/E') }
    $opcaoLog = if ($AnexarLog) { "/UNILOG+:$Log" } else { "/UNILOG:$Log" }
    foreach ($a in @('/COPY:DAT', '/DCOPY:DAT', '/XC', '/XN', '/XO', '/XA:O',
            '/R:2', '/W:5', "/MT:$Threads", '/NP', '/NDL', '/FP', $opcaoLog)) { $argumentos.Add($a) }
    if ($ExcluirPastas.Count) { $argumentos.Add('/XD'); foreach ($x in $ExcluirPastas) { $argumentos.Add($x) } }
    if ($ExcluirArquivos.Count) { $argumentos.Add('/XF'); foreach ($x in $ExcluirArquivos) { $argumentos.Add($x) } }
    $linha = (@($argumentos | ForEach-Object { Format-Argumento $_ })) -join ' '
    if ($linha.Length -gt 32000) {
        throw 'Há links ou exclusões demais nesta pasta para o Robocopy. Exclua a pasta problemática em [EXCLUIR_PASTAS].'
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'robocopy.exe'
    $info.Arguments = $linha
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $livreAntes = Get-LivreDestino $Destino
    $inicio = Get-Date
    $atividade = "Copiando $Rotulo"
    $processo = [Diagnostics.Process]::Start($info)
    try {
        while (-not $processo.WaitForExit(1000)) {
            $p = Get-ProgressoCopia -LivreAntes $livreAntes -LivreAgora (Get-LivreDestino $Destino) `
                -BytesPrevistos $BytesPrevistos -Segundos ((Get-Date) - $inicio).TotalSeconds
            Write-Progress -Id 1 -Activity $atividade -Status $p.Status -PercentComplete $p.Percentual
        }
        $processo.WaitForExit()
        return $processo.ExitCode
    } finally {
        if (-not $processo.HasExited) { try { $processo.Kill() } catch { Write-Verbose 'Robocopy já encerrado.' } }
        Write-Progress -Id 1 -Activity $atividade -Completed
        $processo.Dispose()
    }
}

function Invoke-PassadaNomeCurto {
    # O Robocopy compara /XD e /XF também com o nome curto 8.3 dos arquivos: "script.tmpl"
    # tem o nome curto SCRIPT~1.TMP, que casa com *.tmp, e seria pulado sem aviso.
    # A listagem marca esses itens; aqui eles são copiados à parte:
    #   pastas: copiadas inteiras com as mesmas exclusões (a raiz da cópia não é testada);
    #   arquivos: pelo nome, sem nenhum padrão de exclusão.
    # Continua sem sobrescrever nada (/XC /XN /XO). Devolve o código do Robocopy (ou $null).
    param($Ctx, [object[]]$Pendentes, [string[]]$ExcluirPastas, [string[]]$ExcluirArquivos, [int]$Threads)
    $varredura = $Ctx.Plano.Origem
    if (-not $Pendentes.Count -or ($varredura.PastasNomeCurto.Count + $varredura.ArquivosNomeCurto.Count) -eq 0) { return $null }
    $sep = [IO.Path]::DirectorySeparatorChar
    $faltam = @{}
    foreach ($a in $Pendentes) { $faltam[$a.Relativo] = $true }
    # Pastas: da mais rasa para a mais funda (uma pasta dentro de outra também marcada
    # seria pulada pela cópia da de fora e é copiada depois). Só as que têm algo a copiar.
    $passadas = New-Object 'Collections.Generic.List[object]'
    $itens = 0
    foreach ($rel in @($varredura.PastasNomeCurto | Sort-Object { ($_.Split($sep)).Count })) {
        $prefixo = $rel + $sep
        foreach ($k in $faltam.Keys) {
            if ($k.StartsWith($prefixo, [StringComparison]::OrdinalIgnoreCase)) {
                $passadas.Add([pscustomobject]@{ Pasta = $rel; Arquivos = @() }); $itens++; break
            }
        }
    }
    # Arquivos: agrupados por pasta, em grupos que cabem na linha de comando.
    $porPasta = [ordered]@{}
    foreach ($rel in $varredura.ArquivosNomeCurto) {
        if (-not $faltam.ContainsKey($rel)) { continue }
        $pasta = [IO.Path]::GetDirectoryName($rel)
        if ($null -eq $pasta) { $pasta = '' }
        if (-not $porPasta.Contains($pasta)) { $porPasta[$pasta] = New-Object 'Collections.Generic.List[string]' }
        $porPasta[$pasta].Add([IO.Path]::GetFileName($rel))
    }
    foreach ($pasta in $porPasta.Keys) {
        $grupo = New-Object 'Collections.Generic.List[string]'
        $tamanho = 0
        foreach ($n in $porPasta[$pasta]) {
            if ($grupo.Count -and ($tamanho + $n.Length + 3) -gt 20000) {
                $passadas.Add([pscustomobject]@{ Pasta = $pasta; Arquivos = $grupo.ToArray() }); $grupo.Clear(); $tamanho = 0
            }
            $grupo.Add($n); $tamanho += $n.Length + 3; $itens++
        }
        if ($grupo.Count) { $passadas.Add([pscustomobject]@{ Pasta = $pasta; Arquivos = $grupo.ToArray() }) }
    }
    if (-not $passadas.Count) { return $null }
    Write-Etapa "Copiando à parte $itens item(ns) que o Robocopy pularia pelo nome curto 8.3"
    $codigo = 0
    foreach ($p in $passadas) {
        $de = if ($p.Pasta) { [IO.Path]::Combine($Ctx.Origem.Caminho, $p.Pasta) } else { $Ctx.Origem.Caminho }
        $para = if ($p.Pasta) { [IO.Path]::Combine($Ctx.PastaDestino, $p.Pasta) } else { $Ctx.PastaDestino }
        if ($p.Arquivos.Count) {
            $c = Invoke-Robocopy -Origem $de -Destino $para -Arquivos $p.Arquivos -Log $Ctx.Log -Threads $Threads `
                -Rotulo "$($Ctx.Origem.Nome)\$($p.Pasta)" -AnexarLog
        } else {
            $c = Invoke-Robocopy -Origem $de -Destino $para -ExcluirPastas $ExcluirPastas -ExcluirArquivos $ExcluirArquivos `
                -Log $Ctx.Log -Threads $Threads -Rotulo "$($Ctx.Origem.Nome)\$($p.Pasta)" -AnexarLog
        }
        $codigo = $codigo -bor $c
    }
    return $codigo
}

function Get-MotivoErro {
    # Códigos de erro do Windows mais comuns no log do Robocopy, em linguagem simples.
    param([int]$Codigo)
    switch ($Codigo) {
        2 { return 'o arquivo sumiu da origem durante a cópia.' }
        3 { return 'a pasta sumiu da origem durante a cópia.' }
        5 { return 'acesso negado (o Windows não deixou ler o arquivo).' }
        32 { return 'o arquivo estava em uso por outro programa. Feche o programa e execute de novo.' }
        33 { return 'parte do arquivo estava bloqueada por outro programa. Feche o programa e execute de novo.' }
        112 { return 'o HD ficou sem espaço.' }
        1392 { return 'arquivo corrompido ou ilegível no disco de origem.' }
    }
    return '{0} (erro {1} do Robocopy).' -f (New-Object ComponentModel.Win32Exception $Codigo).Message.TrimEnd('.'), $Codigo
}

function Get-FalhasRobocopy {
    # Motivo de cada arquivo que o Robocopy não conseguiu copiar (a última tentativa vale).
    # Linhas como "2026/10/13 20:41:56 ERRO 32 (0x00000020) Copiando Arquivo C:\pasta\arq.txt";
    # o texto entre o código e o caminho muda com o idioma do Windows.
    param([string]$Log, [Parameter(Mandatory)][string]$Origem)
    $falhas = @{}
    if (-not $Log -or -not (Test-Path -LiteralPath $Log -PathType Leaf)) { return $falhas }
    $separador = if ($Origem.Contains('\')) { '\' } else { [string][IO.Path]::DirectorySeparatorChar }
    $base = $Origem.TrimEnd('\', '/') + $separador
    $padrao = '^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} \S+ (\d+) \(0x[0-9A-Fa-f]{8}\) .*?([A-Za-z]:\\.+|\\\\.+|/.+)$'
    foreach ($linha in [IO.File]::ReadAllLines($Log)) {   # /UNILOG grava em UTF-16 com BOM
        $m = [regex]::Match($linha.TrimEnd(), $padrao)
        if (-not $m.Success) { continue }
        $caminho = $m.Groups[2].Value
        if (-not $caminho.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $falhas[$caminho.Substring($base.Length)] = Get-MotivoErro ([int]$m.Groups[1].Value)
    }
    return $falhas
}

# ------------------------------------------------------------------ verificação
function Save-Manifesto {
    param($Ctx)
    $pasta = Split-Path -Parent $Ctx.CaminhoManifesto
    if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    [WindowsBackupAudit.Nativo]::GravarManifesto($Ctx.CaminhoManifesto, $Ctx.Manifesto)
    $Ctx.UltimoSalvo = Get-Date
}

function New-Lotes {
    # Arquivos pequenos: 64 por lote, 4 em paralelo. Grandes: um por vez.
    param([object[]]$Itens, [scriptblock]$Tamanho)
    $lotes = New-Object 'Collections.Generic.List[object]'
    $atual = New-Object 'Collections.Generic.List[object]'
    foreach ($i in $Itens) {
        if ((& $Tamanho $i) -ge $script:LimiteGrande) {
            if ($atual.Count) { $lotes.Add([pscustomobject]@{ Itens = $atual.ToArray(); Paralelo = 4 }); $atual = New-Object 'Collections.Generic.List[object]' }
            $lotes.Add([pscustomobject]@{ Itens = @($i); Paralelo = 1 })
        } else {
            $atual.Add($i)
            if ($atual.Count -ge 64) { $lotes.Add([pscustomobject]@{ Itens = $atual.ToArray(); Paralelo = 4 }); $atual = New-Object 'Collections.Generic.List[object]' }
        }
    }
    if ($atual.Count) { $lotes.Add([pscustomobject]@{ Itens = $atual.ToArray(); Paralelo = 4 }) }
    return , $lotes.ToArray()
}

function Invoke-VerificacaoArquivos {
    # Confere cada arquivo (SHA-256 da origem e da cópia, lidos ao mesmo tempo) e registra
    # no manifesto. Salva o manifesto a cada minuto: se a energia cair, o que já foi
    # conferido não precisa ser lido de novo.
    param($Ctx, [object[]]$Arquivos, [string]$EstadoOk, $Detalhes, [switch]$DevolverDivergentes, [string]$Atividade = 'Conferindo')
    $divergentes = New-Object 'Collections.Generic.List[object]'
    if (-not $Arquivos -or $Arquivos.Count -eq 0) { return , $divergentes.ToArray() }
    $totalBytes = [long]0
    foreach ($a in $Arquivos) { $totalBytes += $a.Bytes }
    $feitos = 0
    $bytesFeitos = [long]0
    $inicio = Get-Date
    foreach ($lote in (New-Lotes $Arquivos { param($x) $x.Bytes })) {
        $n = $lote.Itens.Count
        $origens = New-Object 'string[]' $n
        $destinos = New-Object 'string[]' $n
        for ($i = 0; $i -lt $n; $i++) {
            $origens[$i] = [IO.Path]::Combine($Ctx.Origem.Caminho, $lote.Itens[$i].Relativo)
            $destinos[$i] = [IO.Path]::Combine($Ctx.PastaDestino, $lote.Itens[$i].Relativo)
        }
        $resultados = [WindowsBackupAudit.Nativo]::VerificarLote($origens, $destinos, $lote.Paralelo)
        $agora = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        for ($i = 0; $i -lt $n; $i++) {
            $a = $lote.Itens[$i]
            $r = $resultados[$i]
            $feitos++
            $bytesFeitos += $a.Bytes
            if ($r.Ok) {
                $reg = New-Object WindowsBackupAudit.Registro
                $reg.Relativo = $a.Relativo
                $reg.Bytes = $r.Bytes
                $reg.Modificado = $r.Modificado
                $reg.Sha256 = $r.HashOrigem
                $reg.Verificado = $agora
                $Ctx.Manifesto.Registros[$a.Relativo] = $reg
                $a.Estado = $EstadoOk
                $a.Sha256 = $r.HashOrigem
                $a.Bytes = $r.Bytes
                $a.Modificado = $r.Modificado
                Add-Detalhe $Detalhes $EstadoOk $Ctx.Origem.Nome $a.Relativo $a.Bytes $a.Sha256
            } elseif ($DevolverDivergentes -and $r.ConteudoDiferente) {
                $divergentes.Add($a)
            } else {
                $a.Estado = 'ERRO'
                $a.Mensagem = $r.Erro
                if ($Ctx.FalhasRobocopy -and $r.Erro -like 'Não foi copiado*' -and $Ctx.FalhasRobocopy.ContainsKey($a.Relativo)) {
                    $a.Mensagem = 'Não foi copiado: ' + $Ctx.FalhasRobocopy[$a.Relativo]
                }
                Add-Detalhe $Detalhes 'ERRO' $Ctx.Origem.Nome $a.Relativo $a.Bytes '' $a.Mensagem
            }
        }
        $segundos = [math]::Max([double]1, ((Get-Date) - $inicio).TotalSeconds)
        $pct = if ($totalBytes -gt 0) { [int](100.0 * $bytesFeitos / $totalBytes) } else { [int](100.0 * $feitos / $Arquivos.Count) }
        Write-Progress -Id 2 -Activity "$Atividade $($Ctx.Origem.Nome) (SHA-256)" -PercentComplete ([math]::Min(100, $pct)) `
            -Status ('{0} de {1} arquivos - {2} de {3} - {4}/s' -f $feitos, $Arquivos.Count, (Format-Tamanho $bytesFeitos), (Format-Tamanho $totalBytes), (Format-Tamanho ($bytesFeitos / $segundos)))
        if (((Get-Date) - $Ctx.UltimoSalvo).TotalSeconds -ge 60) { Save-Manifesto $Ctx }
    }
    Write-Progress -Id 2 -Activity "$Atividade $($Ctx.Origem.Nome) (SHA-256)" -Completed
    return , $divergentes.ToArray()
}

# ------------------------------------------------------------------ resumo
function Get-ContagemOrigem {
    param($Ctx)
    $p = $Ctx.Plano
    $c = [ordered]@{
        Nome = $p.Nome; Origem = $Ctx.Origem.Caminho
        Arquivos = $p.Origem.Arquivos.Count + $p.Origem.SomenteNuvem.Count; Bytes = $p.Origem.Bytes
        SemMudanca = $p.SemMudanca; Copiados = 0; Atualizados = 0; Movidos = 0; Conferidos = 0
        BytesCopiados = [long]0; Nuvem = $p.Nuvem.Count; Links = $p.Origem.Links.Count
        Erros = $p.Origem.Erros.Count; Pendentes = 0
        PlanoNovos = $p.Novos.Count; PlanoBytesNovos = [long]0; PlanoAlterados = $p.Alterados.Count
        PlanoBytesAlterados = [long]0; PlanoConferir = $p.Conferir.Count; PlanoMovidos = 0
    }
    foreach ($a in $p.Novos) { $c.PlanoBytesNovos += $a.Bytes }
    foreach ($a in $p.Alterados) { $c.PlanoBytesAlterados += $a.Bytes }
    foreach ($lista in @($p.Novos, $p.Alterados, $p.Conferir)) {
        foreach ($a in $lista) {
            switch ($a.Estado) {
                'COPIADO' { $c.Copiados++; $c.BytesCopiados += $a.Bytes }
                'ATUALIZADO' { $c.Atualizados++; $c.BytesCopiados += $a.Bytes }
                'MOVIDO' { $c.Movidos++ }
                'CONFERIDO' { $c.Conferidos++ }
                'ERRO' { $c.Erros++ }
                default { $c.Pendentes++ }
            }
        }
    }
    return [pscustomobject]$c
}

function Show-Plano {
    param([object[]]$Contextos, [object[]]$Movimentos)
    $movidosPor = @{}
    foreach ($m in $Movimentos) { $movidosPor[$m.PlanoNovo.Nome] = 1 + [int]$movidosPor[$m.PlanoNovo.Nome] }
    Write-Host ''
    Write-Host 'PLANO' -ForegroundColor Cyan
    foreach ($ctx in $Contextos) {
        $c = Get-ContagemOrigem $ctx
        $mov = [int]$movidosPor[$c.Nome]
        Write-Host ('  {0,-24} {1,9:N0} arquivos ({2})' -f $c.Nome, $c.Arquivos, (Format-Tamanho $c.Bytes))
        Write-Host ('      novos: {0:N0} ({1})  alterados: {2:N0} ({3})  movidos: {4:N0}  conferir: {5:N0}  sem mudança: {6:N0}' -f `
            ($c.PlanoNovos - $mov), (Format-Tamanho $c.PlanoBytesNovos), $c.PlanoAlterados, (Format-Tamanho $c.PlanoBytesAlterados), $mov, $c.PlanoConferir, $c.SemMudanca)
        if ($c.Nuvem -or $c.Links -or $c.Erros) {
            Write-Host ('      só na nuvem: {0:N0}  links ignorados: {1:N0}  pastas ilegíveis: {2:N0}' -f $c.Nuvem, $c.Links, $c.Erros) -ForegroundColor Yellow
        }
    }
    Write-Host ''
}

function Get-Situacao {
    param([int]$Erros, [int]$Avisos, [bool]$Concluido)
    if (-not $Concluido) { return [pscustomobject]@{ Situacao = 'INTERROMPIDO'; Codigo = 2 } }
    if ($Erros) { return [pscustomobject]@{ Situacao = 'ERROS'; Codigo = 2 } }
    if ($Avisos) { return [pscustomobject]@{ Situacao = 'AVISOS'; Codigo = 1 } }
    return [pscustomobject]@{ Situacao = 'OK'; Codigo = 0 }
}

# ------------------------------------------------------------------ backup
function Invoke-BackupWBA {
    <#
    .SYNOPSIS
    Faz (ou simula) o backup das origens da configuração para o destino.
    Devolve um resumo com CodigoSaida: 0 sem problemas, 1 avisos, 2 erros/interrompido.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Destino,
        [ValidateSet('Backup', 'Simular')][string]$Modo = 'Backup',
        [ValidateRange(1, 128)][int]$Threads = 8,
        [string]$PastaSimulacao = ''
    )
    $inicio = Get-Date
    $origens = @($Config.Origens)
    $caminhosOrigem = [string[]]@($origens | ForEach-Object { $_.Caminho })
    Clear-CacheDisco
    $disco = Assert-DestinoSeguro $Destino $caminhosOrigem
    $Destino = $Destino.TrimEnd('\', '/')
    $filtro = [WindowsBackupAudit.Filtro]::new([string[]]$Config.ExcluirPastas, [string[]]$Config.ExcluirArquivos)
    $controle = Join-Path $Destino '_CONTROLE'
    $carimbo = Get-Carimbo -Controle $controle
    $trava = $null; $detalhes = $null; $execucao = ''; $falha = ''; $concluido = $false
    $contextos = New-Object 'Collections.Generic.List[object]'
    $movimentos = @()
    $resumo = $null

    if ($Modo -eq 'Backup') {
        if (-not (Test-Path -LiteralPath $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }
        $trava = Open-Trava $Destino
    }
    try {
        if ($Modo -eq 'Backup') {
            Move-PastasVersaoAnterior $origens $Destino
            $execucao = Join-Path (Join-Path $controle 'execucoes') $carimbo
            New-Item -ItemType Directory -Path $execucao -Force | Out-Null
            $detalhes = New-Detalhes (Join-Path $execucao 'detalhes.tsv')
            Write-LeiaMeDestino $Destino
        } else {
            if (-not $PastaSimulacao) { $PastaSimulacao = [IO.Path]::GetTempPath() }
            New-Item -ItemType Directory -Path $PastaSimulacao -Force | Out-Null
            $execucao = $PastaSimulacao
            $detalhes = New-Detalhes (Join-Path $PastaSimulacao "simulacao-$carimbo.tsv")
        }

        # 1) Listar e comparar (só metadados: rápido, não lê o conteúdo dos arquivos).
        foreach ($o in $origens) {
            Write-Etapa "Listando $($o.Nome)  ($($o.Caminho))"
            $vOrigem = [WindowsBackupAudit.Nativo]::Varrer($o.Caminho, $filtro, $true)
            $pastaDestino = Join-Path $Destino $o.Nome
            if (Test-Path -LiteralPath $pastaDestino -PathType Container) {
                $vDestino = [WindowsBackupAudit.Nativo]::Varrer($pastaDestino, $filtro, $false)
            } else { $vDestino = New-Object WindowsBackupAudit.Varredura }
            $caminhoManifesto = Join-Path (Join-Path $controle 'manifestos') "$($o.Nome).tsv"
            $manifesto = [WindowsBackupAudit.Nativo]::LerManifesto($caminhoManifesto)
            if ($manifesto.Problema) {
                Write-Etapa "Manifesto de $($o.Nome) ignorado: $($manifesto.Problema) Os arquivos serão conferidos de novo por SHA-256." Yellow
            }
            $plano = [WindowsBackupAudit.Nativo]::Classificar($o.Nome, $vOrigem, $vDestino, $manifesto)
            foreach ($rel in $plano.Obsoletos) { [void]$manifesto.Registros.Remove($rel) }
            $contextos.Add([pscustomobject]@{
                Origem = $o; PastaDestino = $pastaDestino; Plano = $plano; Manifesto = $manifesto
                CaminhoManifesto = $caminhoManifesto; UltimoSalvo = Get-Date; CodigoRobocopy = $null; Log = ''
                FalhasRobocopy = $null
            })
            foreach ($e in $vOrigem.Erros) { Add-Detalhe $detalhes 'ERRO' $o.Nome $e[0] 0 '' $e[1] }
            foreach ($l in $vOrigem.Links) { Add-Detalhe $detalhes 'LINK_IGNORADO' $o.Nome $l 0 '' 'Atalho do sistema (junction/symlink): não é seguido.' }
            foreach ($a in $plano.Nuvem) {
                Add-Detalhe $detalhes 'SO_NA_NUVEM' $o.Nome $a.Relativo $a.Bytes '' "Disponível só online. Para incluir: botão direito > 'Sempre manter neste dispositivo'."
            }
        }
        $porNome = @{}
        foreach ($ctx in $contextos) { $porNome[$ctx.Plano.Nome] = $ctx }
        $planos = [WindowsBackupAudit.Plano[]]@($contextos | ForEach-Object { $_.Plano })
        $movimentos = @([WindowsBackupAudit.Nativo]::AssociarMovidos($planos, $script:MinimoMovido))
        Show-Plano $contextos $movimentos

        if ($Modo -eq 'Simular') {
            $movidos = @{}
            foreach ($m in $movimentos) {
                $movidos[$m.Novo] = $true
                Add-Detalhe $detalhes 'MOVER' $m.PlanoNovo.Nome $m.Novo.Relativo $m.Novo.Bytes '' "Mesmo conteúdo de $($m.PlanoAntigo.Nome)\$($m.Antigo.Relativo) (renomeado/movido)."
            }
            foreach ($ctx in $contextos) {
                foreach ($a in $ctx.Plano.Novos) { if (-not $movidos.ContainsKey($a)) { Add-Detalhe $detalhes 'COPIAR' $ctx.Plano.Nome $a.Relativo $a.Bytes } }
                foreach ($a in $ctx.Plano.Alterados) { Add-Detalhe $detalhes 'ATUALIZAR' $ctx.Plano.Nome $a.Relativo $a.Bytes '' 'A versão atual do backup será guardada em _VERSOES_ANTERIORES.' }
                foreach ($a in $ctx.Plano.Conferir) { Add-Detalhe $detalhes 'CONFERIR' $ctx.Plano.Nome $a.Relativo $a.Bytes '' 'Já está no backup; será conferido por SHA-256.' }
            }
        } else {
            Invoke-EtapasDeGravacao -Contextos $contextos -PorNome $porNome -Movimentos $movimentos -Config $Config `
                -Destino $Destino -CaminhosOrigem $caminhosOrigem -Disco $disco -Carimbo $carimbo -Execucao $execucao `
                -Detalhes $detalhes -Threads $Threads
        }
        $concluido = $true
    } catch {
        $falha = $_.Exception.Message
        Write-Etapa "Execução interrompida: $falha" Red
    } finally {
        foreach ($ctx in $contextos) {
            if ($Modo -eq 'Backup') {
                try { Save-Manifesto $ctx } catch { if (-not $falha) { $falha = "Não foi possível gravar o manifesto: $($_.Exception.Message)" } }
            }
        }
        $contagens = @($contextos | ForEach-Object { Get-ContagemOrigem $_ })
        $erros = 0; $nuvem = 0; $pendentes = 0
        foreach ($c in $contagens) { $erros += $c.Erros; $nuvem += $c.Nuvem; $pendentes += $c.Pendentes }
        if ($Modo -eq 'Backup' -and $concluido -and $pendentes) { $erros += $pendentes }
        $sit = Get-Situacao -Erros $erros -Avisos $nuvem -Concluido $concluido
        if ($null -ne $detalhes) { try { $detalhes.Dispose() } catch { Write-Verbose 'detalhes já fechado' } }
        $relatorio = ''
        if ($Modo -eq 'Backup' -and $execucao) {
            try {
                $relatorio = Write-RelatorioBackup -Execucao $execucao -Controle $controle -Destino $Destino -Disco $disco `
                    -Situacao $sit.Situacao -Falha $falha -Inicio $inicio -Contagens $contagens -Contextos $contextos
            } catch { Write-Etapa "Não foi possível gravar o relatório: $($_.Exception.Message)" Red }
        } elseif ($Modo -eq 'Simular' -and $null -ne $detalhes) {
            $relatorio = Join-Path $execucao "simulacao-$carimbo.tsv"
        }
        if ($null -ne $trava) { $trava.Dispose() }
        $resumo = [pscustomobject]@{
            Modo = $Modo; Situacao = $sit.Situacao; CodigoSaida = $sit.Codigo; Falha = $falha
            Destino = $Destino; Relatorio = $relatorio; Inicio = $inicio; Duracao = (Get-Date) - $inicio
            Erros = $erros; SoNaNuvem = $nuvem; Origens = $contagens; Movimentos = $movimentos.Count
        }
    }
    return $resumo
}

function Invoke-EtapasDeGravacao {
    # Etapas 2 a 5 do backup (as únicas que gravam no HD).
    param($Contextos, $PorNome, $Movimentos, $Config, [string]$Destino, [string[]]$CaminhosOrigem, $Disco,
        [string]$Carimbo, [string]$Execucao, $Detalhes, [int]$Threads)
    $porNome = $PorNome; $movimentos = $Movimentos; $contextos = $Contextos; $disco = $Disco
    $caminhosOrigem = $CaminhosOrigem; $detalhes = $Detalhes; $carimbo = $Carimbo; $execucao = $Execucao

    # 2) Pastas renomeadas/movidas na origem: move a cópia no próprio HD.
    if ($movimentos.Count) {
        Assert-MesmoDisco $Destino $caminhosOrigem $disco
        Write-Etapa "Movendo no HD $($movimentos.Count) arquivo(s) que só mudaram de lugar"
        foreach ($m in $movimentos) {
            $ctxNovo = $porNome[$m.PlanoNovo.Nome]
            $ctxAntigo = $porNome[$m.PlanoAntigo.Nome]
            $de = Join-Path $ctxAntigo.PastaDestino $m.Antigo.Relativo
            $para = Join-Path $ctxNovo.PastaDestino $m.Novo.Relativo
            try { [WindowsBackupAudit.Nativo]::Mover($de, $para) } catch { continue }   # será copiado normalmente
            $r = [WindowsBackupAudit.Nativo]::Verificar((Join-Path $ctxNovo.Origem.Caminho $m.Novo.Relativo), $para)
            if ($r.Ok) {
                $reg = New-Object WindowsBackupAudit.Registro
                $reg.Relativo = $m.Novo.Relativo; $reg.Bytes = $r.Bytes; $reg.Modificado = $r.Modificado
                $reg.Sha256 = $r.HashOrigem; $reg.Verificado = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
                [void]$ctxAntigo.Manifesto.Registros.Remove($m.Antigo.Relativo)
                $ctxNovo.Manifesto.Registros[$m.Novo.Relativo] = $reg
                $m.Novo.Estado = 'MOVIDO'; $m.Novo.Sha256 = $r.HashOrigem
                Add-Detalhe $detalhes 'MOVIDO' $ctxNovo.Origem.Nome $m.Novo.Relativo $r.Bytes $r.HashOrigem "Antes em $($ctxAntigo.Origem.Nome)\$($m.Antigo.Relativo)"
            } else {
                try { [WindowsBackupAudit.Nativo]::Mover($para, $de) }
                catch {
                    $m.Novo.Estado = 'ERRO'
                    $m.Novo.Mensagem = "Não foi possível desfazer a movimentação ($($_.Exception.Message)). Confira $para."
                    Add-Detalhe $detalhes 'ERRO' $ctxNovo.Origem.Nome $m.Novo.Relativo $m.Novo.Bytes '' $m.Novo.Mensagem
                }
            }
        }
    }

    # 3) Arquivos que já estão no backup mas sem registro (backup antigo ou execução
    #    interrompida): confere por SHA-256 em vez de copiar de novo.
    foreach ($ctx in $contextos) {
        if (-not $ctx.Plano.Conferir.Count) { continue }
        Write-Etapa "Conferindo $($ctx.Plano.Conferir.Count) arquivo(s) de $($ctx.Origem.Nome) que já estão no HD"
        $divergentes = Invoke-VerificacaoArquivos -Ctx $ctx -Arquivos $ctx.Plano.Conferir.ToArray() -EstadoOk 'CONFERIDO' -Detalhes $detalhes -DevolverDivergentes
        if ($divergentes.Count) {
            # A cópia no HD é diferente da origem: tratada como alterada (a antiga é guardada).
            $diferentes = @{}
            foreach ($a in $divergentes) { $diferentes[$a] = $true }
            $restantes = New-Object 'Collections.Generic.List[WindowsBackupAudit.Arquivo]'
            foreach ($a in $ctx.Plano.Conferir) {
                if ($diferentes.ContainsKey($a)) { $ctx.Plano.Alterados.Add($a) } else { $restantes.Add($a) }
            }
            $ctx.Plano.Conferir = $restantes
        }
        Save-Manifesto $ctx
    }

    # 4) Espaço livre suficiente para tudo o que falta copiar?
    $faltam = [long]0
    foreach ($ctx in $contextos) {
        foreach ($a in $ctx.Plano.Novos) { if (-not $a.Estado) { $faltam += $a.Bytes } }
        foreach ($a in $ctx.Plano.Alterados) { $faltam += $a.Bytes }
    }
    $livre = Get-LivreDestino $Destino
    if ($livre -lt ($faltam + $script:MargemEspaco)) {
        throw ("Espaço insuficiente no HD: é preciso copiar {0} e há {1} livres (margem de segurança: {2}). " +
            'Use um HD maior ou libere espaço (por exemplo, apagando pastas antigas em _VERSOES_ANTERIORES).') -f `
            (Format-Tamanho $faltam), (Format-Tamanho $livre), (Format-Tamanho $script:MargemEspaco)
    }

    # 5) Para cada origem: guardar versões antigas, copiar o que falta, conferir.
    foreach ($ctx in $contextos) {
        $nome = $ctx.Origem.Nome
        if ($ctx.Plano.Alterados.Count) {
            Assert-MesmoDisco $Destino $caminhosOrigem $disco
            $pastaVersoes = Join-Path (Join-Path (Join-Path $Destino '_VERSOES_ANTERIORES') $carimbo) $nome
            Write-Etapa "Guardando a versão anterior de $($ctx.Plano.Alterados.Count) arquivo(s) alterado(s) de $nome"
            foreach ($a in $ctx.Plano.Alterados) {
                try {
                    [WindowsBackupAudit.Nativo]::Mover((Join-Path $ctx.PastaDestino $a.Relativo), (Join-Path $pastaVersoes $a.Relativo))
                    [void]$ctx.Manifesto.Registros.Remove($a.Relativo)
                } catch {
                    $a.Estado = 'ERRO'
                    $a.Mensagem = "Não foi possível guardar a versão anterior; o arquivo não foi atualizado: $($_.Exception.Message)"
                    Add-Detalhe $detalhes 'ERRO' $nome $a.Relativo $a.Bytes '' $a.Mensagem
                }
            }
        }
        $novos = New-Object 'Collections.Generic.List[object]'
        $alterados = New-Object 'Collections.Generic.List[object]'
        $bytesCopiar = [long]0
        foreach ($a in $ctx.Plano.Novos) { if (-not $a.Estado) { $novos.Add($a); $bytesCopiar += $a.Bytes } }
        foreach ($a in $ctx.Plano.Alterados) { if (-not $a.Estado) { $alterados.Add($a); $bytesCopiar += $a.Bytes } }
        $quantos = $novos.Count + $alterados.Count
        if ($quantos) {
            Assert-MesmoDisco $Destino $caminhosOrigem $disco
            Write-Etapa "Copiando $quantos arquivo(s) de $nome ($(Format-Tamanho $bytesCopiar)) com Robocopy"
            if (-not (Test-Path -LiteralPath $ctx.PastaDestino)) { New-Item -ItemType Directory -Path $ctx.PastaDestino -Force | Out-Null }
            $ctx.Log = Join-Path $execucao "robocopy-$nome.log"
            $excluirPastas = [string[]]@(@($Config.ExcluirPastas) + @($ctx.Plano.Origem.PastasExcluir) | Where-Object { $_ })
            $excluirArquivos = [string[]]@(@($Config.ExcluirArquivos) + @($ctx.Plano.Origem.ArquivosExcluir) | Where-Object { $_ })
            $ctx.CodigoRobocopy = Invoke-Robocopy -Origem $ctx.Origem.Caminho -Destino $ctx.PastaDestino `
                -ExcluirPastas $excluirPastas -ExcluirArquivos $excluirArquivos -Log $ctx.Log -Threads $Threads `
                -BytesPrevistos $bytesCopiar -Rotulo $nome
            $extra = Invoke-PassadaNomeCurto -Ctx $ctx -Pendentes (@($novos) + @($alterados)) -ExcluirPastas $excluirPastas `
                -ExcluirArquivos $excluirArquivos -Threads $Threads
            if ($null -ne $extra) { $ctx.CodigoRobocopy = $ctx.CodigoRobocopy -bor $extra }
            if ($ctx.CodigoRobocopy -ge 8) {
                $ctx.FalhasRobocopy = Get-FalhasRobocopy -Log $ctx.Log -Origem $ctx.Origem.Caminho
                Write-Etapa "Robocopy terminou com código $($ctx.CodigoRobocopy): alguns arquivos falharam. Cada arquivo será conferido." Yellow
            }
            Write-Etapa "Conferindo as cópias de $nome por SHA-256"
            $null = Invoke-VerificacaoArquivos -Ctx $ctx -Arquivos $novos.ToArray() -EstadoOk 'COPIADO' -Detalhes $detalhes -Atividade 'Conferindo cópias de'
            $null = Invoke-VerificacaoArquivos -Ctx $ctx -Arquivos $alterados.ToArray() -EstadoOk 'ATUALIZADO' -Detalhes $detalhes -Atividade 'Conferindo cópias de'
        }
        Save-Manifesto $ctx
    }
}

# ------------------------------------------------------------------ verificar integridade
function Invoke-VerificacaoWBA {
    <#
    .SYNOPSIS
    Relê as cópias do HD e compara com o SHA-256 registrado no manifesto (detecta
    arquivos corrompidos ou alterados no backup). Arquivos com problema saem do
    manifesto: o próximo backup os copia de novo (a cópia ruim vai para _VERSOES_ANTERIORES).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Destino, [string[]]$Origens = @(), [ValidateRange(1, 100)][int]$Amostra = 100)
    $inicio = Get-Date
    Clear-CacheDisco
    $disco = Assert-DestinoSeguro $Destino $Origens
    $Destino = $Destino.TrimEnd('\', '/')
    $controle = Join-Path $Destino '_CONTROLE'
    $pastaManifestos = Join-Path $controle 'manifestos'
    if (-not (Test-Path -LiteralPath $pastaManifestos -PathType Container)) {
        throw 'Este HD ainda não tem manifestos desta versão. Faça um backup primeiro.'
    }
    $trava = Open-Trava $Destino
    $execucao = Join-Path (Join-Path $controle 'execucoes') (Get-Carimbo -Controle $controle -Sufixo '-verificacao')
    New-Item -ItemType Directory -Path $execucao -Force | Out-Null
    $detalhes = New-Detalhes (Join-Path $execucao 'detalhes.tsv')
    $linhas = New-Object 'Collections.Generic.List[object]'
    $problemas = 0; $concluido = $false; $falha = ''
    $sorteio = New-Object Random
    try {
        foreach ($arquivo in @(Get-ChildItem -LiteralPath $pastaManifestos -Filter '*.tsv' -File)) {
            $nome = $arquivo.BaseName
            $pasta = Join-Path $Destino $nome
            $m = [WindowsBackupAudit.Nativo]::LerManifesto($arquivo.FullName)
            if ($m.Problema) {
                $problemas++
                Add-Detalhe $detalhes 'ERRO' $nome '' 0 '' "Manifesto: $($m.Problema) O próximo backup confere tudo de novo."
                $linhas.Add([pscustomobject]@{ Nome = $nome; Registros = 0; Conferidos = 0; Problemas = 1; Bytes = 0 })
                continue
            }
            $registros = @($m.Registros.Values | Where-Object { $Amostra -ge 100 -or $sorteio.Next(100) -lt $Amostra })
            Write-Etapa "Conferindo $($registros.Count) arquivo(s) de $nome"
            $ok = 0; $ruins = 0; $bytes = [long]0; $feitos = 0
            $agora = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            foreach ($lote in (New-Lotes $registros { param($x) $x.Bytes })) {
                $n = $lote.Itens.Count
                $caminhos = New-Object 'string[]' $n; $tamanhos = New-Object 'long[]' $n; $shas = New-Object 'string[]' $n
                for ($i = 0; $i -lt $n; $i++) {
                    $caminhos[$i] = [IO.Path]::Combine($pasta, $lote.Itens[$i].Relativo)
                    $tamanhos[$i] = $lote.Itens[$i].Bytes
                    $shas[$i] = $lote.Itens[$i].Sha256
                }
                $resultados = [WindowsBackupAudit.Nativo]::ConferirLote($caminhos, $tamanhos, $shas, [math]::Min(2, $lote.Paralelo))
                for ($i = 0; $i -lt $n; $i++) {
                    $reg = $lote.Itens[$i]; $r = $resultados[$i]
                    $feitos++
                    if ($r.Ok) { $ok++; $bytes += $reg.Bytes; $reg.Verificado = $agora }
                    else {
                        $ruins++
                        [void]$m.Registros.Remove($reg.Relativo)
                        Add-Detalhe $detalhes 'PROBLEMA' $nome $reg.Relativo $reg.Bytes $reg.Sha256 $r.Erro
                    }
                }
                Write-Progress -Id 3 -Activity "Verificando $nome" -Status "$feitos de $($registros.Count)" -PercentComplete ([int](100.0 * $feitos / [math]::Max(1, $registros.Count)))
            }
            Write-Progress -Id 3 -Activity "Verificando $nome" -Completed
            [WindowsBackupAudit.Nativo]::GravarManifesto($arquivo.FullName, $m)
            $problemas += $ruins
            $linhas.Add([pscustomobject]@{ Nome = $nome; Registros = $m.Registros.Count + $ruins; Conferidos = $ok; Problemas = $ruins; Bytes = $bytes })
        }
        $concluido = $true
    } catch {
        $falha = $_.Exception.Message
        Write-Etapa "Verificação interrompida: $falha" Red
    } finally {
        $detalhes.Dispose()
        $sit = Get-Situacao -Erros $problemas -Avisos 0 -Concluido $concluido
        $relatorio = ''
        try {
            $relatorio = Write-RelatorioVerificacao -Execucao $execucao -Controle $controle -Destino $Destino -Disco $disco `
                -Situacao $sit.Situacao -Falha $falha -Inicio $inicio -Linhas $linhas.ToArray() -Amostra $Amostra
        } catch { Write-Etapa "Não foi possível gravar o relatório: $($_.Exception.Message)" Red }
        $trava.Dispose()
    }
    return [pscustomobject]@{
        Modo = 'Verificar'; Situacao = $sit.Situacao; CodigoSaida = $sit.Codigo; Falha = $falha; Destino = $Destino
        Relatorio = $relatorio; Inicio = $inicio; Duracao = (Get-Date) - $inicio; Erros = $problemas; Origens = $linhas.ToArray()
    }
}

Export-ModuleMember -Function @(
    'Invoke-BackupWBA', 'Get-ProgressoCopia', 'Invoke-VerificacaoWBA', 'Invoke-Robocopy', 'Format-Tamanho', 'Write-Etapa',
    'Get-FalhasRobocopy', 'Get-MotivoErro',
    'Read-Configuracao', 'ConvertFrom-TextoConfig', 'Assert-Configuracao', 'Read-TextoConfig', 'New-TextoConfig',
    'Save-TextoConfig', 'Get-OrigensSugeridas', 'Get-NomePadrao', 'Test-NomeValido', 'Resolve-CaminhoLocal',
    'Test-Dentro', 'Get-IdVersaoAnterior', 'Get-InfoDisco', 'Clear-CacheDisco', 'Assert-DestinoSeguro',
    'Resolve-Destino', 'Test-PastaDeBackup', 'Get-DiscosCandidatos', 'Select-DestinoInterativo',
    'Register-BackupAgendado', 'Unregister-BackupAgendado', 'Get-BackupAgendado',
    'Invoke-AssistenteConfiguracao', 'Invoke-AssistenteAgendamento', 'Show-Resumo', 'Open-UltimoRelatorio',
    'Set-DestinoNoTexto')
