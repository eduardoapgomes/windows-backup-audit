@echo off
setlocal
cd /d "%~dp0"
:menu
cls
echo BACKUP DE DADOS - escolha uma opcao
echo.
echo 1. VER PLANO DE PASTAS (rapido; sem USB e sem hashes)
echo 2. AUDITAR pastas selecionadas (compara arquivos; precisa de USB)
echo 3. FAZER BACKUP (copia e verifica; precisa de USB)
echo 4. Selecionar minhas pastas manualmente
echo 5. Auditar pastas manuais
echo 6. Fazer backup das pastas manuais
echo 7. Abrir guia no GitHub
echo 8. Mapa visual opcional (Python)
echo 9. Editar configuracao manual
echo 0. Sair
choice /c 1234567890 /n /m "Opcao: "
if errorlevel 10 exit /b 0
if errorlevel 9 goto editar
if errorlevel 8 goto catalogo
if errorlevel 7 goto docs
if errorlevel 6 goto manualbackup
if errorlevel 5 goto manualaudit
if errorlevel 4 goto setup
if errorlevel 3 goto backup
if errorlevel 2 goto audit
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Mode Plan -AutoDiscover
goto resultado
:audit
powershell.exe -NoProfile -STA -File "%~dp0Backup.ps1" -Mode Audit -AutoDiscover -SelectDestination -OpenReport
goto resultado
:backup
echo Revise as pastas do plano e selecione o mesmo destino usado na auditoria.
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
echo Use a opcao 4 para criar sua configuracao manual.
pause
goto menu
:resultado
if errorlevel 1 (echo A operacao nao foi concluida. Leia a mensagem acima e o relatorio indicado.) else (echo Operacao concluida.)
pause
goto menu
