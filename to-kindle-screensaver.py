# -*- coding: utf-8 -*-
"""把一张图转成 Kindle 熄屏封面（灰度 PNG，尺寸由设备自动探测决定）。

用法：
  python to-kindle-screensaver.py <输入图> <输出.png> [宽x高]
  例： ... <src> <out> 1072x1448

尺寸传第三个参数（从设备 kss-agent.sh detect 拿到），不传则默认 1072x1448。
只用 Pillow。独立文件而非 python -c 内联代码——避免被安全软件判为动态代码执行。
"""
import sys

from PIL import Image, ImageEnhance, ImageFilter, ImageOps

DEFAULT = (1072, 1448)


def convert(src, out, size=DEFAULT):
    W, H = size
    im = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
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
            w, h = sys.argv[3].lower().split("x")
            size = (int(w), int(h))
        except ValueError:
            print("尺寸格式应为 宽x高，例如 1072x1448", file=sys.stderr)
            raise SystemExit(1)
    convert(sys.argv[1], sys.argv[2], size)
