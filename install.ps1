# dsh-plugin-net-access installer (anchor-based, no version pinning)
# Applies the net-access patches STRUCTURALLY to whatever DSH version is
# installed. manifest.json carries, per patched file, recipe steps
# (insert-before-anchor / exact replace) plus verification markers, instead of
# exact byte hashes per engine version. Surviving anchors make version bumps a
# no-op; a missing/ambiguous anchor aborts with a clear message BEFORE anything
# is written. The runner/UI/CLI files are patched in place after a backup
# (*.netaccess.bak). Idempotent: files already carrying every marker are skipped.
param(
  [string[]]$DshRoots
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$Manifest = [System.IO.File]::ReadAllText((Join-Path $Repo 'manifest.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json

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

function Read-Text($path) {
  try { return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) }
  catch { return $null }
}
function Write-Text($path, $text) {
  $enc = New-Object System.Text.UTF8Encoding($false)   # no BOM, byte-true
  [System.IO.File]::WriteAllText($path, $text, $enc)
}
function Test-Markers($text, $markers) {
  foreach ($m in $markers) { if (-not $text.Contains($m)) { return $false } }
  return $true
}
function Find-LineBlock($text, $block) {
  $lines = @($text -split "`n")
  $hits = @()
  for ($i = 0; $i -le $lines.Count - $block.Count; $i++) {
    $match = $true
    for ($k = 0; $k -lt $block.Count; $k++) {
      if ($lines[$i + $k] -ne $block[$k]) { $match = $false; break }
    }
    if ($match) { $hits += $i }
  }
  if ($hits.Count -eq 0) { return -1 }
  if ($hits.Count -gt 1) { return -2 }
  return $hits[0]
}
function Shorten($s) {
  if ($null -eq $s) { return '' }
  $s = $s.Replace("`n", ' / ')
  if ($s.Length -gt 70) { $s = $s.Substring(0, 70) + '...' }
  return $s
}
function Apply-Recipe($text, $steps) {
  # Throws on the first missing/ambiguous anchor; returns the patched text.
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.AddRange([string[]]@($text -split "`n"))
  foreach ($step in $steps) {
    if ($step.type -eq 'insert') {
      $anchor = [string[]]@($step.before -split "`n")
      $idx = Find-LineBlock ([string]::Join("`n", $lines.ToArray())) $anchor
      if ($idx -lt 0) { throw "insert anchor missing: $(Shorten $step.before)" }
      $ins = [string[]]@($step.lines -split "`n")
      $lines.InsertRange($idx, $ins)
    } elseif ($step.type -eq 'replace') {
      $frm = [string[]]@($step.from -split "`n")
      $idx = Find-LineBlock ([string]::Join("`n", $lines.ToArray())) $frm
      if ($idx -lt 0) { throw "replace target missing: $(Shorten $step.from)" }
      $to = [string[]]@($step.to -split "`n")
      $lines.RemoveRange($idx, $frm.Count)
      $lines.InsertRange($idx, $to)
    } else {
      throw "unknown recipe step type: $($step.type)"
    }
  }
  return [string]::Join("`n", $lines.ToArray())
}

# ---- Phase 1: plan (no writes) ----
$roots = @()
if ($DshRoots -and $DshRoots.Count -gt 0) {
  $roots = @($DshRoots | Where-Object { Test-Path $_ })
  if ($roots.Count -eq 0) { Write-Host "ABORT: none of the given -DshRoots exist."; exit 1 }
} else {
  $roots = @(Get-DshRoots)
}
if ($roots.Count -eq 0) {
  Write-Host "ABORT: no DSH installation found (scanned npm caches, ~/.dsh/profiles and npm global)."
  Write-Host "Install DeepSeek Harness first (npx @deepseek-ai/dsh web), then re-run this script."
  exit 1
}
$found = @{}
$blockers = @()
$plan = @()
foreach ($root in $roots) {
  Write-Host "== install root: $root"
  foreach ($recipe in @($Manifest.recipes)) {
    $target = Join-Path $root $recipe.file
    if (-not (Test-Path $target)) { continue }
    $found[$recipe.file] = $true
    $text = Read-Text $target
    if ($null -eq $text) { $blockers += "  cannot read: $target"; continue }
    $wasCrlf = $text.Contains("`r`n")
    $text = $text.Replace("`r`n", "`n")
    if (Test-Markers $text $recipe.markers) {
      Write-Host "ALREADY PATCHED: $($recipe.file)"; continue
    }
    try {
      $patched = Apply-Recipe $text $recipe.steps
      if (-not (Test-Markers $patched $recipe.markers)) {
        throw "markers missing after patch ($($recipe.markers -join ', '))"
      }
    } catch {
      $blockers += "  $target`n    $($_.Exception.Message)"
      continue
    }
    if ($wasCrlf) { $patched = $patched.Replace("`n", "`r`n") }
    $plan += @{ root = $root; recipe = $recipe; target = $target; patched = $patched }
  }
}
$missing = @($Manifest.recipes | Where-Object { -not $found[$_.file] } | ForEach-Object { $_.file })
if ($missing.Count -gt 0) {
  Write-Host "ABORT: these files were not found in any DSH installation:"
  $missing | ForEach-Object { Write-Host "  $_" }
  exit 1
}
if ($blockers.Count -gt 0) {
  Write-Host "ABORT: recipe anchors were not found - the installed DSH structure differs from what the plugin expects, or files were modified by something else. Nothing was changed. Update the plugin or report this:"
  $blockers | ForEach-Object { Write-Host $_ }
  exit 1
}

# ---- Phase 2: apply ----
if ($plan.Count -eq 0) {
  Write-Host 'Nothing to do (all targets already patched or absent).'
} else {
  foreach ($item in $plan) {
    $bak = "$($item.target).netaccess.bak"
    if (-not (Test-Path $bak)) { Copy-Item $item.target $bak -Force; Write-Host "  backup: $($item.recipe.file).netaccess.bak" }
    Write-Text $item.target $item.patched
    Write-Host "  PATCHED: $($item.recipe.file)"
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