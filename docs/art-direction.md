# Art direction

## Visual identity

Cultivation-fantasy relic illustration: mystical, handmade, and legible at inventory size. Use painterly gouache, fine dark ink contours, material-led color, and restrained metallic accents. Light comes from upper left; keep shading to broad planes. Avoid modern props, text baked into art, heavy gradients, noisy texture, and sexualized imagery.

## Item icons

- One centered object on transparent background; no baked labels, borders, or scene.
- Generated PNGs are 256×256 and composed to read at 48 px; lightweight family symbols use a 64×64 SVG view box.
- Palette roles: ink `#263A35`, warm ivory `#F2E8D2`, antique gold `#C49A53`. Material colors include jade `#739B83`, pale jade `#D8E6D3`, cinnabar `#B75F4A`, mineral blue `#668AA0`, and violet `#82739B`; these are options, not a default set.
- Choose color from the object's material and identity. Jade and green are one family among cinnabar, amber, blue, violet, ivory, iron, and mixed metals. Across a batch, vary both dominant hue and surface motif; use fitting patterns such as cloud scrolls, constellation points, angular seals, scale carving, or mineral veining.
- Keep motifs subordinate to the silhouette and one identifying detail. Preserve the shared gouache finish, ink contour, upper-left light, and restrained highlights across all palettes.
- Keep the silhouette and one identifying detail readable at 32×32. No letters, labels, borders, or cast shadows.
- Reuse a category/subcategory family from `game/assets/asset-index.jsonl`. Generated PNGs are the painted target; SVGs cover families without a generated seed. Item names, elements, and grades can use UI tint or badges instead of one image per variant.
- `id_prefix` and `id_regex` rules override category/subcategory families for distinct object forms.
- `item_ids` links each current item seed to its family in the same SSOT index. Run `uv run python -m tools assets sync` after item/rule edits, then `uv run python -m tools assets audit`; `report` shows coverage and distribution.

## Technical target

Godot 4.7, 2D, transparent 256×256 PNG item art and SVG family symbols. SVGs use a 64×64 view box. In-game sizing and filtering follow the consuming UI. No representative in-game capture exists yet.
