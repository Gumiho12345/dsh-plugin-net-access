# dsh-plugin-net-access uninstaller
# Restores every *.netaccess.bak file and the preset backup.
$ErrorActionPreference = 'Continue'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$Manifest = Get-Content (Join-Path $Repo 'manifest.json') -Raw | ConvertFrom-Json

function Get-DshRoots {
  $roots = @()
  $npmCache = $null
  try { $npmCache = (npm config get cache 2>$null).Trim() } catch {}
  $candidates = @()
  $npxDirs = @()
  if ($npmCache) { $npxDirs += (Join-Path $npmCache '_npx') }
  $npxDirs += (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx')
  $npxDirs += (Join-Path $env:USERPROFILE '.npm\_npx')
  foreach ($npx in $npxDirs) {
    if (-not (Test-Path $npx)) { continue }
    # npm's npx cache layout is _npx\<hash>\node_modules\@deepseek-ai, so
    # every hash subdirectory is a candidate root (the _npx dir itself is
    # kept for older flat layouts).
    $candidates += $npx
    Get-ChildItem $npx -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $candidates += (Join-Path $_.FullName 'node_modules')
    }
  }
  $candidates += (Join-Path $env:USERPROFILE '.dsh\profiles\node_modules')
  $candidates += (Join-Path $env:USERPROFILE '.dsh\profiles\web\node_modules')
  foreach ($c in $candidates) {
    if (-not (Test-Path $c)) { continue }
    $roots += (Join-Path $c '@deepseek-ai')
  }
  try {
    $g = npm root -g 2>$null
    if ($g -and (Test-Path (Join-Path $g '@deepseek-ai'))) { $roots += (Join-Path $g '@deepseek-ai') }
  } catch {}
  $roots | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique
}

$restored = 0
foreach ($root in Get-DshRoots) {
  foreach ($entry in $Manifest.targets) {
    $bak = Join-Path $root ($entry.file + '.netaccess.bak')
    if (Test-Path $bak) {
      Copy-Item $bak (Join-Path $root $entry.file) -Force
      Remove-Item $bak -Force
      $restored++
      Write-Host "RESTORED: $($entry.file)"
    }
  }
}

$pb = Join-Path $env:USERPROFILE '.dsh\profiles\web\cordis.patch.yml.netaccess.bak'
if (Test-Path $pb) {
  Copy-Item $pb (Join-Path $env:USERPROFILE '.dsh\profiles\web\cordis.patch.yml') -Force
  Remove-Item $pb -Force
  Write-Host 'preset restored'
}

$toolDir = Join-Path $env:USERPROFILE '.dsh\netaccess-tools'
if (Test-Path $toolDir) {
  Remove-Item $toolDir -Recurse -Force
  Write-Host "toolbox removed: $toolDir"
}

Write-Host "Uninstall done: $restored files restored. Restart dsh to apply."
