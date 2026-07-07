<#
.SYNOPSIS
    Ouvinte de comandos do Telegram para o Monitoramento (somente leitura).
.DESCRIPTION
    Fica em long-polling no getUpdates do Telegram e responde a comandos
    SEGUROS, apenas para os Chat IDs autorizados. Nao executa comandos
    arbitrarios. Projetado para rodar como tarefa permanente (inicia no boot).

    Comandos: /status /check /log /servicos /disco /uptime /help

.NOTES
    Runtime recomendado: PowerShell 7 (pwsh). Locale-safe (WMI/CIM).
    Token: variavel de maquina MONITOR_TG_TOKEN (mesma do alerta) ou inline.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# ======================================================================
# CONFIG (edite aqui se necessario)
# ======================================================================
$Config = [ordered]@{
    TelegramToken  = if ($env:MONITOR_TG_TOKEN) { $env:MONITOR_TG_TOKEN } else { 'COLOQUE_SEU_TOKEN_AQUI' }
    AllowedChatIds = @('COLOQUE_SEU_CHAT_ID_AQUI')   # SOMENTE estes IDs podem enviar comandos
    CriticalServices = @('Spooler')    # servicos mostrados em /servicos
    PollTimeoutSec = 30                # long-poll (segundos)
    ApiTimeoutSec  = 45                # timeout HTTP (> PollTimeoutSec)
    MonitorLog     = 'C:\Monitoramento\logs\monitor.log'
    LogTailLines   = 15
    TaskName       = 'MonitoramentoServidor'   # tarefa disparada por /check
    LogDir         = "$PSScriptRoot\logs"
    LogMaxBytes    = 3MB
    LogKeepFiles   = 5
    StateFile      = "$PSScriptRoot\bot-state.json"
}

$script:Token    = $Config.TelegramToken
$script:LogFile  = Join-Path $Config.LogDir 'bot.log'
$script:Server   = $env:COMPUTERNAME
if (-not (Test-Path $Config.LogDir)) { New-Item -ItemType Directory -Path $Config.LogDir -Force | Out-Null }

# ======================================================================
# LOG
# ======================================================================
function Write-BotLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')]$Level='INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        if (Test-Path $script:LogFile -ErrorAction SilentlyContinue) {
            if ((Get-Item $script:LogFile).Length -ge $Config.LogMaxBytes) {
                $arch = "{0}.{1}.bak" -f $script:LogFile, (Get-Date -Format 'yyyyMMdd_HHmmss')
                Move-Item $script:LogFile $arch -Force
                Get-ChildItem $Config.LogDir -Filter 'bot.log.*.bak' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -Skip $Config.LogKeepFiles |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Verbose $line
}

# ======================================================================
# TELEGRAM
# ======================================================================
function Test-TokenOk {
    return ($script:Token -match '^\d{6,}:[A-Za-z0-9_-]{30,}$')
}
function Get-HtmlSafe { param([string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;')
}
function Send-Reply {
    param([string]$ChatId, [string]$Text)
    $uri  = "https://api.telegram.org/bot$script:Token/sendMessage"
    $body = @{ chat_id = $ChatId; text = $Text; parse_mode = 'HTML'; disable_web_page_preview = $true }
    for ($i=1; $i -le 3; $i++) {
        try {
            $r = Invoke-RestMethod -Uri $uri -Method Post -Body $body -TimeoutSec 20 -ErrorAction Stop
            if ($r.ok) { return $true }
        } catch {
            Write-BotLog "Falha ao responder (tentativa $i): $($_.Exception.Message)" 'WARN'
            Start-Sleep -Seconds ([math]::Min(10, $i*2))
        }
    }
    return $false
}

# ======================================================================
# ESTADO (offset do getUpdates)
# ======================================================================
function Get-Offset {
    if (Test-Path $Config.StateFile) {
        try { return [int64]((Get-Content $Config.StateFile -Raw | ConvertFrom-Json).offset) } catch { }
    }
    return $null
}
function Save-Offset { param([int64]$Offset)
    try { @{ offset = $Offset } | ConvertTo-Json | Set-Content -Path $Config.StateFile -Encoding UTF8 } catch { }
}

# ======================================================================
# COLETA (locale-safe)
# ======================================================================
function Get-Cpu {
    $vals = @()
    for ($i=0; $i -lt 2; $i++) {
        $c = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
        if ($null -ne $c) { $vals += [double]$c }
        if ($i -lt 1) { Start-Sleep -Milliseconds 700 }
    }
    if ($vals.Count -eq 0) { return 'n/d' }
    return ("{0}%" -f [math]::Round(($vals | Measure-Object -Average).Average,1))
}
function Get-Ram {
    $os = Get-CimInstance Win32_OperatingSystem
    if (-not $os -or $os.TotalVisibleMemorySize -le 0) { return 'n/d' }
    $pct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100,1)
    $totGB = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
    return ("{0}% de {1} GB" -f $pct, $totGB)
}
function Get-DisksText {
    $lines = @()
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        if ($_.Size -gt 0) {
            $used = [math]::Round((($_.Size - $_.FreeSpace)/$_.Size)*100,1)
            $freeGB = [math]::Round($_.FreeSpace/1GB,1)
            $lines += ("{0} {1}% usado ({2} GB livres)" -f $_.DeviceID, $used, $freeGB)
        }
    }
    if ($lines.Count -eq 0) { return 'n/d' }
    return ($lines -join "`n")
}
function Get-UptimeText {
    $os = Get-CimInstance Win32_OperatingSystem
    $boot = $os.LastBootUpTime
    $ts = (Get-Date) - $boot
    return ("{0}d {1}h {2}m (boot {3})" -f $ts.Days, $ts.Hours, $ts.Minutes, $boot.ToString('dd/MM HH:mm'))
}
function Get-ServicesText {
    $lines = @()
    foreach ($n in $Config.CriticalServices) {
        $svc = Get-Service -Name $n -ErrorAction SilentlyContinue
        if ($svc) { $lines += ("{0}: {1}" -f $n, $svc.Status) }
        else      { $lines += ("{0}: (nao instalado)" -f $n) }
    }
    $stopped = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State='Stopped'" -ErrorAction SilentlyContinue)
    $lines += ("Automaticos parados: {0}" -f $stopped.Count)
    return ($lines -join "`n")
}
function Get-LogTailText {
    if (-not (Test-Path $Config.MonitorLog)) { return '(log ainda nao gerado)' }
    $tail = Get-Content $Config.MonitorLog -Tail $Config.LogTailLines -ErrorAction SilentlyContinue
    if (-not $tail) { return '(log vazio)' }
    return (Get-HtmlSafe (($tail) -join "`n"))
}

# ======================================================================
# COMANDOS
# ======================================================================
function Get-HelpText {
@"
<b>Monitoramento - $($script:Server)</b>
Comandos disponiveis:
/status  - CPU, RAM, disco e uptime agora
/check   - dispara uma ronda completa de monitoramento
/log     - ultimas linhas do log
/servicos- estado dos servicos criticos
/disco   - uso de disco por volume
/uptime  - tempo ligado / ultimo boot
/help    - esta lista
"@
}
function Invoke-Command2 {
    param([string]$Cmd, [string]$ChatId)
    switch ($Cmd) {
        '/start'    { return (Get-HelpText) }
        '/help'     { return (Get-HelpText) }
        '/status'   {
            return ("<b>Status - $($script:Server)</b>`nCPU: {0}`nRAM: {1}`n{2}`nUptime: {3}" -f `
                    (Get-Cpu), (Get-Ram), (Get-DisksText), (Get-UptimeText))
        }
        '/disco'    { return ("<b>Disco - $($script:Server)</b>`n{0}" -f (Get-DisksText)) }
        '/servicos' { return ("<b>Servicos - $($script:Server)</b>`n{0}" -f (Get-ServicesText)) }
        '/uptime'   { return ("<b>Uptime - $($script:Server)</b>`n{0}" -f (Get-UptimeText)) }
        '/log'      { return ("<b>Log - $($script:Server)</b>`n<pre>{0}</pre>" -f (Get-LogTailText)) }
        '/check'    {
            try {
                $out = & schtasks.exe /Run /TN $Config.TaskName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    return "Ronda de monitoramento disparada. Se houver algo a alertar, voce recebera em instantes."
                }
                return ("Nao consegui disparar a tarefa '{0}': {1}" -f $Config.TaskName, (($out | Out-String).Trim()))
            } catch {
                return ("Erro ao disparar a tarefa '{0}': {1}" -f $Config.TaskName, $_.Exception.Message)
            }
        }
        default     { return "Comando nao reconhecido. Use /help para ver as opcoes." }
    }
}

# ======================================================================
# LOOP PRINCIPAL
# ======================================================================
# Instancia unica (evita conflito 409 no getUpdates)
$mutex = New-Object System.Threading.Mutex($false, 'Global\MonitorTelegramBot')
if (-not $mutex.WaitOne(0)) {
    Write-BotLog 'Outra instancia do bot ja esta em execucao. Saindo.' 'WARN'
    exit 0
}

if (-not (Test-TokenOk)) {
    Write-BotLog 'Token do Telegram ausente/invalido. Configure MONITOR_TG_TOKEN.' 'ERROR'
    exit 1
}

Write-BotLog "Bot iniciado em $script:Server. IDs autorizados: $($Config.AllowedChatIds -join ', ')"

$offset = Get-Offset
if ($null -eq $offset) {
    # Primeira execucao: descarta mensagens antigas (backlog)
    try {
        $r0 = Invoke-RestMethod "https://api.telegram.org/bot$script:Token/getUpdates?offset=-1&timeout=0" -TimeoutSec 20 -ErrorAction Stop
        if ($r0.ok -and $r0.result.Count -gt 0) { $offset = [int64]$r0.result[-1].update_id + 1 } else { $offset = 0 }
    } catch { $offset = 0 }
    Save-Offset $offset
    Write-BotLog "Backlog ignorado. Offset inicial = $offset"
}

while ($true) {
    try {
        $uri  = "https://api.telegram.org/bot$script:Token/getUpdates?timeout=$($Config.PollTimeoutSec)&offset=$offset"
        $resp = Invoke-RestMethod -Uri $uri -TimeoutSec $Config.ApiTimeoutSec -ErrorAction Stop

        if ($resp.ok -and $resp.result) {
            foreach ($upd in $resp.result) {
                $offset = [int64]$upd.update_id + 1   # avanca SEMPRE
                $msg = $upd.message
                if (-not $msg) { continue }
                $chatId = "$($msg.chat.id)"
                $text   = $msg.text
                if (-not $text) { continue }

                if ($Config.AllowedChatIds -notcontains $chatId) {
                    Write-BotLog "Comando ignorado de ID nao autorizado: $chatId (texto: $text)" 'WARN'
                    continue
                }

                $cmd = (($text.Trim() -split '\s+')[0]).ToLower()
                $cmd = ($cmd -replace '@.*$','')   # /status@MeuBot -> /status
                Write-BotLog "Comando '$cmd' de $chatId"
                try {
                    $reply = Invoke-Command2 -Cmd $cmd -ChatId $chatId
                } catch {
                    $reply = "Erro ao executar o comando: $($_.Exception.Message)"
                    Write-BotLog "Erro no comando '$cmd': $($_.Exception.Message)" 'ERROR'
                }
                [void](Send-Reply -ChatId $chatId -Text $reply)
            }
            Save-Offset $offset
        }
    }
    catch {
        Write-BotLog "Falha no ciclo de polling: $($_.Exception.Message)" 'WARN'
        Start-Sleep -Seconds 5   # backoff em erro de rede/API
    }
}
