# -*- coding: utf-8 -*-
"""从 Kindle 拉取所有屏保图，拼成带编号标签的联系表并打开。

用法：
  python kss-contact-sheet.py [--host 192.168.1.222] [--port 2222]
                              [--key ~/.ssh/id_ed25519] [--user root]
输出：%TEMP%/kss-contact-sheet.png（缩略图按编号排列，标 bg_ssNN）

只做只读拉取 + 本地拼图，不修改设备。
"""
import argparse
import os
import subprocess
import tempfile
import time

from PIL import Image, ImageDraw, ImageFont

DIR = "/var/local/custom_screensavers"
LABEL_H = 26
CELL_W, CELL_H = 200, 300
COLS = 4


def ssh(args, cmd):
    base = ["ssh", "-p", str(args.port), "-i", os.path.expanduser(args.key),
            "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=8",
            "%s@%s" % (args.user, args.host)]
    r = subprocess.run(base + [cmd], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("SSH 失败（设备可能在睡眠，按电源键唤醒后重试）: %s" % r.stderr.strip())
    return r.stdout


def scp(args, remote, local):
    src = "%s@%s:%s" % (args.user, args.host, remote)
    r = subprocess.run(["scp", "-P", str(args.port), "-i", os.path.expanduser(args.key),
                        "-o", "StrictHostKeyChecking=no", src, local],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("scp 失败: %s" % r.stderr.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="192.168.1.222")
    ap.add_argument("--port", default="2222")
    ap.add_argument("--user", default="root")
    ap.add_argument("--key", default="~/.ssh/id_ed25519")
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "kss-contact-sheet-%d.png" % int(time.time())))
    args = ap.parse_args()

    names = []
    for line in ssh(args, "ls -1 %s/bg_ss*.png 2>/dev/null" % DIR).splitlines():
        n = os.path.basename(line.strip())
        if n.startswith("bg_ss") and n.endswith(".png"):
            names.append(n)
    if not names:
        print("设备上没有屏保图")
        return

    rows = (len(names) + COLS - 1) // COLS
    sheet = Image.new("RGB", (COLS * CELL_W, rows * (CELL_H + LABEL_H)), "#f1f5f4")
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("msyh.ttc", 15)
    except Exception:
        font = ImageFont.load_default()

    tmpdir = tempfile.mkdtemp(prefix="kss-sheet-")
    for i, name in enumerate(names):
        local = os.path.join(tmpdir, name)
        scp(args, "%s/%s" % (DIR, name), local)
        im = Image.open(local).convert("L").convert("RGB")
        im.thumbnail((CELL_W - 12, CELL_H - 12), Image.LANCZOS)
        col, row = i % COLS, i // COLS
        x = col * CELL_W + (CELL_W - im.width) // 2
        y = row * (CELL_H + LABEL_H) + (CELL_H - im.height) // 2
        sheet.paste(im, (x, y))
        d.text((col * CELL_W + 8, row * (CELL_H + LABEL_H) + CELL_H + 4),
               name, fill="#0f766e", font=font)

    sheet.save(args.out)
    print(args.out)
    os.startfile(args.out)  # 用图片查看器打开


if __name__ == "__main__":
    main()
