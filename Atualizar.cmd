@echo off
setlocal EnableExtensions
rem Capturar antes de CALL :label: dentro da subrotina %%0 e o rotulo, nao o arquivo.
set "PROJECT_DIR=%~dp0"
call :atualizar
set "UPDATE_EXIT=%ERRORLEVEL%"
echo.
if /I not "%~1"=="--no-pause" pause
exit /b %UPDATE_EXIT%

:atualizar
cd /d "%PROJECT_DIR%"
if errorlevel 1 (
    echo ERRO: nao foi possivel abrir a pasta do programa.
    exit /b 2
)
echo.
echo WINDOWS BACKUP - atualizar o programa
echo Feche a auditoria e o backup antes de atualizar.
echo Esta operacao NAO altera arquivos no HD externo.
echo.
where git >nul 2>&1
if errorlevel 1 goto semgit
if not exist "%PROJECT_DIR%.git" goto zip

set "BRANCH="
for /f "delims=" %%B in ('git branch --show-current 2^>nul') do set "BRANCH=%%B"
if not defined BRANCH (
    echo ERRO: nao foi possivel identificar a branch Git atual.
    goto falha_git
)
if /I not "%BRANCH%"=="main" goto outra_branch

rem Nunca descartar alteracoes locais ou fazer merge automatico.
git diff --quiet
if errorlevel 1 goto alteracoes
git diff --cached --quiet
if errorlevel 1 goto alteracoes

echo Atualizando a branch main do repositorio origin...
git pull --ff-only origin main
if errorlevel 1 (
    echo ERRO: git pull --ff-only origin main falhou.
    goto falha_git
)
if not exist "%PROJECT_DIR%Backup.ps1" goto incompleto
if not exist "%PROJECT_DIR%src\Backup.Core.psm1" goto incompleto
echo.
echo ATUALIZADO: os arquivos principais estao presentes.
echo A configuracao backup.local.json e os backups no USB nao foram alterados.
echo Abra Iniciar.cmd para executar a auditoria.
exit /b 0

:outra_branch
echo ERRO: voce esta na branch "%BRANCH%", nao na main.
echo A atualizacao foi cancelada para nao misturar versoes.
echo Consulte docs\ATUALIZAR.md para voltar com seguranca a main.
exit /b 3

:alteracoes
echo ERRO: ha modificacoes locais em arquivos versionados.
echo Nada foi descartado. Consulte docs\ATUALIZAR.md.
exit /b 3

:semgit
echo Git nao foi encontrado neste computador.
goto zip

:zip
echo Esta pasta nao e um clone Git atualizavel automaticamente.
echo Baixe o ZIP da branch main e EXTRAIA EM OUTRA PASTA:
echo https://github.com/eduardoapgomes/windows-backup-audit/archive/refs/heads/main.zip
echo.
echo Nao misture arquivos de versoes diferentes.
echo Se usar configuracao manual, copie apenas backup.local.json para a pasta nova.
echo Nao mova nem apague backups ou relatorios do HD externo.
exit /b 2

:incompleto
echo ERRO: atualizacao terminou, mas arquivos essenciais estao ausentes.
echo Confira o repositorio e a instalacao. Nao execute o backup.
exit /b 2

:falha_git
echo ERRO: nao foi possivel atualizar. Nada foi apagado nem restaurado a forca.
echo Confira a conexao, a branch e as mensagens do Git.
exit /b 2
