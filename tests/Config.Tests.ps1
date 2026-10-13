BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Backup.Core.psm1') -Force -DisableNameChecking
}

Describe 'Leitura do arquivo de configuração' {
    It 'lê seções, comentários, aspas e nomes escolhidos' {
        $texto = @"
# comentário
[DESTINO]
"E:\BACKUP_WINDOWS\PC-teste"

[ORIGENS]
C:\Users\Ana\Documents
  "D:\Fotos de família" > Fotos-D
[excluir pastas]
node_modules
[EXCLUIR_ARQUIVOS]
*.tmp
"@
        $c = ConvertFrom-TextoConfig $texto
        $c.Destino | Should -Be 'E:\BACKUP_WINDOWS\PC-teste'
        $c.Origens.Count | Should -Be 2
        $c.Origens[0].Caminho | Should -Be 'C:\Users\Ana\Documents'
        $c.Origens[0].Nome | Should -Be ''
        $c.Origens[1].Caminho | Should -Be 'D:\Fotos de família'
        $c.Origens[1].Nome | Should -Be 'Fotos-D'
        $c.ExcluirPastas | Should -Be @('node_modules')
        $c.ExcluirArquivos | Should -Be @('*.tmp')
    }
    It 'recusa seção desconhecida, linha fora de seção e dois destinos' {
        { ConvertFrom-TextoConfig "[PASTAS]`nC:\x" } | Should -Throw '*seção desconhecida*'
        { ConvertFrom-TextoConfig "C:\x" } | Should -Throw '*fora de uma seção*'
        { ConvertFrom-TextoConfig "[DESTINO]`nE:\a`nF:\b" } | Should -Throw '*apenas uma*'
    }
    It 'lê UTF-8 com e sem BOM, UTF-16 e ANSI (Bloco de Notas antigo)' {
        $texto = "[ORIGENS]`r`nC:\Ação"
        $arquivo = Join-Path $TestDrive 'cfg.txt'
        foreach ($codificacao in @((New-Object Text.UTF8Encoding($true)), (New-Object Text.UTF8Encoding($false)), [Text.Encoding]::Unicode, [Text.Encoding]::GetEncoding(1252))) {
            $bytes = $codificacao.GetPreamble() + $codificacao.GetBytes($texto)
            [IO.File]::WriteAllBytes($arquivo, $bytes)
            (ConvertFrom-TextoConfig (Read-TextoConfig $arquivo)).Origens[0].Caminho | Should -Be 'C:\Ação'
        }
    }
    It 'gera um arquivo que é lido de volta igual' {
        $origens = @([pscustomobject]@{ Caminho = 'C:\Users\Ana\Documents'; Nome = '' }, [pscustomobject]@{ Caminho = 'D:\Projetos'; Nome = 'D_Projetos' })
        $c = ConvertFrom-TextoConfig (New-TextoConfig -Destino 'E:\B\PC' -Origens $origens)
        $c.Destino | Should -Be 'E:\B\PC'
        $c.Origens[0].Caminho | Should -Be 'C:\Users\Ana\Documents'
        $c.Origens[1].Nome | Should -Be 'D_Projetos'
        $c.ExcluirPastas | Should -Contain 'node_modules'
        $c.ExcluirPastas | Should -Not -Contain '.git'
        $c.ExcluirArquivos | Should -Contain '~$*'
    }
    It 'troca só a linha do destino e preserva o resto' {
        $texto = "# meu comentário`r`n[DESTINO]`r`n# dica`r`nE:\velho`r`n[ORIGENS]`r`nC:\Dados"
        $novo = Set-DestinoNoTexto $texto 'F:\novo'
        $novo | Should -Match '# meu comentário'
        $novo | Should -Match '# dica'
        (ConvertFrom-TextoConfig $novo).Destino | Should -Be 'F:\novo'
        (ConvertFrom-TextoConfig (Set-DestinoNoTexto "[ORIGENS]`r`nC:\Dados" 'G:\x')).Destino | Should -Be 'G:\x'
    }
}

Describe 'Validação da configuração' {
    BeforeAll {
        $base = Join-Path $TestDrive 'dados'
        New-Item -ItemType Directory -Force (Join-Path $base 'Docs\Sub'), (Join-Path $base 'Fotos') | Out-Null
        function Test-Erro([string]$Texto) {
            $c = ConvertFrom-TextoConfig $Texto -Arquivo 'teste.txt'
            try { Assert-Configuracao $c; return '' } catch { return $_.Exception.Message }
        }
    }
    It 'aceita pastas válidas e dá nomes padrão' {
        $c = ConvertFrom-TextoConfig "[ORIGENS]`r`n$base\Docs`r`n$base\Fotos > Minhas Fotos"
        Assert-Configuracao $c
        $c.Origens[0].Nome | Should -Be 'Docs'
        $c.Origens[1].Nome | Should -Be 'Minhas Fotos'
    }
    It 'mostra todos os problemas de uma vez' {
        $msg = Test-Erro "[ORIGENS]`r`n$base\Docs`r`n$base\Docs\Sub > Sub`r`nrelativo\pasta`r`n$base\NaoExiste`r`n$base\Fotos > _reservado"
        $msg | Should -Match 'já está dentro'
        $msg | Should -Match 'caminho completo'
        $msg | Should -Match 'não existe'
        $msg | Should -Match 'inválido'
    }
    It 'recusa nomes repetidos, disco inteiro, pasta do Windows e rede' {
        Test-Erro "[ORIGENS]`r`n$base\Docs > X`r`n$base\Fotos > x" | Should -Match 'já é usado'
        Test-Erro "[ORIGENS]`r`nC:\" | Should -Match 'disco inteiro'
        Test-Erro "[ORIGENS]`r`n$env:windir\System32" | Should -Match 'Windows'
        Test-Erro "[ORIGENS]`r`n\\servidor\pasta" | Should -Match 'letra de unidade'
        Test-Erro "[ORIGENS]`r`n$base\Docs > CON" | Should -Match 'inválido'
        Test-Erro '[ORIGENS]' | Should -Match 'Nenhuma pasta'
    }
    It 'limpa nomes padrão' {
        Get-NomePadrao 'C:\Users\Ana\_Projetos.' | Should -Be 'Projetos'
        Get-NomePadrao 'C:\x\.config' | Should -Be 'config'
        Test-NomeValido 'Documentos' | Should -BeTrue
        Test-NomeValido '_CONTROLE' | Should -BeFalse
        Test-NomeValido 'a:b' | Should -BeFalse
    }
}

Describe 'Compatibilidade com a versão anterior' {
    It 'calcula o nome AUTO_ usado pela versão 1' {
        # SHA-256 de "C:\DADOS" em UTF-8: primeiros 16 dígitos.
        Get-IdVersaoAnterior 'C:\Dados\' | Should -Be 'AUTO_FE1913109510F2BA'
    }
    It 'importa backup.local.json mantendo os nomes de pasta' {
        $json = Join-Path $TestDrive 'backup.local.json'
        '{"Destination":"E:\\BACKUP_WINDOWS\\PC","Sources":[{"Id":"PASTA_01","Path":"C:\\Dados"},{"Id":"_ruim","Path":"C:\\Outra"}]}' |
            Set-Content -LiteralPath $json -Encoding UTF8
        $s = Get-OrigensSugeridas -ConfigAntiga $json
        $s.Importada | Should -BeTrue
        $s.Destino | Should -Be 'E:\BACKUP_WINDOWS\PC'
        $s.Origens[0].Nome | Should -Be 'PASTA_01'
        $s.Origens[1].Nome | Should -Be ''
    }
}
