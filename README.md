# Kindle 屏保替换工具

给 Kindle 换熄屏封面的小工具。挑几张图，转成 Kindle 能认的灰度 PNG，通过 SSH 放到设备上。下一次熄屏就能看到。

有两个入口，规则一样：一个带界面的 exe，一个在 PowerShell 里敲一行命令的 `kss`。常用的是后者。

## 用之前

只处理你自己的 Kindle。设备上要装好 SSH（端口 2222），私钥放在 `~/.ssh/`。怎么开 SSH 自己弄，这个工具不管。设备睡眠时连不上，按一下电源键，等半分钟再试。

Kindle 的系统屏保不缩放图片。尺寸不对就跳过，熄屏什么也不显示。所以工具会先从设备读屏幕尺寸，读不到就要求你明确指定，不会自己猜一个数往下走。常见的尺寸：

| 设备 | 尺寸 |
|---|---|
| Kindle Basic 4 / PW3 / PW4 / Voyage / Oasis 1 | 1072×1448 |
| Paperwhite 5 | 1236×1648 |
| Paperwhite 6 / Oasis 2、3 / ColorSoft | 1264×1680 |
| Kindle Scribe | 1860×2480 |
| 更早的 6 寸机型 | 600×800 |

微信读书那个应用内的休眠壁纸是 1236×1648，它自己会缩放，和这里说的系统屏保不是一回事。

## 装 kss

在 PowerShell 里跑一行：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

它检查 Python 和 Pillow，把脚本复制到 `%USERPROFILE%\.kss`，给 PowerShell 加一个 `kss` 命令。设备在线的话顺手把 `kss-agent.sh` 放到 Kindle 的 `/mnt/us/`，放完读一遍 sha256 确认；设备没开就跳过，以后手动补。

要在 PowerShell 7 里用也行，安装时会同时写两个版本的 profile。新开一个窗口才生效。

## 用 kss

```
kss                          菜单
kss add C:\pic.jpg           加一张
kss add C:\a.jpg C:\b.jpg    加多张
kss ls                       列出设备上的图
kss preview                  看图认编号
kss rm 5                     删第 5 张（kss rm "2,5" 删多张）
kss set C:\pic.jpg 3         用 pic.jpg 换掉第 3 张
kss conn                     看设备信息
kss rollback                 恢复最近一次备份的图
```

删和换之前会把原来的图拉回 `%USERPROFILE%\.kss\backup\`，后悔了就跑 `kss rollback`。

不想真动设备就加 `-WhatIf`，它只把要做的事打印出来：

```
kss add C:\pic.jpg -WhatIf
```

## 尺寸和路线不对的时候

工具一般能自己认出屏幕尺寸和屏保路线。认不出时会报错让你指定，不会闷头按 Basic 4 的尺寸转。

```
kss add C:\pic.jpg -Model pw5
kss add C:\pic.jpg -Size 1264x1680
```

`-Model` 用机型代号，都在 `kss-devices.ps1` 里；`-Size` 直接给宽高。Paperwhite 1、2 和 Oasis 2 的资料有两个说法，表里有标注，最好以 `kss conn` 读到的尺寸为准。

屏保存两条路线：

- A：系统自带那一套，写到 `/var/local/custom_screensavers/`，需要 root。
- B：MobileRead 的 screensaver hack，写到 `/mnt/us/screensavers/`，不需要动系统分区。

`kss conn` 会显示当前走哪条。要手动指定就加 `-Route B`。广告版设备上会提示 `ad_screensaver`，系统的广告屏保可能盖住你放的图，这个工具不去广告。固件 5.16.3 以后老的 hack 可能失效，走 B 之前先确认它还能用。

装了 KOReader 的设备自己也会画屏保，两套屏保会先后出现，差一两秒。这是正常现象。别去把 `preventScreenSaver` 钉成 1，那样系统会忽略电源键，卡在屏保里出不来。

连接信息存在 `%USERPROFILE%\.kss\config.json`，改一次以后就不用每次都填。

## 带界面的 exe

双击 `dist/kindle-screensaver-tool.exe`。选图、选机型、选填充方式，填连接信息，点检测路线，再点一键替换。填充方式里「完整保留」不裁人物，空白处用原图模糊补上；「裁剪填满」等比缩放后居中裁掉多余部分。

只想转图不想推设备，点「仅转换」，文件会留在输出目录。

## 其余文件

GUI 部分：`models.py` 是机型尺寸表，`converter.py` 转换图片，`device.py` 连设备、查路线，`deploy.py` 上传和校验，`gui_qt.py` 是界面。`gui.py.bak-tkinter-20261120` 是换界面之前的备份，不用了。

`kss` 部分：`manage-screensaver.ps1` 是入口，`kss-device.ps1` 只管设备操作，`kss-common.ps1` 放共用函数，`kss-devices.ps1` 是机型表，`kss-agent.sh` 在设备上跑，`kss-probe.py` 给安装器探测 Python 用，`kss-contact-sheet.py` 拼编号预览图，`to-kindle-screensaver.py` 转图。

设备端 `kss-agent.sh` 要留在 `/mnt/us/`，删了就没法操作了。删文件、切读写这些动作都放在设备上做，电脑上只发一句命令。Windows 杀软看到电脑端一整串操作容易误报。

License: MIT。
