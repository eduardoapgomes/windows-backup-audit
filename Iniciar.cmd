@echo off
setlocal
cd /d "%~dp0"
:menu
cls
echo WINDOWS BACKUP - escolha uma opcao
 echo 1. Configurar pastas de origem (primeiro uso)
 echo 2. Auditar - comparar arquivos e gerar relatorio
 echo 3. Fazer backup - copiar e verificar arquivos
 echo 4. Abrir documentacao
 echo 5. Editar configuracao existente
 echo 0. Sair
choice /c 123450 /n /m "Opcao: "
if errorlevel 6 exit /b 0
if errorlevel 5 goto editar
if errorlevel 4 goto docs
if errorlevel 3 goto backup
if errorlevel 2 goto audit
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Setup
goto resultado
:audit
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Mode Audit -SelectDestination -OpenReport
goto resultado
:backup
echo Revise a auditoria antes de copiar. Selecione a mesma pasta do backup parcial.
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Mode Backup -SelectDestination -OpenReport
goto resultado
:docs
start "" "https://github.com/eduardoapgomes/windows-backup-audit#readme"
goto menu
:editar
if not exist "%~dp0backup.local.json" goto ausente
notepad.exe "%~dp0backup.local.json"
goto menu
:ausente
echo Use a opcao 1 para criar sua configuracao.
pause
goto menu
:resultado
if errorlevel 1 (echo A operacao nao foi concluida. Leia a mensagem acima.) else (echo Operacao concluida.)
pause
goto menu
