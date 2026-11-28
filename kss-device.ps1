#requires -version 5.1
<#
  纯设备操作：列出 / 推送 / 删除 / 体检。
  所有 rm/mntroot/sha256sum 都在【设备端】kss-agent.sh 执行，
  本脚本只发 "sh /mnt/us/kss-agent.sh <op> N [route] [staging]"——PC 端不出现危险命令文本，
  规避卡巴 PDM 行为误报。

  2026-11-28（第二轮）：共享 kss-common.ps1；config.json 替代 TEMP 缓存；路线参数；
  staging 用 $$ 唯一名（消除 TOCTOU）；detect 输出 SIZE/ROUTE/MODEL/AGENT_VER。
#>
param(
    [Parameter(Mandatory=$true)][ValidateSet("list","push","remove","detect")][string]$Op,
    [string]$HostIP = "",
    [int]$Port = 2222,
    [string]$User = "root",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
    [int]$Index = 0,
    [string]$LocalFile = "",
    [ValidateSet("A","B","")] [string]$Route = ""
)
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $src "kss-common.ps1")
. (Join-Path $src "kss-devices.ps1")

$agent = "/mnt/us/kss-agent.sh"

# 配置优先级：显式参数 > config.json > 默认
$cfg = Read-KssConfig
if (-not $HostIP) {
    if ($cfg.PSObject.Properties['HostIP'] -and (Test-KssHost $cfg.HostIP)) { $HostIP = $cfg.HostIP }
    else { $HostIP = "192.168.1.222" }
}
if (-not (Test-KssHost $HostIP)) { throw "HostIP 不合法: $HostIP" }
if (-not $Route -and $cfg.PSObject.Properties['Route']) { $Route = $cfg.Route }

function Invoke-Agent {
    param([string]$Action2)
    $r = Invoke-Native -CmdArgs @("ssh", "-p", "$Port", "-i", $KeyPath,
        "-o", "ConnectTimeout=3", "-o", "StrictHostKeyChecking=no", "-o", "LogLevel=Error",
        "${User}@${HostIP}", "sh $agent $Action2")
    return $r
}

switch ($Op) {
    "detect" {
        $r = Invoke-Agent "detect"
        $r.Out | ForEach-Object { Write-Output $_ }
        exit $r.Code
    }
    "list" {
        $r = Invoke-Agent ("list " + $Route)
        if ($r.Code -ne 0) { throw "设备 list 失败（设备可能在睡眠，按电源键唤醒后重试）: $($r.Out -join ' ')" }
        $r.Out | Where-Object { [string]$_ -match '^bg_ss\d+\.png$' } | ForEach-Object { ([string]$_).Trim() }
    }
    "push" {
        if (-not $LocalFile -or -not (Test-Path $LocalFile)) { throw "本地文件不存在: $LocalFile" }
        $sha = (Get-FileHash $LocalFile -Algorithm SHA256).Hash.ToLower()
        $name = "bg_ss{0:D2}.png" -f $Index
        # staging 唯一名（GUID），消除固定 /var/tmp/bg_ssNN.png 的 TOCTOU
        $staging = "/var/tmp/$name.$([guid]::NewGuid().ToString('N')).png"
        $r = Invoke-Native -CmdArgs @("scp", "-P", "$Port", "-i", $KeyPath,
            "-o", "StrictHostKeyChecking=no", "-o", "LogLevel=Error", "-o", "ConnectTimeout=3",
            $LocalFile, "${User}@${HostIP}:$staging")
        if ($r.Code -ne 0) { throw "scp 失败：设备可能在睡眠 — $($r.Out -join ' ')" }
        $out = (Invoke-Agent ("install {0} {1} {2}" -f $Index, $Route, $staging)).Out
        $remoteSha = ("$out" -split '\s+' | Where-Object { $_ -match '^[0-9a-f]{64}$' } | Select-Object -First 1)
        if ($remoteSha -eq $sha) { Write-Host "OK $name sha256 一致" }
        else { throw "sha256 不符 本地=$sha 远端=$remoteSha（$name 可能未正确写入）" }
    }
    "remove" {
        $r = Invoke-Agent ("remove {0} {1}" -f $Index, $Route)
        if ($r.Code -ne 0) { throw "设备 remove 失败: $($r.Out -join ' ')" }
        Write-Host "$($r.Out -join ' ')"
    }
}
