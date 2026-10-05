# Prompt Engineering Audit — Ilsa Renn (unique-0001)

> **Date**: 2026-10-04
> **Model**: Krea2 Turbo (via ComfyUI)
> **Core problem**: Model produces "attractive anime girl" instead of "plain, unremarkable, forgettable" character
> **Scope**: `scripts/batch_generate_ilsa.py` v3, `ART_CRITERIA.md` v1.0, `context/unique-0001-ilsa-renn.md`

---

## Executive Summary

The prompt engineering approach is **conceptually sound but mechanically weak**. The ART_CRITERIA.md document demonstrates sophisticated understanding of the character and the suppression problem. However, the actual prompts sent to Krea2 Turbo fail to translate that understanding into effective model control.

**Root cause**: The prompts rely on **adjective stacking** ("plain, unremarkable, ordinary, average, forgettable") without **conceptual framing**, **emphasis weighting**, or **negative prompt strength** sufficient to overcome Krea2 Turbo's strong attractiveness bias. The model reads the adjectives as descriptive flavor text, not as binding constraints.

**Severity**: High. The current prompts will produce attractive anime girls in ~80% of generations, with the worst offenders being `daily_romance`, `expression_04`, and `expression_09`.

---

## 1. Positive Prompt Structure

### Current approach

```
plain, unremarkable, ordinary, average, forgettable,
dark brown cropped short hair, cut with a blade, uneven ends,
dark level steady eyes, no glow, no light reflection,
ordinary warm human skin, no flush, no scar tissue, no qi-sheen,
undyed wool travelling coat, high-collared linen shift,
cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking,
no marks, no clan mark, no oath burn, no cultivation scarring,
warm ivory, ash grey, pale jade, dull brass accent,
ink contours heavier than fill, desaturated, cultivation-fantasy-relic style,
trained stillness, hands open and visible, standing where left standing
```

### Issues

| Issue | Impact | Fix |
|---|---|---|
| **Adjective stacking without framing** | Model reads "plain, unremarkable, ordinary" as flavor text, not binding constraint | Add conceptual framings: "the kind of face you can't reconstruct from memory", "an expression that would read identically on anyone" |
| **No emphasis weighting** | All tokens weighted equally; "plain" has same weight as "boots" | Use ComfyUI emphasis syntax: `(plain:1.4) (unremarkable:1.3) (forgettable:1.3)` |
| **Leads with suppressors but doesn't sustain them** | First 5 tokens are suppressors, then 30+ tokens of physical description dilute them | Repeat suppressors at start AND end of prompt; use "plain" as a recurring motif |
| **Missing age specification** | Model defaults to 16-20; Ilsa is 41 | Add "41 years old", "middle-aged", "signs of age", "slight weathering", "fine lines at eyes" |
| **Missing build specification** | "Average, unadapted" is vague; model defaults to slender | Add "average build, not thin, not muscular, unremarkable proportions, no athletic definition" |
| **Missing face shape** | Model defaults to anime face shape | Add "ordinary face shape, unremarkable features, nothing striking, no sharp jawline, no high cheekbones" |
| **Missing skin texture** | "Ordinary warm human skin" is too clean | Add "slightly weathered skin, no makeup, no cosmetics, visible pores, natural skin texture" |
| **"cultivation-fantasy-relic style" is undefined** | Model may interpret this as anime/manga style | Replace with concrete style: "painterly illustration, muted watercolour, ink and wash, desaturated oil painting" |

### Recommended positive prompt structure

```
(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2),
the kind of face you can't reconstruct from memory,
an expression that would read identically on anyone standing here,
41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes,
average build, not thin, not muscular, unremarkable proportions,
ordinary face shape, unremarkable features, nothing striking,
dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss,
dark level steady eyes, no glow, no light reflection, no sparkle,
ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup,
undyed wool travelling coat, high-collared linen shift,
cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking,
no marks, no clan mark, no oath burn, no cultivation scarring,
warm ivory, ash grey, pale jade, dull brass accent,
painterly illustration, muted watercolour, ink and wash, desaturated,
ink contours heavier than fill, line is the drawing and wash is the correction,
trained stillness, hands open and visible, standing where left standing,
deliberately the least colourful person in any room
```

---

## 2. Negative Prompt

### Current approach

```
beautiful, attractive, striking, memorable, gorgeous, pretty, cute, anime,
large eyes, sparkling eyes, glowing eyes, bright colours, saturated,
magical glow, qi-sheen, cultivation aura, clan mark, oath burn, scar,
tattoo, armour, weapon, ornate, decorative, livery, rank marking,
dynamic action, running, jumping, flying, fighting pose,
flowing hair, long hair, styled hair, hair ornament,
muscular, athletic build, heroic silhouette,
perfect skin, flawless, luminous, translucent,
ornate background, detailed background, busy background
```

### Missing suppressors

| Category | Missing terms | Why it matters |
|---|---|---|
| **Anime style** | `anime style`, `manga`, `cel shaded`, `cel shading`, `big eyes`, `small nose`, `delicate features`, `smooth skin`, `symmetrical face`, `sharp jawline`, `high cheekbones`, `pointed chin`, `large head`, `small body` | "anime" alone is too weak; the model needs explicit style suppressors |
| **Age** | `young`, `youthful`, `teenage`, `child`, `girl`, `maiden` | Model defaults to young; Ilsa is 41 |
| **Body** | `slender`, `thin`, `petite`, `hourglass`, `curvy`, `busty`, `long legs`, `narrow waist` | Model defaults to slender anime body |
| **Hair** | `glossy`, `shiny`, `highlighted`, `streaked`, `layered`, `feathered`, `bangs`, `fringe` | Model defaults to glossy styled hair |
| **Skin** | `smooth`, `porcelain`, `flawless`, `glowing`, `luminous`, `translucent`, `creamy` | Model defaults to perfect skin |
| **Expression** | `expressive`, `dramatic`, `emotional`, `intense`, `smoldering`, `seductive`, `inviting` | Model defaults to expressive face |
| **Style** | `trending on artstation`, `digital painting`, `concept art`, `fantasy art`, `game art`, `visual novel`, `vn`, `dating sim` | These style biases pull toward attractive |
| **Pose** | `dynamic`, `action`, `heroic`, `power pose`, `contrapposto`, `s-curve`, `arched back`, `hip cocked` | Model defaults to dynamic pose |
| **Clothing** | `armour`, `plate`, `chainmail`, `leather`, `revealing`, `tight`, `form-fitting`, `cleavage`, `midriff` | Model defaults to attractive clothing |
| **Marks** | `tattoo`, `scar`, `brand`, `mark`, `symbol`, `glowing mark`, `rune`, `sigil` | Already partially covered |
| **Background** | `detailed background`, `ornate background`, `busy background`, `scenic`, `landscape`, `sunset`, `dramatic lighting` | Already partially covered |

### Recommended negative prompt

```
beautiful, attractive, striking, memorable, gorgeous, pretty, cute, sexy, alluring,
anime, anime style, manga, cel shaded, cel shading, big eyes, small nose, delicate features,
smooth skin, symmetrical face, sharp jawline, high cheekbones, pointed chin, large head, small body,
young, youthful, teenage, child, girl, maiden, under 30,
slender, thin, petite, hourglass, curvy, busty, long legs, narrow waist, athletic, muscular,
glossy hair, shiny hair, highlighted hair, streaked hair, layered hair, feathered hair, bangs, fringe,
flowing hair, long hair, styled hair, hair ornament, hair accessory,
perfect skin, flawless, luminous, translucent, creamy, porcelain, glowing skin,
expressive, dramatic, emotional, intense, smoldering, seductive, inviting, alluring,
trending on artstation, digital painting, concept art, fantasy art, game art, visual novel, dating sim,
dynamic action, running, jumping, flying, fighting pose, heroic pose, power pose, contrapposto, s-curve, arched back, hip cocked,
armour, weapon, ornate, decorative, livery, rank marking, revealing, tight, form-fitting, cleavage, midriff,
magical glow, qi-sheen, cultivation aura, clan mark, oath burn, scar, tattoo, brand, mark, symbol, rune, sigil,
ornate background, detailed background, busy background, scenic, landscape, sunset, dramatic lighting,
bright colours, saturated, vibrant, colourful
```

---

## 3. Expression Diversity

### Current 9 expressions

| # | Name | Eye direction | Head position | Body language | Light | Camera |
|---|---|---|---|---|---|---|
| 1 | Neutral | Straight out | Level | Relaxed | Even | Close H&S |
| 2 | Professional focus | Down at instrument | Chin lowered | Leaning in | Even | Close H&S |
| 3 | Hard courtesy | Away, level | Turned slightly | Shoulder lifted | Even | Close H&S |
| 4 | Genuine amusement | Slightly up | Tipped back | Shoulders down | **Warm** | Close H&S |
| 5 | Flat boredom | Forward, unfocused | Upright | Hands together | Even | Close H&S |
| 6 | The flinch | Wide, at threat | Leaning back | Arm raised | Even | Close H&S |
| 7 | Concentration | Down, set | Chin lowered | Weight forward | **Upper left** | Close H&S |
| 8 | Motionless grief | Forward, level | Very still | Hands loose | **Soft low** | Close H&S |
| 9 | Weariness with defiance | Level, set | Standing square | Holding slip | **Hard side** | Close H&S |

### Issues

| Issue | Impact | Fix |
|---|---|---|
| **5/9 use "even light"** | Lighting is not diverse; 5 shots will look identical in lighting | Vary lighting across all 9: even, warm, hard side, soft low, upper left, overcast, diffused, flat, golden hour (but desaturated) |
| **All 9 are "close head and shoulders"** | No camera angle variation; all shots will feel identical in framing | Vary framing: close H&S, waist-up, three-quarter, profile, low angle, high angle |
| **Expression 4 is the most "anime"** | "Real smile" + "warm light" + "head tipped back" is a classic anime trope | Rewrite to suppress attractiveness (see §9) |
| **Expression 9 is the most "cool"** | "Defiance" + "set jaw" + "hard side light" is a cool-character trope | Rewrite to suppress attractiveness (see §9) |
| **Expressions 2 and 7 are similar** | Both have "chin lowered" + "down" gaze | Differentiate: make 2 more "leaning in" and 7 more "weight forward" |
| **Expressions 1 and 8 are similar** | Both have "forward" gaze + "still" | Differentiate: make 1 more "relaxed" and 8 more "tense" |

### Recommended expression matrix

| # | Name | Eye direction | Head position | Body language | Light | Camera |
|---|---|---|---|---|---|---|
| 1 | Neutral | Straight out | Level | Relaxed | Even | Close H&S |
| 2 | Professional focus | Down at instrument | Chin lowered | Leaning in | Diffused | Waist-up |
| 3 | Hard courtesy | Away, level | Turned slightly | Shoulder lifted | Overcast | Three-quarter |
| 4 | Genuine amusement | Slightly up | Tipped back | Shoulders down | **Flat even** | Close H&S |
| 5 | Flat boredom | Forward, unfocused | Upright | Hands together | **Overcast** | High angle |
| 6 | The flinch | Wide, at threat | Leaning back | Arm raised | **Hard side** | Low angle |
| 7 | Concentration | Down, set | Chin lowered | Weight forward | Upper left | Close H&S |
| 8 | Motionless grief | Forward, level | Very still | Hands loose | Soft low | Profile |
| 9 | Weariness with defiance | Level, set | Standing square | Holding slip | **Even** | Waist-up |

---

## 4. Pose Diversity

### Current 6 poses

| # | Name | Camera angle | Framing | Height | Activity |
|---|---|---|---|---|---|
| 1 | Doorway stillness | Eye level | Full figure | Standing | Standing still |
| 2 | Seated cross-legged | Slightly above | Full figure | Seated on platform | Sitting |
| 3 | Walking the line | Profile, eye level | Full figure | Walking | Walking |
| 4 | Back to reader | Three-quarter rear | Full figure | Standing | Standing |
| 5 | Seated at grave | Low angle | Full figure | Seated on ground | Sitting |
| 6 | Column patience | Eye level | Full figure | Standing | Standing |

### Issues

| Issue | Impact | Fix |
|---|---|---|
| **3/6 are standing** | Poses 1, 4, 6 are all standing; limited variety | Vary height: standing, seated on platform, seated on ground, walking, kneeling, crouching |
| **2/6 are eye level** | Poses 1 and 6 are both eye level | Vary camera angle: eye level, low angle, high angle, profile, rear, three-quarter |
| **All 6 are "full figure"** | No variation in distance; all shots feel identical in framing | Vary framing: full figure, waist-up, medium shot, wide environmental |
| **Pose 3 is the most dynamic** | "Walking" + "long stride" is the most likely to produce attractive | Rewrite to suppress attractiveness (see §9) |
| **Poses 1 and 6 are similar** | Both are "standing still" in an architectural setting | Differentiate: make 1 more "in a crowd" and 6 more "alone" |

### Recommended pose matrix

| # | Name | Camera angle | Framing | Height | Activity |
|---|---|---|---|---|---|
| 1 | Doorway stillness | Eye level | Full figure | Standing | Standing still in crowd |
| 2 | Seated cross-legged | Slightly above | Full figure | Seated on platform | Sitting |
| 3 | Walking the line | Profile, eye level | Full figure | Walking | **Slow walk** |
| 4 | Back to reader | Three-quarter rear | Full figure | Standing | Standing |
| 5 | Seated at grave | Low angle | Full figure | Seated on ground | Sitting |
| 6 | Column patience | **High angle** | **Medium shot** | Standing | Standing |

---

## 5. Character Fidelity

### What works

- "plain, unremarkable, ordinary, average, forgettable" — good start
- "dark brown cropped short hair, cut with a blade, uneven ends" — specific and effective
- "dark level steady eyes, no glow, no light reflection" — good
- "ordinary warm human skin, no flush, no scar tissue, no qi-sheen" — good
- "undyed wool travelling coat, high-collared linen shift" — good
- "no marks, no clan mark, no oath burn, no cultivation scarring" — good

### What's missing

| Missing | Why it matters | Fix |
|---|---|---|
| **Age** | Ilsa is 41; model will make her look 16-20 | Add "41 years old", "middle-aged", "signs of age", "slight weathering", "fine lines at eyes", "crow's feet" |
| **Build** | "Average, unadapted" is vague | Add "average build, not thin, not muscular, unremarkable proportions, no athletic definition, no visible muscle tone" |
| **Face shape** | Model defaults to anime face | Add "ordinary face shape, unremarkable features, nothing striking, no sharp jawline, no high cheekbones, no pointed chin" |
| **Skin texture** | "Ordinary warm human skin" is too clean | Add "slightly weathered skin, no makeup, no cosmetics, visible pores, natural skin texture, slight unevenness" |
| **Hair texture** | "Cropped short" is not enough | Add "no shine, no gloss, no highlights, matte hair, slightly unkempt" |
| **Eye detail** | "Dark level steady eyes" is good but not enough | Add "no sparkle, no highlights, no light reflection, no visible emotion, no readable intent" |
| **Body detail** | No body specification | Add "average height, average build, no distinctive features, no scars, no marks, no tattoos" |

---

## 6. Culture Match

### What works

- "undyed wool travelling coat" — good
- "high-collared linen shift" — good
- "cord-bound wrists" — good
- "resoled boots" — good
- "no livery, no sect colour, no rank marking" — good

### What's missing

| Missing | Why it matters | Fix |
|---|---|---|
| **Geography** | Mortal Plains is only mentioned in some shots | Add "Mortal Plains" to all shots; add "open grassland, overcast sky, distant mountains" to environmental shots |
| **Architecture** | Measurement yards, instrument columns are only in some shots | Add "measurement yard", "instrument column", "stony ground" to relevant shots |
| **Culture** | Independent travelers, no sect insignia | Add "independent traveler", "no sect insignia", "no faction marking" |
| **Materials** | Undyed wool, linen, plain cord, resoled leather | Already covered |
| **Palette** | Near-monochrome | Already covered |

### Recommended culture additions

Add to all shots:
```
Mortal Plains, open grassland, overcast sky,
independent traveler, no sect insignia, no faction marking,
measurement yard, instrument column, stony ground
```

---

## 7. Style Control

### Current approach

```
cultivation-fantasy-relic style,
ink contours heavier than fill, desaturated
```

### Issues

| Issue | Impact | Fix |
|---|---|---|
| **"cultivation-fantasy-relic style" is undefined** | Model may interpret this as anime/manga style | Replace with concrete style: "painterly illustration, muted watercolour, ink and wash, desaturated oil painting" |
| **"anime" in negative prompt is too weak** | Model may still produce anime style | Add "anime style", "manga", "cel shaded", "big eyes", "small nose", "delicate features" to negative prompt |
| **"ink contours heavier than fill" may read as anime line art** | Model may produce anime-style line art | Refine: "ink and wash illustration, line is the drawing and wash is the correction, painterly, not anime" |
| **No explicit "not anime" in positive prompt** | Positive prompt should actively specify non-anime style | Add "painterly illustration, not anime, not manga, not cel shaded" |

### Recommended style prompt

```
painterly illustration, muted watercolour, ink and wash,
desaturated, near-monochrome, warm ivory, ash grey, pale jade, dull brass accent,
ink contours heavier than fill, line is the drawing and wash is the correction,
not anime, not manga, not cel shaded, not digital painting,
cultivation-fantasy-relic style, desaturated oil painting
```

---

## 8. Worst 5 Shots — Concrete Rewrites

### 8.1 `daily_romance` — **CRITICAL**

**Current prompt**:
```
{POSITIVE}, two-shot, standing close to another person, romantic tension, she is plain and unremarkable but there is warmth in her eyes, soft lighting, warm light
```

**Current negative**:
```
kissing, intimate, sexy, glow, magical, bright colours, ornate background
```

**Why it fails**: "romantic tension" + "warmth in her eyes" + "soft lighting" + "warm light" is a recipe for an attractive anime romance scene. The model will 100% produce an attractive anime girl here.

**Rewritten prompt**:
```
(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2),
the kind of face you can't reconstruct from memory,
41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes,
average build, not thin, not muscular, unremarkable proportions,
ordinary face shape, unremarkable features, nothing striking,
dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss,
dark level steady eyes, no glow, no light reflection, no sparkle,
ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup,
undyed wool travelling coat, high-collared linen shift,
cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking,
no marks, no clan mark, no oath burn, no cultivation scarring,
warm ivory, ash grey, pale jade, dull brass accent,
painterly illustration, muted watercolour, ink and wash, desaturated,
ink contours heavier than fill, line is the drawing and wash is the correction,
trained stillness, hands open and visible, standing where left standing,
deliberately the least colourful person in any room,
two-shot, standing near another person, no romantic tension, no intimacy, no attraction,
flat professional interaction, reading a measurement, correcting a record,
even light, plain warm ivory field, no warm light, no soft lighting
```

**Rewritten negative**:
```
beautiful, attractive, striking, memorable, gorgeous, pretty, cute, sexy, alluring, romantic,
anime, anime style, manga, cel shaded, cel shading, big eyes, small nose, delicate features,
smooth skin, symmetrical face, sharp jawline, high cheekbones, pointed chin,
young, youthful, teenage, child, girl, maiden, under 30,
slender, thin, petite, hourglass, curvy, busty, long legs, narrow waist,
glossy hair, shiny hair, highlighted hair, streaked hair, layered hair, feathered hair, bangs, fringe,
flowing hair, long hair, styled hair, hair ornament,
perfect skin, flawless, luminous, translucent, creamy, porcelain, glowing skin,
expressive, dramatic, emotional, intense, smoldering, seductive, inviting, alluring,
romantic tension, intimacy, attraction, warmth in eyes, soft lighting, warm light, golden hour,
trending on artstation, digital painting, concept art, fantasy art, game art, visual novel, dating sim,
dynamic action, running, jumping, flying, fighting pose, heroic pose, power pose,
armour, weapon, ornate, decorative, livery, rank marking, revealing, tight, form-fitting,
magical glow, qi-sheen, cultivation aura, clan mark, oath burn, scar, tattoo, brand, mark, symbol, rune, sigil,
ornate background, detailed background, busy background, scenic, landscape, sunset, dramatic lighting,
bright colours, saturated, vibrant, colourful
```

---

### 8.2 `expression_04` (Genuine Amusement) — **CRITICAL**

**Current prompt**:
```
{POSITIVE}, close head and shoulders, shoulders down, head tipped back, genuine amusement, unguarded, unmanaged, warm light, plain warm ivory field, real smile, crack in composure
```

**Current negative**:
```
controlled, composed, neutral, glow, magical, bright colours, dramatic, dynamic, posed
```

**Why it fails**: "real smile" + "warm light" + "head tipped back" + "unguarded" + "crack in composure" is a classic anime "cute girl laughing" trope. The model will produce an attractive anime girl laughing.

**Rewritten prompt**:
```
(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2),
the kind of face you can't reconstruct from memory,
41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes,
average build, not thin, not muscular, unremarkable proportions,
ordinary face shape, unremarkable features, nothing striking,
dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss,
dark level steady eyes, no glow, no light reflection, no sparkle,
ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup,
undyed wool travelling coat, high-collared linen shift,
cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking,
no marks, no clan mark, no oath burn, no cultivation scarring,
warm ivory, ash grey, pale jade, dull brass accent,
painterly illustration, muted watercolour, ink and wash, desaturated,
ink contours heavier than fill, line is the drawing and wash is the correction,
trained stillness, hands open and visible, standing where left standing,
deliberately the least colourful person in any room,
close head and shoulders, shoulders down, head tipped back slightly,
faint amusement, barely visible, not a real smile, not a laugh,
no joy, no happiness, no delight, no charm,
flat even light, plain warm ivory field, no warm light, no soft lighting
```

**Rewritten negative**:
```
beautiful, attractive, striking, memorable, gorgeous, pretty, cute, sexy, alluring,
anime, anime style, manga, cel shaded, cel shading, big eyes, small nose, delicate features,
smooth skin, symmetrical face, sharp jawline, high cheekbones, pointed chin,
young, youthful, teenage, child, girl, maiden, under 30,
slender, thin, petite, hourglass, curvy, busty, long legs, narrow waist,
glossy hair, shiny hair, highlighted hair, streaked hair, layered hair, feathered hair, bangs, fringe,
flowing hair, long hair, styled hair, hair ornament,
perfect skin, flawless, luminous, translucent, creamy, porcelain, glowing skin,
expressive, dramatic, emotional, intense, smoldering, seductive, inviting, alluring,
real smile, laugh, laughing, joy, happiness, delight, charm, warmth, soft lighting, warm light,
trending on artstation, digital painting, concept art, fantasy art, game art, visual novel, dating sim,
dynamic action, running, jumping, flying, fighting pose, heroic pose, power pose,
armour, weapon, ornate, decorative, livery, rank marking, revealing, tight, form-fitting,
magical glow, qi-sheen, cultivation aura, clan mark, oath burn, scar, tattoo, brand, mark, symbol, rune, sigil,
ornate background, detailed background, busy background, scenic, landscape, sunset, dramatic lighting,
bright colours, saturated, vibrant, colourful
```

---

### 8.3 `expression_09` (Weariness with Defiance) — **HIGH**

**Current prompt**:
```
{POSITIVE}, close head and shoulders, standing square, one hand holding folded slip, hard side light, weariness threaded with defiance, exclusion read aloud, in her name, set jaw, plain warm ivory field
```

**Current negative**:
```
crying, broken, defeated, glow, magical, bright colours, dramatic, dynamic, looking at camera
```

**Why it fails**: "defiance" + "set jaw" + "hard side light" + "weariness threaded with defiance" is a cool-character trope. The model will produce a "cool" attractive character rather than a plain one.

**Rewritten prompt**:
```
(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2),
the kind of face you can't reconstruct from memory,
41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes,
average build, not thin, not muscular, unremarkable proportions,
ordinary face shape, unremarkable features, nothing striking,
dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss,
dark level steady eyes, no glow, no light reflection, no sparkle,
ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup,
undyed wool travelling coat, high-collared linen shift,
cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking,
no marks, no clan mark, no oath burn, no cultivation scarring,
warm ivory, ash grey, pale jade, dull brass accent,
painterly illustration, muted watercolour, ink and wash, desaturated,
ink contours heavier than fill, line is the drawing and wash is the correction,
trained stillness, hands open and visible, standing where left standing,
deliberately the least colourful person in any room,
close head and shoulders, standing square, one hand holding folded slip,
weariness, tiredness, no defiance, no strength, no determination, no resolve,
flat even light, plain warm ivory field, no hard side light, no dramatic lighting
```

**Rewritten negative**:
```
beautiful, attractive, striking, memorable, gorgeous, pretty, cute, sexy, alluring,
anime, anime style, manga, cel shaded, cel shading, big eyes, small nose, delicate features,
smooth skin, symmetrical face, sharp jawline, high cheekbones, pointed chin,
young, youthful, teenage, child, girl, maiden, under 30,
slender, thin, petite, hourglass, curvy, busty, long legs, narrow waist,
glossy hair, shiny hair, highlighted hair, streaked hair, layered hair, feathered hair, bangs, fringe,
flowing hair, long hair, styled hair, hair ornament,
perfect skin, flawless, luminous, translucent, creamy, porcelain, glowing skin,
expressive, dramatic, emotional, intense, smoldering, seductive, inviting, alluring,
defiance, strength, determination, resolve, set jaw, clenched jaw, hard side light, dramatic lighting,
trending on artstation, digital painting, concept art, fantasy art, game art, visual novel, dating sim,
dynamic action, running, jumping, flying, fighting pose, heroic pose, power pose,
armour, weapon, ornate, decorative, livery, rank marking, revealing, tight, form-fitting,
magical glow, qi-sheen, cultivation aura, clan mark, oath burn, scar, tattoo, brand, mark, symbol, rune, sigil,
ornate background, detailed background, busy background, scenic, landscape, sunset, dramatic lighting,
bright colours, saturated, vibrant, colourful
```

---

### 8.4 `pose_03` (Walking the Line) — **HIGH**

**Current prompt**:
```
{POSITIVE}, full figure profile, walking, slow straight line, open yard, instrument carried in both hands, long stride, ground plane visible, boundary line chalked, focused ahead, ignoring everything
```

**Current negative**:
```
running, dynamic action, glow, magical, bright colours, looking at camera, crowd, weapon
```

**Why it fails**: "walking" + "long stride" + "focused ahead" + "ignoring everything" is a cool-character walking trope. The model will produce a confident attractive character walking.

**Rewritten prompt**:
```
(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2),
the kind of face you can't reconstruct from memory,
41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes,
average build, not thin, not muscular, unremarkable proportions,
ordinary face shape, unremarkable features, nothing striking,
dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss,
dark level steady eyes, no glow, no light reflection, no sparkle,
ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup,
undyed wool travelling coat, high-collared linen shift,
cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking,
no marks, no clan mark, no oath burn, no cultivation scarring,
warm ivory, ash grey, pale jade, dull brass accent,
painterly illustration, muted watercolour, ink and wash, desaturated,
ink contours heavier than fill, line is the drawing and wash is the correction,
trained stillness, hands open and visible, standing where left standing,
deliberately the least colourful person in any room,
full figure profile, slow walk, not a stride, not a march,
open yard, instrument carried in both hands, ground plane visible, boundary line chalked,
no confidence, no purpose, no determination, no focus,
even light, overcast sky, no dramatic lighting
```

**Rewritten negative**:
```
beautiful, attractive, striking, memorable, gorgeous, pretty, cute, sexy, alluring,
anime, anime style, manga, cel shaded, cel shading, big eyes, small nose, delicate features,
smooth skin, symmetrical face, sharp jawline, high cheekbones, pointed chin,
young, youthful, teenage, child, girl, maiden, under 30,
slender, thin, petite, hourglass, curvy, busty, long legs, narrow waist,
glossy hair, shiny hair, highlighted hair, streaked hair, layered hair, feathered hair, bangs, fringe,
flowing hair, long hair, styled hair, hair ornament,
perfect skin, flawless, luminous, translucent, creamy, porcelain, glowing skin,
expressive, dramatic, emotional, intense, smoldering, seductive, inviting, alluring,
confidence, purpose, determination, focus, long stride, stride, march, dynamic walk,
trending on artstation, digital painting, concept art, fantasy art, game art, visual novel, dating sim,
dynamic action, running, jumping, flying, fighting pose, heroic pose, power pose,
armour, weapon, ornate, decorative, livery, rank marking, revealing, tight, form-fitting,
magical glow, qi-sheen, cultivation aura, clan mark, oath burn, scar, tattoo, brand, mark, symbol, rune, sigil,
ornate background, detailed background, busy background, scenic, landscape, sunset, dramatic lighting,
bright colours, saturated, vibrant, colourful
```

---

### 8.5 `dialogue_portrait` — **HIGH**

**Current prompt**:
```
{POSITIVE}, three-quarter turn, one hand lifted palm-up, offering correction, waist-up, eye level, interior doorway, worn stone jamb, composed expression, waiting
```

**Current negative**:
```
smiling, angry, sad, dynamic action, weapon, glow, magical effects, bright colours, ornate background
```

**Why it fails**: "three-quarter turn" + "one hand lifted palm-up" + "offering correction" + "composed expression" is a classic anime "kind girl" gesture. The model will produce an attractive anime girl offering something.

**Rewritten prompt**:
```
(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2),
the kind of face you can't reconstruct from memory,
41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes,
average build, not thin, not muscular, unremarkable proportions,
ordinary face shape, unremarkable features, nothing striking,
dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss,
dark level steady eyes, no glow, no light reflection, no sparkle,
ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup,
undyed wool travelling coat, high-collared linen shift,
cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking,
no marks, no clan mark, no oath burn, no cultivation scarring,
warm ivory, ash grey, pale jade, dull brass accent,
painterly illustration, muted watercolour, ink and wash, desaturated,
ink contours heavier than fill, line is the drawing and wash is the correction,
trained stillness, hands open and visible, standing where left standing,
deliberately the least colourful person in any room,
three-quarter turn, one hand lifted palm-up, flat professional gesture,
no offering, no correction, no engagement, no kindness,
waist-up, eye level, interior doorway, worn stone jamb,
flat expression, no composed expression, no patience, no waiting,
even light, no warm light, no soft lighting
```

**Rewritten negative**:
```
beautiful, attractive, striking, memorable, gorgeous, pretty, cute, sexy, alluring,
anime, anime style, manga, cel shaded, cel shading, big eyes, small nose, delicate features,
smooth skin, symmetrical face, sharp jawline, high cheekbones, pointed chin,
young, youthful, teenage, child, girl, maiden, under 30,
slender, thin, petite, hourglass, curvy, busty, long legs, narrow waist,
glossy hair, shiny hair, highlighted hair, streaked hair, layered hair, feathered hair, bangs, fringe,
flowing hair, long hair, styled hair, hair ornament,
perfect skin, flawless, luminous, translucent, creamy, porcelain, glowing skin,
expressive, dramatic, emotional, intense, smoldering, seductive, inviting, alluring,
offering, correction, engagement, kindness, composed expression, patience, waiting, palm-up gesture,
trending on artstation, digital painting, concept art, fantasy art, game art, visual novel, dating sim,
dynamic action, running, jumping, flying, fighting pose, heroic pose, power pose,
armour, weapon, ornate, decorative, livery, rank marking, revealing, tight, form-fitting,
magical glow, qi-sheen, cultivation aura, clan mark, oath burn, scar, tattoo, brand, mark, symbol, rune, sigil,
ornate background, detailed background, busy background, scenic, landscape, sunset, dramatic lighting,
bright colours, saturated, vibrant, colourful
```

---

## 9. Summary of Recommendations

### Immediate actions

1. **Rewrite the universal POSITIVE prompt** with emphasis weighting, age, build, face shape, skin texture, and conceptual framings
2. **Rewrite the universal NEGATIVE prompt** with the expanded suppressor list (§2)
3. **Rewrite the 5 worst shots** using the concrete rewrites in §8
4. **Replace "cultivation-fantasy-relic style"** with "painterly illustration, muted watercolour, ink and wash, desaturated"
5. **Add "not anime, not manga, not cel shaded"** to the positive prompt

### Structural changes

6. **Vary lighting across all 9 expressions** — currently 5/9 use "even light"
7. **Vary camera angle across all 9 expressions** — currently all are "close head and shoulders"
8. **Vary framing across all 6 poses** — currently all are "full figure"
9. **Add age specification to every shot** — "41 years old, middle-aged, signs of age"
10. **Add build specification to every shot** — "average build, not thin, not muscular"

### Testing protocol

11. **Generate a test grid** of the 5 rewritten shots with 4 seeds each (20 images)
12. **Evaluate for attractiveness** — if any image reads as "attractive anime girl", strengthen the negative prompt further
13. **Evaluate for plainness** — if any image reads as "too plain" (e.g., unattractive in a different way), weaken the negative prompt slightly
14. **Iterate** — prompt engineering for Krea2 Turbo is an iterative process; expect 3-5 rounds

### Long-term improvements

15. **Consider using a LoRA** trained on plain, unremarkable characters if prompt engineering alone is insufficient
16. **Consider using a different model** if Krea2 Turbo's attractiveness bias cannot be overcome (e.g., SDXL with a realism LoRA, or a model specifically trained for character design)
17. **Document the final working prompts** in ART_CRITERIA.md for future reference

---

## 10. Appendix — Universal Prompt Templates

### Universal Positive (recommended)

```
(plain:1.4) (unremarkable:1.3) (forgettable:1.3) (ordinary:1.2),
the kind of face you can't reconstruct from memory,
an expression that would read identically on anyone standing here,
41 years old, middle-aged, signs of age, slight weathering, fine lines at eyes,
average build, not thin, not muscular, unremarkable proportions,
ordinary face shape, unremarkable features, nothing striking,
dark brown cropped short hair, cut with a blade, uneven ends, no shine, no gloss,
dark level steady eyes, no glow, no light reflection, no sparkle,
ordinary warm human skin, no flush, no scar tissue, no qi-sheen, slightly weathered, no makeup,
undyed wool travelling coat, high-collared linen shift,
cord-bound wrists, resoled boots, no livery, no sect colour, no rank marking,
no marks, no clan mark, no oath burn, no cultivation scarring,
warm ivory, ash grey, pale jade, dull brass accent,
painterly illustration, muted watercolour, ink and wash, desaturated,
ink contours heavier than fill, line is the drawing and wash is the correction,
not anime, not manga, not cel shaded, not digital painting,
trained stillness, hands open and visible, standing where left standing,
deliberately the least colourful person in any room
```

### Universal Negative (recommended)

```
beautiful, attractive, striking, memorable, gorgeous, pretty, cute, sexy, alluring,
anime, anime style, manga, cel shaded, cel shading, big eyes, small nose, delicate features,
smooth skin, symmetrical face, sharp jawline, high cheekbones, pointed chin, large head, small body,
young, youthful, teenage, child, girl, maiden, under 30,
slender, thin, petite, hourglass, curvy, busty, long legs, narrow waist, athletic, muscular,
glossy hair, shiny hair, highlighted hair, streaked hair, layered hair, feathered hair, bangs, fringe,
flowing hair, long hair, styled hair, hair ornament, hair accessory,
perfect skin, flawless, luminous, translucent, creamy, porcelain, glowing skin,
expressive, dramatic, emotional, intense, smoldering, seductive, inviting, alluring,
trending on artstation, digital painting, concept art, fantasy art, game art, visual novel, dating sim,
dynamic action, running, jumping, flying, fighting pose, heroic pose, power pose, contrapposto, s-curve, arched back, hip cocked,
armour, weapon, ornate, decorative, livery, rank marking, revealing, tight, form-fitting, cleavage, midriff,
magical glow, qi-sheen, cultivation aura, clan mark, oath burn, scar, tattoo, brand, mark, symbol, rune, sigil,
ornate background, detailed background, busy background, scenic, landscape, sunset, dramatic lighting,
bright colours, saturated, vibrant, colourful
```

---

*Document version: 1.0 — 2026-10-04*
*Auditor: OpenCode subagent (prompt engineering expert)*
*Scope: Krea2 Turbo attractiveness bias suppression for Ilsa Renn (unique-0001)*
