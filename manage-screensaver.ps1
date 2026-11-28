#requires -version 5.1
<#
  Kindle 熄屏封面管理（通用版 2026-11-28）：
    1=看图 2=加图 3=删图 4=替换 5=列出 6=体检  命令：kss ls/add/rm/set/preview/conn
  通用化：
    - 设备自动探测 SIZE/MODEL/ROUTE/FW/BLANKET/AGENT_VER（kss conn 体检）
    - -Size WxH / -Model <机型> / -Route A|B 显式覆盖（探测失败不再静默回退）
    - 多机型尺寸表 kss-devices.ps1（含 pw5/pw6/oasis/scribe 修正值）
    - -WhatIf dry-run：只打印计划不连设备
    - 删除/替换前备份原图到 ~/.kss/backup/<时间>/，可 kss rollback
    - 批量加图显示逐张进度
    - 配置持久化 ~/.kss/config.json（不再用可被投毒的 %TEMP%\kss-host.txt）
#>
param(
    [Parameter(Position=0)][string]$PosAction = "",
    [Parameter(Position=1)][string]$PosArg = "",
    [Parameter(Position=2)][string]$PosArg2 = "",
    [ValidateSet("list","add","remove","preview","replace","detect","rollback","")][string]$Action = "",
    [string]$HostIP = "",
    [int]$Port = 2222,
    [string]$User = "root",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
    [string]$Python = "python",
    [string]$Pick = "",
    [string]$Image = "",
    [string]$Size = "",        # 显式尺寸 WxH，覆盖设备探测
    [string]$Model = "",       # 显式机型代号（查 kss-devices.ps1）
    [ValidateSet("A","B","")] [string]$Route = "",
    [string]$Subnet = "",
    [switch]$Yes,
    [switch]$NoPreview,
    [switch]$WhatIf            # dry-run：不连设备，只打印计划
)
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $src "kss-common.ps1")
. (Join-Path $src "kss-devices.ps1")

# 位置参数简写
if ($PosAction) {
    $aliasMap = @{ 'ls'='list'; 'rm'='remove'; 'del'='remove'; 'set'='replace';
                  'prev'='preview'; 'view'='preview'; 'conn'='detect'; 'check'='detect';
                  'add'='add'; 'replace'='replace'; 'remove'='remove';
                  'preview'='preview'; 'list'='list'; 'detect'='detect'; 'rollback'='rollback' }
    if ($aliasMap.ContainsKey($PosAction.ToLower())) { $Action = $aliasMap[$PosAction.ToLower()] }
    else { $PosArg = $PosAction; $Action = "add" }
}
if ($PosArg) {
    if ($Action -eq "remove") { $Pick = $PosArg }
    elseif ($Action -eq "replace" -and $PosArg -match '^\d+$') { $Pick = $PosArg }
    else { $Image = $PosArg }
}
if ($PosArg2) {
    if ($PosArg2 -match '^\d+$') {
        $Pick = $PosArg2
        if ($Action -eq "replace" -and $PosArg -notmatch '^\d+$' -and -not $Image) { $Image = $PosArg }
    } else {
        if ($PosArg -match '^\d+$') { $Pick = $PosArg }
        $Image = $PosArg2
    }
}

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
$dev  = Join-Path $src "kss-device.ps1"
$conv = Join-Path $src "to-kindle-screensaver.py"
$sheet = Join-Path $src "kss-contact-sheet.py"

# 配置优先级：显式参数 > config.json > 默认
$cfg = Read-KssConfig
if (-not $HostIP -and $cfg.PSObject.Properties['HostIP'] -and (Test-KssHost $cfg.HostIP)) { $HostIP = $cfg.HostIP }
if (-not $Port -and $cfg.PSObject.Properties['Port']) { $Port = [int]$cfg.Port }
if (-not $Route -and $cfg.PSObject.Properties['Route']) { $Route = $cfg.Route }
if (-not $Size -and $cfg.PSObject.Properties['Size']) { $Size = $cfg.Size }
if (-not $Model -and $cfg.PSObject.Properties['Model']) { $Model = $cfg.Model }

function Ensure-Connection {
    if ($HostIP) { return $true }
    $subnets = @()
    if ($Subnet) { $subnets += $Subnet.TrimEnd('.') }
    else {
        $localIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | ForEach-Object { $_.IPAddress })
        $subnets = @($localIps | Where-Object { $_.LastIndexOf('.') -gt 0 } |
            ForEach-Object { $_.Substring(0, $_.LastIndexOf('.')) } | Select-Object -Unique)
    }
    if ($subnets.Count -eq 0) { $subnets = @("192.168.1") }
    $arpOut = @((Invoke-Native -CmdArgs @("arp", "-a")).Out)
    $candidates = @()
    foreach ($sn in $subnets) {
        $escaped = [regex]::Escape($sn)
        $candidates += ($arpOut | Where-Object { $_ -match "^\s*$escaped\." } |
            ForEach-Object { ($_ -split '\s+')[1] } | Where-Object { $_ })
        $candidates += "$sn.222"
    }
    $candidates = @($candidates | Select-Object -Unique | Where-Object { (Test-KssHost $_) -and $_ -notmatch '^(127\.|169\.254\.)' })
    Write-Host "`n正在查找 Kindle..." -ForegroundColor Cyan
    foreach ($ip in $candidates) {
        $r = @((Invoke-Native -CmdArgs @("ssh", "-p", "$Port", "-i", $KeyPath,
            "-o", "ConnectTimeout=3", "-o", "StrictHostKeyChecking=no", "-o", "LogLevel=Error",
            "${User}@${ip}", "sh /mnt/us/kss-agent.sh detect")).Out)
        if (($r -join ' ') -match 'SIZE=') {
            $script:HostIP = $ip
            Write-Host "找到设备：$ip" -ForegroundColor Green
            return $true
        }
    }
    Write-Host "`n没找到 Kindle。请确认：设备唤醒、同一网络、SSH 已开(2222)。也可 -HostIP x.x.x.x 指定。" -ForegroundColor Yellow
    return $false
}

# 一次 detect 结果复用（原来调两次 ssh）
$script:DetectInfo = $null
function Get-DetectInfo {
    if ($null -ne $script:DetectInfo) { return $script:DetectInfo }
    $out = @((Invoke-Native -CmdArgs @($dev, "-Op", "detect", "-HostIP", $HostIP,
        "-Port", "$Port", "-User", $User, "-KeyPath", $KeyPath)).Out)
    $info = @{}
    foreach ($line in $out) { if ($line -match '^([A-Z_]+)=(.*)$') { $info[$Matches[1]] = $Matches[2] } }
    $script:DetectInfo = $info
    return $info
}
function Resolve-Size {
    $info = Get-DetectInfo
    # 优先级：-Size > -Model 查表 > 设备 SIZE > 探测失败硬失败
    if ($Size) { return $Size }
    if ($Model) {
        $s = Get-KssSizeForModel $Model
        if ($s) { return $s }
        Write-Host "警告：机型 $Model 不在尺寸表，回退设备探测。" -ForegroundColor Yellow
    }
    if ($info.ContainsKey('SIZE') -and $info['SIZE'] -match '^\d+x\d+$') { return $info['SIZE'] }
    # 探测失败：绝不静默回退 Basic4 尺寸（别的机型会熄屏空白）
    throw "无法从设备读取屏幕尺寸，且未指定 -Size/-Model。请用 -Size 1072x1448 或 -Model kt4 显式指定（机型对照见 kss-devices.ps1）。"
}
function Get-Images {
    @((Invoke-Native -CmdArgs @($dev, "-Op", "list", "-HostIP", $HostIP, "-Port", "$Port",
        "-User", $User, "-KeyPath", $KeyPath, "-Route", $Route)).Out) |
        Where-Object { [string]$_ -match '^bg_ss\d+\.png$' } | ForEach-Object { ([string]$_).Trim() }
}
function Backup-Target {
    param([string]$Name)
    # 删除/替换前把原图拉回本地备份（不可逆操作的兜底）
    $info = Get-DetectInfo
    $dir = if ($info.ContainsKey('DIR')) { $info['DIR'] } else { "/var/local/custom_screensavers" }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $bk = Join-Path $env:USERPROFILE ".kss\backup\$stamp"
    if (-not (Test-Path $bk)) { New-Item -ItemType Directory -Force -Path $bk | Out-Null }
    $local = Join-Path $bk $Name
    $r = Invoke-Native -CmdArgs @("scp", "-P", "$Port", "-i", $KeyPath,
        "-o", "StrictHostKeyChecking=no", "${User}@${HostIP}:$dir/$Name", $local)
    if ($r.Code -eq 0 -and (Test-Path $local)) { Write-Host "  已备份原图 → $local" -ForegroundColor DarkGray }
    else { Write-Host "  备份失败（原图可能不存在），继续操作" -ForegroundColor Yellow }
}
function Convert-And-Push {
    param([string]$Src, [int]$Index, [string]$Sz)
    $name = "bg_ss{0:D2}.png" -f $Index
    if ($WhatIf) { Write-Host ("  [dry-run] 转换 {0} → {1} ({2})，scp → install → sha 校验" -f (Split-Path $Src -Leaf), $name, $Sz) -ForegroundColor DarkYellow; return }
    $tmp = New-KssTempFile -Prefix "kss-$name-"
    $convR = Invoke-Native -CmdArgs @($Python, $conv, $Src, $tmp, $Sz)
    if ($convR.Code -ne 0 -or -not (Test-Path $tmp)) { throw "转换失败: $Src — $($convR.Out -join ' ')" }
    $pushR = Invoke-Native -CmdArgs @($dev, "-Op", "push", "-HostIP", $HostIP, "-Port", "$Port",
        "-User", $User, "-KeyPath", $KeyPath, "-Index", "$Index", "-LocalFile", $tmp, "-Route", $Route)
    if ($pushR.Code -ne 0) { throw "推送失败: $name — $($pushR.Out -join ' ')" }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Host "  OK $name" -ForegroundColor Green
}

Write-Host "`n=== Kindle 熄屏封面管理 ===" -ForegroundColor Green
if (-not $Action) {
    Write-Host "`n选择操作：" -ForegroundColor Cyan
    Write-Host "  1=看图  2=加图  3=删图  4=替换  5=列出  6=体检"
    $c = Read-Host "输入 1/2/3/4/5/6"
    $Action = switch ($c) { "1"{"preview"} "2"{"add"} "3"{"remove"} "4"{"replace"} "5"{"list"} "6"{"detect"} default { throw "无效选择" } }
}

# dry-run 不需要连设备；rollback 也不需要
if (-not $WhatIf -and $Action -ne "rollback" -and -not (Ensure-Connection)) { exit }

if ($Action -eq "rollback") {
    $bkRoot = Join-Path $env:USERPROFILE ".kss\backup"
    if (-not (Test-Path $bkRoot)) { Write-Host "没有备份目录"; exit }
    $dirs = @(Get-ChildItem $bkRoot -Directory | Sort-Object Name -Descending)
    if ($dirs.Count -eq 0) { Write-Host "没有可回滚的备份"; exit }
    $latest = $dirs[0].FullName
    $files = @(Get-ChildItem $latest -File | Where-Object { $_.Name -match '^bg_ss\d+\.png$' })
    Write-Host "最近备份：$latest（$($files.Count) 张）" -ForegroundColor Cyan
    $files | ForEach-Object { Write-Host "  $($_.Name)" }
    if (-not (Ensure-Connection)) { exit }
    $ok = if ($Yes) { 'y' } else { Read-Host "把这些图恢复到设备？(y/N)" }
    if ($ok -notmatch '^[yY]$') { Write-Host "已取消"; exit }
    foreach ($f in $files) { Convert-And-Push $f.FullName ([int]($f.BaseName -replace 'bg_ss','')) (Resolve-Size) }
    exit
}

$info = if (-not $WhatIf) { Get-DetectInfo } else { @{} }
if ($Action -eq "detect") {
    Write-Host "`n--- 设备体检 ---" -ForegroundColor Cyan
    foreach ($k in @('SIZE','MODEL','ROUTE','DIR','COUNT','BLANKET','FW','AGENT_VER')) {
        if ($info.ContainsKey($k)) { Write-Host ("  {0,-10} {1}" -f $k, $info[$k]) }
    }
    $agentVer = if ($info.ContainsKey('AGENT_VER')) { $info['AGENT_VER'] } else { '?' }
    if ($agentVer -ne '2') { Write-Host "  设备端 agent 版本旧（期望 2），请重新运行 install.ps1 推送。" -ForegroundColor Yellow }
    if ($info.ContainsKey('BLANKET') -and $info['BLANKET'] -match 'ad_screensaver') {
        Write-Host "  广告版（ad_screensaver）：系统屏保可能覆盖自定义图，本工具不内置去广告。" -ForegroundColor Yellow
    }
    if ($info.ContainsKey('FW') -and $info['FW'] -match '5\.16\.3|5\.1[789]|5\.2') {
        Write-Host "  新固件（≥5.16.3）：旧 MobileRead hack 可能失效，路线 B 请先确认可用。" -ForegroundColor Yellow
    }
    exit
}

$size = if ($WhatIf -and $Size) { $Size } elseif ($WhatIf -and $Model) { (Get-KssSizeForModel $Model) } elseif ($WhatIf) { "?" } else { Resolve-Size }
$count = if ($info.ContainsKey('COUNT')) { $info['COUNT'] } else { '?' }
Write-Host ("设备 {0}  屏幕 {1}  路线 {2}  已有 {3} 张" -f $HostIP, $size, $(if($Route){$Route}else{$(if($info.ContainsKey('ROUTE')){$info['ROUTE']}else{'?'})}), $count) -ForegroundColor Green
$names = if ($WhatIf) { @() } else { @(Get-Images) }

if ($Action -eq "list") {
    if ($names.Count -eq 0) { Write-Host "（设备里没有屏保图）" -ForegroundColor Yellow }
    else { $names | ForEach-Object { Write-Host "  $_" } }
    exit
}
if ($Action -eq "preview") {
    if ($WhatIf) { Write-Host "  [dry-run] 拉图拼联系表并打开"; exit }
    Write-Host "正在拉图生成预览..." -ForegroundColor Cyan
    $r = Invoke-Native -CmdArgs @($Python, $sheet, "--host", $HostIP, "--port", "$Port", "--user", $User, "--key", $KeyPath)
    if ($r.Code -ne 0) { throw "预览失败 — $($r.Out -join ' ')" }
    Write-Host "预览图已打开。" -ForegroundColor Green
    exit
}
if ($Action -eq "remove") {
    Write-Host "`n当前图:" -ForegroundColor Cyan; $names | ForEach-Object { Write-Host "  $_" }
    if ($names.Count -eq 0 -and -not $WhatIf) { Write-Host "没有可删的图"; exit }
    $pick = $Pick; if (-not $pick) { $pick = Read-Host "编号（逗号分隔，q 退出）" }
    if ($pick -eq 'q') { exit }
    $parts = @($pick -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    $bad = @($parts | Where-Object { $_ -notmatch '^\d+$' })
    if ($bad.Count -gt 0) { Write-Host "无效编号：$($bad -join ',')" -ForegroundColor Red; exit }
    $idxs = @($parts | ForEach-Object { [int]$_ } | Where-Object { $_ -ge 0 -and $_ -le 99 } | Sort-Object -Unique)
    if ($idxs.Count -eq 0) { Write-Host "没有有效编号"; exit }
    $targets = @($idxs | Where-Object { ($names -contains ("bg_ss{0:D2}.png" -f $_)) -or $WhatIf })
    Write-Host "将删除:"; $targets | ForEach-Object { Write-Host ("  bg_ss{0:D2}.png" -f $_) }
    $ok = if ($Yes -or $WhatIf) { 'y' } else { Read-Host "确认删除？(y/N)" }
    if ($ok -notmatch '^[yY]$') { Write-Host "已取消"; exit }
    foreach ($i in $targets) {
        $n = "bg_ss{0:D2}.png" -f $i
        if ($WhatIf) { Write-Host "  [dry-run] remove $n"; continue }
        Backup-Target $n
        $r = Invoke-Native -CmdArgs @($dev, "-Op", "remove", "-HostIP", $HostIP, "-Port", "$Port",
            "-User", $User, "-KeyPath", $KeyPath, "-Index", "$i", "-Route", $Route)
        if ($r.Code -ne 0) { Write-Host ("删除失败: {0} — {1}" -f $n, ($r.Out -join ' ')) -ForegroundColor Red }
    }
    exit
}
if ($Action -eq "add" -or $Action -eq "replace") {
    $isReplace = ($Action -eq "replace")
    if ($isReplace) { Write-Host "`n当前图:" -ForegroundColor Cyan; $names | ForEach-Object { Write-Host "  $_" } }
    if ($Image) { $files = @($Image) }
    else {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = if ($isReplace) { "选择要替换的图" } else { "选择要添加的图（可多选）" }
        $dlg.Multiselect = -not $isReplace
        $dlg.Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp;*.webp|所有文件|*.*"
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Write-Host "已取消"; exit }
        $files = @($dlg.FileNames)
    }
    if ($isReplace) {
        $idxRaw = $Pick; if (-not $idxRaw) { $idxRaw = Read-Host "替换哪个编号？（0-99）" }
        if ($idxRaw -notmatch '^\d+$' -or [int]$idxRaw -lt 0 -or [int]$idxRaw -gt 99) { Write-Host "无效编号：$idxRaw" -ForegroundColor Red; exit }
        $idx = [int]$idxRaw
        $n = "bg_ss{0:D2}.png" -f $idx
        $preview = New-KssTempFile -Prefix "kss-preview-"
        if ($WhatIf) { Write-Host "  [dry-run] 替换 $n ← $(Split-Path $files[0] -Leaf) ($size)"; exit }
        $r = Invoke-Native -CmdArgs @($Python, $conv, $files[0], $preview, $size)
        if ($r.Code -ne 0) { throw "转换失败 — $($r.Out -join ' ')" }
        if (-not $NoPreview) { Write-Host "已打开样例，看完确认。" -ForegroundColor Yellow; Start-Process $preview }
        $ok = if ($Yes) { 'y' } else { Read-Host "替换 $n 吗？(y/N)" }
        if ($ok -notmatch '^[yY]$') { Write-Host "已取消"; exit }
        Backup-Target $n
        Convert-And-Push $files[0] $idx $size
        Remove-Item $preview -Force -ErrorAction SilentlyContinue
        Write-Host "完成：$n 已替换" -ForegroundColor Green
    } else {
        $used = @($names | ForEach-Object { if ($_ -match 'bg_ss(\d+)\.png') { [int]$Matches[1] } })
        $free = @(); for ($i = 0; $free.Count -lt $files.Count -and $i -lt 100; $i++) { if ($used -notcontains $i) { $free += $i } }
        if ($free.Count -lt $files.Count) { throw "空闲编号不足（最多 100 张）" }
        Write-Host "`n将添加（编号 ← 文件）:" -ForegroundColor Cyan
        for ($j = 0; $j -lt $files.Count; $j++) { Write-Host ("  bg_ss{0:D2}.png  <- {1}" -f $free[$j], (Split-Path $files[$j] -Leaf)) }
        $ok = if ($Yes -or $WhatIf) { 'y' } else { Read-Host "确认添加？(y/N)" }
        if ($ok -notmatch '^[yY]$') { Write-Host "已取消"; exit }
        $env:PYTHONUTF8 = "1"
        for ($j = 0; $j -lt $files.Count; $j++) {
            Write-Host ("  [{0}/{1}] bg_ss{2:D2} ← {3}" -f ($j+1), $files.Count, $free[$j], (Split-Path $files[$j] -Leaf)) -ForegroundColor Cyan
            Convert-And-Push $files[$j] $free[$j] $size
        }
        if ($WhatIf) { Write-Host "完成（dry-run，未改动设备）。" -ForegroundColor DarkYellow }
        else {
            Write-Host "完成。当前图:" -ForegroundColor Green
            Get-Images | ForEach-Object { Write-Host "  $_" }
        }
    }
    exit
}
