#requires -version 5.1
<#
  Kindle 机型/屏保尺寸表与路线规则（2026-11-28 通用化）。
  由 manage-screensaver.ps1 dot-source；与 GUI 版 models.py 同一事实来源。

  事实来源（2026-11-28 联网核查）：
    - KOReader device.lua（github.com/koreader/koreader frontend/device/kindle/device.lua）
    - MobileRead Serial Numbers / ScreenSaver Hack wiki
    - Bookfere 硬件参数表 bookfere.com/post/694.html
    - ebookscreensaver.com/screensaver-size/kindle

  关键规则：系统 blanket 屏保【不缩放】——尺寸不符直接跳过、熄屏无图。
  存疑机型（PW1/PW2、Oasis2）标注 Uncertain，探测失败时提示用户用 -Size 覆盖。
#>

# 机型 → 竖屏物理分辨率。键为 KOReader/MobileRead 常见代号，值为 "WxH"
$KSS_DEVICE_SIZES = @{
    # 6" 600×800 组（老机型 / 基础款 2019 及以前）
    "k1"        = "600x800"
    "k2"        = "600x800"
    "k3"        = "600x800"
    "k4"        = "600x800"
    "k5"        = "600x800"
    "ktouch"    = "600x800"
    "k7"        = "600x800"
    "k8"        = "600x800"
    "k10"       = "600x800"      # 2019 基础款
    "kdx"       = "824x1200"     # DX/DXG 9.7"
    # 6" 768×1024 组（PW1/2，来源冲突 758 vs 768，存疑）
    "pw1"       = "768x1024"
    "pw2"       = "768x1024"
    # 6" 1072×1448 组（300 PPI，机型最多）
    "k11"       = "1072x1448"    # KT4 / Basic 4 2022（本机）
    "kt4"       = "1072x1448"
    "k2024"     = "1072x1448"    # 2024 基础款
    "pw3"       = "1072x1448"
    "pw4"       = "1072x1448"
    "voyage"    = "1072x1448"
    "oasis1"    = "1072x1448"
    # 6.8"/7" 1236×1648 / 1264×1680
    "pw5"       = "1236x1648"    # PW5 11代 2021（6.8"）
    "pw6"       = "1264x1680"    # PW6 12代 2024（7"）
    "oasis2"    = "1264x1680"    # Oasis2/3（存疑：另有 1272x1696 说法）
    "oasis3"    = "1264x1680"
    "colorsoft" = "1264x1680"    # ColorSoft 2024（彩色 Kaleido，屏保可用灰度图）
    # 大屏
    "scribe"    = "1860x2480"    # Scribe 2022（10.2"）
}

# 存疑机型：探测失败时提示用 -Size 覆盖
$KSS_DEVICE_UNCERTAIN = @("pw1", "pw2", "oasis2", "oasis3", "scribe")

# /proc/usid 前缀 → 机型代号（常见部分；新机型未收录时靠 PNG 头探测）
$KSS_USID_MODEL = @{
    "G092AQ" = "k11"     # 本机 KT4
    "G092"   = "k11"
    "B0"     = "k4"
    "90"     = "k3"
    "70"     = "k2"
    "60"     = "k1"
}

# 屏保路线：A=系统 blanket（需 mntroot rw）；B=MobileRead hack（用户分区，无需 mntroot）
$KSS_ROUTE_A = "A"
$KSS_ROUTE_B = "B"
$KSS_ROUTE_LABELS = @{
    "A" = "路线A·系统blanket（/var/local/custom_screensavers/，需mntroot）"
    "B" = "路线B·MobileRead hack（/mnt/us/screensavers/，用户分区）"
}

function Get-KssSizeForModel {
    param([string]$Model)
    if (-not $Model) { return $null }
    $key = $Model.ToLower()
    if ($KSS_DEVICE_SIZES.ContainsKey($key)) { return $KSS_DEVICE_SIZES[$key] }
    if ($KSS_USID_MODEL.ContainsKey($key)) {
        $m = $KSS_USID_MODEL[$key]
        if ($KSS_DEVICE_SIZES.ContainsKey($m)) { return $KSS_DEVICE_SIZES[$m] }
    }
    return $null
}
