# A fallback silhouette's colour is transcribed from the Lore Bible when no RaceDef exists

Status: accepted

## Decision

`tools portrait_fallback` derives a body plan's fallback silhouette from **two sources, in this
order**, and the order is the rule:

1. **`game/data/races/*.tres`** — an authored `RaceDef`. The game reads these, so an authored
   affinity outranks the Bible wherever the two disagree.
2. **The Lore Bible's `races.<id>` entities** — for every species the character catalog names that
   has no `RaceDef`.

The species list comes from **the catalog**, not from either race table. A tool driven by the race
table alone answers a question nobody asked.

## Why

Measured: 401 characters name **30** species; the race table holds **5**. Only 4 of those 5 are
species the cast actually uses, so `commonborn`/`emberblood`/`stoneborn`/`tidecaller` served **54**
characters and **347 had no fallback at all**. `_fallback_layer` returns `None` for those, so
`character_bundle_sync publish` refused them outright — a body plan with no silhouette is not
cosmetic, it is a character that cannot be drawn at all.

That is DEF-0313, and it was never really about the 17 `unique-0001` layers it was filed against.
Those were visible; the 347 were not, because a character with no def simply does not appear in the
def directory to be counted.

## Consequences

- **A tint is transcribed, never invented.** The Bible carries `affinities` per species, so a
  species with no `RaceDef` gets the colour its authored affinities imply — the same discipline as
  ADR 0253, for the same reason: a second place to retune a body's identity is how two copies drift.
- **An affinity with no assigned hue is NEUTRAL, not a new colour.** `dark`, `light` and `wind` lead
  15 of the 30 species and have no entry in `AFFINITY_RGB`, so those bodies share the neutral
  placeholder. Assigning an element a hue is art direction and belongs in `docs/art-direction.md`;
  this tool will not decide it. **GAP, reported rather than resolved:** the palette needs three
  more entries, and until it does, 15 of 30 species are indistinguishable placeholders.
- **A tied top affinity yields neutral.** A body with two equal affinities has no single identity and
  must not be handed one by a sort order. Shared as one helper with the `.tres` path so the two
  sources cannot disagree about what "dominant" means — the same reason `_visual_traits` is shared
  between `build_def` and `_fallback_def`, where a retyped copy reproduced the ambiguity it was
  written to prevent.
- **34 silhouettes, ~0.1 MB total.** Two ellipses and a rounded shoulder per body, drawn from
  primitives rather than traced from a render: a fallback that resembles a specific person is one
  that will eventually be mistaken for them.
- **A silhouette is a placeholder, not a portrait.** It says which body plan you are looking at. It
  is not the character's face, and no screen may present it as one.
