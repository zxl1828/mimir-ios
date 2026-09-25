"""生成 Mimir 的 App 图标（吉祥物「米米」：智慧之井里的小鲸）。

用法：
    python tools/icon/generate_icon.py

产物写入 Mimir/Resources/Assets.xcassets/AppIcon.appiconset/：
    icon-light.png / icon-dark.png / icon-tinted.png（均为 1024×1024、无 alpha）
脚本本身可复现：改颜色或形状后重跑即可，无需设计稿。
"""
from __future__ import annotations

import pathlib
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # 超采样倍数：4 倍绘制再缩小，边缘干净
U = SIZE * SS
OUT = (
    pathlib.Path(__file__).resolve().parents[2]
    / "Mimir"
    / "Resources"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def gradient(size, c0, c1):
    """左上 → 右下的线性渐变（先算小图再放大，够用且快）。"""
    n = 256
    small = Image.new("RGB", (n, n))
    px = small.load()
    for y in range(n):
        for x in range(n):
            px[x, y] = lerp(c0, c1, (x + y) / (2 * (n - 1)))
    return small.resize((size, size), Image.BICUBIC)


def star(draw, cx, cy, r, color, thin=0.30):
    """四角星（闪光）。"""
    w = r * thin
    draw.polygon(
        [
            (cx, cy - r),
            (cx + w, cy - w),
            (cx + r, cy),
            (cx + w, cy + w),
            (cx, cy + r),
            (cx - w, cy + w),
            (cx - r, cy),
            (cx - w, cy - w),
        ],
        fill=color,
    )


def whale_layer(s: int, body, shade, belly, ink, spark, blush, gloss, eye=True):
    """在透明层上画鲸鱼（一个设计单位 = 1024）。"""
    layer = Image.new("RGBA", (U, U), (0, 0, 0, 0))

    def box(b):
        return [b[0] * s, b[1] * s, b[2] * s, b[3] * s]

    def poly(points):
        return [(x * s, y * s) for x, y in points]

    head = (505, 398, 820, 700)     # 头部大圆
    bridge = (430, 434, 700, 688)   # 背线过渡，避免两圆相交处出现凹口
    rear = (312, 442, 690, 684)     # 后身，形成向尾部收窄的豆形
    flukes = [(338, 556), (188, 446), (252, 552), (188, 660), (342, 594)]
    dorsal = [(478, 472), (546, 350), (596, 472)]
    pectoral = (664, 644, 776, 726)

    d = ImageDraw.Draw(layer, "RGBA")
    # 鳍（在身体之下，只露出尖端）
    d.polygon(poly(flukes), fill=shade)
    d.polygon(poly(dorsal), fill=shade)
    d.ellipse(box(pectoral), fill=shade)

    # 身体剪影
    sil = Image.new("RGBA", (U, U), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sil, "RGBA")
    for shape in (head, bridge, rear, (322, 498, 452, 642)):  # 身体 + 尾根
        sd.ellipse(box(shape), fill=body)
    layer.alpha_composite(sil)

    # 身体内部细节：腹部 + 背部高光（用剪影遮罩裁掉溢出）
    det = Image.new("RGBA", (U, U), (0, 0, 0, 0))
    dd = ImageDraw.Draw(det, "RGBA")
    dd.ellipse(box((400, 588, 812, 712)), fill=belly)
    dd.arc(box((330, 330, 780, 690)), 188, 276, fill=gloss, width=int(20 * s))
    det.putalpha(ImageChops.multiply(det.getchannel("A"), sil.getchannel("A")))
    layer.alpha_composite(det)

    if eye:
        d.ellipse(box((654, 470, 718, 534)), fill=ink)          # 眼
        d.ellipse(box((668, 482, 690, 504)), fill=(255, 255, 255, 240))
        d.ellipse(box((702, 516, 714, 528)), fill=(255, 255, 255, 190))
        d.ellipse(box((726, 560, 792, 594)), fill=blush)        # 腮红
        d.arc(box((668, 552, 744, 620)), 25, 105, fill=ink, width=int(9 * s))  # 微笑
    else:
        # tinted：把眼睛挖空，系统着色时才看得出来
        alpha = layer.getchannel("A")
        ImageDraw.Draw(alpha).ellipse(box((654, 470, 718, 534)), fill=0)
        layer.putalpha(alpha)

    # 喷水：闪光 + 水滴
    star(d, 660 * s, 300 * s, 46 * s, spark)
    star(d, 736 * s, 244 * s, 20 * s, spark)
    d.ellipse([600 * s, 326 * s, 630 * s, 356 * s], fill=spark)
    d.ellipse([712 * s, 318 * s, 734 * s, 340 * s], fill=spark)
    return layer


def draw_icon(kind: str) -> Image.Image:
    s = SS
    if kind == "tinted":
        img = Image.new("RGBA", (U, U), (0, 0, 0, 0))
        ring_color, fill_color = (255, 255, 255, 96), (255, 255, 255, 0)
        body, shade = (255, 255, 255, 255), (255, 255, 255, 200)
        belly = gloss = blush = ink = (255, 255, 255, 0)
        spark = (255, 255, 255, 235)
    elif kind == "dark":
        img = gradient(U, (24, 16, 48), (78, 50, 158)).convert("RGBA")
        ring_color, fill_color = (255, 255, 255, 130), (255, 255, 255, 20)
        body, shade = (243, 238, 255, 255), (206, 192, 248, 255)
        belly = (255, 255, 255, 150)
        gloss = (255, 255, 255, 120)
        ink, spark = (32, 22, 62, 255), (226, 214, 255, 255)
        blush = (255, 150, 192, 110)
    else:
        img = gradient(U, (150, 92, 255), (92, 52, 214)).convert("RGBA")
        ring_color, fill_color = (255, 255, 255, 135), (255, 255, 255, 24)
        body, shade = (255, 255, 255, 255), (216, 204, 255, 255)
        belly = (228, 219, 255, 210)
        gloss = (255, 255, 255, 120)
        ink, spark = (34, 24, 66, 255), (255, 255, 255, 235)
        blush = (255, 152, 196, 120)

    if kind != "tinted":
        # 顶部柔光
        glow = Image.new("RGBA", (U, U), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse(
            [280 * s, 40 * s, 1200 * s, 880 * s], fill=(255, 255, 255, 44)
        )
        img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(int(110 * s))))

    # 智慧之井：玻璃圆环 + 井底阴影
    ring = Image.new("RGBA", (U, U), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring, "RGBA")
    rd.ellipse([152 * s, 208 * s, 872 * s, 912 * s], fill=fill_color)
    rd.ellipse([152 * s, 208 * s, 872 * s, 912 * s], outline=ring_color, width=int(11 * s))
    rd.arc([152 * s, 208 * s, 872 * s, 912 * s], 200, 320,
           fill=(255, 255, 255, 200), width=int(6 * s))
    img.alpha_composite(ring.filter(ImageFilter.GaussianBlur(int(2 * s))))

    if kind != "tinted":
        shade_layer = Image.new("RGBA", (U, U), (0, 0, 0, 0))
        ImageDraw.Draw(shade_layer).ellipse(
            [210 * s, 300 * s, 830 * s, 900 * s], fill=(30, 18, 68, 70)
        )
        img.alpha_composite(shade_layer.filter(ImageFilter.GaussianBlur(int(46 * s))))

    img.alpha_composite(
        whale_layer(s, body, shade, belly, ink, spark, blush, gloss, eye=kind != "tinted")
    )
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for kind in ("light", "dark", "tinted"):
        img = draw_icon(kind)
        if kind == "tinted":
            img = img.convert("RGBA")  # 保留透明通道：系统会着色
        else:
            img = img.convert("RGB")  # iOS 图标禁止 alpha
        path = OUT / f"icon-{kind}.png"
        img.save(path)
        print(f"wrote {path} ({path.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
