#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Instala, remove ou testa a tarefa de Monitoramento do Servidor.
    Escolhe automaticamente o runtime: PowerShell 7 (pwsh) se existir,
    senao Windows PowerShell 5.1/4.0 (powershell.exe).

.EXAMPLE
    .\Install-Monitor.ps1 -Install
    .\Install-Monitor.ps1 -Test
    .\Install-Monitor.ps1 -Uninstall
#>
[CmdletBinding(DefaultParameterSetName='Install')]
param(
    [Parameter(ParameterSetName='Install')]  [switch]$Install,
    [Parameter(ParameterSetName='Uninstall')][switch]$Uninstall,
    [Parameter(ParameterSetName='Test')]     [switch]$Test,
    [string]$TaskName    = 'MonitoramentoServidor',
    [string]$InstallDir  = 'C:\Monitoramento',
    [string]$Runtime     = ''   # opcional: caminho do pwsh.exe ou powershell.exe
)

$ErrorActionPreference = 'Stop'
$src    = $PSScriptRoot
$script = Join-Path $InstallDir 'Monitor.ps1'
$xmlOut = Join-Path $InstallDir 'MonitoramentoServidor.xml'

function Resolve-Runtime {
    if ($Runtime -and (Test-Path $Runtime)) { return $Runtime }
    $p = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if ($p) { return $p }
    if (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') { return 'C:\Program Files\PowerShell\7\pwsh.exe' }
    return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function Copy-IfNeeded {
    param([string]$From, [string]$To)
    if (-not (Test-Path $From)) { Write-Warning "Origem nao encontrada: $From"; return }
    $f = [System.IO.Path]::GetFullPath($From)
    $t = [System.IO.Path]::GetFullPath($To)
    if ($f -ieq $t) { Write-Host "  Ja no destino: $To (copia ignorada)"; return }
    Copy-Item -Path $From -Destination $To -Force
    Write-Host "  Copiado: $To"
}

function New-TaskXml {
    param([string]$RuntimePath, [string]$ScriptPath)
@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Monitoramento de servidor Windows com alertas via Telegram. Executa a cada 5 minutos.</Description>
    <Author>Infraestrutura</Author>
    <URI>\$($TaskName)</URI>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>2025-01-01T00:00:00</StartBoundary>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>PT5M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </TimeTrigger>
    <BootTrigger>
      <Enabled>true</Enabled>
      <Delay>PT2M</Delay>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT4M</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$($RuntimePath)</Command>
      <Arguments>-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$($ScriptPath)"</Arguments>
      <WorkingDirectory>$($InstallDir)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
}

function Install-Monitor {
    if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
    Copy-IfNeeded (Join-Path $src 'Monitor.ps1') $script
    if (-not (Test-Path $script)) { throw "Monitor.ps1 nao encontrado em $InstallDir." }

    $rt = Resolve-Runtime
    Write-Host "Runtime escolhido: $rt"

    $xml = New-TaskXml -RuntimePath $rt -ScriptPath $script
    $xml | Out-File -FilePath $xmlOut -Encoding Unicode -Force
    Write-Host "XML da tarefa gerado: $xmlOut"

    Write-Host "Registrando tarefa '$TaskName'..."
    $out = schtasks /Create /TN $TaskName /XML "$xmlOut" /RU "SYSTEM" /F 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "schtasks falhou: $out. Tentando Register-ScheduledTask..."
        Register-ScheduledTask -TaskName $TaskName -Xml (Get-Content $xmlOut -Raw) -Force | Out-Null
    }
    Write-Host "Tarefa registrada (SYSTEM, privilegios maximos, a cada 5 min, reinicia em falha)."
    Write-Host "Confirme Token/ChatID no Monitor.ps1 ou nas variaveis de maquina."
}

function Uninstall-Monitor {
    $out = schtasks /Delete /TN $TaskName /F 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Host "Tarefa '$TaskName' removida." }
    else { Write-Host "Tarefa '$TaskName' nao encontrada (ou ja removida)." }
}

function Test-Monitor {
    if (-not (Test-Path $script)) { throw "Monitor.ps1 nao encontrado em $script. Rode -Install primeiro." }
    $rt = Resolve-Runtime
    Write-Host "Testando com: $rt"
    & $rt -NoProfile -ExecutionPolicy Bypass -File $script -Test -Verbose
}

switch ($PSCmdlet.ParameterSetName) {
    'Install'   { Install-Monitor }
    'Uninstall' { Uninstall-Monitor }
    'Test'      { Test-Monitor }
}
