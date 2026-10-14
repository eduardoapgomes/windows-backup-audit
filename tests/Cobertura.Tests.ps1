# Procurar arquivos fora do backup (menu 8).
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Backup.Core.psm1') -Force -DisableNameChecking
    function New-Arquivo([string]$Caminho, [string]$Texto = 'x') {
        New-Item -ItemType Directory -Force (Split-Path -Parent $Caminho) | Out-Null
        [IO.File]::WriteAllText($Caminho, $Texto)
    }
}

Describe 'Arquivos fora do backup' {
    BeforeAll {
        $raiz = Join-Path $TestDrive 'cobertura'
        $script:perfil = Join-Path $raiz 'Usuario'
        $script:appdata = Join-Path $raiz 'AppData\Roaming'
        $docs = Join-Path $perfil 'Documentos'
        New-Arquivo (Join-Path $docs 'no backup.docx')
        New-Arquivo (Join-Path $perfil 'Pesquisa\artigo.pdf')
        New-Arquivo (Join-Path $perfil 'Pesquisa\dados\medidas.csv')
        New-Arquivo (Join-Path $perfil 'Pesquisa\node_modules\lib\x.js')
        New-Arquivo (Join-Path $perfil 'Pesquisa\venv\Lib\site-packages\pacote\m.py')
        New-Arquivo (Join-Path $perfil 'solto.xlsx')
        New-Arquivo (Join-Path $perfil 'Programa\app.exe')
        New-Arquivo (Join-Path $perfil '.vscode\extensions\ext\main.js')
        New-Arquivo (Join-Path $perfil '.gnupg\pubring.kbx')
        New-Arquivo (Join-Path $appdata 'Bitcoin\wallets\wallet.dat')
        New-Arquivo (Join-Path $appdata 'Algum App\icone.png')
        $texto = New-TextoConfig -Destino 'E:\BACKUP_WINDOWS\PC' -Origens @([pscustomobject]@{ Caminho = $docs; Nome = '' })
        $script:config = ConvertFrom-TextoConfig $texto -Arquivo 'teste'
        Assert-Configuracao $config
        $script:relatorios = Join-Path $raiz 'relatorios'
        $raizes = Get-RaizesCobertura -Perfil $perfil -AppData @($appdata) -SemDiscos
        $script:r = Find-ArquivosForaDoBackup -Config $config -Raizes $raizes.Comuns -RaizesCriticas $raizes.Criticas -PastaRelatorio $relatorios
        $script:porPasta = @{}
        foreach ($g in $r.Grupos) { $porPasta[$g.Pasta] = $g }
    }

    It 'encontra arquivos pessoais fora das origens, agrupados por pasta' {
        $porPasta[(Join-Path $perfil 'Pesquisa')].Arquivos | Should -Be 2
        $porPasta["$perfil (arquivos soltos)"].Arquivos | Should -Be 1
    }
    It 'ignora o que já está no backup, exclusões, programas e pastas ocultas comuns' {
        $porPasta.ContainsKey((Join-Path $perfil 'Documentos')) | Should -BeFalse
        $porPasta.ContainsKey((Join-Path $perfil 'Programa')) | Should -BeFalse
        $porPasta.ContainsKey((Join-Path $perfil '.vscode')) | Should -BeFalse
        $porPasta.ContainsKey((Join-Path $appdata 'Algum App')) | Should -BeFalse
        $r.Arquivos | Should -Be 5
    }
    It 'em AppData e nas pastas ocultas, aponta carteiras e chaves (primeiro na lista)' {
        $porPasta[(Join-Path $appdata 'Bitcoin')].Critico | Should -BeTrue
        $porPasta[(Join-Path $perfil '.gnupg')].Critico | Should -BeTrue
        $r.Criticos | Should -Be 2
        $r.Grupos[0].Critico | Should -BeTrue
        $r.Grupos[1].Critico | Should -BeTrue
    }
    It 'grava a lista completa para o Excel' {
        $linhas = Import-Csv -LiteralPath $r.Relatorio -Delimiter "`t"
        @($linhas).Count | Should -Be 5
        @($linhas | Where-Object { $_.caminho -like '*wallet.dat' }).Count | Should -Be 1
    }
    It 'não procura dentro de uma pasta que já é origem' {
        $s = Find-ArquivosForaDoBackup -Config $config -Raizes @((Join-Path $perfil 'Documentos')) -RaizesCriticas @()
        $s.Arquivos | Should -Be 0
        { Show-Cobertura $s } | Should -Not -Throw
        { Show-Cobertura $r } | Should -Not -Throw
    }
    It 'classifica pelo nome do arquivo' {
        Get-TipoPessoal 'x\Relatório Final.DOCX' | Should -Be 'Documento'
        Get-TipoPessoal 'wallet.dat' | Should -Match 'Carteira'
        Get-TipoPessoal 'senhas.kdbx' -SoCriticos | Should -Match 'Carteira'
        Get-TipoPessoal 'foto.jpg' -SoCriticos | Should -BeNullOrEmpty
        Get-TipoPessoal 'programa.exe' | Should -BeNullOrEmpty
        Get-TipoPessoal 'LEIAME' | Should -BeNullOrEmpty
    }
    It 'por padrão procura no perfil e nos discos internos (não no HD USB)' {
        $raizes = Get-RaizesCobertura
        @($raizes.Comuns | Where-Object { $_.Caminho -eq $env:USERPROFILE }).Count | Should -Be 1
        @($raizes.Comuns | Where-Object { $_.Caminho -match '\\(Windows|Program Files)$' }).Count | Should -Be 0
    } -Skip:([Environment]::OSVersion.Platform -ne 'Win32NT')
}
