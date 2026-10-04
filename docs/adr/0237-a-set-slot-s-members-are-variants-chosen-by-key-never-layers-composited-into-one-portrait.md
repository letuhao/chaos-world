# A set slot's members are variants chosen by key, never layers composited into one portrait

Status: accepted

## Decision

A **set slot** — `expression_set`, `pose_set` — contributes **at most one member** to a portrait's
`layer_paths`, and only when it is *the selected variant*. Its other members are **alternatives**,
reachable through ADR 0177's variant mechanism, never pixels stacked on the same face.

`character_bundle_sync` therefore composes only slots that are genuinely layers of one image:
`map_sprite` and `dialogue_portrait` (and `character_portrait` as the base). A set slot with no
selected variant contributes nothing.

## Why

`core/portrait_def.gd:37-39` defines `layer_paths` as "the composable layers, back to front", and
`PortraitPanel` composites each over the last. That is correct for a base plus regalia. It is
**wrong for a set**: nine expressions and six poses are fifteen alternative renderings of the same
character, and compositing them puts fifteen faces on one portrait. The result is not a bad
portrait, it is an unreadable one, and it passes every gate — the files exist, the canvases match,
and `PortraitResolver.validate()` only checks that `layer_paths` is non-empty.

The failure is silent because it looks like success. `install_plan` reported "19 layers
installable" for `unique-0001` and would have written a `.tres` that no reviewer could tell was
wrong without opening all fifteen PNGs.

**Two vocabularies, one field.** `layer_paths` answers "what is drawn on top of what"; ADR 0177's
`axis:value` trait answers "which one of several". A set is the second question. Writing the first
to answer the second is how a resource ends up technically complete and visually impossible.

## Consequences

- A portrait's layer count is bounded by the number of *slots*, not the number of *shots*. Two for
  `unique-0001` today: the dialogue portrait and the map token.
- `character_bundle_sync` publishes `character_portrait` / `dialogue_portrait` / `map_sprite` and
  names every set member it skipped, so an author learns that nine expressions are reachable *by
  variant* rather than concluding they were lost.
- A variant request for `expression:flat-with-fatigue` resolves through
  `PortraitCatalog.for_variant`. A portrait carrying the trait answers; one that does not falls
  back to the base face and reports `variant_found: false`, so totality (ADR 0131) holds.
- **A set member is not automatically a variant.** `declares_variant` matches the whole
  `axis:value` string, so `expression:flat-with-fatigue` is only selectable on a portrait whose
  `visual_traits` actually declare it. Selecting one is an authoring decision, not a side effect of
  the shot existing.
- The `daily_life` family is unaffected: one character, one occasion, one shot — a scene, not a set.
  Its canon minimum counts DISTINCT dayparts (ADR 0178), which is a content gate on the catalog and
  not a compositing question.