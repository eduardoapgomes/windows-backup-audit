BeforeAll { Import-Module "$PSScriptRoot/../src/Backup.Core.psm1" -Force }
Describe 'Focused automatic discovery' {
    BeforeEach {
        Mock Get-PersonalFolderCandidates -ModuleName Backup.Core {
            @([pscustomobject]@{Path='C:\People\User\Documents';Kind='Documents'},
              [pscustomobject]@{Path='F:\Redirected';Kind='Redirected'})
        }
        Mock Get-Volume -ModuleName Backup.Core { @(@{DriveLetter='C'},@{DriveLetter='D'},@{DriveLetter='E'}) }
        Mock Get-StorageIdentity -ModuleName Backup.Core {
            @{BusType=$(if ($Path -like 'D:*') {'USB'} else {'NVMe'});IsOffline=$false}
        }
        Mock Assert-PlainPath -ModuleName Backup.Core {}
        Mock Test-Path -ModuleName Backup.Core {
            $LiteralPath -in @('C:\People\User\Documents','F:\Redirected','C:\Dados','E:\Projetos')
        }
    }
    It 'selects personal and data folders, never whole disks or the Users tree' {
        $plan=Get-AutomaticBackupPlan
        @($plan.Sources).Count | Should -Be 4
        $plan.Sources.Path | Should -Contain 'C:\Dados'
        $plan.Sources.Path | Should -Contain 'E:\Projetos'
        $plan.Sources.Path | Should -Contain 'F:\Redirected'
        $plan.Sources.Path | Should -Contain 'C:\People\User\Documents'
        $plan.Sources.Path | Should -Not -Contain 'C:\'
        $plan.Sources.Path | Should -Not -Contain 'E:\'
        $plan.Sources.Path | Should -Not -Contain 'C:\Users'
        $plan.Sources.Path | Should -Not -Contain 'D:\'
        @($plan.Discovery | Where-Object Status -eq REVIEW).Path | Should -Contain 'C:\'
        @($plan.Discovery | Where-Object Status -eq REVIEW).Path | Should -Contain 'E:\'
        @($plan.Discovery | Where-Object Status -eq EXCLUDED).Path | Should -Contain 'D:\'
        @($plan.ExcludedPaths).Count | Should -Be 0
    }
    It 'keeps source identifiers stable across discovery order changes' {
        $first=Get-AutomaticBackupPlan
        $second=Get-AutomaticBackupPlan
        ($first.Sources.Id -join ',') | Should -Be ($second.Sources.Id -join ',')
    }
    It 'records absent optional folders without claiming coverage' {
        Mock Test-Path -ModuleName Backup.Core { $false } -ParameterFilter { $LiteralPath -eq 'F:\Redirected' }
        $plan=Get-AutomaticBackupPlan
        @($plan.Discovery | Where-Object Status -eq NOT_FOUND).Path | Should -Contain 'F:\Redirected'
        $plan.Sources.Path | Should -Not -Contain 'F:\Redirected'
    }
    It 'records disk identity failures instead of guessing eligibility' {
        Mock Get-StorageIdentity -ModuleName Backup.Core { throw 'unknown disk' } -ParameterFilter { $Path -like 'E:*' }
        $plan=Get-AutomaticBackupPlan
        $plan.Sources.Path | Should -Not -Contain 'E:\Projetos'
        @($plan.Discovery | Where-Object Status -eq ERROR).Count | Should -Be 1
    }
    It 'fails closed when no data folder is found' {
        Mock Get-PersonalFolderCandidates -ModuleName Backup.Core { @() }
        Mock Test-Path -ModuleName Backup.Core { $false }
        { Get-AutomaticBackupPlan } | Should -Throw '*Nenhuma pasta de dados*'
    }
}

Describe 'Fast audit for new files' {
    It 'does not hash unmatched new source files and marks the Merkle observation unverified' {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { @{DiskId='test';VolumeId='test';FreeBytes=100GB;Drive='Z:\'} }
        $source=New-Item -ItemType Directory (Join-Path $TestDrive 'quick-source')
        $dest=New-Item -ItemType Directory (Join-Path $TestDrive 'quick-dest')
        $file=Join-Path $source.FullName 'new.txt'
        [IO.File]::WriteAllText($file,'important new data')
        Mock Get-BackupHash -ModuleName Backup.Core { throw 'new source should not be hashed in quick audit' } -ParameterFilter { $Path -eq $file }
        $run=Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Audit -QuickAudit -DependencyPolicy Exclude
        $row=Import-Csv (Join-Path $run 'inventario.csv')
        $row.Status | Should -Be NEEDS_COPY
        $row.SHA256 | Should -BeNullOrEmpty
        (Get-Content (Join-Path $run 'merkle.json') -Raw | ConvertFrom-Json).ObservedHashesComplete | Should -BeFalse
        (Get-Content (Join-Path $run 'metricas.json') -Raw | ConvertFrom-Json).QuickAuditUnhashed | Should -Be 1
    }
    It 'still hashes and matches existing same-size content' {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { @{DiskId='test';VolumeId='test';FreeBytes=100GB;Drive='Z:\'} }
        $source=New-Item -ItemType Directory (Join-Path $TestDrive 'matched-source')
        $dest=New-Item -ItemType Directory (Join-Path $TestDrive 'matched-dest')
        [IO.File]::WriteAllText((Join-Path $source.FullName 'new.txt'),'same bytes')
        [IO.File]::WriteAllText((Join-Path $dest.FullName 'old.txt'),'same bytes')
        $run=Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Audit -QuickAudit -DependencyPolicy Exclude
        $row=Import-Csv (Join-Path $run 'inventario.csv')
        $row.Status | Should -Be REUSED_EXISTING
        $row.SHA256 | Should -Match '^[A-F0-9]{64}$'
    }
}

Describe 'Resilient enumeration and chunked progress' {
    It 'continues past a rejected junction and honors explicit exclusions' {
        $root=New-Item -ItemType Directory (Join-Path $TestDrive 'tree')
        $outside=New-Item -ItemType Directory (Join-Path $TestDrive 'outside')
        $excluded=New-Item -ItemType Directory (Join-Path $root 'excluded')
        [IO.File]::WriteAllText("$root\keep.txt",'keep')
        [IO.File]::WriteAllText("$excluded\skip.txt",'skip')
        [IO.File]::WriteAllText("$outside\not-followed.txt",'external')
        New-Item -ItemType Junction -Path "$root\link" -Target $outside.FullName | Out-Null
        $issues=New-Object 'Collections.Generic.List[object]'
        $files=@(Get-BackupFiles $root.FullName -ExcludedPaths @($excluded.FullName) -Issues $issues)
        $files.Count | Should -Be 1
        $files[0].Name | Should -Be 'keep.txt'
        $issues.Count | Should -Be 1
        $issues[0].Path | Should -Be "$root\link"
        { Get-BackupFiles $root.FullName -ExistingBackup } | Should -Throw
    }
    It 'matches standard SHA256 for empty and multi-chunk files and emits progress without contaminating output' {
        Mock Show-BackupProgress -ModuleName Backup.Core {}
        $path=Join-Path $TestDrive 'large.bin'
        [IO.File]::WriteAllBytes($path,(New-Object byte[] (9MB)))
        Get-BackupHash $path | Should -Be (Get-FileHash $path -Algorithm SHA256).Hash
        Should -Invoke Show-BackupProgress -ModuleName Backup.Core -ParameterFilter { $ReadBytes -eq 4MB -and $TotalBytes -eq 9MB } -Times 1 -Exactly
        [IO.File]::WriteAllBytes($path,(New-Object byte[] 0))
        Get-BackupHash $path | Should -Be (Get-FileHash $path -Algorithm SHA256).Hash
    }
    It 'writes progress only to host/progress streams' {
        Mock Write-Progress -ModuleName Backup.Core {}
        Mock Write-Host -ModuleName Backup.Core {}
        $result=@(Start-BackupProgress Audit; Show-BackupProgress -Phase 'Hash' -Path 'C:\file' -ReadBytes 1 -TotalBytes 2; Stop-BackupProgress)
        $result.Count | Should -Be 0
        Should -Invoke Write-Progress -ModuleName Backup.Core -Times 2 -Exactly
    }
    It 'saves enumeration failures and still audits accessible sibling files' {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { @{DiskId='test';VolumeId='test';FreeBytes=100GB;Drive='Z:\'} }
        $source=New-Item -ItemType Directory (Join-Path $TestDrive 'partial-source')
        $dest=New-Item -ItemType Directory (Join-Path $TestDrive 'partial-dest')
        $outside=New-Item -ItemType Directory (Join-Path $TestDrive 'partial-outside')
        New-Item -ItemType Junction -Path "$source\link" -Target $outside.FullName | Out-Null
        [IO.File]::WriteAllText("$source\good.txt",'data')
        { Invoke-BackupPlan @(@{Id='docs';Path=$source.FullName}) $dest.FullName Audit } | Should -Throw '*erro*'
        $run=(Get-ChildItem "$dest\_RELATORIOS" -Directory)[0].FullName
        (Import-Csv "$run\inventario.csv").Status | Should -Be NEEDS_COPY
        @(Import-Csv "$run\falhas-enumeracao.csv").Count | Should -Be 1
        (Get-Content "$run\LEIA-ME.html" -Raw) | Should -Match 'INCOMPLETO'
    }
}
Describe 'Readable HTML report' {
    It 'renders real tables, coverage, large files and escaped paths without a raw Markdown block' {
        $run=New-Item -ItemType Directory (Join-Path $TestDrive 'html')
        @([pscustomobject]@{RootId='docs';Source='C:\Docs\<script>.txt';Bytes=2048;Status='NEEDS_COPY';Error=''},
          [pscustomobject]@{RootId='docs';Source='C:\Docs\cloud.txt';Bytes=1024;Status='ERROR';Error='Offline <img>'}) |
            Export-Csv "$run\inventario.csv" -NoTypeInformation -Encoding UTF8
        [pscustomobject]@{Path='C:\AppData';Status='EXCLUDED';Reason='App data'} |
            Export-Csv "$run\cobertura.csv" -NoTypeInformation -Encoding UTF8
        Write-BackupReview $run.FullName @(@{Id='docs';Path='C:\Docs'}) Audit 1
        $html=Get-Content "$run\LEIA-ME.html" -Raw
        $html | Should -Match '<table>'
        $html | Should -Match '<td>2</td>'
        $html | Should -Match 'Maiores arquivos'
        $html | Should -Match 'C:\\AppData'
        $html | Should -Match '&lt;script&gt;'
        $html | Should -Not -Match '<script>|<pre>|\*\*Audit\*\*'
    }
}

Describe 'Partial reports' {
    It 'saves live counters with an explicit partial status and then links to the final report' {
        $run=New-Item -ItemType Directory (Join-Path $TestDrive 'partial-live')
        InModuleScope Backup.Core -Parameters @{RunPath=$run.FullName} {
            param($RunPath)
            Mock Assert-ExternalDestination { @{DiskId='test';VolumeId='test'} }
            Start-BackupProgress Audit
            try {
                $script:BackupProgress.Run=$RunPath
                $script:BackupProgress.Identity=@{DiskId='test';VolumeId='test'}
                $script:BackupProgress.SourcePaths=@('C:\')
                $script:BackupProgress.AuditFiles=12
                $script:BackupProgress.AuditBytes=1024
                $script:BackupProgress.Results=@{NEEDS_COPY=12}
                Write-BackupPartial -Phase 'Hash' -Path 'C:\<script>.bin' -ReadBytes 4MB -TotalBytes 9MB
                $json=Get-Content "$RunPath\andamento.json" -Raw | ConvertFrom-Json
                $json.InventoriedFiles | Should -Be 12
                $json.ReadBytes | Should -Be 4MB
                $json.Status | Should -Match '^PARCIAL'
                $html=Get-Content "$RunPath\ANDAMENTO.html" -Raw
                $html | Should -Match 'content="10"'
                $html | Should -Not -Match '<script>'
                Write-BackupPartial -Phase 'Encerrado' -Finished
                Get-Content "$RunPath\ANDAMENTO.html" -Raw | Should -Match 'url=LEIA-ME.html'
            } finally { Stop-BackupProgress }
        }
    }
}
