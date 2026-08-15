# dsh launcher - DeepSeek Harness 后台启动/停止/重启/状态
# 用法: dsh start | stop | restart | status
$ErrorActionPreference = 'Stop'

$LauncherDir = Join-Path $HOME '.dsh-launcher'
$PidFile     = Join-Path $LauncherDir 'dsh.pid'
$StdLog      = Join-Path $LauncherDir 'dsh.log'
$ErrLog      = Join-Path $LauncherDir 'dsh.err.log'
$Port        = 3080
$StartUrl    = "http://127.0.0.1:$Port"

function Get-DshPidByPort {
  $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  if ($c) { return ($c | Select-Object -First 1).OwningProcess }
  return $null
}

function Test-Running {
  $p = Get-DshPidByPort
  if ($p) { return $p }
  if (Test-Path $PidFile) {
    $saved = (Get-Content $PidFile -Raw).Trim()
    if ($saved -match '^\d+$') {
      $proc = Get-Process -Id ([int]$saved) -ErrorAction SilentlyContinue
      if ($proc -and $proc.ProcessName -eq 'node') { return [int]$saved }
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
  }
  return $null
}

function Start-Dsh {
  $running = Test-Running
  if ($running) { Write-Host "dsh 已在运行 (PID $running)，访问 $StartUrl"; return }
  New-Item -ItemType Directory -Force -Path $LauncherDir | Out-Null
  $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c "npx @deepseek-ai/dsh web"' `
       -WorkingDirectory $HOME -WindowStyle Hidden `
       -RedirectStandardOutput $StdLog -RedirectStandardError $ErrLog -PassThru
  $nodePid = $null
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    $nodePid = Get-DshPidByPort
    if ($nodePid) { break }
  }
  if ($nodePid) {
    Set-Content -Path $PidFile -Value $nodePid -Encoding ASCII
    Write-Host "dsh 已启动 (PID $nodePid)，访问 $StartUrl"
  } else {
    Write-Host 'dsh 启动超时(30秒内未监听端口)，请检查日志:'
    if (Test-Path $ErrLog) { Get-Content $ErrLog -Tail 10 }
    throw 'dsh 启动失败'
  }
}

function Stop-Dsh {
  $target = Test-Running
  if (-not $target) { Write-Host 'dsh 未在运行'; return }
  taskkill /F /PID $target | Out-Null
  for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Milliseconds 500
    if (-not (Get-DshPidByPort)) { break }
  }
  Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
  Write-Host "dsh 已停止 (PID $target)"
}

function Show-Status {
  $target = Test-Running
  if ($target) { Write-Host "dsh 正在运行。PID: $target" } else { Write-Host 'dsh 未在运行' }
}

switch ($args[0]) {
  'start'   { Start-Dsh }
  'stop'    { Stop-Dsh }
  'restart' { Stop-Dsh; Start-Sleep -Seconds 1; Start-Dsh }
  'status'  { Show-Status }
  default   { Write-Host '用法: dsh start | stop | restart | status' }
}
