#requires -version 5.1
<#
  一键安装 Kindle 屏保工具。
  运行一行：  powershell -ExecutionPolicy Bypass -File install.ps1
  或（已在 PowerShell 里）：  .\install.ps1

  装什么：
    1) 检查 Python + Pillow（缺 Pillow 自动 pip 装）——用独立 kss-probe.py，不用 python -c
    2) 把工具脚本复制到固定目录 %USERPROFILE%\.kss\（含 kss-common.ps1）
    3) 在 PowerShell 5.1 和 7 的 profile 都加 kss 函数（以后任意窗口一行命令唤起）
    4) 若 Kindle 在线，把 kss-agent.sh 推到设备 /mnt/us/（离线可跳过，以后补）
  不装：SSH（由用户自行处理）、越狱、KOReader（前提，用户自备）

  修复 2026-11-28（第二轮）：
    ① install.ps1 原来 3 处 python -c 内联动态代码——卡巴 PDM 判木马特征（2026-11-20 实测），
       改用独立 kss-probe.py（与 to-kindle-screensaver.py 同样思路）
    ② 公共函数抽到 kss-common.ps1（Invoke-Native 修 CmdArgs.Count=1 的 1..0 陷阱）
    ③ host 缓存从 %TEMP%\kss-host.txt 移到 ~/.kss/config.json 并校验 IP/主机名（防投毒）
    ④ InstallDir 含 $ 时用 MatchEvaluator 字面替换（原来正则替换会破坏 profile）
    ⑤ agent 推送后回读 sha256（防设备上残留旧脚本导致「新代码没生效」误判）
    ⑥ Get-Content/Renames 时回显私钥路径用占位符（不回显真实路径）
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

# dot-source 共享函数（本目录即源码目录；安装后 manage 等从 ~/.kss 加载）
. (Join-Path $src "kss-common.ps1")

function OK($m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function SKIP($m) { Write-Host "  [--] $m" -ForegroundColor DarkGray }
function FAIL($m) { Write-Host "  [!!] $m" -ForegroundColor Red }

Write-Host "`n=== Kindle 屏保工具 · 安装 ===" -ForegroundColor Cyan

# 1) Python + Pillow（用独立探测脚本，避免 python -c 动态代码特征）
Write-Host "`n[1/4] 检查 Python / Pillow"
$probe = Join-Path $src "kss-probe.py"
if (-not (Test-Path $probe)) { throw "探测脚本 kss-probe.py 不存在，安装不完整。" }
$pyCheck = Invoke-Native -CmdArgs @($Python, $probe)
if ($pyCheck.Code -ne 0 -or -not $pyCheck.Out) {
    throw "没找到 Python。请先安装 Python 3 并加入 PATH，或指定 -Python 路径。"
}
OK "Python $($pyCheck.Out -join '')"

$piCheck = Invoke-Native -CmdArgs @($Python, $probe, "--pillow")
if ($piCheck.Code -ne 0 -or -not $piCheck.Out) {
    Write-Host "  Pillow 缺失，正在安装..."
    $pip = Invoke-Native -CmdArgs @($Python, "-m", "pip", "install", "Pillow")
    $piCheck = Invoke-Native -CmdArgs @($Python, $probe, "--pillow")
    if ($piCheck.Code -ne 0 -or -not $piCheck.Out) {
        FAIL "Pillow 安装失败，请手动 pip install Pillow（pip 输出：$($pip.Out -join ' ')）"
    } else { OK "Pillow $($piCheck.Out -join '')（已安装）" }
} else { OK "Pillow $($piCheck.Out -join '')" }

# 2) 复制脚本到固定目录
Write-Host "`n[2/4] 安装脚本到 $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$files = @("kss-common.ps1", "kss-probe.py", "manage-screensaver.ps1", "kss-device.ps1",
           "kss-contact-sheet.py", "to-kindle-screensaver.py", "kss-agent.sh")
foreach ($f in ($files | Select-Object -Unique)) {
    if (Test-Path (Join-Path $src $f)) {
        Copy-Item (Join-Path $src $f) (Join-Path $InstallDir $f) -Force
        OK $f
    } else { SKIP "$f（源文件不存在，跳过）" }
}

# 3) profile 加 kss 函数（幂等：整块替换；手写 kss 不覆盖）
#    用 MatchEvaluator 而非正则替换串，避免 InstallDir 含 $ 时被当分组引用。
Write-Host "`n[3/4] 配置 kss 一行命令入口"
function Install-KssProfile {
    param([string]$Path)
    $dir = Split-Path $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not (Test-Path $Path)) { "" | Set-Content $Path -Encoding UTF8 }
    $prof = Get-Content $Path -Raw -Encoding UTF8
    $blockLines = @(
        "#region Kindle 屏保工具一行入口（由 install.ps1 安装）",
        "function kss {",
        "    & `"$InstallDir\manage-screensaver.ps1`" @args",
        "}"
    )
    $kssBlock = ($blockLines -join "`r`n") + "`r`n#endregion"
    if ($prof -match '(?s)#region Kindle 屏保工具一行入口.*?#endregion') {
        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $kssBlock }
        $prof = [regex]::Replace($prof, '(?s)#region Kindle 屏保工具一行入口.*?#endregion', $evaluator)
        Set-Content -Path $Path -Value $prof -Encoding UTF8
        OK "已更新 $Path 的 kss 函数 → $InstallDir"
    } elseif ($prof -match 'function kss\s*\{') {
        SKIP "$Path 已有手写 kss 函数；未覆盖，如需指向 $InstallDir 请手动调整"
    } else {
        Add-Content -Path $Path -Value "`r`n$kssBlock" -Encoding UTF8
        OK "已加入 $Path 的 kss 函数（新开窗口生效）"
    }
}
$docs = [Environment]::GetFolderPath('MyDocuments')
Install-KssProfile -Path (Join-Path $docs "WindowsPowerShell\profile.ps1")
Install-KssProfile -Path (Join-Path $docs "PowerShell\profile.ps1")

# 4) 设备端 agent（可选，连不上就跳过）
Write-Host "`n[4/4] 安装设备端 agent"
if ($SkipDevice) {
    SKIP "按 -SkipDevice 跳过；以后设备在线可补推"
} else {
    $targetIp = $HostIP
    if (-not $targetIp) {
        $cfg = Read-KssConfig
        if ($cfg.PSObject.Properties['HostIP'] -and (Test-KssHost $cfg.HostIP)) { $targetIp = $cfg.HostIP }
    }
    if (-not $targetIp) { $targetIp = "192.168.1.222" }
    if (-not (Test-KssHost $targetIp)) { throw "HostIP 不合法: $targetIp" }
    $agent = Join-Path $InstallDir "kss-agent.sh"
    $probeR = Invoke-Native -CmdArgs @("ssh", "-p", "$Port", "-i", $KeyPath,
        "-o", "ConnectTimeout=3", "-o", "StrictHostKeyChecking=no", "-o", "LogLevel=Error",
        "${User}@${targetIp}", "echo OK")
    if ($probeR.Code -eq 0 -and "$($probeR.Out)" -match "OK") {
        $scpR = Invoke-Native -CmdArgs @("scp", "-P", "$Port", "-i", $KeyPath,
            "-o", "StrictHostKeyChecking=no", $agent, "${User}@${targetIp}:/mnt/us/kss-agent.sh")
        $chmodR = Invoke-Native -CmdArgs @("ssh", "-p", "$Port", "-i", $KeyPath,
            "-o", "StrictHostKeyChecking=no", "${User}@${targetIp}", "chmod +x /mnt/us/kss-agent.sh")
        # 回读 sha256 校验：设备端脚本和本地一致才算推送成功
        $localSha = (Get-FileHash $agent -Algorithm SHA256).Hash.ToLower()
        $remShaR = Invoke-Native -CmdArgs @("ssh", "-p", "$Port", "-i", $KeyPath,
            "-o", "StrictHostKeyChecking=no", "${User}@${targetIp}", "sha256sum /mnt/us/kss-agent.sh")
        $remoteSha = ("$($remShaR.Out)" -split '\s+' | Where-Object { $_ -match '^[0-9a-f]{64}$' } | Select-Object -First 1)
        if ($scpR.Code -eq 0 -and $chmodR.Code -eq 0 -and $remoteSha -eq $localSha) {
            OK "agent 已推送并校验一致（sha ${localSha}）到 ${targetIp}:/mnt/us/kss-agent.sh"
            Save-KssConfig @{ HostIP = $targetIp; Port = $Port; User = $User }
        } else {
            FAIL "agent 推送/校验失败（scp=$($scpR.Code) chmod=$($chmodR.Code) sha本地=$localSha sha远端=$remoteSha）"
            Write-Host "       以后设备在线时手动推：scp -P $Port -i <私钥路径> $agent ${User}@<IP>:/mnt/us/kss-agent.sh" -ForegroundColor DarkGray
        }
    } else {
        SKIP "设备 $targetIp 连不上（SSH 由你自行处理）；agent 未推送"
        Write-Host "       以后设备在线时手动推：scp -P $Port -i <私钥路径> $agent ${User}@<IP>:/mnt/us/kss-agent.sh" -ForegroundColor DarkGray
    }
}

Write-Host @"

=== 安装完成 ===
以后任意 PowerShell 窗口（新开的，5.1 或 7 都行）直接用：

  kss            交互菜单
  kss preview    看图认编号
  kss add <图>   加图
  kss rm N       删第 N 张
  kss set <图> N 替换第 N 张
  kss ls         列出
  kss conn       体检（主机/屏幕/路线/固件/已加载模块）

前提（由你自行处理）：设备唤醒、同一网络、SSH 已开(2222)。

"@ -ForegroundColor Green
