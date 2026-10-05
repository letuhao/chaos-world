# Art direction

## Visual identity

Cultivation-fantasy relic illustration: mystical, handmade, and legible at inventory size. Use painterly gouache, fine dark ink contours, material-led color, and restrained metallic accents. Light comes from upper left; keep shading to broad planes. Avoid modern props, text baked into art, heavy gradients, noisy texture, and sexualized imagery.

## Item icons

- One centered object on transparent background; no baked labels, borders, or scene.
- Generated PNGs are 256×256 and composed to read at 48 px; lightweight family symbols use a 64×64 SVG view box.
- Palette roles: ink `#263A35`, warm ivory `#F2E8D2`, antique gold `#C49A53`. Material colors include jade `#739B83`, pale jade `#D8E6D3`, cinnabar `#B75F4A`, mineral blue `#668AA0`, and violet `#82739B`; these are options, not a default set.
- Choose color from the object's material and identity. Jade and green are one family among cinnabar, amber, blue, violet, ivory, iron, and mixed metals. Across a batch, vary both dominant hue and surface motif; use fitting patterns such as cloud scrolls, constellation points, angular seals, scale carving, or mineral veining.
- Plan batches before generation: across every eight icons, use at least four dominant hue families and keep jade/green to at most two unless the objects specifically require it. Rotate motifs across cloud scrolls, constellation points, angular seals, scale carving, banded strata, lacquer, and mineral veining.
- Keep motifs subordinate to the silhouette and one identifying detail. Preserve the shared gouache finish, ink contour, upper-left light, and restrained highlights across all palettes.
- Keep the silhouette and one identifying detail readable at 32×32. No letters, labels, borders, or cast shadows.
- Reuse a category/subcategory family from `game/assets/asset-index.jsonl`. Generated PNGs are the painted target; SVGs cover families without a generated seed. Item names, elements, and grades can use UI tint or badges instead of one image per variant.
- `id_prefix` and `id_regex` rules override category/subcategory families for distinct object forms.
- `item_ids` links each current item seed to its family in the same SSOT index. Run `uv run python -m tools assets sync` after item/rule edits, then `uv run python -m tools assets audit`; `report` shows coverage and distribution.
- Optional `visual_traits` use `axis:value` tags such as `form:robe`, `presentation:female`, `palette:cinnabar`, and `motif:cloud-scroll`.
- Review palette, forms, tags, and the 2,000 unique-image floor with `uv run python -m tools assets report --diversity` before planning generation batches.

## Top-down world map

- Camera is orthographic and straight down: show ground-facing silhouettes and top surfaces, with no horizon, isometric projection, or perspective convergence.
- Preferred rendering reference: anime-painted gouache, dark `#263A35` ink contours, broad readable value planes, material-led colors, and restrained upper-left light.
- Keep terrain quieter than props with broader value planes and less surface detail; keep the camera strictly overhead even for architectural subjects.
- Reserve warm ivory and antique gold for readable focal details. Terrain hues follow material and environment; Qi azure, Body gold, and Mind violet are restrained faction accents, not full-scene filters.
- Start each environment with an opaque 1024×1024 terrain surface texture. Compose indexed transparent props over that surface from a JSON layout with `uv run python -m tools assets map compose`; keep each source sprite separate so layouts stay editable. Each index record defines `footprint_cells` at a 128 px unit. Grid layouts set `grid.cell_px`, `columns`, and `rows`; integer `cell: [column, row]` coordinates name the top-left footprint cell. Center-pivot art is centered in its footprint; bottom-center art rests on its lower edge. `overlap: "forbid"` reserves grid cells touched by pixels with alpha 128 or higher; `overlap: "allow"` permits intentional visual layering. `show_grid: true` draws a preview overlay. The composite is a map preview, not a replacement for the terrain and sprite layers.
- Model-authored tiles are optional follow-up pieces; do not depend on them for the base terrain. Props use 128–512 px canvases and a bottom-center ground pivot; decals use a center pivot. Props keep shadows short and attached to the footprint; painted shadows never imply collision. No baked labels or UI.
- Keep walkable ground low contrast. Make blockers, harvest nodes, routes, domain entrances, and landmarks distinct by silhouette and placement. Decorative flora, decals, and effects carry no collision unless the index says `solid`.
- Build coherent environment sets across the Mortal, Spirit, Immortal, and Transcendent worlds plus authored domains. Environmental variants change form and material to fit the place; hue-only recolors do not count as separate art.
- `environment_theme` in the map index is each region's generation brief for materials, silhouettes, and terrain forms; carry it into every asset prompt.
- The style target is a native-scale patch with one actor, ground, blocker, resource node, and landmark together. Approve its scale and contrast in-game before generating full batches; no gameplay capture is approved yet.
- `game/assets/map-asset-index.jsonl` tracks each planned or produced map asset. Run `uv run python -m tools assets map report|audit`; `assets map scaffold` creates the initial plan only when no index exists.

## Character LoRAs

- Krea2 character generation exposes all 32 adapters from the configured workflow; every adapter defaults to strength 0. Enable adapters selectively and record exact weights with reviewed outputs. LoRA effects depend on prompt, seed, and combinations, so filenames alone are not evidence of style or role.
- Character profiles balance cultivation, modern, frontier, spirit, court, and future settings; varied clothing; child, teen, adult, and elder ages; visible disability; and non-graphic injuries. Children and teens always use age-appropriate, non-revealing clothing. Adult swimwear and other revealing non-nude outfits are allowed.
- Disability traits are shown naturally and respectfully, including wheelchairs, canes, prosthetics, hearing aids, and limb differences. Injuries use clean bandages, slings, braces, or healed non-graphic scars; exclude gore and exposed wounds.
- The user previously preferred Dishwasher + Meion Style at strength 1, but a small character sample also showed lowered gaze. Treat this as a historical observation, not a default: keep both at 0 and retain direct-gaze instructions in character prompts.
- Ephemeral Elegance was also observed to lower gaze and remains at 0. Hentai Studio Quality remains at 0 under the project's nonsexual-art rule.
- The two pose adapters, More Dynamic Poses and v67 Pose Framing, are available for experiments; their effects and interaction with map-sprite framing have not yet been validated.
- No evil-character adapter or combination has been verified. Explore the style adapters one at a time with a consistent character prompt and seed, then compare any candidate combination. Keep evil characterization in nonsexual visual cues such as severe expression, dark materials, controlled posture, and ominous motifs until a specific adapter effect is demonstrated.

## Technical target

Godot 4.7, 2D, transparent 256×256 PNG item art and SVG family symbols. SVGs use a 64×64 view box. In-game sizing and filtering follow the consuming UI. No representative in-game capture exists yet.
