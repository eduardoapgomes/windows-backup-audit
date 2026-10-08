[CmdletBinding()]
param([string]$Inventory, [switch]$Watch)
$ErrorActionPreference = 'Stop'
try {
    $python = Get-Command py.exe -ErrorAction SilentlyContinue
    $prefix = @('-3')
    if (-not $python) {
        $python = Get-Command python.exe -ErrorAction SilentlyContinue
        $prefix = @()
    }
    if (-not $python) { throw 'O painel precisa de Python 3.9 ou superior. O backup funciona sem Python. Consulte docs/ORGANIZATION.md.' }
    & $python.Source @prefix -c "import sys; sys.exit(0 if sys.version_info >= (3,9) else 1)"
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.9 ou superior não está disponível neste terminal. Consulte docs/ORGANIZATION.md.' }
    if ([string]::IsNullOrWhiteSpace($Inventory)) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object Windows.Forms.OpenFileDialog
        $dialog.Title = 'Selecione inventario.csv da auditoria ou backup (inclusive em andamento)'
        $dialog.Filter = 'Inventário CSV (*.csv)|*.csv'
        $dialog.CheckFileExists = $true
        try {
            if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit 0 }
            $Inventory = $dialog.FileName
        } finally { $dialog.Dispose() }
    }
    $resolved = (Resolve-Path -LiteralPath $Inventory).Path
    $arguments = @((Join-Path $PSScriptRoot 'tools\organize_inventory.py'), $resolved, '--open')
    if ($Watch) { $arguments += '--watch' }
    & $python.Source @prefix @arguments
    if ($LASTEXITCODE -ne 0) { throw 'O painel não foi gerado. Confira a mensagem acima; o backup não foi alterado.' }
} catch {
    Write-Error $_
    exit 1
}
