#!/usr/bin/env python3
"""Generates build/icon.png, build/tray.png and build/icons/*.png.

The mark is the brand described in plan.md: one continuous listening arc with a gap
(the "i" dot becomes a signal point) on a dark slate tile with a violet glow.
Supersampled 3x so the arcs stay smooth at 16 px.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
ICONS = BUILD / "icons"

SIGNAL = (124, 92, 255)
DEEP = (58, 32, 150)
INK = (11, 13, 20)
SS = 3  # supersample factor
SIZE = 1024


def rounded_mask(size: int, radius_ratio: float = 0.225) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255)
    return mask


def radial_glow(size: int, center_xy: tuple[float, float], spread: float, color: tuple[int, int, int]) -> np.ndarray:
  ys, xs = np.mgrid[0:size, 0:size]
  dist = np.sqrt((xs - center_xy[0]) ** 2 + (ys - center_xy[1]) ** 2) / (size * spread)
  alpha = np.clip(1.0 - dist, 0.0, 1.0) ** 2.2
  layer = np.zeros((size, size, 4), dtype=np.uint8)
  # Premultiply so np.maximum behaves like a screen blend against the ink base.
  layer[..., 0] = (color[0] * alpha).astype(np.uint8)
  layer[..., 1] = (color[1] * alpha).astype(np.uint8)
  layer[..., 2] = (color[2] * alpha).astype(np.uint8)
  layer[..., 3] = (alpha * 255).astype(np.uint8)
  return layer


def base_tile(size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    background = np.zeros((size, size, 4), dtype=np.uint8)
    background[..., 0] = INK[0]
    background[..., 1] = INK[1]
    background[..., 2] = INK[2]
    background[..., 3] = 255
    background = np.maximum(background, radial_glow(size, (size * 0.3, size * 0.22), 0.85, DEEP))
    background = np.maximum(background, radial_glow(size, (size * 0.34, size * 0.26), 0.5, SIGNAL))
    tile = Image.fromarray(background, "RGBA")
    canvas.paste(tile, (0, 0), rounded_mask(size))
    return canvas


def mark(size: int, color: tuple[int, int, int], width_ratio: float = 0.075) -> Image.Image:
    """Broken ring + signal dot: the bubble that is always listening."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    stroke = max(2, int(size * width_ratio))
    margin = int(size * 0.2)
    box = [margin, margin, size - margin, size - margin]
    # Gap at the top-right reads as an opening ear rather than a closed circle.
    draw.arc(box, start=-52, end=232, fill=color + (255,), width=stroke)
    dot_r = stroke * 0.62
    cx, cy = size * 0.755, size * 0.245
    draw.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r], fill=color + (255,))
    inner = int(size * 0.075)
    center = size / 2
    draw.ellipse(
        [center - inner, center - inner, center + inner, center + inner],
        fill=color + (255,),
    )
    return layer


def build_app_icon() -> Image.Image:
    canvas = base_tile(SIZE * SS)
    ring = mark(SIZE * SS, (255, 255, 255), width_ratio=0.062)
    glow = ring.filter(ImageFilter.GaussianBlur(radius=SIZE * SS * 0.02))
    glow = Image.merge("RGBA", (*glow.split()[:3], glow.split()[3].point(lambda v: int(v * 0.55))))
    canvas.alpha_composite(glow)
    canvas.alpha_composite(ring)
    icon = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    return icon


def build_tray_icon(size: int = 32) -> Image.Image:
    layer = mark(size * 8, (255, 255, 255), width_ratio=0.1)
    return layer.resize((size, size), Image.LANCZOS)


def main() -> None:
    ICONS.mkdir(parents=True, exist_ok=True)
    icon = build_app_icon()
    icon.save(BUILD / "icon.png")
    for size in (16, 32, 48, 64, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(ICONS / f"{size}x{size}.png")
    build_tray_icon(32).save(BUILD / "tray.png")
    build_tray_icon(16).save(BUILD / "tray-16.png")
    print(f"wrote {BUILD / 'icon.png'}, {BUILD / 'tray.png'} and {ICONS}/*.png")


if __name__ == "__main__":
    main()
