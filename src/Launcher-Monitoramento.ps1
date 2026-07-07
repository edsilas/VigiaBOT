<#
    VigiaBOT - Assistente de Implantacao
    Copyright (c) 2026 Edsilas - Licenca Apache 2.0

.SYNOPSIS
    VigiaBOT: assistente inteligente de implantacao e parametrizacao do
    monitoramento de Servidor Windows (alertas via Telegram).

.DESCRIPTION
    Launcher guiado que automatiza TODO o processo de campo:
      - Verifica pre-requisitos (admin, PowerShell, conectividade 443).
      - Configura Telegram com validacao ao vivo (getMe) e DETECCAO
        AUTOMATICA do Chat ID (le a mensagem que voce enviar ao bot).
      - Sugere a MELHOR parametrizacao com base no proprio servidor
        (nucleos, RAM, discos, papel do servidor, servicos instalados).
      - Prepara o ambiente (firewall 443, TLS 1.2, ExecutionPolicy).
      - Instala/atualiza a tarefa agendada e, opcionalmente, o bot.
      - Testa ponta a ponta e mostra um painel de status.

    COMPATIBILIDADE / SEGURANCA DE DESIGN:
      - NAO modifica Monitor.ps1, Install-Monitor.ps1 nem o XML da tarefa.
      - Toda a parametrizacao e gravada em C:\Monitoramento\MonitorConfig.json,
        que o proprio Monitor.ps1 ja le e mescla sobre a config padrao.
      - A instalacao reusa o Install-Monitor.ps1 existente quando presente.
      - Edicoes no Monitor-Bot.ps1 (opcional) sao feitas com backup .bak.

.NOTES
    Runtime: Windows PowerShell 5.1 (ideal) ou PowerShell 7. Sem acentos no
    codigo para evitar mojibake em consoles legados (Server 2012R2/2016).
#>

[CmdletBinding()]
param(
    [switch]$Express,            # inicia direto a Implantacao Expressa
    [string]$InstallDir = 'C:\Monitoramento'
)

# ======================================================================
# 0. CONSTANTES / ESTADO GLOBAL
# ======================================================================
$ErrorActionPreference = 'Continue'
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$script:Src        = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$script:InstallDir = $InstallDir
$script:ConfigJson = Join-Path $InstallDir 'MonitorConfig.json'
$script:MonitorPs1 = Join-Path $InstallDir 'Monitor.ps1'
$script:InstallPs1 = Join-Path $InstallDir 'Install-Monitor.ps1'
$script:BotPs1     = Join-Path $InstallDir 'Monitor-Bot.ps1'
$script:TaskMon    = 'MonitoramentoServidor'
$script:TaskBot    = 'MonitoramentoBotTelegram'
$script:Token      = $env:MONITOR_TG_TOKEN
$script:TgHost     = 'api.telegram.org'

# Espelho dos padroes de fabrica do Monitor.ps1 (para exibir "config efetiva")
$script:Defaults = [ordered]@{
    CpuThreshold        = 80
    CpuSustainMinutes   = 5
    RamThreshold        = 80
    DiskThreshold       = 90
    ProcCpuThreshold    = 70
    ProcMemThresholdMB  = 2048
    AlertCooldownMin    = 30
    CriticalServices    = @('Spooler')
    MonitorAutoStopped  = $true
    MaxAutoStoppedAlerts= 10
    DbServicePrefixes   = @('MSSQL','MySQL','postgresql','OracleService')
}

# Arquivos-fonte que o launcher garante em C:\Monitoramento
$script:SourceFiles = @(
    'Monitor.ps1','MonitoramentoServidor.xml','Install-Monitor.ps1','Monitor-Bot.ps1'
)

# ======================================================================
# 1. UI / SAIDA
# ======================================================================
function Write-Rule { param([string]$Ch='=') Write-Host ($Ch * 70) -ForegroundColor DarkCyan }
function Write-Title {
    param([string]$Text)
    Write-Host ''
    Write-Rule
    Write-Host ("  " + $Text) -ForegroundColor Cyan
    Write-Rule
}
function Write-Step { param([string]$Text) Write-Host ("-> " + $Text) -ForegroundColor White }
function Write-Ok   { param([string]$Text) Write-Host ("[ OK ] " + $Text) -ForegroundColor Green }
function Write-Warn2{ param([string]$Text) Write-Host ("[AVISO] " + $Text) -ForegroundColor Yellow }
function Write-Err2 { param([string]$Text) Write-Host ("[ERRO] " + $Text) -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host ("       " + $Text) -ForegroundColor Gray }
function Pause-Enter { param([string]$Msg='Pressione ENTER para continuar...') Write-Host ''; [void](Read-Host $Msg) }

function Prompt-YesNo {
    param([string]$Question, [bool]$Default=$true)
    $suffix = if ($Default) { '[S/n]' } else { '[s/N]' }
    while ($true) {
        $r = (Read-Host ("{0} {1}" -f $Question, $suffix)).Trim()
        if ($r -eq '') { return $Default }
        switch -Regex ($r) {
            '^(s|sim|y|yes)$' { return $true }
            '^(n|nao|no)$'    { return $false }
            default { Write-Warn2 'Responda S ou N.' }
        }
    }
}

function Mask-Secret {
    param([string]$Value, [int]$Show=6)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '(vazio)' }
    if ($Value.Length -le $Show) { return ('*' * $Value.Length) }
    return ($Value.Substring(0,$Show) + ('*' * [math]::Min(10, $Value.Length-$Show)))
}

# ======================================================================
# 2. PRIVILEGIO / ELEVACAO
# ======================================================================
function Test-Admin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Invoke-SelfElevate {
    Write-Warn2 'Este assistente precisa de privilegios de Administrador.'
    if (-not (Prompt-YesNo 'Reabrir agora como Administrador?' $true)) { return $false }
    try {
        $exe  = (Get-Process -Id $PID).Path
        if (-not $exe) { $exe = 'powershell.exe' }
        $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File', ('"{0}"' -f $PSCommandPath))
        if ($Express) { $args += '-Express' }
        Start-Process -FilePath $exe -ArgumentList $args -Verb RunAs | Out-Null
        return $true
    } catch {
        Write-Err2 ("Nao foi possivel elevar: " + $_.Exception.Message)
        return $false
    }
}

# ======================================================================
# 3. CONECTIVIDADE (TCP 443, locale/versao-safe)
# ======================================================================
function Test-Tcp443 {
    param([string]$TargetHost=$script:TgHost, [int]$Port=443, [int]$TimeoutMs=3000)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($TargetHost, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
            $client.EndConnect($iar); return $true
        }
        return $false
    } catch { return $false }
    finally { if ($client) { try { $client.Close() } catch { } } }
}

function Test-Tcp443Cached {
    # Evita repetir o teste (com timeout) a cada redesenho do menu.
    if ($script:NetCacheTime -and ((Get-Date) - $script:NetCacheTime).TotalSeconds -lt 20) { return $script:NetCache }
    $script:NetCache     = Test-Tcp443
    $script:NetCacheTime = Get-Date
    return $script:NetCache
}

# ======================================================================
# 4. TELEGRAM (validacao + auto-deteccao de Chat ID)
# ======================================================================
function Test-TokenFormat { param([string]$T) return ($T -match '^\d{6,}:[A-Za-z0-9_-]{30,}$') }

function Resolve-Token {
    # Popula $script:Token a partir da variavel de ambiente ou do MonitorConfig.json.
    if ($script:Token -and (Test-TokenFormat $script:Token)) { return }
    $t = $env:MONITOR_TG_TOKEN
    if (-not $t) { $t = (Read-ConfigJson)['TelegramToken'] }
    if ($t) { $script:Token = "$t" }
}

function Invoke-TgApi {
    param([string]$Path, [hashtable]$Body, [int]$TimeoutSec=25, [switch]$Post)
    if (-not $script:Token) { return [pscustomobject]@{ ok=$false; error='token ausente' } }
    $uri = "https://$($script:TgHost)/bot$($script:Token)/$Path"
    try {
        if ($Post) {
            return Invoke-RestMethod -Uri $uri -Method Post -Body $Body -TimeoutSec $TimeoutSec -ErrorAction Stop
        }
        return Invoke-RestMethod -Uri $uri -TimeoutSec $TimeoutSec -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ ok=$false; error=$_.Exception.Message }
    }
}

function Get-BotIdentity {
    # Retorna o objeto 'result' do getMe, ou $null se o token nao autenticar.
    $r = Invoke-TgApi 'getMe'
    if ($r -and $r.ok) { return $r.result }
    return $null
}

function Read-TokenInteractive {
    Write-Step 'Informe o TOKEN do bot (obtido no @BotFather).'
    Write-Info 'Formato: 123456789:AAE...  (cole com os dois-pontos no meio)'
    while ($true) {
        $t = (Read-Host 'TOKEN').Trim().Trim('"').Trim("'")
        if ($t -eq '') { if (Prompt-YesNo 'Deixar em branco e cancelar?' $false) { return $null } else { continue } }
        if (-not (Test-TokenFormat $t)) {
            Write-Warn2 'Formato invalido. Verifique se copiou o token inteiro.'
            if (-not (Prompt-YesNo 'Tentar de novo?' $true)) { return $null }
            continue
        }
        $script:Token = $t
        Write-Step 'Validando o token com o Telegram...'
        $me = Get-BotIdentity
        if ($me) {
            Write-Ok ("Token valido. Bot conectado: @{0} ({1})" -f $me.username, $me.first_name)
            return $t
        }
        Write-Err2 'O Telegram rejeitou este token (nao autenticou).'
        if (-not (Prompt-YesNo 'Digitar outro token?' $true)) { return $null }
    }
}

function Find-ChatId {
    # Le a proxima mensagem enviada ao bot e extrai o(s) Chat ID(s).
    # Pausa o bot de comandos (se estiver rodando) para evitar conflito 409.
    $botState = Get-TaskState $script:TaskBot
    $botPaused = $false
    if ($botState -eq 'Running') {
        Write-Info 'Pausando temporariamente o bot de comandos para ler as mensagens...'
        schtasks /End /TN $script:TaskBot *> $null
        $botPaused = $true
        Start-Sleep -Seconds 2
    }

    try {
        # Zera o backlog: pega o ultimo update conhecido e avanca o offset.
        $off = 0
        $r0 = Invoke-TgApi 'getUpdates?offset=-1&timeout=0' -TimeoutSec 20
        if ($r0.ok -and $r0.result -and $r0.result.Count -gt 0) { $off = [int64]$r0.result[-1].update_id + 1 }

        Write-Host ''
        Write-Host '  >>> ABRA O SEU BOT NO TELEGRAM E ENVIE QUALQUER MENSAGEM (ex.: oi)' -ForegroundColor Yellow
        Write-Host '      (para grupo: adicione o bot ao grupo e mande uma mensagem la)' -ForegroundColor Yellow
        Write-Host '      Aguardando ate 90 segundos... (Ctrl+C cancela)' -ForegroundColor Gray
        Write-Host ''

        $found    = @{}
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline -and $found.Count -eq 0) {
            $r = Invoke-TgApi ("getUpdates?offset={0}&timeout=15" -f $off) -TimeoutSec 25
            if ($r.PSObject.Properties['error']) { Start-Sleep -Seconds 2; continue }
            if ($r.ok -and $r.result) {
                foreach ($u in $r.result) {
                    $off = [int64]$u.update_id + 1
                    $m = $u.message
                    if (-not $m) { $m = $u.channel_post }
                    if ($m -and $m.chat) {
                        $id = "$($m.chat.id)"
                        if (-not $found.ContainsKey($id)) {
                            $label = $null
                            if     ($m.chat.title)     { $label = $m.chat.title }
                            elseif ($m.chat.username)  { $label = '@' + $m.chat.username }
                            else { $label = (@($m.chat.first_name, $m.chat.last_name) | Where-Object { $_ }) -join ' ' }
                            if (-not $label) { $label = '(sem nome)' }
                            $found[$id] = [pscustomobject]@{ Id=$id; Label=$label.Trim(); Type=$m.chat.type }
                            Write-Ok ("Detectado: {0}  ->  {1} [{2}]" -f $label.Trim(), $id, $m.chat.type)
                        }
                    }
                }
            }
        }
        return @($found.Values)
    }
    finally {
        if ($botPaused) {
            Write-Info 'Reativando o bot de comandos...'
            schtasks /Run /TN $script:TaskBot *> $null
        }
    }
}

function Configure-Telegram {
    Write-Title 'CONFIGURACAO DO TELEGRAM'

    if ($script:Token -and (Test-TokenFormat $script:Token)) {
        $me = Get-BotIdentity
        if ($me) { Write-Ok ("Ja existe um token valido (@{0})." -f $me.username) }
        if (-not (Prompt-YesNo 'Deseja (re)configurar o token?' (-not $me))) { }
        else { $null = Read-TokenInteractive }
    } else {
        $null = Read-TokenInteractive
    }
    if (-not ($script:Token) -or -not (Test-TokenFormat $script:Token)) {
        Write-Err2 'Sem token valido; configuracao do Telegram abortada.'
        return $null
    }

    # --- Chat ID ---
    $chatId = $null
    Write-Host ''
    Write-Step 'Agora vamos definir o CHAT ID (para onde os alertas vao).'
    Write-Host '   [1] Detectar automaticamente (recomendado - le sua mensagem ao bot)' -ForegroundColor Gray
    Write-Host '   [2] Digitar manualmente' -ForegroundColor Gray
    $opt = (Read-Host 'Opcao [1]').Trim(); if ($opt -eq '') { $opt = '1' }

    if ($opt -eq '2') {
        $chatId = (Read-Host 'CHAT ID').Trim()
    } else {
        $list = Find-ChatId
        if (-not $list -or @($list).Count -eq 0) {
            Write-Warn2 'Nenhuma mensagem detectada a tempo.'
            if (Prompt-YesNo 'Digitar o Chat ID manualmente?' $true) { $chatId = (Read-Host 'CHAT ID').Trim() }
        } elseif (@($list).Count -eq 1) {
            $chatId = @($list)[0].Id
            Write-Ok ("Chat ID definido: {0} ({1})" -f $chatId, @($list)[0].Label)
        } else {
            Write-Host ''
            Write-Step 'Varios destinos detectados. Escolha um:'
            $i = 1
            foreach ($c in $list) { Write-Host ("   [{0}] {1}  ->  {2} [{3}]" -f $i, $c.Label, $c.Id, $c.Type); $i++ }
            $sel = [int]((Read-Host 'Numero') -as [int])
            if ($sel -ge 1 -and $sel -le @($list).Count) { $chatId = @($list)[$sel-1].Id }
        }
    }

    if ([string]::IsNullOrWhiteSpace($chatId)) {
        Write-Err2 'Chat ID nao definido; configuracao incompleta.'
        return $null
    }

    # --- Onde gravar as credenciais ---
    Write-Host ''
    Write-Step 'Onde gravar TOKEN e CHAT ID?'
    Write-Host '   [1] Arquivo de config (C:\Monitoramento) - funciona na hora, sem reiniciar  [recomendado]' -ForegroundColor Gray
    Write-Host '   [2] Variavel de maquina (mais isolado) - a tarefa SYSTEM pode exigir reinicio do servidor' -ForegroundColor Gray
    $modo = (Read-Host 'Opcao [1]').Trim(); if ($modo -eq '') { $modo = '1' }

    Save-Secrets -Token $script:Token -ChatId $chatId -Mode $modo

    # --- Teste imediato de envio ---
    if (Prompt-YesNo 'Enviar uma mensagem de teste agora?' $true) {
        $body = @{
            chat_id = $chatId
            text    = ("<b>Teste do Assistente</b>`nServidor: {0}`nData: {1}" -f $env:COMPUTERNAME, (Get-Date -Format 'dd/MM HH:mm:ss'))
            parse_mode = 'HTML'
        }
        $r = Invoke-TgApi 'sendMessage' -Body $body -Post
        if ($r.ok) { Write-Ok 'Mensagem de teste ENVIADA. Confira o Telegram.' }
        else       { Write-Err2 ("Falha no envio: " + ($(if ($r.PSObject.Properties['error']) { $r.error } else { 'resposta ok=false' }))) }
    }
    return $chatId
}

function Save-Secrets {
    param([string]$Token, [string]$ChatId, [string]$Mode)
    # Sempre disponibiliza no processo atual (para o -Test imediato funcionar).
    $env:MONITOR_TG_TOKEN  = $Token
    $env:MONITOR_TG_CHATID = $ChatId

    if ($Mode -eq '2') {
        # Variavel de maquina; remove do JSON para nao haver conflito de precedencia.
        try {
            [Environment]::SetEnvironmentVariable('MONITOR_TG_TOKEN',  $Token,  'Machine')
            [Environment]::SetEnvironmentVariable('MONITOR_TG_CHATID', $ChatId, 'Machine')
            Write-Ok 'Credenciais gravadas como variaveis de maquina.'
            Write-Info 'Se a tarefa (SYSTEM) nao enviar, reinicie o servidor para o SYSTEM enxergar as variaveis.'
        } catch { Write-Err2 ('Falha ao gravar variaveis: ' + $_.Exception.Message) }
        Remove-JsonKeys -Keys @('TelegramToken','TelegramChatId')
    } else {
        # Arquivo de config (autoritativo e lido diretamente pelo SYSTEM).
        Merge-ConfigJson -Values ([ordered]@{ TelegramToken=$Token; TelegramChatId=$ChatId })
        Write-Ok 'Credenciais gravadas em MonitorConfig.json.'
        Write-Info ('Local protegido (apenas Administradores): ' + $script:ConfigJson)
    }
}

# ======================================================================
# 5. CONFIG JSON (override que o Monitor.ps1 ja le e mescla)
# ======================================================================
function Read-ConfigJson {
    if (Test-Path $script:ConfigJson) {
        try {
            $o = Get-Content $script:ConfigJson -Raw | ConvertFrom-Json
            $h = [ordered]@{}
            foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
            return $h
        } catch { Write-Warn2 ('MonitorConfig.json ilegivel; sera recriado. ' + $_.Exception.Message) }
    }
    return [ordered]@{}
}

function Write-ConfigJson {
    param($Hash)
    if (-not (Test-Path $script:InstallDir)) { New-Item -ItemType Directory -Path $script:InstallDir -Force | Out-Null }
    ($Hash | ConvertTo-Json -Depth 8) | Set-Content -Path $script:ConfigJson -Encoding UTF8
}

function Merge-ConfigJson {
    param([Parameter(Mandatory)] $Values)   # ordered/hashtable de chaves a aplicar
    $cur = Read-ConfigJson
    foreach ($k in $Values.Keys) { $cur[$k] = $Values[$k] }
    Write-ConfigJson $cur
}

function Remove-JsonKeys {
    param([string[]]$Keys)
    if (-not (Test-Path $script:ConfigJson)) { return }
    $cur = Read-ConfigJson
    $changed = $false
    foreach ($k in $Keys) { if ($cur.Contains($k)) { $cur.Remove($k); $changed = $true } }
    if ($changed) { Write-ConfigJson $cur }
}

# ======================================================================
# 6. PARAMETRIZACAO INTELIGENTE
# ======================================================================
function Get-MachineFacts {
    $facts = [ordered]@{
        Cores=1; RamGB=0; ProductType=1; IsServer=$false; IsVM=$false
        Volumes=@(); Services=@(); DbFound=@(); WebFound=$false; SpoolerAuto=$false
    }
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $facts.Cores = [int]$cs.NumberOfLogicalProcessors
        if ($facts.Cores -lt 1) { $facts.Cores = 1 }
        $facts.RamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 0)
        $model = ("$($cs.Manufacturer) $($cs.Model)")
        if ($model -match 'Virtual|VMware|KVM|Xen|Hyper-V|QEMU|Bochs') { $facts.IsVM = $true }
    } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $facts.ProductType = [int]$os.ProductType   # 1=workstation, 2=DC, 3=server
        $facts.IsServer = ($facts.ProductType -ne 1)
        if ($facts.RamGB -le 0) { $facts.RamGB = [math]::Round($os.TotalVisibleMemorySize/1MB,0) }
    } catch { }
    try {
        $facts.Volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
            $usedPct = if ($_.Size -gt 0) { [math]::Round((($_.Size-$_.FreeSpace)/$_.Size)*100,1) } else { 0 }
            [pscustomobject]@{ Id=$_.DeviceID; SizeGB=[math]::Round($_.Size/1GB,1); UsedPct=$usedPct }
        })
    } catch { }
    try {
        $svc = @(Get-CimInstance Win32_Service -ErrorAction Stop | Select-Object Name,DisplayName,StartMode,State)
        $facts.Services = $svc
        $facts.DbFound = @($svc | Where-Object { $_.Name -match '^(MSSQL(SERVER|\$.+)|MySQL\d*|postgresql.*|OracleService.+)$' } | Select-Object -ExpandProperty Name)
        $facts.WebFound = [bool](@($svc | Where-Object { $_.Name -eq 'W3SVC' }).Count)
        $sp = $svc | Where-Object { $_.Name -eq 'Spooler' } | Select-Object -First 1
        if ($sp -and $sp.StartMode -match 'Auto') { $facts.SpoolerAuto = $true }
    } catch { }
    return $facts
}

function Get-SuggestedConfig {
    param($Facts)
    $s = [ordered]@{}
    # CPU / RAM
    $s['CpuThreshold']      = 80
    $s['CpuSustainMinutes'] = 5
    $s['RamThreshold']      = if ($Facts.RamGB -gt 0 -and $Facts.RamGB -le 4) { 85 } else { 80 }
    $s['DiskThreshold']     = 90
    $s['ProcCpuThreshold']  = 70
    # Memoria por processo escala com a RAM total (evita ruido em servidores grandes)
    $pmem = 2048
    if     ($Facts.RamGB -ge 64) { $pmem = 8192 }
    elseif ($Facts.RamGB -ge 32) { $pmem = 4096 }
    $s['ProcMemThresholdMB'] = $pmem
    $s['AlertCooldownMin']   = 30
    $s['MaxAutoStoppedAlerts']= 10
    # Servicos criticos sugeridos = bancos + IIS (+ Spooler so se Auto)
    $crit = New-Object System.Collections.Generic.List[string]
    foreach ($n in $Facts.DbFound) { if (-not $crit.Contains($n)) { $crit.Add($n) } }
    if ($Facts.WebFound -and -not $crit.Contains('W3SVC')) { $crit.Add('W3SVC') }
    if ($Facts.SpoolerAuto -and -not $crit.Contains('Spooler')) { $crit.Add('Spooler') }
    if ($crit.Count -eq 0) { $crit.Add('Spooler') }   # mantem o padrao de fabrica
    $s['CriticalServices'] = @($crit)
    # Em estacao de trabalho ha muitos servicos trigger-start; reduz ruido.
    $s['MonitorAutoStopped'] = [bool]$Facts.IsServer
    return $s
}

function Show-Facts {
    param($Facts)
    Write-Step 'Perfil detectado do servidor:'
    Write-Info ("Nucleos logicos : {0}" -f $Facts.Cores)
    Write-Info ("Memoria RAM      : {0} GB" -f $Facts.RamGB)
    Write-Info ("Papel            : {0}{1}" -f $(if($Facts.IsServer){'Servidor'}else{'Estacao'}), $(if($Facts.IsVM){' (VM)'}else{''}))
    if ($Facts.Volumes.Count) {
        $vtxt = ($Facts.Volumes | ForEach-Object { "{0} {1}GB/{2}%" -f $_.Id,$_.SizeGB,$_.UsedPct }) -join '  '
        Write-Info ("Volumes          : {0}" -f $vtxt)
    }
    if ($Facts.DbFound.Count) { Write-Info ("Banco de dados   : {0}" -f ($Facts.DbFound -join ', ')) }
    if ($Facts.WebFound)      { Write-Info  "Web (IIS/W3SVC)  : presente" }
    if ($Facts.IsVM)          { Write-Warn2 'Servidor virtual: em caso de falso REDE_DOWN, confira o gateway virtual.' }
}

function Show-ConfigTable {
    param($Suggested, $Facts)
    Write-Host ''
    Write-Step 'Parametrizacao sugerida (Enter aceita tudo; voce podera ajustar):'
    Write-Host ''
    Write-Host ('   {0,-22}{1,-12}{2}' -f 'PARAMETRO','SUGERIDO','PADRAO') -ForegroundColor DarkGray
    Write-Host ('   ' + ('-'*58)) -ForegroundColor DarkGray
    foreach ($k in $Suggested.Keys) {
        $sug = $Suggested[$k]; $def = $script:Defaults[$k]
        if ($sug -is [array]) { $sug = ($sug -join ',') }
        if ($def -is [array]) { $def = ($def -join ',') }
        $mark = if ("$sug" -ne "$def") { '*' } else { ' ' }
        Write-Host ('  {0}{1,-22}{2,-12}{3}' -f $mark, $k, "$sug", "$def")
    }
    Write-Host ''
    Write-Info '(*) diferente do padrao de fabrica, ajustado ao seu ambiente.'
}

function Edit-ConfigInteractive {
    param($Suggested)
    $out = [ordered]@{}
    foreach ($k in $Suggested.Keys) { $out[$k] = $Suggested[$k] }
    if (-not (Prompt-YesNo 'Ajustar algum parametro manualmente?' $false)) { return $out }

    Write-Info 'Deixe em branco para manter o valor sugerido.'
    foreach ($k in @('CpuThreshold','CpuSustainMinutes','RamThreshold','DiskThreshold','ProcCpuThreshold','ProcMemThresholdMB','AlertCooldownMin','MaxAutoStoppedAlerts')) {
        $cur = $out[$k]
        $v = (Read-Host ("{0} [{1}]" -f $k, $cur)).Trim()
        if ($v -ne '') { $n = ($v -as [int]); if ($null -ne $n) { $out[$k] = $n } else { Write-Warn2 "Valor nao numerico ignorado." } }
    }
    # Servicos criticos
    $curSvc = (@($out['CriticalServices']) -join ',')
    $v = (Read-Host ("CriticalServices (separados por virgula) [{0}]" -f $curSvc)).Trim()
    if ($v -ne '') { $out['CriticalServices'] = @($v -split '\s*,\s*' | Where-Object { $_ }) }
    # MonitorAutoStopped
    $out['MonitorAutoStopped'] = Prompt-YesNo ("Vigiar TODOS os servicos automaticos parados? (atual: {0})" -f $out['MonitorAutoStopped']) ([bool]$out['MonitorAutoStopped'])
    return $out
}

function Configure-Parameters {
    Write-Title 'PARAMETRIZACAO INTELIGENTE'
    Write-Step 'Analisando o servidor...'
    $facts = Get-MachineFacts
    Show-Facts $facts
    $sug = Get-SuggestedConfig $facts
    Show-ConfigTable -Suggested $sug -Facts $facts
    $final = Edit-ConfigInteractive $sug

    # Normaliza tipos e grava
    $typed = [ordered]@{}
    foreach ($k in $final.Keys) {
        $val = $final[$k]
        if ($k -eq 'CriticalServices')      { $typed[$k] = @([string[]]$val) }
        elseif ($k -eq 'MonitorAutoStopped'){ $typed[$k] = [bool]$val }
        else                                { $typed[$k] = [int]$val }
    }
    Merge-ConfigJson -Values $typed
    Write-Ok  'Parametrizacao gravada em MonitorConfig.json.'
    Write-Info 'A proxima ronda (ate 5 min) ja usa estes valores. Nao precisa reinstalar.'
    return $typed
}

# ======================================================================
# 7. AMBIENTE (firewall / TLS / execution policy / copia de arquivos)
# ======================================================================
function Ensure-Folders {
    foreach ($d in @($script:InstallDir, (Join-Path $script:InstallDir 'logs'))) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function Copy-SourceFiles {
    Ensure-Folders
    $copied = 0
    foreach ($f in $script:SourceFiles) {
        $from = Join-Path $script:Src $f
        $to   = Join-Path $script:InstallDir $f
        if (-not (Test-Path $from)) { continue }
        try {
            $ff = [IO.Path]::GetFullPath($from); $tt = [IO.Path]::GetFullPath($to)
            if ($ff -ieq $tt) { continue }
            Copy-Item -Path $from -Destination $to -Force
            $copied++
        } catch { Write-Warn2 ("Nao copiei {0}: {1}" -f $f, $_.Exception.Message) }
    }
    if ($copied -gt 0) { Write-Ok ("Arquivos copiados para {0} ({1})." -f $script:InstallDir, $copied) }
    else { Write-Info ("Arquivos ja estao em {0}." -f $script:InstallDir) }
}

function Add-FirewallRule {
    param([string]$Name, [string]$Program)
    if (-not (Test-Path $Program)) { return }
    netsh advfirewall firewall delete rule name="$Name" *> $null
    netsh advfirewall firewall add rule name="$Name" dir=out action=allow program="$Program" protocol=TCP remoteport=443 enable=yes profile=any *> $null
}

function Prepare-Environment {
    Write-Title 'PREPARACAO DO AMBIENTE'
    Ensure-Folders
    Write-Step 'Liberando firewall de saida (HTTPS 443 para o Telegram)...'
    $ps64  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $ps32  = Join-Path $env:SystemRoot 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    $pwsh  = 'C:\Program Files\PowerShell\7\pwsh.exe'
    Add-FirewallRule 'Monitoramento - Telegram HTTPS (PS64)'  $ps64
    Add-FirewallRule 'Monitoramento - Telegram HTTPS (PS32)'  $ps32
    Add-FirewallRule 'Monitoramento - Telegram HTTPS (pwsh)'  $pwsh
    Write-Ok 'Regras de firewall aplicadas.'

    Write-Step 'Habilitando TLS 1.2 forte no .NET Framework...'
    foreach ($base in @('HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319','HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319')) {
        try {
            if (-not (Test-Path $base)) { New-Item -Path $base -Force | Out-Null }
            New-ItemProperty -Path $base -Name 'SchUseStrongCrypto' -Value 1 -PropertyType DWord -Force | Out-Null
        } catch { }
    }
    Write-Ok 'TLS 1.2 forte configurado.'

    Write-Step 'Ajustando ExecutionPolicy (LocalMachine = RemoteSigned)...'
    try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop; Write-Ok 'ExecutionPolicy ajustada.' }
    catch { Write-Warn2 ('Nao consegui ajustar a ExecutionPolicy: ' + $_.Exception.Message) }

    Write-Step 'Testando conectividade com api.telegram.org:443...'
    if (Test-Tcp443) { Write-Ok 'Porta 443 acessivel.' }
    else { Write-Err2 'FALHOU. Libere api.telegram.org:443 no firewall de borda/proxy.' }
}

# ======================================================================
# 8. RUNTIME / TAREFAS
# ======================================================================
function Resolve-Runtime {
    $p = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if ($p) { return $p }
    if (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') { return 'C:\Program Files\PowerShell\7\pwsh.exe' }
    return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function Get-TaskState {
    param([string]$Name)
    try { $t = Get-ScheduledTask -TaskName $Name -ErrorAction Stop; return "$($t.State)" } catch { }
    $out = schtasks /Query /TN $Name /FO LIST 2>$null
    if (-not $out) { return 'NotFound' }
    foreach ($l in $out) { if ($l -match ':\s*(Ready|Running|Disabled|Pronto|Em execu)') { return ($l -split ':',2)[1].Trim() } }
    return 'Unknown'
}

function Install-Task {
    Write-Title 'INSTALACAO DA TAREFA DE MONITORAMENTO'
    Copy-SourceFiles
    if (-not (Test-Path $script:MonitorPs1)) { Write-Err2 "Monitor.ps1 nao encontrado em $($script:InstallDir)."; return }

    if (Test-Path $script:InstallPs1) {
        Write-Step 'Reutilizando o instalador oficial (Install-Monitor.ps1 -Install)...'
        try {
            & $script:InstallPs1 -Install -InstallDir $script:InstallDir
            Write-Ok 'Tarefa registrada via Install-Monitor.ps1.'
        } catch {
            Write-Err2 ('Install-Monitor.ps1 falhou: ' + $_.Exception.Message)
            Install-TaskFallback
        }
    } else {
        Write-Warn2 'Install-Monitor.ps1 ausente; usando registro direto por XML.'
        Install-TaskFallback
    }
    $st = Get-TaskState $script:TaskMon
    Write-Info ("Estado da tarefa '{0}': {1}" -f $script:TaskMon, $st)
}

function Install-TaskFallback {
    $xml = Join-Path $script:InstallDir 'MonitoramentoServidor.xml'
    if (Test-Path $xml) {
        $out = schtasks /Create /TN $script:TaskMon /XML "$xml" /RU 'SYSTEM' /F 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Ok 'Tarefa registrada a partir do XML.' }
        else { Write-Err2 ("schtasks falhou: " + ($out -join ' ')) }
    } else {
        $rt = Resolve-Runtime
        $tr = ('"{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}"' -f $rt, $script:MonitorPs1)
        schtasks /Create /TN $script:TaskMon /TR $tr /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F *> $null
        if ($LASTEXITCODE -eq 0) { Write-Ok 'Tarefa registrada (a cada 5 min, SYSTEM).' }
        else { Write-Err2 'Nao foi possivel registrar a tarefa.' }
    }
}

function Install-Bot {
    Write-Title 'BOT DE COMANDOS DO TELEGRAM (opcional)'
    if (-not (Test-Path $script:BotPs1)) {
        Copy-SourceFiles
        if (-not (Test-Path $script:BotPs1)) { Write-Warn2 'Monitor-Bot.ps1 nao encontrado; etapa ignorada.'; return }
    }
    $rt = Resolve-Runtime
    Write-Info ("Runtime do bot: {0}" -f $rt)

    # Ajuste opcional (com backup) do AllowedChatIds para o Chat ID atual
    $chatId = if ($env:MONITOR_TG_CHATID) { $env:MONITOR_TG_CHATID } else { (Read-ConfigJson)['TelegramChatId'] }
    if ($chatId) {
        try {
            $raw = Get-Content $script:BotPs1 -Raw
            if ($raw -notmatch [regex]::Escape("'$chatId'")) {
                if (Prompt-YesNo ("Autorizar o Chat ID {0} a enviar comandos ao bot? (edita Monitor-Bot.ps1 com backup)" -f $chatId) $true) {
                    Copy-Item $script:BotPs1 ($script:BotPs1 + '.bak') -Force
                    $new = [regex]::Replace($raw, "AllowedChatIds\s*=\s*@\([^\)]*\)", ("AllowedChatIds = @('{0}')" -f $chatId), 1)
                    Set-Content -Path $script:BotPs1 -Value $new -Encoding UTF8
                    Write-Ok ('AllowedChatIds atualizado. Backup: ' + $script:BotPs1 + '.bak')
                }
            } else { Write-Info 'Chat ID ja autorizado no bot.' }
        } catch { Write-Warn2 ('Nao consegui ajustar AllowedChatIds: ' + $_.Exception.Message) }
    }

    Write-Step 'Registrando a tarefa do bot (inicia no boot, SYSTEM)...'
    $tr = ('"{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}"' -f $rt, $script:BotPs1)
    schtasks /End /TN $script:TaskBot *> $null
    schtasks /Create /TN $script:TaskBot /TR $tr /SC ONSTART /RU SYSTEM /RL HIGHEST /F *> $null
    if ($LASTEXITCODE -eq 0) {
        schtasks /Run /TN $script:TaskBot *> $null
        Write-Ok 'Bot registrado e iniciado. Teste no Telegram: /help  e  /status'
    } else { Write-Err2 'Falha ao registrar a tarefa do bot.' }
}

# ======================================================================
# 9. TESTE / STATUS / ROLLBACK
# ======================================================================
function Test-Now {
    Write-Title 'TESTE PONTA A PONTA'
    Resolve-Token
    Write-Step ("Conectividade 443 : " + $(if (Test-Tcp443) { 'OK' } else { 'FALHOU' }))
    if ($script:Token -and (Test-TokenFormat $script:Token)) {
        $me = Get-BotIdentity
        Write-Step ("Token Telegram    : " + $(if ($me) { "VALIDO (@$($me.username))" } else { 'INVALIDO' }))
    } else { Write-Step 'Token Telegram    : NAO CONFIGURADO' }

    if (-not (Test-Path $script:MonitorPs1)) { Write-Warn2 'Monitor.ps1 ainda nao esta instalado. Rode a instalacao antes.'; return }
    $rt = Resolve-Runtime
    Write-Step ("Executando Monitor.ps1 -Test com {0}..." -f $rt)
    Write-Host ''
    & $rt -NoProfile -ExecutionPolicy Bypass -File $script:MonitorPs1 -Test
    Write-Host ''
    Write-Info 'Se recebeu a mensagem no Telegram, a implantacao esta validada.'
}

function Show-Status {
    Write-Title 'PAINEL DE STATUS'
    Write-Step 'Tarefas agendadas:'
    Write-Info ("{0,-28}: {1}" -f $script:TaskMon, (Get-TaskState $script:TaskMon))
    Write-Info ("{0,-28}: {1}" -f $script:TaskBot, (Get-TaskState $script:TaskBot))

    Write-Host ''
    Write-Step 'Credenciais:'
    $jt = (Read-ConfigJson)['TelegramToken']
    $tok = if ($jt) { $jt } elseif ($env:MONITOR_TG_TOKEN) { $env:MONITOR_TG_TOKEN } else { $null }
    $cid = (Read-ConfigJson)['TelegramChatId']; if (-not $cid) { $cid = $env:MONITOR_TG_CHATID }
    Write-Info ("Token  : {0}" -f (Mask-Secret $tok))
    Write-Info ("ChatID : {0}" -f $(if ($cid) { $cid } else { '(nao definido)' }))
    Write-Info ("Origem : {0}" -f $(if ($jt) { 'MonitorConfig.json' } elseif ($env:MONITOR_TG_TOKEN) { 'Variavel de maquina' } else { 'nenhuma' }))

    Write-Host ''
    Write-Step 'Config efetiva (padrao + overrides do JSON):'
    $ov = Read-ConfigJson
    foreach ($k in $script:Defaults.Keys) {
        $def = $script:Defaults[$k]; if ($def -is [array]) { $def = ($def -join ',') }
        if ($ov.Contains($k)) {
            $val = $ov[$k]; if ($val -is [array]) { $val = ($val -join ',') }
            Write-Host ('  * {0,-22}{1}' -f $k, "$val") -ForegroundColor Green
        } else {
            Write-Host ('    {0,-22}{1}' -f $k, "$def") -ForegroundColor Gray
        }
    }

    Write-Host ''
    Write-Step 'Ultimas linhas do log:'
    $log = Join-Path $script:InstallDir 'logs\monitor.log'
    if (Test-Path $log) { Get-Content $log -Tail 12 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ('   ' + $_) -ForegroundColor DarkGray } }
    else { Write-Info '(log ainda nao gerado)' }
}

function Do-Rollback {
    Write-Title 'REMOCAO / ROLLBACK'
    Write-Warn2 'Isto ira parar a vigilancia e remover as tarefas agendadas.'
    if (-not (Prompt-YesNo 'Confirmar remocao das tarefas?' $false)) { Write-Info 'Cancelado.'; return }

    if (Test-Path $script:InstallPs1) { try { & $script:InstallPs1 -Uninstall -InstallDir $script:InstallDir } catch { } }
    schtasks /Delete /TN $script:TaskMon /F *> $null
    schtasks /End    /TN $script:TaskBot *> $null
    schtasks /Delete /TN $script:TaskBot /F *> $null
    Write-Ok 'Tarefas removidas.'

    if (Prompt-YesNo 'Remover regras de firewall criadas pelo assistente?' $true) {
        foreach ($n in @('Monitoramento - Telegram HTTPS (PS64)','Monitoramento - Telegram HTTPS (PS32)','Monitoramento - Telegram HTTPS (pwsh)')) {
            netsh advfirewall firewall delete rule name="$n" *> $null
        }
        Write-Ok 'Regras de firewall removidas.'
    }
    if (Prompt-YesNo 'Remover variaveis de maquina (Token/Chat ID)?' $false) {
        [Environment]::SetEnvironmentVariable('MONITOR_TG_TOKEN',  $null, 'Machine')
        [Environment]::SetEnvironmentVariable('MONITOR_TG_CHATID', $null, 'Machine')
        Write-Ok 'Variaveis removidas.'
    }
    Write-Info ("A pasta {0} foi mantida. Apague manualmente se desejar." -f $script:InstallDir)
}

# ======================================================================
# 10. FLUXO EXPRESSO
# ======================================================================
function Invoke-Express {
    Write-Title 'IMPLANTACAO EXPRESSA'
    Write-Info 'Vamos configurar tudo do zero em poucos passos.'
    Write-Host ''
    Copy-SourceFiles
    Prepare-Environment
    $chat = Configure-Telegram
    if (-not $chat) { Write-Warn2 'Telegram nao configurado; voce pode retomar pelo menu (opcao 2).' }
    Configure-Parameters | Out-Null
    Install-Task
    if (Prompt-YesNo 'Instalar tambem o bot de comandos (/status, /log, ...)?' $false) { Install-Bot }
    if (Prompt-YesNo 'Rodar o teste ponta a ponta agora?' $true) { Test-Now }
    Write-Title 'IMPLANTACAO CONCLUIDA'
    Write-Ok  'O servidor agora avisa sozinho no Telegram quando algo der errado.'
    Write-Info 'Silencio = tudo certo. Use a opcao 8 (Painel) para acompanhar.'
}

# ======================================================================
# 11. MENU PRINCIPAL
# ======================================================================
function Show-Header {
    $admin = if (Test-Admin) { 'SIM' } else { 'NAO' }
    $net   = if (Test-Tcp443Cached) { 'OK' } else { 'FALHOU' }
    $psv   = "$($PSVersionTable.PSVersion)"
    Clear-Host
    Write-Rule
    Write-Host '  ASSISTENTE DE IMPLANTACAO - MONITORAMENTO DE SERVIDOR (TELEGRAM)' -ForegroundColor Cyan
    Write-Rule
    Write-Host ("  Servidor: {0} | PowerShell: {1} | Admin: {2} | Telegram(443): {3}" -f $env:COMPUTERNAME, $psv, $admin, $net) -ForegroundColor DarkGray
    Write-Rule
}

function Show-Menu {
    Write-Host ''
    Write-Host '  [1] Implantacao Expressa (recomendado) - configura tudo, guiado' -ForegroundColor White
    Write-Host '  [2] Configurar Telegram (token + deteccao automatica do Chat ID)'
    Write-Host '  [3] Parametrizacao inteligente (limiares e servicos sugeridos)'
    Write-Host '  [4] Preparar ambiente (firewall 443, TLS 1.2, ExecutionPolicy)'
    Write-Host '  [5] Instalar / atualizar tarefa de monitoramento (5 min)'
    Write-Host '  [6] Instalar / atualizar bot de comandos (opcional)'
    Write-Host '  [7] Testar agora (diagnostico + mensagem no Telegram)'
    Write-Host '  [8] Painel de status (tarefas, config efetiva, log)'
    Write-Host '  [9] Remover / Rollback' -ForegroundColor DarkYellow
    Write-Host '  [0] Sair'
    Write-Host ''
}

function Main {
    Resolve-Token
    if (-not (Test-Admin)) {
        Show-Header
        if (Invoke-SelfElevate) { return }
        Write-Err2 'Sem privilegios de Administrador, varias etapas irao falhar.'
        if (-not (Prompt-YesNo 'Continuar mesmo assim (nao recomendado)?' $false)) { return }
    }

    if ($Express) { Invoke-Express; Pause-Enter; return }

    while ($true) {
        Show-Header
        Show-Menu
        $op = (Read-Host 'Escolha uma opcao').Trim()
        switch ($op) {
            '1' { Invoke-Express;        Pause-Enter }
            '2' { Configure-Telegram | Out-Null; Pause-Enter }
            '3' { Configure-Parameters | Out-Null; Pause-Enter }
            '4' { Prepare-Environment;   Pause-Enter }
            '5' { Install-Task;          Pause-Enter }
            '6' { Install-Bot;           Pause-Enter }
            '7' { Test-Now;              Pause-Enter }
            '8' { Show-Status;           Pause-Enter }
            '9' { Do-Rollback;           Pause-Enter }
            '0' { Write-Host 'Ate logo.' -ForegroundColor Cyan; return }
            default { Write-Warn2 'Opcao invalida.'; Start-Sleep -Milliseconds 800 }
        }
    }
}

Main
