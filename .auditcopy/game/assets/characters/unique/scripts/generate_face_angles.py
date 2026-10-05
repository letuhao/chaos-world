#!/usr/bin/env python3
"""
Generate multi-angle face shots for Ilsa Renn (unique-0001).

These are input references for a 2-workflow combination:
  Workflow 1 (this): Generate face at multiple angles
  Workflow 2 (user-provided): Use face references to generate final character

Angles:
  front, three_quarter_left, three_quarter_right,
  profile_left, profile_right, rear,
  low_angle, high_angle
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate import generate, PROFILES

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "outputs" / "face_angles"
COMFY_URL = "http://127.0.0.1:8188"

# Universal positive prompt (v4 — strengthened)
POSITIVE = (
    "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), "
    "the kind of face you can't reconstruct from memory, "
    "an expression that would read identically on anyone standing here, "
    "41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, "
    "average build, not thin, not muscular, unremarkable proportions, "
    "ordinary face shape, unremarkable features, nothing striking, "
    "dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, "
    "dark level steady eyes, no glow, no light reflection, no sparkle, "
    "ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, "
    "undyed wool travelling coat, high-collared linen shift, "
    "cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, "
    "no marks, no clan mark, no oath burn, no cultivation scarring, "
    "warm ivory, ash grey, pale jade, dull brass accent, "
    "painterly illustration, muted watercolour, ink and wash, desaturated, "
    "ink contours heavier than fill, line is the drawing and wash is the correction, "
    "not anime, not manga, not cel shaded, not digital painting, "
    "trained stillness, hands open and visible, standing where left standing, "
    "deliberately the least colourful person in any room"
)

# Face angle shots
SHOTS = [
    {
        "name": "face_front",
        "prompt": f"{POSITIVE}, close head and shoulders, front view facing camera, head level, shoulders relaxed, looking straight out, plain warm ivory field, even light, composed, unreadable, neutral, waiting",
        "seed": 500,
    },
    {
        "name": "face_three_quarter_left",
        "prompt": f"{POSITIVE}, close head and shoulders, three-quarter view from left, head turned slightly left, looking straight out, plain warm ivory field, even light, composed, unreadable, neutral",
        "seed": 501,
    },
    {
        "name": "face_three_quarter_right",
        "prompt": f"{POSITIVE}, close head and shoulders, three-quarter view from right, head turned slightly right, looking straight out, plain warm ivory field, even light, composed, unreadable, neutral",
        "seed": 502,
    },
    {
        "name": "face_profile_left",
        "prompt": f"{POSITIVE}, close head and shoulders, profile view from left, head turned 90 degrees left, looking left, plain warm ivory field, even light, composed, unreadable, neutral",
        "seed": 503,
    },
    {
        "name": "face_profile_right",
        "prompt": f"{POSITIVE}, close head and shoulders, profile view from right, head turned 90 degrees right, looking right, plain warm ivory field, even light, composed, unreadable, neutral",
        "seed": 504,
    },
    {
        "name": "face_rear",
        "prompt": f"{POSITIVE}, close head and shoulders, rear view, back of head facing camera, plain warm ivory field, even light, composed, unreadable, neutral",
        "seed": 505,
    },
    {
        "name": "face_low_angle",
        "prompt": f"{POSITIVE}, close head and shoulders, low angle looking up at face, head level, shoulders relaxed, looking straight out, plain warm ivory field, even light, composed, unreadable, neutral",
        "seed": 506,
    },
    {
        "name": "face_high_angle",
        "prompt": f"{POSITIVE}, close head and shoulders, high angle looking down at face, head level, shoulders relaxed, looking straight out, plain warm ivory field, even light, composed, unreadable, neutral",
        "seed": 507,
    },
    {
        "name": "face_three_quarter_left_smile",
        "prompt": f"{POSITIVE}, close head and shoulders, three-quarter view from left, head turned slightly left, faint amusement, barely visible, not a real smile, not a laugh, no joy, no happiness, no delight, no charm, flat even light, plain warm ivory field",
        "seed": 508,
    },
    {
        "name": "face_three_quarter_right_frown",
        "prompt": f"{POSITIVE}, close head and shoulders, three-quarter view from right, head turned slightly right, weariness, tiredness, no defiance, no strength, no determination, no resolve, flat even light, plain warm ivory field",
        "seed": 509,
    },
]


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    total = len(SHOTS)
    print(f"Generating {total} face angle shots for Ilsa Renn (unique-0001)")
    print(f"Output: {OUTPUT_DIR}")
    print()

    succeeded = 0
    failed = 0

    for i, shot in enumerate(SHOTS, 1):
        output = OUTPUT_DIR / f"ilsa_{shot['name']}.png"
        print(f"[{i}/{total}] {shot['name']} (seed {shot['seed']})...", end=" ", flush=True)
        try:
            generate(
                profile="no-bg",
                prompt=shot["prompt"],
                output=str(output),
                loras=[],
                ratio=None,
                bg=False,
                seed=shot["seed"],
                comfy_url=COMFY_URL,
            )
            print("OK")
            succeeded += 1
        except Exception as e:
            print(f"FAIL: {e}")
            failed += 1

        if i < total:
            time.sleep(2)

    print()
    print(f"=== Summary ===")
    print(f"Succeeded: {succeeded}/{total}")
    print(f"Failed: {failed}/{total}")


if __name__ == "__main__":
    main()
