@echo off
setlocal EnableExtensions
title VigiaBOT - Assistente de Implantacao

REM =====================================================================
REM  VigiaBOT - Copyright (c) 2026 Edsilas - Licenca Apache 2.0
REM  ATALHO DE DUPLO-CLIQUE PARA O ASSISTENTE (Launcher-Monitoramento.ps1)
REM  - Solicita privilegios de Administrador automaticamente (UAC).
REM  - Detecta PowerShell 7 (pwsh); se nao houver, usa o Windows PowerShell.
REM  - Roda com -ExecutionPolicy Bypass (nao exige liberar scripts antes).
REM =====================================================================

REM --- Autoelevacao: se nao for admin, reabre este .cmd elevado ---
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Solicitando privilegios de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

set "HERE=%~dp0"
set "LAUNCHER=%HERE%Launcher-Monitoramento.ps1"

if not exist "%LAUNCHER%" (
    echo [ERRO] Nao encontrei o Launcher-Monitoramento.ps1 nesta pasta:
    echo        %HERE%
    echo        Deixe o .cmd e o .ps1 na MESMA pasta e tente de novo.
    pause
    exit /b 1
)

REM --- Escolhe o runtime: PowerShell 7 (pwsh) se existir, senao 5.1 ---
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "C:\Program Files\PowerShell\7\pwsh.exe" set "PS=C:\Program Files\PowerShell\7\pwsh.exe"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" %*

endlocal
