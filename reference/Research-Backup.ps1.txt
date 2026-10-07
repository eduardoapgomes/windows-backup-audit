#Requires -Version 5.1

<#
.SYNOPSIS
    Backup e auditoria pré-formatação para Windows.

.PRINCIPIOS
    - Não usa Robocopy /MIR.
    - Não apaga arquivos da origem.
    - Não apaga arquivos antigos do destino.
    - Deduplicação: origem canônica + caminho relativo + tamanho + SHA256.
    - Verificação pós-cópia por SHA256.
    - Evita copiar duas vezes o mesmo arquivo quando raízes se sobrepõem.
    - Gera inventários CSV, logs Robocopy, transcript e manifesto SHA256.
    - Audita todos os discos fixos configurados.
    - Trata WSL, Docker, Hyper-V, VMware, VirtualBox, certificados e apps.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("Incremental", "Full")]
    [string]$Mode = "Incremental",

    [Parameter()]
    [string]$BackupRoot = "E:\BACKUP_WINDOWS"
)

# ============================================================
# PRIMEIRO COMANDO EXECUTÁVEL
# Padroniza o diretório de trabalho para a pasta do script.
# ============================================================

cd $PSScriptRoot

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Continue"

# ============================================================
# CONFIGURAÇÃO MÍNIMA
# ============================================================

# Discos que serão auditados mesmo que não sejam detectados
# automaticamente. Exemplos: @("C:", "D:", "F:")
$IncludeDrives = @("C:")

# Detectar automaticamente todos os discos fixos locais.
$AutoIncludeOtherFixedDrives = $true

# Se true, além de auditar os discos adicionais, copia o disco
# inteiro para 09_DISCOS. Deixe false normalmente.
$BackupEntireAdditionalDrives = $false

# Auditoria profunda de todos os arquivos acessíveis.
$DeepAudit = $true

# Gera inventário de TODOS os arquivos acessíveis nos discos auditados.
# Pode ficar muito grande e demorar bastante.
$WriteFullDiskInventory = $true

# Arquivos "importantes" encontrados fora das áreas já cobertas
# poderão ser copiados automaticamente para 08_DESCOBERTOS.
$CopyDiscoveredImportantFiles = $true

# Arquivos maiores que este valor aparecem em arquivos_grandes.csv.
$LargeFileThresholdGB = 0.5

# Hash de todos os arquivos finais do repositório.
# Full sempre fará isto, mesmo que fique false.
$GenerateFullHashManifest = $true

# Tenta baixar/materializar arquivos OneDrive online-only por leitura.
# False = marca no inventário, mas não força download.
$HydrateCloudFiles = $true

# Perfis podem conter mensagens, sessões e outros dados sensíveis.
$IncludeSensitiveAppProfiles = $true

# Recursos especiais.
$BackupWSL = $true
$BackupDockerVolumes = $true
$ExportHyperV = $true

# Não puxa imagem Docker da Internet sem autorização explícita.
$DockerHelperImage = "alpine:3.20"
$AllowDockerImagePull = $false

# Chaves privadas de certificados NÃO são exportadas por padrão.
$ExportPrivateCertificates = $false

# Se true, aborta caso o destino local não esteja protegido por BitLocker.
$RequireEncryptedDestination = $false

# Se true e destino for NTFS local, restringe ACL da raiz do backup
# para usuário atual + Administradores.
$HardenBackupAcl = $false

# Preservar ACL NTFS da origem reduz portabilidade.
# False => /COPY:DAT
# True  => /COPY:DATS
$PreserveAcls = $false

# Operações que podem parar workloads ficam opt-in.
# Atualmente usado para WSL antes da exportação.
$QuiesceWorkloads = $false

# Robocopy.
$RobocopyThreads = 8
$RobocopyRetry = 2
$RobocopyWaitSeconds = 2
$RobocopyBatchSize = 64

# Exclusões de auditoria/cópia.
# Não inclua aqui diretórios pessoais importantes sem revisar.
$ExcludePatterns = @(
    "*\System Volume Information\*",
    '*\$RECYCLE.BIN\*',
    "*\Windows\Temp\*",
    "*\AppData\Local\Temp\*",
    "*\Temp\*",
    "*\node_modules\*",
    "*\.cache\*",
    "*\__pycache__\*"
)

# Extensões que merecem atenção na auditoria profunda.
$ImportantExtensions = @(
    # Escritório / documentos
    ".doc", ".docx", ".xls", ".xlsx", ".xlsm",
    ".ppt", ".pptx", ".pdf", ".rtf", ".odt", ".ods",
    ".txt", ".md", ".tex", ".bib",

    # Imagens / conteúdo pessoal
    ".jpg", ".jpeg", ".png", ".tif", ".tiff", ".heic",
    ".raw", ".cr2", ".nef", ".arw",

    # Código / projetos
    ".py", ".ipynb", ".ps1", ".psm1", ".bat", ".cmd",
    ".sh", ".zsh", ".js", ".ts", ".tsx", ".jsx",
    ".java", ".c", ".cpp", ".h", ".hpp", ".cs", ".go",
    ".rs", ".php", ".rb", ".html", ".css", ".scss",
    ".json", ".yaml", ".yml", ".toml", ".xml",

    # Bancos
    ".db", ".sqlite", ".sqlite3", ".mdb", ".accdb",
    ".mdf", ".ndf", ".ldf", ".bak", ".sql", ".dump",

    # E-mail
    ".pst", ".ost", ".mbox", ".eml",

    # Segurança / certificados / vaults
    ".pfx", ".p12", ".pem", ".cer", ".crt",
    ".key", ".ppk", ".kdbx",

    # Arquivos compactados
    ".zip", ".7z", ".rar", ".tar", ".gz",

    # VMs / discos virtuais
    ".vhd", ".vhdx", ".vmdk", ".vdi", ".qcow2"
)

# Somente estes tipos descobertos são copiados automaticamente.
# VHD/VMDK etc. ficam inventariados, pois VMs são tratadas separadamente.
$AutoCopyDiscoveredExtensions = @(
    ".doc", ".docx", ".xls", ".xlsx", ".xlsm",
    ".ppt", ".pptx", ".pdf", ".rtf", ".odt",
    ".txt", ".md", ".tex", ".bib",
    ".jpg", ".jpeg", ".png", ".tif", ".tiff",
    ".heic", ".raw", ".cr2", ".nef", ".arw",
    ".py", ".ipynb", ".ps1", ".psm1", ".bat",
    ".cmd", ".sh", ".js", ".ts", ".tsx", ".jsx",
    ".java", ".c", ".cpp", ".h", ".hpp", ".cs",
    ".go", ".rs", ".php",
    ".db", ".sqlite", ".sqlite3", ".mdb", ".accdb",
    ".bak", ".sql", ".dump",
    ".pst", ".mbox", ".eml",
    ".pfx", ".p12", ".pem", ".cer", ".crt",
    ".key", ".ppk", ".kdbx"
)

# ============================================================
# ESTADO DA EXECUÇÃO
# ============================================================

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$StartTime = Get-Date

$Computer = $env:COMPUTERNAME
$User = $env:USERNAME
$UserProfile = $env:USERPROFILE

$RepoRoot = Join-Path $BackupRoot "$Computer-$User"

$UserRoot       = Join-Path $RepoRoot "01_USUARIO"
$OneDriveRoot   = Join-Path $RepoRoot "02_ONEDRIVE"
$ProjectsRoot   = Join-Path $RepoRoot "03_PROJETOS"
$AppsRoot       = Join-Path $RepoRoot "04_APPS"
$SpecialRoot    = Join-Path $RepoRoot "05_WSL_DOCKER"
$VmRoot         = Join-Path $RepoRoot "06_VMS"
$CertRoot       = Join-Path $RepoRoot "07_CERTIFICADOS"
$DiscoveredRoot = Join-Path $RepoRoot "08_DESCOBERTOS"
$ExtraDisksRoot = Join-Path $RepoRoot "09_DISCOS"

$InventoryRoot = Join-Path $RepoRoot "_INVENTARIO"
$LogsRoot      = Join-Path $RepoRoot "_LOGS"
$StateRoot     = Join-Path $RepoRoot "_STATE"
$TempRoot      = Join-Path $RepoRoot "_TEMP"

$AllTopFolders = @(
    $UserRoot, $OneDriveRoot, $ProjectsRoot, $AppsRoot,
    $SpecialRoot, $VmRoot, $CertRoot, $DiscoveredRoot,
    $ExtraDisksRoot, $InventoryRoot, $LogsRoot, $StateRoot,
    $TempRoot
)

foreach ($Folder in $AllTopFolders) {
    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
}

$TranscriptPath = Join-Path $LogsRoot "transcript_$RunId.log"
$GeneralLogPath = Join-Path $LogsRoot "backup_$RunId.log"
$RobocopyLogPath = Join-Path $LogsRoot "robocopy_$RunId.log"

$InventoryCsv = Join-Path $InventoryRoot "inventario_backup_$RunId.csv"
$TransferCsv = Join-Path $InventoryRoot "transferencias_$RunId.csv"
$ErrorCsv = Join-Path $LogsRoot "erros_$RunId.csv"
$ArtifactCsv = Join-Path $InventoryRoot "artefatos_$RunId.csv"
$DiskInventoryCsv = Join-Path $InventoryRoot "inventario_discos_$RunId.csv"
$ImportantAuditCsv = Join-Path $InventoryRoot "auditoria_importantes_$RunId.csv"
$LargeFilesCsv = Join-Path $InventoryRoot "arquivos_grandes_$RunId.csv"
$FinalHashCsv = Join-Path $InventoryRoot "hashes_sha256_$RunId.csv"

$script:Errors = New-Object System.Collections.ArrayList
$script:ProcessedSources = New-Object 'System.Collections.Generic.HashSet[string]'
$script:ManagedRoots = New-Object System.Collections.ArrayList
$script:Buckets = @{}

$script:Stats = @{
    Examined        = 0
    Copied          = 0
    Verified        = 0
    SkippedSame     = 0
    DuplicateSource = 0
    HashErrors      = 0
    CopyErrors      = 0
    CloudOnly       = 0
    Discovered      = 0
    LargeFiles      = 0
    Artifacts       = 0
}

# ============================================================
# FUNÇÕES DE LOG E CSV
# ============================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "OK")]
        [string]$Level = "INFO"
    )

    $Line = "{0:u} [{1}] {2}" -f (Get-Date), $Level, $Message
    Write-Host $Line

    try {
        Add-Content -LiteralPath $GeneralLogPath -Value $Line -Encoding UTF8
    } catch {}
}

function Add-ErrorRecord {
    param(
        [string]$Context,
        [string]$Path,
        [string]$Message,
        [bool]$Critical = $false
    )

    $Record = [PSCustomObject]@{
        TimeUtc  = (Get-Date).ToUniversalTime().ToString("o")
        Context  = $Context
        Path     = $Path
        Message  = $Message
        Critical = $Critical
    }

    [void]$script:Errors.Add($Record)

    if ($Critical) {
        Write-Log "$Context :: $Path :: $Message" "ERROR"
    } else {
        Write-Log "$Context :: $Path :: $Message" "WARN"
    }
}

function Escape-CsvField {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    $Text = [string]$Value
    return '"' + $Text.Replace('"', '""') + '"'
}

function Open-CsvWriter {
    param(
        [string]$Path,
        [string[]]$Headers
    )

    $Parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null

    $Encoding = New-Object System.Text.UTF8Encoding($true)
    $Writer = New-Object System.IO.StreamWriter($Path, $false, $Encoding)

    $HeaderLine = ($Headers | ForEach-Object {
        Escape-CsvField $_
    }) -join ","

    $Writer.WriteLine($HeaderLine)
    $Writer.Flush()

    return $Writer
}

function Write-CsvRow {
    param(
        [System.IO.StreamWriter]$Writer,
        [object[]]$Values
    )

    $Line = ($Values | ForEach-Object {
        Escape-CsvField $_
    }) -join ","

    $Writer.WriteLine($Line)
}

# ============================================================
# WRITERS
# ============================================================

$InventoryWriter = Open-CsvWriter $InventoryCsv @(
    "RunId", "Mode", "Category", "RootId",
    "SourcePath", "RelativePath", "DestinationPath",
    "SizeBytes", "LastWriteTimeUtc", "LastAccessTimeUtc",
    "Extension", "SHA256", "PriorityScore", "Priority",
    "Sensitivity", "Status", "Note"
)

$TransferWriter = Open-CsvWriter $TransferCsv @(
    "RunId", "SourcePath", "DestinationPath",
    "SizeBytes", "SourceSHA256", "DestinationSHA256",
    "RobocopyExitCode", "Status", "TimeUtc"
)

$ArtifactWriter = Open-CsvWriter $ArtifactCsv @(
    "RunId", "Type", "Name", "DestinationPath",
    "SizeBytes", "SHA256", "Status", "TimeUtc"
)

if ($WriteFullDiskInventory) {
    $DiskInventoryWriter = Open-CsvWriter $DiskInventoryCsv @(
        "RunId", "Drive", "FullName", "SizeBytes",
        "Extension", "LastWriteTimeUtc", "LastAccessTimeUtc"
    )
} else {
    $DiskInventoryWriter = $null
}

$ImportantWriter = Open-CsvWriter $ImportantAuditCsv @(
    "RunId", "Drive", "FullName", "SizeBytes", "Extension",
    "LastWriteTimeUtc", "PriorityScore", "Priority",
    "Sensitivity", "AlreadyCovered"
)

$LargeWriter = Open-CsvWriter $LargeFilesCsv @(
    "RunId", "Drive", "FullName", "SizeBytes",
    "SizeGB", "Extension", "LastWriteTimeUtc",
    "AlreadyCovered"
)

# ============================================================
# FUNÇÕES DE PATH / EXCLUSÃO
# ============================================================

function Get-NormalizedPath {
    param([string]$Path)

    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
    } catch {
        return $Path.TrimEnd("\")
    }
}

$RepoRootNormalized = (Get-NormalizedPath $RepoRoot).ToLowerInvariant()

function Test-ExcludedPath {
    param([string]$Path)

    $Normalized = (Get-NormalizedPath $Path).ToLowerInvariant()

    if ($Normalized -eq $RepoRootNormalized -or
        $Normalized.StartsWith($RepoRootNormalized + "\")) {
        return $true
    }

    foreach ($Pattern in $ExcludePatterns) {
        if ($Path -like $Pattern) {
            return $true
        }
    }

    return $false
}

function Get-RelativePathSafe {
    param(
        [string]$Root,
        [string]$Path
    )

    $RootFull = (Get-NormalizedPath $Root).TrimEnd("\") + "\"
    $PathFull = Get-NormalizedPath $Path

    if (-not $PathFull.StartsWith(
        $RootFull,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Path '$PathFull' não pertence a '$RootFull'."
    }

    return $PathFull.Substring($RootFull.Length)
}

# ============================================================
# ENUMERAÇÃO SEGURA
# Não segue junctions/symlinks de DIRETÓRIO.
# ============================================================

function Get-SafeFiles {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return
    }

    $Stack = New-Object 'System.Collections.Generic.Stack[string]'
    $Stack.Push((Get-NormalizedPath $Root))

    while ($Stack.Count -gt 0) {

        $Current = $Stack.Pop()

        if (Test-ExcludedPath $Current) {
            continue
        }

        try {
            $Items = Get-ChildItem `
                -LiteralPath $Current `
                -Force `
                -ErrorAction Stop
        } catch {
            Add-ErrorRecord `
                "ENUMERATE" `
                $Current `
                $_.Exception.Message `
                $false

            continue
        }

        foreach ($Item in $Items) {

            if ($Item.PSIsContainer) {

                # Evita recursão por junction/symlink.
                if (($Item.Attributes -band
                    [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    continue
                }

                if (-not (Test-ExcludedPath $Item.FullName)) {
                    $Stack.Push($Item.FullName)
                }

            } else {

                if (-not (Test-ExcludedPath $Item.FullName)) {
                    Write-Output $Item
                }
            }
        }
    }
}

# ============================================================
# HASH
# ============================================================

function Get-SHA256Safe {
    param(
        [string]$Path,
        [bool]$Critical = $false
    )

    try {
        return (
            Get-FileHash `
                -LiteralPath $Path `
                -Algorithm SHA256 `
                -ErrorAction Stop
        ).Hash
    } catch {

        # Fallback .NET.
        try {
            $Stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )

            try {
                $Sha = [System.Security.Cryptography.SHA256]::Create()
                $Bytes = $Sha.ComputeHash($Stream)
                return (
                    $Bytes |
                    ForEach-Object { $_.ToString("x2") }
                ) -join ""
            } finally {
                $Stream.Dispose()
            }

        } catch {
            $script:Stats.HashErrors++

            Add-ErrorRecord `
                "HASH" `
                $Path `
                $_.Exception.Message `
                $Critical

            return $null
        }
    }
}

# ============================================================
# CLASSIFICAÇÃO / PRIORIZAÇÃO
# ============================================================

function Get-FilePriority {
    param([System.IO.FileInfo]$File)

    $Score = 10
    $Reasons = New-Object System.Collections.ArrayList
    $Sensitivity = "Normal"

    $Ext = $File.Extension.ToLowerInvariant()
    $LowerPath = $File.FullName.ToLowerInvariant()

    # Conteúdo difícil ou impossível de recriar.
    if ($Ext -in @(
        ".pfx", ".p12", ".pem", ".key", ".ppk", ".kdbx"
    )) {
        $Score += 55
        $Sensitivity = "Critical"
        [void]$Reasons.Add("credential-or-key")
    }

    if ($Ext -in @(
        ".db", ".sqlite", ".sqlite3",
        ".mdb", ".accdb", ".mdf", ".bak", ".dump"
    )) {
        $Score += 35
        if ($Sensitivity -eq "Normal") {
            $Sensitivity = "High"
        }
        [void]$Reasons.Add("database")
    }

    if ($Ext -in @(
        ".pst", ".mbox", ".eml"
    )) {
        $Score += 30
        if ($Sensitivity -eq "Normal") {
            $Sensitivity = "High"
        }
        [void]$Reasons.Add("mail")
    }

    if ($Ext -in @(
        ".doc", ".docx", ".xls", ".xlsx", ".xlsm",
        ".ppt", ".pptx", ".pdf", ".odt",
        ".txt", ".md", ".tex", ".bib"
    )) {
        $Score += 25
        [void]$Reasons.Add("document")
    }

    if ($Ext -in @(
        ".jpg", ".jpeg", ".png", ".tif", ".tiff",
        ".heic", ".raw", ".cr2", ".nef", ".arw"
    )) {
        $Score += 25
        [void]$Reasons.Add("personal-media")
    }

    if ($Ext -in @(
        ".py", ".ipynb", ".ps1", ".psm1",
        ".js", ".ts", ".tsx", ".jsx",
        ".java", ".c", ".cpp", ".cs",
        ".go", ".rs", ".php"
    )) {
        $Score += 20
        [void]$Reasons.Add("source-code")
    }

    $CriticalWords = @(
        "certificado", "certificate",
        "imposto", "tax",
        "contrato", "contract",
        "finance", "financeiro",
        "tese", "thesis",
        "pesquisa", "research",
        "projeto", "project",
        "backup",
        "credential", "secret",
        "recovery", "recuperacao",
        "passkey", "vault"
    )

    foreach ($Word in $CriticalWords) {
        if ($LowerPath.Contains($Word)) {
            $Score += 7
            [void]$Reasons.Add("keyword:$Word")
        }
    }

    # Recência de MODIFICAÇÃO pesa mais que LastAccess.
    $AgeDays = ((Get-Date) - $File.LastWriteTime).TotalDays

    if ($AgeDays -le 30) {
        $Score += 15
        [void]$Reasons.Add("modified<=30d")
    } elseif ($AgeDays -le 365) {
        $Score += 8
        [void]$Reasons.Add("modified<=365d")
    }

    # LastAccess é apenas um sinal fraco no Windows.
    try {
        $AccessAge = ((Get-Date) - $File.LastAccessTime).TotalDays

        if ($AccessAge -le 30) {
            $Score += 3
            [void]$Reasons.Add("recent-access-heuristic")
        }
    } catch {}

    if ($Score -gt 100) {
        $Score = 100
    }

    $Priority =
        if ($Score -ge 80) { "P0_CRITICAL" }
        elseif ($Score -ge 60) { "P1_HIGH" }
        elseif ($Score -ge 35) { "P2_MEDIUM" }
        else { "P3_LOW" }

    return [PSCustomObject]@{
        Score       = $Score
        Priority    = $Priority
        Sensitivity = $Sensitivity
        Reasons     = ($Reasons -join ";")
    }
}

function Test-OnlineOnlyFile {
    param([System.IO.FileInfo]$File)

    # FILE_ATTRIBUTE_OFFLINE = 0x1000
    # FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = 0x400000
    $Raw = [int64]$File.Attributes

    return (
        (($Raw -band 0x1000) -ne 0) -or
        (($Raw -band 0x400000) -ne 0)
    )
}

# ============================================================
# ROBOCOPY EM LOTES
# ============================================================

function Invoke-RobocopyBatch {
    param(
        [object[]]$Items
    )

    if (-not $Items -or $Items.Count -eq 0) {
        return
    }

    $SourceDir = $Items[0].SourceDirectory
    $DestinationDir = $Items[0].DestinationDirectory

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $DestinationDir |
        Out-Null

    $Args = @(
        $SourceDir,
        $DestinationDir
    )

    foreach ($Item in $Items) {
        $Args += $Item.FileName
    }

    if ($PreserveAcls) {
        $Args += "/COPY:DATS"
    } else {
        $Args += "/COPY:DAT"
    }

    $Args += @(
        "/DCOPY:DAT",
        "/Z",
        "/IS",
        "/IT",
        "/XJ",
        "/R:$RobocopyRetry",
        "/W:$RobocopyWaitSeconds",
        "/MT:$RobocopyThreads",
        "/NP",
        "/FP",
        "/TS",
        "/BYTES",
        "/LOG+:$RobocopyLogPath"
    )

    & robocopy.exe @Args | Out-Null
    $Rc = $LASTEXITCODE

    if ($Rc -ge 8) {
        Add-ErrorRecord `
            "ROBOCOPY" `
            $SourceDir `
            "Robocopy retornou código $Rc." `
            $true

        $script:Stats.CopyErrors++
    }

    foreach ($Item in $Items) {

        $DestinationHash = $null
        $Status = "COPY_FAILED"

        try {
            if (-not (Test-Path -LiteralPath $Item.DestinationPath)) {
                throw "Arquivo não apareceu no destino."
            }

            $DestInfo = Get-Item `
                -LiteralPath $Item.DestinationPath `
                -Force `
                -ErrorAction Stop

            if ($DestInfo.Length -ne $Item.SizeBytes) {
                throw "Tamanho pós-cópia difere da origem."
            }

            $DestinationHash = Get-SHA256Safe `
                $Item.DestinationPath `
                $true

            if (-not $DestinationHash) {
                throw "Não foi possível calcular hash do destino."
            }

            if ($DestinationHash -ne $Item.SourceSHA256) {
                throw "SHA256 pós-cópia não confere."
            }

            $Status = "VERIFIED"
            $script:Stats.Copied++
            $script:Stats.Verified++

        } catch {

            Add-ErrorRecord `
                "VERIFY_AFTER_COPY" `
                $Item.DestinationPath `
                $_.Exception.Message `
                $true

            $script:Stats.CopyErrors++
        }

        Write-CsvRow $TransferWriter @(
            $RunId,
            $Item.SourcePath,
            $Item.DestinationPath,
            $Item.SizeBytes,
            $Item.SourceSHA256,
            $DestinationHash,
            $Rc,
            $Status,
            (Get-Date).ToUniversalTime().ToString("o")
        )
    }
}

function Add-ToCopyBatch {
    param([object]$Item)

    $Key = (
        $Item.SourceDirectory.ToLowerInvariant() +
        "|" +
        $Item.DestinationDirectory.ToLowerInvariant()
    )

    if (-not $script:Buckets.ContainsKey($Key)) {
        $script:Buckets[$Key] =
            New-Object System.Collections.ArrayList
    }

    [void]$script:Buckets[$Key].Add($Item)

    if ($script:Buckets[$Key].Count -ge $RobocopyBatchSize) {

        Invoke-RobocopyBatch `
            -Items @($script:Buckets[$Key])

        $script:Buckets[$Key].Clear()
    }
}

function Flush-CopyBatches {

    foreach ($Key in @($script:Buckets.Keys)) {

        if ($script:Buckets[$Key].Count -gt 0) {

            Invoke-RobocopyBatch `
                -Items @($script:Buckets[$Key])

            $script:Buckets[$Key].Clear()
        }
    }
}

# ============================================================
# DECISÃO DE DEDUPLICAÇÃO POR ARQUIVO
# ============================================================

function Sync-FileRecord {
    param(
        [System.IO.FileInfo]$File,
        [string]$SourceRoot,
        [string]$DestinationRoot,
        [string]$Category,
        [string]$RootId
    )

    $script:Stats.Examined++

    $SourceNormalized =
        (Get-NormalizedPath $File.FullName).ToLowerInvariant()

    $Relative = Get-RelativePathSafe `
        $SourceRoot `
        $File.FullName

    $DestinationPath =
        Join-Path $DestinationRoot $Relative

    $Priority = Get-FilePriority $File

    # Evita duplicação se, por exemplo, Documents também estiver
    # dentro de OneDrive e a mesma origem for encontrada novamente.
    if (-not $script:ProcessedSources.Add($SourceNormalized)) {

        $script:Stats.DuplicateSource++

        Write-CsvRow $InventoryWriter @(
            $RunId, $Mode, $Category, $RootId,
            $File.FullName, $Relative, $DestinationPath,
            $File.Length,
            $File.LastWriteTimeUtc.ToString("o"),
            $File.LastAccessTimeUtc.ToString("o"),
            $File.Extension,
            "",
            $Priority.Score,
            $Priority.Priority,
            $Priority.Sensitivity,
            "DUP_SOURCE",
            "Mesma origem física/lógica já processada por outra raiz."
        )

        return
    }

    # OneDrive / Cloud placeholder.
    if ((Test-OnlineOnlyFile $File) -and
        (-not $HydrateCloudFiles)) {

        $script:Stats.CloudOnly++

        Write-CsvRow $InventoryWriter @(
            $RunId, $Mode, $Category, $RootId,
            $File.FullName, $Relative, $DestinationPath,
            $File.Length,
            $File.LastWriteTimeUtc.ToString("o"),
            $File.LastAccessTimeUtc.ToString("o"),
            $File.Extension,
            "",
            $Priority.Score,
            $Priority.Priority,
            $Priority.Sensitivity,
            "CLOUD_ONLY_NOT_HYDRATED",
            "Arquivo online-only; HydrateCloudFiles=false."
        )

        Add-ErrorRecord `
            "CLOUD_ONLY" `
            $File.FullName `
            "Arquivo não foi materializado localmente." `
            ($Priority.Priority -eq "P0_CRITICAL")

        return
    }

    # A leitura para SHA256 também força materialização
    # quando o provedor de arquivos em nuvem permite.
    $SourceHash = Get-SHA256Safe `
        $File.FullName `
        ($Priority.Priority -eq "P0_CRITICAL")

    if (-not $SourceHash) {

        Write-CsvRow $InventoryWriter @(
            $RunId, $Mode, $Category, $RootId,
            $File.FullName, $Relative, $DestinationPath,
            $File.Length,
            $File.LastWriteTimeUtc.ToString("o"),
            $File.LastAccessTimeUtc.ToString("o"),
            $File.Extension,
            "",
            $Priority.Score,
            $Priority.Priority,
            $Priority.Sensitivity,
            "HASH_ERROR",
            "Origem não pôde ser validada."
        )

        return
    }

    $Status = "NEW"
    $NeedCopy = $true
    $Note = ""

    if (Test-Path -LiteralPath $DestinationPath) {

        try {
            $DestInfo = Get-Item `
                -LiteralPath $DestinationPath `
                -Force `
                -ErrorAction Stop

            if ($DestInfo.Length -eq $File.Length) {

                $DestinationHash =
                    Get-SHA256Safe $DestinationPath $false

                if ($DestinationHash -and
                    $DestinationHash -eq $SourceHash) {

                    $NeedCopy = $false
                    $Status = "SKIP_IDENTICAL"
                    $Note = "Mesmo caminho relativo + tamanho + SHA256."
                    $script:Stats.SkippedSame++
                } else {
                    $Status = "CHANGED_SAME_SIZE"
                    $Note = "Mesmo tamanho, SHA256 diferente."
                }

            } else {
                $Status = "CHANGED_SIZE"
                $Note = "Tamanho diferente."
            }

        } catch {
            $Status = "DESTINATION_CHECK_ERROR"
            $Note = $_.Exception.Message
        }
    }

    Write-CsvRow $InventoryWriter @(
        $RunId, $Mode, $Category, $RootId,
        $File.FullName, $Relative, $DestinationPath,
        $File.Length,
        $File.LastWriteTimeUtc.ToString("o"),
        $File.LastAccessTimeUtc.ToString("o"),
        $File.Extension,
        $SourceHash,
        $Priority.Score,
        $Priority.Priority,
        $Priority.Sensitivity,
        $Status,
        $Note
    )

    if (-not $NeedCopy) {
        return
    }

    $DestinationDirectory =
        Split-Path -Parent $DestinationPath

    $CopyItem = [PSCustomObject]@{
        SourcePath           = $File.FullName
        DestinationPath      = $DestinationPath
        SourceDirectory      = $File.DirectoryName
        DestinationDirectory = $DestinationDirectory
        FileName             = $File.Name
        SizeBytes            = $File.Length
        SourceSHA256         = $SourceHash
    }

    Add-ToCopyBatch $CopyItem
}

function Sync-Root {
    param(
        [string]$SourceRoot,
        [string]$DestinationRoot,
        [string]$Category,
        [string]$RootId
    )

    if (-not $SourceRoot) {
        return
    }

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        Write-Log "Fonte ausente: $SourceRoot" "WARN"
        return
    }

    $SourceNormalized = Get-NormalizedPath $SourceRoot

    if ((Get-NormalizedPath $SourceNormalized).
        ToLowerInvariant().
        StartsWith($RepoRootNormalized)) {

        Write-Log "Fonte dentro do próprio backup ignorada: $SourceRoot" "WARN"
        return
    }

    [void]$script:ManagedRoots.Add(
        [PSCustomObject]@{
            Source      = $SourceNormalized
            Destination = $DestinationRoot
            Category    = $Category
            RootId      = $RootId
        }
    )

    Write-Log "Processando [$Category/$RootId] $SourceRoot"

    foreach ($File in Get-SafeFiles $SourceRoot) {
        Sync-FileRecord `
            -File $File `
            -SourceRoot $SourceRoot `
            -DestinationRoot $DestinationRoot `
            -Category $Category `
            -RootId $RootId
    }

    Flush-CopyBatches
}

# ============================================================
# ARTEFATOS: WSL / DOCKER / CERTIFICADOS ETC.
# ============================================================

function Install-Artifact {
    param(
        [string]$Type,
        [string]$Name,
        [string]$TemporaryPath,
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $TemporaryPath)) {
        Add-ErrorRecord `
            "ARTIFACT" `
            $TemporaryPath `
            "Artefato temporário não foi criado." `
            $true
        return
    }

    $SourceHash = Get-SHA256Safe $TemporaryPath $true

    if (-not $SourceHash) {
        return
    }

    $TempInfo = Get-Item $TemporaryPath

    $Status = "INSTALLED"

    if (Test-Path -LiteralPath $DestinationPath) {

        $DestInfo = Get-Item $DestinationPath

        if ($DestInfo.Length -eq $TempInfo.Length) {

            $DestHash = Get-SHA256Safe $DestinationPath $false

            if ($DestHash -eq $SourceHash) {

                Remove-Item `
                    -LiteralPath $TemporaryPath `
                    -Force `
                    -ErrorAction SilentlyContinue

                $Status = "SKIP_IDENTICAL"
            }
        }
    }

    if ($Status -ne "SKIP_IDENTICAL") {

        New-Item `
            -ItemType Directory `
            -Force `
            -Path (Split-Path -Parent $DestinationPath) |
            Out-Null

        Move-Item `
            -LiteralPath $TemporaryPath `
            -Destination $DestinationPath `
            -Force

        $VerifyHash =
            Get-SHA256Safe $DestinationPath $true

        if ($VerifyHash -ne $SourceHash) {
            $Status = "VERIFY_FAILED"

            Add-ErrorRecord `
                "ARTIFACT_VERIFY" `
                $DestinationPath `
                "SHA256 do artefato final não confere." `
                $true
        } else {
            $script:Stats.Artifacts++
        }
    }

    $FinalInfo =
        Get-Item $DestinationPath -ErrorAction SilentlyContinue

    Write-CsvRow $ArtifactWriter @(
        $RunId,
        $Type,
        $Name,
        $DestinationPath,
        $(if ($FinalInfo) { $FinalInfo.Length } else { "" }),
        $SourceHash,
        $Status,
        (Get-Date).ToUniversalTime().ToString("o")
    )
}

# ============================================================
# SEGURANÇA DO DESTINO
# ============================================================

function Test-DestinationEncryption {

    $Root = [System.IO.Path]::GetPathRoot(
        (Get-NormalizedPath $BackupRoot)
    )

    if ($Root -notmatch "^[A-Za-z]:\\$") {
        Write-Log "Destino não é volume local; BitLocker não será validado." "WARN"

        if ($RequireEncryptedDestination) {
            throw "RequireEncryptedDestination=true, mas destino não pôde ser validado."
        }

        return
    }

    if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        Write-Log "Cmdlet Get-BitLockerVolume não disponível." "WARN"

        if ($RequireEncryptedDestination) {
            throw "Não foi possível confirmar BitLocker."
        }

        return
    }

    try {
        $Volume = Get-BitLockerVolume `
            -MountPoint $Root `
            -ErrorAction Stop

        $Summary = [PSCustomObject]@{
            MountPoint       = $Root
            VolumeStatus     = $Volume.VolumeStatus
            ProtectionStatus = $Volume.ProtectionStatus
            EncryptionMethod = $Volume.EncryptionMethod
        }

        $Summary |
            Export-Csv `
                (Join-Path $InventoryRoot "bitlocker_destino_$RunId.csv") `
                -NoTypeInformation `
                -Encoding UTF8

        if ([string]$Volume.ProtectionStatus -ne "On") {

            Write-Log "Destino não está com proteção BitLocker ativa." "WARN"

            if ($RequireEncryptedDestination) {
                throw "Destino sem BitLocker ativo."
            }

        } else {
            Write-Log "BitLocker ativo no destino." "OK"
        }

    } catch {
        if ($RequireEncryptedDestination) {
            throw
        }

        Add-ErrorRecord `
            "BITLOCKER" `
            $Root `
            $_.Exception.Message `
            $false
    }
}

function Set-BackupRootAcl {

    if (-not $HardenBackupAcl) {
        return
    }

    $Root = [System.IO.Path]::GetPathRoot(
        (Get-NormalizedPath $RepoRoot)
    )

    try {
        $Volume = Get-Volume `
            -DriveLetter $Root.TrimEnd(":\") `
            -ErrorAction Stop

        if ($Volume.FileSystem -ne "NTFS") {
            Write-Log "ACL hardening ignorado: filesystem não é NTFS." "WARN"
            return
        }

        $CurrentSid =
            ([System.Security.Principal.WindowsIdentity]::GetCurrent()).
            User.Value

        & icacls.exe `
            $RepoRoot `
            "/inheritance:r" `
            "/grant:r" `
            "*$($CurrentSid):(OI)(CI)F" `
            "*S-1-5-32-544:(OI)(CI)F" |
            Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "icacls retornou $LASTEXITCODE."
        }

        Write-Log "ACL da raiz do backup restringida." "OK"

    } catch {
        Add-ErrorRecord `
            "ACL" `
            $RepoRoot `
            $_.Exception.Message `
            $false
    }
}

# ============================================================
# INVENTÁRIO DE SISTEMA
# ============================================================

function Export-SystemInventory {

    try {
        Get-Volume |
            Select-Object `
                DriveLetter, FileSystemLabel, FileSystem,
                Size, SizeRemaining, HealthStatus |
            Export-Csv `
                (Join-Path $InventoryRoot "volumes_$RunId.csv") `
                -NoTypeInformation `
                -Encoding UTF8
    } catch {}

    try {
        Get-Disk |
            Select-Object `
                Number, FriendlyName, SerialNumber,
                PartitionStyle, OperationalStatus, Size |
            Export-Csv `
                (Join-Path $InventoryRoot "discos_$RunId.csv") `
                -NoTypeInformation `
                -Encoding UTF8
    } catch {}

    # Não exporta VALORES das variáveis de ambiente.
    try {
        Get-ChildItem Env: |
            Select-Object -ExpandProperty Name |
            Sort-Object |
            Set-Content `
                (Join-Path $InventoryRoot "nomes_variaveis_ambiente_$RunId.txt") `
                -Encoding UTF8
    } catch {}

    # Programas instalados via registro.
    try {
        $RegistryPaths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        $Apps = foreach ($Reg in $RegistryPaths) {
            Get-ItemProperty `
                $Reg `
                -ErrorAction SilentlyContinue |
                Where-Object DisplayName |
                Select-Object `
                    DisplayName,
                    DisplayVersion,
                    Publisher,
                    InstallLocation
        }

        $Apps |
            Sort-Object DisplayName -Unique |
            Export-Csv `
                (Join-Path $InventoryRoot "programas_instalados_$RunId.csv") `
                -NoTypeInformation `
                -Encoding UTF8
    } catch {}

    # Winget.
    if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        try {
            & winget.exe export `
                -o (Join-Path $InventoryRoot "winget_$RunId.json") `
                --accept-source-agreements |
                Out-Null
        } catch {}
    }

    # Serviços de banco de dados.
    try {
        Get-Service |
            Where-Object {
                $_.Name -match
                "SQL|MSSQL|Postgre|MySQL|Maria|Mongo|Oracle"
            } |
            Select-Object `
                Name, DisplayName, Status, StartType |
            Export-Csv `
                (Join-Path $InventoryRoot "servicos_banco_dados_$RunId.csv") `
                -NoTypeInformation `
                -Encoding UTF8
    } catch {}

    # Tarefas agendadas.
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        try {
            Get-ScheduledTask |
                Select-Object `
                    TaskPath, TaskName, State |
                Export-Csv `
                    (Join-Path $InventoryRoot "tarefas_agendadas_$RunId.csv") `
                    -NoTypeInformation `
                    -Encoding UTF8
        } catch {}
    }

    # Política LastAccess para interpretação posterior do campo.
    try {
        (& fsutil.exe behavior query disablelastaccess 2>&1) |
            Out-File `
                (Join-Path $InventoryRoot "ntfs_lastaccess_policy_$RunId.txt") `
                -Encoding UTF8
    } catch {}
}

# ============================================================
# CERTIFICADOS
# ============================================================

function Backup-Certificates {

    Write-Log "Inventariando certificados..."

    $CertRecords = New-Object System.Collections.ArrayList

    foreach ($Store in @(
        "Cert:\CurrentUser\My",
        "Cert:\LocalMachine\My"
    )) {

        try {
            foreach ($Cert in Get-ChildItem $Store -ErrorAction Stop) {

                [void]$CertRecords.Add(
                    [PSCustomObject]@{
                        Store         = $Store
                        Subject       = $Cert.Subject
                        Issuer        = $Cert.Issuer
                        Thumbprint    = $Cert.Thumbprint
                        NotBefore     = $Cert.NotBefore
                        NotAfter      = $Cert.NotAfter
                        HasPrivateKey = $Cert.HasPrivateKey
                    }
                )
            }
        } catch {
            Add-ErrorRecord `
                "CERT_ENUM" `
                $Store `
                $_.Exception.Message `
                $false
        }
    }

    $CertRecords |
        Export-Csv `
            (Join-Path $InventoryRoot "certificados_$RunId.csv") `
            -NoTypeInformation `
            -Encoding UTF8

    if (-not $ExportPrivateCertificates) {
        Write-Log "Chaves privadas NÃO serão exportadas; opção está desativada."
        return
    }

    $Password = Read-Host `
        "Senha forte para os PFX exportados" `
        -AsSecureString

    try {
        foreach ($Cert in Get-ChildItem Cert:\CurrentUser\My) {

            if (-not $Cert.HasPrivateKey) {
                continue
            }

            $SafeName =
                ($Cert.Thumbprint -replace '[^A-Za-z0-9_-]', '_')

            $TempPfx =
                Join-Path $TempRoot "$SafeName.pfx"

            try {
                Export-PfxCertificate `
                    -Cert $Cert `
                    -FilePath $TempPfx `
                    -Password $Password `
                    -Force `
                    -ErrorAction Stop |
                    Out-Null

                Install-Artifact `
                    "CertificatePFX" `
                    $Cert.Thumbprint `
                    $TempPfx `
                    (Join-Path $CertRoot "$SafeName.pfx")

            } catch {
                Add-ErrorRecord `
                    "CERT_EXPORT" `
                    $Cert.Thumbprint `
                    $_.Exception.Message `
                    $true
            }
        }
    } finally {
        $Password = $null
    }
}

# ============================================================
# WSL
# ============================================================

function Backup-WSLDistributions {

    if (-not $BackupWSL) {
        return
    }

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Log "WSL não encontrado."
        return
    }

    Write-Log "Inventariando WSL..."

    try {
        (& wsl.exe --list --verbose 2>&1) |
            Out-File `
                (Join-Path $InventoryRoot "wsl_list_$RunId.txt") `
                -Encoding UTF8
    } catch {}

    $Distros = @(
        & wsl.exe --list --quiet 2>$null |
        ForEach-Object {
            ($_ -replace "`0", "").Trim()
        } |
        Where-Object { $_ }
    )

    if ($Distros.Count -eq 0) {
        return
    }

    if ($QuiesceWorkloads) {
        Write-Log "QuiesceWorkloads=true: executando wsl --shutdown." "WARN"
        & wsl.exe --shutdown
    }

    foreach ($Distro in $Distros) {

        $SafeName =
            ($Distro -replace '[^A-Za-z0-9._-]', '_')

        $TempTar =
            Join-Path $TempRoot "WSL_$SafeName.tar"

        $Destination =
            Join-Path `
                (Join-Path $SpecialRoot "WSL") `
                "$SafeName.tar"

        Write-Log "Exportando WSL: $Distro"

        & wsl.exe --export $Distro $TempTar

        if ($LASTEXITCODE -ne 0) {
            Add-ErrorRecord `
                "WSL_EXPORT" `
                $Distro `
                "wsl --export retornou $LASTEXITCODE." `
                $true
            continue
        }

        Install-Artifact `
            "WSL" `
            $Distro `
            $TempTar `
            $Destination
    }
}

# ============================================================
# DOCKER VOLUMES
# ============================================================

function Backup-Docker {

    if (-not $BackupDockerVolumes) {
        return
    }

    if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
        Write-Log "Docker CLI não encontrado."
        return
    }

    try {
        & docker.exe info 2>&1 |
            Out-File `
                (Join-Path $InventoryRoot "docker_info_$RunId.txt") `
                -Encoding UTF8

        if ($LASTEXITCODE -ne 0) {
            throw "Docker daemon não está acessível."
        }
    } catch {
        Add-ErrorRecord `
            "DOCKER" `
            "docker info" `
            $_.Exception.Message `
            $false
        return
    }

    & docker.exe ps -a --no-trunc 2>&1 |
        Out-File `
            (Join-Path $InventoryRoot "docker_containers_$RunId.txt") `
            -Encoding UTF8

    & docker.exe images --digests 2>&1 |
        Out-File `
            (Join-Path $InventoryRoot "docker_images_$RunId.txt") `
            -Encoding UTF8

    $Volumes = @(
        & docker.exe volume ls -q 2>$null |
        Where-Object { $_ }
    )

    $Volumes |
        Set-Content `
            (Join-Path $InventoryRoot "docker_volumes_$RunId.txt") `
            -Encoding UTF8

    if ($Volumes.Count -eq 0) {
        return
    }

    & docker.exe image inspect $DockerHelperImage 2>$null |
        Out-Null

    $HelperExists = ($LASTEXITCODE -eq 0)

    if (-not $HelperExists -and $AllowDockerImagePull) {

        Write-Log "Baixando imagem auxiliar Docker: $DockerHelperImage" "WARN"

        & docker.exe pull $DockerHelperImage

        $HelperExists = ($LASTEXITCODE -eq 0)
    }

    if (-not $HelperExists) {

        Add-ErrorRecord `
            "DOCKER" `
            $DockerHelperImage `
            "Imagem auxiliar não existe localmente. " +
            "Defina AllowDockerImagePull=true ou faça docker pull manual." `
            $false

        return
    }

    foreach ($Volume in $Volumes) {

        $SafeName =
            ($Volume -replace '[^A-Za-z0-9._-]', '_')

        $ArchiveName = "docker_volume_$SafeName.tar.gz"
        $TempArchive = Join-Path $TempRoot $ArchiveName

        Remove-Item `
            -LiteralPath $TempArchive `
            -Force `
            -ErrorAction SilentlyContinue

        Write-Log "Exportando volume Docker: $Volume"

        & docker.exe run `
            --rm `
            --mount "type=volume,src=$Volume,dst=/volume,readonly" `
            --mount "type=bind,src=$TempRoot,dst=/backup" `
            $DockerHelperImage `
            sh -c "tar czf '/backup/$ArchiveName' -C /volume ."

        if ($LASTEXITCODE -ne 0) {

            Add-ErrorRecord `
                "DOCKER_VOLUME_EXPORT" `
                $Volume `
                "docker run/tar retornou $LASTEXITCODE." `
                $true

            continue
        }

        Install-Artifact `
            "DockerVolume" `
            $Volume `
            $TempArchive `
            (Join-Path `
                (Join-Path $SpecialRoot "DockerVolumes") `
                $ArchiveName)
    }
}

# ============================================================
# HYPER-V
# ============================================================

function Backup-HyperV {

    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        return
    }

    Write-Log "Inventariando Hyper-V..."

    try {
        $VMs = @(Get-VM -ErrorAction Stop)

        $VMs |
            Select-Object `
                Name, State, Status,
                Generation, Version,
                Path, ConfigurationLocation,
                SnapshotFileLocation,
                SmartPagingFilePath |
            Export-Csv `
                (Join-Path $InventoryRoot "hyperv_vms_$RunId.csv") `
                -NoTypeInformation `
                -Encoding UTF8
    } catch {
        Add-ErrorRecord `
            "HYPERV_ENUM" `
            "Get-VM" `
            $_.Exception.Message `
            $false
        return
    }

    if (-not $ExportHyperV) {
        return
    }

    foreach ($VM in $VMs) {

        $SafeName =
            ($VM.Name -replace '[^A-Za-z0-9._-]', '_')

        $Stage =
            Join-Path $TempRoot "HyperV_$SafeName"

        Remove-Item `
            -LiteralPath $Stage `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue

        New-Item `
            -ItemType Directory `
            -Force `
            -Path $Stage |
            Out-Null

        Write-Log "Exportando VM Hyper-V: $($VM.Name)"

        try {
            Export-VM `
                -VM $VM `
                -Path $Stage `
                -CaptureLiveState CaptureDataConsistentState `
                -ErrorAction Stop

            $ExportedFolder =
                Get-ChildItem `
                    -LiteralPath $Stage `
                    -Directory `
                    -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($ExportedFolder) {
                $Source = $ExportedFolder.FullName
            } else {
                $Source = $Stage
            }

            Sync-Root `
                $Source `
                (Join-Path `
                    (Join-Path $VmRoot "HyperV") `
                    $SafeName) `
                "VM" `
                "HyperV_$SafeName"

        } catch {
            Add-ErrorRecord `
                "HYPERV_EXPORT" `
                $VM.Name `
                $_.Exception.Message `
                $true
        } finally {
            Remove-Item `
                -LiteralPath $Stage `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# DESCOBERTA DE FONTES CONHECIDAS
# ============================================================

function Backup-KnownRoots {

    # ---------- Pastas pessoais ----------

    $KnownUserFolders = @(
        @{
            Name = "Desktop"
            Path = [Environment]::GetFolderPath("Desktop")
        },
        @{
            Name = "Documents"
            Path = [Environment]::GetFolderPath("MyDocuments")
        },
        @{
            Name = "Pictures"
            Path = [Environment]::GetFolderPath("MyPictures")
        },
        @{
            Name = "Music"
            Path = [Environment]::GetFolderPath("MyMusic")
        },
        @{
            Name = "Videos"
            Path = [Environment]::GetFolderPath("MyVideos")
        },
        @{
            Name = "Favorites"
            Path = [Environment]::GetFolderPath("Favorites")
        },
        @{
            Name = "Downloads"
            Path = (Join-Path $UserProfile "Downloads")
        }
    )

    foreach ($Entry in $KnownUserFolders) {
        if ($Entry.Path) {
            Sync-Root `
                $Entry.Path `
                (Join-Path $UserRoot $Entry.Name) `
                "USER" `
                $Entry.Name
        }
    }

    # ---------- OneDrive ----------

    $OneDrivePaths = @(
        $env:OneDrive,
        $env:OneDriveConsumer,
        $env:OneDriveCommercial
    ) |
        Where-Object {
            $_ -and (Test-Path -LiteralPath $_)
        } |
        Select-Object -Unique

    $Index = 0

    foreach ($Path in $OneDrivePaths) {

        $Index++

        Sync-Root `
            $Path `
            (Join-Path $OneDriveRoot "OneDrive_$Index") `
            "ONEDRIVE" `
            "OneDrive_$Index"
    }

    # ---------- Projetos ----------

    $ProjectCandidates = @(
        "$UserProfile\Projects",
        "$UserProfile\Projetos",
        "$UserProfile\Source",
        "$UserProfile\source",
        "$UserProfile\Code",
        "$UserProfile\code",
        "$UserProfile\dev",
        "$UserProfile\Development",
        "$UserProfile\workspace",
        "$UserProfile\repos",
        "$UserProfile\GitHub",
        "$UserProfile\Documents\GitHub",
        "$UserProfile\Documents\Projects",
        "$UserProfile\Documents\Projetos"
    )

    foreach ($Path in $ProjectCandidates | Select-Object -Unique) {

        if (Test-Path -LiteralPath $Path) {

            $Name =
                Split-Path -Leaf $Path

            Sync-Root `
                $Path `
                (Join-Path $ProjectsRoot $Name) `
                "PROJECTS" `
                $Name
        }
    }

    # ---------- SSH ----------

    $Ssh = Join-Path $UserProfile ".ssh"

    if (Test-Path $Ssh) {
        Sync-Root `
            $Ssh `
            (Join-Path $AppsRoot "SSH") `
            "SENSITIVE_APP" `
            "SSH"
    }

    # ---------- PowerShell ----------

    foreach ($Path in @(
        "$UserProfile\Documents\PowerShell",
        "$UserProfile\Documents\WindowsPowerShell"
    )) {
        if (Test-Path $Path) {
            Sync-Root `
                $Path `
                (Join-Path `
                    (Join-Path $AppsRoot "PowerShell") `
                    (Split-Path -Leaf $Path)) `
                "APP" `
                "PowerShell"
        }
    }

    # ---------- VS Code ----------

    $VsCode = Join-Path $env:APPDATA "Code\User"

    if (Test-Path $VsCode) {
        Sync-Root `
            $VsCode `
            (Join-Path $AppsRoot "VSCode\User") `
            "APP" `
            "VSCode"
    }

    # ---------- Thunderbird ----------

    if ($IncludeSensitiveAppProfiles) {

        $Thunderbird = Join-Path $env:APPDATA "Thunderbird"

        if (Test-Path $Thunderbird) {
            Sync-Root `
                $Thunderbird `
                (Join-Path $AppsRoot "Thunderbird") `
                "SENSITIVE_APP" `
                "Thunderbird"
        }
    }

    # ---------- Zotero ----------

    foreach ($ZPath in @(
        "$UserProfile\Zotero",
        "$env:APPDATA\Zotero"
    )) {

        if (Test-Path $ZPath) {
            Sync-Root `
                $ZPath `
                (Join-Path `
                    (Join-Path $AppsRoot "Zotero") `
                    (Split-Path -Leaf $ZPath)) `
                "SENSITIVE_APP" `
                "Zotero"
        }
    }

    # ---------- Telegram legacy ----------

    if ($IncludeSensitiveAppProfiles) {

        $TelegramLegacy =
            Join-Path $env:APPDATA "Telegram Desktop"

        if (Test-Path $TelegramLegacy) {
            Sync-Root `
                $TelegramLegacy `
                (Join-Path $AppsRoot "Telegram\Legacy") `
                "SENSITIVE_APP" `
                "TelegramLegacy"
        }
    }

    # ---------- WhatsApp legacy ----------

    if ($IncludeSensitiveAppProfiles) {

        foreach ($Path in @(
            "$env:APPDATA\WhatsApp",
            "$env:LOCALAPPDATA\WhatsApp"
        )) {

            if (Test-Path $Path) {
                Sync-Root `
                    $Path `
                    (Join-Path `
                        $AppsRoot `
                        "WhatsApp\Legacy_$(Split-Path -Leaf $Path)") `
                    "SENSITIVE_APP" `
                    "WhatsAppLegacy"
            }
        }
    }

    # ---------- Apps Microsoft Store ----------
    # Descoberta dinâmica é preferível a assumir PackageFamilyName.

    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {

        foreach ($Pattern in @("*WhatsApp*", "*Telegram*")) {

            try {
                foreach ($Package in Get-AppxPackage $Pattern) {

                    $PkgRoot =
                        Join-Path `
                            $env:LOCALAPPDATA `
                            "Packages\$($Package.PackageFamilyName)"

                    if (Test-Path $PkgRoot) {

                        $AppName =
                            ($Package.Name -replace '[^A-Za-z0-9._-]', '_')

                        Sync-Root `
                            $PkgRoot `
                            (Join-Path $AppsRoot "StoreApps\$AppName") `
                            "SENSITIVE_APP" `
                            "StoreApp_$AppName"
                    }
                }
            } catch {}
        }
    }

    # ---------- Firefox ----------
    # Útil para perfil, favoritos e configurações.
    if ($IncludeSensitiveAppProfiles) {

        $Firefox =
            Join-Path $env:APPDATA "Mozilla\Firefox"

        if (Test-Path $Firefox) {
            Sync-Root `
                $Firefox `
                (Join-Path $AppsRoot "Firefox") `
                "SENSITIVE_APP" `
                "Firefox"
        }
    }

    # ---------- VMs não Hyper-V ----------

    $VmCandidates = @(
        @{
            Path = "$UserProfile\VirtualBox VMs"
            Type = "VirtualBox"
        },
        @{
            Path = "$UserProfile\Documents\Virtual Machines"
            Type = "VMware"
        },
        @{
            Path = "$UserProfile\Documents\VirtualBox VMs"
            Type = "VirtualBox"
        }
    )

    foreach ($Vm in $VmCandidates) {

        if (Test-Path $Vm.Path) {

            Sync-Root `
                $Vm.Path `
                (Join-Path $VmRoot $Vm.Type) `
                "VM" `
                $Vm.Type
        }
    }
}

# ============================================================
# DISCOS PARA AUDITORIA
# ============================================================

function Get-AuditDrives {

    $Result =
        New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($Drive in $IncludeDrives) {
        if ($Drive) {
            [void]$Result.Add(
                $Drive.TrimEnd("\").ToUpperInvariant()
            )
        }
    }

    if ($AutoIncludeOtherFixedDrives) {

        try {
            $Fixed = Get-CimInstance `
                Win32_LogicalDisk `
                -Filter "DriveType=3"

            foreach ($Disk in $Fixed) {
                if ($Disk.DeviceID) {
                    [void]$Result.Add(
                        $Disk.DeviceID.ToUpperInvariant()
                    )
                }
            }
        } catch {
            Add-ErrorRecord `
                "DRIVE_DISCOVERY" `
                "Win32_LogicalDisk" `
                $_.Exception.Message `
                $false
        }
    }

    return @($Result)
}

function Test-AutoCopyAllowedPath {
    param([string]$Path)

    $Lower = $Path.ToLowerInvariant()

    foreach ($Prefix in @(
        "c:\windows\",
        "c:\program files\",
        "c:\program files (x86)\"
    )) {
        if ($Lower.StartsWith($Prefix)) {
            return $false
        }
    }

    return $true
}

# ============================================================
# AUDITORIA PROFUNDA
# ============================================================

function Invoke-DeepAudit {

    if (-not $DeepAudit) {
        return
    }

    $Drives = Get-AuditDrives

    $BackupDrive =
        [System.IO.Path]::GetPathRoot(
            (Get-NormalizedPath $BackupRoot)
        ).TrimEnd("\").ToUpperInvariant()

    foreach ($Drive in $Drives) {

        $Root = "$Drive\"

        if (-not (Test-Path $Root)) {
            continue
        }

        # Nunca auditar o próprio repositório como fonte.
        if ($Drive.ToUpperInvariant() -eq $BackupDrive) {
            Write-Log "Disco do destino ($Drive) excluído da auditoria recursiva."
            continue
        }

        Write-Log "AUDITORIA PROFUNDA: $Root"

        foreach ($File in Get-SafeFiles $Root) {

            $SourceKey =
                (Get-NormalizedPath $File.FullName).
                ToLowerInvariant()

            $AlreadyCovered =
                $script:ProcessedSources.Contains($SourceKey)

            if ($DiskInventoryWriter) {
                Write-CsvRow $DiskInventoryWriter @(
                    $RunId,
                    $Drive,
                    $File.FullName,
                    $File.Length,
                    $File.Extension,
                    $File.LastWriteTimeUtc.ToString("o"),
                    $File.LastAccessTimeUtc.ToString("o")
                )
            }

            $Ext = $File.Extension.ToLowerInvariant()

            if ($Ext -in $ImportantExtensions) {

                $script:Stats.Discovered++

                $Priority = Get-FilePriority $File

                Write-CsvRow $ImportantWriter @(
                    $RunId,
                    $Drive,
                    $File.FullName,
                    $File.Length,
                    $File.Extension,
                    $File.LastWriteTimeUtc.ToString("o"),
                    $Priority.Score,
                    $Priority.Priority,
                    $Priority.Sensitivity,
                    $AlreadyCovered
                )

                if ($CopyDiscoveredImportantFiles -and
                    (-not $AlreadyCovered) -and
                    ($Ext -in $AutoCopyDiscoveredExtensions) -and
                    (Test-AutoCopyAllowedPath $File.FullName)) {

                    $DriveName =
                        "DRIVE_" + $Drive.TrimEnd(":")

                    Sync-FileRecord `
                        -File $File `
                        -SourceRoot $Root `
                        -DestinationRoot (
                            Join-Path $DiscoveredRoot $DriveName
                        ) `
                        -Category "DISCOVERED" `
                        -RootId $DriveName
                }
            }

            if ($File.Length -ge ($LargeFileThresholdGB * 1GB)) {

                $script:Stats.LargeFiles++

                Write-CsvRow $LargeWriter @(
                    $RunId,
                    $Drive,
                    $File.FullName,
                    $File.Length,
                    [math]::Round($File.Length / 1GB, 3),
                    $File.Extension,
                    $File.LastWriteTimeUtc.ToString("o"),
                    $AlreadyCovered
                )
            }
        }

        Flush-CopyBatches

        # Opcional: backup integral de discos adicionais.
        if ($BackupEntireAdditionalDrives -and
            $Drive -ne "C:") {

            Sync-Root `
                $Root `
                (Join-Path `
                    $ExtraDisksRoot `
                    ("DRIVE_" + $Drive.TrimEnd(":"))) `
                "EXTRA_DISK" `
                ("DRIVE_" + $Drive.TrimEnd(":"))
        }
    }
}

# ============================================================
# MANIFESTO FINAL SHA256
# ============================================================

function Write-FinalHashManifest {

    $ShouldRun =
        $GenerateFullHashManifest -or
        ($Mode -eq "Full")

    if (-not $ShouldRun) {
        return
    }

    Write-Log "Gerando manifesto SHA256 final..."

    $Writer = Open-CsvWriter $FinalHashCsv @(
        "RunId",
        "RelativePath",
        "SizeBytes",
        "LastWriteTimeUtc",
        "SHA256"
    )

    try {
        foreach ($Top in @(
            $UserRoot,
            $OneDriveRoot,
            $ProjectsRoot,
            $AppsRoot,
            $SpecialRoot,
            $VmRoot,
            $CertRoot,
            $DiscoveredRoot,
            $ExtraDisksRoot
        )) {

            if (-not (Test-Path $Top)) {
                continue
            }

            foreach ($File in Get-SafeFiles $Top) {

                $Hash = Get-SHA256Safe $File.FullName $true

                Write-CsvRow $Writer @(
                    $RunId,
                    (Get-RelativePathSafe $RepoRoot $File.FullName),
                    $File.Length,
                    $File.LastWriteTimeUtc.ToString("o"),
                    $Hash
                )
            }
        }
    } finally {
        $Writer.Flush()
        $Writer.Dispose()
    }
}

# ============================================================
# PROMPT PARA IA / AUTOMAÇÃO
# ============================================================

function Write-AIPrompt {

$Prompt = @'
Você é um auditor de backup PRÉ-FORMATAÇÃO de Windows.

OBJETIVO:
Avaliar os inventários fornecidos e decidir se existem itens críticos
não copiados, não verificados ou provavelmente esquecidos.

IMPORTANTE:
- Você NÃO tem autorização para excluir arquivos.
- Você NÃO deve afirmar que é seguro formatar apenas porque o script terminou.
- Trate qualquer erro de hash/cópia em P0 ou P1 como bloqueador.
- Não solicite conteúdo de senhas, tokens, chaves privadas ou documentos.
- Trabalhe inicialmente apenas com metadados, nomes de arquivos, caminhos,
  extensões, tamanhos, datas, classificação e status.
- Marque inferências explicitamente como inferências.
- Não considere LastAccessTime uma medida confiável de frequência de uso.
- Quando houver dúvida, classifique para revisão humana.
- Segredos devem permanecer locais ou ser analisados somente por sistema
  autorizado e apropriado para esses dados.

ENTRADAS ESPERADAS:
1. inventario_backup_*.csv
2. auditoria_importantes_*.csv
3. arquivos_grandes_*.csv
4. transferencias_*.csv
5. erros_*.csv
6. certificados_*.csv
7. servicos_banco_dados_*.csv
8. hashes_sha256_*.csv
9. docker_volumes_*.txt
10. wsl_list_*.txt
11. hyperv_vms_*.csv
12. programas_instalados_*.csv

PRIORIDADE:

P0_CRITICAL:
- chaves privadas, certificados, PFX/P12/PEM;
- vaults de senhas;
- recovery codes/recovery keys;
- bancos de dados locais únicos;
- WSL/VMs/Docker volumes com dados não reproduzíveis;
- documentos legais/fiscais;
- pesquisa/tese/projetos;
- fotos pessoais únicas;
- e-mail local não reproduzível;
- qualquer arquivo marcado crítico que não tenha SHA256 verificado.

P1_HIGH:
- código não enviado a repositório remoto;
- configurações complexas;
- perfis de aplicativos;
- documentos recentes;
- arquivos de trabalho;
- arquivos em discos adicionais;
- bancos que também existem em outro serviço mas cuja sincronização
  não foi confirmada.

P2_MEDIUM:
- material útil, mas provavelmente reproduzível.

P3_LOW:
- cache, instaladores baixáveis novamente, builds reproduzíveis
  e outros itens de baixo impacto.

PROCURE ESPECIFICAMENTE:
- status HASH_ERROR;
- COPY_FAILED;
- VERIFY_FAILED;
- CLOUD_ONLY_NOT_HYDRATED;
- P0 ou P1 sem destino verificado;
- certificados com HasPrivateKey=True mas sem PFX exportado quando necessário;
- WSL listado sem export correspondente;
- Docker volume listado sem tar correspondente;
- Hyper-V VM listada sem export quando o usuário deseja preservá-la;
- banco de dados ativo sem backup nativo;
- Zotero com anexos possivelmente online-only;
- OneDrive online-only;
- caminhos em D:, F:, G: etc.;
- arquivos grandes inexplicados;
- arquivos recentes fora das pastas padrão.

CRITÉRIO NO-GO:
Retorne NO-GO se existir qualquer P0 não verificado, erro crítico,
cloud-only necessário, banco ativo sem procedimento consistente,
VM/WSL/Docker crítico sem export, certificado/chave necessária sem cópia,
ou se não houver teste real de restauração.

CRITÉRIO GO-CANDIDATE:
Somente se:
- todos P0 estiverem copiados e SHA256 verificados;
- erros críticos = 0;
- itens cloud-only importantes estiverem materializados;
- exports especiais necessários existirem;
- houver uma segunda cópia independente dos itens críticos;
- uma amostra de restauração tiver sido testada;
- as recovery keys estiverem guardadas separadamente;
- o usuário humano tiver revisado os itens desconhecidos.

SAÍDA:
Produza primeiro JSON neste formato:

{
  "decision": "GO-CANDIDATE|NO-GO",
  "critical_items": [],
  "unverified_items": [],
  "cloud_only_items": [],
  "database_risks": [],
  "vm_wsl_docker_risks": [],
  "certificate_risks": [],
  "sensitive_items": [],
  "large_unknown_items": [],
  "restore_tests_required": [],
  "human_review_required": [],
  "reasoning_summary": ""
}

Depois do JSON, produza uma tabela curta:
Prioridade | Item | Problema | Evidência | Ação antes da formatação

Nunca converta GO-CANDIDATE em autorização automática para formatar.
A decisão final é humana.
'@

    $Prompt |
        Set-Content `
            (Join-Path $InventoryRoot "PROMPT_IA_PRIORIZACAO.txt") `
            -Encoding UTF8
}

# ============================================================
# RESUMO FINAL
# ============================================================

function Write-FinalSummary {

    if ($script:Errors.Count -gt 0) {
        $script:Errors |
            Export-Csv `
                $ErrorCsv `
                -NoTypeInformation `
                -Encoding UTF8
    } else {
        "TimeUtc,Context,Path,Message,Critical" |
            Set-Content $ErrorCsv -Encoding UTF8
    }

    $CriticalErrors = @(
        $script:Errors |
        Where-Object { $_.Critical }
    ).Count

    $EndTime = Get-Date
    $Duration = $EndTime - $StartTime

    $Readme = @"
BACKUP WINDOWS - RESUMO

RunId:                $RunId
Modo:                 $Mode
Computador:           $Computer
Usuário:              $User
Início:               $StartTime
Fim:                  $EndTime
Duração:               $Duration

Destino:
$RepoRoot

ARQUIVOS
Examinados:           $($script:Stats.Examined)
Copiados:             $($script:Stats.Copied)
Verificados:          $($script:Stats.Verified)
Idênticos ignorados:  $($script:Stats.SkippedSame)
Origens duplicadas:   $($script:Stats.DuplicateSource)
Hash errors:          $($script:Stats.HashErrors)
Copy errors:          $($script:Stats.CopyErrors)
Cloud-only ignorados: $($script:Stats.CloudOnly)
Descobertos:          $($script:Stats.Discovered)
Arquivos grandes:     $($script:Stats.LargeFiles)
Artefatos especiais:  $($script:Stats.Artifacts)

ERROS CRÍTICOS:
$CriticalErrors

ARQUIVOS IMPORTANTES:
$InventoryCsv
$TransferCsv
$ImportantAuditCsv
$LargeFilesCsv
$FinalHashCsv
$ErrorCsv

LOG ROBOCOPY:
$RobocopyLogPath

PROMPT IA:
$(Join-Path $InventoryRoot "PROMPT_IA_PRIORIZACAO.txt")

REGRA DE SEGURANÇA:
Um script concluído NÃO significa automaticamente que é seguro formatar.

Antes da formatação:
1. Erros críticos devem ser zero.
2. Todos os P0 devem estar verificados.
3. Itens OneDrive/Zotero online-only devem ser revisados.
4. Bancos ativos devem possuir backup nativo quando aplicável.
5. WSL/Docker/VMs devem ter exports verificáveis.
6. Certificados e recovery keys devem ser revisados.
7. Deve existir uma segunda cópia independente dos itens críticos.
8. Deve ser feito pelo menos um teste real de restauração.

"@

    $Readme |
        Set-Content `
            (Join-Path $RepoRoot "LEIA-ME_BACKUP.txt") `
            -Encoding UTF8

    Write-Host ""
    Write-Host $Readme

    return $CriticalErrors
}

# ============================================================
# EXECUÇÃO PRINCIPAL
# ============================================================

$ExitCode = 0

try {

    Start-Transcript `
        -Path $TranscriptPath `
        -Append |
        Out-Null

    Write-Log "================================================="
    Write-Log "BACKUP WINDOWS - $Mode"
    Write-Log "RunId: $RunId"
    Write-Log "Destino: $RepoRoot"
    Write-Log "================================================="

    # Segurança primeiro.
    Test-DestinationEncryption
    Set-BackupRootAcl

    # Inventário básico do sistema.
    Export-SystemInventory

    # Arquivos diretamente acessíveis.
    Backup-KnownRoots

    # Certificados.
    Backup-Certificates

    # Exportações especiais.
    Backup-WSLDistributions
    Backup-Docker
    Backup-HyperV

    # Auditoria de todos os discos configurados.
    Invoke-DeepAudit

    # Garante que nada permaneceu na fila Robocopy.
    Flush-CopyBatches

    # Manifesto final.
    Write-FinalHashManifest

    # Prompt para revisão por IA.
    Write-AIPrompt

    $CriticalErrors = Write-FinalSummary

    if ($CriticalErrors -gt 0) {
        Write-Log "Backup terminou com erros críticos. NÃO FORMATAR." "ERROR"
        $ExitCode = 2
    } else {
        Write-Log "Execução sem erros críticos registrados." "OK"
        $ExitCode = 0
    }

} catch {

    Add-ErrorRecord `
        "FATAL" `
        $RepoRoot `
        $_.Exception.Message `
        $true

    try {
        Write-FinalSummary | Out-Null
    } catch {}

    $ExitCode = 3

} finally {

    try {
        $InventoryWriter.Flush()
        $InventoryWriter.Dispose()
    } catch {}

    try {
        $TransferWriter.Flush()
        $TransferWriter.Dispose()
    } catch {}

    try {
        $ArtifactWriter.Flush()
        $ArtifactWriter.Dispose()
    } catch {}

    try {
        if ($DiskInventoryWriter) {
            $DiskInventoryWriter.Flush()
            $DiskInventoryWriter.Dispose()
        }
    } catch {}

    try {
        $ImportantWriter.Flush()
        $ImportantWriter.Dispose()
    } catch {}

    try {
        $LargeWriter.Flush()
        $LargeWriter.Dispose()
    } catch {}

    try {
        Stop-Transcript | Out-Null
    } catch {}

    # _TEMP só deve conter staging descartável.
    try {
        Get-ChildItem `
            -LiteralPath $TempRoot `
            -Force `
            -ErrorAction SilentlyContinue |
            Remove-Item `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
    } catch {}
}

exit $ExitCode
