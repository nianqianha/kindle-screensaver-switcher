# -*- coding: utf-8 -*-
"""从 Kindle 拉取所有屏保图，拼成带编号标签的联系表并打开。

用法：
  python kss-contact-sheet.py [--host 192.168.1.222] [--port 2222]
                              [--key ~/.ssh/id_ed25519] [--user root]
输出：%TEMP%/kss-contact-sheet-<时间戳>.png（缩略图按编号排列，标 bg_ssNN）

只做只读拉取 + 本地拼图，不修改设备。

修复 2026-11-28：
  ① ssh/scp 的 subprocess.run 加 timeout（ConnectTimeout 只管建连，连上后假死会无限等）
  ② 拉图临时目录在 finally 里清理（原来每次 preview 都在 %TEMP% 留一组 PNG）
  ③ 修正 docstring 的输出路径描述（原来写固定名，实际是时间戳名）
  ④ 第二轮：文件名改 re.fullmatch('bg_ss\\d{2}\\.png') 严格白名单（原 startswith/endswith
     会把 bg_ss$(id).png 之类拼进 scp 路径）；清理改逐文件 os.unlink，不用 shutil.rmtree
     （PC 端递归强制删除与本工具「不出现危险命令文本」的卡巴规避前提冲突）
"""
import argparse
import os
import re
import subprocess
import tempfile
import time

from PIL import Image, ImageDraw, ImageFont

DIR = "/var/local/custom_screensavers"
LABEL_H = 26
CELL_W, CELL_H = 200, 300
COLS = 4
TIMEOUT = 45  # 单次 ssh/scp 最长等待秒数：连上后设备假死/丢包也能收尾


def _run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        raise RuntimeError("命令超时（%ss），设备可能在睡眠或网络中断: %s" % (TIMEOUT, cmd[0]))


def ssh(args, cmd):
    base = ["ssh", "-p", str(args.port), "-i", os.path.expanduser(args.key),
            "-o", "StrictHostKeyChecking=no", "-o", "LogLevel=Error",
            "-o", "ConnectTimeout=8", "%s@%s" % (args.user, args.host)]
    r = _run(base + [cmd])
    if r.returncode != 0:
        raise RuntimeError("SSH 失败（设备可能在睡眠，按电源键唤醒后重试）: %s" % r.stderr.strip())
    return r.stdout


def scp(args, remote, local):
    src = "%s@%s:%s" % (args.user, args.host, remote)
    r = _run(["scp", "-P", str(args.port), "-i", os.path.expanduser(args.key),
              "-o", "StrictHostKeyChecking=no", "-o", "LogLevel=Error",
              "-o", "ConnectTimeout=8", src, local])
    if r.returncode != 0:
        raise RuntimeError("scp 失败: %s" % r.stderr.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="192.168.1.222")
    ap.add_argument("--port", default="2222")
    ap.add_argument("--user", default="root")
    ap.add_argument("--key", default="~/.ssh/id_ed25519")
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(),
                    "kss-contact-sheet-%d.png" % int(time.time())))
    args = ap.parse_args()

    names = []
    for line in ssh(args, "ls -1 %s/bg_ss*.png 2>/dev/null" % DIR).splitlines():
        n = os.path.basename(line.strip())
        # 严格白名单：只允许 bg_ss00.png ~ bg_ss99.png，杜绝路径注入
        if re.fullmatch(r"bg_ss\d{2}\.png", n):
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
    try:
        for i, name in enumerate(names):
            local = os.path.join(tmpdir, name)
            scp(args, "%s/%s" % (DIR, name), local)
            with Image.open(local) as img:
                im = img.convert("L").convert("RGB")
            im.thumbnail((CELL_W - 12, CELL_H - 12), Image.LANCZOS)
            col, row = i % COLS, i // COLS
            x = col * CELL_W + (CELL_W - im.width) // 2
            y = row * (CELL_H + LABEL_H) + (CELL_H - im.height) // 2
            sheet.paste(im, (x, y))
            d.text((col * CELL_W + 8, row * (CELL_H + LABEL_H) + CELL_H + 4),
                   name, fill="#0f766e", font=font)
        sheet.save(args.out)
    finally:
        # 逐文件删除，不用 shutil.rmtree（PC 端避免递归强制删除的 PDM 特征）
        for name in names:
            try:
                os.unlink(os.path.join(tmpdir, name))
            except OSError:
                pass
        try:
            os.rmdir(tmpdir)
        except OSError:
            pass

    print(args.out)
    os.startfile(args.out)  # 用图片查看器打开


if __name__ == "__main__":
    main()
