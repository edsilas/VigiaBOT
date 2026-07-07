@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Agendar Bot de Comandos do Telegram

REM =====================================================================
REM  AGENDA O BOT DE COMANDOS DO TELEGRAM (Monitor-Bot.ps1)
REM  Cria a tarefa que mantem o bot rodando (inicia no boot do servidor)
REM  e o inicia agora. EXECUTE COMO ADMINISTRADOR.
REM =====================================================================

REM --- Verifica privilegio de administrador ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo.
    echo [ERRO] Execute este arquivo como ADMINISTRADOR.
    echo        Clique com o botao direito ^> Executar como administrador.
    echo.
    pause
    exit /b 1
)

set "BOTSCRIPT=C:\Monitoramento\Monitor-Bot.ps1"
set "TASKNAME=MonitoramentoBotTelegram"

REM --- Confirma que o script do bot existe ---
if not exist "%BOTSCRIPT%" (
    echo [ERRO] Nao encontrei: %BOTSCRIPT%
    echo        Coloque o Monitor-Bot.ps1 em C:\Monitoramento e rode de novo.
    pause
    exit /b 1
)

REM --- Localiza o PowerShell 7 (pwsh.exe) ---
set "PWSH=C:\Program Files\PowerShell\7\pwsh.exe"
if not exist "%PWSH%" (
    for /f "delims=" %%i in ('where pwsh 2^>nul') do set "PWSH=%%i"
)
if not exist "%PWSH%" (
    echo [ERRO] PowerShell 7 ^(pwsh.exe^) nao encontrado.
    echo        Instale o PowerShell 7 ou ajuste o caminho neste arquivo.
    pause
    exit /b 1
)
echo Runtime do bot: %PWSH%

REM --- (Opcional) configurar o TOKEN do Telegram ---
echo.
echo Deseja configurar agora o TOKEN do bot (variavel de maquina)? [S/N]
set "RESP="
set /p RESP=Resposta: 
if /I "!RESP!"=="S" (
    set "TGTOKEN="
    set /p TGTOKEN=Cole o TOKEN do bot: 
    if not "!TGTOKEN!"=="" setx /M MONITOR_TG_TOKEN "!TGTOKEN!" >nul
    echo Token gravado como variavel de maquina.
)

REM --- Cria a tarefa: roda no boot, como SYSTEM, privilegios maximos ---
echo.
echo Criando a tarefa "%TASKNAME%"...
schtasks /Create /TN "%TASKNAME%" /TR "\"%PWSH%\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%BOTSCRIPT%\"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F
if %errorlevel% NEQ 0 (
    echo.
    echo [ERRO] Falha ao criar a tarefa. Veja a mensagem acima.
    pause
    exit /b 1
)

REM --- Inicia o bot agora ---
echo Iniciando o bot...
schtasks /Run /TN "%TASKNAME%"

echo.
echo =====================================================================
echo  PRONTO. O bot esta agendado e em execucao.
echo.
echo  TESTE: no Telegram, mande  /help  para o seu bot.
echo  Ver atividade do bot:   type C:\Monitoramento\logs\bot.log
echo  Conferir a tarefa:      schtasks /Query /TN "%TASKNAME%"
echo  Remover o bot:          schtasks /Delete /TN "%TASKNAME%" /F
echo =====================================================================
echo.
echo  OBS: nao abra o getUpdates no navegador enquanto o bot roda
echo       (causaria conflito 409 no Telegram).
echo.
pause
endlocal
