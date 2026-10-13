BeforeAll {
    $updater = Join-Path $PSScriptRoot '..\Atualizar.cmd'

    # Windows PowerShell 5.1 converte mensagens normais do stderr do Git em
    # RemoteException sob Pester -CI. O cmd.exe redireciona o stderr antes
    # que ele chegue ao PowerShell, preservando o codigo de saida.
    function Invoke-FixtureGit {
        param([string]$Command)
        & cmd.exe /d /c ($Command + ' 1>nul 2>nul')
        if ($LASTEXITCODE -ne 0) { throw "Git fixture failed (exit $LASTEXITCODE): $Command" }
    }
    function Invoke-TestUpdater {
        param([string]$Path)
        & cmd.exe /d /c ('call "' + $Path + '" --no-pause 2>nul')
    }
}
Describe 'Safe one-click updater' {
    It 'refuses a ZIP installation without modifying its files' {
        $dir = New-Item -ItemType Directory (Join-Path $TestDrive 'zip install') -Force
        $path = Join-Path $dir.FullName 'Atualizar.cmd'
        Copy-Item -LiteralPath $updater -Destination $path
        Set-Content -LiteralPath (Join-Path $dir.FullName 'backup.local.json') -Value 'my config'
        $output = Invoke-TestUpdater -Path $path
        $LASTEXITCODE | Should -Be 2
        ($output -join ' ') | Should -Match 'ZIP'
        (Get-Content -LiteralPath (Join-Path $dir.FullName 'backup.local.json') -Raw) | Should -Match 'my config'
    }

    It 'fast-forwards main from an offline origin and preserves manual config; rejects dirty files' -Skip:($null -eq (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        $remote = Join-Path $TestDrive 'origin.git'
        $client = Join-Path $TestDrive 'project with spaces'
        $other = Join-Path $TestDrive 'other'

        Invoke-FixtureGit ('git init --bare "' + $remote + '"')
        Invoke-FixtureGit ('git clone "' + $remote + '" "' + $client + '"')
        Invoke-FixtureGit ('git -C "' + $client + '" checkout -b main')
        Invoke-FixtureGit ('git -C "' + $client + '" config user.name "Updater CI"')
        Invoke-FixtureGit ('git -C "' + $client + '" config user.email updater@example.invalid')
        Copy-Item -LiteralPath $updater -Destination (Join-Path $client 'Atualizar.cmd')
        New-Item -ItemType Directory (Join-Path $client 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $client 'Backup.ps1') -Value '# test entry'
        Set-Content -LiteralPath (Join-Path $client 'src\Backup.Core.psm1') -Value '# test module'
        Set-Content -LiteralPath (Join-Path $client '.gitignore') -Value 'backup.local.json'
        Invoke-FixtureGit ('git -C "' + $client + '" add .')
        Invoke-FixtureGit ('git -C "' + $client + '" commit -m initial')
        Invoke-FixtureGit ('git -C "' + $client + '" push -u origin main')

        Invoke-FixtureGit ('git clone --branch main "' + $remote + '" "' + $other + '"')
        Invoke-FixtureGit ('git -C "' + $other + '" config user.name "Updater CI"')
        Invoke-FixtureGit ('git -C "' + $other + '" config user.email updater@example.invalid')
        Set-Content -LiteralPath (Join-Path $other 'new-version.txt') -Value 'latest'
        Invoke-FixtureGit ('git -C "' + $other + '" add new-version.txt')
        Invoke-FixtureGit ('git -C "' + $other + '" commit -m update')
        Invoke-FixtureGit ('git -C "' + $other + '" push origin main')

        Set-Content -LiteralPath (Join-Path $client 'backup.local.json') -Value 'private config'
        $output = Invoke-TestUpdater -Path (Join-Path $client 'Atualizar.cmd')
        $LASTEXITCODE | Should -Be 0
        (Test-Path -LiteralPath (Join-Path $client 'new-version.txt')) | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $client 'backup.local.json') -Raw) | Should -Match 'private config'

        Set-Content -LiteralPath (Join-Path $client 'Backup.ps1') -Value '# user change'
        $output = Invoke-TestUpdater -Path (Join-Path $client 'Atualizar.cmd')
        $LASTEXITCODE | Should -Be 3
        ($output -join ' ') | Should -Match 'modificacoes locais'
        (Get-Content -LiteralPath (Join-Path $client 'Backup.ps1') -Raw) | Should -Match 'user change'
    }
}
