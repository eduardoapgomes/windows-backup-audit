# Backup.ps1 executado como o menu executa: um processo novo do PowerShell.
BeforeAll {
    $script:Entrada = Join-Path $PSScriptRoot '..\Backup.ps1'
    $script:Exe = (Get-Process -Id $PID).Path
    function Invoke-Cli([string[]]$Argumentos) {
        $saida = & $script:Exe -NoProfile -ExecutionPolicy Bypass -File $script:Entrada @Argumentos 2>&1 | Out-String
        [pscustomobject]@{ Codigo = $LASTEXITCODE; Saida = $saida }
    }
}

Describe 'Backup.ps1 na linha de comando' {
    It 'sem configuração: não executa (código 3) e indica Configurar' {
        $r = Invoke-Cli @('-Acao', 'Backup', '-Config', (Join-Path $TestDrive 'nao-existe.txt'), '-SemAbrirRelatorio')
        $r.Codigo | Should -Be 3
        $r.Saida | Should -Match 'Configurar'
    }
    It 'configuração com erro: mostra a linha do problema' {
        $cfg = Join-Path $TestDrive 'ruim.txt'
        [IO.File]::WriteAllText($cfg, "[DESTINO]`r`nE:\BACKUP`r`n[ORIGENS]`r`npasta\relativa`r`n", (New-Object Text.UTF8Encoding($true)))
        $r = Invoke-Cli @('-Acao', 'Simular', '-Config', $cfg)
        $r.Codigo | Should -Be 3
        $r.Saida | Should -Match 'Linha 4'
    }
    It 'recusa um destino que não é HD externo USB e não cria nada' {
        $origem = Join-Path $TestDrive 'origem'
        New-Item -ItemType Directory -Force $origem | Out-Null
        $destino = Join-Path $TestDrive 'nao-e-usb\BACKUP'
        $cfg = Join-Path $TestDrive 'cfg.txt'
        [IO.File]::WriteAllText($cfg, "[DESTINO]`r`n$destino`r`n[ORIGENS]`r`n$origem`r`n", (New-Object Text.UTF8Encoding($true)))
        $r = Invoke-Cli @('-Acao', 'Simular', '-Config', $cfg)
        $r.Codigo | Should -Be 3
        $r.Saida | Should -Match '(USB|identidade|mesmo disco)'
        Test-Path -LiteralPath $destino | Should -BeFalse
    } -Skip:(-not (Get-Command Get-Disk -ErrorAction SilentlyContinue))
}
