#!/usr/bin/env bash
#
# report-env.sh
# Envía variables de entorno concretas al endpoint POST /variables.
# Equivalente en bash del script saludo.ps1 (PowerShell).
#
# Uso:
#   ./report-env.sh                       # usa la URL por defecto
#   ./report-env.sh https://otra/url      # sobreescribe la URL

set -u

# Primer argumento opcional = URL del endpoint (igual que el param $ApiUrl en PowerShell)
API_URL="${1:-https://rd.ngrok.dev/variables}"

# Variables que SÍ queremos mandar
vars=(PATH HOME USER SHELL LANG)

# Armar el JSON solo con las variables que tengan valor
payload="{"
first=1
for name in "${vars[@]}"; do
  value="${!name-}"
  if [ -n "$value" ]; then
    # Escapar backslashes y comillas dobles para que el JSON sea válido
    esc=${value//\\/\\\\}
    esc=${esc//\"/\\\"}
    if [ "$first" -eq 0 ]; then
      payload+=","
    fi
    payload+="\"$name\":\"$esc\""
    first=0
  fi
done
payload+="}"

echo "Payload que se enviará:"
echo "$payload"
echo

# Enviar y mostrar la respuesta (timeout de 10s, como en el original)
if response=$(curl -sS -X POST "$API_URL" \
                   -H "Content-Type: application/json" \
                   -d "$payload" \
                   --max-time 10); then
  echo "Respuesta del servidor:"
  echo "$response"
else
  echo "Error al contactar el servicio."
fi
