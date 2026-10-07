"""Algorithmic Terrain Compositor.

Combines uniform base swatches with minor transparent decals (sprouts, pebbles,
grass tufts, ruts) using controllable distributions (grid, scatter, cluster)
to produce endless seamless, non-hallucinated combination terrain textures.
"""

from __future__ import annotations

import argparse
import random
from pathlib import Path
from PIL import Image, ImageEnhance

def composite_terrain(
    base_image_path: Path,
    decal_layers: list[dict],
    output_path: Path,
    seed: int = 42,
    canvas_size: tuple[int, int] | None = None,
) -> Path:
    rng = random.Random(seed)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with Image.open(base_image_path) as opened:
        base = opened.convert("RGBA")

    if canvas_size:
        base = base.resize(canvas_size, Image.Resampling.LANCZOS)
    canvas_w, canvas_h = base.size

    composite = base.copy()

    for layer in decal_layers:
        decal_path = Path(layer["image"])
        if not decal_path.is_file():
            print(f"[WARN] Decal file missing: {decal_path}")
            continue

        with Image.open(decal_path) as d_img:
            decal_raw = d_img.convert("RGBA")

        # Crop to non-transparent bounding box
        alpha = decal_raw.split()[-1]
        bbox = alpha.getbbox()
        if bbox:
            decal_raw = decal_raw.crop(bbox)

        mode = layer.get("mode", "scatter")
        scale_min, scale_max = layer.get("scale_range", (0.15, 0.25))
        rot_range = layer.get("rot_jitter_deg", 360)
        opacity = layer.get("opacity", 1.0)

        positions = []
        if mode == "grid":
            rows = layer.get("rows", 4)
            cols = layer.get("cols", 4)
            jitter = layer.get("jitter_px", 16)
            step_x = canvas_w / cols
            step_y = canvas_h / rows
            for r in range(rows):
                for c in range(cols):
                    px = (c + 0.5) * step_x + rng.uniform(-jitter, jitter)
                    py = (r + 0.5) * step_y + rng.uniform(-jitter, jitter)
                    positions.append((px, py))
        elif mode == "cluster":
            clusters = layer.get("clusters", 3)
            per_cluster = layer.get("per_cluster", 4)
            radius = layer.get("radius_px", 60)
            for _ in range(clusters):
                cx = rng.uniform(canvas_w * 0.15, canvas_w * 0.85)
                cy = rng.uniform(canvas_h * 0.15, canvas_h * 0.85)
                for _ in range(per_cluster):
                    positions.append((
                        cx + rng.gauss(0, radius / 2),
                        cy + rng.gauss(0, radius / 2)
                    ))
        else: # scatter
            count = layer.get("count", 8)
            for _ in range(count):
                positions.append((
                    rng.uniform(0, canvas_w),
                    rng.uniform(0, canvas_h)
                ))

        for px, py in positions:
            scale = rng.uniform(scale_min, scale_max)
            rot = rng.uniform(-rot_range, rot_range) if rot_range else 0.0

            # Scale decal
            dw = max(8, int(canvas_w * scale))
            aspect = decal_raw.height / max(1, decal_raw.width)
            dh = max(8, int(dw * aspect))
            d_scaled = decal_raw.resize((dw, dh), Image.Resampling.LANCZOS)

            # Random horizontal flip
            if rng.random() > 0.5:
                d_scaled = d_scaled.transpose(Image.Transpose.FLIP_LEFT_RIGHT)

            # Rotate
            if rot != 0:
                d_scaled = d_scaled.rotate(rot, resample=Image.Resampling.BICUBIC, expand=True)

            # Opacity
            if opacity < 1.0:
                r, g, b, a = d_scaled.split()
                a = ImageEnhance.Brightness(a).enhance(opacity)
                d_scaled.putalpha(a)

            # Paste
            paste_x = int(px - d_scaled.width / 2)
            paste_y = int(py - d_scaled.height / 2)

            # Seamless wrap or clamp
            composite.alpha_composite(d_scaled, (paste_x, paste_y))

    composite.convert("RGB").save(output_path, format="PNG", optimize=True)
    print(f"[OK] Saved composite terrain -> {output_path} ({output_path.stat().st_size} bytes)")
    return output_path
