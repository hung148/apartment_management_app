# One command for a staging release: check, test, deploy functions, build web,
# deploy hosting. Stops at the first step that fails, so nothing is deployed
# after a failed check. Analyze stops only on errors (the old code has many
# style hints and a few warnings). Run from the repository root:
#
#   powershell -ExecutionPolicy Bypass -File tool\staging_all.ps1
#       Full release. Skips the functions deploy when nothing in functions/
#       changed since the last successful one, and skips the web build and
#       hosting deploy when nothing the app is built from changed.
#
#   powershell -ExecutionPolicy Bypass -File tool\staging_all.ps1 -Tests booking_form,operational_workflows
#       Runs only these test files (test\<name>_test.dart) instead of all of
#       them. Use for small changes; run the full suite before production and
#       after changes to shared code (ws_ui, theme, services).
#
#   -Force         deploy functions and web even if nothing changed.
#   -MarkDeployed  only record the current functions as deployed (after a
#                  functions deploy made another way); runs nothing else.
param(
  [string[]]$Tests = @(),
  [switch]$Force,
  [switch]$MarkDeployed
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$stateDir = '.dart_tool/staging-all'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

# Fingerprint of a set of files (path + content), so an unchanged part is skipped.
function Get-Fingerprint([string[]]$paths, [string[]]$exclude) {
  $files = foreach ($p in $paths) {
    if (Test-Path $p -PathType Leaf) { Get-Item $p }
    elseif (Test-Path $p) { Get-ChildItem $p -Recurse -File }
  }
  $files = $files | Where-Object {
    $full = $_.FullName
    -not ($exclude | Where-Object { $full -like $_ })
  } | Sort-Object FullName
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $text = ($files | ForEach-Object {
    $rel = Resolve-Path -Relative $_.FullName
    "$rel=$((Get-FileHash $_.FullName -Algorithm SHA256).Hash)"
  }) -join "`n"
  return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '')
}
function Test-Changed([string]$name, [string]$hash) {
  $file = Join-Path $stateDir "$name.txt"
  if ($Force -or -not (Test-Path $file)) { return $true }
  return (Get-Content $file -Raw).Trim() -ne $hash
}
function Save-Done([string]$name, [string]$hash) {
  Set-Content -Path (Join-Path $stateDir "$name.txt") -Value $hash
}

# Every function is bundled from these files, so any change redeploys them all.
$functionsHash = Get-Fingerprint (Get-ChildItem functions -File | Where-Object { $_.Extension -in '.js', '.json' } | ForEach-Object { $_.FullName }) @()
$rulesHash = Get-Fingerprint @('firestore.rules') @()
$webHash = Get-Fingerprint @('lib', 'web', 'assets', 'pubspec.yaml', 'pubspec.lock', 'config/app_check.staging.json') @()

if ($MarkDeployed) {
  Save-Done 'functions' $functionsHash
  Write-Host 'Recorded the current functions as deployed.' -ForegroundColor Green
  exit 0
}

# "-Tests a,b" reaches the script as one string through -File; split it.
# A lone "*" means all tests: from Command Prompt (cmd), "*> deploy.txt" is not
# a redirect and passes "*" here (2026-10-09). Wildcards are never test names.
$Tests = @($Tests | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ -and $_ -notmatch '[*?\[\]]' })
$testCmd = if ($Tests.Count -gt 0) {
  # Always a list: one file name must not be split into letters by @files.
  $files = @($Tests | ForEach-Object { "test/$($_ -replace '_test(\.dart)?$','')_test.dart" })
  foreach ($f in $files) { if (-not (Test-Path -LiteralPath $f)) { Write-Host "No such test file: $f" -ForegroundColor Red; exit 1 } }
  { flutter test --concurrency=1 @files }.GetNewClosure()
} else {
  { flutter test --concurrency=1 }
}

$steps = @(
  @{ name = 'Analyze'; cmd = { flutter analyze --no-fatal-infos --no-fatal-warnings } },
  @{ name = $(if ($Tests.Count) { "Tests ($($Tests -join ', '))" } else { 'Tests (all)' }); cmd = $testCmd },
  @{ name = 'Server tests'; cmd = { node --test --test-concurrency=1 functions/test/*.test.js } },
  @{ name = 'Functions deploy'; skip = -not (Test-Changed 'functions' $functionsHash);
     cmd = { node tool/staging_release.cjs all --replace }; done = { Save-Done 'functions' $functionsHash } },
  @{ name = 'Firestore rules'; skip = -not (Test-Changed 'rules' $rulesHash);
     cmd = { node functions/node_modules/firebase-tools/lib/bin/firebase.js deploy --only firestore:rules --config firebase.staging.json --project apartment-management-staging };
     done = { Save-Done 'rules' $rulesHash } },
  @{ name = 'Web build'; skip = -not (Test-Changed 'web' $webHash);
     cmd = { flutter build web --release --output=build/staging-web --dart-define-from-file=config/app_check.staging.json } },
  @{ name = 'Hosting deploy'; skip = -not (Test-Changed 'web' $webHash);
     cmd = { node functions/node_modules/firebase-tools/lib/bin/firebase.js deploy --only hosting --config firebase.staging.json --project apartment-management-staging };
     done = { Save-Done 'web' $webHash } }
)

$i = 0
foreach ($step in $steps) {
  $i++
  Write-Host ""
  if ($step.skip) {
    Write-Host "=== [$i/$($steps.Count)] $($step.name): skipped, nothing changed since the last deploy ===" -ForegroundColor DarkGray
    continue
  }
  Write-Host "=== [$i/$($steps.Count)] $($step.name) ===" -ForegroundColor Cyan
  $started = Get-Date
  & $step.cmd
  if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "STOPPED at '$($step.name)' (exit code $LASTEXITCODE). Nothing after this step ran." -ForegroundColor Red
    exit $LASTEXITCODE
  }
  if ($step.done) { & $step.done }
  Write-Host ("--- {0} took {1:mm\:ss}" -f $step.name, ((Get-Date) - $started)) -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "=== Finished: staging is up to date ===" -ForegroundColor Green
