@echo off
setlocal enabledelayedexpansion

rem === report-env.bat ===
rem Envia variables de entorno concretas al endpoint POST /variables.
rem Version para cmd (Windows), equivalente a saludo.ps1 (PowerShell).
rem
rem Uso:
rem   report-env.bat                     (usa la URL por defecto)
rem   report-env.bat https://otra/url    (sobreescribe la URL)

rem URL del endpoint (primer argumento opcional, como el param $ApiUrl del .ps1)
set "API_URL=%~1"
if "%API_URL%"=="" set "API_URL=https://rd.ngrok.dev/variables"

rem Comilla doble reutilizable para armar el JSON a mano
set DQ="

rem Variables que SI queremos mandar (equivalentes Windows de las Unix del original)
set "VARS=PATH USERPROFILE USERNAME USERDOMAIN COMPUTERNAME"

set "JSON={"
set "SEP="
for %%V in (%VARS%) do (
    set "NAME=%%V"
    call set "VAL=%%!NAME!%%"
    if defined VAL (
        rem Escapar backslashes para que el JSON sea valido
        set "VAL=!VAL:\=\\!"
        set "JSON=!JSON!!SEP!!DQ!!NAME!!DQ!:!DQ!!VAL!!DQ!"
        set "SEP=,"
    )
)
set "JSON=!JSON!}"

rem Escribir el payload a un archivo temporal (evita problemas de comillas con curl)
set "TMPFILE=%TEMP%\report-env-payload.json"
> "%TMPFILE%" echo !JSON!

echo Payload que se enviara:
type "%TMPFILE%"
echo.

rem Enviar (curl viene incluido en Windows 10/11); timeout de 10s como el original
curl -s -S -X POST "%API_URL%" -H "Content-Type: application/json" --data-binary "@%TMPFILE%" --max-time 10
if errorlevel 1 (
    echo.
    echo Error al contactar el servicio.
)

del "%TMPFILE%" >nul 2>&1
endlocal
