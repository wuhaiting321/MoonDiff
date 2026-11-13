# MoonDiff 一致性矩阵（PowerShell 版，Windows 默认环境）
#
# 用法：
#   .\scripts\matrix.ps1 probe:int-overflow
#   .\scripts\matrix.ps1 -ProgramJson '{"seed":7,...}'
#   .\scripts\matrix.ps1 -File .\examples\probe-frem-zero.json

param(
  [string]$ProgramJson = "",
  [string]$File = "",
  [string[]]$Backends = @("wasm", "wasm-gc", "js", "native")
)

$ErrorActionPreference = "Continue"
Set-Location (Split-Path -Parent $PSCommandPath) | Out-Null
Set-Location ..
$moon = if ($env:MOON) { $env:MOON } else { "moon" }
$out = ".moondiff-out"
New-Item -ItemType Directory -Force -Path $out | Out-Null

if ($ProgramJson -like "probe:*") {
  $name = $ProgramJson.Substring(6)
  $prog = (& $moon run cmd/moondiff --target wasm -- probe $name 2>$null | Select-Object -Last 1)
  $label = "probe:$name"
} elseif ($ProgramJson -ne "") {
  $prog = $ProgramJson
  $label = "inline"
} elseif ($File -ne "") {
  $prog = (Get-Content -Raw $File).Trim()
  $label = $File
} else {
  Write-Host "用法: .\scripts\matrix.ps1 probe:<名字>  /  -ProgramJson '<json>'  /  -File <路径>" -ForegroundColor Yellow
  exit 2
}

if (-not $prog -or -not $prog.StartsWith("{")) {
  Write-Host "错误：无法解析程序输入" -ForegroundColor Red
  exit 3
}

Write-Host "== MoonDiff =="
Write-Host "输入   : $label"
Write-Host ""

$available = @()
foreach ($t in $Backends) {
  Write-Host ("  {0,-8} ... " -f $t) -NoNewline
  & $moon run cmd/driver --target $t -- literals > "$out\lit-$t.txt" 2> "$out\lit-$t.err"
  if ($LASTEXITCODE -eq 0) {
    Write-Host "ok"
    $available += $t
  } else {
    Write-Host "unavailable（已跳过）"
  }
}
Write-Host ""

if ($available.Count -lt 2) {
  Write-Host "可用的后端不足 2 个，无法做差分比较。" -ForegroundColor Red
  exit 4
}

$matrixArgs = @()
foreach ($t in $available) {
  & $moon run cmd/driver --target $t -- $prog > "$out\$t.txt" 2> "$out\$t.err"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  注意：$t 退出码 $LASTEXITCODE（可能是 trap，见 $out\$t.err）"
  }
  $text = (Get-Content -Raw "$out\$t.txt")
  if ($null -eq $text) { $text = "" }
  $matrixArgs += "$t=$text"
}

& $moon run cmd/moondiff --target $available[0] -- matrix @matrixArgs
