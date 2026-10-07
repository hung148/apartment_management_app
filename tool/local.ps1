# Local test stack: Firebase emulators (Auth, Firestore, Functions) + the app
# on http://localhost:5300, all on this computer. Nothing is deployed and no
# cloud data is used (demo project "demo-canho360"). Run from the repository root:
#
#   powershell -ExecutionPolicy Bypass -File tool\local.ps1
#       Starts the emulators in a second window (with the saved local data),
#       creates the local test accounts, builds the app (release, into
#       build\local-web) and serves it here at http://localhost:5300; it
#       starts in any browser, including the Claude browser pane.
#       After app code changes: Ctrl+C here and run the command again
#       (about 1-2 minutes; the emulators keep running).
#       Server code (functions/) reloads by itself in the emulator window.
#       The local data is saved into .local-data\ for next time: every 5
#       minutes while the emulators run, and when the app is stopped with
#       Ctrl+C here (2026-10-04: the emulator window is hidden, so closing it
#       lost a whole day of data).
#
#   -Stop      save the data, then stop the emulators (use this instead of
#              closing any window).
#   -Save      save the running emulators' data now (into .local-data\).
#   -Fresh     start with empty data; the old data is moved to
#              .local-data-old-<time>\ (nothing is deleted).
#   -NoApp     start only the emulators (for example to run server checks).
#   -Debug     debug mode with hot reload (r) for your own Chrome; the Claude
#              browser pane cannot connect to debug mode.
#   -Java <folder>  use this Java (21 or newer) instead of searching for one.
param(
  [switch]$Save,
  [switch]$Stop,
  [switch]$Fresh,
  [switch]$NoApp,
  [switch]$Debug,
  [string]$Java = ''
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$root = (Get-Location).Path
$project = 'demo-canho360'
$firebase = 'functions/node_modules/firebase-tools/lib/bin/firebase.js'
$data = '.local-data'
$ports = @{ 'Auth' = 9199; 'Firestore' = 8180; 'Functions' = 5101 }
$hubPort = 4500
$pidFile = '.local-emulators.pid'

function Test-Port([int]$port) {
  $client = New-Object System.Net.Sockets.TcpClient
  try { $client.Connect('127.0.0.1', $port); return $true } catch { return $false } finally { $client.Dispose() }
}

function Save-Data {
  if (-not (Test-Port $hubPort)) { Write-Host 'Emulators are not running: nothing to save.'; return $false }
  Write-Host 'Saving local data into .local-data ...'
  node $firebase emulators:export $data --config firebase.local.json --project $project --force | Out-Null
  if ($LASTEXITCODE -eq 0) { Write-Host 'Local data saved.' -ForegroundColor Green; return $true }
  Write-Host 'Saving the local data FAILED.' -ForegroundColor Red
  return $false
}

if ($Save) {
  if (Save-Data) { exit 0 } else { exit 1 }
}

if ($Stop) {
  if (Test-Port $hubPort) {
    if (-not (Save-Data)) {
      Write-Host 'Not stopping, so nothing is lost. Try again, or run -Save first.' -ForegroundColor Red
      exit 1
    }
  }
  # The hidden emulator window and everything it started (Java, node).
  if (Test-Path $pidFile) {
    $emuPid = Get-Content $pidFile
    cmd /c "taskkill /T /F /PID $emuPid >nul 2>&1"
    Remove-Item $pidFile
  }
  # Anything still holding an emulator port (for example started by an older version of this script).
  foreach ($port in @($ports.Values) + @($hubPort, 4100, 4600, 9399)) {
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
      ForEach-Object { cmd /c "taskkill /T /F /PID $($_.OwningProcess) >nul 2>&1" }
  }
  Write-Host 'Emulators stopped.' -ForegroundColor Green
  exit 0
}

# The emulators need Java 21 or newer. The system Java setting is left alone
# (other programs such as Minecraft may need their own version): a suitable Java
# is searched for and used only inside the emulator window.
function Get-JavaMajor([string]$exe) {
  try {
    $out = cmd /c "`"$exe`" -version 2>&1" | Out-String
    if ($out -match 'version "(\d+)') { return [int]$Matches[1] }
  } catch {}
  return 0
}
function Find-Java {
  $candidates = @()
  if ($Java) { $candidates += (Join-Path $Java 'bin\java.exe'), (Join-Path $Java 'java.exe') }
  if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin\java.exe' }
  $onPath = Get-Command java -ErrorAction SilentlyContinue
  if ($onPath) { $candidates += $onPath.Source }
  foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs")) {
    if (-not $base) { continue }
    foreach ($vendor in @('Eclipse Adoptium', 'Java', 'Microsoft', 'Zulu', 'Amazon Corretto', 'BellSoft', 'Temurin')) {
      $dir = Join-Path $base $vendor
      if (Test-Path $dir) {
        $candidates += Get-ChildItem $dir -Directory | ForEach-Object { Join-Path $_.FullName 'bin\java.exe' }
      }
    }
  }
  $best = $null; $bestMajor = 0
  foreach ($exe in ($candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique)) {
    $major = Get-JavaMajor $exe
    Write-Host "  found Java $major at $exe"
    if ($major -gt $bestMajor) { $best = $exe; $bestMajor = $major }
  }
  if ($bestMajor -ge 21) { return $best }
  return $null
}
$javaExe = Find-Java
if (-not $javaExe) {
  Write-Host 'No Java 21 or newer found. Install Temurin 21 (JDK, Windows x64 .msi) from https://adoptium.net' -ForegroundColor Red
  Write-Host 'In the installer you can leave "Set JAVA_HOME" and "Add to PATH" OFF; this script finds it anyway.' -ForegroundColor Red
  Write-Host 'Or pass the folder of an existing Java 21+: tool\local.ps1 -Java "C:\path\to\jdk-21"' -ForegroundColor Red
  exit 1
}
$javaBin = Split-Path $javaExe -Parent
Write-Host "Using Java: $javaExe"
if (-not (Test-Path $firebase)) {
  Write-Host 'Run "npm install" in the functions folder first.' -ForegroundColor Red
  exit 1
}

if ($Fresh -and (Test-Path $data)) {
  $old = "$data-old-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Move-Item $data $old
  Write-Host "Old local data moved to $old"
}

$running = @($ports.Values | Where-Object { Test-Port $_ }).Count
if ($running -eq $ports.Count) {
  Write-Host 'Emulators already running.'
} else {
  if ($running -gt 0) {
    Write-Host 'Some emulator ports are busy but not all. Close the old emulator window first.' -ForegroundColor Red
    exit 1
  }
  $import = ''
  if (Test-Path $data) { $import = "--import $data" }
  $command = "Set-Location '$root'; `$env:Path = '$javaBin;' + `$env:Path; `$env:JAVA_HOME = '$(Split-Path $javaBin -Parent)'; `$host.UI.RawUI.WindowTitle = 'CanHo360 local emulators (Ctrl+C here saves data)'; node $firebase emulators:start --config firebase.local.json --project $project $import --export-on-exit $data"
  $emulators = Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoExit', '-Command', $command -PassThru
  Set-Content $pidFile $emulators.Id
  Write-Host 'Starting emulators in a new window...'
  $deadline = (Get-Date).AddSeconds(180)
  while (@($ports.Values | Where-Object { Test-Port $_ }).Count -lt $ports.Count) {
    if ((Get-Date) -gt $deadline) {
      Write-Host 'Emulators did not start within 3 minutes. Check the emulator window for the error.' -ForegroundColor Red
      exit 1
    }
    Start-Sleep -Seconds 2
  }
  Write-Host 'Emulators ready. Emulator UI: http://localhost:4100'
  # Auto-save every 5 minutes while the emulators run; it ends by itself when
  # they stop. It survives Ctrl+C in this window.
  $saver = "Set-Location '$root'; while (`$true) { Start-Sleep -Seconds 300; `$c = New-Object System.Net.Sockets.TcpClient; try { `$c.Connect('127.0.0.1', $hubPort) } catch { break } finally { `$c.Dispose() }; node $firebase emulators:export $data --config firebase.local.json --project $project --force | Out-Null }"
  Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $saver | Out-Null
  Write-Host 'Local data is saved every 5 minutes. To stop the emulators: tool\local.ps1 -Stop'
}

node tool/local_seed.cjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($NoApp) { exit 0 }
Write-Host ''
# Ctrl+C in this window stops the app and saves the local data (the emulators keep running).
try {
if ($Debug) {
  Write-Host 'App: http://localhost:5300   (debug: r = reload after changes, q = quit)' -ForegroundColor Green
  flutter run -d web-server --web-hostname localhost --web-port 5300 --dart-define=LOCAL_EMULATORS=true --dart-define=V2_ORG_CREATION=true
} else {
  # Own folder: a local build must never end up in build\web (production) or
  # build\staging-web. tool\local_serve.cjs serves it and forwards Firebase calls.
  flutter build web --release --output=build/local-web --dart-define=LOCAL_EMULATORS=true --dart-define=V2_ORG_CREATION=true
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Write-Host 'App: http://localhost:5300   (after app changes: Ctrl+C, then run this command again)' -ForegroundColor Green
  node tool/local_serve.cjs
}
} finally {
  [void](Save-Data)
}
