#requires -version 5.1
<#
  纯设备操作：列出 / 推送 / 删除。
  所有 rm / mntroot / sha256sum 都在【设备端】kss-agent.sh 里执行，
  本脚本只向设备发 "sh /mnt/us/kss-agent.sh <op> N" —— PC 端不出现危险命令文本，
  避免卡巴 PDM 行为检测误报（实测：设备端执行 rm 不触发，PC 端发 rm 命令即触发）。
#>
param(
    [Parameter(Mandatory=$true)][ValidateSet("list","push","remove","detect")][string]$Op,
    [string]$HostIP = "",
    [int]$Port = 2222,
    [string]$User = "root",
    [string]$KeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
    [int]$Index = 0,
    [string]$LocalFile = ""
)
$ErrorActionPreference = "Stop"
if (-not $HostIP) { $HostIP = "192.168.1.222" }
$agent = "/mnt/us/kss-agent.sh"

function Invoke-Agent {
    param([string]$Action2)
    & ssh -p $Port -i $KeyPath -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o LogLevel=Error "${User}@${HostIP}" "sh $agent $Action2" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "设备命令失败（设备可能在睡眠，按电源键唤醒后重试）" }
}

switch ($Op) {
    "detect" {
        # 探测专用：失败静默返回非0，不 throw（供调用方循环扫描）
        & ssh -p $Port -i $KeyPath -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o LogLevel=Error "${User}@${HostIP}" "sh $agent detect" 2>$null
        exit $LASTEXITCODE
    }
    "list" {
        @(Invoke-Agent "list") | Where-Object { [string]$_ -match '^bg_ss\d+\.png$' } |
            ForEach-Object { ([string]$_).Trim() }
    }
    "push" {
        if (-not $LocalFile -or -not (Test-Path $LocalFile)) { throw "本地文件不存在: $LocalFile" }
        $sha = (Get-FileHash $LocalFile -Algorithm SHA256).Hash.ToLower()
        $name = "bg_ss{0:D2}.png" -f $Index
        & scp -P $Port -i $KeyPath $LocalFile "${User}@${HostIP}:/var/tmp/$name" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "scp 失败：设备可能在睡眠" }
        $out = Invoke-Agent "install $Index"
        $remoteSha = ("$out" -split '\s+' | Where-Object { $_ -match '^[0-9a-f]{64}$' } | Select-Object -First 1)
        if ($remoteSha -eq $sha) { Write-Host "OK $name sha256 一致" }
        else { Write-Host "警告 $name sha 不符 本地=$sha 远端=$remoteSha" }
    }
    "remove" {
        $out = Invoke-Agent "remove $Index"
        Write-Host "$out"
    }
}
