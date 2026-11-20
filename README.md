# kindle-screensaver-switcher

给 Kindle 换熄屏封面的小工具。装一次，以后在 PowerShell 里敲一行 `kss` 就能加图、删图、替换。

## 用之前

Kindle 得已经越狱、开着 SSH（2222），并且和电脑在同一网络。怎么开 SSH 你自己弄，这个工具不管——连不上时它只会提醒你确认这几件事。

需要 Python 和 Pillow，安装脚本会检查，缺 Pillow 会自己装。

## 装

在 PowerShell 里跑一行：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

它把脚本装到 `%USERPROFILE%\.kss`，给 PowerShell 加个 `kss` 命令，设备在线的话顺便把 `kss-agent.sh` 放到 Kindle 的 `/mnt/us/`。设备没开就跳过，以后手动推一次就行。

私钥默认找 `~/.ssh/id_ed25519`，设备 IP 自动探测。都不一样就传参数：

```powershell
.\install.ps1 -KeyPath C:\path\to\key -HostIP 192.168.x.x -SkipDevice
```

## 用

新开一个 PowerShell 窗口：

```
kss                    菜单
kss preview            看看几号是哪张图
kss ls                 列出
kss add C:\pic.jpg     加一张
kss rm 5               删第 5 张（kss rm "2,5" 删多张）
kss set C:\pic.jpg 3   用 pic.jpg 换掉第 3 张
kss conn               测连接
```

图会被转成设备屏幕的尺寸（工具自己从设备读，不用你管机型），存成 `bg_ssNN.png` 放进 `/var/local/custom_screensavers/`。下次熄屏生效。

## 两个实现细节

删文件、切分区这些动作放在 Kindle 上跑（`kss-agent.sh`），电脑上只发一句命令。不是为了别的，是 Windows 杀软看到一整串操作容易误报。

`kss-agent.sh` 放在 Kindle 的 `/mnt/us/`，别删——每次操作都要用。

## 许可

MIT
