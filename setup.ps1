# dsh-plugin-net-access one-click setup
# 1) engine patch + permission preset (delegates to install.ps1)
# 2) download the official OpenSSL/LibreSSL curl from curl.se into the tool bin
# 3) verify the toolbox HTTPS works
# ASCII-only on purpose (PS 5.1 + cmd encoding pitfalls with Chinese text).
param(
    [string]$ToolBin = (Join-Path $env:USERPROFILE '.dsh\netaccess-tools\bin'),
    [switch]$SkipDownload
)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "== [1/3] engine patch + permission preset =="
& (Join-Path $Repo 'install.ps1')
if ($LASTEXITCODE -eq 1) { throw 'install.ps1 aborted (see messages above); nothing was changed.' }

if ($SkipDownload) {
    Write-Host "== [2/3] skipped (SkipDownload) =="
} else {
    Write-Host "== [2/3] HTTPS toolbox -> $ToolBin =="
    New-Item -ItemType Directory -Force -Path $ToolBin | Out-Null
    if ((Test-Path (Join-Path $ToolBin 'curl.exe')) -and (Test-Path (Join-Path $ToolBin 'curl-ca-bundle.crt'))) {
        Write-Host "toolbox already present, skipping download."
    } else {
        $work = Join-Path $env:TEMP ("dsh-curl-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        try {
            # --- resolve the latest win64-mingw zip URL from curl.se/windows ---
            $page = $null
            try { $page = (Invoke-WebRequest -Uri 'https://curl.se/windows/' -UseBasicParsing -TimeoutSec 30).Content } catch {}
            if (-not $page) {
                try { $page = (& python -c "import urllib.request;print(urllib.request.urlopen('https://curl.se/windows/',timeout=30).read().decode('utf-8','replace'))" 2>$null | Out-String) } catch {}
            }
            if (-not $page) { throw "cannot fetch https://curl.se/windows/ - download curl manually and put curl.exe + curl-ca-bundle.crt into $ToolBin" }
            $m = [regex]::Match($page, 'href="([^"]*dl-[^"]*win64-mingw\.zip)"')
            if (-not $m.Success) { throw 'no win64-mingw download link found on curl.se/windows' }
            $url = $m.Groups[1].Value
            if ($url.StartsWith('/')) { $url = 'https://curl.se' + $url }
            elseif (-not $url.StartsWith('http')) { $url = 'https://curl.se/windows/' + $url }
            Write-Host "downloading $url"

            # --- download (IWR first, python urllib as fallback) ---
            $zip = Join-Path $work 'curl.zip'
            $ok = $false
            try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 120; $ok = (Test-Path $zip) } catch { $ok = $false }
            if (-not $ok) {
                try {
                    $py = "import urllib.request;urllib.request.urlretrieve('$url','$zip')"
                    & python -c $py 2>$null | Out-Null
                    $ok = (Test-Path $zip)
                } catch { $ok = $false }
            }
            if (-not $ok) { throw "download failed - put curl.exe + curl-ca-bundle.crt into $ToolBin manually" }

            # --- extract and copy curl.exe + curl-ca-bundle.crt ---
            Expand-Archive -Path $zip -DestinationPath (Join-Path $work 'x') -Force
            $curlExe = Get-ChildItem (Join-Path $work 'x') -Recurse -Filter 'curl.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
            if (-not $curlExe) { throw 'curl.exe not found inside the downloaded archive' }
            $binDir = Split-Path $curlExe
            Copy-Item $curlExe (Join-Path $ToolBin 'curl.exe') -Force
            $ca = Join-Path $binDir 'curl-ca-bundle.crt'
            if (Test-Path $ca) { Copy-Item $ca (Join-Path $ToolBin 'curl-ca-bundle.crt') -Force }
            else { throw 'curl-ca-bundle.crt not found inside the downloaded archive' }
            Write-Host 'toolbox installed.'
        } finally {
            Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "== [3/3] verify =="
$tc = Join-Path $ToolBin 'curl.exe'
if (Test-Path $tc) {
    & $tc --version 2>&1 | Select-Object -First 1 | Out-String | Write-Host
    & $tc -sS -o NUL -w "HTTPS check: HTTP %{http_code} verify=%{ssl_verify_result}`n" --max-time 20 https://example.com 2>&1 | Out-String | Write-Host
} else {
    Write-Host "WARN: no curl.exe at $ToolBin - HTTPS toolbox missing."
}

Write-Host ""
Write-Host "Done. Restart DSH (Ctrl+C in its terminal, or taskkill the 3080 listener),"
Write-Host "reopen http://127.0.0.1:3080, hard-refresh, and pick Net Access in the"
Write-Host "permission selector (bottom-left). Then:"
Write-Host "  curl.exe -sS https://example.com        # should return 200 inside the sandbox"
