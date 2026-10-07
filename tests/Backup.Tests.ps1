BeforeAll {
    Import-Module "$PSScriptRoot/../src/Backup.Core.psm1" -Force
}
Describe 'Backup safety and identity' {
    It 'uses directory boundaries, not prefix matching' {
        Test-PathWithin 'C:\data2\x' 'C:\data' | Should -BeFalse
        Test-PathWithin 'C:\data\x' 'C:\data' | Should -BeTrue
    }
    It 'rejects a destination inside source' {
        $source = Join-Path $TestDrive 'source'
        New-Item -ItemType Directory $source | Out-Null
        { Invoke-BackupPlan @(@{Id='user';Path=$source}) "$source\backup" } | Should -Throw
    }
    It 'rejects duplicate destination identifiers' {
        { Invoke-BackupPlan @(@{Id='x';Path=$TestDrive},@{Id='x';Path=$TestDrive}) 'C:\unused' } | Should -Throw
    }
    It 'does not copy during audit' {
        $source = Join-Path $TestDrive 'audit-source'
        $dest = Join-Path $TestDrive 'audit-destination'
        New-Item -ItemType Directory $source | Out-Null
        'test' | Set-Content "$source\file.txt"
        Invoke-BackupPlan @(@{Id='user';Path=$source}) $dest Audit
        Test-Path "$dest\user\file.txt" | Should -BeFalse
    }
    It 'skips identical content and catches same-size changes' {
        $source = Join-Path $TestDrive 'copy-source'
        $dest = Join-Path $TestDrive 'copy-dest'
        New-Item -ItemType Directory $source,$dest | Out-Null
        [IO.File]::WriteAllText("$source\file.txt", 'AAAA')
        Copy-VerifiedFile "$source\file.txt" "$dest\file.txt" "$TestDrive\copy.log" | Should -Be VERIFIED
        Copy-VerifiedFile "$source\file.txt" "$dest\file.txt" "$TestDrive\copy.log" | Should -Be SKIP_IDENTICAL
        $time = (Get-Item "$source\file.txt").LastWriteTimeUtc
        [IO.File]::WriteAllText("$source\file.txt", 'BBBB')
        (Get-Item "$source\file.txt").LastWriteTimeUtc = $time
        Copy-VerifiedFile "$source\file.txt" "$dest\file.txt" "$TestDrive\copy.log" | Should -Be VERIFIED
        [IO.File]::ReadAllText("$dest\file.txt") | Should -Be 'BBBB'
        @(Get-ChildItem $dest -Force -Filter '.history-*').Count | Should -Be 1
    }
}
