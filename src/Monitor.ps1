# Recomendado: PowerShell 7 (pwsh) ou Windows PowerShell 5.1.
# Evite Windows PowerShell 4.0 (Server 2012 R2 sem WMF 5.1) para execucao manual.
<#
.SYNOPSIS
    Monitoramento de servidor Windows com alertas inteligentes via Telegram.

.DESCRIPTION
    Coleta CPU, RAM, disco, rede, servicos, eventos criticos, processos travados,
    reinicializacoes inesperadas, BSOD, falhas de Backup/Windows Update/Banco de Dados
    e dispara alertas no Telegram com retry, timeout, log local e rotacao de log.

    Projetado para rodar a cada 5 minutos via Agendador de Tarefas, na conta SYSTEM.
    Mantem estado entre execucoes (CPU sustentada, cooldown de alertas, ultimo boot)
    em arquivo JSON, evitando spam de notificacoes.

.PARAMETER Test
    Valida token/ChatID/conectividade e envia uma mensagem de teste ao Telegram.

.NOTES
    Compatibilidade : Windows Server 2012 R2/2016/2019/2022 e Windows 10/11.
    Engine          : Windows PowerShell 5.1 (sem dependencias externas).
    Locale-safe     : usa contadores WMI/CIM (independente de idioma do SO).
    Conectividade   : pre-checagem via TCP 443 (nao depende de ICMP/ping).
#>

[CmdletBinding()]
param(
    [switch]$Test,
    [string]$ConfigPath = "$PSScriptRoot\MonitorConfig.json"
)

# ======================================================================
# 0. INICIALIZACAO E SEGURANCA GLOBAL
# ======================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Forca TLS 1.2 (necessario em Server 2012R2/2016 para api.telegram.org)
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# ----------------------------------------------------------------------
# CONFIGURACAO (edite aqui). Segredos preferencialmente via variavel de
# ambiente de maquina: MONITOR_TG_TOKEN / MONITOR_TG_CHATID.
# ----------------------------------------------------------------------
$Config = [ordered]@{
    # --- Telegram ---
    TelegramToken      = if ($env:MONITOR_TG_TOKEN)  { $env:MONITOR_TG_TOKEN }  else { 'COLOQUE_SEU_TOKEN_AQUI' }
    TelegramChatId     = if ($env:MONITOR_TG_CHATID) { $env:MONITOR_TG_CHATID } else { 'COLOQUE_SEU_CHAT_ID_AQUI' }
    TelegramRetry      = 3
    TelegramTimeoutSec = 15

    # --- Limiares ---
    CpuThreshold       = 80      # % CPU
    CpuSustainMinutes  = 5       # minutos sustentados acima do limiar
    RamThreshold       = 80      # % RAM
    DiskThreshold      = 90      # % por volume
    ProcCpuThreshold   = 70      # % CPU de um unico processo
    ProcMemThresholdMB = 2048    # MB de working set de um unico processo

    # --- Janela / agendamento ---
    IntervalMinutes    = 5       # deve casar com o gatilho da tarefa
    AlertCooldownMin   = 30      # nao repetir o mesmo alerta antes disso

    # --- Servicos criticos a vigiar (alem dos Automaticos parados) ---
    CriticalServices   = @('Spooler')   # ex.: 'MSSQLSERVER','W3SVC','Dhcp'

    # Vigiar TODOS os servicos Automaticos parados (alem dos criticos nomeados).
    # Em servidores com muitos servicos trigger-start, deixe $false para reduzir ruido.
    MonitorAutoStopped = $true
    # Servicos a ignorar na varredura ampla (trigger-start / normalmente parados).
    IgnoreServicesRegex = 'edgeupdate|gupdate|MapsBroker|RemoteRegistry|sppsvc|TrustedInstaller|CDPSvc|WbioSrvc|wuauserv|BITS|DoSvc|WinHttpAutoProxySvc|tiledatamodelsvc|dmwappushservice|cbdhsvc|RmSvc|TabletInputService|StiSvc|ScDeviceEnum|SDRSVC|SharedAccess|svsvc|UsoSvc|InstallService|MessagingService|PimIndexMaintenanceSvc|UnistoreSvc|UserDataSvc|WpnService|OneSyncSvc|shpamsvc'
    MaxAutoStoppedAlerts = 10    # teto de alertas de servico parado por ciclo

    # --- Provedores/IDs para deteccoes especificas ---
    DbServicePrefixes  = @('MSSQL', 'MySQL', 'postgresql', 'OracleService')

    # --- Limites operacionais ---
    MaxEventsPerQuery  = 20      # teto de eventos lidos por consulta (eficiencia)
    TelegramMaxChars   = 3900    # Telegram limita mensagem em 4096; margem de seguranca
    StatePruneHours    = 24      # remove chaves de alerta mais antigas que isso

    # --- Log ---
    LogDir             = "$PSScriptRoot\logs"
    LogMaxBytes        = 5MB
    LogKeepFiles       = 7

    # --- Estado ---
    StateFile          = "$PSScriptRoot\monitor-state.json"
}

# Override opcional por arquivo JSON externo
if (Test-Path $ConfigPath) {
    try {
        $ext = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        foreach ($p in $ext.PSObject.Properties) { $Config[$p.Name] = $p.Value }
    } catch { Write-Warning "Falha ao ler $ConfigPath : $($_.Exception.Message)" }
}

$script:Config    = $Config
$script:LogFile   = Join-Path $Config.LogDir 'monitor.log'
$script:StateFile = $Config.StateFile
$script:ServerName = $env:COMPUTERNAME
$script:Alerts    = New-Object System.Collections.Generic.List[object]
$script:OsInfo       = $null
$script:LogicalCores = $null

if (-not (Test-Path $Config.LogDir)) {
    New-Item -ItemType Directory -Path $Config.LogDir -Force | Out-Null
}

# ======================================================================
# 1. LOG LOCAL COM ROTACAO
# ======================================================================
function Write-MonitorLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','CRITICAL')][string]$Level = 'INFO'
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        if (Test-Path $script:LogFile) {
            if ((Get-Item $script:LogFile).Length -ge $script:Config.LogMaxBytes) {
                $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
                $archive = "{0}.{1}.bak" -f $script:LogFile, $stamp
                Move-Item -Path $script:LogFile -Destination $archive -Force
                Get-ChildItem -Path $script:Config.LogDir -Filter 'monitor.log.*.bak' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -Skip $script:Config.LogKeepFiles |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    } catch { }   # log nunca pode derrubar o monitoramento
    Write-Verbose $line
}

# ======================================================================
# 2. TELEGRAM (validacao + internet + retry + timeout)
# ======================================================================
function Test-TelegramConfig {
    $okToken  = $script:Config.TelegramToken  -match '^\d{6,}:[A-Za-z0-9_-]{30,}$'
    $okChatId = -not [string]::IsNullOrWhiteSpace($script:Config.TelegramChatId) -and
                $script:Config.TelegramChatId -notmatch 'SUBSTITUA'
    if (-not $okToken)  { Write-MonitorLog 'Token do Telegram ausente ou em formato invalido.' 'ERROR' }
    if (-not $okChatId) { Write-MonitorLog 'ChatID do Telegram ausente ou nao configurado.'     'ERROR' }
    return ($okToken -and $okChatId)
}

function Test-InternetConnection {
    # Testa conectividade TCP real na porta 443 do Telegram (sem depender de
    # ICMP/ping, que costuma ser bloqueado em redes corporativas e no perimetro).
    $targetHost = 'api.telegram.org'
    $targetPort = 443
    $timeoutMs  = 3000
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($targetHost, $targetPort, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($timeoutMs, $false) -and $client.Connected) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        if ($client) { try { $client.Close() } catch { } }
    }
}

function Get-HtmlSafe { param([string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;')
}

function Send-TelegramMessage {
    param([Parameter(Mandatory)][string]$Text)

    if (-not (Test-TelegramConfig)) { return $false }

    $maxChars = [int]$script:Config.TelegramMaxChars
    if ($maxChars -gt 0 -and $Text.Length -gt $maxChars) {
        $Text = $Text.Substring(0, $maxChars) + "`n... (mensagem truncada)"
    }

    $uri  = "https://api.telegram.org/bot{0}/sendMessage" -f $script:Config.TelegramToken
    $body = @{
        chat_id                  = $script:Config.TelegramChatId
        text                     = $Text
        parse_mode               = 'HTML'
        disable_web_page_preview = $true
    }
    $max = [int]$script:Config.TelegramRetry

    for ($i = 1; $i -le $max; $i++) {
        try {
            if (-not (Test-InternetConnection)) {
                Write-MonitorLog "Sem conectividade de rede (tentativa $i/$max)." 'WARN'
                Start-Sleep -Seconds ([math]::Min(30, $i * 3)); continue
            }
            $resp = Invoke-RestMethod -Uri $uri -Method Post -Body $body `
                        -TimeoutSec $script:Config.TelegramTimeoutSec -ErrorAction Stop
            if ($resp.ok) { return $true }
            Write-MonitorLog "Telegram retornou ok=false (tentativa $i/$max)." 'WARN'
        } catch {
            Write-MonitorLog "Falha no envio Telegram (tentativa $i/$max): $($_.Exception.Message)" 'WARN'
        }
        Start-Sleep -Seconds ([math]::Min(30, [math]::Pow(2, $i)))   # backoff exponencial
    }
    Write-MonitorLog "Falha definitiva ao enviar alerta apos $max tentativas." 'ERROR'
    return $false
}

# ======================================================================
# 3. ESTADO PERSISTENTE (entre execucoes)
# ======================================================================
function Get-MonitorState {
    $state = $null
    if (Test-Path $script:StateFile) {
        try { $state = (Get-Content $script:StateFile -Raw | ConvertFrom-Json) } catch { }
    }
    if (-not $state) { $state = [pscustomobject]@{} }
    foreach ($prop in 'HighCpuSince','LastBootTime') {
        if (-not $state.PSObject.Properties[$prop]) {
            $state | Add-Member -NotePropertyName $prop -NotePropertyValue $null -Force
        }
    }
    if (-not $state.PSObject.Properties['LastAlerts']) {
        $state | Add-Member -NotePropertyName 'LastAlerts' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    return $state
}
function Save-MonitorState { param($State)
    try { $State | ConvertTo-Json -Depth 6 | Set-Content -Path $script:StateFile -Encoding UTF8 }
    catch { Write-MonitorLog "Falha ao salvar estado: $($_.Exception.Message)" 'WARN' }
}
function Get-LastAlertTime { param($State, $Key)
    $p = $State.LastAlerts.PSObject.Properties[$Key]
    if ($p -and $p.Value) { try { return [datetime]$p.Value } catch { } }
    return $null
}
function Set-LastAlertTime { param($State, $Key, $Time)
    if ($State.LastAlerts.PSObject.Properties[$Key]) { $State.LastAlerts.$Key = $Time }
    else { $State.LastAlerts | Add-Member -NotePropertyName $Key -NotePropertyValue $Time -Force }
}
function Remove-StaleAlertKeys { param($State)
    # Remove chaves antigas para o arquivo de estado nao crescer indefinidamente.
    $cutoff = (Get-Date).AddHours(-[double]$script:Config.StatePruneHours)
    $stale  = @()
    foreach ($p in $State.LastAlerts.PSObject.Properties) {
        $t = $null
        try { $t = [datetime]$p.Value } catch { }
        if ($null -eq $t -or $t -lt $cutoff) { $stale += $p.Name }
    }
    foreach ($name in $stale) { $State.LastAlerts.PSObject.Properties.Remove($name) }
}

# ======================================================================
# 4. REGISTRO DE ALERTAS
# ======================================================================
$Recommendations = @{
    'CPU_SUSTENTADA'   = 'Identifique o processo no Gerenciador de Tarefas. Avalie escalonamento, throttling ou mais vCPU.'
    'RAM_ALTA'         = 'Verifique vazamento de memoria, ajuste pool/cache da aplicacao ou amplie a RAM.'
    'DISCO_CHEIO'      = 'Libere espaco (logs, temp, dumps), expanda o volume ou mova dados.'
    'SERVICO_PARADO'   = 'Reinicie o servico e investigue o motivo da queda no Event Viewer.'
    'EVENTO_CRITICO'   = 'Abra o Visualizador de Eventos e trate a causa raiz do evento sinalizado.'
    'PROC_TRAVADO'     = 'Aplicacao sem resposta. Reinicie o processo/servico responsavel.'
    'REBOOT_INESPERADO'= 'Reboot nao planejado. Verifique energia, hardware e logs Kernel-Power (ID 41).'
    'BSOD'             = 'Tela azul detectada. Analise o minidump em C:\Windows\Minidump e atualize drivers.'
    'BACKUP_FALHA'     = 'Falha de backup. Valide destino, credenciais e espaco; reexecute o job.'
    'WU_FALHA'         = 'Falha no Windows Update. Rode wuauclt/USOClient e verifique conectividade WSUS.'
    'DB_FALHA'         = 'Banco de dados indisponivel. Cheque o servico e o errorlog do SGBD.'
    'PROC_CPU_ALTA'    = 'Processo consumindo CPU excessiva. Avalie reinicio ou limite de recurso.'
    'PROC_MEM_ALTA'    = 'Processo consumindo memoria excessiva. Avalie vazamento e reinicio.'
    'REDE_DOWN'        = 'Adaptador de rede inativo. Verifique cabo/switch/driver e gateway.'
}

function Add-Alert {
    param(
        [Parameter(Mandatory)][string]$Type,
        [ValidateSet('Critico','Alto','Medio','Baixo')][string]$Severity,
        [string]$Process = '-',
        [string]$Value   = '-',
        [string]$Key
    )
    if (-not $Key) { $Key = "$Type|$Process" }
    $rec = if ($Recommendations.ContainsKey($Type)) { $Recommendations[$Type] } else { 'Investigar manualmente.' }
    $script:Alerts.Add([pscustomobject]@{
        Type=$Type; Severity=$Severity; Process=$Process; Value=$Value
        Recommendation=$rec; Key=$Key; Time=(Get-Date)
    })
}

# ======================================================================
# 5. COLETORES (cada um isolado em try/catch pelo chamador)
# ======================================================================
function Get-CpuUsagePercent {
    # 3 amostras CIM (locale-safe) -> media
    $vals = @()
    for ($i = 0; $i -lt 3; $i++) {
        $c = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
        if ($null -ne $c) { $vals += [double]$c }
        if ($i -lt 2) { Start-Sleep -Milliseconds 800 }
    }
    if ($vals.Count -eq 0) { return $null }
    $avg = ($vals | Measure-Object -Average).Average
    if ($avg -gt 100) { $avg = 100 }   # protecao: _Total nunca deve passar de 100%
    return [math]::Round($avg, 1)
}

function Get-OsInfoCached {
    if (-not $script:OsInfo) { $script:OsInfo = Get-CimInstance Win32_OperatingSystem }
    return $script:OsInfo
}
function Get-LogicalCoresCached {
    if (-not $script:LogicalCores) {
        $n = [int](Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        if ($n -lt 1) { $n = 1 }
        $script:LogicalCores = $n
    }
    return $script:LogicalCores
}

function Get-MemoryUsagePercent {
    $os = Get-OsInfoCached
    if (-not $os -or $os.TotalVisibleMemorySize -le 0) { return $null }
    return [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
}

function Test-Cpu { param($State)
    $cpu = Get-CpuUsagePercent
    if ($null -eq $cpu) { Write-MonitorLog 'Nao foi possivel ler a CPU.' 'WARN'; return }
    Write-MonitorLog "CPU total: $cpu%"
    if ($cpu -ge $script:Config.CpuThreshold) {
        if (-not $State.HighCpuSince) { $State.HighCpuSince = (Get-Date).ToString('o') }
        $since = [datetime]$State.HighCpuSince
        $mins  = [math]::Round(((Get-Date) - $since).TotalMinutes, 1)
        if ($mins -ge $script:Config.CpuSustainMinutes) {
            Add-Alert -Type 'CPU_SUSTENTADA' -Severity 'Alto' -Process 'CPU(_Total)' `
                      -Value "$cpu% por ~$mins min" -Key 'CPU_SUSTENTADA'
        }
    } else {
        $State.HighCpuSince = $null
    }
}

function Test-Memory {
    $ram = Get-MemoryUsagePercent
    if ($null -eq $ram) { return }
    Write-MonitorLog "RAM: $ram%"
    if ($ram -ge $script:Config.RamThreshold) {
        Add-Alert -Type 'RAM_ALTA' -Severity 'Alto' -Process 'Memoria' -Value "$ram%" -Key 'RAM_ALTA'
    }
}

function Test-Disk {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        if ($_.Size -gt 0) {
            $used = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
            Write-MonitorLog "Disco $($_.DeviceID) $used% usado"
            if ($used -ge $script:Config.DiskThreshold) {
                $freeGB = [math]::Round($_.FreeSpace / 1GB, 1)
                Add-Alert -Type 'DISCO_CHEIO' -Severity 'Critico' -Process $_.DeviceID `
                          -Value "$used% usado ($freeGB GB livres)" -Key "DISCO_$($_.DeviceID)"
            }
        }
    }
}

function Test-Network {
    # Conectividade real = existe adaptador habilitado por IP com gateway padrao.
    $hasGateway = $false
    try {
        Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' -ErrorAction Stop |
            ForEach-Object {
                if ($_.DefaultIPGateway -and $_.DefaultIPGateway.Count -gt 0) { $hasGateway = $true }
            }
    } catch { $hasGateway = $true }   # em duvida, nao alarmar

    if (-not $hasGateway) {
        # confirma com status de conexao fisica antes de alarmar
        $up = Get-CimInstance Win32_NetworkAdapter -Filter 'NetConnectionStatus=2' -ErrorAction SilentlyContinue
        if (-not $up) {
            Add-Alert -Type 'REDE_DOWN' -Severity 'Critico' -Process 'NIC' `
                      -Value 'Nenhum adaptador com gateway/conexao ativa' -Key 'REDE_DOWN'
        }
    }
}

function Test-Services {
    # 1) servicos criticos nomeados
    foreach ($name in $script:Config.CriticalServices) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') {
            Add-Alert -Type 'SERVICO_PARADO' -Severity 'Critico' -Process $name `
                      -Value "Status: $($svc.Status)" -Key "SVC_$name"
        }
    }
    # 2) servicos Automaticos que estao parados (opcional / com teto)
    if ($script:Config.MonitorAutoStopped) {
        $named = @($script:Config.CriticalServices)
        Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State='Stopped'" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch $script:Config.IgnoreServicesRegex -and $named -notcontains $_.Name } |
            Select-Object -First ([int]$script:Config.MaxAutoStoppedAlerts) |
            ForEach-Object {
                Add-Alert -Type 'SERVICO_PARADO' -Severity 'Alto' -Process $_.Name `
                          -Value 'Automatico, porem parado' -Key "SVC_$($_.Name)"
            }
    }
}

function Get-RecentEvents { param([int]$LookbackMin)
    $since = (Get-Date).AddMinutes(-$LookbackMin)
    try {
        return Get-WinEvent -FilterHashtable @{ LogName=@('System','Application'); Level=@(1,2); StartTime=$since } `
                            -MaxEvents ([int]$script:Config.MaxEventsPerQuery) -ErrorAction Stop
    } catch { return @() }   # "no events" lanca excecao em Get-WinEvent
}

function Test-CriticalEvents {
    $events = Get-RecentEvents -LookbackMin ($script:Config.IntervalMinutes + 1)
    $count  = ($events | Measure-Object).Count
    if ($count -gt 0) {
        $top = $events | Select-Object -First 3
        foreach ($e in $top) {
            $sev = if ($e.Level -eq 1) { 'Critico' } else { 'Alto' }
            $msg = ($e.Message -split "`n")[0]
            if ($msg.Length -gt 160) { $msg = $msg.Substring(0,160) + '...' }
            Add-Alert -Type 'EVENTO_CRITICO' -Severity $sev -Process "$($e.ProviderName) (ID $($e.Id))" `
                      -Value $msg -Key "EVT_$($e.ProviderName)_$($e.Id)"
        }
    }
}

function Test-HungProcesses {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and -not $_.Responding } |
        ForEach-Object {
            Add-Alert -Type 'PROC_TRAVADO' -Severity 'Alto' -Process $_.ProcessName `
                      -Value "PID $($_.Id) sem resposta" -Key "HUNG_$($_.Id)"
        }
}

function Test-Reboot { param($State)
    $boot = (Get-OsInfoCached).LastBootUpTime
    $bootStr = $boot.ToString('o')
    if ($State.LastBootTime -and $State.LastBootTime -ne $bootStr) {
        $since = (Get-Date).AddMinutes(-($script:Config.IntervalMinutes + 5))
        $unexpected = $false
        try {
            $ev = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=@(41,6008); StartTime=$since } -MaxEvents 5 -ErrorAction Stop
            if (($ev | Measure-Object).Count -gt 0) { $unexpected = $true }
        } catch { }
        $sev = if ($unexpected) { 'Critico' } else { 'Medio' }
        $tag = if ($unexpected) { 'INESPERADA' } else { 'planejada/normal' }
        Add-Alert -Type 'REBOOT_INESPERADO' -Severity $sev -Process 'Sistema' `
                  -Value "Reinicializacao $tag em $($boot.ToString('dd/MM HH:mm'))" -Key "BOOT_$bootStr"
    }
    $State.LastBootTime = $bootStr
}

function Test-BSOD {
    $since = (Get-Date).AddMinutes(-($script:Config.IntervalMinutes + 5))
    try {
        $bs = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=1001;
                ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$since } -MaxEvents 5 -ErrorAction Stop
        foreach ($b in $bs) {
            Add-Alert -Type 'BSOD' -Severity 'Critico' -Process 'Kernel' `
                      -Value 'BugCheck registrado (tela azul)' -Key "BSOD_$($b.TimeCreated.Ticks)"
        }
    } catch { }
    # reforco por minidump recente
    $dumpDir = Join-Path $env:SystemRoot 'Minidump'
    if (Test-Path $dumpDir) {
        Get-ChildItem $dumpDir -Filter '*.dmp' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $since } |
            ForEach-Object {
                Add-Alert -Type 'BSOD' -Severity 'Critico' -Process 'Kernel' `
                          -Value "Minidump: $($_.Name)" -Key "DMP_$($_.Name)"
            }
    }
}

function Test-BackupFailure {
    $since = (Get-Date).AddMinutes(-($script:Config.IntervalMinutes + 1))
    try {
        $f = Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Backup'; Level=@(1,2); StartTime=$since } -MaxEvents 10 -ErrorAction Stop
        foreach ($e in $f) {
            Add-Alert -Type 'BACKUP_FALHA' -Severity 'Alto' -Process 'Windows Backup' `
                      -Value "Evento ID $($e.Id)" -Key "BKP_$($e.Id)_$($e.TimeCreated.Ticks)"
        }
    } catch { }
}

function Test-WindowsUpdateFailure {
    $since = (Get-Date).AddMinutes(-($script:Config.IntervalMinutes + 1))
    try {
        $u = Get-WinEvent -FilterHashtable @{ LogName='System';
                ProviderName='Microsoft-Windows-WindowsUpdateClient'; Level=@(1,2); StartTime=$since } -MaxEvents 10 -ErrorAction Stop
        foreach ($e in $u) {
            Add-Alert -Type 'WU_FALHA' -Severity 'Medio' -Process 'Windows Update' `
                      -Value "Evento ID $($e.Id)" -Key "WU_$($e.Id)_$($e.TimeCreated.Ticks)"
        }
    } catch { }
}

function Test-DatabaseFailure {
    foreach ($prefix in $script:Config.DbServicePrefixes) {
        Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "$prefix*" -and $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running'
        } | ForEach-Object {
            Add-Alert -Type 'DB_FALHA' -Severity 'Critico' -Process $_.Name `
                      -Value "Servico de banco $($_.Status)" -Key "DB_$($_.Name)"
        }
    }
}

function Test-ProcessResourceHogs {
    $cores = Get-LogicalCoresCached

    # --- CPU por processo: delta de TotalProcessorTime sobre o tempo REAL decorrido ---
    # Usa um cronometro monotonico e mede o tempo real entre as duas amostras de
    # cada processo. Em servidores sobrecarregados, enumerar os processos pode
    # levar bem mais que 1s; dividir por um intervalo fixo de 1000ms inflava o
    # percentual (podendo passar de 100%). Aqui o divisor e o tempo real decorrido
    # e o valor e limitado a 100% (um processo nao usa mais que a capacidade total).
    $sw    = [System.Diagnostics.Stopwatch]::StartNew()
    $snap1 = @{}
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $t = $_.TotalProcessorTime
            if ($null -ne $t) { $snap1[$_.Id] = @{ Cpu = $t.TotalMilliseconds; At = $sw.Elapsed.TotalMilliseconds } }
        } catch { }   # System/Idle/protegidos nao expoem tempo de CPU
    }
    Start-Sleep -Milliseconds 1000
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $t = $_.TotalProcessorTime
            if ($snap1.ContainsKey($_.Id) -and $null -ne $t) {
                $prev      = $snap1[$_.Id]
                $deltaMs   = $t.TotalMilliseconds - $prev.Cpu
                $elapsedMs = $sw.Elapsed.TotalMilliseconds - $prev.At
                if ($elapsedMs -gt 0 -and $deltaMs -ge 0) {
                    $pct = [math]::Round(($deltaMs / ($elapsedMs * $cores)) * 100, 1)
                    if ($pct -gt 100) { $pct = 100.0 }   # protecao: nunca acima de 100%
                    if ($pct -ge $script:Config.ProcCpuThreshold) {
                        Add-Alert -Type 'PROC_CPU_ALTA' -Severity 'Alto' -Process "$($_.ProcessName) (PID $($_.Id))" `
                                  -Value "$pct% CPU" -Key "PCPU_$($_.Id)"
                    }
                }
            }
        } catch { }
        # --- Memoria por processo ---
        try {
            $memMB = [math]::Round($_.WorkingSet64 / 1MB, 0)
            if ($memMB -ge $script:Config.ProcMemThresholdMB) {
                Add-Alert -Type 'PROC_MEM_ALTA' -Severity 'Medio' -Process "$($_.ProcessName) (PID $($_.Id))" `
                          -Value "$memMB MB" -Key "PMEM_$($_.Id)"
            }
        } catch { }
    }
}

# ======================================================================
# 6. DESPACHO DOS ALERTAS (com cooldown e severidade)
# ======================================================================
function Get-SeverityRank { param([string]$S)
    switch ($S) { 'Critico'{4} 'Alto'{3} 'Medio'{2} 'Baixo'{1} default{0} }
}
function Get-SeverityIcon { param([string]$S)
    switch ($S) { 'Critico'{'[CRITICO]'} 'Alto'{'[ALTO]'} 'Medio'{'[MEDIO]'} default{'[BAIXO]'} }
}

function Send-Alerts { param($State)
    if ($script:Alerts.Count -eq 0) { Write-MonitorLog 'Nenhum alerta nesta execucao.'; return }

    $send = New-Object System.Collections.Generic.List[object]
    foreach ($a in $script:Alerts) {
        $last = Get-LastAlertTime $State $a.Key
        if ($null -eq $last -or ((Get-Date) - $last).TotalMinutes -ge $script:Config.AlertCooldownMin) {
            $send.Add($a)
            Set-LastAlertTime $State $a.Key (Get-Date).ToString('o')
        } else {
            Write-MonitorLog "Alerta '$($a.Key)' em cooldown; suprimido." 'INFO'
        }
    }
    if ($send.Count -eq 0) { return }

    $ordered = $send | Sort-Object @{ Expression = { Get-SeverityRank $_.Severity }; Descending = $true }
    $now = Get-Date -Format 'dd/MM/yyyy HH:mm:ss'

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<b>ALERTA DE MONITORAMENTO</b>")
    [void]$sb.AppendLine("Servidor: <b>$(Get-HtmlSafe $script:ServerName)</b>")
    [void]$sb.AppendLine("Data/Hora: $now")
    [void]$sb.AppendLine("Ocorrencias: <b>$($send.Count)</b>")
    [void]$sb.AppendLine('')
    foreach ($a in $ordered) {
        [void]$sb.AppendLine("$(Get-SeverityIcon $a.Severity) <b>$($a.Type)</b>")
        [void]$sb.AppendLine("Processo/Alvo: $(Get-HtmlSafe $a.Process)")
        [void]$sb.AppendLine("Valor: $(Get-HtmlSafe $a.Value)")
        [void]$sb.AppendLine("Recomendacao: $(Get-HtmlSafe $a.Recommendation)")
        [void]$sb.AppendLine('')
        Write-MonitorLog ("ALERTA [{0}] {1} | {2} | {3}" -f $a.Severity, $a.Type, $a.Process, $a.Value) 'CRITICAL'
    }

    $ok = Send-TelegramMessage -Text $sb.ToString().Trim()
    if ($ok) { Write-MonitorLog "Alerta enviado ao Telegram ($($send.Count) ocorrencias)." 'INFO' }
}

# ======================================================================
# 7. MODO TESTE
# ======================================================================
function Invoke-SelfTest {
    Write-Host "== Diagnostico do Monitoramento =="
    Write-Host "Servidor      : $script:ServerName"
    Write-Host "PowerShell    : $($PSVersionTable.PSVersion)"
    Write-Host "Internet      : $(if (Test-InternetConnection){'OK'}else{'FALHOU'})"
    Write-Host "Config Telegram: $(if (Test-TelegramConfig){'VALIDA'}else{'INVALIDA'})"
    $msg = "<b>Teste de Monitoramento</b>`nServidor: $(Get-HtmlSafe $script:ServerName)`nStatus: comunicacao OK em $(Get-Date -Format 'dd/MM HH:mm')"
    $ok  = Send-TelegramMessage -Text $msg
    Write-Host "Envio de teste: $(if ($ok){'ENVIADO'}else{'FALHOU (ver log)'})"
    Write-MonitorLog "Self-test executado. Envio=$ok" 'INFO'
}

# ======================================================================
# 8. EXECUCAO PRINCIPAL (excecao global + finally)
# ======================================================================
function Invoke-Monitoring {
    $state = Get-MonitorState
    $checks = @(
        @{ Name='CPU';            Action={ Test-Cpu -State $state } },
        @{ Name='Memoria';        Action={ Test-Memory } },
        @{ Name='Disco';          Action={ Test-Disk } },
        @{ Name='Rede';           Action={ Test-Network } },
        @{ Name='Servicos';       Action={ Test-Services } },
        @{ Name='EventosCrit';    Action={ Test-CriticalEvents } },
        @{ Name='ProcTravados';   Action={ Test-HungProcesses } },
        @{ Name='Reboot';         Action={ Test-Reboot -State $state } },
        @{ Name='BSOD';           Action={ Test-BSOD } },
        @{ Name='Backup';         Action={ Test-BackupFailure } },
        @{ Name='WindowsUpdate';  Action={ Test-WindowsUpdateFailure } },
        @{ Name='BancoDados';     Action={ Test-DatabaseFailure } },
        @{ Name='ProcessHogs';    Action={ Test-ProcessResourceHogs } }
    )
    foreach ($c in $checks) {
        try { & $c.Action }
        catch { Write-MonitorLog "Falha no coletor '$($c.Name)': $($_.Exception.Message)" 'WARN' }
    }
    Send-Alerts -State $state
    Remove-StaleAlertKeys -State $state
    Save-MonitorState -State $state
}

# ----------------------------------------------------------------------
# ENTRYPOINT
# ----------------------------------------------------------------------
$startedAt = Get-Date
try {
    Write-MonitorLog "=== Inicio do ciclo (PID $PID) ===" 'INFO'
    if ($Test) { Invoke-SelfTest } else { Invoke-Monitoring }
}
catch {
    $err = "ERRO GLOBAL: $($_.Exception.Message)"
    Write-MonitorLog $err 'CRITICAL'
    try {
        $safe = (Get-HtmlSafe $err)
        Send-TelegramMessage -Text "<b>FALHA NO MONITORAMENTO</b>`n$($script:ServerName): $safe" | Out-Null
    } catch { }
    exit 1
}
finally {
    $dur = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
    Write-MonitorLog "=== Fim do ciclo (duracao ${dur}s) ===" 'INFO'
}
exit 0
