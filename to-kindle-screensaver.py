# -*- coding: utf-8 -*-
"""把一张图转成 Kindle 熄屏封面（灰度 PNG，尺寸由设备自动探测决定）。

用法：
  python to-kindle-screensaver.py <输入图> <输出.png> [宽x高]
  例： ... <src> <out> 1072x1448

尺寸传第三个参数（从设备 kss-agent.sh detect 拿到），不传则默认 1072x1448。
只用 Pillow。独立文件而非 python -c 内联代码——避免被安全软件判为动态代码执行。

修复 2026-11-28：
  ① 尺寸校验宽高为正数（原来 0x0/负数直接抛 Pillow 底层异常，提示不友好）
  ② split("x", 1) 限制分段；Image.open 用 with 上下文释放句柄（批量转换不累积）
  ③ 第二轮：尺寸加上限 64-4096（防 999999x999999 撑爆内存），并对齐已知 Kindle 机型表；
     非白名单尺寸可用但会给提示（用户自定义尺寸仍放行）
"""
import sys

from PIL import Image, ImageEnhance, ImageFilter, ImageOps

DEFAULT = (1072, 1448)
MIN_DIM, MAX_DIM = 64, 4096
# 已知 Kindle 屏保尺寸白名单（来自 kss-devices.ps1 / models.py，2026-11-28 核查）
KNOWN_SIZES = {(600, 800), (824, 1200), (768, 1024), (1072, 1448),
               (1236, 1648), (1264, 1680), (1860, 2480)}


def convert(src, out, size=DEFAULT):
    W, H = size
    if not (MIN_DIM <= W <= MAX_DIM and MIN_DIM <= H <= MAX_DIM):
        raise ValueError("尺寸宽高须在 %d-%d 之间：%sx%s" % (MIN_DIM, MAX_DIM, W, H))
    if (W, H) not in KNOWN_SIZES:
        print("提示：%sx%s 不在已知 Kindle 机型尺寸表，请确认设备确实用此尺寸。" % (W, H),
              file=sys.stderr)
    with Image.open(src) as img:
        im = ImageOps.exif_transpose(img).convert("RGB")
    # 完整保留 + 同图模糊填充（不裁人物，本机实际部署用法）
    bg = ImageOps.fit(im, (W, H), Image.LANCZOS).filter(
        ImageFilter.GaussianBlur(max(W, H) // 30))
    bg = ImageEnhance.Brightness(bg).enhance(0.82)
    fg = im.copy()
    fg.thumbnail((W, H), Image.LANCZOS)
    bg.paste(fg, ((W - fg.width) // 2, (H - fg.height) // 2))
    bg.convert("L").save(out, "PNG", optimize=True)


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        print("usage: to-kindle-screensaver.py <src> <out.png> [WxH]", file=sys.stderr)
        raise SystemExit(1)
    size = DEFAULT
    if len(sys.argv) == 4:
        try:
            parts = sys.argv[3].lower().split("x", 1)
            if len(parts) != 2:
                raise ValueError
            w, h = int(parts[0]), int(parts[1])
            if not (MIN_DIM <= w <= MAX_DIM and MIN_DIM <= h <= MAX_DIM):
                raise ValueError
            size = (w, h)
        except ValueError:
            print("尺寸格式应为 宽x高，各在 %d-%d 之间，例如 1072x1448" % (MIN_DIM, MAX_DIM), file=sys.stderr)
            raise SystemExit(1)
    convert(sys.argv[1], sys.argv[2], size)
