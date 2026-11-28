# Kindle 屏保替换工具

本工具用于将自定义图片设置为 Kindle 设备的熄屏封面。用户选定图片后，工具将其转换为设备所需的灰度 PNG 格式，并通过 SSH 传输至设备。图片在下次熄屏时生效。

工具提供命令行版本，通过可执行脚本调用；安装一次后即可反复使用。

> 本文档有英文版本：[README.en.md](README.en.md)。

## 一、使用前提

本工具仅适用于用户本人拥有且已完成越狱的 Kindle 设备。工具本身不包含越狱组件、不提供去除广告功能，也不分发厂商固件。

使用本工具前，设备须满足以下条件：

1. 设备已完成越狱，并已开启 SSH 服务（端口 2222）。
2. 客户端计算机已配置可用的 SSH 私钥，默认路径为 `~/.ssh/id_ed25519`。
3. 设备与客户端计算机连接至同一局域网。
4. 设备在操作期间处于唤醒状态。设备休眠时 SSH 服务不可达，请按电源键唤醒并等待约 30 秒。

关于越狱与 SSH 的配置方法，请参见本文第六节「相关教程」。这部分配置需由用户自行完成，本工具不提供自动化支持。

## 二、安装

在工具所在目录打开 PowerShell，执行：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

安装程序会检查 Python 与 Pillow 环境（Pillow 缺失时自动安装），将运行脚本复制到 `%USERPROFILE%\.kss`，并在 PowerShell 5.1 与 PowerShell 7 的配置文件中注册 `kss` 命令。若设备在线，安装程序会同时将 `kss-agent.sh` 推送至设备的 `/mnt/us/` 目录，并回读 SHA-256 校验值确认内容一致；设备离线时会跳过此步骤，可稍后手动推送。

安装完成后需重新打开 PowerShell 窗口，`kss` 命令方可生效。

## 三、使用方法

### 3.1 命令行入口

在新打开的 PowerShell 窗口中执行：

```
kss                          打开交互菜单
kss add C:\pic.jpg           添加一张图片
kss ls                       列出设备上的屏保图片
kss preview                  生成带编号的预览图
kss rm 5                     删除第 5 张（kss rm "2,5" 可删除多张）
kss set C:\pic.jpg 3         用指定图片替换第 3 张
kss conn                     查看设备状态
kss rollback                 恢复最近一次备份
```

交互菜单提供与上述命令相同的功能，适合不熟悉命令行的用户。执行 `kss` 不带参数即可进入菜单，根据提示输入数字选项，随后按窗口提示操作。添加图片时会弹出文件选择窗口，可通过鼠标选取文件，无需手动输入路径。

### 3.2 批量入口（双击脚本）

工具目录提供以下 Windows 批处理脚本，可直接双击运行，无需打开 PowerShell：

| 脚本 | 用途 |
|---|---|
| `1-一键安装.bat` | 首次安装 |
| `2-打开工具.bat` | 打开交互菜单 |
| `3-拖图片到这里加屏保.bat` | 将图片文件拖放到此脚本图标上即可添加 |
| `4-检查Kindle.bat` | 检查设备连接状态 |
| `5-恢复备份.bat` | 恢复最近一次备份的图片 |

其中 `3-拖图片到这里加屏保.bat` 支持一次拖放多张图片。脚本执行后会提示确认，输入 `y` 并回车表示同意。

### 3.3 尺寸与路线的自动识别

工具会从设备读取屏幕尺寸、设备型号和屏保路线，无需用户手动指定。系统级屏保不会缩放图片，尺寸不匹配时系统不会显示该图片。若自动探测失败，工具会中止操作并提示用户显式指定尺寸，而不会采用默认值继续处理。

```
kss add C:\pic.jpg -Model pw5         按机型代号指定尺寸
kss add C:\pic.jpg -Size 1264x1680    直接指定宽高
kss add C:\pic.jpg -Route B           指定屏保路线
```

机型代号与尺寸对应关系维护在 `kss-devices.ps1`。常见尺寸如下：

| 设备 | 屏幕尺寸 |
|---|---|
| Kindle Basic 4、Paperwhite 3/4、Voyage、Oasis 1 | 1072×1448 |
| Paperwhite 5 | 1236×1648 |
| Paperwhite 6、Oasis 2/3、ColorSoft | 1264×1680 |
| Kindle Scribe | 1860×2480 |
| 早期 6 英寸机型 | 600×800 |

Paperwhite 1/2 与 Oasis 2 的资料存在来源差异，相关条目已在机型表中标注，建议以 `kss conn` 从设备读取的尺寸为准。

### 3.4 屏保路线

工具支持两条屏保部署路线：

- **路线 A**：系统原生 blanket 机制，图片写入 `/var/local/custom_screensavers/`，需要 root 权限。
- **路线 B**：MobileRead ScreenSavers Hack，图片写入 `/mnt/us/screensavers/`，无需修改系统分区，但需设备预先安装相应插件。

`kss conn` 会显示当前检测到的路线。若需手动指定，使用 `-Route A` 或 `-Route B` 参数。

广告版（Special Offers）设备的系统屏保可能覆盖自定义图片，`kss conn` 会给出相应提示；本工具不提供去除广告功能。固件 5.16.3 及更高版本上，旧版 MobileRead 插件可能失效，使用路线 B 前请先确认插件可用。安装了 KOReader 的设备可能同时绘制自绘屏保，与系统屏保出现约 1–2 秒的先后差异，属于正常现象；请勿将 `preventScreenSaver` 设为 1，否则设备可能无法退出屏保状态。

### 3.5 备份与恢复

删除或替换图片前，工具会将原图备份至 `%USERPROFILE%\.kss\backup\<时间戳>\`。执行 `kss rollback` 或双击 `5-恢复备份.bat` 可恢复最近一次备份。

### 3.6 预览模式

添加 `-WhatIf` 参数可仅打印操作计划而不连接设备，例如：

```
kss add C:\pic.jpg -WhatIf
```

## 四、常见问题

| 现象 | 原因 | 处理方式 |
|---|---|---|
| 未找到 Kindle | 设备处于休眠状态，或设备与计算机不在同一网络 | 按电源键唤醒设备并等待 30 秒；确认两侧 Wi-Fi 名称一致；执行 `kss conn` 复查 |
| 安装失败，提示未找到 Python | 系统未安装 Python 或未加入 PATH | 安装 Python 3 并确保其在命令行中可用 |
| 转换失败或找不到文件 | 图片路径不正确 | 使用拖放脚本或文件选择窗口指定图片，避免手动输入路径 |
| 熄屏后无图片显示 | 图片尺寸与设备不匹配 | 执行 `kss conn` 读取设备屏幕尺寸，并以 `-Size` 参数重新转换 |
| 杀毒软件报告风险 | 安全软件对脚本行为链的误报 | 选择允许运行；如无法允许，请咨询设备管理员 |
| 熄屏时出现两张图片先后显示 | 系统屏保与 KOReader 自绘屏保并存 | 属正常现象，无需处理 |

若出现无法理解的错误信息，建议记录完整窗口内容后寻求技术支持。

## 五、名词说明

| 术语 | 说明 |
|---|---|
| SSH | 用于从计算机登录设备的网络协议，是传输图片的前提条件 |
| 越狱 | 解除 Kindle 系统限制的操作，为安装 SSH 和自定义屏保所必需 |
| 私钥 | SSH 身份验证用的密钥文件，通常位于用户目录的 `.ssh` 文件夹 |
| 屏保编号 | 设备上的每张屏保对应一个编号（00、01、02 等），用于删除或替换操作 |
| 路线 A / B | 屏保图片的两种部署位置，工具通常可自动识别 |
| blanket | Kindle 系统中负责管理屏保的模块 |
| ScreenSavers Hack | MobileRead 社区提供的屏保插件，对应路线 B |

## 六、相关教程

以下资源可供参考，用于完成越狱与 SSH 配置。请按设备型号与固件版本选择适用的教程。

以下链接已于 2026-11-28 验证可访问。请按设备型号与固件版本选择适用的教程。

**越狱（必做）**

- [KindleModding 越狱向导](https://kindlemodding.org/jailbreak-wizard.html)：输入设备型号与固件版本后，自动推荐适用的越狱方法。建议从这里开始。
- [WinterBreak 越狱教程](https://kindlemodding.org/jailbreaking/WinterBreak/)：适用于固件 5.16.3 及更高的新型号，含图文分步说明。
- [Legacy 越狱方法合集](https://kindlemodding.org/jailbreaking/Legacy/index.html)：适用于较早型号（Kindle 2/3/4、早期 Paperwhite 等）。

**开启 SSH（必做）**

- [KOReader 内置 SSH 插件](https://github.com/koreader/koreader/tree/master/plugins/SSH.koplugin)：已安装 KOReader 的设备可直接在插件菜单中启动 SSH 服务。
- [KUAL SSH/SFTP 启动器](https://github.com/mzlogin/kual-ssh-sftp-server)：提供中文说明，可在 KUAL 菜单中一键启动或停止 SSH 服务。
- [dropbear-ssh](https://github.com/akshaylahudkar/dropbear-ssh)：独立的 SSH 服务方案，通过 KPM 安装，不依赖 KOReader。

**路线 B 所需的屏保插件（可选）**

- [MobileRead ScreenSavers Hack 安装说明](https://www.mobileread.com/forums/showthread.php?t=195474)：首帖包含安装步骤与适用机型列表（KT、PW、PW2、KT2、KV、PW3、KOA、KT3、KOA2、PW4）。仅在采用路线 B 时需要。

**社区与总入口**

- [KindleModding 主页](https://kindlemodding.org/)：越狱、hotfix、KUAL/MRPI、KOReader 的完整新手路径索引。
- [MobileRead Kindle 论坛](https://www.mobileread.com/forums/forumdisplay.php?f=140)：设备讨论与插件资源入口。技术开发类内容见 [Developer's Corner](https://www.mobileread.com/forums/forumdisplay.php?f=150)。

## 七、项目结构

GUI 部分：`models.py` 维护机型尺寸表，`converter.py` 负责图片转换，`device.py` 负责设备连接与路线检测，`deploy.py` 负责上传与校验，`gui_qt.py` 为图形界面入口；`gui.py.bak-tkinter-20261120` 为旧版备份，已不再使用。

命令行部分：`manage-screensaver.ps1` 为主入口，`kss-device.ps1` 封装设备操作，`kss-common.ps1` 提供公共函数，`kss-devices.ps1` 维护机型数据表，`kss-agent.sh` 在设备端执行敏感操作，`kss-probe.py` 供安装程序探测环境，`kss-contact-sheet.py` 生成编号预览图，`to-kindle-screensaver.py` 负责图片转换。`kss-agent.sh` 需保留在设备的 `/mnt/us/` 目录，不得删除。

## 八、许可

MIT License。本工具仅用于处理用户自有设备，不包含越狱组件，不提供去除广告功能。
