<#
    report-env.ps1
    Envía variables de entorno concretas al endpoint POST /variables.
#>

param(
    [string]$ApiUrl = "https://rd.ngrok.dev/variables"
)

# Variables que SÍ queremos mandar
$vars = @("PATH", "HOME", "USER", "SHELL", "LANG")

$payload = @{}
foreach ($name in $vars) {
    $value = [System.Environment]::GetEnvironmentVariable($name)
    if ($value) { $payload[$name] = $value }
}

$body = $payload | ConvertTo-Json -Depth 2

Write-Host "Payload que se enviará:" -ForegroundColor Cyan
Write-Host $body

try {
    $resp = Invoke-RestMethod -Uri $ApiUrl -Method Post `
                              -ContentType "application/json" `
                              -Body $body -TimeoutSec 10
    Write-Host "`nRespuesta del servidor:" -ForegroundColor Green
    Write-Host ($resp | ConvertTo-Json -Depth 4)
}
catch {
    Write-Host "`nError al contactar el servicio:" -ForegroundColor Yellow
    Write-Host $_.Exception.Message
}
