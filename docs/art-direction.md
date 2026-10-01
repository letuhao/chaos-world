# Art direction

## Visual identity

Cultivation-fantasy relic illustration: calm, mystical, handmade, and legible at inventory size. Use painterly gouache, fine ink-dark green contours, jade and mineral colors, and a little antique-gold detail. Light comes from upper left; keep shading to broad planes. Avoid modern props, text baked into art, heavy gradients, noisy texture, and sexualized imagery.

## Item icons

- One centered object on transparent background; no baked labels, borders, or scene.
- Generated PNGs are 256×256 and composed to read at 48 px; lightweight family symbols use a 64×64 SVG view box.
- Use the shared palette: ink `#263A35`, jade `#739B83`, pale jade `#D8E6D3`, warm ivory `#F2E8D2`, cinnabar `#B75F4A`, antique gold `#C49A53`, mineral blue `#668AA0`, violet `#82739B`.
- Keep the silhouette and one identifying detail readable at 32×32. No letters, labels, borders, or cast shadows.
- Reuse a category/subcategory family from `game/assets/asset-index.jsonl`. Generated PNGs are the painted target; SVGs cover families without a generated seed. Item names, elements, and grades can use UI tint or badges instead of one image per variant.
- A rule with `id_prefix` overrides its category/subcategory family; use it when one subtype contains distinct object forms.

## Technical target

Godot 4.7, 2D, transparent 256×256 PNG item art and SVG family symbols. SVGs use a 64×64 view box. In-game sizing and filtering follow the consuming UI. No representative in-game capture exists yet.
