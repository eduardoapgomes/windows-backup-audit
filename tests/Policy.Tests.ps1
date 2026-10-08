BeforeAll { Import-Module "$PSScriptRoot/../src/Backup.Core.psm1" -Force }
Describe 'Hierarchical dependency policy' {
    BeforeEach {
        $project=New-Item -ItemType Directory (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $libraries=New-Item -ItemType Directory (Join-Path $project.FullName 'node_modules\package') -Force
        [IO.File]::WriteAllText("$project\package.json",'{"dependencies":{}}')
        [IO.File]::WriteAllText("$project\package-lock.json",'{}')
        [IO.File]::WriteAllText("$project\work.ipynb",'important notebook')
        [IO.File]::WriteAllText("$libraries\library.js",'reinstallable')
        $decisions=New-Object 'Collections.Generic.List[object]'
    }
    It 'does not descend into confirmed libraries and preserves notebook and manifests' {
        Mock Get-ChildItem -ModuleName Backup.Core { throw 'must not enumerate dependency contents' } -ParameterFilter { $LiteralPath -like '*\node_modules*' }
        $files=@(Get-BackupFiles $project.FullName -DependencyPolicy Auto -Dependencies $decisions)
        $files.Name | Should -Contain work.ipynb
        $files.Name | Should -Contain package-lock.json
        $files.Name | Should -Not -Contain library.js
        $decisions.Count | Should -Be 1
        $decisions[0].EstimatedBytes | Should -BeNullOrEmpty
        $decisions[0].Decision | Should -Be DEFERRED
    }
    It 'requires evidence, and Include explicitly disables dependency skipping' {
        Remove-Item "$project\package.json"
        @(Get-BackupFiles $project.FullName -DependencyPolicy Auto -Dependencies $decisions).Name | Should -Contain library.js
        $decisions.Count | Should -Be 0
        [IO.File]::WriteAllText("$project\package.json",'{}')
        @(Get-BackupFiles $project.FullName -DependencyPolicy Include).Name | Should -Contain library.js
    }
    It 'handles environments inside projects without discarding adjacent user work or Conda metadata' {
        $envRoot=New-Item -ItemType Directory "$project\environment\Lib\site-packages\pkg" -Force
        [IO.File]::WriteAllText("$project\environment\pyvenv.cfg",'home = C:\Python')
        [IO.File]::WriteAllText("$project\environment\results.csv",'data')
        [IO.File]::WriteAllText("$envRoot\module.py",'module')
        $files=@(Get-BackupFiles $project.FullName -DependencyPolicy Auto -Dependencies $decisions)
        $files.Name | Should -Contain results.csv
        $files.Name | Should -Contain pyvenv.cfg
        $files.Name | Should -Not -Contain module.py
        Remove-Item "$project\environment\pyvenv.cfg"
        New-Item -ItemType Directory "$project\environment\conda-meta" | Out-Null
        [IO.File]::WriteAllText("$project\environment\conda-meta\history",'conda history')
        @(Get-BackupFiles $project.FullName -DependencyPolicy Auto -Dependencies $decisions).Name | Should -Contain history
    }
    It 'blocks a dependency junction instead of treating it as a safe excluded folder' {
        Remove-Item "$project\node_modules" -Recurse -Force
        $other=New-Item -ItemType Directory (Join-Path $TestDrive 'junction-target')
        New-Item -ItemType Junction "$project\node_modules" -Target $other.FullName | Out-Null
        { Get-BackupFiles $project.FullName -DependencyPolicy Auto -Dependencies $decisions } | Should -Throw '*redirecionado*'
    }
    It 'audits essentials without reading dependency source or destination contents' {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { @{DiskId='test';VolumeId='test';FreeBytes=100GB;Drive='Z:\'} }
        Mock Get-BackupHash -ModuleName Backup.Core { throw 'must not hash dependencies' } -ParameterFilter { $Path -like '*\node_modules\*' }
        $dest=New-Item -ItemType Directory (Join-Path $TestDrive 'audit-destination')
        New-Item -ItemType Directory "$dest\manual\node_modules\pkg" -Force | Out-Null
        [IO.File]::WriteAllText("$dest\manual\package.json",'{}')
        [IO.File]::WriteAllText("$dest\manual\node_modules\pkg\library.js",'reinstallable')
        $run=Invoke-BackupPlan @(@{Id='project';Path=$project.FullName}) $dest.FullName Audit
        @(Import-Csv "$run\inventario.csv").Count | Should -Be 3
        @(Import-Csv "$run\dependencias.csv").Count | Should -Be 1
        @(Import-Csv "$run\indice-excluido.csv").Count | Should -Be 1
    }
    It 'copies essential data before optional libraries when space permits' {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { @{DiskId='test';VolumeId='test';FreeBytes=100GB;Drive='Z:\'} }
        $dest=New-Item -ItemType Directory (Join-Path $TestDrive 'backup-destination')
        $run=Invoke-BackupPlan @(@{Id='project';Path=$project.FullName}) $dest.FullName Backup
        $rows=@(Import-Csv "$run\inventario.csv")
        $rows[-1].Priority | Should -Be OPTIONAL_DEPENDENCY
        [IO.File]::ReadAllText("$dest\project\work.ipynb") | Should -Be 'important notebook'
        [IO.File]::ReadAllText("$dest\project\node_modules\package\library.js") | Should -Be 'reinstallable'
        (Import-Csv "$run\dependencias.csv").Decision | Should -Be OPTIONAL_VERIFIED
    }
    It 'records optional space omission but still copies essential data' {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { @{DiskId='test';VolumeId='test';FreeBytes=64MB;Drive='Z:\'} }
        $dest=New-Item -ItemType Directory (Join-Path $TestDrive 'low-space-destination')
        $run=Invoke-BackupPlan @(@{Id='project';Path=$project.FullName}) $dest.FullName Backup
        Test-Path "$dest\project\work.ipynb" | Should -BeTrue
        Test-Path "$dest\project\node_modules" | Should -BeFalse
        (Import-Csv "$run\dependencias.csv").Decision | Should -Be NOT_COPIED_SPACE
    }
    It 'does not copy optional libraries when essential data has failed' {
        Mock Assert-ExternalDestination -ModuleName Backup.Core { @{DiskId='test';VolumeId='test';FreeBytes=100GB;Drive='Z:\'} }
        Mock Get-BackupHash -ModuleName Backup.Core { throw 'essential read failed' } -ParameterFilter { $Path -like '*work.ipynb' }
        $dest=New-Item -ItemType Directory (Join-Path $TestDrive 'error-destination')
        { Invoke-BackupPlan @(@{Id='project';Path=$project.FullName}) $dest.FullName Backup } | Should -Throw '*erro*'
        Test-Path "$dest\project\node_modules" | Should -BeFalse
        $run=(Get-ChildItem "$dest\_RELATORIOS" -Directory)[0].FullName
        (Import-Csv "$run\dependencias.csv").Decision | Should -Be NOT_COPIED_ESSENTIAL_OR_PREVIOUS_ERRORS
    }
}
