# 0166 A drop pays its item's own rung, so a rolled relic does not move and the band stops paying magnitude

- **Status**: accepted
- **Supersedes**: ADR 0157 — only the question it deferred, whether a rolled entry may
  move. Its magnitude-table ruling and its guaranteed-entry placement are re-asserted here.

## Context

`tools/cultivation/loot_magnitude.py`, both scopes, 2026-10-04:

- **8084** reachable direct entries; **6310** pay a rung that is not their item's own.
  Gate (guaranteed reagent) **3**, rolled reagent **0**, seeded consumable **64**,
  residual **6243**.
- **The gate is not green.** Three failures, in committed and clean files:
  `loot_qi_earth_immortal_guardian.qi_earth_immortal_guardian_core_0` (owes
  `earth_immortal` 2.80x, paid `qi_refining` 1.00x),
  `loot_puppet_ash_effigy.puppet_ash_effigy_domain_21` (owes `nascent_soul` 1.30x,
  paid `foundation` 1.10x),
  `loot_qi_spirit_condensation_guardian.qi_spirit_condensation_guardian_core_0` (owes
  `spirit_condensation` 1.90x, paid `foundation` 1.10x).
- The residual is **6066** distinct items over **333** tables, **160** domains, all
  **30** owed realms. **All 333 tables are paid by exactly one band**; none spans two.
  Median **13** distinct owed realms per table (min 1, max 25). **4630 of 6243** cross a
  10-realm tier boundary; the gap runs the full **−29…+29**; paid/owed min 0.26,
  **p50 0.60**, max 3.90. **4705** underpay, **1538** overpay.

So it is one band paying a whole catalogue, not a handful of mislabelled bands, and it
is total rather than marginal.

Two facts fix the shape of any fix:

- **The magnitude authority is already the item.** `ItemGenerator.roll` hands `def.realm`
  to `OptionCatalog.roll_next` (`item_generator.gd:46`). The one thing that substitutes
  the band is `LootRewards.contextualize`, whose `copy.realm = realm`
  (`loot_rewards.gd:111`) is the entire mechanism behind all 6310.
- **The band's realm is a documented fallback.** `chain.py:696-705` picks it *lowest*
  "because the label is a drop-context *fallback* and a wrong-high fallback hands out
  loot scaled above its authored magnitude", and calls it "never actually consulted for
  a world domain". `design.py:70-72`: the band is "a statement about difficulty, not
  about which realm a drop belongs to".

The only prose saying otherwise — `loot_rewards.gd:83`, `loot_table_def.gd:17-19` — is
the defect describing itself.

## Decision

1. **A drop realizes at its item's authored rung.** `contextualize` keeps `def.realm`
   and overrides rarity only. The band keeps what it owns: rarity, `rarity_floor`,
   `quality_steps`, draw count, `quantity`/`quantity_max`.
2. **No rolled entry moves, ever.** ADR 0157's placement rule stands for the
   **guaranteed** class, which is acquisition-neutral. Nothing rolled moves.
3. **No part of the 6310 is correct by design**, so there is no by-design subset to
   exempt; the band's realm is a fallback by its own documentation.
4. **`item_magnitude_scale.json` is not touched** (ADR 0157's first decision, kept).
5. **`loot_rewards.gd:83` and `loot_table_def.gd:17-19` are amended, not preserved** —
   they are the only statements of the superseded rule.
6. **The 53 guaranteed reagents ADR 0157 already moved are not reverted.** Under (1)
   their placement is redundant for magnitude, not wrong, and reverting 53 files buys
   nothing.

## Why placement was rejected for the rolled class

Four measured blockers, any one disqualifying. A migration needs one pool per owed realm
per table: **4380** `(table, realm)` groups, **488** already on disk.

- **It truncates.** Median **13** pools per table, max **25**, so a table with `G` pools
  yields `G` plans where it yielded 1, and `MAX_PLANS_PER_RESOLVE = 12` discards the
  rest behind `WARN_TRUNCATED`. **279 of 333** truncate; **318** exceed
  `MAX_DROPS_PER_RESOLVE = 8`. A `guaranteed` nesting entry makes that amplification
  deterministic rather than probabilistic. A silent drop is worse than a visible
  mis-payment.
- **It soft-locks.** **2679** of 6243 residual entries are an input to a shipped recipe
  and **13** are ruled `mind_sea_catalyst` in `progression_roles.json`. Rule E2 grants no
  second run, so rolling any of them is the DEF-0187 / DEF-0199 permanent-miss class
  against a realm gate.
- **It is not acquisition-neutral.** A rolled entry goes from 1 of `N` candidates to 1
  of `N` pools times 1 of `M`. ADR 0157's guaranteed-only rule exists for this reason.
- **The corpus is half-migrated, and that is why it is unfinishable.** 1083 pools already
  ship (`seed.py:_pool_entries`, `design.DRAWS = 1`) and `chain.py:701-705` claims every
  generated drop is a pool entry. Finishing inherits all three blockers above.

**Rejected too: "the band may raise a drop's rung but never lower it."** It reinstates
the hazard `chain.py:700` names — `R25_mortal_plover_clasp` is authored `qi_refining`,
so a floor keeps it at **3.90x**, which is exactly "scaled above its authored
magnitude" — and it makes a new power-shaped rule, which AGENTS.md reserves for an ADR
with an owner ruling.

## Cost

- **4705 drops get stronger**, up to 3.90x: a band no longer caps magnitude. The band
  keeps its difficulty meaning through `design.TIER_RARITY` (tier 2 one rarity up),
  `quality_steps` and `rarity_floor` (`loot_resolver.gd:249-254`).
- **1538 drops get weaker**, up to 3.90x. A player-power reduction, and the one number
  wanting an owner ruling. Correct direction — the item was never authored that strong.
- **Blast radius: one function, one tool scope, one test.** Zero `.tres`, zero new data
  files, zero new pools. The 1774 already-correct entries are unaffected, and the 3 gate
  failures are fixed by the same change.

## Guard

`game/tests/modules/loot/test_loot_band_magnitude_ruling.gd` reads SOURCE, because after
the change a corpus scan is trivially satisfied and before it the scan is red on 6310
entries for reasons that say nothing about the decision. All green today and after:

- at most one place in `res://src/modules/{loot,items}` writes a drop's realm onto an
  `ItemDef`, and it is `LootRewards.contextualize` — the one-function claim cannot
  quietly become two;
- `contextualize` is still named and still reached with the drop's realm;
- `ItemGenerator` reads `def.realm` and never a tier, band or context realm;
- `LootResolver._plan` still reports the band realm, because the change belongs at
  realization.

Plus a corpus canary: shipped `_pool_` tables are **ceilinged at 1200** against a measured
**1086** files (1083 parsed tables), so executing the rejected alternative — which needs
4380 pools and lands near 4978 — fails the build.

## Tool change to build (not built here)

In `tools/cultivation/loot_magnitude.py`. No new dependencies.

**`check --scope magnitude`** — asserts the mechanism, because that is the only thing
that still means anything once the change lands.

- *Inputs*: `loot_rewards.gd`, `item_generator.gd`, `loot_resolver.gd`.
- *Rules*: (a) at most one assignment matching `\.realm\s*=` whose left side is a
  definition copy across `res://src/modules/{loot,items}`, and it must be in
  `loot_rewards.gd`; (b) `item_generator.gd` has `def.realm` and none of
  `context.get("realm"`, `tier.realm`, `context.realm`, `band.realm`; (c)
  `loot_resolver.gd` still reads `context.get("realm", &"")`.
- *Output*: one `fail <path>:<line> <rule> <found>` per violation, then `ok` naming the
  rule count; exit 1 on any.
- *Proof it fired*: exactly one violation today, rule (a) at `loot_rewards.gd:111`, and
  zero after. Rule (a) is a **count**, so 1 (today) and 0 (after) pass and only 2 fails.

**`report --scope drop`** — makes the ruling legible per entry, since "which of the 6310"
is a balance question and `report` prints only the gate's three.

- *Inputs*: `Graph`, `load_scale()`, `data/items/progression_roles.json`, and
  `data/recipes/*_recipe.tres` `inputs = Array[StringName]` for the blocked set.
- *Output*: one row per mis-paid entry —
  `item | table | entry_id | band | item_realm | delta_rungs | direction | blocked_by`,
  `direction` in `under`|`over`, `blocked_by` in `role:<role>`|`recipe`|`-`; then totals.
- *Proof it fired*: `under` + `over` must equal **6243** and `blocked` **2679**, or the
  corpus moved and this ADR's numbers are stale.

**`check --scope movable`** — the canary the GDScript test cannot compute cheaply.

- *Inputs*: `mispaid()` minus `reagents | seeded_consumables`, the scale table, the blocked
  set, and `MAX_PLANS_PER_RESOLVE` (12) / `MAX_DROPS_PER_RESOLVE` (8) as literals with the
  `file:line` named.
- *Output*: per residual table its `realm_groups`, then 4380 groups / 1083 shipped pools /
  488 already present / 318 tables at or above 8 groups / 279 at or above 12, then a
  single `fail` naming the first table that could be migrated without truncation.
- *Proof it fired*: `fail` names the first of 279 tables over the plan cap.
