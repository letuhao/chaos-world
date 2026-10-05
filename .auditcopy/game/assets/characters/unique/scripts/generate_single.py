#!/usr/bin/env python3
"""
Generate ONE image at a time with validation and prompt adjustment.

Usage:
  python scripts/generate_single.py --shot character_portrait --seed 103
  python scripts/generate_single.py --shot expression_01 --seed 200 --attempt 2

The agent should:
  1. Call this script for one shot
  2. Inspect the result visually
  3. If noise/artifacts, adjust the prompt and retry with --attempt N
  4. Only move to next shot after the current one passes
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate import generate, PROFILES

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "outputs"
COMFY_URL = "http://127.0.0.1:8188"
PROMPT_HISTORY = Path(__file__).resolve().parent.parent / "prompt_history.json"

# ── Background policy per shot ─────────────────────────────────────────────
# `tools art_fidelity` gates transparency, and the game installs figure assets on
# transparent PNGs. But RMBG strips the background from EVERY shot, which makes a
# written scene criterion physically impossible to satisfy (a circle of struck
# ground, a chamber, a graveside all vanish). So background is declared per shot
# rather than forced:
#   "figure"  -> background removed; the game-ready cutout. Default.
#   "scene"   -> background KEPT; the shot only means something with its setting.
# A scene shot is art direction, not a game-ready sprite, and is not installed.
BACKGROUND = {
    "map_sprite": "figure",
    "dialogue_portrait": "figure",
    "character_portrait": "figure",
    "concept_art": "figure",
    "expression": "figure",
    "pose": "figure",
    "daily_working": "figure",
    "daily_casual": "figure",
    # These carry their setting in the written criterion, so they keep it. They are
    # art direction, not installed game assets: art_fidelity's transparency gate
    # demands >=10% alpha, which a described ground plane or sky cannot satisfy.
    "environmental_concept": "scene",
    "relationship_scene": "scene",
    "combat_concept": "scene",
}

# ── Optional creative latitude ─────────────────────────────────────────────
# The repo's art_fidelity MANUAL_REVIEW items (apparent age, hair crop, flush,
# garment coverage, jewellery, pose bearing) have no reliable pixel proxy — each
# was measured and rejected by the repo's authors. They are therefore NOT gates
# and NOT retries: they are free creative latitude. We still name the intended
# trait so the model has something to aim at, but a render that reads 38 instead
# of 41, or wears a brass clasp, is an accepted variant and not a defect to
# chase. Only the GATING checks (palette, single subject, transparency, skin
# area) are ever a reason to re-render.
CREATIVE_LATITUDE_NOTE = (
    "optional creative latitude, not a gate: apparent age, hair crop, flush, "
    "garment coverage, jewellery and pose bearing are reviewed by a human and "
    "accepted as variants"
)

# Shot definitions with base prompts
SHOTS = {
    "map_sprite": {
        "profile": "map_sprite",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, full figure profile, small scale, game sprite, bare ash grey stone floor, pale jade dust, one plain ash grey instrument stand, no chalk colour, no metal shine, hands open at sides, weight even, silhouette readable, 256x256 token, flat even lighting, low contrast, compressed value range, mid-key tones, no rim light, no edge light, no backlight, no specular highlight, no glint, no shine, no bright spot, no blown highlight, no deep shadow, no dark hole, flat two-tone ink and wash, hard-edged matte colour blocks, poster-flat, no smooth gradient, no airbrushed shading, no soft blending, no tone between the shadow and the fill, the undyed wool travelling coat is one flat ash grey fill with solid ink brown shadow shapes, no olive, no khaki, no tan mid-tone, no mid-tone brown, no beige, the darkest tone in the frame is warm dark brown ink and never pure black, no crushed black, no dead black, lifted shadows, the palest tone in the frame is warm ivory and never white, no pure white, no white paper",
        "seed": 101,
    },
    "dialogue_portrait": {
        "profile": "dialogue",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, three-quarter turn, one hand lifted palm-up, flat professional gesture, no offering, no correction, no engagement, no kindness, waist-up, eye level, interior doorway, worn stone jamb, flat expression, even light",
        "seed": 102,
    },
    "character_portrait": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, head and shoulders, square to viewer, hands loose and visible, plain warm ivory field, flat expression, legible, shallow depth, upper-left light, neutral, unreadable",
        "seed": 103,
    },
    "concept_art": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, full body, head to toe, arms at sides, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, stony measurement yard, low platform, chalked baseline in pale jade chalk, patient, watching, flat two-tone ink and wash, hard-edged matte colour blocks, poster-flat, no smooth gradient, no airbrushed shading, no soft blending, no tone between the shadow and the fill, no olive, no khaki, no tan mid-tone, no mid-tone brown, the palest tone in the frame is warm ivory and never white, no pure white, no white paper, no blown-out white highlight, the darkest tone is ink brown and never pure black, no crushed black, no dead black",
        "seed": 104,
    },
    "environmental_concept": {
        "profile": "landscape",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, wide environmental shot, small in frame, instrument column, hands behind back, First Ward chamber, four seated imprints, three seats, architecture dominant, character secondary, attentive to instrument, the Mortal Plains rendered entirely in near-monochrome: ash grey dry grass, pale jade overcast sky, warm ivory horizon light, no green grass, no blue sky, stone and dust only",
        "seed": 105,
    },
    "combat_concept": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, low three-quarter angle, wide shot, small in frame, full ground plane, standing unbothered at the centre of a wide ring of struck ground, coat still buttoned, the Mortal Plains road outside the gate rendered entirely in near-monochrome: warm ivory dust ground, pale jade flat overcast sky, plain ash grey timber gate, ash grey and pale jade stone, no green grass, no blue sky, no brown earth, stone and dust only, the qi-work as flat ink brown scorch rings on the warm ivory dust, the scorch rings stop short of her boots, no flame, no fire, no orange, no glow, no smoke, untroubled, almost bored, flat even lighting, low contrast, compressed value range, mid-key tones, no rim light, no edge light, no backlight, no specular highlight, no glint, no shine, no bright spot, no blown highlight, no deep shadow, no dark hole, no jewellery, no pendant, no medallion, no brooch, no pin, no necklace, flat two-tone ink and wash, hard-edged matte colour blocks, poster-flat, no smooth gradient, no airbrushed shading, no soft blending, no tone between the shadow and the fill, nothing on her body is a mid-tone: every square centimetre of her is either dark ink brown #2A2520, ash grey #8A8580, pale jade #B8C4B0 or warm ivory #E8E0D0, and no fifth value exists anywhere on her, the travelling coat is a DARK coat, its field is ink brown #2A2520 with ash grey #8A8580 only as narrow lit edges along the shoulders and sleeve tops, most of the coat is the dark ink brown and never a warm mid-brown, no khaki, no olive, no tan, no beige, no taupe, no mud, no drab, no leather, no brown leather, no tan leather, no satchel, no pouch, no belt, no belt pouch, no buckle, no brass buckle, no strap, no sheath, no holster, no bandolier, no ornament of any kind, the only thing at her waist is a knotted plain cord, her boots are the darkest thing in the frame, solid ink brown #2A2520, no lit edge on the leather, no highlight on the boots, the darkest tone in the frame is warm dark brown ink and never pure black, no crushed black, no dead black, lifted shadows, the palest tone in the frame is warm ivory and never white, no pure white, no white paper",
        "seed": 106,
    },
    "relationship_scene": {
        "profile": "landscape",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, two-shot, reader's back to camera, graveside, reading slip of paper, held flat in both hands, shallow named grave, Mortal Plains, flat stone, no marker, reading aloud, flat, unhurried",
        "seed": 107,
    },
    "expression_01": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, close head and shoulders, head level, shoulders relaxed, looking straight out, plain warm ivory field, even light, composed, unreadable, neutral, waiting",
        "seed": 200,
    },
    "expression_02": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, waist-up, leaning in, chin lowered, looking at instrument dial, slight downward tilt, flat professional focus, eyes on reading, not on person, flat even shadowless lighting, low contrast, compressed value range, mid-key tones, no rim light, no edge light, no backlight, no specular highlight, no glint, no shine, no sheen, no bright spot, no blown highlight, no deep shadow, no dark hole, no jewellery, no pendant, no medallion, no brooch, no pin, no necklace, flat two-tone ink and wash, hard-edged matte colour blocks, poster-flat, no smooth gradient, no airbrushed shading, no soft blending, no tone between the shadow and the fill, the darkest tone in the frame is warm dark brown ink and never pure black, no crushed black, no dead black, lifted shadows, no olive, no khaki, no tan mid-tone, no mid-tone brown, the palest tone in the frame is warm ivory and never white, no pure white, no white paper",
        "seed": 201,
    },
    "expression_03": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, close head and shoulders, three-quarter turn, turned slightly away, one shoulder lifted, as if to leave, small hard courtesy, does not reach eyes, offered to hostile person, overcast light",
        "seed": 202,
    },
    "expression_04": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, close head and shoulders, shoulders down, head tipped back slightly, faint amusement, barely visible, not a real smile, not a laugh, no joy, no happiness, no delight, no charm, flat even light, plain warm ivory field",
        "seed": 203,
    },
    "expression_05": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, close head and shoulders, high angle looking down, upright, hands together in front, perfectly still, flat even light, flatly bored, ceremony, become weather, repressed, overcast light",
        "seed": 204,
    },
    "expression_06": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, close head and shoulders, low angle looking up, arm half-raised, other hand catching wrist, slight lean back, flinch, involuntary reflex, hand raised near skin, cannot train out, hard side light",
        "seed": 205,
    },
    "expression_07": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, close head and shoulders, chin down, brow faintly set, weight forward, concentration, reading runs, every other thought put away, light from upper left, flat even lighting, low contrast, compressed value range, mid-key tones, no rim light, no edge light, no backlight, no specular highlight, no glint, no shine, no bright spot, no blown highlight, no deep shadow, no dark hole, no jewellery, no pendant, no medallion, no brooch, no pin, no necklace, flat two-tone ink and wash, hard-edged matte colour blocks, poster-flat, no smooth gradient, no airbrushed shading, no soft blending, no tone between the shadow and the fill, the darkest tone in the frame is warm dark brown ink and never pure black, no crushed black, no dead black, lifted shadows, no olive, no khaki, no tan mid-tone, no mid-tone brown, the palest tone in the frame is warm ivory and never white, no pure white, no white paper",
        "seed": 206,
    },
    "expression_08": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, close head and shoulders, profile view, very still, hands loose, eyes forward and level, soft low light, grief held motionless, nothing moves that was not trained, internal",
        "seed": 207,
    },
    "expression_09": {
        "profile": "no-bg",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, waist-up, standing square, one hand holding folded slip, weariness, tiredness, no defiance, no strength, no determination, no resolve, flat even light, plain warm ivory field",
        "seed": 208,
    },
    "pose_01": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, full figure, standing perfectly still, doorway centred, crowd files past both sides, blurred motion, busy gate corridor, Mortal Plains, untroubled, eyes tracking nothing, still centre",
        "seed": 300,
    },
    "pose_02": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, full figure, seated cross-legged, low measurement platform, palms open flat on knees, plain measurement floor, chalked square, settled, waiting, comfortable in stillness",
        "seed": 301,
    },
    "pose_03": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, full figure profile, slow walk, not a stride, not a march, open yard, instrument carried in both hands, ground plane visible, boundary line chalked, no confidence, no purpose, no determination, no focus, even light, overcast sky",
        "seed": 302,
    },
    "pose_04": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, three-quarter rear, full figure, shoulders turned, back to camera, spine held straight, reader behind her, arms slightly away from body, calm compliance, chin turned, one eye on reader, bare measurement room, low bench",
        "seed": 303,
    },
    "pose_05": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, full figure, seated alone on open ground, knees drawn up, note folded in one hand, low camera angle, a flat stone marker in the dirt beside her, no other figure, no standing person, no second body, composed, speaking, reading finished, not yet put away, flat even lighting, low contrast, compressed value range, mid-key tones, no rim light, no edge light, no backlight, no specular highlight, no glint, no shine, no bright spot, no blown highlight, no deep shadow, no dark hole, no jewellery, no pendant, no medallion, no brooch, no pin, no necklace, flat two-tone ink and wash, hard-edged matte colour blocks, poster-flat, no smooth gradient, no airbrushed shading, no soft blending, no tone between the shadow and the fill, the undyed wool travelling coat is one flat ash grey fill with solid ink brown shadow shapes, no olive, no khaki, no tan mid-tone, no mid-tone brown, no beige, the darkest tone in the frame is warm dark brown ink and never pure black, no crushed black, no dead black, lifted shadows, the palest tone in the frame is warm ivory and never white, no pure white, no white paper",
        "seed": 304,
    },
    "pose_06": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, medium shot, standing under canopy, one hand flat on column, holding position, others argue, hall with open colonnade, scattered seats, listeners out of focus, patient, listening, unwilling to decide",
        "seed": 305,
    },
    "daily_romance": {
        "profile": "landscape",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, two-shot, standing near another person, no romantic tension, no intimacy, no attraction, flat professional interaction, reading a measurement, correcting a record, even light, plain warm ivory field, no warm light, no soft lighting",
        "seed": 401,
    },
    "daily_working": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, kneeling on the ground, calibrating a stone marker with a measuring tape, focused expression, instrument in hands, measurement yard",
        "seed": 402,
    },
    "daily_casual": {
        "profile": "fullbody",
        "prompt": "(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2), the kind of face you can't reconstruct from memory, 41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes, average build, not thin, not muscular, unremarkable proportions, ordinary face shape, unremarkable features, nothing striking, dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss, dark level steady eyes, no glow, no light reflection, no sparkle, ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup, undyed wool travelling coat, high-collared linen shift, cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking, no marks, no clan mark, no oath burn, no cultivation scarring, warm ivory, ash grey, pale jade, dull brass accent, painterly illustration, muted watercolour, ink and wash, desaturated, ink contours heavier than fill, line is the drawing and wash is the correction, not anime, not manga, not cel shaded, not digital painting, trained stillness, hands open and visible, standing where left standing, deliberately the least colourful person in any room, sitting on a rock, resting, looking out at the horizon, relaxed stillness, one hand on the rock, Mortal Plains landscape",
        "seed": 403,
    },
}


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate ONE image with validation")
    ap.add_argument("--shot", required=True, help="Shot name (e.g., character_portrait)")
    ap.add_argument("--seed", type=int, default=None, help="Override seed")
    ap.add_argument("--attempt", type=int, default=1, help="Attempt number")
    ap.add_argument("--prompt-file", help="File containing adjusted prompt (for re-generation)")
    args = ap.parse_args()

    if args.shot not in SHOTS:
        print(f"Unknown shot: {args.shot}")
        print(f"Available: {', '.join(SHOTS.keys())}")
        sys.exit(1)

    shot = SHOTS[args.shot]
    seed = args.seed if args.seed is not None else shot["seed"] + (args.attempt - 1) * 1000
    prompt = shot["prompt"]
    if args.prompt_file:
        prompt = Path(args.prompt_file).read_text(encoding="utf-8")

    # Fidelity lock — appended to every shot so one edit governs all of them.
    # `tools art_fidelity check` is GATING on palette containment (a dominant
    # colour further than 46 from every authored hex may cover <=1% of the frame)
    # and on single-subject. The threshold may only ever be tightened, so the
    # prompt has to carry the palette rather than the gate being widened.
    prompt = prompt + (
        ", strictly near-monochrome, warm ivory and ash grey and pale jade and "
        "dull brass are the ONLY colours anywhere in the frame, "
        "no pink, no red, no rosy cheeks, no blush, no blue, no green, no purple, "
        "no orange, no saturated colour, no colour variation, "
        "every pixel is warm ivory or ash grey or pale jade or dull brass or "
        "ink brown or skin tan, "
        "one subject only, a single figure, alone, no other people, no crowd, "
        "no background figures, no second subject, no duplicate figure"
    )

    output = OUTPUT_DIR / f"ilsa_{args.shot}.png"
    # Background is declared per shot, not forced. A "scene" shot keeps its
    # setting because its written criterion IS the setting; everything else is
    # background-removed for the game.
    shot_background = BACKGROUND.get(args.shot, "figure")
    # `generate(bg=...)` means "has a background", i.e. KEEP it. A figure shot is
    # background-removed, which is the opposite of keep_background.
    keep_background = shot_background == "scene"
    remove_bg = not keep_background
    print(f"Generating: {args.shot} (seed {seed}, attempt {args.attempt})")
    print(f"Output: {output}")
    print(f"Background: {shot_background} (remove_background={remove_bg})")
    print(f"Prompt length: {len(prompt)} chars")
    print()

    # Content safety negative prompt — universal for ALL characters (W7)
    # Suppresses EXPLICIT SEXUAL CONTENT only, NOT sexy/attractive characters
    # Sexy is fine (cultivation game has beautiful characters); explicit sex is not
    negative = (
        "explicit sexual content, sexual intercourse, orgasm, ejaculation, genitalia, "
        "penis, vagina, nipples, areola, exposed breasts, crotch, groin, "
        "pornographic, porn, erotica, hentai, NSFW extreme, "
        "sexualized minor, child sexual content, underage sexual content, "
        "rape, sexual violence, forced sex, "
        "fetish, BDSM, bondage, gimp, latex, leather fetish, "
        "urine, feces, vomit, scat, watersports"
    )

    try:
        generate(
            profile=shot["profile"],
            prompt=prompt,
            output=str(output),
            negative=negative,
            loras=[],
            ratio=None,
            bg=keep_background,
            seed=seed,
            comfy_url=COMFY_URL,
        )
        print(f"\n✓ Generated: {output}")
        print(f"  Size: {output.stat().st_size} bytes")
        print(f"\n  Agent: Inspect this image. If noise/artifacts, adjust prompt and retry with --attempt {args.attempt + 1}")
    except Exception as e:
        print(f"\n✗ FAIL: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
