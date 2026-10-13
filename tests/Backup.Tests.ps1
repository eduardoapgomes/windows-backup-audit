# Testes de ponta a ponta com Robocopy e sistema de arquivos reais.
# Só a identificação física do HD é simulada (o servidor de testes não tem HD USB).
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Backup.Core.psm1') -Force -DisableNameChecking

    function New-Cenario {
        # Caminhos com espaço e acento de propósito.
        $raiz = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $origem = Join-Path $raiz 'Meus Documentos'
        $destino = Join-Path $raiz 'HD Externo\BACKUP_WINDOWS\PC-Ação'
        New-Item -ItemType Directory -Force (Join-Path $origem 'Sub pasta\node_modules\lib') | Out-Null
        [IO.File]::WriteAllText((Join-Path $origem 'a.txt'), 'AAAA')
        [IO.File]::WriteAllText((Join-Path $origem 'Sub pasta\b.txt'), 'BBBB')
        [IO.File]::WriteAllText((Join-Path $origem 'Sub pasta\node_modules\lib\x.js'), 'lib')
        [IO.File]::WriteAllText((Join-Path $origem '~$aberto.docx'), 'lock')
        [IO.File]::WriteAllText((Join-Path $origem 'ação ü 日本.txt'), 'unicode')
        [IO.File]::WriteAllBytes((Join-Path $origem 'vazio.bin'), (New-Object byte[] 0))
        $grande = New-Object byte[] (9MB)
        (New-Object Random 7).NextBytes($grande)
        [IO.File]::WriteAllBytes((Join-Path $origem 'Sub pasta\grande.bin'), $grande)
        $oculto = Join-Path $origem 'oculto.txt'
        [IO.File]::WriteAllText($oculto, 'h')
        (Get-Item -LiteralPath $oculto).Attributes = 'Hidden'
        $texto = New-TextoConfig -Destino $destino -Origens @([pscustomobject]@{ Caminho = $origem; Nome = 'Documentos' })
        $config = ConvertFrom-TextoConfig $texto -Arquivo 'teste'
        Assert-Configuracao $config
        [pscustomobject]@{ Raiz = $raiz; Origem = $origem; Destino = $destino; Config = $config; Copia = (Join-Path $destino 'Documentos') }
    }
    function Invoke-Teste($Cenario, [string]$Modo = 'Backup') {
        Invoke-BackupWBA -Config $Cenario.Config -Destino $Cenario.Destino -Modo $Modo -Threads 4 -PastaSimulacao (Join-Path $Cenario.Raiz 'sim')
    }
    function Get-Soma($Resumo, [string]$Campo) { return [int](($Resumo.Origens | Measure-Object -Property $Campo -Sum).Sum) }
    function Set-ConteudoMesmaData([string]$Caminho, [byte[]]$Bytes) {
        $data = (Get-Item -LiteralPath $Caminho).LastWriteTimeUtc
        [IO.File]::WriteAllBytes($Caminho, $Bytes)
        (Get-Item -LiteralPath $Caminho).LastWriteTimeUtc = $data
    }
}

Describe 'Backup de ponta a ponta' {
    BeforeAll {
        Mock Assert-DestinoSeguro -ModuleName Backup.Core { [pscustomobject]@{ DiscoId = 'usb-teste'; Modelo = 'HD de teste'; Rotulo = 'TESTE'; Letra = 'C' } }
    }

    It 'simulação não grava nada no HD' {
        $c = New-Cenario
        $r = Invoke-Teste $c 'Simular'
        $r.CodigoSaida | Should -Be 0
        Test-Path -LiteralPath $c.Destino | Should -BeFalse
        @(Get-Content -LiteralPath $r.Relatorio | Where-Object { $_ -like 'COPIAR*' }).Count | Should -Be 6
    }

    It 'primeiro backup copia, confere e exclui o que deve' {
        $c = New-Cenario
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        $r.CodigoSaida | Should -Be 0
        Get-Soma $r 'Copiados' | Should -Be 6
        [IO.File]::ReadAllText((Join-Path $c.Copia 'Sub pasta\b.txt')) | Should -Be 'BBBB'
        Test-Path -LiteralPath (Join-Path $c.Copia 'ação ü 日本.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $c.Copia 'vazio.bin') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $c.Copia 'oculto.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $c.Copia 'Sub pasta\node_modules') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $c.Copia '~$aberto.docx') | Should -BeFalse
        (Get-FileHash -LiteralPath (Join-Path $c.Copia 'Sub pasta\grande.bin')).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $c.Origem 'Sub pasta\grande.bin')).Hash
        Test-Path -LiteralPath $r.Relatorio | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $c.Destino '_CONTROLE\ULTIMO-RELATORIO.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $c.Destino 'LEIA-ME.txt') | Should -BeTrue
        $m = [WindowsBackupAudit.Nativo]::LerManifesto((Join-Path $c.Destino '_CONTROLE\manifestos\Documentos.tsv'))
        $m.Problema | Should -BeNullOrEmpty
        $m.Registros.Count | Should -Be 6
        $m.Registros['Sub pasta\grande.bin'].Sha256 | Should -Be (Get-FileHash -LiteralPath (Join-Path $c.Origem 'Sub pasta\grande.bin')).Hash.ToLowerInvariant()
        $detalhes = Import-Csv -LiteralPath (Join-Path (Split-Path $r.Relatorio) 'detalhes.tsv') -Delimiter "`t"
        @($detalhes | Where-Object situacao -eq 'COPIADO').Count | Should -Be 6
        # A origem nunca é alterada.
        [IO.File]::ReadAllText((Join-Path $c.Origem 'a.txt')) | Should -Be 'AAAA'
    }

    It 'segunda execução não copia nem lê nada que não mudou' {
        $c = New-Cenario
        $null = Invoke-Teste $c
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        Get-Soma $r 'Copiados' | Should -Be 0
        Get-Soma $r 'Conferidos' | Should -Be 0
        Get-Soma $r 'SemMudanca' | Should -Be 6
    }

    It 'arquivo alterado: guarda a versão anterior e copia a nova' {
        $c = New-Cenario
        $null = Invoke-Teste $c
        [IO.File]::WriteAllText((Join-Path $c.Origem 'a.txt'), 'AAAA versão 2')
        $r = Invoke-Teste $c
        Get-Soma $r 'Atualizados' | Should -Be 1
        [IO.File]::ReadAllText((Join-Path $c.Copia 'a.txt')) | Should -Be 'AAAA versão 2'
        $antiga = @(Get-ChildItem -LiteralPath (Join-Path $c.Destino '_VERSOES_ANTERIORES') -Recurse -Filter 'a.txt')
        $antiga.Count | Should -Be 1
        [IO.File]::ReadAllText($antiga[0].FullName) | Should -Be 'AAAA'
    }

    It 'arquivo apagado na origem continua no backup' {
        $c = New-Cenario
        $null = Invoke-Teste $c
        Remove-Item -LiteralPath (Join-Path $c.Origem 'a.txt')
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        Test-Path -LiteralPath (Join-Path $c.Copia 'a.txt') | Should -BeTrue
    }

    It 'pasta renomeada: move no HD em vez de copiar de novo' {
        $c = New-Cenario
        $null = Invoke-Teste $c
        Rename-Item -LiteralPath (Join-Path $c.Origem 'Sub pasta') -NewName 'Pasta nova'
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        Get-Soma $r 'Movidos' | Should -Be 1      # grande.bin (os pequenos são copiados de novo)
        Test-Path -LiteralPath (Join-Path $c.Copia 'Pasta nova\grande.bin') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $c.Copia 'Sub pasta\grande.bin') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $c.Copia 'Sub pasta\b.txt') | Should -BeTrue
    }

    It 'confere por SHA-256 o que já está no HD sem manifesto e corrige cópia corrompida' {
        $c = New-Cenario
        $null = Invoke-Teste $c
        Remove-Item -LiteralPath (Join-Path $c.Destino '_CONTROLE\manifestos\Documentos.tsv')
        Set-ConteudoMesmaData (Join-Path $c.Copia 'a.txt') ([Text.Encoding]::ASCII.GetBytes('AAAX'))
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        Get-Soma $r 'Conferidos' | Should -Be 5
        Get-Soma $r 'Atualizados' | Should -Be 1
        Get-Soma $r 'Copiados' | Should -Be 0
        [IO.File]::ReadAllText((Join-Path $c.Copia 'a.txt')) | Should -Be 'AAAA'
    }

    It 'ignora manifesto adulterado e confere tudo de novo' {
        $c = New-Cenario
        $null = Invoke-Teste $c
        $caminho = Join-Path $c.Destino '_CONTROLE\manifestos\Documentos.tsv'
        $linhas = [IO.File]::ReadAllLines($caminho)
        $linhas[3] = $linhas[3] -replace '[0-9a-f]{64}', ('0' * 64)
        [IO.File]::WriteAllLines($caminho, $linhas)
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        Get-Soma $r 'Conferidos' | Should -Be 6
    }

    It 'verificação de integridade encontra cópia alterada e o backup seguinte corrige' {
        $c = New-Cenario
        $null = Invoke-Teste $c
        Set-ConteudoMesmaData (Join-Path $c.Copia 'Sub pasta\b.txt') ([Text.Encoding]::ASCII.GetBytes('XXXX'))
        $v = Invoke-VerificacaoWBA -Destino $c.Destino
        $v.Situacao | Should -Be 'ERROS'
        $v.Erros | Should -Be 1
        $r = Invoke-Teste $c
        Get-Soma $r 'Atualizados' | Should -Be 1
        (Invoke-VerificacaoWBA -Destino $c.Destino).Situacao | Should -Be 'OK'
        (Invoke-VerificacaoWBA -Destino $c.Destino -Amostra 50).CodigoSaida | Should -Be 0
    }

    It 'cópia interrompida (arquivo parcial no HD) é guardada e refeita' {
        $c = New-Cenario
        $null = Invoke-Teste $c
        [IO.File]::WriteAllText((Join-Path $c.Origem 'novo.txt'), 'conteúdo completo')
        [IO.File]::WriteAllText((Join-Path $c.Copia 'novo.txt'), 'cont')
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        [IO.File]::ReadAllText((Join-Path $c.Copia 'novo.txt')) | Should -Be 'conteúdo completo'
    }

    It 'não segue junctions nem links simbólicos' {
        $c = New-Cenario
        $fora = Join-Path $c.Raiz 'fora'
        New-Item -ItemType Directory -Force $fora | Out-Null
        [IO.File]::WriteAllText((Join-Path $fora 'segredo.txt'), 'fora')
        New-Item -ItemType Junction -Path (Join-Path $c.Origem 'atalho') -Target $fora | Out-Null
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        Get-Soma $r 'Links' | Should -Be 1
        Test-Path -LiteralPath (Join-Path $c.Copia 'atalho') | Should -BeFalse
    }

    It 'arquivo só na nuvem (atributo Offline) não é baixado: aviso, código 1' {
        $c = New-Cenario
        $p = Join-Path $c.Origem 'na nuvem.docx'
        [IO.File]::WriteAllText($p, 'placeholder')
        (Get-Item -LiteralPath $p).Attributes = [IO.FileAttributes]::Offline
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'AVISOS'
        $r.CodigoSaida | Should -Be 1
        $r.SoNaNuvem | Should -Be 1
        Test-Path -LiteralPath (Join-Path $c.Copia 'na nuvem.docx') | Should -BeFalse
        (Get-Item -LiteralPath $p).Attributes = [IO.FileAttributes]::Normal
    }

    It 'arquivo em uso vira erro (código 2) sem afetar os outros; depois é copiado' {
        $c = New-Cenario
        $p = Join-Path $c.Origem 'em uso.pst'
        [IO.File]::WriteAllText($p, 'dados')
        $trava = [IO.File]::Open($p, 'Open', 'ReadWrite', 'None')
        try {
            $r = Invoke-Teste $c
            $r.Situacao | Should -Be 'ERROS'
            $r.CodigoSaida | Should -Be 2
            Get-Soma $r 'Copiados' | Should -Be 6
        } finally { $trava.Dispose() }
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        Get-Soma $r 'Copiados' | Should -Be 1
    }

    It 'caminhos com mais de 260 caracteres' {
        $c = New-Cenario
        $curto = Join-Path $c.Origem 'p1\p2'
        New-Item -ItemType Directory -Force $curto | Out-Null
        [IO.File]::WriteAllText((Join-Path $curto 'longo.txt'), 'caminho longo')
        Rename-Item -LiteralPath $curto -NewName ('B' * 120)
        Rename-Item -LiteralPath (Join-Path $c.Origem 'p1') -NewName ('A' * 120)
        $relativo = ('A' * 120) + '\' + ('B' * 120) + '\longo.txt'
        (Join-Path $c.Copia $relativo).Length | Should -BeGreaterThan 260
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        Get-Soma $r 'Copiados' | Should -Be 7
        [WindowsBackupAudit.Nativo]::Info((Join-Path $c.Copia $relativo)) | Should -Not -BeNullOrEmpty
        (Invoke-VerificacaoWBA -Destino $c.Destino).Situacao | Should -Be 'OK'
    }

    It 'pasta da versão 1 (AUTO_...) é renomeada e conferida, sem recópia' {
        $c = New-Cenario
        $antiga = Join-Path $c.Destino (Get-IdVersaoAnterior $c.Origem)
        New-Item -ItemType Directory -Force $antiga, (Join-Path $c.Destino '_RELATORIOS') | Out-Null
        Copy-Item -LiteralPath (Join-Path $c.Origem 'a.txt') -Destination (Join-Path $antiga 'a.txt')
        (Get-Item -LiteralPath (Join-Path $antiga 'a.txt')).LastWriteTimeUtc = (Get-Item -LiteralPath (Join-Path $c.Origem 'a.txt')).LastWriteTimeUtc
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'OK'
        Test-Path -LiteralPath $antiga | Should -BeFalse
        Get-Soma $r 'Conferidos' | Should -Be 1
        Get-Soma $r 'Copiados' | Should -Be 5
    }

    It 'sem espaço no HD: não copia nada e informa' {
        $c = New-Cenario
        Mock Get-LivreDestino -ModuleName Backup.Core { 0 }
        $r = Invoke-Teste $c
        $r.Situacao | Should -Be 'INTERROMPIDO'
        $r.Falha | Should -Match 'Espaço insuficiente'
        Test-Path -LiteralPath (Join-Path $c.Copia 'a.txt') | Should -BeFalse
    }

    It 'impede duas execuções no mesmo HD ao mesmo tempo' {
        $c = New-Cenario
        New-Item -ItemType Directory -Force $c.Destino | Out-Null
        $trava = [IO.File]::Open((Join-Path $c.Destino '.backup.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
        try { { Invoke-Teste $c } | Should -Throw '*Outro backup*' }
        finally { $trava.Dispose() }
    }
}

Describe 'Motor nativo' {
    It 'aplica padrões de exclusão como o Robocopy' {
        $f = [WindowsBackupAudit.Filtro]::new([string[]]@('node_modules', 'cache*', 'C:\Dados\Grande'), [string[]]@('*.tmp', '~$*'))
        $f.ExcluiPasta('node_modules', 'C:\x\node_modules') | Should -BeTrue
        $f.ExcluiPasta('Cache2', 'C:\x\Cache2') | Should -BeTrue
        $f.ExcluiPasta('Grande', 'C:\Dados\Grande') | Should -BeTrue
        $f.ExcluiPasta('Grande', 'C:\Outro\Grande') | Should -BeFalse
        $f.ExcluiArquivo('a.TMP', 'C:\a.TMP') | Should -BeTrue
        $f.ExcluiArquivo('~$doc.docx', 'C:\~$doc.docx') | Should -BeTrue
        $f.ExcluiArquivo('doc.docx', 'C:\doc.docx') | Should -BeFalse
    }
    It 'reconhece tags de nuvem e de link' {
        # Sufixo L: sem ele o PowerShell lê 0x9000001A como Int32 negativo.
        foreach ($v in 0..15) { [WindowsBackupAudit.Nativo]::EhNuvem([uint32](0x9000001AL + $v * 0x1000)) | Should -BeTrue }
        [WindowsBackupAudit.Nativo]::EhNuvem([uint32]0xA0000003L) | Should -BeFalse
        [WindowsBackupAudit.Nativo]::EhLink([uint32]0xA0000003L) | Should -BeTrue    # junction
        [WindowsBackupAudit.Nativo]::EhLink([uint32]0xA000000CL) | Should -BeTrue    # symlink
        [WindowsBackupAudit.Nativo]::EhLink([uint32]0x80000017L) | Should -BeFalse   # WOF (arquivo comprimido)
        [WindowsBackupAudit.Nativo]::EhLink([uint32]0x9000001AL) | Should -BeFalse   # OneDrive
    }
    It 'calcula SHA-256 igual ao Get-FileHash' {
        $p = Join-Path $TestDrive 'hash.bin'
        $b = New-Object byte[] (3MB + 17)
        (New-Object Random 3).NextBytes($b)
        [IO.File]::WriteAllBytes($p, $b)
        [WindowsBackupAudit.Nativo]::Sha256($p) | Should -Be (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
