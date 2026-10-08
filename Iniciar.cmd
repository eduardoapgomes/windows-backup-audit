@echo off
setlocal
cd /d "%~dp0"
:menu
cls
echo WINDOWS BACKUP - escolha uma opcao
 echo 1. AUDITORIA AUTOMATICA - descobrir dados e comparar
 echo 2. BACKUP AUTOMATICO - descobrir, copiar e verificar
 echo 3. Configurar pastas manualmente (primeiro uso manual)
 echo 4. Auditoria das pastas da configuracao manual
 echo 5. Backup das pastas da configuracao manual
 echo 6. Abrir documentacao
 echo 7. Editar configuracao manual existente
 echo 8. Mapa visual e agrupamentos (Python; pode acompanhar auditoria)
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
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Mode Audit -AutoDiscover -SelectDestination -OpenReport
goto resultado
:backup
echo Use a mesma pasta de destino da auditoria automatica revisada.
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Mode Backup -AutoDiscover -SelectDestination -OpenReport
goto resultado
:setup
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Setup
goto resultado
:manualaudit
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Mode Audit -SelectDestination -OpenReport
goto resultado
:manualbackup
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Mode Backup -SelectDestination -OpenReport
goto resultado
:docs
start "" "https://github.com/eduardoapgomes/windows-backup-audit#readme"
goto menu
:catalogo
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
if errorlevel 1 (echo A operacao nao foi concluida. Leia a mensagem acima e o relatorio indicado.) else (echo Operacao concluida.)
pause
goto menu
