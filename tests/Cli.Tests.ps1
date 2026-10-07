BeforeAll {
    $entryPoint = Join-Path $PSScriptRoot '..\Backup.ps1'
}
Describe 'CLI configuration in a fresh Windows PowerShell process' {
    BeforeEach {
        $fixture = Join-Path $TestDrive ('project with spaces ' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory (Join-Path $fixture 'src') -Force | Out-Null
        Copy-Item -LiteralPath $entryPoint -Destination (Join-Path $fixture 'Backup.ps1')
        # Isolate config binding and CLI invocation; no physical disk or backup is touched.
        @'
function Assert-BackupDependencies { param($Mode) }
function New-BackupConfiguration { param($Path) Write-Output ('SETUP:' + $Path) }
function Get-AutomaticBackupPlan { [pscustomobject]@{Destination='';Sources=@(@{Id='AUTO';Path='C:\Personal'});Discovery=@();ExcludedPaths=@()} }
function Select-BackupDestination { param($Sources) 'E:\Chosen' }
function Invoke-BackupPlan {
    param($Sources, $Destination, $Mode, $Discovery, $ExcludedPaths, $Scope, [switch]$OpenReport)
    Write-Output ("PLAN:" + $Sources[0].Id + ":" + $Mode + ":" + $Destination)
}
Export-ModuleMember -Function *
'@ | Set-Content -LiteralPath (Join-Path $fixture 'src\Backup.Core.psm1') -Encoding UTF8
        '{"Destination":"","Sources":[{"Id":"DEFAULT","Path":"C:\\Data"}]}' |
            Set-Content -LiteralPath (Join-Path $fixture 'backup.local.json') -Encoding UTF8
    }
    It 'discovers automatically without a config and ignores a manual project-only config' {
        $output = & powershell.exe -NoProfile -STA -File "$fixture\Backup.ps1" -AutoDiscover -Mode Audit
        $LASTEXITCODE | Should -Be 0
        ($output -join '') | Should -Be 'PLAN:AUTO:Audit:E:\Chosen'
        Remove-Item -LiteralPath "$fixture\backup.local.json"
        $output = & powershell.exe -NoProfile -STA -File "$fixture\Backup.ps1" -AutoDiscover -Mode Audit
        $LASTEXITCODE | Should -Be 0
        ($output -join '') | Should -Be 'PLAN:AUTO:Audit:E:\Chosen'
    }
    It 'routes setup to the script-local configuration without starting a backup' {
        $output = & powershell.exe -NoProfile -STA -File "$fixture\Backup.ps1" -Setup
        $LASTEXITCODE | Should -Be 0
        ($output -join '') | Should -Be "SETUP:$fixture\backup.local.json"
    }
    It 'loads the default config beside the script with -File and -SelectDestination' {
        $output = & powershell.exe -NoProfile -STA -File "$fixture\Backup.ps1" -Mode Audit -SelectDestination
        $LASTEXITCODE | Should -Be 0
        ($output -join '') | Should -Be 'PLAN:DEFAULT:Audit:E:\Chosen'
    }
    It 'honors a relative explicit config without depending on the caller directory' {
        '{"Destination":"E:\\Custom","Sources":[{"Id":"CUSTOM","Path":"C:\\Data"}]}' |
            Set-Content -LiteralPath "$fixture\custom.json" -Encoding UTF8
        $output = & powershell.exe -NoProfile -STA -File "$fixture\Backup.ps1" -Mode Audit -Config custom.json
        $LASTEXITCODE | Should -Be 0
        ($output -join '') | Should -Be 'PLAN:CUSTOM:Audit:E:\Custom'
    }
    It 'exits with code 2 and an actionable path when config is missing' {
        Remove-Item -LiteralPath "$fixture\backup.local.json"
        $previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = & powershell.exe -NoProfile -STA -File "$fixture\Backup.ps1" -Mode Audit 2>&1
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previous }
        $code | Should -Be 2
        ($output -join '') | Should -Match 'backup.local.json'
        ($output -join '') | Should -Match 'Iniciar.cmd'
    }
}
