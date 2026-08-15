# dsh-plugin-net-access installer
# Scans every DSH install location, backs up each target to *.netaccess.bak,
# overwrites with the patched file, and verifies the SHA256 from manifest.json.
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$Manifest = Get-Content (Join-Path $Repo 'manifest.json') -Raw | ConvertFrom-Json

function Get-DshRoots {
  $roots = @()
  $npmCache = $null
  try { $npmCache = (npm config get cache 2>$null).Trim() } catch {}
  $candidates = @()
  if ($npmCache) { $candidates += (Join-Path $npmCache '_npx') }
  $candidates += (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx')
  $candidates += (Join-Path $env:USERPROFILE '.npm\_npx')
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

$patched = 0
foreach ($root in Get-DshRoots) {
  Write-Host "== install root: $root"
  foreach ($entry in $Manifest.targets) {
    $target = Join-Path $root $entry.file
    if (-not (Test-Path $target)) { Write-Host "  SKIP (target missing): $($entry.file)"; continue }
    $bak = "$target.netaccess.bak"
    if (-not (Test-Path $bak)) {
      Copy-Item $target $bak -Force
      Write-Host "  backup: $($entry.file).netaccess.bak"
    }
    Copy-Item (Join-Path $Repo "patches\$($entry.file)") $target -Force
    $h = (Get-FileHash $target -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $entry.sha256) { Write-Host "  VERIFY FAILED: $target"; exit 1 }
    $patched++
    Write-Host "  PATCHED: $($entry.file)"
  }
}

# Preset: install the user-layer cordis patch (web profile) when absent.
$profilePatch = Join-Path $env:USERPROFILE '.dsh\profiles\web\cordis.patch.yml'
if (Test-Path $profilePatch) {
  $content = Get-Content $profilePatch -Raw -ErrorAction SilentlyContinue
  if ($content -notmatch 'net-access') {
    Copy-Item $profilePatch "$profilePatch.netaccess.bak" -Force
    Copy-Item (Join-Path $Repo 'patches\profile-cordis.patch.yml') $profilePatch -Force
    Write-Host "preset installed: $profilePatch (backup: $profilePatch.netaccess.bak)"
  } else {
    Write-Host "preset already present: $profilePatch"
  }
} else {
  Write-Host "WARN: no web profile at $profilePatch - install the preset manually (see README.md)."
}

Write-Host ""
Write-Host "Done: $patched files patched. Restart dsh (dsh restart) and hard-refresh the browser (Ctrl+Shift+R)."
