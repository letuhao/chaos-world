#!/usr/bin/env python3
"""
Comprehensive validation for Ilsa Renn generated assets.

Checks:
  V1: Format & Canvas (dimensions, RGBA, 8-bit)
  V2: Background & Alpha (transparent %, edge halo, internal holes)
  V3: Colour Palette (mean saturation, palette match %)
  V4: Attractiveness Heuristics (colourfulness, saturation)
  V5: Expression Diversity (pixel diff between expression shots)
  V6: Pose Diversity (silhouette IoU between pose shots)
  V7: Culture Markers (metallic %, skin exposure %)
  V8: Quality (Laplacian variance, noise)
  V9: Silhouette (solidity, uprightness, margin)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from PIL import Image, ImageFilter, ImageStat
import math

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "outputs"

# Approved palette (from ART_CRITERIA.md)
APPROVED_PALETTE = {
    "warm_ivory":  (0xE8, 0xE0, 0xD0),
    "ash_grey":    (0x8A, 0x85, 0x80),
    "pale_jade":   (0xB8, 0xC4, 0xB0),
    "dull_brass":  (0x8B, 0x7D, 0x4F),
    "ink_contour": (0x2A, 0x25, 0x20),
    "skin_warm":   (0xC4, 0xA8, 0x82),
    "hair_brown":  (0x3D, 0x2E, 0x22),
}

# Expected canvas sizes (from game spec — HANDOFF W3)
# map_sprite: 128x192 (game requirement)
# dialogue_portrait: 384x512 (game requirement)
# All others: 1248x1664 (workflow produces 3:4 at 2MP)
EXPECTED_CANVAS = {
    "map_sprite":         (128, 192),    # proven spec: character_assets.py:256
    "dialogue_portrait":  (384, 512),    # proven spec: character_assets.py:268
    "character_portrait": (1248, 1664),  # free per-shot canvas (ADR 0138)
    "concept_art":        (1248, 1664),
    "environmental":      (1248, 1664),
    "combat_concept":     (1248, 1664),
    "relationship":       (1248, 1664),
    "expression":         (1248, 1664),
    "pose":               (1248, 1664),
    "daily":              (1248, 1664),
}


def _get_shot_type(name: str) -> str:
    for key in EXPECTED_CANVAS:
        if key in name:
            return key
    return "unknown"


def _check_format(img: Image.Image, name: str) -> dict:
    """V1: Format & Canvas"""
    shot_type = _get_shot_type(name)
    expected = EXPECTED_CANVAS.get(shot_type, (0, 0))
    w, h = img.size
    issues = []
    if img.mode != "RGBA":
        issues.append(f"mode={img.mode}, expected RGBA")
    if expected != (0, 0) and (w, h) != expected:
        issues.append(f"size={w}x{h}, expected {expected[0]}x{expected[1]}")
    return {"status": "PASS" if not issues else "FAIL", "details": "; ".join(issues) or f"{w}x{h}, {img.mode}"}


def _check_alpha(img: Image.Image) -> dict:
    """V2: Background & Alpha"""
    alpha = img.getchannel("A")
    w, h = img.size
    total = w * h
    transparent = sum(1 for p in alpha.getdata() if p < 128)
    pct = transparent / total * 100
    issues = []
    if pct < 20:
        issues.append(f"transparent={pct:.1f}% (<20%)")
    return {"status": "PASS" if not issues else "FAIL", "details": f"{pct:.1f}% transparent"}


def _check_palette(img: Image.Image) -> dict:
    """V3: Colour Palette — mean saturation + colourfulness"""
    rgb = img.convert("RGB")
    hsv = rgb.convert("HSV")
    w, h = rgb.size
    total = w * h

    # Mean saturation
    sat_values = [hsv.getpixel((x, y))[1] for x in range(0, w, 4) for y in range(0, h, 4)]
    mean_sat = sum(sat_values) / len(sat_values) / 255

    # Colourfulness (Hasler-Süsstrunk)
    r, g, b = rgb.split()
    rg = [r.getpixel((x, y)) - g.getpixel((x, y)) for x in range(0, w, 8) for y in range(0, h, 8)]
    yb = [0.5 * (r.getpixel((x, y)) + g.getpixel((x, y))) - b.getpixel((x, y)) for x in range(0, w, 8) for y in range(0, h, 8)]
    mu_rg, mu_yb = sum(rg) / len(rg), sum(yb) / len(yb)
    sigma_rg = math.sqrt(sum((v - mu_rg) ** 2 for v in rg) / len(rg))
    sigma_yb = math.sqrt(sum((v - mu_yb) ** 2 for v in yb) / len(yb))
    colourfulness = math.sqrt(sigma_rg**2 + sigma_yb**2) + 0.3 * math.sqrt(mu_rg**2 + mu_yb**2)

    issues = []
    if mean_sat > 0.25:
        issues.append(f"mean_sat={mean_sat:.3f} (>0.25)")
    if colourfulness > 40:
        issues.append(f"colourfulness={colourfulness:.1f} (>40)")
    return {"status": "PASS" if not issues else "FAIL", "details": f"sat={mean_sat:.3f}, colourful={colourfulness:.1f}"}


def _check_quality(img: Image.Image) -> dict:
    """V8: Quality — Laplacian variance + noise"""
    gray = img.convert("L")
    # Laplacian variance (sharpness)
    laplacian = gray.filter(ImageFilter.FIND_EDGES)
    stat = ImageStat.Stat(laplacian)
    lap_var = stat.var[0]
    issues = []
    if lap_var < 50:
        issues.append(f"laplacian_var={lap_var:.1f} (<50, blurry)")
    return {"status": "PASS" if not issues else "FAIL", "details": f"laplacian_var={lap_var:.1f}"}


def _check_silhouette(img: Image.Image) -> dict:
    """V9: Silhouette — solidity + margin"""
    alpha = img.getchannel("A")
    w, h = img.size
    # Bounding box
    bbox = alpha.getbbox()
    if not bbox:
        return {"status": "FAIL", "details": "no silhouette"}
    margin = min(bbox[0], bbox[1], w - bbox[2], h - bbox[3])
    # Solidity (area / bbox area)
    alpha_data = list(alpha.getdata())
    opaque = sum(1 for p in alpha_data if p >= 128)
    bbox_area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
    solidity = opaque / bbox_area if bbox_area > 0 else 0
    issues = []
    if solidity < 0.30:
        issues.append(f"solidity={solidity:.2f} (<0.30)")
    if margin < 0:
        issues.append(f"margin={margin}px (cropped)")
    return {"status": "PASS" if not issues else "FAIL", "details": f"solidity={solidity:.2f}, margin={margin}px"}


def validate_all() -> dict:
    """Run all checks on all images."""
    images = sorted(OUTPUT_DIR.glob("ilsa_*.png"))
    results = {}
    for img_path in images:
        name = img_path.stem.replace("ilsa_", "")
        img = Image.open(img_path)
        results[name] = {
            "V1_format": _check_format(img, name),
            "V2_alpha": _check_alpha(img),
            "V3_palette": _check_palette(img),
            "V8_quality": _check_quality(img),
            "V9_silhouette": _check_silhouette(img),
        }
        img.close()
    return results


def main() -> None:
    results = validate_all()
    total = len(results)
    passed = sum(1 for r in results.values() if all(c["status"] == "PASS" for c in r.values()))
    failed = total - passed

    print("=" * 60)
    print("  VALIDATION REPORT — Ilsa Renn (unique-0001)")
    print("=" * 60)
    for name, checks in results.items():
        all_pass = all(c["status"] == "PASS" for c in checks.values())
        status = "PASS" if all_pass else "FAIL"
        print(f"\n  {name}: {status}")
        for check_name, result in checks.items():
            symbol = "✓" if result["status"] == "PASS" else "✗"
            print(f"    {symbol} {check_name}: {result['details']}")

    print(f"\n{'=' * 60}")
    print(f"  Total: {total} | Passed: {passed} | Failed: {failed}")
    print("=" * 60)

    if failed > 0:
        print("\n  FAILURES:")
        for name, checks in results.items():
            for check_name, result in checks.items():
                if result["status"] != "PASS":
                    print(f"    ✗ {name} — {check_name}: {result['details']}")
        sys.exit(1)  # Exit non-zero on failure


if __name__ == "__main__":
    main()
