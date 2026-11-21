# Start the whole SmartFit backend locally, without Docker (Windows PowerShell).
#
#   cd backend
#   .\run_local.bat            # all services, each in its own window
#   .\run_local.bat -Stop      # stop them again
#
# Use the .bat: Windows blocks .ps1 files by default ("running scripts is
# disabled on this system"). The .bat runs this script with -ExecutionPolicy
# Bypass for that one run and changes nothing on the PC.
#
# Uses backend\.venv-cpu and the repo-root .env. Each service runs on its own
# port; the gateway (http://localhost:8000) is the only one the app and the
# admin panel talk to. API docs: http://localhost:8000/docs
param([switch]$Stop)

$ErrorActionPreference = 'Stop'
$backend = $PSScriptRoot
$python = Join-Path $backend '.venv-cpu\Scripts\python.exe'

# module -> port (same ports as docker-compose.yml)
$services = [ordered]@{
  'gateway.main:app'                    = 8000
  'services.cv_analysis.main:app'       = 8001
  'services.recommendation.main:app'    = 8002
  'services.scraper.main:app'           = 8003
  'services.chat_orchestrator.main:app' = 8004
  'services.tryon.main:app'             = 8005
  'services.hairstyle.main:app'         = 8006
  'services.scoring.main:app'           = 8007
}

if ($Stop) {
  Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
    Where-Object { $_.CommandLine -match 'uvicorn' -and $_.CommandLine -match '--port 800[0-7]' } |
    ForEach-Object {
      # the venv launcher and its child Python both match; one may already be gone
      Stop-Process -Id $_.ProcessId -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
  "SmartFit backend stopped."
  return
}

if (-not (Test-Path $python)) { throw "Missing $python. Create the venv first (see README)." }

# Inside Docker the services find each other by name; here they are all on this PC.
# 127.0.0.1, not "localhost": on Windows "localhost" tries IPv6 first and Python
# waits ~2 s for that to fail on every call between services.
$env:CV_ANALYSIS_URL       = 'http://127.0.0.1:8001'
$env:RECOMMENDATION_URL    = 'http://127.0.0.1:8002'
$env:SCRAPER_URL           = 'http://127.0.0.1:8003'
$env:CHAT_ORCHESTRATOR_URL = 'http://127.0.0.1:8004'
$env:TRYON_URL             = 'http://127.0.0.1:8005'
$env:HAIRSTYLE_URL         = 'http://127.0.0.1:8006'
$env:SCORING_URL           = 'http://127.0.0.1:8007'

foreach ($module in $services.Keys) {
  $port = $services[$module]
  Start-Process -FilePath $python -WorkingDirectory $backend -WindowStyle Minimized `
    -ArgumentList '-m', 'uvicorn', $module, '--host', '0.0.0.0', '--port', $port
  "started $module on http://localhost:$port"
}
"Recommendations need ~1 minute to load FashionCLIP on first start. Stop everything with: .\run_local.bat -Stop"
