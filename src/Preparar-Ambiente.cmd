@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Preparacao de Ambiente - Monitoramento de Servidor

REM =====================================================================
REM  PREPARACAO DE AMBIENTE - MONITORAMENTO DE SERVIDOR WINDOWS
REM  Libera o firewall e aplica os requisitos para o monitor funcionar.
REM  EXECUTE COMO ADMINISTRADOR (botao direito > Executar como admin).
REM =====================================================================

REM --- Verificar privilegio de administrador ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo.
    echo [ERRO] Este arquivo precisa ser executado como ADMINISTRADOR.
    echo        Clique com o botao direito e escolha "Executar como administrador".
    echo.
    pause
    exit /b 1
)

set "PS64=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PS32=%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"

echo =====================================================================
echo  PREPARACAO DE AMBIENTE - MONITORAMENTO
echo =====================================================================
echo.

REM --- [1/6] Criar pastas ---
echo [1/6] Criando pastas...
if not exist "C:\Monitoramento"      mkdir "C:\Monitoramento"
if not exist "C:\Monitoramento\logs" mkdir "C:\Monitoramento\logs"

REM --- [2/6] Firewall: saida HTTPS 443 para o PowerShell (Telegram) ---
echo [2/6] Liberando firewall de saida (HTTPS 443 para api.telegram.org)...
netsh advfirewall firewall delete rule name="Monitoramento - Telegram HTTPS (PS64)" >nul 2>&1
netsh advfirewall firewall add rule name="Monitoramento - Telegram HTTPS (PS64)" dir=out action=allow program="%PS64%" protocol=TCP remoteport=443 enable=yes profile=any >nul
netsh advfirewall firewall delete rule name="Monitoramento - Telegram HTTPS (PS32)" >nul 2>&1
netsh advfirewall firewall add rule name="Monitoramento - Telegram HTTPS (PS32)" dir=out action=allow program="%PS32%" protocol=TCP remoteport=443 enable=yes profile=any >nul

REM --- [3/6] Firewall: saida ICMP (OPCIONAL - so para diagnostico via ping) ---
REM O monitor NAO depende mais de ICMP (a checagem de conectividade usa TCP 443).
REM Esta regra ajuda apenas se o admin quiser usar "ping" manualmente. Pode remover.
echo [3/6] (Opcional) Liberando ICMP echo de saida para diagnostico manual...
netsh advfirewall firewall delete rule name="Monitoramento - ICMP Echo Out" >nul 2>&1
netsh advfirewall firewall add rule name="Monitoramento - ICMP Echo Out" dir=out action=allow protocol=icmpv4:8,any enable=yes profile=any >nul

REM --- [4/6] TLS 1.2 forte no .NET (necessario em Server 2012R2/2016) ---
echo [4/6] Habilitando TLS 1.2 forte no .NET Framework...
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f >nul 2>&1

REM --- [5/6] Politica de execucao (a tarefa ja usa Bypass; isto ajuda no manual) ---
echo [5/6] Ajustando ExecutionPolicy (LocalMachine = RemoteSigned)...
"%PS64%" -NoProfile -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force" >nul 2>&1

REM --- [6/6] Verificar conectividade real com o Telegram ---
echo [6/6] Testando conectividade com api.telegram.org:443...
"%PS64%" -NoProfile -Command "try { $r = Test-NetConnection api.telegram.org -Port 443 -WarningAction SilentlyContinue; if ($r.TcpTestSucceeded) { Write-Host '      RESULTADO: OK (porta 443 acessivel)' } else { Write-Host '      RESULTADO: FALHOU (verifique proxy/firewall de borda)' } } catch { Write-Host '      RESULTADO: ERRO no teste de conectividade' }"

echo.
echo =====================================================================
echo  Deseja configurar agora o Token e o Chat ID do Telegram?
echo  (eles serao gravados como variaveis de maquina) [S/N]
echo =====================================================================
set "RESP="
set /p RESP=Resposta: 
if /I "!RESP!"=="S" (
    set "TGTOKEN="
    set "TGCHAT="
    set /p TGTOKEN=Cole o TOKEN do bot: 
    set /p TGCHAT=Cole o CHAT ID: 
    if not "!TGTOKEN!"=="" setx /M MONITOR_TG_TOKEN "!TGTOKEN!" >nul
    if not "!TGCHAT!"==""  setx /M MONITOR_TG_CHATID "!TGCHAT!" >nul
    echo.
    echo Token/Chat ID gravados. Pode ser necessario reiniciar o servidor
    echo (ou o servico Agendador de Tarefas) para a tarefa enxergar os valores.
)

echo.
echo =====================================================================
echo  CONCLUIDO. PROXIMOS PASSOS:
echo   1) Instalar a tarefa (PowerShell como Administrador):
echo        cd C:\Monitoramento
echo        .\Install-Monitor.ps1 -Install
echo   2) Testar o envio:
echo        .\Install-Monitor.ps1 -Test
echo.
echo  Para REMOVER as regras de firewall criadas por este script:
echo    netsh advfirewall firewall delete rule name="Monitoramento - Telegram HTTPS (PS64)"
echo    netsh advfirewall firewall delete rule name="Monitoramento - Telegram HTTPS (PS32)"
echo    netsh advfirewall firewall delete rule name="Monitoramento - ICMP Echo Out"
echo =====================================================================
echo.
pause
endlocal
