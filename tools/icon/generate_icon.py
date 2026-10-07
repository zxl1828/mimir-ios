"""生成 Mimir 的 App 图标与品牌图（全息玻璃球里的赛博猫头鹰 Cyber-Owl）。

用法：
    python tools/icon/generate_icon.py

产物写入：
    1. Mimir/Resources/Assets.xcassets/AppIcon.appiconset/
       - icon-light.png (1024×1024, RGB, 无 alpha)
       - icon-dark.png  (1024×1024, RGB, 无 alpha)
       - icon-tinted.png (1024×1024, RGBA, 供系统着色)
    2. docs/brand/
       - icon.png / icon-dark.png / mascot.png
"""
from __future__ import annotations

import math
import pathlib
from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SS = 2  # 2x 超采样绘制后缩回 1024，兼顾边缘抗锯齿与生成速度
U = SIZE * SS

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Mimir" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
BRAND_OUT = ROOT / "docs" / "brand"


def lerp(a: tuple[int, ...], b: tuple[int, ...], t: float) -> tuple[int, ...]:
    t = max(0.0, min(1.0, t))
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def radial_Wait_gradient(size: int, c_center: tuple[int, int, int], c_mid: tuple[int, int, int], c_edge: tuple[int, int, int]) -> Image.Image:
    """生成带中心柔光的径向+对角混合背景（先在 256×256 计算再放大）。"""
    n = 256
    small = Image.new("RGB", (n, n))
    px = small.load()
    cx, cy = n * 0.5, n * 0.46
    max_r = n * 0.72
    for y in range(n):
        for x in range(n):
            dist = math.hypot(x - cx, y - cy) / max_r
            diag = (x + y) / (2.0 * (n - 1))
            t = min(1.0, dist * 0.75 + diag * 0.25)
            if t < 0.5:
                px[x, y] = lerp(c_center, c_mid, t * 2.0)
            else:
                px[x, y] = lerp(c_mid, c_edge, (t - 0.5) * 2.0)
    return small.resize((size, size), Image.BICUBIC)


def draw_rotated_orbit(
    target: Image.Image,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    angle_deg: float,
    color: tuple[int, int, int, int],
    width: int,
    front_only: bool | None = None,
    dots: list[float] | None = None,
    dot_color: tuple[int, int, int, int] = (255, 255, 255, 255),
    glow_color: tuple[int, int, int, int] | None = None,
) -> None:
    """绘制倾斜椭圆轨道环（支持只画前半环或后半环，实现穿插球体的立体层次）。"""
    layer = Image.new("RGBA", target.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer, "RGBA")
    rad = math.radians(angle_deg)
    cos_a, sin_a = math.cos(rad), math.sin(rad)

    steps = 360
    if front_only is None:
        ranges = [(0, steps)]
    elif front_only:
        # 前半环：sin(t) >= 0 即 0..180 度
        ranges = [(0, 180)]
    else:
        # 后半环：180..360 度
        ranges = [(180, 360)]

    for start_deg, end_deg in ranges:
        pts = []
        for step in range(start_deg, end_deg + 1):
            t = math.radians(step)
            ex = rx * math.cos(t)
            ey = ry * math.sin(t)
            px = cx + ex * cos_a - ey * sin_a
            py = cy + ex * sin_a + ey * cos_a
            pts.append((px, py))
        if len(pts) >= 2:
            d.line(pts, fill=color, width=width, joint="curve")

    if glow_color is not None:
        blurred = layer.filter(ImageFilter.GaussianBlur(max(2, width * 2)))
        target.alpha_composite(blurred)
    target.alpha_composite(layer)

    if dots:
        dot_layer = Image.new("RGBA", target.size, (0, 0, 0, 0))
        dd = ImageDraw.Draw(dot_layer, "RGBA")
        for deg in dots:
            in_front = 0 <= (deg % 360) <= 180
            if front_only is not None and in_front != front_only:
                continue
            t = math.radians(deg)
            ex = rx * math.cos(t)
            ey = ry * math.sin(t)
            px = cx + ex * cos_a - ey * sin_a
            py = cy + ex * sin_a + ey * cos_a
            r = width * 2.1
            if glow_color is not None:
                dd.ellipse([px - r * 2.4, py - r * 2.4, px + r * 2.4, py + r * 2.4], fill=glow_color)
            dd.ellipse([px - r, py - r, px + r, py + r], fill=dot_color)
        if glow_color is not None:
            target.alpha_composite(dot_layer.filter(ImageFilter.GaussianBlur(int(width * 1.4))))
        target.alpha_composite(dot_layer)


def draw_cyber_owl(s: int, kind: str) -> Image.Image:
    """绘制赛博猫头鹰图层（与参考图 1 & 2 的全息紫色猫头鹰严格对齐）。"""
    layer = Image.new("RGBA", (U, U), (0, 0, 0, 0))

    def pt(x: float, y: float) -> tuple[float, float]:
        return (x * s, y * s)

    def box(x0: float, y0: float, x1: float, y1: float) -> list[float]:
        return [x0 * s, y0 * s, x1 * s, y1 * s]

    def poly(pts: list[tuple[float, float]]) -> list[tuple[float, float]]:
        return [(x * s, y * s) for x, y in pts]

    if kind == "tinted":
        body_top = (255, 255, 255, 245)
        body_bot = (255, 255, 255, 200)
        wing_fill = (255, 255, 255, 225)
        wing_edge = (255, 255, 255, 255)
        ear_fill = (255, 255, 255, 250)
        brow_fill = (255, 255, 255, 255)
        eye_ring = (255, 255, 255, 255)
        eye_glow = (255, 255, 255, 160)
        pupil_color = (0, 0, 0, 0)
        beak_color = (255, 255, 255, 255)
        feather_color = (0, 0, 0, 0)
        claw_color = (255, 255, 255, 230)
    elif kind == "light":
        body_top = (128, 78, 248, 255)
        body_bot = (66, 32, 165, 255)
        wing_fill = (96, 52, 212, 255)
        wing_edge = (212, 180, 255, 235)
        ear_fill = (146, 96, 255, 255)
        brow_fill = (196, 156, 255, 245)
        eye_ring = (218, 182, 255, 255)
        eye_glow = (178, 112, 255, 220)
        pupil_color = (26, 12, 64, 255)
        beak_color = (238, 216, 255, 255)
        feather_color = (216, 184, 255, 225)
        claw_color = (168, 122, 255, 255)
    else:
        body_top = (118, 64, 242, 255)
        body_bot = (48, 20, 128, 255)
        wing_fill = (78, 36, 182, 255)
        wing_edge = (196, 144, 255, 235)
        ear_fill = (138, 78, 252, 255)
        brow_fill = (188, 136, 255, 245)
        eye_ring = (206, 156, 255, 255)
        eye_glow = (168, 88, 255, 235)
        pupil_color = (18, 8, 44, 255)
        beak_color = (232, 204, 255, 255)
        feather_color = (204, 158, 255, 225)
        claw_color = (152, 96, 248, 255)

    # 1. 猫头鹰背部紫光光晕
    if kind != "tinted":
        aura = Image.new("RGBA", (U, U), (0, 0, 0, 0))
        ad = ImageDraw.Draw(aura, "RGBA")
        ad.ellipse(box(310, 280, 714, 740), fill=(168, 92, 255, 95))
        layer.alpha_composite(aura.filter(ImageFilter.GaussianBlur(int(36 * s))))

    # 2. 身体主轮廓（饱满的圆润躯干 + 渐变）
    body_mask = Image.new("L", (U, U), 0)
    bmd = ImageDraw.Draw(body_mask)
    bmd.ellipse(box(348, 370, 676, 716), fill=255)
    bmd.ellipse(box(356, 292, 668, 536), fill=255)

    body_grad = Image.new("RGBA", (U, U), (0, 0, 0, 0))
    bgd = ImageDraw.Draw(body_grad, "RGBA")
    for y in range(int(285 * s), int(720 * s)):
        t = (y - 285 * s) / max(1, (720 - 285) * s)
        col = lerp(body_top, body_bot, t)
        bgd.line([(330 * s, y), (694 * s, y)], fill=col)
    body_grad.putalpha(ImageChops.multiply(body_grad.getchannel("A"), body_mask))
    layer.alpha_composite(body_grad)

    d = ImageDraw.Draw(layer, "RGBA")

    # 3. 两侧收拢的双翼（弧形护翼 + 霓虹描边）
    left_wing = poly([
        (356, 440),
        (324, 504),
        (328, 594),
        (366, 668),
        (398, 636),
        (386, 526),
    ])
    right_wing = poly([
        (668, 440),
        (700, 504),
        (696, 594),
        (658, 668),
        (626, 636),
        (638, 526),
    ])
    d.polygon(left_wing, fill=wing_fill, outline=wing_edge, width=int(6 * s))
    d.polygon(right_wing, fill=wing_fill, outline=wing_edge, width=int(6 * s))

    # 4. 标志性上扬耳羽簇（参考图 V 字霸气眉骨 + 尖耳）
    left_ear = poly([
        (362, 360),
        (336, 252),
        (414, 290),
        (468, 344),
        (402, 368),
    ])
    right_ear = poly([
        (662, 360),
        (688, 252),
        (610, 290),
        (556, 344),
        (622, 368),
    ])
    d.polygon(left_ear, fill=ear_fill, outline=wing_edge, width=int(6 * s))
    d.polygon(right_ear, fill=ear_fill, outline=wing_edge, width=int(6 * s))

    # 耳羽内侧高光折线
    d.line(poly([(344, 262), (412, 314), (486, 368)]), fill=brow_fill, width=int(7 * s))
    d.line(poly([(680, 262), (612, 314), (538, 368)]), fill=brow_fill, width=int(7 * s))

    # 5. 双眼发光底盘与眼眶
    left_eye_center = (438, 412)
    right_eye_center = (586, 412)
    eye_outer_r = 62
    eye_inner_r = 46

    if kind != "tinted":
        eye_glow_layer = Image.new("RGBA", (U, U), (0, 0, 0, 0))
        egd = ImageDraw.Draw(eye_glow_layer, "RGBA")
        for cx, cy in (left_eye_center, right_eye_center):
            egd.ellipse(
                box(cx - eye_outer_r - 12, cy - eye_outer_r - 12, cx + eye_outer_r + 12, cy + eye_outer_r + 12),
                fill=eye_glow,
            )
        layer.alpha_composite(eye_glow_layer.filter(ImageFilter.GaussianBlur(int(16 * s))))
        d = ImageDraw.Draw(layer, "RGBA")

    for cx, cy in (left_eye_center, right_eye_center):
        # 眼盘外圈霓虹环
        d.ellipse(
            box(cx - eye_outer_r, cy - eye_outer_r, cx + eye_outer_r, cy + eye_outer_r),
            fill=eye_ring,
            outline=brow_fill,
            width=int(6 * s),
        )
        if kind != "tinted":
            # 紫色虹膜环
            d.ellipse(
                box(cx - eye_inner_r - 5, cy - eye_inner_r - 5, cx + eye_inner_r + 5, cy + eye_inner_r + 5),
                fill=(154, 84, 255, 255),
            )
            # 深色瞳孔
            d.ellipse(
                box(cx - eye_inner_r + 6, cy - eye_inner_r + 6, cx + eye_inner_r - 6, cy + eye_inner_r - 6),
                fill=pupil_color,
            )
            # 双眼神高光点
            d.ellipse(
                box(cx - 22, cy - 24, cx - 2, cy - 4),
                fill=(255, 255, 255, 250),
            )
            d.ellipse(
                box(cx + 12, cy + 10, cx + 23, cy + 21),
                fill=(230, 210, 255, 220),
            )

    # 眉心 V 字科技棱线（连接双眉直达鸟喙）
    d.line(
        poly([(372, 318), (512, 418), (652, 318)]),
        fill=brow_fill,
        width=int(9 * s),
        joint="curve",
    )

    # 6. 锐利菱形鸟喙
    beak = poly([
        (512, 422),
        (484, 466),
        (512, 512),
        (540, 466),
    ])
    d.polygon(beak, fill=beak_color, outline=wing_edge, width=int(4 * s))

    # 7. 胸前标志性三排 V 形羽毛鳞纹（与参考图 1 & 2 完全一致）
    feather_rows = [
        [(442, 548), (488, 552), (536, 552), (582, 548)],
        [(462, 592), (512, 596), (562, 592)],
        [(486, 634), (538, 634)],
    ]
    if kind == "tinted":
        # Tinted 模式下将瞳孔与胸羽挖空以展现层次
        alpha = layer.getchannel("A")
        ad = ImageDraw.Draw(alpha)
        for cx, cy in (left_eye_center, right_eye_center):
            ad.ellipse(
                box(cx - eye_inner_r + 4, cy - eye_inner_r + 4, cx + eye_inner_r - 4, cy + eye_inner_r - 4),
                fill=0,
            )
            ad.ellipse(box(cx - 20, cy - 22, cx - 2, cy - 4), fill=255)
        for row in feather_rows:
            for fx, fy in row:
                v_pts = poly([(fx - 14, fy - 7), (fx, fy + 10), (fx + 14, fy - 7)])
                ad.line(v_pts, fill=0, width=int(8 * s))
        layer.putalpha(alpha)
        d = ImageDraw.Draw(layer, "RGBA")
    else:
        for row in feather_rows:
            for fx, fy in row:
                v_pts = poly([(fx - 14, fy - 7), (fx, fy + 10), (fx + 14, fy - 7)])
                d.line(v_pts, fill=feather_color, width=int(7 * s), joint="curve")

    # 8. 底部外露利爪
    for base_x in (452, 572):
        for dx in (-18, 0, 18):
            d.rounded_rectangle(
                box(base_x + dx - 6, 696, base_x + dx + 6, 730),
                radius=int(6 * s),
                fill=claw_color,
            )

    # 身体外圈精致高光描边
    d.arc(box(348, 370, 676, 716), 20, 160, fill=wing_edge, width=int(6 * s))

    return layer


def draw_glass_sphere_and_owl(
    canvas: Image.Image,
    s: int,
    kind: str,
) -> None:
    """在 canvas 上组合：后置双星轨 → 全息液态玻璃球底 → 赛博猫头鹰 → 玻璃球高光罩 → 前置双星轨。"""
    cx, cy = 512 * s, 512 * s
    sphere_r = 286 * s

    if kind == "tinted":
        orbit1_col = (255, 255, 255, 170)
        orbit2_col = (255, 255, 255, 115)
        orbit_glow = None
        rim_col = (255, 255, 255, 220)
    elif kind == "light":
        orbit1_col = (232, 206, 255, 235)
        orbit2_col = (198, 156, 255, 185)
        orbit_glow = (176, 108, 255, 150)
        rim_col = (242, 225, 255, 230)
    else:
        orbit1_col = (214, 164, 255, 235)
        orbit2_col = (156, 96, 255, 185)
        orbit_glow = (168, 84, 255, 170)
        rim_col = (232, 198, 255, 215)

    # 1. 后半圈星轨（位于玻璃球后方）
    draw_rotated_orbit(
        canvas,
        cx,
        cy + 14 * s,
        rx=435 * s,
        ry=142 * s,
        angle_deg=-22,
        color=orbit1_col,
        width=int(7 * s),
        front_only=False,
        dots=[215, 330],
        glow_color=orbit_glow,
    )
    draw_rotated_orbit(
        canvas,
        cx,
        cy + 14 * s,
        rx=392 * s,
        ry=118 * s,
        angle_deg=19,
        color=orbit2_col,
        width=int(5 * s),
        front_only=False,
        dots=[250],
        glow_color=orbit_glow,
    )

    # 2. 玻璃球内部深邃能量底衬
    if kind != "tinted":
        sphere_bg = Image.new("RGBA", (U, U), (0, 0, 0, 0))
        sbd = ImageDraw.Draw(sphere_bg, "RGBA")
        inner_fill = (32, 14, 78, 175) if kind == "dark" else (58, 26, 138, 155)
        sbd.ellipse(
            [cx - sphere_r, cy - sphere_r, cx + sphere_r, cy + sphere_r],
            fill=inner_fill,
        )
        # 球体右下方紫罗兰内反射光
        refract = Image.new("RGBA", (U, U), (0, 0, 0, 0))
        rd = ImageDraw.Draw(refract, "RGBA")
        rd.ellipse(
            [cx - sphere_r * 0.4, cy - sphere_r * 0.2, cx + sphere_r * 0.95, cy + sphere_r * 0.95],
            fill=(176, 96, 255, 110),
        )
        refract = refract.filter(ImageFilter.GaussianBlur(int(42 * s)))
        sphere_mask = Image.new("L", (U, U), 0)
        ImageDraw.Draw(sphere_mask).ellipse(
            [cx - sphere_r, cy - sphere_r, cx + sphere_r, cy + sphere_r], fill=255
        )
        refract.putalpha(ImageChops.multiply(refract.getchannel("A"), sphere_mask))
        sphere_bg.alpha_composite(refract)
        canvas.alpha_composite(sphere_bg)

    # 3. 赛博猫头鹰本体
    owl = draw_cyber_owl(s, kind)
    canvas.alpha_composite(owl)

    # 4. 玻璃球表面高光弧与外边缘折射圈
    glass_rim = Image.new("RGBA", (U, U), (0, 0, 0, 0))
    grd = ImageDraw.Draw(glass_rim, "RGBA")
    grd.ellipse(
        [cx - sphere_r, cy - sphere_r, cx + sphere_r, cy + sphere_r],
        outline=rim_col,
        width=int(8 * s),
    )
    # 左上角月牙高光反射弧
    inset = 18 * s
    grd.arc(
        [cx - sphere_r + inset, cy - sphere_r + inset, cx + sphere_r - inset, cy + sphere_r - inset],
        196,
        312,
        fill=(255, 255, 255, 235 if kind != "tinted" else 200),
        width=int(10 * s),
    )
    # 右下角次级折射弧
    grd.arc(
        [cx - sphere_r + inset, cy - sphere_r + inset, cx + sphere_r - inset, cy + sphere_r - inset],
        22,
        118,
        fill=orbit1_col,
        width=int(6 * s),
    )
    canvas.alpha_composite(glass_rim)

    # 5. 前半圈星轨（横跨玻璃球前方，形成真实 3D 环绕感）
    draw_rotated_orbit(
        canvas,
        cx,
        cy + 14 * s,
        rx=435 * s,
        ry=142 * s,
        angle_deg=-22,
        color=orbit1_col,
        width=int(7 * s),
        front_only=True,
        dots=[28, 148],
        glow_color=orbit_glow,
    )
    draw_rotated_orbit(
        canvas,
        cx,
        cy + 14 * s,
        rx=392 * s,
        ry=118 * s,
        angle_deg=19,
        color=orbit2_col,
        width=int(5 * s),
        front_only=True,
        dots=[72, 162],
        glow_color=orbit_glow,
    )


def draw_icon(kind: str) -> Image.Image:
    s = SS
    if kind == "tinted":
        canvas = Image.new("RGBA", (U, U), (0, 0, 0, 0))
    elif kind == "dark":
        # 深色模式：深邃曜石紫黑底 + 中央霓虹紫星云辉光
        canvas = radial_Wait_gradient(
            U,
            c_center=(68, 30, 148),
            c_mid=(24, 11, 56),
            c_edge=(9, 5, 22),
        ).convert("RGBA")
    else:
        # 浅色模式：通透电光紫罗兰渐变底，与深色模式既有家族感又明快醒目
        canvas = radial_Wait_gradient(
            U,
            c_center=(162, 108, 255),
            c_mid=(104, 54, 224),
            c_edge=(54, 24, 136),
        ).convert("RGBA")

    if kind != "tinted":
        # 顶部环境柔光
        top_glow = Image.new("RGBA", (U, U), (0, 0, 0, 0))
        ImageDraw.Draw(top_glow, "RGBA").ellipse(
            [180 * s, -40 * s, 844 * s, 520 * s],
            fill=(220, 185, 255, 55 if kind == "dark" else 80),
        )
        canvas.alpha_composite(top_glow.filter(ImageFilter.GaussianBlur(int(95 * s))))

    draw_glass_sphere_and_owl(canvas, s, kind)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def generate_mascot_showcase(light_icon: Image.Image, dark_icon: Image.Image) -> Image.Image:
    """生成 docs/brand/mascot.png：浅色与深色模式下的全息赛博猫头鹰对比预览。"""
    w, h = 1200, 520
    showcase = Image.new("RGB", (w, h), (244, 242, 252))
    half = w // 2

    # 左半：浅色模式卡片
    left_bg = radial_Wait_gradient(
        half,
        c_center=(250, 247, 255),
        c_mid=(238, 232, 255),
        c_edge=(222, 212, 250),
    ).resize((half, h), Image.BICUBIC).convert("RGBA")
    owl_light = Image.new("RGBA", (U, U), (0, 0, 0, 0))
    draw_glass_sphere_and_owl(owl_light, SS, "light")
    owl_light_small = owl_light.resize((440, 440), Image.LANCZOS)
    left_bg.alpha_composite(owl_light_small, ((half - 440) // 2, (h - 440) // 2))

    # 右半：深色模式卡片
    right_bg = radial_Wait_gradient(
        half,
        c_center=(52, 24, 112),
        c_mid=(20, 10, 46),
        c_edge=(8, 5, 18),
    ).resize((half, h), Image.BICUBIC).convert("RGBA")
    owl_dark = Image.new("RGBA", (U, U), (0, 0, 0, 0))
    draw_glass_sphere_and_owl(owl_dark, SS, "dark")
    owl_dark_small = owl_dark.resize((440, 440), Image.LANCZOS)
    right_bg.alpha_composite(owl_dark_small, ((half - 440) // 2, (h - 440) // 2))

    showcase.paste(left_bg.convert("RGB"), (0, 0))
    showcase.paste(right_bg.convert("RGB"), (half, 0))
    return showcase


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    BRAND_OUT.mkdir(parents=True, exist_ok=True)

    rendered: dict[str, Image.Image] = {}
    for kind in ("light", "dark", "tinted"):
        img = draw_icon(kind)
        rendered[kind] = img
        if kind == "tinted":
            out_img = img.convert("RGBA")  # 保留透明通道：系统会着色
        else:
            out_img = img.convert("RGB")   # iOS 主图标禁止 alpha
        path = OUT / f"icon-{kind}.png"
        out_img.save(path)
        print(f"wrote {path} ({path.stat().st_size} bytes)")

    # 同步更新 docs/brand/ 下的全部图标与吉祥物预览图
    light_brand = rendered["light"].convert("RGB").resize((512, 512), Image.LANCZOS)
    dark_brand = rendered["dark"].convert("RGB").resize((512, 512), Image.LANCZOS)
    light_brand.save(BRAND_OUT / "icon.png")
    dark_brand.save(BRAND_OUT / "icon-dark.png")
    mascot_img = generate_mascot_showcase(rendered["light"], rendered["dark"])
    mascot_img.save(BRAND_OUT / "mascot.png")
    print(f"updated docs/brand/icon.png, icon-dark.png, mascot.png")


if __name__ == "__main__":
    main()
