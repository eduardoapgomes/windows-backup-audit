BeforeAll {
    $updater = Join-Path $PSScriptRoot '..\Atualizar.cmd'
    $hasGit = $null -ne (Get-Command git.exe -ErrorAction SilentlyContinue)
}
Describe 'Safe one-click updater' {
    It 'refuses a ZIP installation without modifying its files' {
        $dir = New-Item -ItemType Directory (Join-Path $TestDrive 'zip install') -Force
        Copy-Item -LiteralPath $updater -Destination (Join-Path $dir.FullName 'Atualizar.cmd')
        Set-Content -LiteralPath (Join-Path $dir.FullName 'backup.local.json') -Value 'my config'
        $output = & (Join-Path $dir.FullName 'Atualizar.cmd') 2>&1
        $LASTEXITCODE | Should -Be 2
        ($output -join ' ') | Should -Match 'ZIP'
        (Get-Content -LiteralPath (Join-Path $dir.FullName 'backup.local.json') -Raw) | Should -Match 'my config'
    }

    It 'fast-forwards main from an offline origin and preserves manual config; rejects dirty files' -Skip:(-not $hasGit) {
        $remote = Join-Path $TestDrive 'origin.git'
        $client = Join-Path $TestDrive 'project with spaces'
        $other = Join-Path $TestDrive 'other'
        & git init --bare $remote 2>&1 | Out-Null
        & git clone $remote $client 2>&1 | Out-Null
        & git -C $client checkout -b main 2>&1 | Out-Null
        & git -C $client config user.name 'Updater CI'
        & git -C $client config user.email 'updater@example.invalid'
        Copy-Item -LiteralPath $updater -Destination (Join-Path $client 'Atualizar.cmd')
        New-Item -ItemType Directory (Join-Path $client 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $client 'Backup.ps1') -Value '# test entry'
        Set-Content -LiteralPath (Join-Path $client 'src\Backup.Core.psm1') -Value '# test module'
        Set-Content -LiteralPath (Join-Path $client '.gitignore') -Value 'backup.local.json'
        & git -C $client add . 2>&1 | Out-Null
        & git -C $client commit -m 'initial' 2>&1 | Out-Null
        & git -C $client push -u origin main 2>&1 | Out-Null

        & git clone --branch main $remote $other 2>&1 | Out-Null
        & git -C $other config user.name 'Updater CI'
        & git -C $other config user.email 'updater@example.invalid'
        Set-Content -LiteralPath (Join-Path $other 'new-version.txt') -Value 'latest'
        & git -C $other add new-version.txt 2>&1 | Out-Null
        & git -C $other commit -m 'new version' 2>&1 | Out-Null
        & git -C $other push origin main 2>&1 | Out-Null

        Set-Content -LiteralPath (Join-Path $client 'backup.local.json') -Value 'private config'
        $output = & (Join-Path $client 'Atualizar.cmd') 2>&1
        $LASTEXITCODE | Should -Be 0
        (Test-Path -LiteralPath (Join-Path $client 'new-version.txt')) | Should -BeTrue
        (Get-Content -LiteralPath (Join-Path $client 'backup.local.json') -Raw) | Should -Match 'private config'

        Set-Content -LiteralPath (Join-Path $client 'Backup.ps1') -Value '# user change'
        $output = & (Join-Path $client 'Atualizar.cmd') 2>&1
        $LASTEXITCODE | Should -Be 3
        ($output -join ' ') | Should -Match 'modificacoes locais'
        (Get-Content -LiteralPath (Join-Path $client 'Backup.ps1') -Raw) | Should -Match 'user change'
    }
}
