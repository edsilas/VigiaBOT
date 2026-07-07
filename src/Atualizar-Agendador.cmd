@echo off
setlocal EnableExtensions
title Atualizar Agendador - Monitoramento + Bot

REM =====================================================================
REM  ATUALIZA O AGENDADOR APOS VOCE SUBSTITUIR OS ARQUIVOS NA PASTA.
REM  - Re-registra a tarefa de monitoramento (a cada 5 min)
REM  - Re-registra/cria a tarefa do bot (inicia no boot) e a reinicia
REM  - Detecta PowerShell 7 (pwsh); se nao houver, usa o Windows PowerShell
REM  EXECUTE COMO ADMINISTRADOR. Nao copia arquivos (voce ja substituiu).
REM =====================================================================

REM --- Verifica privilegio de administrador ---
net session >nul 2>&1
if not errorlevel 1 goto :ADMIN_OK
echo.
echo [ERRO] Execute este arquivo como ADMINISTRADOR.
echo        Clique com o botao direito ^> Executar como administrador.
echo.
pause
exit /b 1
:ADMIN_OK

set "DIR=C:\Monitoramento"
set "MON=%DIR%\Monitor.ps1"
set "BOT=%DIR%\Monitor-Bot.ps1"
set "TASK_MON=MonitoramentoServidor"
set "TASK_BOT=MonitoramentoBotTelegram"

REM --- Confirma que o Monitor.ps1 esta na pasta ---
if exist "%MON%" goto :MON_OK
echo [ERRO] Nao encontrei: %MON%
echo        Substitua/coloque os arquivos novos em %DIR% e rode de novo.
pause
exit /b 1
:MON_OK

REM --- Detecta runtime: PowerShell 7 (pwsh), senao Windows PowerShell ---
set "RT=C:\Program Files\PowerShell\7\pwsh.exe"
if exist "%RT%" goto :RT_OK
for /f "delims=" %%i in ('where pwsh 2^>nul') do set "RT=%%i"
if exist "%RT%" goto :RT_OK
set "RT=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
:RT_OK
echo Runtime escolhido: %RT%
echo.

REM --- Atualiza a tarefa de MONITORAMENTO (a cada 5 minutos) ---
echo Atualizando tarefa de monitoramento "%TASK_MON%"...
schtasks /Create /TN "%TASK_MON%" /TR "\"%RT%\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%MON%\"" /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F
if not errorlevel 1 goto :MON_DONE
echo [ERRO] Falha ao atualizar a tarefa de monitoramento. Veja a mensagem acima.
pause
exit /b 1
:MON_DONE
schtasks /Run /TN "%TASK_MON%" >nul 2>&1
echo Monitoramento atualizado e disparado para validacao.
echo.

REM --- Atualiza/cria a tarefa do BOT (apenas se o arquivo existir) ---
if not exist "%BOT%" goto :SKIP_BOT
echo Parando o bot atual, se estiver rodando...
schtasks /End /TN "%TASK_BOT%" >nul 2>&1
timeout /t 2 /nobreak >nul
echo Atualizando tarefa do bot "%TASK_BOT%"...
schtasks /Create /TN "%TASK_BOT%" /TR "\"%RT%\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%BOT%\"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F
schtasks /Run /TN "%TASK_BOT%" >nul 2>&1
echo Bot atualizado e iniciado.
goto :AFTER_BOT
:SKIP_BOT
echo [INFO] %BOT% nao encontrado - etapa do bot ignorada.
:AFTER_BOT

echo.
echo =====================================================================
echo  ATUALIZACAO CONCLUIDA.
echo.
echo  Conferir o monitoramento (aguarde ~10s):
echo    powershell -Command "Get-Content C:\Monitoramento\logs\monitor.log -Tail 12"
echo  Conferir o bot:
echo    powershell -Command "Get-Content C:\Monitoramento\logs\bot.log -Tail 15"
echo  Testar o bot no Telegram:  /help   e   /status
echo.
echo  OBS 1: a tarefa de monitoramento foi recriada como "a cada 5 min".
echo         Se voce usava o XML com "reiniciar em caso de falha", pode
echo         reimportar o XML depois, se desejar esse extra.
echo  OBS 2: confirme que Token e Chat ID estao certos nos arquivos .ps1
echo         (ou nas variaveis de maquina) antes de validar.
echo =====================================================================
echo.
pause
endlocal
