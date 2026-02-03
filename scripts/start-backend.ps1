param(
  [int]$Port = 3000,
  [ValidateSet('0', '1')]
  [string]$UseDotenvLocal = '0'
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspaceRoot = Split-Path -Parent $scriptDir
$out = Join-Path $scriptDir 'backend.out.log'
$err = Join-Path $scriptDir 'backend.err.log'

# Variables que hereda el proceso Node
$env:PORT = "$Port"
$env:USE_DOTENV_LOCAL = "$UseDotenvLocal"

# Si ya hay algo escuchando en el puerto, lo detenemos
try {
  $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($conn) {
    Stop-Process -Id $conn.OwningProcess -Force
    Start-Sleep -Seconds 1
  }
} catch {}

if (Test-Path $out) { Remove-Item $out -Force }
if (Test-Path $err) { Remove-Item $err -Force }

Start-Process -FilePath node -WorkingDirectory $workspaceRoot -ArgumentList @('backend\server.js') -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
Start-Sleep -Seconds 1

$conn2 = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $conn2) {
  Write-Host "❌ Backend NO quedó escuchando en $Port." -ForegroundColor Red
  Write-Host "Revisa logs: $out y $err"
  exit 1
}

Write-Host "✅ Backend iniciado en http://127.0.0.1:$Port" -ForegroundColor Green
Write-Host "Logs: $out / $err"
