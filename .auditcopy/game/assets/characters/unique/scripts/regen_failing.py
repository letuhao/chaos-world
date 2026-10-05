#!/usr/bin/env python3
"""Regenerate the art_fidelity failures one shot at a time.

Uses the mandated single-shot loop: generate, then let the gate judge. The
palette/subject lock lives in generate_single.py so every shot carries it.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from generate_single import SHOTS  # noqa: E402

# Seeds are nudged per attempt so a retry explores rather than repeats.
BASE_ATTEMPT_SEED_OFFSET = 0

def failing() -> list[str]:
    out = subprocess.run(
        ["uv", "run", "python", "-m", "tools", "art_fidelity", "report"],
        cwd=REPO, capture_output=True, text=True,
    ).stdout
    names = []
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("[FAIL]"):
            fname = s.split()[1]
            names.append(fname)
    return names

REPO = Path(r"D:\Works\source\chaos-world")

# report prints the filename; map it back to the shot id.
def shot_for(fname: str) -> str | None:
    stem = Path(fname).stem
    return stem.replace("ilsa_", "")

if __name__ == "__main__":
    names = failing()
    shots = [s for s in (shot_for(n) for n in names) if s in SHOTS]
    print(f"failing: {len(shots)} -> {shots}\n")
    for s in shots:
        print(f"--- {s} ---")
        r = subprocess.run(
            [sys.executable, str(HERE / "generate_single.py"), "--shot", s],
            capture_output=True, text=True,
        )
        print(r.stdout.strip().splitlines()[-3] if r.stdout else r.stderr[-300:])