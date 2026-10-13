@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Windows Backup Audit
set "SAIDA=0"

:menu
cls
echo ==============================================================
echo   WINDOWS BACKUP AUDIT  -  backup para HD externo
echo   Nunca apaga arquivos. Cada copia e conferida por SHA-256.
echo ==============================================================
echo.
if not exist "%~dp0configuracao.txt" (
    echo   PRIMEIRO USO: conecte o HD externo e escolha 4 - Configurar.
    echo.
)
echo   1. Fazer backup agora
echo   2. Simular  (mostra o que sera copiado, nao grava nada)
echo   3. Verificar integridade do backup  (rele o HD)
echo   4. Configurar pastas e HD de destino
echo   5. Agendar backup automatico
echo   6. Abrir o ultimo relatorio
echo   7. Guia rapido
echo   0. Sair
echo.
choice /c 12345670 /n /m "Escolha uma opcao: "
set "OPCAO=%ERRORLEVEL%"
if "%OPCAO%"=="8" exit /b 0
if "%OPCAO%"=="7" goto guia
if "%OPCAO%"=="1" call :executar -Acao Backup
if "%OPCAO%"=="2" call :executar -Acao Simular
if "%OPCAO%"=="3" call :executar -Acao Verificar
if "%OPCAO%"=="4" call :executar -Acao Configurar
if "%OPCAO%"=="5" call :executar -Acao Agendar
if "%OPCAO%"=="6" call :executar -Acao Relatorio
echo.
if "%SAIDA%"=="0" echo   Concluido.
if "%SAIDA%"=="1" echo   AVISO: concluido com avisos. Veja o relatorio.
if "%SAIDA%"=="2" echo   ATENCAO: ha erros ou a execucao foi interrompida. Veja o relatorio.
if "%SAIDA%"=="3" echo   NAO EXECUTADO: leia a mensagem acima. Nada foi copiado.
echo.
pause
goto menu

:guia
if exist "%~dp0docs\GUIA-RAPIDO.md" (
    start "" notepad.exe "%~dp0docs\GUIA-RAPIDO.md"
) else (
    start "" "https://github.com/eduardoapgomes/windows-backup-audit/blob/main/docs/GUIA-RAPIDO.md"
)
goto menu

:executar
set "SAIDA=3"
for %%F in ("Backup.ps1" "src\Backup.Core.psm1" "src\Nativo.cs") do (
    if not exist "%~dp0%%~F" (
        echo.
        echo   ERRO: o arquivo %%~F nao foi encontrado em "%~dp0".
        echo   A instalacao esta incompleta. Extraia o ZIP inteiro em uma pasta nova
        echo   ou use Atualizar.cmd. Veja docs\ATUALIZAR.md. Nada foi feito.
        exit /b 3
    )
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Backup.ps1" %*
set "SAIDA=%ERRORLEVEL%"
exit /b %SAIDA%
