#!/usr/bin/env python3
"""
Batch generate the nine-prompt visual set for Ilsa Renn (unique-0001).

v4 — All audit fixes applied:
  - Emphasis weighting (plain:1.4, unremarkable:1.3)
  - Age (41), build (average), face shape (ordinary), skin texture (weathered)
  - Varied framing for expressions (not all "close head and shoulders")
  - Varied framing for poses (not all "full figure")
  - Varied lighting across all 9 expressions
  - Stronger negative prompt (anime, age, body, hair, skin, expression, style, pose, clothing)
  - "painterly illustration" instead of "cultivation-fantasy-relic style"
  - Daily art shots with full criteria
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate import generate, PROFILES

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "outputs"
COMFY_URL = "http://127.0.0.1:8188"

# ── Universal Positive Prompt (v4 — strengthened) ─────────────────────────
# Emphasis weighting + age + build + face shape + skin texture + conceptual framing
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

# ── Universal Negative Prompt (v4 — expanded) ──────────────────────────────
NEGATIVE = (
    "beautiful, attractive, striking, memorable, gorgeous, pretty, cute, sexy, alluring, "
    "anime, anime style, manga, cel shaded, cel shading, big eyes, small nose, delicate features, "
    "smooth skin, symmetrical face, sharp jawline, high cheekbones, pointed chin, large head, small body, "
    "young, youthful, teenage, child, girl, maiden, under 30, "
    "slender, thin, petite, hourglass, curvy, busty, long legs, narrow waist, athletic, muscular, "
    "glossy hair, shiny hair, highlighted hair, streaked hair, layered hair, feathered hair, bangs, fringe, "
    "flowing hair, long hair, styled hair, hair ornament, hair accessory, "
    "perfect skin, flawless, luminous, translucent, creamy, porcelain, glowing skin, "
    "expressive, dramatic, emotional, intense, smoldering, seductive, inviting, alluring, "
    "trending on artstation, digital painting, concept art, fantasy art, game art, visual novel, dating sim, "
    "dynamic action, running, jumping, flying, fighting pose, heroic pose, power pose, contrapposto, s-curve, arched back, hip cocked, "
    "armour, weapon, ornate, decorative, livery, rank marking, revealing, tight, form-fitting, cleavage, midriff, "
    "magical glow, qi-sheen, cultivation aura, clan mark, oath burn, scar, tattoo, brand, mark, symbol, rune, sigil, "
    "ornate background, detailed background, busy background, scenic, landscape, sunset, dramatic lighting, "
    "bright colours, saturated, vibrant, colourful"
)

# ── Shot definitions (v4 — varied framing + lighting) ──────────────────────
SHOTS = [
    # 1. map_sprite
    {
        "name": "map_sprite",
        "profile": "sprite",
        "prompt": f"{POSITIVE}, full figure profile, small scale, game sprite, bare measurement floor, chalked square, instrument stand, hands open at sides, weight even, silhouette readable, 256x256 token, white background",
        "seed": 101,
    },
    # 2. dialogue_portrait
    {
        "name": "dialogue_portrait",
        "profile": "no-bg",
        "prompt": f"{POSITIVE}, three-quarter turn, one hand lifted palm-up, flat professional gesture, no offering, no correction, no engagement, no kindness, waist-up, eye level, interior doorway, worn stone jamb, flat expression, even light",
        "seed": 102,
    },
    # 3. character_portrait
    {
        "name": "character_portrait",
        "profile": "no-bg",
        "prompt": f"{POSITIVE}, head and shoulders, square to viewer, hands loose and visible, plain warm ivory field, flat expression, legible, shallow depth, upper-left light, neutral, unreadable",
        "seed": 103,
    },
    # 4. concept_art
    {
        "name": "concept_art",
        "profile": "fullbody",
        "prompt": f"{POSITIVE}, full body, head to toe, arms at sides, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, stony measurement yard, low platform, chalked baseline, patient, watching",
        "seed": 104,
    },
    # 5. environmental_concept
    {
        "name": "environmental_concept",
        "profile": "landscape",
        "prompt": f"{POSITIVE}, wide environmental shot, small in frame, instrument column, hands behind back, First Ward chamber, four seated imprints, three seats, architecture dominant, character secondary, attentive to instrument",
        "seed": 105,
    },
    # 6. combat_concept
    {
        "name": "combat_concept",
        "profile": "fullbody",
        "prompt": f"{POSITIVE}, low three-quarter angle, standing unbothered, circle of struck ground, coat still buttoned, road cut outside gate, scorched qi-work, flaring and dissipating, short of her, clear ground plane, untroubled, almost bored",
        "seed": 106,
    },
    # 7. relationship_scene
    {
        "name": "relationship_scene",
        "profile": "landscape",
        "prompt": f"{POSITIVE}, two-shot, reader's back to camera, graveside, reading slip of paper, held flat in both hands, shallow named grave, Mortal Plains, flat stone, no marker, reading aloud, flat, unhurried",
        "seed": 107,
    },
    # 8-16. expression_set — 9 expressions with VARIED framing + lighting
    *[
        {
            "name": f"expression_{i+1:02d}",
            "profile": "no-bg",
            "prompt": f"{POSITIVE}, {expr}",
            "seed": 200 + i,
        }
        for i, expr in enumerate([
            # 1. Neutral — close H&S, even light
            "close head and shoulders, head level, shoulders relaxed, looking straight out, plain warm ivory field, even light, composed, unreadable, neutral, waiting",
            # 2. Professional focus — waist-up, diffused light
            "waist-up, leaning in, chin lowered, looking at instrument dial, slight downward tilt, flat professional focus, eyes on reading, not on person, diffused light",
            # 3. Hard courtesy — three-quarter, overcast
            "close head and shoulders, three-quarter turn, turned slightly away, one shoulder lifted, as if to leave, small hard courtesy, does not reach eyes, offered to hostile person, overcast light",
            # 4. Genuine amusement — close H&S, flat even (NOT warm)
            "close head and shoulders, shoulders down, head tipped back slightly, faint amusement, barely visible, not a real smile, not a laugh, no joy, no happiness, no delight, no charm, flat even light, plain warm ivory field",
            # 5. Flat boredom — high angle, overcast
            "close head and shoulders, high angle looking down, upright, hands together in front, perfectly still, flat even light, flatly bored, ceremony, become weather, repressed, overcast light",
            # 6. The flinch — low angle, hard side light
            "close head and shoulders, low angle looking up, arm half-raised, other hand catching wrist, slight lean back, flinch, involuntary reflex, hand raised near skin, cannot train out, hard side light",
            # 7. Concentration — close H&S, upper left
            "close head and shoulders, chin down, brow faintly set, weight forward, concentration, reading runs, every other thought put away, light from upper left",
            # 8. Motionless grief — profile, soft low light
            "close head and shoulders, profile view, very still, hands loose, eyes forward and level, soft low light, grief held motionless, nothing moves that was not trained, internal",
            # 9. Weariness with defiance — waist-up, even light
            "waist-up, standing square, one hand holding folded slip, weariness, tiredness, no defiance, no strength, no determination, no resolve, flat even light, plain warm ivory field",
        ])
    ],
    # 17-22. pose_set — 6 poses with VARIED framing + camera angles
    *[
        {
            "name": f"pose_{i+1:02d}",
            "profile": "fullbody",
            "prompt": f"{POSITIVE}, {pose}",
            "seed": 300 + i,
        }
        for i, pose in enumerate([
            # 1. Doorway stillness — eye level, full figure
            "full figure, standing perfectly still, doorway centred, crowd files past both sides, blurred motion, busy gate corridor, Mortal Plains, untroubled, eyes tracking nothing, still centre",
            # 2. Seated cross-legged — slightly above, full figure
            "full figure, seated cross-legged, low measurement platform, palms open flat on knees, plain measurement floor, chalked square, settled, waiting, comfortable in stillness",
            # 3. Walking the line — profile, eye level
            "full figure profile, slow walk, not a stride, not a march, open yard, instrument carried in both hands, ground plane visible, boundary line chalked, no confidence, no purpose, no determination, no focus, even light, overcast sky",
            # 4. Back to reader — three-quarter rear, full figure
            "three-quarter rear, full figure, shoulders turned, back to camera, spine held straight, reader behind her, arms slightly away from body, calm compliance, chin turned, one eye on reader, bare measurement room, low bench",
            # 5. Seated at grave — low angle, full figure
            "full figure, seated on ground, beside filled grave, knees drawn up, note folded in one hand, low camera angle, grave mound, flat stone, composed, speaking, reading finished, not yet put away",
            # 6. Column patience — high angle, medium shot
            "medium shot, standing under canopy, one hand flat on column, holding position, others argue, hall with open colonnade, scattered seats, listeners out of focus, patient, listening, unwilling to decide",
        ])
    ],
    # 23. daily_art — romance scene (no romantic tension, flat professional)
    {
        "name": "daily_romance",
        "profile": "landscape",
        "prompt": f"{POSITIVE}, two-shot, standing near another person, no romantic tension, no intimacy, no attraction, flat professional interaction, reading a measurement, correcting a record, even light, plain warm ivory field, no warm light, no soft lighting",
        "seed": 401,
    },
    # 24. daily_art — working (calibrating)
    {
        "name": "daily_working",
        "profile": "fullbody",
        "prompt": f"{POSITIVE}, kneeling on the ground, calibrating a stone marker with a measuring tape, focused expression, instrument in hands, measurement yard",
        "seed": 402,
    },
    # 25. daily_art — casual (resting)
    {
        "name": "daily_casual",
        "profile": "fullbody",
        "prompt": f"{POSITIVE}, sitting on a rock, resting, looking out at the horizon, relaxed stillness, one hand on the rock, Mortal Plains landscape",
        "seed": 403,
    },
]


def main() -> None:
    import argparse
    ap = argparse.ArgumentParser(description="Batch generate Ilsa Renn assets")
    ap.add_argument("--only-failed", action="store_true", help="Only regenerate shots that don't exist or failed validation")
    args = ap.parse_args()

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    # Determine which shots to generate
    shots_to_generate = SHOTS
    if args.only_failed:
        shots_to_generate = []
        for shot in SHOTS:
            output = OUTPUT_DIR / f"ilsa_{shot['name']}.png"
            if not output.exists() or output.stat().st_size < 10000:
                shots_to_generate.append(shot)
        if not shots_to_generate:
            print("No failed shots to regenerate — all exist and are non-trivial.")
            return
        print(f"Regenerating {len(shots_to_generate)} failed shots...")
    
    total = len(shots_to_generate)
    print(f"Generating {total} images for Ilsa Renn (unique-0001) — v4 all audit fixes")
    print(f"Output: {OUTPUT_DIR}")
    print()

    succeeded = 0
    failed = 0
    gaps = []

    for i, shot in enumerate(shots_to_generate, 1):
        output = OUTPUT_DIR / f"ilsa_{shot['name']}.png"
        print(f"[{i}/{total}] {shot['name']} (seed {shot['seed']})...", end=" ", flush=True)
        try:
            generate(
                profile=shot["profile"],
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
            gaps.append((shot["name"], str(e)))

        if i < total:
            time.sleep(2)

    print()
    print(f"=== Summary ===")
    print(f"Succeeded: {succeeded}/{total}")
    print(f"Failed: {failed}/{total}")
    if gaps:
        print(f"\nGaps to fix:")
        for name, err in gaps:
            print(f"  - {name}: {err}")
    else:
        print("\nNo gaps — all shots generated successfully!")


if __name__ == "__main__":
    main()
