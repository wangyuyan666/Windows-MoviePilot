<#
.SYNOPSIS
    对上游 MoviePilot 源码做 Windows 便携版所需的最小改动。

.DESCRIPTION
    上游 release 源码面向 Docker，两处行为在便携版下不成立：

      1. 以 `python app/main.py` 方式启动时，源码根目录不在 sys.path 中，
         模块顶部的 `from app.utils.stdio import ...` 会 ImportError。
      2. 托盘图标被 `SystemUtils.is_frozen()` 挡住，便携版没有 PyInstaller 冻结，
         永远起不来托盘。

    其余差异（监听端口、时区等）全部通过 config/app.env 配置，不改代码。

    每处改动都先校验锚点存在，锚点消失即抛错，这样上游重构时 CI 会立刻失败，
    而不是静默产出一个坏包。脚本可重复执行。
#>
[CmdletBinding()]
param(
    # MoviePilot 源码目录
    [string]$Root = "MoviePilot"
)

$ErrorActionPreference = "Stop"

$mainPath = Join-Path $Root "app/main.py"
if (-not (Test-Path $mainPath)) {
    throw "找不到 $mainPath"
}

# 按行处理，避免 CRLF/LF 差异影响匹配
$lines = @(Get-Content -LiteralPath $mainPath -Encoding UTF8)
$bootstrap = 'sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))'

# ---- 补丁 1: 把源码根目录加入 sys.path ----
# 必须插在首个 `from app.xxx import` 之前，否则第一次导入 app 包就会失败。
# 用 os.path 而非 pathlib，因为 Path 的 import 在更下面。
if ($lines -contains $bootstrap) {
    Write-Output "补丁 1 已存在, 跳过"
} else {
    $anchor = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "import sys") {
            $anchor = $i
            break
        }
    }
    if ($anchor -lt 0) {
        throw "补丁 1 锚点丢失: app/main.py 中未找到 'import sys'"
    }

    $patched = @()
    $patched += $lines[0..$anchor]
    $patched += ""
    $patched += "# Windows 便携版: 以源码目录直接运行, 需保证 app 包可被导入"
    $patched += $bootstrap
    $patched += $lines[($anchor + 1)..($lines.Count - 1)]
    $lines = $patched

    Write-Output "补丁 1 已应用: sys.path 引导"
}

# ---- 补丁 2: 放开托盘图标的 frozen 限制 ----
# start_tray() 内另有 is_windows() 判断，去掉 frozen 判断不影响非 Windows 平台。
$trayIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^def start_tray\(\):") {
        $trayIndex = $i
        break
    }
}
if ($trayIndex -lt 0) {
    throw "补丁 2 锚点丢失: app/main.py 中未找到 'def start_tray():'"
}

# 只在 start_tray() 函数头部附近找，避免误伤第 28 行那处 frozen 判断
$guardIndex = -1
$searchEnd = [Math]::Min($trayIndex + 20, $lines.Count - 2)
for ($i = $trayIndex; $i -le $searchEnd; $i++) {
    if ($lines[$i] -match "^\s*if not SystemUtils\.is_frozen\(\):\s*$" -and $lines[$i + 1] -match "^\s*return\s*$") {
        $guardIndex = $i
        break
    }
}

if ($guardIndex -lt 0) {
    Write-Output "补丁 2 已应用过或上游已移除该限制, 跳过"
} else {
    # 连带删掉守卫后的空行，保持函数体整洁
    $removeCount = 2
    if ($guardIndex + 2 -lt $lines.Count -and $lines[$guardIndex + 2] -match "^\s*$") {
        $removeCount = 3
    }

    $patched = @()
    if ($guardIndex -gt 0) {
        $patched += $lines[0..($guardIndex - 1)]
    }
    $patched += $lines[($guardIndex + $removeCount)..($lines.Count - 1)]
    $lines = $patched

    Write-Output "补丁 2 已应用: 托盘图标解除 frozen 限制"
}

# 统一写成 LF，与上游源码保持一致
$content = ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText(
    (Resolve-Path $mainPath),
    $content,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Output "Windows 补丁应用完成: $mainPath"
