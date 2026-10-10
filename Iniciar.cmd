@echo off
setlocal EnableExtensions
cd /d "%~dp0"
:menu
cls
echo WINDOWS BACKUP - escolha uma opcao
echo.
echo PRIMEIRO USO: 1 confere sem copiar; depois 2 faz o backup.
echo Para escolher apenas algumas pastas, use 3, 4 e 5.
echo.
echo 1. AUDITORIA FOCADA - revisar dados importantes (recomendado)
echo 2. BACKUP FOCADO - copiar e verificar apos revisar
echo 3. Configurar pastas manualmente (primeiro uso manual)
echo 4. Auditoria das pastas da configuracao manual
echo 5. Backup das pastas da configuracao manual
echo 6. Abrir guia rapido de uso
echo 7. Editar configuracao manual existente
echo 8. Mapa opcional de pastas (Python; somente leitura)
echo 0. Sair
choice /c 123456780 /n /m "Opcao: "
if errorlevel 9 exit /b 0
if errorlevel 8 goto catalogo
if errorlevel 7 goto editar
if errorlevel 6 goto docs
if errorlevel 5 goto manualbackup
if errorlevel 4 goto manualaudit
if errorlevel 3 goto setup
if errorlevel 2 goto backup
call :executar_backup -Mode Audit -AutoDiscover -SelectDestination -OpenReport
set "BACKUP_EXIT=%ERRORLEVEL%"
goto resultado
:backup
echo Use a mesma pasta de destino da auditoria automatica revisada.
call :executar_backup -Mode Backup -AutoDiscover -SelectDestination -OpenReport
set "BACKUP_EXIT=%ERRORLEVEL%"
goto resultado
:setup
call :executar_backup -Setup
set "BACKUP_EXIT=%ERRORLEVEL%"
goto resultado
:manualaudit
call :executar_backup -Mode Audit -SelectDestination -OpenReport
set "BACKUP_EXIT=%ERRORLEVEL%"
goto resultado
:manualbackup
call :executar_backup -Mode Backup -SelectDestination -OpenReport
set "BACKUP_EXIT=%ERRORLEVEL%"
goto resultado
:docs
if exist "%~dp0docs\GUIA-RAPIDO.md" (
    start "" notepad.exe "%~dp0docs\GUIA-RAPIDO.md"
) else (
    start "" "https://github.com/eduardoapgomes/windows-backup-audit#readme"
)
goto menu
:catalogo
if not exist "%~dp0Organizar.ps1" (
    echo ERRO: Organizar.ps1 nao foi encontrado na pasta do menu.
    echo Extraia ou restaure o projeto completo.
    pause
    goto menu
)
start "Mapa dos arquivos" powershell.exe -NoProfile -STA -NoExit -File "%~dp0Organizar.ps1" -Watch
goto menu
:editar
if not exist "%~dp0backup.local.json" goto ausente
notepad.exe "%~dp0backup.local.json"
goto menu
:ausente
echo Use a opcao 3 para criar sua configuracao manual.
pause
goto menu
:resultado
if "%BACKUP_EXIT%"=="0" (
    echo Comando executado sem erro reportado. Confira a configuracao ou o relatorio.
) else (
    echo.
    echo FALHA: a operacao nao foi concluida. Codigo de saida: %BACKUP_EXIT%.
    echo Leia a mensagem acima. Se houver relatorio, confira as pendencias.
)
pause
goto menu

:executar_backup
if not exist "%~dp0Backup.ps1" (
    echo.
    echo ERRO: Backup.ps1 nao foi encontrado na mesma pasta que Iniciar.cmd.
    echo Pasta do programa: "%~dp0"
    echo Extraia o ZIP completo ou restaure os arquivos do repositorio Git.
    echo Nenhuma configuracao, auditoria ou copia foi iniciada.
    exit /b 2
)
if not exist "%~dp0src\Backup.Core.psm1" (
    echo.
    echo ERRO: src\Backup.Core.psm1 nao foi encontrado.
    echo O projeto esta incompleto. Extraia ou restaure a pasta src.
    echo Nenhuma configuracao, auditoria ou copia foi iniciada.
    exit /b 2
)
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" %*
exit /b %ERRORLEVEL%
