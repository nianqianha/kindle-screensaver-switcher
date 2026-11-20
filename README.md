# kindle-screensaver-switcher

一行命令安装、一行命令使用的 Kindle 熄屏封面管理工具。

## 它做什么

- 把图片转成 Kindle 熄屏封面（自动读取设备屏幕尺寸，兼容不同机型）
- 推送到 Kindle 的 `/var/local/custom_screensavers/bg_ssNN.png`
- 看图认编号、加图、删图、替换指定编号

**不越狱、不改系统模块、不禁用广告**。它只在你自己已越狱、已开启 SSH 的 Kindle 上读写屏保图片。

## 前提（由你自己准备）

- Kindle 已越狱（系统分区 `/var/local` 可写）
- Kindle 上 SSH 已开启（端口 2222），密钥认证已配好
- Kindle 和电脑在同一网络，设备已唤醒

本工具**不负责**开 SSH——这是你自己的事。连不上时只会提示确认以上三点。

## 安装（一次）

Windows PowerShell 里运行一行：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

安装器会：检查 Python + Pillow → 复制脚本到 `%USERPROFILE%\.kss` → 配置 `kss` 命令（新建 PowerShell 窗口生效）→ 设备在线则推送设备端 agent（离线可跳过，以后补推）。

默认私钥路径 `~/.ssh/id_ed25519`，设备 IP 未指定时自动探测同网段。可用参数覆盖：

```powershell
.\install.ps1 -KeyPath C:\path\to\key -HostIP 192.168.x.x -SkipDevice
```

## 使用（随时）

新开 PowerShell 窗口：

```
kss                    交互菜单
kss preview            看图认编号（打开带编号的联系表）
kss ls                 列出当前屏保图
kss add <图片路径>      加图（自动用空闲编号）
kss rm N               删第 N 张（多张：kss rm "2,5"）
kss set <图片路径> N    用某图替换第 N 张（先看样例）
kss conn               检查连接
```

## 为什么这样设计

- **设备端 agent（`kss-agent.sh`）**：所有 `rm`/`mntroot`/`sha256sum` 都在 Kindle 上执行，PC 端只发 `sh /mnt/us/kss-agent.sh <op> N`。这样 Windows 上的安全软件看不到危险命令，避免行为检测误报。
- **自动认机型**：设备端读系统原生屏保 PNG 头拿到屏幕尺寸，转换时按该尺寸输出，不写死分辨率。
- **连接信息记忆**：成功连接的 IP 缓存到临时目录，下次自动用。

## 文件

| 文件 | 作用 |
|---|---|
| `install.ps1` | 一行命令安装器 |
| `manage-screensaver.ps1` | 主入口（菜单 + 位置参数子命令） |
| `kss-device.ps1` | PC 端薄封装：向设备发 agent 命令 |
| `kss-agent.sh` | 设备端 agent（放 Kindle 的 `/mnt/us/`） |
| `kss-contact-sheet.py` | 拉图生成带编号的预览联系表 |
| `to-kindle-screensaver.py` | 图片转 Kindle 格式（尺寸自适应） |

## 许可

MIT。
