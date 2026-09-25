"""生成 Mimir 内置聊天背景（紫色系）。

三张壁纸刻意做成"低对比、低饱和"，因为 App 会在上面叠一层材质遮罩，
背景只负责氛围，不能抢正文的可读性。

用法：
    python tools/generate_wallpapers.py

产物直接写进 `Mimir/Resources/Assets.xcassets/`，每张一个 imageset。
改颜色 / 形状后重跑即可，脚本是幂等的。
"""

from __future__ import annotations

import json
import pathlib

import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Mimir" / "Resources" / "Assets.xcassets"

WIDTH, HEIGHT = 1179, 2556
SEED = 20260925


def _grid() -> tuple[np.ndarray, np.ndarray]:
    ys, xs = np.mgrid[0:HEIGHT, 0:WIDTH].astype(np.float32)
    return xs / WIDTH, ys / HEIGHT


def _blob(nx: np.ndarray, ny: np.ndarray, cx: float, cy: float, radius: float) -> np.ndarray:
    """归一化径向光斑（0..1），radius 为相对长边的半径。"""
    dx = (nx - cx) * (WIDTH / HEIGHT)
    dy = ny - cy
    d2 = (dx * dx + dy * dy) / (radius * radius)
    return np.exp(-d2 * 1.6).astype(np.float32)


def _vertical_gradient(*stops: tuple[float, tuple[int, int, int]]) -> np.ndarray:
    """按 (位置, RGB) 生成竖向渐变，位置 0 在顶部，返回 (HEIGHT, 3)。"""
    ys = np.linspace(0.0, 1.0, HEIGHT, dtype=np.float32)[:, None]
    out = np.tile(np.array(stops[0][1], dtype=np.float32), (HEIGHT, 1))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        mask = ((ys[:, 0] >= p0) & (ys[:, 0] <= p1))
        if not mask.any():
            continue
        t = (ys[mask] - p0) / max(p1 - p0, 1e-6)
        a = np.array(c0, dtype=np.float32)[None, :]
        b = np.array(c1, dtype=np.float32)[None, :]
        out[mask] = a + (b - a) * t
    return out


def _finish(field: np.ndarray, grain: float) -> Image.Image:
    """叠噪点 → 轻微柔化 → 输出 PIL 图。"""
    rng = np.random.default_rng(SEED)
    if grain > 0:
        field = field + rng.normal(0.0, grain, (HEIGHT, WIDTH, 1)).astype(np.float32)
    field = np.clip(field, 0, 255).astype(np.uint8)
    image = Image.fromarray(field, mode="RGB")
    # 极轻的模糊让噪点变成胶片颗粒，而不是数字噪点。
    return image.filter(ImageFilter.GaussianBlur(0.4))


def violet_mist() -> Image.Image:
    """紫雾：深紫到靛蓝的竖向渐变 + 三团柔光。"""
    nx, ny = _grid()
    base = _vertical_gradient(
        (0.0, (36, 24, 68)),
        (0.45, (74, 48, 138)),
        (0.78, (108, 74, 190)),
        (1.0, (58, 38, 108)),
    )
    field = np.repeat(base[:, None, :], WIDTH, axis=1)
    field += _blob(nx, ny, 0.22, 0.20, 0.55)[..., None] * np.array([46, 26, 88], dtype=np.float32)
    field += _blob(nx, ny, 0.86, 0.52, 0.48)[..., None] * np.array([62, 40, 120], dtype=np.float32)
    field += _blob(nx, ny, 0.50, 0.96, 0.60)[..., None] * np.array([30, 18, 60], dtype=np.float32)
    return _finish(field, grain=2.2)


def aurora() -> Image.Image:
    """极光：几条流动的紫 / 品红光带。"""
    nx, ny = _grid()
    base = _vertical_gradient(
        (0.0, (24, 20, 52)),
        (0.5, (52, 32, 96)),
        (1.0, (28, 20, 60)),
    )
    field = np.repeat(base[:, None, :], WIDTH, axis=1)

    ribbon = np.zeros((HEIGHT, WIDTH), dtype=np.float32)
    for (amp, freq, phase, center, width, weight) in (
        (0.10, 1.6, 0.0, 0.30, 0.16, 1.00),
        (0.07, 2.4, 1.7, 0.52, 0.13, 0.72),
        (0.05, 3.1, 3.4, 0.72, 0.11, 0.52),
    ):
        wave = center + amp * np.sin(ny * freq * np.pi * 2 + phase) + 0.03 * np.sin(nx * 6.0 + phase)
        ribbon += weight * np.exp(-((ny - wave) ** 2) / (2 * width * width)).astype(np.float32)

    ribbon = ribbon[:, :, None]
    field += ribbon * np.array([120, 70, 200], dtype=np.float32)
    field += ribbon * _blob(nx, ny, 0.75, 0.35, 0.5)[..., None] * np.array([90, 40, 120], dtype=np.float32)
    field += _blob(nx, ny, 0.15, 0.85, 0.55)[..., None] * np.array([40, 60, 130], dtype=np.float32)
    return _finish(field, grain=2.0)


def starfield() -> Image.Image:
    """星夜：深紫近黑底 + 星云 + 星点。"""
    nx, ny = _grid()
    base = _vertical_gradient(
        (0.0, (16, 14, 36)),
        (0.55, (30, 22, 62)),
        (1.0, (14, 12, 30)),
    )
    field = np.repeat(base[:, None, :], WIDTH, axis=1)
    field += _blob(nx, ny, 0.70, 0.28, 0.42)[..., None] * np.array([54, 32, 96], dtype=np.float32)
    field += _blob(nx, ny, 0.24, 0.62, 0.38)[..., None] * np.array([38, 24, 78], dtype=np.float32)

    rng = np.random.default_rng(SEED + 1)
    canvas = np.asarray(_finish(field, grain=1.2), dtype=np.float32).copy()
    for _ in range(520):
        cx = int(rng.integers(0, WIDTH))
        cy = int(rng.integers(0, HEIGHT))
        radius = int(rng.integers(1, 3))
        brightness = float(rng.uniform(40, 120))
        y0, y1 = max(cy - radius, 0), min(cy + radius + 1, HEIGHT)
        x0, x1 = max(cx - radius, 0), min(cx + radius + 1, WIDTH)
        canvas[y0:y1, x0:x1] += brightness
    canvas = np.clip(canvas, 0, 255).astype(np.uint8)
    return Image.fromarray(canvas, mode="RGB").filter(ImageFilter.GaussianBlur(0.3))


def write_imageset(name: str, image: Image.Image) -> pathlib.Path:
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"{name}.jpg"
    target = folder / filename
    image.save(target, format="JPEG", quality=86, optimize=True, progressive=True)
    contents = {
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2), encoding="utf-8")
    return target


def main() -> None:
    builders = {
        "bg-violet-mist": violet_mist,
        "bg-aurora": aurora,
        "bg-starfield": starfield,
    }
    for name, builder in builders.items():
        image = builder()
        path = write_imageset(name, image)
        print(f"{name}: {image.size[0]}x{image.size[1]}  {path.stat().st_size / 1024:.0f} KB  -> {path}")


if __name__ == "__main__":
    main()
