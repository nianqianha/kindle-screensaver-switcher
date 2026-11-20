#requires -version 5.1
<#
  Kindle 熄屏封面管理（一个脚本、自动认机型、带连接引导）：
    1=看图认编号  2=加图  3=删图  4=替换指定编号  5=列出  6=连接状态
  连接信息可给可不给：不给就自动探测同网段设备；探测不到给图文指引。
  屏幕尺寸从设备自动读取（kss-agent.sh detect），不支持的机型也能变通。
#>
param(
    [Parameter(Position=0)][string]$PosAction = "",
    [Parameter(Position=1)][string]$PosArg = "",
    [ValidateSet("list","add","remove","preview","replace","detect","")][string]$Action = "",
    [string]$HostIP = "",
    [int]$Port = 2222,
    [string]$User = "root",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
    [string]$Python = "python",
    [string]$Pick = "",
    [string]$Image = "",
    [switch]$Yes,
    [switch]$NoPreview
)
# 位置参数简写：kss add C:\pic.png / kss rm 5 / kss preview
if ($PosAction) {
    $aliasMap = @{ 'ls'='list'; 'rm'='remove'; 'del'='remove'; 'set'='replace';
                  'prev'='preview'; 'view'='preview'; 'conn'='detect'; 'add'='add';
                  'replace'='replace'; 'remove'='remove'; 'preview'='preview';
                  'list'='list'; 'detect'='detect' }
    if ($aliasMap.ContainsKey($PosAction.ToLower())) {
        $Action = $aliasMap[$PosAction.ToLower()]
    } else {
        # 不是已知子命令 → 当作图片路径，默认 add
        $PosArg = $PosAction; $Action = "add"
    }
}
if ($PosArg) {
    if ($Action -eq "remove") { $Pick = $PosArg }
    elseif ($Action -eq "replace" -and $PosArg -match '^\d+$') { $Pick = $PosArg }
    else { $Image = $PosArg }
}

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dev  = Join-Path $root "kss-device.ps1"
$conv = Join-Path $root "to-kindle-screensaver.py"
$sheet = Join-Path $root "kss-contact-sheet.py"

# 连接引导：没给 IP 就扫同网段，找不到给图文指引
function Ensure-Connection {
    if ($HostIP) { return $true }
    $cache = Join-Path $env:TEMP "kss-host.txt"
    # 1) 上次成功的 IP（最快）
    $candidates = @()
    if (Test-Path $cache) { $candidates += (Get-Content $cache -Raw).Trim() }
    # 2) 本机同网段的 arp 活跃主机（秒级拿到，不盲扫）
    $localIp = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -match '^192\.168\.' } | Select-Object -First 1).IPAddress
    if (-not $localIp) { $localIp = "192.168.1.100" }
    $subnet = $localIp.Substring(0, $localIp.LastIndexOf('.'))
    $arp = arp -a 2>$null | Where-Object { $_ -match "^\s*$subnet\." } |
        ForEach-Object { ($_ -split '\s+')[1] } | Where-Object { $_ -and $_ -ne $localIp }
    $candidates += $arp
    # 3) 常见固定 IP
    $candidates += "$subnet.195"
    $candidates += @($candidates | Select-Object -Unique | Where-Object { $_ -and $_ -ne $localIp })

    Write-Host "`n正在查找 Kindle（先试记住的地址和同网段设备）..." -ForegroundColor Cyan
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"   # 外部 ssh 的 stderr 不能中断探测循环
    foreach ($ip in $candidates) {
        $r = @(& ssh -p $Port -i $KeyPath -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o LogLevel=Error "${User}@${ip}" "sh /mnt/us/kss-agent.sh detect" 2>$null)
        if ($LASTEXITCODE -eq 0 -and ($r -join ' ') -match 'SIZE=') {
            $ErrorActionPreference = $oldEap
            $script:HostIP = $ip
            $ip | Set-Content $cache
            Write-Host "找到设备：$ip（已记住，下次自动用）" -ForegroundColor Green
            return $true
        }
    }
    $ErrorActionPreference = $oldEap
    Write-Host @"

没找到 Kindle。请确认：

  设备已唤醒、和电脑同一网络、SSH 已开启（2222）。
  这些由你自行处理；准备好后重跑即可，脚本会自动找设备。
  也可直接用 -HostIP 192.168.x.x 指定地址。

"@ -ForegroundColor Yellow
    return $false
}

function Get-Detect {
    @(& $dev -Op detect -HostIP $HostIP -Port $Port -User $User -KeyPath $KeyPath 2>&1)
}
function Get-ScreenSize {
    $line = (Get-Detect | Where-Object { [string]$_ -match '^SIZE=' } | Select-Object -First 1)
    if ($line -match 'SIZE=(\d+)x(\d+)') { return "$($Matches[1])x$($Matches[2])" }
    return "1072x1448"   # 兜底
}
function Get-Images {
    @(& $dev -Op list -HostIP $HostIP -Port $Port -User $User -KeyPath $KeyPath 2>&1) |
        Where-Object { [string]$_ -match '^bg_ss\d+\.png$' } |
        ForEach-Object { ([string]$_).Trim() }
}
function Convert-And-Push {
    param([string]$Src, [int]$Index, [string]$Size)
    $name = "bg_ss{0:D2}.png" -f $Index
    $tmp = Join-Path $env:TEMP $name
    & $Python $conv $Src $tmp $Size 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) { throw "转换失败: $Src" }
    & $dev -Op push -HostIP $HostIP -Port $Port -User $User -KeyPath $KeyPath -Index $Index -LocalFile $tmp 2>&1
    if ($LASTEXITCODE -ne 0) { throw "推送失败: $name" }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== Kindle 熄屏封面管理 ===" -ForegroundColor Green

if (-not $Action) {
    Write-Host "`n选择操作：" -ForegroundColor Cyan
    Write-Host "  1=看图认编号   2=加图   3=删图   4=替换指定编号   5=列出   6=连接状态"
    $c = Read-Host "输入 1/2/3/4/5/6"
    $Action = switch ($c) {
        "1" { "preview" } "2" { "add" } "3" { "remove" }
        "4" { "replace" } "5" { "list" } "6" { "detect" } default { throw "无效选择" }
    }
}

if (-not (Ensure-Connection)) { exit }

$size = Get-ScreenSize
$info = Get-Detect
$count = (($info | Where-Object { [string]$_ -match '^COUNT=' }) -replace 'COUNT=','')
Write-Host ("设备 {0}  屏幕 {1}  已有 {2} 张屏保" -f $HostIP, $size, $count) -ForegroundColor Green

if ($Action -eq "detect") { Write-Host "连接正常。"; exit }
$names = @(Get-Images)

if ($Action -eq "list") {
    if ($names.Count -eq 0) { Write-Host "（设备里没有屏保图）" -ForegroundColor Yellow }
    else { $names | ForEach-Object { Write-Host "  $_" } }
    exit
}

if ($Action -eq "preview") {
    Write-Host "正在从设备拉图生成预览（每张图标着编号）..." -ForegroundColor Cyan
    & $Python $sheet --host $HostIP --port $Port --user $User --key $KeyPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "预览失败" }
    Write-Host "预览图已打开，图下方标着编号。" -ForegroundColor Green
    exit
}

if ($Action -eq "remove") {
    Write-Host "`n当前图:" -ForegroundColor Cyan
    $names | ForEach-Object { Write-Host "  $_" }
    if ($names.Count -eq 0) { Write-Host "没有可删的图"; exit }
    Write-Host "输入要删的编号（逗号分隔，如 2,5；不确定就先选 1 看图）" -ForegroundColor Cyan
    $pick = $Pick; if (-not $pick) { $pick = Read-Host "编号" }
    if ($pick -eq 'q') { exit }
    $idxs = @($pick -split ',' | ForEach-Object { [int]$_.Trim() } | Sort-Object -Unique)
    $targets = @()
    foreach ($i in $idxs) {
        $n = "bg_ss{0:D2}.png" -f $i
        if ($names -contains $n) { $targets += $i }
        else { Write-Host "  跳过 $n（不存在）" -ForegroundColor Yellow }
    }
    if ($targets.Count -eq 0) { Write-Host "没有可删的图"; exit }
    Write-Host "将删除:"; $targets | ForEach-Object { Write-Host ("  bg_ss{0:D2}.png" -f $_) }
    $ok = if ($Yes) { 'y' } else { Read-Host "确认删除？(y/N)" }
    if ($ok -notmatch '^[yY]$') { Write-Host "已取消"; exit }
    foreach ($i in $targets) {
        & $dev -Op remove -HostIP $HostIP -Port $Port -User $User -KeyPath $KeyPath -Index $i 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host ("删除失败: bg_ss{0:D2}.png" -f $i) -ForegroundColor Red }
    }
    exit
}

if ($Action -eq "add" -or $Action -eq "replace") {
    $isReplace = ($Action -eq "replace")
    if ($isReplace) {
        Write-Host "`n当前图:" -ForegroundColor Cyan
        $names | ForEach-Object { Write-Host "  $_" }
    }
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
        $idx = [int]$idxRaw
        $preview = Join-Path $env:TEMP "kss-replace-preview.png"
        & $Python $conv $files[0] $preview $size 2>&1
        if ($LASTEXITCODE -ne 0) { throw "转换失败" }
        if (-not $NoPreview) { Write-Host "已打开样例，看完确认。" -ForegroundColor Yellow; Start-Process $preview }
        $ok = if ($Yes) { 'y' } else { Read-Host ("用样例替换 bg_ss{0:D2}.png 吗？(y/N)" -f $idx) }
        if ($ok -notmatch '^[yY]$') { Write-Host "已取消"; exit }
        Convert-And-Push $files[0] $idx $size
        Remove-Item $preview -Force -ErrorAction SilentlyContinue
        Write-Host ("完成：bg_ss{0:D2}.png 已替换" -f $idx) -ForegroundColor Green
    } else {
        $used = @($names | ForEach-Object { if ($_ -match 'bg_ss(\d+)\.png') { [int]$Matches[1] } })
        $free = @(); for ($i = 0; $free.Count -lt $files.Count -and $i -lt 100; $i++) {
            if ($used -notcontains $i) { $free += $i }
        }
        if ($free.Count -lt $files.Count) { throw "空闲编号不足（最多 100 张）" }
        Write-Host "`n将添加（编号 ← 文件）:" -ForegroundColor Cyan
        for ($j = 0; $j -lt $files.Count; $j++) {
            Write-Host ("  bg_ss{0:D2}.png  <- {1}" -f $free[$j], (Split-Path $files[$j] -Leaf))
        }
        $ok = if ($Yes) { 'y' } else { Read-Host "确认添加？(y/N)" }
        if ($ok -notmatch '^[yY]$') { Write-Host "已取消"; exit }
        $env:PYTHONUTF8 = "1"
        for ($j = 0; $j -lt $files.Count; $j++) { Convert-And-Push $files[$j] $free[$j] $size }
        Write-Host "完成。当前图:" -ForegroundColor Green
        Get-Images | ForEach-Object { Write-Host "  $_" }
    }
    exit
}
