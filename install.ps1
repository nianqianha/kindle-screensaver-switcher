#requires -version 5.1
<#
  一键安装 Kindle 屏保工具。
  运行一行：  powershell -ExecutionPolicy Bypass -File install.ps1
  或（已在 PowerShell 里）：  .\install.ps1

  装什么：
    1) 检查 Python + Pillow（缺 Pillow 自动 pip 装）
    2) 把工具脚本复制到固定目录 %USERPROFILE%\.kss\
    3) 在 PowerShell profile 加 kss 函数（以后任意窗口一行命令唤起）
    4) 若 Kindle 在线，把 kss-agent.sh 推到设备 /mnt/us/（离线可跳过，以后补）
  不装：SSH（由用户自行处理）、越狱、KOReader（前提，用户自备）
#>
param(
    [string]$Python = "python",
    [string]$InstallDir = "$env:USERPROFILE\.kss",
    [string]$HostIP = "",
    [int]$Port = 2222,
    [string]$User = "root",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
    [switch]$SkipDevice   # 跳过设备端 agent 推送
)
$ErrorActionPreference = "Stop"
$src = Split-Path -Parent $MyInvocation.MyCommand.Path

function OK($m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function SKIP($m) { Write-Host "  [--] $m" -ForegroundColor DarkGray }
function FAIL($m) { Write-Host "  [!!] $m" -ForegroundColor Red }

Write-Host "`n=== Kindle 屏保工具 · 安装 ===" -ForegroundColor Cyan

# 1) Python + Pillow
Write-Host "`n[1/4] 检查 Python / Pillow"
try {
    $pv = & $Python -c "import sys; print(sys.version.split()[0])" 2>$null
    OK "Python $pv"
} catch { throw "没找到 Python。请先安装 Python 3 并加入 PATH，或指定 -Python 路径。" }
$pillow = & $Python -c "import PIL; print(PIL.__version__)" 2>$null
if (-not $pillow) {
    Write-Host "  Pillow 缺失，正在安装..."
    & $Python -m pip install Pillow 2>&1 | Out-Null
    $pillow = & $Python -c "import PIL; print(PIL.__version__)" 2>$null
    if (-not $pillow) { FAIL "Pillow 安装失败，请手动 pip install Pillow" } else { OK "Pillow $pillow（已安装）" }
} else { OK "Pillow $pillow" }

# 2) 复制脚本到固定目录
Write-Host "`n[2/4] 安装脚本到 $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$files = @("manage-screensaver.ps1", "kss-device.ps1", "kss-contact-sheet.py",
           "to-kindle-screensaver.py", "kss-agent.sh", "kss-contact-sheet.py")
foreach ($f in ($files | Select-Object -Unique)) {
    if (Test-Path (Join-Path $src $f)) {
        Copy-Item (Join-Path $src $f) (Join-Path $InstallDir $f) -Force
        OK $f
    } else { SKIP "$f（源文件不存在，跳过）" }
}

# 3) profile 加 kss 函数（幂等：已有则不重复加）
Write-Host "`n[3/4] 配置 kss 一行命令入口"
$profilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "WindowsPowerShell\profile.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $profilePath) | Out-Null
if (-not (Test-Path $profilePath)) { "" | Set-Content $profilePath -Encoding UTF8 }
$prof = Get-Content $profilePath -Raw -Encoding UTF8
$kssBlock = @"

#region Kindle 屏保工具一行入口（由 install.ps1 安装）
function kss {
    & "$InstallDir\manage-screensaver.ps1" @args
}
#endregion
"@
if ($prof -match '(?s)#region Kindle 屏保工具一行入口.*?#endregion') {
    # 已装过：整块替换，保证指向最新安装目录
    $prof = [regex]::Replace($prof, '(?s)#region Kindle 屏保工具一行入口.*?#endregion', $kssBlock.Trim())
    Set-Content -Path $profilePath -Value $prof -Encoding UTF8
    OK "已更新 kss 函数指向 $InstallDir"
} elseif ($prof -match 'function kss\s*\{') {
    # 有手写的 kss（无 region 标记）：不覆盖用户内容，只提示
    SKIP "profile 里已有手写 kss 函数；如需指向 $InstallDir 请手动调整"
} else {
    Add-Content -Path $profilePath -Value $kssBlock -Encoding UTF8
    OK "已加入 kss 函数（新开 PowerShell 窗口生效）"
}

# 4) 设备端 agent（可选，连不上就跳过）
Write-Host "`n[4/4] 安装设备端 agent"
if ($SkipDevice) {
    SKIP "按 -SkipDevice 跳过；以后设备在线可补推"
} else {
    $targetIp = $HostIP
    if (-not $targetIp) {
        $cache = Join-Path $env:TEMP "kss-host.txt"
        if (Test-Path $cache) { $targetIp = (Get-Content $cache -Raw).Trim() }
    }
    if (-not $targetIp) { $targetIp = "192.168.1.222" }
    $agent = Join-Path $InstallDir "kss-agent.sh"
    $oldEap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $probe = & ssh -p $Port -i $KeyPath -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o LogLevel=Error "${User}@${targetIp}" "echo OK" 2>$null
    $ErrorActionPreference = $oldEap
    if ($LASTEXITCODE -eq 0 -and "$probe" -match "OK") {
        & scp -P $Port -i $KeyPath -o StrictHostKeyChecking=no $agent "${User}@${targetIp}:/mnt/us/kss-agent.sh" 2>$null
        & ssh -p $Port -i $KeyPath -o StrictHostKeyChecking=no "${User}@${targetIp}" "chmod +x /mnt/us/kss-agent.sh" 2>$null
        OK "agent 已推送到 ${targetIp}:/mnt/us/kss-agent.sh"
    } else {
        SKIP "设备 $targetIp 连不上（SSH 由你自行处理）；agent 未推送"
        Write-Host "       以后设备在线时手动推：scp -P $Port -i $KeyPath $agent ${User}@<IP>:/mnt/us/kss-agent.sh" -ForegroundColor DarkGray
    }
}

Write-Host @"

=== 安装完成 ===
以后任意 PowerShell 窗口（新开的）直接用：

  kss            交互菜单
  kss preview    看图认编号
  kss add <图>   加图
  kss rm N       删第 N 张
  kss set <图> N 替换第 N 张
  kss ls         列出
  kss conn       检查连接

前提（由你自行处理）：设备唤醒、同一网络、SSH 已开(2222)。

"@ -ForegroundColor Green
