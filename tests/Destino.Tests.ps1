BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\src\Backup.Core.psm1') -Force -DisableNameChecking
}

Describe 'Regras do HD de destino (metadados de disco simulados)' {
    BeforeAll {
        # E: e F: são partições do MESMO HD USB; G: é exFAT; H: é USB do sistema; C: é interno.
        Mock Get-InfoDisco -ModuleName Backup.Core {
            $base = @{ DiscoId = 'usb-1'; Modelo = 'HD USB'; Barramento = 'USB'; DiscoDoSistema = $false; Offline = $false
                SomenteLeitura = $false; SistemaArquivos = 'NTFS'; Rotulo = 'BACKUP'; Tamanho = 1TB; Letra = $Letra.Substring(0, 1) }
            switch ($Letra.Substring(0, 1)) {
                'C' { $base.DiscoId = 'interno'; $base.Barramento = 'NVMe'; $base.DiscoDoSistema = $true }
                'G' { $base.DiscoId = 'usb-2'; $base.SistemaArquivos = 'exFAT' }
                'H' { $base.DiscoId = 'usb-3'; $base.DiscoDoSistema = $true }
                'K' { $base.DiscoId = 'usb-4'; $base.SomenteLeitura = $true }
                'L' { $base.DiscoId = '' }
            }
            [pscustomobject]$base
        }
    }
    It 'aceita um HD USB NTFS em outro disco' {
        (Assert-DestinoSeguro 'E:\BACKUP_WINDOWS\PC' @('C:\Users\Ana\Documents')).DiscoId | Should -Be 'usb-1'
    }
    It 'recusa disco interno, disco do sistema, exFAT, somente leitura e disco sem identidade' {
        { Assert-DestinoSeguro 'C:\Backup' @() } | Should -Throw '*não é um HD externo USB*'
        { Assert-DestinoSeguro 'H:\Backup' @() } | Should -Throw '*Windows está instalado*'
        { Assert-DestinoSeguro 'G:\Backup' @() } | Should -Throw '*NTFS*'
        { Assert-DestinoSeguro 'K:\Backup' @() } | Should -Throw '*protegido contra gravação*'
        { Assert-DestinoSeguro 'L:\Backup' @() } | Should -Throw '*identidade*'
    }
    It 'recusa outra partição do mesmo disco físico da origem' {
        { Assert-DestinoSeguro 'E:\Backup' @('F:\Dados') } | Should -Throw '*mesmo disco físico*'
    }
    It 'recusa a raiz do HD (exceto para listar discos)' {
        { Assert-DestinoSeguro 'E:\' @() } | Should -Throw '*não a raiz*'
        (Assert-DestinoSeguro 'E:\' @() -PermitirRaiz).Letra | Should -Be 'E'
    }
}

Describe 'Encontrar o HD quando a letra muda' {
    BeforeAll {
        Mock Get-UnidadesProntas -ModuleName Backup.Core { @('C', 'F', 'G') }
        Mock Assert-DestinoSeguro -ModuleName Backup.Core { [pscustomobject]@{ DiscoId = "id-$($Destino.Substring(0,1))" } }
    }
    It 'usa a mesma pasta em outra letra' {
        Mock Test-PastaDeBackup -ModuleName Backup.Core { $Caminho -like 'F:*' }
        Resolve-Destino -Configurado 'E:\BACKUP_WINDOWS\PC-ana' | Should -Be 'F:\BACKUP_WINDOWS\PC-ana'
    }
    It 'no modo automático, recusa dois HDs com o mesmo backup' {
        Mock Test-PastaDeBackup -ModuleName Backup.Core { $Caminho -like 'F:*' -or $Caminho -like 'G:*' }
        { Resolve-Destino -Configurado 'E:\BACKUP_WINDOWS\PC-ana' -Automatico } | Should -Throw '*mais de um HD*'
    }
    It 'avisa quando o HD não está conectado' {
        Mock Test-PastaDeBackup -ModuleName Backup.Core { $false }
        { Resolve-Destino -Configurado 'Q:\BACKUP_WINDOWS\PC-ana' } | Should -Throw '*não encontrado*'
    }
    It 'pede para configurar quando não há destino' {
        { Resolve-Destino -Configurado '' } | Should -Throw '*Configurar*'
    }
}
