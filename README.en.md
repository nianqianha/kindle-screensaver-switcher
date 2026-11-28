# Kindle Screensaver Switcher

This tool sets custom images as the sleep-screen wallpaper of a Kindle device. It converts selected images into the grayscale PNG format required by the device and transfers them over SSH. The new wallpaper appears the next time the device goes to sleep.

A command-line version is provided through PowerShell scripts. Installation is required only once.

> For the Chinese version, see [README.md](README.md).

## 1. Prerequisites

This tool is intended only for Kindle devices that you own and that have been jailbroken. It does not include any jailbreak components, does not remove advertisements, and does not distribute vendor firmware.

Before using the tool, ensure that:

1. The device has been jailbroken and has SSH enabled (port 2222).
2. The client computer has a usable SSH private key; the default path is `~/.ssh/id_ed25519`.
3. The device and the computer are on the same local network.
4. The device is awake during the operation. A sleeping device is unreachable over SSH; press the power button and wait about 30 seconds.

Jailbreaking and SSH configuration must be performed by the user. This tool does not automate that step. See section 6, "Further Reading", for tutorials.

## 2. Installation

Open PowerShell in the tool directory and run:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

The installer checks the Python and Pillow environment (installing Pillow automatically if missing), copies the runtime scripts to `%USERPROFILE%\.kss`, and registers the `kss` command in the PowerShell 5.1 and PowerShell 7 profiles. If the device is online, the installer also pushes `kss-agent.sh` to `/mnt/us/` on the device and verifies it by reading back its SHA-256 checksum; if the device is offline, this step is skipped and can be performed manually later.

Open a new PowerShell window after installation for the `kss` command to take effect.

## 3. Usage

### 3.1 Command-line interface

In a newly opened PowerShell window:

```
kss                          open the interactive menu
kss add C:\pic.jpg           add one image
kss ls                       list wallpaper images on the device
kss preview                  generate a numbered preview sheet
kss rm 5                     remove image 5 (kss rm "2,5" removes several)
kss set C:\pic.jpg 3         replace image 3 with the given file
kss conn                     show device status
kss rollback                 restore the most recent backup
```

The interactive menu provides the same functions and is intended for users unfamiliar with the command line. Run `kss` without arguments to enter the menu, then follow the numbered prompts. When adding images, a file-selection dialog appears so that files can be picked with the mouse; typing a path is not required.

### 3.2 Double-click batch scripts

The tool directory contains Windows batch scripts that can be run by double-clicking, without opening PowerShell:

| Script | Purpose |
|---|---|
| `1-一键安装.bat` | First-time installation |
| `2-打开工具.bat` | Open the interactive menu |
| `3-拖图片到这里加屏保.bat` | Drag image files onto this icon to add them |
| `4-检查Kindle.bat` | Check device connectivity |
| `5-恢复备份.bat` | Restore the most recent backup |
| `6-选图裁剪.bat` | Open the image cropper to select a region from a local image and export a screensaver image |

`3-拖图片到这里加屏保.bat` accepts multiple files in one drag-and-drop operation. After a script starts, it asks for confirmation; type `y` and press Enter to proceed.

### 3.2.1 Image cropping tool

`kss-crop.html` is an installation-free, single-file tool that runs in the browser. It selects a region from a larger image and exports it at the exact size required by the target device. Double-click `6-选图裁剪.bat` to open it.

Usage:

1. Click "选择图片" in the page to pick a local image, or drag an image file onto that area.
2. Select the target device from the model drop-down; the selection rectangle is locked to that device's screen aspect ratio.
3. Drag the cyan rectangle over the image (corner handles resize, dragging inside moves it). The right pane previews the grayscale result in real time.
4. Set the starting index and number of copies, then click "导出 PNG". Files are named `bg_ssNN.png` and saved to the browser's download directory.
5. Add the generated images to the device using `3-拖图片到这里加屏保.bat`.

The supported model sizes match `kss-devices.ps1`. The system screensaver does not scale images, so the selection ratio must match the target device. Sources disagree on Paperwhite 1/2 and Oasis 2; the tool displays a note for these models, and the size reported by `kss conn` should be used as the authoritative value.

### 3.3 Automatic detection of size and route

The tool reads the screen size, device model, and screensaver route from the device; manual configuration is normally unnecessary. The system screensaver does not scale images, so an image with a mismatched size will not be displayed. If automatic detection fails, the tool aborts and asks for an explicit size rather than continuing with a default value.

```
kss add C:\pic.jpg -Model pw5         specify size by model code
kss add C:\pic.jpg -Size 1264x1680    specify width and height
kss add C:\pic.jpg -Route B           specify the screensaver route
```

Model codes and their sizes are maintained in `kss-devices.ps1`. Common sizes:

| Device | Screen size |
|---|---|
| Kindle Basic 4, Paperwhite 3/4, Voyage, Oasis 1 | 1072×1448 |
| Paperwhite 5 | 1236×1648 |
| Paperwhite 6, Oasis 2/3, ColorSoft | 1264×1680 |
| Kindle Scribe | 1860×2480 |
| Earlier 6-inch models | 600×800 |

Sources disagree on Paperwhite 1/2 and Oasis 2; the corresponding entries are marked as uncertain in the device table. Use the size reported by `kss conn` as the authoritative value.

### 3.4 Screensaver routes

Two deployment routes are supported:

- **Route A**: the native blanket mechanism. Images are written to `/var/local/custom_screensavers/` and root access is required.
- **Route B**: the MobileRead ScreenSavers Hack. Images are written to `/mnt/us/screensavers/`. No system-partition modification is required, but the plugin must be installed on the device in advance.

`kss conn` reports the detected route. To override it, use `-Route A` or `-Route B`.

On devices with Special Offers, the system may overwrite custom images; `kss conn` will display a warning. This tool does not remove advertisements. On firmware 5.16.3 and later, older versions of the MobileRead hack may no longer work; verify the plugin before using route B. Devices with KOReader may draw their own screensaver, causing a 1–2 second overlap with the system screensaver; this is expected behavior. Do not set `preventScreenSaver` to 1, as the device may then fail to exit the screensaver state.

### 3.5 Backup and restore

Before deleting or replacing an image, the tool backs up the original to `%USERPROFILE%\.kss\backup\<timestamp>\`. Run `kss rollback` or double-click `5-恢复备份.bat` to restore the most recent backup.

### 3.6 Dry run

Add `-WhatIf` to print the planned operations without connecting to the device:

```
kss add C:\pic.jpg -WhatIf
```

## 4. Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| Kindle not found | Device asleep, or device and computer on different networks | Wake the device and wait 30 seconds; confirm both use the same Wi-Fi network; recheck with `kss conn` |
| Installation fails with "Python not found" | Python not installed or not on PATH | Install Python 3 and ensure it is available from the command line |
| Conversion fails or file not found | Incorrect image path | Use the drag-and-drop script or the file-selection dialog instead of typing a path |
| No image shown on sleep | Image size does not match the device | Read the size with `kss conn` and convert again using `-Size` |
| Antivirus reports a threat | False positive from the security suite behavior detector | Allow the script to run; consult your administrator if this is not possible |
| Two images appear in sequence on sleep | System screensaver and KOReader screensaver both active | Expected behavior; no action required |

If an error message is unclear, record the complete window content when seeking technical support.

## 5. Glossary

| Term | Meaning |
|---|---|
| SSH | Network protocol used to log in to the device; required for transferring images |
| Jailbreak | Process of removing Kindle system restrictions; required for SSH and custom screensavers |
| Private key | SSH authentication key file, usually located in the `.ssh` folder of the user profile |
| Screensaver index | Each image on the device has an index (00, 01, 02, ...) used for removal or replacement |
| Route A / B | Two locations for deploying screensaver images; normally detected automatically |
| blanket | The Kindle system module that manages screensavers |
| ScreenSavers Hack | MobileRead plugin that enables custom screensavers; corresponds to route B |

## 6. Further Reading

The following resources may be used to complete the jailbreak and SSH configuration. Choose the tutorial matching your device model and firmware version.

The following links were verified as accessible on 2026-11-28. Choose the tutorial matching your device model and firmware version.

**Jailbreak (required)**

- [KindleModding Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html): enter the device model and firmware version to obtain a recommended jailbreak method. Start here.
- [WinterBreak tutorial](https://kindlemodding.org/jailbreaking/WinterBreak/): for newer devices on firmware 5.16.3 and later, with step-by-step instructions.
- [Legacy jailbreak methods](https://kindlemodding.org/jailbreaking/Legacy/index.html): for older devices such as Kindle 2/3/4 and early Paperwhite models.

**Enabling SSH (required)**

- [KOReader built-in SSH plugin](https://github.com/koreader/koreader/tree/master/plugins/SSH.koplugin): devices with KOReader installed can start the SSH service directly from the plugin menu.
- [KUAL SSH/SFTP launcher](https://github.com/mzlogin/kual-ssh-sftp-server): provides a one-click start/stop entry in the KUAL menu, with Chinese documentation.
- [dropbear-ssh](https://github.com/akshaylahudkar/dropbear-ssh): a standalone SSH service installed via KPM, without a KOReader dependency.

**Screensaver plugin for route B (optional)**

- [MobileRead ScreenSavers Hack](https://www.mobileread.com/forums/showthread.php?t=195474): installation steps and a list of supported devices (KT, PW, PW2, KT2, KV, PW3, KOA, KT3, KOA2, PW4). Required only for route B.

**Community and general resources**

- [KindleModding](https://kindlemodding.org/): an index covering jailbreak, hotfix, KUAL/MRPI, and KOReader.
- [MobileRead Kindle forum](https://www.mobileread.com/forums/forumdisplay.php?f=140): device discussions and plugin resources. Development topics are in the [Developer's Corner](https://www.mobileread.com/forums/forumdisplay.php?f=150).

## 7. Project Structure

GUI components: `models.py` maintains the device-size table, `converter.py` handles image conversion, `device.py` manages connections and route detection, `deploy.py` handles upload and verification, and `gui_qt.py` is the GUI entry point. `gui.py.bak-tkinter-20261120` is an obsolete backup.

Command-line components: `manage-screensaver.ps1` is the main entry point, `kss-device.ps1` wraps device operations, `kss-common.ps1` provides shared functions, `kss-devices.ps1` maintains the device table, `kss-agent.sh` performs sensitive operations on the device, `kss-probe.py` is used by the installer to inspect the environment, `kss-contact-sheet.py` generates the numbered preview, and `to-kindle-screensaver.py` converts images. `kss-agent.sh` must remain in `/mnt/us/` on the device and must not be deleted. The cropping tool `kss-crop.html` is a standalone single-file page opened through `6-选图裁剪.bat`.

## 8. License

MIT License. This tool is intended solely for devices you own. It contains no jailbreak components and does not remove advertisements.
