# Art direction

## Visual identity

Cultivation-fantasy relic illustration: calm, mystical, handmade, and legible at inventory size. Use clear object silhouettes, ink-dark green outlines, jade and mineral fills, and sparing antique-gold details. Light comes from upper left; keep shading to broad, quiet planes. Avoid modern props, text baked into art, heavy gradients, noisy texture, and sexualized imagery.

## Item icons

- 64×64 view box, transparent background, one centered object with breathing room.
- Use the shared palette: ink `#263A35`, jade `#739B83`, pale jade `#D8E6D3`, warm ivory `#F2E8D2`, cinnabar `#B75F4A`, antique gold `#C49A53`, mineral blue `#668AA0`, violet `#82739B`.
- Keep the silhouette and one identifying detail readable at 32×32. No letters, labels, borders, or cast shadows.
- Reuse a category/subcategory family from `game/assets/asset-index.jsonl`. Item names, elements, and grades can be expressed by UI tint or badges; do not make a new icon for every variant.

## Technical target

Godot 4.7, 2D, SVG texture, 64×64 view box, transparent background. Icons are authored as family defaults; in-game sizing and filtering follow the consuming UI. No representative in-game capture exists yet.
