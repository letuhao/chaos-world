# Validation Audit — Unique Character Asset Pipeline

> **Date**: 2026-10-04
> **Auditor**: QA subagent
> **Scope**: `scripts/audit_images.py` and the Phase 5 validation approach
> **Character**: Ilsa Renn (unique-0001) — deliberately plain, near-monochrome, forgettable

---

## 1. Executive Summary

The current validation (`audit_images.py`) checks **3 things**: alpha channel existence, transparent percentage, and image dimensions. This is insufficient for a character whose entire design philosophy is the **absence of signal** — no attractiveness, no colour, no marks, no memorability. A generated image can pass all three current checks while being completely wrong: a beautiful anime girl with glowing eyes, bright colours, and ornate clothing would pass the existing audit without complaint.

**The validation gap is not a missing check — it is a missing philosophy.** The current script validates that the image is a PNG with transparency. It does not validate that the image is *Ilsa*.

---

## 2. Current State: What `audit_images.py` Actually Does

| Check | Implementation | Documented Threshold | Actual Threshold |
|-------|---------------|---------------------|------------------|
| Alpha channel exists | `img.mode != "RGBA"` | Yes | Yes |
| Transparent % | `sum(p < 128) / total * 100` | > 20% | > 10% |
| Dimensions | Printed, not validated | Match expected | Not checked |

**Bugs in the current script:**

1. **Threshold mismatch**: WORKFLOW.md says >20%, code checks `< 10%` — a 15% transparent image passes silently.
2. **No dimension validation**: Dimensions are printed but never compared to expected canvas sizes.
3. **No per-shot awareness**: The script globs `ilsa_*.png` and treats all shots identically. A `map_sprite` (256x256 token) and a `character_portrait` (3:4 bust) have completely different validation requirements.
4. **No palette validation**: The near-monochrome palette (warm ivory, ash grey, pale jade, dull brass) is never checked.
5. **No attractiveness detection**: The model's default bias toward "beautiful anime girl" is the #1 failure mode and is not checked at all.
6. **No diversity check**: No two shots should feel the same — not checked.
7. **No culture/clothing check**: Undyed wool, linen, no livery — not checked.
8. **No quality check**: Artifacts, clean lines, readable silhouette — not checked.

---

## 3. Validation System Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                  VALIDATION PIPELINE                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Layer 1: AUTOMATED (deterministic, no GPU)             │
│  ├── V1  Format & Canvas                                │
│  ├── V2  Background & Alpha                             │
│  ├── V3  Colour Palette                                 │
│  ├── V4  Attractiveness Heuristics                       │
│  ├── V5  Diversity (Expression)                         │
│  ├── V6  Diversity (Pose)                               │
│  ├── V7  Culture Markers                                │
│  ├── V8  Quality & Artifacts                            │
│  └── V9  Silhouette                                     │
│                                                         │
│  Layer 2: MODEL-ASSISTED (lightweight CV models)        │
│  ├── V10 Face Landmark Symmetry                         │
│  ├── V11 Eye Size Ratio                                 │
│  ├── V12 Clothing Detection                             │
│  └── V13 Expression Classification                      │
│                                                         │
│  Layer 3: AGENT/VISUAL (human or VLM)                   │
│  ├── V14 Character Fidelity                             │
│  ├── V15 Culture & Geography Match                      │
│  ├── V16 Narrative Coherence                            │
│  └── V17 Overall Quality                                │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Per-Shot Validation Matrix

Different shot types have different validation requirements:

| Check | map_sprite | dialogue_portrait | character_portrait | concept_art | environmental | combat | relationship | expressions | poses | daily |
|-------|:----------:|:-----------------:|:------------------:|:-----------:|:-------------:|:------:|:------------:|:-----------:|:-----:|:-----:|
| V1 Format | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| V2 Alpha | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| V3 Palette | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| V4 Attractiveness | — | ✓ | ✓ | ✓ | — | — | — | ✓ | ✓ | ✓ |
| V5 Expression Diversity | — | — | — | — | — | — | — | ✓ | — | — |
| V6 Pose Diversity | — | — | — | — | — | — | — | — | ✓ | — |
| V7 Culture | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| V8 Quality | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| V9 Silhouette | ✓ | — | — | ✓ | — | ✓ | — | — | ✓ | ✓ |
| V10 Face Symmetry | — | ✓ | ✓ | — | — | — | — | ✓ | — | ✓ |
| V11 Eye Size | — | ✓ | ✓ | — | — | — | — | ✓ | — | ✓ |
| V12 Clothing | — | — | — | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| V13 Expression Class | — | — | — | — | — | — | — | ✓ | — | — |
| V14 Fidelity | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| V15 Culture/Geo | — | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| V16 Narrative | — | — | — | ✓ | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| V17 Overall | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

---

## 4. Automated Checks (Layer 1) — Detailed Specification

### V1: Format & Canvas

**Purpose**: Verify the image is a valid PNG with correct dimensions for its shot type.

```python
EXPECTED_CANVAS = {
    "map_sprite":         {"w": 512, "h": 512,   "tolerance": 0},      # 1:1 token
    "dialogue_portrait":  {"w": 768, "h": 1024,  "tolerance": 0.02},   # 3:4
    "character_portrait": {"w": 768, "h": 1024,  "tolerance": 0.02},   # 3:4
    "concept_art":        {"w": 768, "h": 1024,  "tolerance": 0.02},   # 3:4
    "environmental":      {"w": 1024, "h": 576,  "tolerance": 0.02},   # 16:9
    "combat_concept":     {"w": 768, "h": 1024,  "tolerance": 0.02},   # 3:4
    "relationship":       {"w": 1024, "h": 576,  "tolerance": 0.02},   # 16:9
    "expression":         {"w": 768, "h": 1024,  "tolerance": 0.02},   # 3:4
    "pose":               {"w": 768, "h": 1024,  "tolerance": 0.02},   # 3:4
    "daily":              {"w": 1024, "h": 576,  "tolerance": 0.02},   # 16:9
}
```

**Checks**:
- File is valid PNG (not corrupted, not a renamed JPEG)
- Dimensions match expected canvas within tolerance
- Colour mode is RGBA (not RGB, not P, not L)
- Bit depth is 8 (not 16-bit, not 32-bit float)

**Failure modes**:
- Corrupted file → FAIL
- Wrong dimensions → FAIL (e.g., portrait generated as landscape)
- Palette mode (P) → FAIL (colour quantization destroys the near-monochrome palette)

---

### V2: Background & Alpha

**Purpose**: Verify background removal worked correctly.

**Checks** (improved from current):
- Alpha channel exists
- Transparent percentage > 20% (as documented, not 10%)
- Alpha is binary or near-binary (not a gradient — RMBG should produce hard edges)
- No semi-transparent fringe > 5% of edge pixels (halo check)
- Opaque region is contiguous (no scattered transparent holes inside the character)

**Metrics**:
```python
transparent_pct = count(alpha < 128) / total_pixels * 100
edge_halo_pct = count(0 < alpha < 200 on bounding-box edge) / edge_pixels * 100
internal_holes = count(alpha < 128 pixels not connected to border) / total_pixels * 100
```

**Thresholds**:
- `transparent_pct < 20%` → FAIL (background removal weak)
- `edge_halo_pct > 5%` → WARN (semi-transparent fringe — may cause rendering artifacts)
- `internal_holes > 1%` → FAIL (transparent holes inside character — RMBG failure)

---

### V3: Colour Palette

**Purpose**: Verify the image uses the approved near-monochrome palette.

**Approved palette** (from ART_CRITERIA.md):
```python
APPROVED_PALETTE = {
    "warm_ivory":  (0xE8, 0xE0, 0xD0),  # Primary field, linen
    "ash_grey":    (0x8A, 0x85, 0x80),  # Wool coat, shadow
    "pale_jade":   (0xB8, 0xC4, 0xB0),  # Secondary fill
    "dull_brass":  (0x8B, 0x7D, 0x4F),  # Single metallic accent
    "ink_contour": (0x2A, 0x25, 0x20),  # Line work
    "skin_warm":   (0xC4, 0xA8, 0x82),  # Skin
    "hair_brown":  (0x3D, 0x2E, 0x22),  # Hair
}
```

**Checks**:
- Convert to HSV, compute saturation distribution
- Compute colour histogram (quantized to 32 bins per channel)
- For each pixel, find nearest approved colour in CIELAB space
- Compute percentage of pixels that match an approved colour within tolerance

**Metrics**:
```python
mean_saturation = mean(HSV.S)  # Should be LOW for near-monochrome
palette_match_pct = count(nearest_approved_delta_E < 15) / total_opaque_pixels * 100
unique_colours = count(distinct_colours)  # Should be LOW
```

**Thresholds**:
- `mean_saturation > 0.25` → FAIL (too colourful — Ilsa is deliberately desaturated)
- `palette_match_pct < 70%` → WARN (significant off-palette colours)
- `palette_match_pct < 50%` → FAIL (wrong palette entirely)
- `unique_colours > 5000` → WARN (too many colours — possible noise/artifacts)

**Additional palette checks**:
- No pure saturated colours (HSV.S > 0.8 and HSV.V > 0.7) → FAIL (bright colours forbidden)
- No pure black (RGB < 10,10,10) → WARN (ink contour is #2A2520, not pure black)
- No pure white (RGB > 245,245,245) → WARN (warm ivory is #E8E0D0, not pure white)

---

### V4: Attractiveness Heuristics

**Purpose**: Detect the model's default bias toward "beautiful anime girl" — the #1 failure mode.

**Approach**: Multi-signal heuristic scoring. No single metric is reliable; combined signals catch most cases.

#### V4a: Eye Size Ratio
```python
# Detect face region, then measure eye width relative to face width
# Anime default: eyes are 30-40% of face width
# Ilsa: eyes should be 15-20% of face width (ordinary, unremarkable)
eye_face_ratio = eye_width / face_width
```
- `eye_face_ratio > 0.25` → FAIL (anime-style large eyes)
- `eye_face_ratio > 0.20` → WARN (slightly large)

#### V4b: Face Symmetry
```python
# Split face along vertical axis, compare left/right halves
# High symmetry = attractive (evolutionary signal)
# Ilsa should have natural, imperfect symmetry
symmetry_score = 1 - mean(abs(left_half - flipped_right_half)) / 255
```
- `symmetry_score > 0.92` → FAIL (too symmetrical — model default)
- `symmetry_score > 0.88` → WARN

#### V4c: Skin Smoothness
```python
# Compute local variance in skin region
# Perfect skin = low variance = attractive
# Ilsa: ordinary skin with slight weathering
skin_variance = variance(skin_region_luminance)
```
- `skin_variance < 5` → FAIL (porcelain-perfect skin)
- `skin_variance < 15` → WARN

#### V4d: Hair Shine
```python
# Detect specular highlights in hair region
# Glossy hair = attractive
# Ilsa: blade-cut, no shine
hair_highlight_pct = count(hair_pixels with V > 0.9 and S < 0.1) / hair_pixels * 100
```
- `hair_highlight_pct > 10%` → FAIL (glossy/styled hair)
- `hair_highlight_pct > 5%` → WARN

#### V4e: Colourfulness (already in V3, but worth repeating)
```python
# Hasler-Susstrunk metric — perceptual colourfulness
colourfulness = sqrt(sigma_rg^2 + sigma_yb^2) + 0.3 * sqrt(mu_rg^2 + mu_yb^2)
```
- `colourfulness > 40` → FAIL (too colourful for near-monochrome character)
- `colourfulness > 25` → WARN

**Combined attractiveness score**:
```python
attractiveness_risk = weighted_sum(
    eye_face_ratio * 0.25,
    symmetry_score * 0.25,
    (1 - skin_variance_normalized) * 0.20,
    hair_highlight_pct * 0.15,
    colourfulness * 0.15,
)
```
- `attractiveness_risk > 0.70` → FAIL (too attractive — regenerate)
- `attractiveness_risk > 0.50` → WARN (borderline — agent review)

---

### V5: Expression Diversity

**Purpose**: Ensure the 9 expression shots are dramatically different from each other.

**Approach**: Pairwise comparison of expression shots using multiple metrics.

#### V5a: Pixel-Level Difference
```python
# Resize all expression shots to 256x256, compute pairwise MSE
# Expressions should differ significantly
for i, j in combinations(expression_shots, 2):
    mse = mean_squared_error(resize(img_i, 256), resize(img_j, 256))
```
- `mse < 50` → FAIL (nearly identical — model ignored expression prompt)
- `mse < 150` → WARN (very similar)

#### V5b: Face Landmark Distance
```python
# Use a lightweight face detector (e.g., MediaPipe, dlib)
# Extract 68 facial landmarks, compute pairwise Procrustes distance
for i, j in combinations(expression_shots, 2):
    landmark_dist = procrustes_distance(landmarks_i, landmarks_j)
```
- `landmark_dist < 0.05` → FAIL (face shape nearly identical)
- `landmark_dist < 0.10` → WARN

#### V5c: Eye Region Difference
```python
# Extract eye regions, compare
# Eye direction is a key expression differentiator
eye_mse = mean_squared_error(eye_region_i, eye_region_j)
```
- `eye_mse < 30` → FAIL (eyes identical — expression not varied)

#### V5d: Head Pose Difference
```python
# Estimate head pose from face landmarks
# Yaw, pitch, roll should differ across expressions
pose_diff = euclidean_distance(pose_i, pose_j)  # in degrees
```
- `pose_diff < 5°` → FAIL (head position identical)

**Combined diversity score**:
```python
diversity_score = min(
    normalized_mse,
    normalized_landmark_dist,
    normalized_eye_mse,
    normalized_pose_diff,
)
```
- `diversity_score < 0.30` → FAIL (expressions too similar)
- `diversity_score < 0.50` → WARN

---

### V6: Pose Diversity

**Purpose**: Ensure the 6 pose shots use different camera angles and framing.

#### V6a: Silhouette Comparison
```python
# Extract alpha channel as silhouette
# Resize to 128x128, compute IoU (Intersection over Union)
for i, j in combinations(pose_shots, 2):
    iou = intersection_over_union(silhouette_i, silhouette_j)
```
- `iou > 0.85` → FAIL (silhouettes nearly identical)
- `iou > 0.70` → WARN (very similar silhouettes)

#### V6b: Bounding Box Aspect Ratio
```python
# Different poses should have different bounding box shapes
# Standing = tall/thin, seated = short/wide, walking = medium
aspect_ratio = bbox_width / bbox_height
```
- Two poses with `aspect_ratio` within 5% of each other → WARN

#### V6c: Camera Angle Detection
```python
# Use a simple heuristic: face position in frame
# Profile = face at edge, front = face at centre, rear = no face
face_x_position = face_centre_x / image_width
```
- Two poses with same face position (±5%) → WARN (same camera angle)

---

### V7: Culture Markers

**Purpose**: Detect wrong-culture items (armour, weapons, jewellery, modern clothing, sect marks).

#### V7a: Metallic Detection
```python
# Dull brass is the ONLY approved metallic
# Detect metallic-looking pixels (high value, low saturation, specific hue)
metallic_hue_range = [30, 60]  # degrees (yellow-brown)
metallic_pixels = count(pixels in metallic_hue_range with V > 0.4 and S < 0.3)
```
- `metallic_pixels > 5%` → WARN (possible unapproved metal — armour, weapon, jewellery)
- `metallic_pixels > 15%` → FAIL (definitely wrong items)

#### V7b: Skin Exposure Check
```python
# Ilsa wears: high-collared linen shift, full sleeves, travelling coat
# Skin should be limited to face and hands
skin_pixel_count = count(skin_colour_pixels)
skin_pct = skin_pixel_count / opaque_pixels * 100
```
- `skin_pct > 25%` → FAIL (too much skin exposure — wrong clothing)
- `skin_pct > 15%` → WARN (possibly wrong clothing)

#### V7c: Mark/Tattoo Detection
```python
# Ilsa has NO marks — no clan mark, no oath burn, no scarring
# Detect dark patterns on skin that could be marks
# Look for high-contrast dark regions on skin-coloured areas
mark_candidates = count(dark_pixels adjacent to skin_pixels with high_contrast)
```
- `mark_candidates > threshold` → FAIL (possible marks/tattoos)

#### V7d: Modern Item Detection
```python
# No modern clothing, no anachronisms
# Detect colours/materials associated with modern items
# Synthetic bright colours, plastic-like textures
modern_colour_pixels = count(pixels with S > 0.7 and V > 0.6)
```
- `modern_colour_pixels > 2%` → FAIL (possible modern items)

---

### V8: Quality & Artifacts

**Purpose**: Detect generation artifacts, noise, and quality issues.

#### V8a: Edge Sharpness
```python
# Compute Laplacian variance (focus measure)
# Blurry = low variance, sharp = high variance
laplacian_var = variance(laplacian(gray_image))
```
- `laplacian_var < 50` → FAIL (blurry — generation quality issue)
- `laplacian_var < 100` → WARN (soft — may be intentional for painterly style)

#### V8b: Noise Detection
```python
# Compute high-frequency noise using median filter difference
noise = median_filter(gray, 3) - gray
noise_std = std(noise)
```
- `noise_std > 15` → FAIL (noisy — generation artifact)
- `noise_std > 10` → WARN

#### V8c: Colour Banding
```python
# Detect posterization/banding in smooth areas
# Count distinct luminance values in smooth regions
smooth_region = gaussian_blur(gray, sigma=5)
distinct_values = count(unique_values(smooth_region))
```
- `distinct_values < 20` → WARN (possible banding — 8-bit quantization artifact)

#### V8d: Compression Artifacts
```python
# Detect JPEG-like block artifacts (8x8 DCT blocks)
# Even though output is PNG, the model may have produced JPEG artifacts
blockiness = compute_8x8_block_variance(gray)
```
- `blockiness > threshold` → WARN (possible compression artifacts)

---

### V9: Silhouette

**Purpose**: Verify the silhouette is readable and matches the "forgettable, upright, contained" keywords.

#### V9a: Silhouette Readability
```python
# Extract alpha channel as silhouette
# Compute solidity (area / convex_hull_area)
# A readable silhouette has moderate solidity
solidity = silhouette_area / convex_hull_area
```
- `solidity < 0.30` → FAIL (silhouette too fragmented — unreadable)
- `solidity > 0.95` → WARN (silhouette too simple — may be a blob)

#### V9b: Silhouette Uprightness
```python
# Compute principal axis of silhouette
# Ilsa stands perfectly vertical
principal_axis_angle = PCA(silhouette).angle
```
- `abs(principal_axis_angle) > 10°` → FAIL (not upright — wrong posture)
- `abs(principal_axis_angle) > 5°` → WARN (slight lean)

#### V9c: Silhouette Containment
```python
# Check if silhouette is contained within frame
# No cropped extremities
bbox = get_bounding_box(silhouette)
margin = min(bbox.left, bbox.top, image_width - bbox.right, image_height - bbox.bottom)
```
- `margin < 0` → FAIL (silhouette cropped — composition error)
- `margin < 20px` → WARN (too close to edge)

---

## 5. Model-Assisted Checks (Layer 2) — Detailed Specification

These checks require lightweight CV models but no GPU inference.

### V10: Face Landmark Symmetry

**Model**: MediaPipe Face Mesh (468 landmarks) or dlib (68 landmarks)

**Purpose**: Precise symmetry measurement for attractiveness detection.

**Method**:
1. Detect face in image
2. Extract facial landmarks
3. Compute symmetry score by comparing left/right landmark distances from centre line
4. Normalize by face size

**Thresholds**:
- `symmetry_score > 0.90` → FAIL (too symmetrical — model default beauty)
- `symmetry_score > 0.85` → WARN

### V11: Eye Size Ratio

**Model**: MediaPipe Face Mesh or dlib

**Purpose**: Precise eye measurement for anime-eye detection.

**Method**:
1. Detect eye landmarks
2. Compute eye width (distance between eye corners)
3. Compute face width (distance between cheekbones)
4. Ratio = eye_width / face_width

**Thresholds**:
- `ratio > 0.28` → FAIL (anime-style large eyes)
- `ratio > 0.22` → WARN (slightly large)

### V12: Clothing Detection

**Model**: Lightweight colour/texture classifier (or heuristic)

**Purpose**: Verify clothing matches undyed wool + linen specification.

**Method**:
1. Segment clothing region (non-skin, non-background, non-hair)
2. Analyse texture (wool = matte, linen = slightly textured)
3. Check for decorative elements (high-frequency patterns, bright colours)

**Thresholds**:
- `decorative_pattern_detected` → FAIL (clothing has decorative elements)
- `bright_colour_in_clothing` → FAIL (clothing has non-approved colours)
- `texture_smoothness > threshold` → WARN (clothing looks too smooth — possibly armour)

### V13: Expression Classification

**Model**: Lightweight expression classifier (e.g., FER2013-trained model)

**Purpose**: Verify each expression shot matches its intended expression.

**Method**:
1. Detect face
2. Classify expression into: neutral, focus, courtesy, amusement, boredom, flinch, concentration, grief, defiance
3. Compare with intended expression from ART_CRITERIA.md

**Thresholds**:
- `classified != intended` → FAIL (wrong expression generated)
- `confidence < 0.60` → WARN (uncertain classification — agent review)

---

## 6. Agent/Visual Checks (Layer 3) — Specification

These checks require human judgment or a Vision-Language Model (VLM).

### V14: Character Fidelity

**Question**: "Does this character match the lore description of Ilsa Renn?"

**Checklist**:
- [ ] Age appears ~41 (not 20s, not 60s)
- [ ] Build is average and unadapted (not athletic, not thin)
- [ ] Complexion is ordinary warm human skin (not pale, not dark, not glowing)
- [ ] Hair is dark brown, cropped short, blade-cut (not long, not styled, not glossy)
- [ ] Eyes are dark, level, steady (not large, not sparkling, not glowing)
- [ ] No visible marks, scars, or tattoos

**Pass condition**: All checklist items pass.

### V15: Culture & Geography Match

**Question**: "Does the clothing and environment match the Mortal Plains + Saltledger faction?"

**Checklist**:
- [ ] Clothing is undyed wool travelling coat (not armour, not robes, not modern)
- [ ] High-collared linen shift visible at neck
- [ ] Sleeves are full (not bare arms)
- [ ] Wrists bound with plain cord (not jewellery, not bracers)
- [ ] Boots are plain and resoled (not armoured boots, not modern shoes)
- [ ] No livery, sect colour, or rank marking
- [ ] Environment matches Mortal Plains (open grassland, stone, measurement yards)
- [ ] No anachronisms (no modern items, no wrong-culture elements)

**Pass condition**: All checklist items pass.

### V16: Narrative Coherence

**Question**: "Does this shot tell the story it is supposed to tell?"

**Per-shot narrative checks**:

| Shot | Narrative Question |
|------|-------------------|
| map_sprite | Is she readable as a tiny game token? |
| dialogue_portrait | Is the palm-up correction gesture visible? |
| character_portrait | Is the expression flat and legible? |
| concept_art | Is the full outfit visible and readable? |
| environmental_concept | Are the four seated imprints visible? |
| combat_concept | Is the circle of struck ground visible? |
| relationship_scene | Is the flat stone grave visible? |
| expression_* | Does the expression match the intended emotion? |
| pose_* | Does the pose match the intended camera angle? |
| daily_* | Does the scene show personality? |

**Pass condition**: The shot's distinguishing feature is visible and correct.

### V17: Overall Quality

**Question**: "Is this image good enough to ship?"

**Checklist**:
- [ ] Clean lines (no artifacts, no noise)
- [ ] Readable silhouette (not fragmented, not blob-like)
- [ ] Consistent style (matches cultivation-fantasy-relic art direction)
- [ ] No rendering errors (no extra limbs, no distorted features)
- [ ] Composition is balanced (not awkwardly cropped, not off-centre)

**Pass condition**: All checklist items pass.

---

## 7. Validation Report Format

### 7.1 Console Output (Automated)

```
═══════════════════════════════════════════════════════════════
  VALIDATION REPORT — Ilsa Renn (unique-0001)
  2026-10-04 14:32:07
═══════════════════════════════════════════════════════════════

SHOT: character_portrait (ilsa_character_portrait.png)
───────────────────────────────────────────────────────────────
  V1  Format & Canvas         ✓ PASS  768x1024, RGBA, 8-bit
  V2  Background & Alpha      ✓ PASS  34.2% transparent, 0.8% halo
  V3  Colour Palette          ✓ PASS  mean_sat=0.12, palette_match=82%
  V4  Attractiveness          ✓ PASS  risk_score=0.31 (threshold 0.70)
  V7  Culture Markers         ✓ PASS  no metallic, skin=12%, no marks
  V8  Quality & Artifacts     ✓ PASS  laplacian_var=187, noise_std=4.2
  V9  Silhouette              ✓ PASS  solidity=0.67, angle=2.1°
  V10 Face Symmetry           ✓ PASS  symmetry=0.81 (threshold 0.90)
  V11 Eye Size Ratio          ✓ PASS  ratio=0.18 (threshold 0.28)
  V12 Clothing Detection      ✓ PASS  matte texture, no decoration
  V13 Expression Class        ✓ PASS  neutral (confidence 0.87)
  ─────────────────────────────────────────────────────────────
  RESULT: ✓ PASS (12/12 automated checks passed)

SHOT: expression_04 (ilsa_expression_04.png)
───────────────────────────────────────────────────────────────
  V1  Format & Canvas         ✓ PASS  768x1024, RGBA, 8-bit
  V2  Background & Alpha      ✓ PASS  31.8% transparent, 1.2% halo
  V3  Colour Palette          ✓ PASS  mean_sat=0.15, palette_match=78%
  V4  Attractiveness          ✓ PASS  risk_score=0.28 (threshold 0.70)
  V5  Expression Diversity     ✓ PASS  min_diversity=0.62 (threshold 0.30)
  V7  Culture Markers         ✓ PASS  no metallic, skin=11%, no marks
  V8  Quality & Artifacts     ✓ PASS  laplacian_var=156, noise_std=5.1
  V10 Face Symmetry           ✓ PASS  symmetry=0.79 (threshold 0.90)
  V11 Eye Size Ratio          ✓ PASS  ratio=0.17 (threshold 0.28)
  V13 Expression Class        ✓ PASS  amusement (confidence 0.72)
  ─────────────────────────────────────────────────────────────
  RESULT: ✓ PASS (9/9 automated checks passed)

...

═══════════════════════════════════════════════════════════════
  SUMMARY
═══════════════════════════════════════════════════════════════
  Total shots:    25
  Passed:         23
  Failed:          2
  Warnings:        5

  FAILURES:
    ✗ expression_07 (ilsa_expression_07.png)
      V4  Attractiveness          ✗ FAIL  risk_score=0.78 (threshold 0.70)
        → Eye ratio 0.31 (anime-style large eyes)
        → Symmetry 0.94 (too symmetrical)
        → Skin variance 3.2 (porcelain-perfect)
      FIX: Strengthen negative prompt, add "plain, unremarkable, forgettable"

    ✗ pose_03 (ilsa_pose_03.png)
      V6  Pose Diversity          ✗ FAIL  silhouette IoU=0.89 with pose_01
        → Silhouettes nearly identical
      FIX: Change camera angle or framing

  WARNINGS:
    ⚠ expression_02  V5  Expression Diversity  diversity=0.42 (threshold 0.50)
    ⚠ pose_05        V9  Silhouette           margin=12px (threshold 20px)
    ⚠ daily_romance  V7  Culture Markers      metallic=6% (threshold 5%)
    ⚠ daily_working  V8  Quality              laplacian_var=89 (threshold 100)
    ⚠ daily_casual   V3  Palette              palette_match=65% (threshold 70%)

═══════════════════════════════════════════════════════════════
  AGENT/VISUAL CHECKS REQUIRED (Layer 3)
═══════════════════════════════════════════════════════════════
  The following checks require human or VLM inspection:

  V14 Character Fidelity        — All 25 shots
  V15 Culture & Geography       — All 25 shots
  V16 Narrative Coherence       — All 25 shots
  V17 Overall Quality           — All 25 shots

  Use: python scripts/validate.py --visual
  Or:  Open each image in the outputs/ directory and check manually.

═══════════════════════════════════════════════════════════════
```

### 7.2 JSON Report (Machine-Readable)

```json
{
  "character": "unique-0001-ilsa-renn",
  "timestamp": "2026-10-04T14:32:07Z",
  "summary": {
    "total": 25,
    "passed": 23,
    "failed": 2,
    "warnings": 5
  },
  "shots": [
    {
      "name": "character_portrait",
      "file": "ilsa_character_portrait.png",
      "result": "PASS",
      "checks": {
        "V1_format": {"status": "PASS", "details": "768x1024, RGBA, 8-bit"},
        "V2_alpha": {"status": "PASS", "details": "34.2% transparent, 0.8% halo"},
        "V3_palette": {"status": "PASS", "details": "mean_sat=0.12, palette_match=82%"},
        "V4_attractiveness": {"status": "PASS", "details": "risk_score=0.31"},
        "V7_culture": {"status": "PASS", "details": "no metallic, skin=12%"},
        "V8_quality": {"status": "PASS", "details": "laplacian_var=187"},
        "V9_silhouette": {"status": "PASS", "details": "solidity=0.67, angle=2.1°"},
        "V10_symmetry": {"status": "PASS", "details": "symmetry=0.81"},
        "V11_eye_ratio": {"status": "PASS", "details": "ratio=0.18"},
        "V12_clothing": {"status": "PASS", "details": "matte texture"},
        "V13_expression": {"status": "PASS", "details": "neutral (0.87)"}
      }
    }
  ],
  "failures": [
    {
      "name": "expression_07",
      "file": "ilsa_expression_07.png",
      "failed_checks": ["V4_attractiveness"],
      "details": "risk_score=0.78, eye_ratio=0.31, symmetry=0.94",
      "fix": "Strengthen negative prompt"
    }
  ],
  "warnings": [
    {
      "name": "expression_02",
      "check": "V5_expression_diversity",
      "details": "diversity=0.42"
    }
  ]
}
```

### 7.3 HTML Report (Human-Readable)

An HTML report should include:
- Summary dashboard (pass/fail/warn counts)
- Per-shot cards with thumbnail, check results, and failure details
- Side-by-side comparison for diversity failures
- Palette visualization (approved vs actual colours)
- Silhouette overlay for pose comparison
- Export to PDF for review

---

## 8. Implementation Priority

### Phase 1: Critical (Immediate)

| Check | Effort | Impact | Rationale |
|-------|--------|--------|-----------|
| V1 Format & Canvas | XS | High | Catches wrong profile, corrupted files |
| V2 Alpha (fix threshold) | XS | High | Fix the 10% → 20% bug |
| V3 Colour Palette | S | High | Catches wrong palette instantly |
| V4 Attractiveness (V4a-V4e) | M | Critical | #1 failure mode — model default beauty |
| V8 Quality (V8a-V8b) | S | High | Catches blurry/noisy generations |

### Phase 2: High Priority

| Check | Effort | Impact | Rationale |
|-------|--------|--------|-----------|
| V5 Expression Diversity | M | High | Catches identical expressions |
| V6 Pose Diversity | M | High | Catches identical poses |
| V7 Culture Markers | M | High | Catches wrong items |
| V9 Silhouette | S | Medium | Catches composition errors |

### Phase 3: Medium Priority

| Check | Effort | Impact | Rationale |
|-------|--------|--------|-----------|
| V10 Face Symmetry | M | Medium | Refines V4b |
| V11 Eye Size | S | Medium | Refines V4a |
| V12 Clothing Detection | L | Medium | Complex — may need model |
| V13 Expression Class | M | Medium | Needs classifier model |

### Phase 4: Nice-to-Have

| Check | Effort | Impact | Rationale |
|-------|--------|--------|-----------|
| V8c Colour Banding | S | Low | Rare issue |
| V8d Compression Artifacts | S | Low | Rare issue |
| HTML Report | M | Low | Convenience |

---

## 9. Recommended Script Architecture

```
scripts/
  audit_images.py          # Keep for backward compatibility (alpha check only)
  validate.py              # New comprehensive validation
    ├── checks/
    │   ├── format.py      # V1
    │   ├── alpha.py       # V2
    │   ├── palette.py     # V3
    │   ├── attractiveness.py  # V4
    │   ├── diversity.py   # V5, V6
    │   ├── culture.py     # V7
    │   ├── quality.py     # V8
    │   ├── silhouette.py  # V9
    │   └── model_assisted.py  # V10-V13
    ├── report.py          # Report generation (console, JSON, HTML)
    └── criteria.py        # Load ART_CRITERIA.md thresholds
  validate_visual.py       # Layer 3 agent/VLM checks (interactive)
```

---

## 10. Key Thresholds Summary

| Check | Metric | WARN | FAIL | Rationale |
|-------|--------|------|------|-----------|
| V2 | Transparent % | < 25% | < 20% | Background removal must be substantial |
| V2 | Edge halo % | > 3% | > 5% | Semi-transparent fringe causes artifacts |
| V3 | Mean saturation | > 0.18 | > 0.25 | Near-monochrome character |
| V3 | Palette match % | < 70% | < 50% | Must use approved colours |
| V4 | Eye/face ratio | > 0.22 | > 0.28 | Anime eyes are 0.30+ |
| V4 | Face symmetry | > 0.88 | > 0.92 | Natural faces are imperfect |
| V4 | Skin variance | < 15 | < 5 | Perfect skin = attractive |
| V4 | Hair highlight % | > 5% | > 10% | Glossy hair = styled |
| V4 | Colourfulness | > 25 | > 40 | Hasler-Süsstrunk metric |
| V5 | Expression MSE | < 150 | < 50 | Pixel-level similarity |
| V5 | Landmark distance | < 0.10 | < 0.05 | Face shape similarity |
| V6 | Silhouette IoU | > 0.70 | > 0.85 | Shape similarity |
| V7 | Metallic % | > 5% | > 15% | Unapproved metal items |
| V7 | Skin exposure % | > 15% | > 25% | Wrong clothing |
| V8 | Laplacian variance | < 100 | < 50 | Blurry = quality issue |
| V8 | Noise std | > 10 | > 15 | Noisy = artifact |
| V9 | Solidity | < 0.40 | < 0.30 | Fragmented silhouette |
| V9 | Upright angle | > 5° | > 10° | Must be vertical |
| V10 | Symmetry score | > 0.85 | > 0.90 | Model default beauty |
| V11 | Eye size ratio | > 0.22 | > 0.28 | Anime eyes |

---

## 11. Conclusion

The current validation is a **format checker**, not a **quality gate**. It verifies that the image is a transparent PNG but says nothing about whether the image is Ilsa Renn.

The most critical missing check is **attractiveness detection** (V4). The model's default bias toward "beautiful anime girl" is the single most likely failure mode, and the current validation has zero defense against it. A generated image of a beautiful anime girl with large sparkling eyes, glossy hair, and perfect skin would pass the current audit without any complaint.

The second most critical missing check is **palette validation** (V3). Ilsa's near-monochrome palette is her defining visual characteristic. A colourful image is immediately wrong, but the current validation cannot detect this.

The third most critical missing check is **diversity** (V5, V6). The workflow explicitly requires that no two shots feel the same, but there is no automated way to verify this.

**Recommendation**: Implement Phase 1 checks immediately (V1-V4, V8). These catch 80% of failure modes with minimal effort. Phase 2 checks (V5-V7, V9) add the remaining coverage. Phase 3 checks (V10-V13) refine the heuristics with model-assisted precision.

---

*Audit completed: 2026-10-04*
*Next review: After Phase 1 implementation*
