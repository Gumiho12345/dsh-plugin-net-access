# dsh-plugin-net-access installer
# Phase 1 (preflight) verifies every target against the manifest ORIGINAL hash
# (pristine 0.1.0-rc.6) and aborts BEFORE touching anything on mismatch.
# Phase 2 backs up (*.netaccess.bak), overwrites, and verifies the patched hash.
# Idempotent: already-patched files are skipped.
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

function Get-Sha256($path) { (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() }

# ---- Phase 1: preflight (no writes) ----
$roots = @(Get-DshRoots)
if ($roots.Count -eq 0) {
  Write-Host "ABORT: no DSH installation found (scanned npm caches, ~/.dsh/profiles and npm global)."
  Write-Host "Install DeepSeek Harness 0.1.0-rc.6 first (npx @deepseek-ai/dsh web), then re-run this script."
  exit 1
}
$plan = @()
$blockers = @()
$found = @{}
foreach ($root in $roots) {
  Write-Host "== install root: $root"
  foreach ($entry in $Manifest.targets) {
    $target = Join-Path $root $entry.file
    if (-not (Test-Path $target)) { continue }
    $found[$entry.file] = $true
    $cur = Get-Sha256 $target
    if ($cur -eq $entry.sha256) { Write-Host "ALREADY PATCHED: $($entry.file)"; continue }
    if ($cur -ne $entry.original) {
      $blockers += "  $target`n    installed : $cur`n    expected original: $($entry.original)"
      continue
    }
    # Source-side preflight: the repo-side patch file must byte-match the
    # manifest (a CRLF-mangled checkout would otherwise be copied over the
    # engine and only then fail the post-copy verification).
    $src = Join-Path $Repo "patches\$($entry.file)"
    if (-not (Test-Path $src)) { $blockers += "  missing patch source: $src"; continue }
    $srcHash = Get-Sha256 $src
    if ($srcHash -ne $entry.sha256) {
      $blockers += "  patch source hash mismatch (CRLF-mangled checkout?): $src`n    source : $srcHash`n    expected: $($entry.sha256)"
      continue
    }
    $plan += @{ root = $root; entry = $entry; target = $target }
  }
}
$missing = @($Manifest.targets | Where-Object { -not $found[$_.file] } | ForEach-Object { $_.file })
if ($missing.Count -gt 0) {
  Write-Host "ABORT: these patched files were not found in any DSH installation (is this DeepSeek Harness 0.1.0-rc.6?):"
  $missing | ForEach-Object { Write-Host "  $_" }
  exit 1
}
if ($blockers.Count -gt 0) {
  Write-Host "ABORT: installed files do not match DeepSeek Harness 0.1.0-rc.6 originals - DSH version differs or files were modified. Nothing was changed:"
  $blockers | ForEach-Object { Write-Host $_ }
  exit 1
}

# ---- Phase 2: apply ----
if ($plan.Count -eq 0) {
  Write-Host 'Nothing to do (all targets already patched or absent).'
} else {
  foreach ($item in $plan) {
    $bak = "$($item.target).netaccess.bak"
    if (-not (Test-Path $bak)) { Copy-Item $item.target $bak -Force; Write-Host "  backup: $($item.entry.file).netaccess.bak" }
    Copy-Item (Join-Path $Repo "patches\$($item.entry.file)") $item.target -Force
    $h = Get-Sha256 $item.target
    if ($h -ne $item.entry.sha256) { Write-Host "VERIFY FAILED: $($item.target)"; exit 1 }
    Write-Host "  PATCHED: $($item.entry.file)"
  }
}

# Preset: install the user-layer cordis patch (web profile) when absent.
$profilePatch = Join-Path $env:USERPROFILE '.dsh\profiles\web\cordis.patch.yml'
if (Test-Path $profilePatch) {
  $content = Get-Content $profilePatch -Raw -ErrorAction SilentlyContinue
  if ($content -notmatch 'net-access') {
    Copy-Item $profilePatch "$profilePatch.netaccess.bak" -Force
    Copy-Item (Join-Path $Repo 'plugin\cordis.patch.yml') $profilePatch -Force
    Write-Host "preset installed: $profilePatch (backup: $profilePatch.netaccess.bak)"
  } else {
    Write-Host "preset already present: $profilePatch"
  }
} else {
  Write-Host "WARN: no web profile at $profilePatch - install the preset manually (see README.md)."
}

Write-Host ""
Write-Host "Done. Restart DSH (Ctrl+C or taskkill the 3080 listener, then npx @deepseek-ai/dsh web) and hard-refresh the browser."
