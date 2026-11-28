# -*- coding: utf-8 -*-
"""安装器专用探测脚本：检查 Python 版本 + Pillow 是否可用。

为什么要独立文件而不是 python -c：
  转换脚本特意做成独立文件就是为了「避免被安全软件判为动态代码执行」
  （见 to-kindle-screensaver.py 注释）。卡巴斯基 PDM 是进程行为链检测，
  install.ps1 里内联 python -c + ssh + scp 的组合曾被判 PDM:Trojan.Win32.Generic
  并删脚本（2026-11-20 实测）。用独立脚本探测，PC 端不再出现动态代码特征。

输出约定（PowerShell 侧按退出码判断，不解析 stderr）：
  - 无参数：打印 Python 版本到 stdout，exit 0
  - --pillow：Pillow 可用则打印版本到 stdout exit 0；不可用 exit 3
"""
import sys


def main():
    args = sys.argv[1:]
    if "--pillow" in args:
        try:
            import PIL
            print(getattr(PIL, "__version__", "unknown"))
            return 0
        except Exception:
            return 3
    print(sys.version.split()[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
