#Requires -Version 5.1
<#
.SYNOPSIS
Sai de todas as contas deste usuário do Windows antes de outra pessoa usar o PC.

.DESCRIPTION
Apaga os dados de login, não os seus arquivos:
  - navegadores Chrome, Edge, Brave, Vivaldi, Opera e Firefox: todos os perfis, com
    sessões, cookies, senhas salvas, histórico, favoritos e extensões;
  - credenciais guardadas no Windows (Gerenciador de Credenciais): Git, Office,
    VS Code, Teams, OneDrive e outras;
  - contas do Office e de apps da Microsoft neste usuário;
  - sessões do WhatsApp, Telegram, Discord, Slack e Teams;
  - tokens de ferramentas de desenvolvimento (git, gh, Docker, AWS, Azure, npm, PyPI,
    Kaggle, Hugging Face).
Documentos, fotos, C:\Dados, a pasta do OneDrive e os demais arquivos NÃO são tocados.
O OneDrive e a conta do Windows pedem alguns cliques; no fim o script mostra onde.

Sem -Executar, só mostra o que seria apagado. Nada muda.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\ferramentas\Sair-de-tudo.ps1
Mostra o que seria apagado.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\ferramentas\Sair-de-tudo.ps1 -Executar
Apaga (pede confirmação antes).
#>
[CmdletBinding()]
param(
    [switch]$Executar,
    [switch]$SemPerguntar,        # não pede confirmação (para testes)
    [switch]$ManterCredenciais    # não mexe no Gerenciador de Credenciais (para testes)
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$local = $env:LOCALAPPDATA
$roaming = $env:APPDATA
$perfil = $env:USERPROFILE

if (-not ('SairDeTudo.Credenciais' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace SairDeTudo {
    public static class Credenciais {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct CREDENTIAL {
            public uint Flags; public uint Type; public IntPtr TargetName; public IntPtr Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint CredentialBlobSize; public IntPtr CredentialBlob; public uint Persist;
            public uint AttributeCount; public IntPtr Attributes; public IntPtr TargetAlias; public IntPtr UserName;
        }
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredEnumerateW(string filtro, uint opcoes, out uint quantas, out IntPtr lista);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDeleteW(string alvo, uint tipo, uint opcoes);
        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr p);

        /// <summary>Credenciais do usuário: { alvo, tipo, usuário }.</summary>
        public static List<string[]> Listar() {
            List<string[]> res = new List<string[]>();
            uint n; IntPtr p;
            if (!CredEnumerateW(null, 1, out n, out p)) return res;   // 1 = CRED_ENUMERATE_ALL_CREDENTIALS
            try {
                for (int i = 0; i < n; i++) {
                    IntPtr c = Marshal.ReadIntPtr(p, i * IntPtr.Size);
                    CREDENTIAL cr = (CREDENTIAL)Marshal.PtrToStructure(c, typeof(CREDENTIAL));
                    string usuario = cr.UserName == IntPtr.Zero ? "" : Marshal.PtrToStringUni(cr.UserName);
                    res.Add(new string[] { Marshal.PtrToStringUni(cr.TargetName), cr.Type.ToString(), usuario });
                }
            } finally { CredFree(p); }
            return res;
        }

        public static bool Apagar(string alvo, uint tipo) { return CredDeleteW(alvo, tipo, 0); }
    }
}
'@
}

function New-Item2([string]$Grupo, [string]$Nome, [string]$Caminho) {
    [pscustomobject]@{ Grupo = $Grupo; Nome = $Nome; Caminho = $Caminho }
}

# ------------------------------------------------------------------ o que apagar
$candidatos = New-Object 'Collections.Generic.List[object]'
foreach ($i in @(
        (New-Item2 'Navegadores' 'Google Chrome' (Join-Path $local 'Google\Chrome\User Data')),
        (New-Item2 'Navegadores' 'Microsoft Edge' (Join-Path $local 'Microsoft\Edge\User Data')),
        (New-Item2 'Navegadores' 'Brave' (Join-Path $local 'BraveSoftware\Brave-Browser\User Data')),
        (New-Item2 'Navegadores' 'Vivaldi' (Join-Path $local 'Vivaldi\User Data')),
        (New-Item2 'Navegadores' 'Opera' (Join-Path $roaming 'Opera Software')),
        (New-Item2 'Navegadores' 'Opera (cache)' (Join-Path $local 'Opera Software')),
        (New-Item2 'Navegadores' 'Firefox' (Join-Path $roaming 'Mozilla\Firefox')),
        (New-Item2 'Navegadores' 'Firefox (cache)' (Join-Path $local 'Mozilla\Firefox')),
        (New-Item2 'Microsoft e Office' 'Contas do Office' 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity'),
        (New-Item2 'Microsoft e Office' 'Cache de identidade' (Join-Path $local 'Microsoft\IdentityCache')),
        (New-Item2 'Microsoft e Office' 'OneAuth' (Join-Path $local 'Microsoft\OneAuth')),
        (New-Item2 'Mensagens' 'Teams (clássico)' (Join-Path $roaming 'Microsoft\Teams')),
        (New-Item2 'Mensagens' 'Telegram' (Join-Path $roaming 'Telegram Desktop\tdata')),
        (New-Item2 'Mensagens' 'Discord' (Join-Path $roaming 'discord')),
        (New-Item2 'Mensagens' 'Slack' (Join-Path $roaming 'Slack')),
        (New-Item2 'Desenvolvimento' 'Git (senhas em texto)' (Join-Path $perfil '.git-credentials')),
        (New-Item2 'Desenvolvimento' 'GitHub CLI' (Join-Path $roaming 'GitHub CLI\hosts.yml')),
        (New-Item2 'Desenvolvimento' 'GitHub CLI' (Join-Path $perfil '.config\gh\hosts.yml')),
        (New-Item2 'Desenvolvimento' 'Docker' (Join-Path $perfil '.docker\config.json')),
        (New-Item2 'Desenvolvimento' 'AWS' (Join-Path $perfil '.aws\credentials')),
        (New-Item2 'Desenvolvimento' 'Azure' (Join-Path $perfil '.azure')),
        (New-Item2 'Desenvolvimento' 'npm' (Join-Path $perfil '.npmrc')),
        (New-Item2 'Desenvolvimento' 'PyPI' (Join-Path $perfil '.pypirc')),
        (New-Item2 'Desenvolvimento' 'Kaggle' (Join-Path $perfil '.kaggle\kaggle.json')),
        (New-Item2 'Desenvolvimento' 'Hugging Face' (Join-Path $perfil '.cache\huggingface\token')),
        (New-Item2 'Desenvolvimento' 'Hugging Face' (Join-Path $perfil '.huggingface\token')),
        (New-Item2 'Desenvolvimento' 'netrc' (Join-Path $perfil '_netrc')),
        (New-Item2 'Desenvolvimento' 'netrc' (Join-Path $perfil '.netrc')))) {
    $candidatos.Add($i)
}
$pacotes = Join-Path $local 'Packages'
foreach ($p in @(Get-ChildItem -LiteralPath $pacotes -Directory -ErrorAction SilentlyContinue)) {
    if ($p.Name -like '*WhatsAppDesktop*') { $candidatos.Add((New-Item2 'Mensagens' 'WhatsApp' (Join-Path $p.FullName 'LocalState'))) }
    if ($p.Name -like 'MSTeams_*') { $candidatos.Add((New-Item2 'Mensagens' 'Teams' (Join-Path $p.FullName 'LocalCache'))) }
}
$itens = @($candidatos | Where-Object { Test-Path -LiteralPath $_.Caminho })

$credenciais = @()
if (-not $ManterCredenciais) { $credenciais = @([SairDeTudo.Credenciais]::Listar()) }
$cofreWeb = $null
if (-not $ManterCredenciais) {
    try {
        # Credenciais da Web (só no Windows PowerShell 5.1).
        $null = [Windows.Security.Credentials.PasswordVault, Windows.Security.Credentials, ContentType = WindowsRuntime]
        $cofreWeb = New-Object Windows.Security.Credentials.PasswordVault
    } catch { $cofreWeb = $null }
}
$senhasWeb = @()
if ($null -ne $cofreWeb) { try { $senhasWeb = @($cofreWeb.RetrieveAll()) } catch { $senhasWeb = @() } }

# Programas que guardam sessão aberta: precisam estar fechados.
$office = @('WINWORD', 'EXCEL', 'POWERPNT', 'OUTLOOK', 'ONENOTE', 'MSACCESS', 'VISIO', 'WINPROJ')
$outros = @('chrome', 'msedge', 'brave', 'vivaldi', 'opera', 'firefox', 'OneDrive', 'Teams', 'ms-teams', 'Telegram',
    'Discord', 'slack', 'Code', 'WhatsApp*')
function Get-Abertos([string[]]$Nomes) {
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $n = $_.ProcessName
            @($Nomes | Where-Object { $n -like $_ }).Count -gt 0
        })
}

# ------------------------------------------------------------------ relatório
$modo = if ($Executar) { 'EXECUÇÃO' } else { 'SIMULAÇÃO: nada será apagado' }
Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host " SAIR DE TUDO - $modo" -ForegroundColor Cyan
Write-Host " Usuário do Windows: $env:USERNAME   (seus arquivos não são tocados)" -ForegroundColor Cyan
Write-Host ('=' * 72) -ForegroundColor Cyan
foreach ($g in ($itens | Group-Object Grupo)) {
    Write-Host ''
    Write-Host " $($g.Name):" -ForegroundColor White
    foreach ($i in $g.Group) { Write-Host ("   {0,-24} {1}" -f $i.Nome, $i.Caminho) }
}
if (-not $itens.Count) { Write-Host ''; Write-Host ' Nenhum dado de navegador ou de aplicativo encontrado.' }
if (-not $ManterCredenciais) {
    Write-Host ''
    Write-Host (" Credenciais do Windows: {0}   Credenciais da Web: {1}" -f $credenciais.Count, $senhasWeb.Count) -ForegroundColor White
    foreach ($c in @($credenciais | Select-Object -First 25)) { Write-Host ("   {0}" -f $c[0]) }
    if ($credenciais.Count -gt 25) { Write-Host ("   ... e mais {0}" -f ($credenciais.Count - 25)) }
}

function Show-PassosManuais {
    $conta = $null
    try { $conta = [string](Get-LocalUser -Name $env:USERNAME -ErrorAction Stop).PrincipalSource } catch { $conta = $null }
    Write-Host ''
    Write-Host ('-' * 72)
    Write-Host ' FALTA FAZER À MÃO (alguns cliques):' -ForegroundColor Yellow
    Write-Host ' 1. OneDrive: ícone da nuvem perto do relógio > engrenagem > Configurações > Conta >'
    Write-Host '    "Desvincular este PC". Os arquivos da pasta OneDrive ficam no PC; só param de sincronizar.'
    Write-Host ' 2. Configurações > Contas > Email e contas: remova as contas de "Contas usadas por outros aplicativos".'
    if ($conta -eq 'MicrosoftAccount') {
        Write-Host ' 3. Você entra no Windows com a conta Microsoft. Em Configurações > Contas > Suas informações,' -ForegroundColor Yellow
        Write-Host '    use "Entrar com uma conta local"; senão os apps da Microsoft voltam a entrar com o seu e-mail.' -ForegroundColor Yellow
    } else {
        Write-Host ' 3. (Você entra no Windows com uma conta local: nada a fazer aqui.)'
    }
    Write-Host ' 4. Crie uma conta só para a outra pessoa (Configurações > Contas > Outros usuários). Se o PC vai'
    Write-Host '    ficar com ela, a conta dela pode ser administradora; entrando por ela, apague a sua em'
    Write-Host '    Outros usuários > sua conta > Remover > "Excluir conta e dados". Isso leva junto toda a sua'
    Write-Host '    pasta de usuário. Se as duas contas continuarem, deixe a dela como PADRÃO e ponha senha na sua.'
    Write-Host ' 5. Na nuvem, que vale mais do que qualquer limpeza no PC:'
    Write-Host '    - Google: myaccount.google.com > Segurança > Seus dispositivos > este PC > Sair.'
    Write-Host '    - Microsoft: account.microsoft.com > Dispositivos > remova este PC.'
    Write-Host '    - WhatsApp e Telegram no celular: Aparelhos conectados / Dispositivos > desconecte o PC.'
    $sensiveis = @(
        (Join-Path $roaming 'Bitcoin\wallets'), (Join-Path $roaming 'Bisq'), (Join-Path $perfil '.rfb'),
        (Join-Path $perfil '.serpro'), (Join-Path $perfil '.receitanet'), 'C:\Dados\Imposto de Renda') |
        Where-Object { Test-Path -LiteralPath $_ }
    if ($sensiveis.Count) {
        Write-Host ''
        Write-Host ' CONTINUAM NO PC (você escolheu manter os arquivos; já estão no backup):' -ForegroundColor Yellow
        foreach ($s in $sensiveis) { Write-Host "   $s" }
        Write-Host '   Carteiras e dados do Imposto de Renda: quem usar a SUA conta ou for administrador consegue copiá-los.'
    }
    if (Test-Path -LiteralPath 'C:\Dados') {
        $abertos = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545')   # Todos, Usuários autenticados, Usuários
        $quem = @((Get-Acl -LiteralPath 'C:\Dados').Access | Where-Object {
                try { $abertos -contains $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $false }
            })
        if ($quem.Count) {
            Write-Host ''
            Write-Host ' C:\Dados pode ser lido por QUALQUER usuário deste PC. Para deixar só a sua conta:' -ForegroundColor Yellow
            Write-Host ('   icacls "C:\Dados" /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "{0}\{1}:(OI)(CI)F" /T /C /Q' -f $env:USERDOMAIN, $env:USERNAME)
        }
    }
    Write-Host ('-' * 72)
}

if (-not $Executar) {
    $aberto = @(Get-Abertos ($office + $outros))
    if ($aberto.Count) { Write-Host ''; Write-Host (" Abertos agora (serão fechados): {0}" -f ((@($aberto | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)) -join ', ')) }
    Show-PassosManuais
    Write-Host ''
    Write-Host ' SIMULAÇÃO: nada foi apagado. Para apagar, rode de novo com -Executar.' -ForegroundColor Cyan
    exit 0
}

# ------------------------------------------------------------------ execução
if (-not $SemPerguntar) {
    Write-Host ''
    Write-Host ' ANTES DE CONTINUAR:' -ForegroundColor Yellow
    Write-Host ' - Senhas e favoritos salvos nos navegadores serão APAGADOS deste PC. Confira se estão'
    Write-Host '   sincronizados na sua conta (Chrome: Google; Brave: código de sincronização) ou exporte-os'
    Write-Host '   direto para o HD externo, não para o PC.'
    Write-Host ' - Salve o que estiver aberto: navegadores, Teams, WhatsApp etc. serão fechados.'
    if ((Read-Host ' Digite APAGAR para continuar') -cne 'APAGAR') { Write-Host ' Cancelado. Nada foi apagado.'; exit 3 }
}

# Office com documento aberto: o usuário fecha (pode haver algo sem salvar).
$officeAberto = @(Get-Abertos $office)
foreach ($p in $officeAberto) { try { [void]$p.CloseMainWindow() } catch { Write-Verbose 'sem janela' } }
Start-Sleep -Seconds 5
if (@(Get-Abertos $office).Count) {
    Write-Host ' Word/Excel/PowerPoint/Outlook ainda estão abertos. Salve, feche e rode de novo. Nada foi apagado.' -ForegroundColor Red
    exit 3
}
foreach ($p in @(Get-Abertos $outros)) { try { [void]$p.CloseMainWindow() } catch { Write-Verbose 'sem janela' } }
Start-Sleep -Seconds 3
foreach ($p in @(Get-Abertos $outros)) { try { Stop-Process -Id $p.Id -Force } catch { Write-Verbose 'já fechado' } }
Start-Sleep -Seconds 2

$falhas = New-Object 'Collections.Generic.List[string]'
foreach ($i in $itens) {
    try {
        if ($i.Caminho -like 'HKCU:*') {
            Remove-Item -LiteralPath $i.Caminho -Recurse -Force
        } elseif (Test-Path -LiteralPath $i.Caminho -PathType Container) {
            # rd com \\?\ aceita caminhos longos, que o Remove-Item do PowerShell 5.1 não aceita.
            $null = & cmd.exe /d /c "rd /s /q `"\\?\$($i.Caminho)`"" 2>&1
        } else {
            Remove-Item -LiteralPath $i.Caminho -Force
        }
    } catch { Write-Verbose $_.Exception.Message }
    if (Test-Path -LiteralPath $i.Caminho) { $falhas.Add("$($i.Nome): $($i.Caminho)") }
    else { Write-Host ("   apagado  {0,-24} {1}" -f $i.Nome, $i.Caminho) -ForegroundColor Green }
}

$apagadas = 0
foreach ($c in $credenciais) {
    if ([SairDeTudo.Credenciais]::Apagar($c[0], [uint32]$c[1])) { $apagadas++ } else { $falhas.Add("credencial: $($c[0])") }
}
foreach ($s in $senhasWeb) { try { $cofreWeb.Remove($s); $apagadas++ } catch { $falhas.Add("credencial da Web: $($s.Resource)") } }
if (-not $ManterCredenciais) { Write-Host ("   apagadas  {0} credencial(is) do Windows" -f $apagadas) -ForegroundColor Green }

Show-PassosManuais
Write-Host ''
if ($falhas.Count) {
    Write-Host ' NÃO FOI POSSÍVEL APAGAR (algum programa ainda aberto?). Reinicie o PC e rode de novo:' -ForegroundColor Red
    foreach ($f in $falhas) { Write-Host "   $f" -ForegroundColor Red }
    exit 2
}
Write-Host ' PRONTO: navegadores, credenciais e sessões deste usuário foram apagados.' -ForegroundColor Green
exit 0
