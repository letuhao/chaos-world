# Krea2 Generation & LoRA Parameter Reference

This reference documents the local ComfyUI generation parameters, node chain, and LoRA recipes for map sprites and game props, eliminating the need to inspect `tools/map_generate.py` or `moodyKrea2Minimal_v40_api_v2.json`.

---

## 1. Hardware & Engine Invariants
* **Host**: `http://127.0.0.1:8188` (Local ComfyUI server).
* **Single GPU Constraint**: The machine holds only one active UNET in VRAM (`KREA2_MODEL`). Do not load secondary checkpoints concurrently.
* **Checkpoint & Encoders**:
  * UNET: `krea2/vxpKrea2Nsfw_beta4AnimeINT8.safetensors`
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

## 4. Prompting Template

### Positive Prompt Structure
```text
One isolated production sprite for a 2D top-down cultivation action RPG:
[Subject Brief: Specific ancient Chinese architecture, prop, tree, or animal].
Straight-down orthographic camera, flat 45-degree top-down angle, with no horizon or isometric projection.
Anime-painted gouache, dark #263A35 ink contours, broad readable value planes, material-led colors, soft upper-left light.
Clean silhouette, game asset sprite, solid plain white background.
```

### Negative Prompt Structure
```text
blurry, noise, low quality, artifacts, modern, 3d render, western, photographic realistic, horizon, landscape scenery, text, watermark, frame, borders
```
