"""Batch driver: generate the ancient_china_low_cultivation pack sub-domain by sub-domain.

Resumable (only 'planned' variants are generated), audits each finished sub-domain for
cyan/green colour bias, exports .tres, and appends a JSONL report to build/.

Loops: iterates a finite snapshot of sub-domains; aborts after MAX_CONSECUTIVE_FAILURES
failed sub-domains in a row (ComfyUI down) instead of spinning.
"""

from __future__ import annotations

import argparse
import colorsys
import json
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

PACK_ID = "ancient_china_low_cultivation"
PACK_DIR = REPO_ROOT / "game/assets/packs" / PACK_ID
PACK_PATH = PACK_DIR / f"{PACK_ID}_pack.json"
RUNTIME_DIR = PACK_DIR / "runtime"
REPORT_PATH = REPO_ROOT / "build" / "low_cultivation_batch_report.jsonl"

MAX_CONSECUTIVE_FAILURES = 3
SUBDOMAIN_TIMEOUT_S = 4 * 3600
# Domains where cyan/green is naturally expected; thresholds are looser there.
COLD_OK_DOMAINS = {
    "water_and_springs",
    "flora_and_spirit_plants",
    "atmospheric_vfx_and_phenomena",
    "underwater_and_abyssal_realms",
    "underground_abyss_and_caverns",
    "elemental_sanctuaries_and_extremes",
}


def pending_subdomains(domain_filter: str | None) -> list[tuple[str, str, int]]:
    pack = json.loads(PACK_PATH.read_text(encoding="utf-8"))
    order: list[tuple[str, str]] = []
    counts: dict[tuple[str, str], int] = {}
    for asset in pack.get("assets", []):
        dom = asset.get("domain", "misc")
        sub = asset.get("sub_domain", "general")
        if domain_filter and dom != domain_filter:
            continue
        key = (dom, sub)
        if key not in counts:
            counts[key] = 0
            order.append(key)
        for var in asset.get("variants", []):
            if (var.get("status") or asset.get("status", "planned")) == "planned":
                counts[key] += 1
    return [(d, s, counts[(d, s)]) for d, s in order if counts[(d, s)] > 0]


def audit_colour(dom: str, sub: str) -> dict:
    files = sorted((RUNTIME_DIR / dom / sub).rglob("*.png"))
    cyan = green = blue = warm = neutral = total = 0
    for fp in files[:40]:
        try:
            from PIL import Image

            im = Image.open(fp).convert("RGBA")
        except Exception:
            continue
        w, h = im.size
        step = max(1, (w * h) // 400)
        px = im.load()
        for idx in range(0, w * h, step):
            r, g, b, a = px[idx % w, idx // w]
            if a < 32 or max(r, g, b) < 25:
                continue
            total += 1
            hh, s, _v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s < 0.15:
                neutral += 1
                continue
            deg = hh * 360
            if 160 <= deg < 200:
                cyan += 1
            elif 80 <= deg < 160:
                green += 1
            elif 200 <= deg < 260:
                blue += 1
            elif deg < 50 or deg >= 330:
                warm += 1
    pct = lambda n: round(n / total * 100, 1) if total else 0.0
    cyan_p, green_p, blue_p = pct(cyan), pct(green), pct(blue)
    loose = dom in COLD_OK_DOMAINS
    flag = cyan_p > (30 if loose else 12) or green_p > (30 if loose else 15) or blue_p > 65
    return {
        "files": len(files),
        "cyan": cyan_p,
        "green": green_p,
        "blue": blue_p,
        "warm": pct(warm),
        "neutral": pct(neutral),
        "flag": flag,
    }


def run(cmd: list[str], timeout: int) -> int:
    try:
        return subprocess.run(cmd, cwd=REPO_ROOT, timeout=timeout).returncode
    except subprocess.TimeoutExpired:
        print(f"TIMEOUT after {timeout}s: {' '.join(cmd)}")
        return 124


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--domain")
    ap.add_argument("--max-subdomains", type=int, default=5)
    args = ap.parse_args()

    todo = pending_subdomains(args.domain)[: max(1, args.max_subdomains)]
    print(f"Batch of {len(todo)} sub-domain(s): {[s for _, s, _ in todo]}")
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)

    consecutive_failures = 0
    for dom, sub, n_pending in todo:
        t0 = time.time()
        print(f"\n=== {dom}/{sub} ({n_pending} pending) ===", flush=True)
        rc = run(
            [
                "uv",
                "run",
                "python",
                "tools/generate_and_package_low_cultivation.py",
                "--sub-domain",
                sub,
                "--skip-import",
            ],
            SUBDOMAIN_TIMEOUT_S,
        )
        if rc != 0:
            consecutive_failures += 1
            print(f"generation rc={rc} (consecutive failures={consecutive_failures})")
            if consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
                print("Aborting: ComfyUI or pipeline is failing repeatedly.")
                return 1
            continue
        consecutive_failures = 0
        run(
            [
                "uv",
                "run",
                "python",
                "tools/export_cultivation_pack_tres.py",
                "--category",
                sub,
            ],
            600,
        )
        report = {"domain": dom, "sub_domain": sub, "seconds": round(time.time() - t0)}
        report.update(audit_colour(dom, sub))
        with REPORT_PATH.open("a", encoding="utf-8") as f:
            f.write(json.dumps(report) + "\n")
        print(f"AUDIT {json.dumps(report)}", flush=True)

    from tools.generate_and_package_low_cultivation import GAME_DIR, run_godot

    run_godot(
        ["--headless", "--editor", "--path", str(GAME_DIR), "--import", "--quit"],
        capture=True,
        tag="low-cultivation-import",
    )
    print("Batch complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
