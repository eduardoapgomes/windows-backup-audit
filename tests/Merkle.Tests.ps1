BeforeAll { Import-Module "$PSScriptRoot/../src/Backup.Core.psm1" -Force }
Describe 'Size filtering and Merkle snapshots' {
    BeforeEach {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { @{DiskId='test';VolumeId='test';FreeBytes=100GB;Drive='Z:\'} }
        $source=New-Item -ItemType Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $dest=New-Item -ItemType Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
    }
    It 'does not hash destination files whose sizes never match a source' {
        [IO.File]::WriteAllText("$source\a.txt",'abc')
        [IO.File]::WriteAllText("$dest\unrelated.bin",'a different length')
        Mock Get-BackupHash -ModuleName Backup.Core { throw 'unrelated content must not be read' } -ParameterFilter { $Path -like '*unrelated.bin' }
        $run=Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Audit
        (Import-Csv "$run\inventario.csv").SHA256.Length | Should -Be 64
        $metrics=Get-Content "$run\metricas.json" -Raw | ConvertFrom-Json
        $metrics.DestinationIndexedFiles | Should -Be 1
        $metrics.DestinationHashCandidates | Should -Be 0
    }
    It 'copies and verifies unique tiny files instead of filtering them out' {
        [IO.File]::WriteAllText("$source\tiny.txt",'x')
        $run=Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Backup
        (Import-Csv "$run\inventario.csv").Status | Should -Be VERIFIED
        [IO.File]::ReadAllText("$dest\docs\tiny.txt") | Should -Be x
        Test-Path "$run\merkle.sha256" | Should -BeTrue
    }
    It 'avoids ambiguous concatenation in tree digests' {
        Get-MerkleDigest @('ab','c') | Should -Not -Be (Get-MerkleDigest @('a','bc'))
        Get-MerkleDigest @('a','b') | Should -Be (Get-MerkleDigest @('a','b'))
    }
    It 'compares identical snapshots at their root without trusting timestamps' {
        [IO.File]::WriteAllText("$source\a.txt",'AAAA')
        $first=Invoke-BackupPlan @(@{Id='d';Path=$source.FullName}) $dest.FullName Audit
        $second=Invoke-BackupPlan @(@{Id='d';Path=$source.FullName}) $dest.FullName Audit
        $a=Get-Content "$first\merkle.json" -Raw | ConvertFrom-Json
        $b=Get-Content "$second\merkle.json" -Raw | ConvertFrom-Json
        $a.ContentRoot | Should -Be $b.ContentRoot
        $b.CoverageComplete | Should -BeFalse
        $delta=@(Import-Csv "$second\merkle-delta.csv")
        $delta.Count | Should -Be 1
        $delta[0].Status | Should -Be SAME_OBSERVED_SUBTREE
        $delta[0].Path | Should -Be '@'
        $timestamp=(Get-Item "$source\a.txt").LastWriteTimeUtc
        [IO.File]::WriteAllText("$source\a.txt",'BBBB')
        (Get-Item "$source\a.txt").LastWriteTimeUtc=$timestamp
        $third=Invoke-BackupPlan @(@{Id='d';Path=$source.FullName}) $dest.FullName Audit
        (Get-Content "$third\merkle.json" -Raw | ConvertFrom-Json).ContentRoot | Should -Not -Be $a.ContentRoot
        @(Import-Csv "$third\merkle-delta.csv").Status | Should -Contain CONTENT_CHANGED
    }
    It 'keeps unknown hashes and optional omissions explicit' {
        [IO.File]::WriteAllText("$source\a.txt",'AAAA')
        Mock Get-BackupHash -ModuleName Backup.Core { throw 'source read failed' } -ParameterFilter { $Source }
        { Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Audit } | Should -Throw
        $run=(Get-ChildItem "$dest\_RELATORIOS" -Directory)[0].FullName
        $manifest=Get-Content "$run\merkle.json" -Raw | ConvertFrom-Json
        $manifest.ObservedHashesComplete | Should -BeFalse
        $manifest.Errors | Should -BeGreaterThan 0
    }
    It 'reports a corrupted previous manifest without trusting its tree' {
        [IO.File]::WriteAllText("$source\a.txt",'AAAA')
        $first=Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Audit
        Add-Content "$first\merkle.json" 'corrupt'
        $second=Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Audit
        (Import-Csv "$second\merkle-delta.csv").Status | Should -Be BASELINE_INVALID
    }
    It 'reports scope changes instead of claiming identical coverage' {
        [IO.File]::WriteAllText("$source\a.txt",'AAAA')
        $null=Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Audit -DependencyPolicy Include
        $second=Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Audit -DependencyPolicy Exclude
        (Import-Csv "$second\merkle-delta.csv").Status | Should -Be SCOPE_CHANGED
    }
    It 'rehashes a candidate after the size bucket was already resolved' {
        [IO.File]::WriteAllText("$dest\manual.txt",'AAAA')
        $hash=Get-BackupHash "$dest\manual.txt"
        $index=Get-ExistingBackupIndex $dest.FullName
        Find-ExistingContent $hash 4 $index | Should -Be "$dest\manual.txt"
        [IO.File]::WriteAllText("$dest\manual.txt",'BBBB')
        Find-ExistingContent $hash 4 $index | Should -BeNullOrEmpty
    }
}
