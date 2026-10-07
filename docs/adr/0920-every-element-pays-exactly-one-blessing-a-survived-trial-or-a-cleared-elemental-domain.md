# 0920 Every element pays exactly one blessing: a survived trial or a cleared elemental domain

- Status: Accepted
- Date: 2026-10-08

## Context

The element status catalogue is a closed pair set: two defs per element, ten mechanics, pinned by ADR 0090/0110 and by `test_status_catalogue.gd`. Only `wood_bloom`, `earth_bulwark` and `light_halo` were CULTIVATION scope, so a survived tribulation paid a blessing for three of ten elements and nothing for the rest — the `cultivation_status` column of `game/data/elements/element-coverage.jsonl` stood empty for seven.

The gap could not be closed by re-scoping an existing def: the seven elements' second defs are live COMBAT content (`fire_pyre` amplifies its siblings, `dark_wane` and five siblings are boss AFFLICTIONS), and a combat def may not become a permanent cultivation gift. Nor by adding a pair member: the catalogue's own tests pin exactly two defs and two mechanics per element. So the blessing is a THIRD def, and the pair rules move with it.

## Decision

- **Seven new CULTIVATION defs**, one per element that had none: `metal_temper`, `water_wellspring`, `fire_forge`, `lightning_quicken`, `ice_stillness`, `wind_stride`, `dark_veil` (`game/data/statuses/metal_temper.tres:7`). Each is `scope = cultivation`, `duration = -1.0`, `kind = stat_modifier`, carries its element's authored family word, two modifier rows, and mitigation tags — the shape the three original blessings already had. Every element now ships EXACTLY ONE cultivation def: the pair's second member where that member already is the blessing (wood, earth, light), a third def otherwise.
- **The pair claims now read on the pair**: `test_status_catalogue.gd` filters the seven new ids out of the ADR 0090/0110 mechanics, channel and vocabulary assertions, while the id SET pin moves to the twenty-seven and a new per-element rule asserts exactly one cultivation def. In `TribulationBlessing` the blessing is still taken by SCOPE (`blessing_for`), never by a restated list.
- **Two producers cover all ten elements.** The trial rows (`REWARD_TABLE`) were reassigned to six elements — `lightning`, `wood`, `earth`, `metal`, `ice`, `dark` — and a second table, `DOMAIN_TABLE` (`game/src/modules/status/tribulation_blessing.gd:81`), maps the six elemental domains onto their elements (`ember -> fire`, `tide -> water`, `gale -> wind`, `terra -> earth`, `aether -> lightning`, `prism -> light`). Together they pay every element at least once.
- **A cleared domain pays through the loot facade**: `TribulationBlessing.award_domain` (`game/src/modules/status/tribulation_blessing.gd:178`) resolves the domain's element and applies the blessing; `StatusApi.apply_domain_blessing` (`game/src/modules/status/api.gd:406`) is the facade verb; `LootApi.strike` calls it once per clear, reading the domain id the state machine reports and erases for that strike (`game/src/modules/loot/api.gd:145`). No loot-side element vocabulary exists: the status module owns the mapping.
- **The coverage tool learns the second producer**: `element_coverage.blessing_elements()` reads `DOMAIN_TABLE` as well as `REWARD_TABLE`, the per-element rule becomes "its pair plus at most one blessing, named in the row", and every row must name a cultivation status.

## Consequences

- All ten elements pay a permanent blessing, reachable in production: six through a survived tribulation, six through a cleared elemental domain (two elements have both).
- A domain clear pays once per BAND — the loot module's own rule E2 refuses a re-entered cleared band — and a second band re-applies the same permanent status, which is a refresh rather than a second gift.
- `test_status_cultivation_reach.gd` drives both producers end to end: a real tribulation fight for the trial-paid six, and a real domain run (enter, strike, clear) through `LootApi` for the domain-paid four.
- The mechanics vocabulary is unchanged: the blessings reuse `brace` and `regrowth`, so `StatusDef.MECHANICS` still resolves exactly the ten authored shapes.
- The three original blessings keep their pair membership; only the seven new ones sit outside a pair, which is why the catalogue is twenty-seven rather than thirty.
