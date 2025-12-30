$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $root 'backend.out.log'
$err = Join-Path $root 'backend.err.log'

# Si ya hay algo escuchando en 3000, lo detenemos
try {
  $conn = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($conn) {
    Stop-Process -Id $conn.OwningProcess -Force
    Start-Sleep -Seconds 1
  }
} catch {}

if (Test-Path $out) { Remove-Item $out -Force }
if (Test-Path $err) { Remove-Item $err -Force }

Start-Process -FilePath node -WorkingDirectory $root -ArgumentList @('backend\server.js') -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
Start-Sleep -Seconds 1

$conn2 = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $conn2) {
  Write-Host '❌ Backend NO quedó escuchando en 3000.' -ForegroundColor Red
  Write-Host "Revisa logs: $out y $err"
  exit 1
}

Write-Host '✅ Backend iniciado en http://127.0.0.1:3000' -ForegroundColor Green
Write-Host "Logs: $out / $err"
