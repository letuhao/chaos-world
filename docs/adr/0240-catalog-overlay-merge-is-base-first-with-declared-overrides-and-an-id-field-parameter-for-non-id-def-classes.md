# 0240 Catalog overlay merge is base-first with declared overrides and an id-field parameter for non-id def classes

- Status: Proposed
- Date: 2026-10-05
- Extends: ADR 0184 (mods are first-class content)

## Context

Mods add content to existing families (items, world locations, techniques) via `content_roots` in their manifest. The base game and each mod contribute defs to the same family catalog. Without a merge policy, two defs with the same id silently collide — the later load wins, the earlier is lost, and no error fires (ADR 0066's duplicated-constant trap).

## Decision

1. **Base-first overlay merge.** The base game's content root is scanned first; mods overlay in load order. Later roots win by default — a mod's def replaces the base def with the same id.
2. **Declared overrides only.** A later root may replace an earlier def ONLY when the later root declared that id in its `overrides` list. An undeclared id collision is a loud boot error (`undeclared_override`), never a silent overwrite.
3. **`id_field` parameter.** Each `content_roots` entry accepts an optional `id_field` string. When the family's def class uses a property other than `id` as its identifier (e.g. `WorldLocationDef` uses `location_id`), the mod must declare `id_field: "location_id"`. Without it, the merge reads the wrong property, finds no id, and the content is silently invisible.

## Consequences

- A mod adding world locations MUST declare `id_field: "location_id"` in its `content_roots` entry or its content is invisible — the merge skips defs whose id property is absent.
- An undeclared id collision aborts boot with a named cause (`undeclared_override`) naming the id, both paths, and both owners.
- A declared override wins and is logged at boot.
- The merge is keyed by authored id, never by array position (ADR 0050).
- `CatalogOverlay.merge` is static and pure: same stack, same result.
