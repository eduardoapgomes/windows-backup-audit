BeforeAll {
    Import-Module "$PSScriptRoot/../src/Backup.Core.psm1" -Force

}
Describe 'Physical destination policy (synthetic disk metadata)' {
    BeforeEach {
        Mock Get-StorageIdentity -ModuleName Backup.Core {
            if ($Path -like 'C:*') { return @{DiskId='internal';VolumeId='c';BusType='NVMe';IsBoot=$true;IsSystem=$true;IsOffline=$false;IsReadOnly=$false;FileSystem='NTFS';FreeBytes=100GB;Drive='C:\'} }
            return @{DiskId='usb-1';VolumeId='volume-1';BusType='USB';IsBoot=$false;IsSystem=$false;IsOffline=$false;IsReadOnly=$false;FileSystem='NTFS';FreeBytes=100GB;Drive='E:\'}
        }
    }
    It 'accepts a USB disk distinct from source' {
        (Assert-ExternalDestination 'E:\Backup' @('C:\Data')).DiskId | Should -Be 'usb-1'
    }
    It 'blocks the system/internal disk' {
        { Assert-ExternalDestination 'C:\Backup' } | Should -Throw '*bloqueado*'
    }
    It 'blocks another partition of the source disk' {
        { Assert-ExternalDestination 'E:\Backup' @('F:\Data') } | Should -Throw '*mesmo disco*'
    }
    It 'blocks a changed volume on the same drive letter' {
        { Assert-ExternalDestination 'E:\Backup' @() @{DiskId='usb-1';VolumeId='other'} } | Should -Throw '*trocado*'
    }
    It 'blocks a readonly external disk' {
        Mock Get-StorageIdentity -ModuleName Backup.Core { @{DiskId='usb';VolumeId='v';BusType='USB';IsBoot=$false;IsSystem=$false;IsOffline=$false;IsReadOnly=$true} }
        { Assert-ExternalDestination 'E:\Backup' } | Should -Throw '*bloqueado*'
    }
    It 'blocks an unidentified disk' {
        Mock Get-StorageIdentity -ModuleName Backup.Core { @{DiskId='';VolumeId='v'} }
        { Assert-ExternalDestination 'E:\Backup' } | Should -Throw '*Identidade*'
    }
    It 'blocks unsupported filesystems without formatting' {
        Mock Get-StorageIdentity -ModuleName Backup.Core { @{DiskId='usb';VolumeId='v';BusType='USB';IsBoot=$false;IsSystem=$false;IsOffline=$false;IsReadOnly=$false;FileSystem='exFAT'} }
        { Assert-ExternalDestination 'E:\Backup' } | Should -Throw '*NTFS*'
    }
    It 'blocks ambiguity/read failures instead of falling back' {
        Mock Get-StorageIdentity -ModuleName Backup.Core { throw 'Cannot resolve disk' }
        { Assert-ExternalDestination 'E:\Backup' } | Should -Throw
    }
}
Describe 'Path protections' {
    It 'uses directory boundaries' {
        Test-PathWithin 'C:\data2\x' 'C:\data' | Should -BeFalse
        Test-PathWithin 'C:\data\x' 'C:\data' | Should -BeTrue
    }
    It 'rejects relative, UNC and alternate-stream paths' {
        { Assert-PlainPath '.\backup' } | Should -Throw
        { Assert-PlainPath '\\server\backup' } | Should -Throw
        { Assert-PlainPath 'C:\file:stream' } | Should -Throw
    }
    It 'rejects a junction in a destination ancestor' {
        $real = New-Item -ItemType Directory (Join-Path $TestDrive 'real')
        $link = Join-Path $TestDrive 'redirect'
        New-Item -ItemType Junction -Path $link -Target $real.FullName | Out-Null
        { Assert-PlainPath "$link\new\file.txt" } | Should -Throw '*redirecionado*'
    }
}
Describe 'File integration (temporary disk; physical guard mocked only here)' {
    BeforeEach {
        Mock Assert-ExternalDestination -ModuleName Backup.Core {
            @{DiskId='test';VolumeId='test';FreeBytes=100GB;Drive='Z:\'}
        }
        $source = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $dest = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $source,$dest | Out-Null
    }
    It 'does not write before destination rejection' {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { throw 'blocked' }
        $missing = Join-Path $TestDrive 'must-not-exist'
        { Invoke-BackupPlan @(@{Id='docs';Path=$source}) $missing Backup } | Should -Throw
        Test-Path $missing | Should -BeFalse
    }
    It 'rejects destination in source, empty plans and reserved identifiers' {
        { Invoke-BackupPlan @(@{Id='docs';Path=$source}) "$source\backup" } | Should -Throw
        { Invoke-BackupPlan @() $dest } | Should -Throw
        { Invoke-BackupPlan @(@{Id='_RELATORIOS';Path=$source}) $dest } | Should -Throw
        { Invoke-BackupPlan @(@{Id='CON';Path=$source}) $dest } | Should -Throw
    }
    It 'rejects duplicate identifiers' {
        { Invoke-BackupPlan @(@{Id='docs';Path=$source},@{Id='DOCS';Path=$source}) $dest } | Should -Throw
    }
    It 'audits by hash without copying and writes a review' {
        [IO.File]::WriteAllText("$source\a.txt", 'AAAA')
        $run = Invoke-BackupPlan @(@{Id='docs';Path=$source}) $dest Audit
        Test-Path "$dest\docs\a.txt" | Should -BeFalse
        $row = Import-Csv "$run\inventario.csv"
        $row.Status | Should -Be NEEDS_COPY
        $row.SHA256 | Should -Be (Get-BackupHash "$source\a.txt")
        Test-Path "$run\LEIA-ME.html" | Should -BeTrue
    }
    It 'reuses manually copied content under a different name and copies only missing data' {
        [IO.File]::WriteAllText("$source\a.txt", 'AAAA')
        [IO.File]::WriteAllText("$source\b.txt", 'BBBB')
        [IO.File]::WriteAllText("$dest\manual.txt", 'AAAA')
        $before = Get-BackupHash "$source\a.txt"
        $run = Invoke-BackupPlan @(@{Id='docs';Path=$source}) $dest Backup
        $rows = @(Import-Csv "$run\inventario.csv")
        ($rows | Where-Object Status -eq REUSED_EXISTING).Destination | Should -Be "$dest\manual.txt"
        Test-Path "$dest\docs\a.txt" | Should -BeFalse
        [IO.File]::ReadAllText("$dest\docs\b.txt") | Should -Be BBBB
        Get-BackupHash "$source\a.txt" | Should -Be $before
        @(Get-ChildItem $source -File).Count | Should -Be 2
        $again = Invoke-BackupPlan @(@{Id='docs';Path=$source}) $dest Backup
        @(Import-Csv "$again\inventario.csv" | Where-Object Status -eq VERIFIED).Count | Should -Be 0
    }
    It 'restores two logical paths from one reused object using the inventory' {
        [IO.File]::WriteAllText("$source\a.txt", 'shared')
        [IO.File]::WriteAllText("$source\b.txt", 'shared')
        [IO.File]::WriteAllText("$dest\manual.txt", 'shared')
        $run = Invoke-BackupPlan @(@{Id='docs';Path=$source}) $dest Backup
        $rows = @(Import-Csv "$run\inventario.csv")
        @($rows | Where-Object Status -eq REUSED_EXISTING).Count | Should -Be 2
        Test-Path "$dest\docs" | Should -BeFalse
        $restore = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $restore | Out-Null
        foreach ($row in $rows) {
            $path = Join-Path $restore $row.RelativePath
            Copy-Item -LiteralPath $row.Destination -Destination $path
            Get-BackupHash $path | Should -Be $row.SHA256
        }
        @(Get-ChildItem $restore -File).Count | Should -Be 2
    }
    It 'detects corruption and preserves prior content on replacement' {
        [IO.File]::WriteAllText("$source\a.txt", 'AAAA')
        Copy-VerifiedFile "$source\a.txt" "$dest\a.txt" "$dest\copy.log" | Should -Be VERIFIED
        Copy-VerifiedFile "$source\a.txt" "$dest\a.txt" "$dest\copy.log" | Should -Be SKIP_IDENTICAL
        $time = (Get-Item "$source\a.txt").LastWriteTimeUtc
        [IO.File]::WriteAllText("$source\a.txt", 'BBBB')
        (Get-Item "$source\a.txt").LastWriteTimeUtc = $time
        Copy-VerifiedFile "$source\a.txt" "$dest\a.txt" "$dest\copy.log" | Should -Be VERIFIED
        [IO.File]::ReadAllText("$dest\a.txt") | Should -Be BBBB
        $old = Get-ChildItem $dest -Force -Filter '.history-*'
        [IO.File]::ReadAllText($old.FullName) | Should -Be AAAA
    }
    It 'does not copy or replace on insufficient space' {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { @{DiskId='test';VolumeId='test';FreeBytes=0;Drive='Z:\'} }
        [IO.File]::WriteAllText("$source\a.txt", 'new')
        [IO.File]::WriteAllText("$dest\a.txt", 'old')
        { Copy-VerifiedFile "$source\a.txt" "$dest\a.txt" "$dest\copy.log" } | Should -Throw '*Espaço*'
        [IO.File]::ReadAllText("$dest\a.txt") | Should -Be old
    }
    It 'preserves old destination when verification fails' {
        [IO.File]::WriteAllText("$source\a.txt", 'new')
        [IO.File]::WriteAllText("$dest\a.txt", 'old')
        Mock Get-BackupHash -ModuleName Backup.Core { 'CORRUPT' } -ParameterFilter { $Path -like '*\.stage-*' }
        { Copy-VerifiedFile "$source\a.txt" "$dest\a.txt" "$dest\copy.log" } | Should -Throw '*verificação*'
        [IO.File]::ReadAllText("$dest\a.txt") | Should -Be old
    }
    It 'does not trust a stale candidate after it changes' {
        [IO.File]::WriteAllText("$dest\manual.txt", 'AAAA')
        $hash = Get-BackupHash "$dest\manual.txt"
        $index = Get-ExistingBackupIndex $dest
        [IO.File]::WriteAllText("$dest\manual.txt", 'BBBB')
        Find-ExistingContent $hash 4 $index | Should -BeNullOrEmpty
    }
    It 'rejects concurrent runs' {
        $lock = [IO.File]::Open("$dest\.backup.lock", 'OpenOrCreate','ReadWrite','None')
        try { { Invoke-BackupPlan @(@{Id='docs';Path=$source}) $dest } | Should -Throw }
        finally { $lock.Dispose() }
    }
}
Describe 'Dependencies and readable reports' {
    It 'requires Robocopy only for backup' {
        Mock Get-Command -ModuleName Backup.Core {
            if ($Name -eq 'robocopy.exe') { return $null }
            return @{Name=$Name}
        }
        { Assert-BackupDependencies Backup } | Should -Throw '*Robocopy*'
        { Assert-BackupDependencies Audit } | Should -Not -Throw
    }
    It 'escapes hostile paths and shows errors' {
        $run = Join-Path $TestDrive 'report'
        New-Item -ItemType Directory $run | Out-Null
        Write-BackupReview $run @(@{Id='docs';Path='C:\docs<script>'}) Audit 1
        Get-Content "$run\LEIA-ME.md" -Raw | Should -Match 'Erros registrados: \*\*1'
        Get-Content "$run\LEIA-ME.html" -Raw | Should -Not -Match '<script>'
    }
}
