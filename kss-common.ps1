#requires -version 5.1
<#
  Kindle 屏保工具共享函数（由 install.ps1 复制到 ~/.kss，各脚本 dot-source）。
  2026-11-28 新增：
    - 统一 Invoke-Native（修 CmdArgs.Count=1 时 1..0 的经典 PS 陷阱）
    - 配置持久化 config.json（取代 %TEMP%\kss-host.txt 这个全局可写的投毒面）
    - IP/主机名校验（防止缓存被改成 1.2.3.4 把私钥送去攻击者）
    - GUID 临时文件（并发 kss 进程不再互相覆盖）
#>
$ErrorActionPreference = "Stop"

# 统一 native 调用：EAP=Continue 期间收集输出，靠 $LASTEXITCODE 判断成败。
# PS 5.1 在 EAP=Stop 下会把原生命令的 stderr 包装成 RemoteException 终止脚本。
function Invoke-Native {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$CmdArgs)
    if ($null -eq $CmdArgs -or $CmdArgs.Count -eq 0) {
        return [pscustomobject]@{ Code = 1; Out = @("native 命令为空（通常是 dry-run 未连设备时误调用，属调用方逻辑错误）") }
    }
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if ($CmdArgs.Count -eq 1) {
            $out = & $CmdArgs[0] 2>&1 | ForEach-Object { [string]$_ }
        } else {
            $out = & $CmdArgs[0] @($CmdArgs[1..($CmdArgs.Count - 1)]) 2>&1 | ForEach-Object { [string]$_ }
        }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldEap
    }
    return [pscustomobject]@{ Code = $code; Out = @($out) }
}

function Get-KssConfigPath {
    $dir = Join-Path $env:USERPROFILE ".kss"
    return Join-Path $dir "config.json"
}

# 读取配置（不存在则返回空对象）。字段：HostIP, Port, User, KeyPath, Size, Route, Subnet, Model
function Read-KssConfig {
    $path = Get-KssConfigPath
    if (-not (Test-Path $path)) { return [pscustomobject]@{} }
    try {
        return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return [pscustomobject]@{}
    }
}

# 合并配置到变量（命令行显式指定的优先；这里只返回合并后的值对象）
function Save-KssConfig {
    param([hashtable]$Values)
    $path = Get-KssConfigPath
    $dir = Split-Path $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $existing = Read-KssConfig
    $obj = @{}
    $existing.PSObject.Properties | ForEach-Object { $obj[$_.Name] = $_.Value }
    foreach ($k in $Values.Keys) {
        if ($null -ne $Values[$k] -and "$($Values[$k])" -ne "") { $obj[$k] = $Values[$k] }
    }
    $obj | ConvertTo-Json -Compress | Set-Content $path -Encoding UTF8
}

# 校验 IP 或简单主机名；拒绝空白、路径分隔符、$ 等危险字符
function Test-KssHost {
    param([string]$Value)
    if (-not $Value) { return $false }
    if ($Value -match '^(\d{1,3}\.){3}\d{1,3}$') {
        $oct = $Value -split '\.'
        foreach ($o in $oct) { if ([int]$o -gt 255) { return $false } }
        return $true
    }
    # 主机名：字母数字、点、连字符
    return ($Value -match '^[A-Za-z0-9][A-Za-z0-9.\-]*$')
}

# 唯一临时文件（GUID，避免并发 kss 进程互相覆盖）
function New-KssTempFile {
    param([string]$Prefix = "kss-", [string]$Suffix = ".png")
    return Join-Path $env:TEMP ("{0}{1}{2}" -f $Prefix, [guid]::NewGuid().ToString('N'), $Suffix)
}
