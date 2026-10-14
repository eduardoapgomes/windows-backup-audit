# ferramentas\Sair-de-tudo.ps1 num perfil de mentira (variáveis de ambiente apontando para o TestDrive).
BeforeAll {
    $script:ferramenta = Join-Path $PSScriptRoot '..\ferramentas\Sair-de-tudo.ps1'
    $script:shell = (Get-Process -Id $PID).Path
    function New-Arquivo([string]$Caminho) {
        New-Item -ItemType Directory -Force (Split-Path -Parent $Caminho) | Out-Null
        [IO.File]::WriteAllText($Caminho, 'x')
    }
    function Invoke-Ferramenta([string]$Raiz, [string[]]$Argumentos) {
        $antes = @{ L = $env:LOCALAPPDATA; R = $env:APPDATA; U = $env:USERPROFILE }
        try {
            $env:LOCALAPPDATA = Join-Path $Raiz 'Local'; $env:APPDATA = Join-Path $Raiz 'Roaming'; $env:USERPROFILE = $Raiz
            $saida = & $shell -NoProfile -ExecutionPolicy Bypass -File $ferramenta @Argumentos 2>&1 | Out-String
            [pscustomobject]@{ Codigo = $LASTEXITCODE; Saida = $saida }
        } finally { $env:LOCALAPPDATA = $antes.L; $env:APPDATA = $antes.R; $env:USERPROFILE = $antes.U }
    }
    function New-Perfil {
        $raiz = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Arquivo (Join-Path $raiz 'Local\Google\Chrome\User Data\Default\Login Data')
        New-Arquivo (Join-Path $raiz 'Local\BraveSoftware\Brave-Browser\User Data\Default\Cookies')
        New-Arquivo (Join-Path $raiz 'Roaming\Mozilla\Firefox\Profiles\abc.default\logins.json')
        New-Arquivo (Join-Path $raiz 'Roaming\Telegram Desktop\tdata\key_datas')
        New-Arquivo (Join-Path $raiz 'Local\Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalState\sessions.db')
        New-Arquivo (Join-Path $raiz '.git-credentials')
        New-Arquivo (Join-Path $raiz 'Documents\meu documento.docx')
        New-Arquivo (Join-Path $raiz 'Local\Google\Chrome\Application\chrome.txt')
        $raiz
    }
}

Describe 'Sair de tudo' {
    It 'simulação lista o que seria apagado e não apaga nada' {
        $raiz = New-Perfil
        $r = Invoke-Ferramenta $raiz @('-ManterCredenciais')
        $r.Codigo | Should -Be 0
        $r.Saida | Should -Match 'Google Chrome'
        $r.Saida | Should -Match 'WhatsApp'
        $r.Saida | Should -Match 'SIMULA'
        Test-Path -LiteralPath (Join-Path $raiz 'Local\Google\Chrome\User Data') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $raiz '.git-credentials') | Should -BeTrue
    }
    It 'com -Executar apaga logins e sessões e não toca nos arquivos' {
        $raiz = New-Perfil
        $r = Invoke-Ferramenta $raiz @('-Executar', '-SemPerguntar', '-ManterCredenciais')
        $r.Codigo | Should -Be 0 -Because $r.Saida
        foreach ($p in 'Local\Google\Chrome\User Data', 'Local\BraveSoftware\Brave-Browser\User Data', 'Roaming\Mozilla\Firefox',
            'Roaming\Telegram Desktop\tdata', 'Local\Packages\5319275A.WhatsAppDesktop_cv1g1gvanyjgm\LocalState', '.git-credentials') {
            Test-Path -LiteralPath (Join-Path $raiz $p) | Should -BeFalse -Because $p
        }
        Test-Path -LiteralPath (Join-Path $raiz 'Documents\meu documento.docx') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $raiz 'Local\Google\Chrome\Application\chrome.txt') | Should -BeTrue
    }
    It 'lista as credenciais do Windows sem erro' {
        $raiz = New-Perfil
        $r = Invoke-Ferramenta $raiz @()
        $r.Codigo | Should -Be 0 -Because $r.Saida
        $r.Saida | Should -Match 'Credenciais do Windows: \d+'
    }
}
