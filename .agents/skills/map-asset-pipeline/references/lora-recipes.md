# Krea2 Generation & LoRA Parameter Reference

This reference documents the local ComfyUI generation parameters, node chain, and LoRA recipes for map sprites and game props, eliminating the need to inspect `tools/map_generate.py` or `moodyKrea2Minimal_v40_api_v2.json`.

---

## 1. Hardware & Engine Invariants
* **Host**: `http://127.0.0.1:8188` (Local ComfyUI server).
* **Single GPU Constraint**: The machine holds only one active UNET in VRAM at a time. Do not load secondary checkpoints concurrently.
* **Available UNET Checkpoints (`models/unet/` or `models/checkpoints/`)**:
  * `krea2/raySemiReal_krea2TurboV1Nsfw.safetensors`: **(RECOMMENDED & BEST FIT FOR MAP ASSETS)** Semi-realistic Asian/Chinese historical model. Delivers superior architectural joinery, authentic clay/thatch texture, grounded materials, natural foliage, and clean top-down orthographic perspective for world map sprites.
  * `krea2/vxpKrea2Nsfw_beta4AnimeINT8.safetensors`: Anime/fantasy model with broad, vibrant cel-shaded color planes.
  * `krea2/krea2Whyx_whyxINT8.safetensors`: High-fidelity stylized Krea2 INT8 variant for detailed characters and fine props.
* **How to Specify Checkpoint**:
  * Via CLI flag: `--checkpoint "krea2/raySemiReal_krea2TurboV1Nsfw.safetensors"`
  * Via ComfyUI API payload: Set `graph["761"]["inputs"]["unet_name"] = "<checkpoint_name>"`
* **Encoders & Rembg**:
  * CLIP: `qwen3vl_4b_fp8_scaled.safetensors`
  * VAE: `qwen_image_vae.safetensors`
  * Background Remover: `RMBG-2.0` (Sensitivity: `0.01`, Resolution: `1024`, Background: `Alpha`)

---

## 2. Standard KSampler Parameters
For sharp, non-noisy anime-painted gouache map props:
* **Sampler**: `euler_ancestral`
* **Scheduler**: `beta`
* **Steps**: `8` (standard) to `12` (high-detail structures)
* **CFG**: `1.0` (Krea2 is tuned for low CFG; exceeding 1.5 causes oversaturation and noise)
* **Noise Mode**: `return_with_leftover_noise: enable`
* **Canvas Size**: `1024x1024` generation latent, downscaled to asset canvas (`128x128`, `256x256`, `512x512`) during normalization.

---

## 3. LoRA Registry & Node Map

All LoRAs run through `LoraLoaderModelOnly` chaining in series:
`761 (UNET)` $\to$ `929` $\to$ `930` $\to$ `924` $\dots$ $\to$ `915` $\to$ `599 (KSampler)`.
| Node ID | LoRA Key | Filename in `models/loras/krea2/` | Recommended Strength | Visual Characteristics |
|:---:|---|---|:---:|---|
| **917** | `scottie` | `krea2/Scottie__Krea2.safetensors` | `1.0` | **(TOP PICK WITH raySemiReal)** High-clarity stylized rendering, clean structure outlines, rich material definition, ideal for 2D map buildings and props. |
| **884** | `dishwasher` | `krea2/dishwasher_000011250.safetensors` | `0.4` - `0.8` | Crisp `#263A35` ink linework, anime concept art finish, solid material edges. |
| **883** | `painterly_fantasy`| `krea2/painterlyfantasycharstyle_000009000.safetensors`| `0.5` - `0.8` | Painterly gouache, rich organic brush texture, fairytale/fantasy warmth. |
| **885** | `micro_details` | `krea2/AddMicroDetails_Krea2_v1.safetensors` | `0.3` - `0.5` | Surface micro-etching, wood grain, tile cracks, fabric weaves. |
| **887** | `meion_style` | `krea2/meion_krea2_style_v7.0_c1-st4000.safetensors` | `0.4` - `0.7` | Soft anime cel shading, clean flat planes, vibrant illumination. |
| **905** | `dunhuang_murals`| `krea2/888_DunHuang_Murals_Style_krea2.safetensors` | `0.5` - `0.8` | Traditional East Asian mineral pigments, ancient Silk Road / Dunhuang fresco texture, cinnabar/ochre/gold motifs. |
| **906** | `neo_tangzhuang` | `krea2/neo_tangzhuang-KreaRaw-V2.safetensors` | `0.4` - `0.7` | Classical Tang/Song architectural and textile motifs, historic Chinese garments and joinery. |
| **925** | `luminous_impasto`| `krea2/Luminous_Impasto__Style__krea2_3348804_epoch_10.safetensors` | `0.3` - `0.6` | Heavy oil/gouache impasto strokes, tactile pigment layers. |
| **927** | `dancai` | `krea2/dancai-krea2_000007000.safetensors` | `0.5` - `0.8` | Classical Chinese light-ink color painting (Đạm Thải / 淡彩), quiet poetic watercolors, parchment tones. |
| **915** | `gacha_style` | `krea2/GachaStyleKrea2FINAL.safetensors` | `0.4` - `0.6` | Crisp readable mobile RPG game prop silhouettes, clean highlights. |

---

### Recommended Production Combo:
* **UNET Checkpoint**: `krea2/raySemiReal_krea2TurboV1Nsfw.safetensors`
* **LoRA**: `krea2/Scottie__Krea2.safetensors` (Node ID `917`) at **weight = 1.0**
* **Sampler**: `euler_ancestral`, Scheduler: `beta`, Steps: `8`, CFG: `1.0`
* **Characteristics**: Grounded East Asian architectural proportions, authentic natural materials (stone, timber, thatch), crisp non-blurry contours, and consistent ~45° top-down perspective.


---

### Positive Prompt Structure (Isolated Props & Buildings: ~45° Axonometric)
```text
One isolated production sprite for a 2D top-down cultivation action RPG:
[Subject Brief: Specific ancient Chinese architecture, prop, tree, or animal].
Straight-down orthographic camera, flat 45-degree top-down angle, with no horizon or isometric projection.
Anime-painted gouache, dark #263A35 ink contours, broad readable value planes, material-led colors, soft upper-left light.
Clean silhouette, game asset sprite, solid plain white background.
```

### Positive Prompt Structure (Continuous Ground & Terrain Surfaces: 90° Perpendicular Straight-Down)
```text
top-down view looking directly straight down at the ground, 90 degree perpendicular camera angle, flat 2D surface texture:
[Subject Brief: Ancient Chinese loess soil / tilled furrows / dry cracked clay / river gravel / flagstone paving].
Completely flat 2D plane, orthographic top-down view, filling 100% of canvas edge-to-edge from corner to corner with zero perspective, no horizon, no vanishing point, no borders, no curbs, no walls.
Anime gouache style, dark #263A35 ink contours, uniform overhead diffused daylight.
```

---

## 5. Continuous Ground & Terrain Surfaces Recipe (Opaque 100% Full-Bleed)

* **Perspective**: Strictly **90° perpendicular top-down view looking directly straight down at the ground**, flat 2D ground surface texture (never 45° for terrain textures).
* **Canvas Coverage**: `100% full-bleed coverage edge-to-edge from corner to corner`.
* **LoRA Settings**:
  * **Natural Soils & Earth** (yellow loess dirt, freshly tilled loam furrows, sun-baked dry cracked clay, river silt & wet gravel, flooded paddy furrows): **No LoRA (weight 0.0)** with base `raySemiReal`. The base checkpoint excels at organic, uninterrupted planar earth without hallucinating structural bounds or islands.
  * **Architectural Stone Paving** (village street flagstones, river pebble pavers): **Scottie at 0.3** (Node ID `917`). Adds crisp masonry contours without creating 3D walls or curbs.
  * **Isolated Props & Buildings** (bridges, tea stalls, ancestral halls, siege engines): **Scottie at 1.0** (Node ID `917`) with `RMBG-2.0` transparent cutout.
* **Negative Prompt for Terrain**:
```text
45 degree angle, angled view, perspective, vanishing point, horizon, sky, tilt, depth of field, isometric, 3d render, border, frame, margin, edge, curb, wall, fence, circular pool, island, vignette, building, roof, tree, person, text, watermark
```

