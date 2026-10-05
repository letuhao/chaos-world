# 0219 Depth is the tier and the band is the fight, so a domain has no layer field

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0254

## Context

BL-0254 asks whether a domain needs a "layer" field, and its own `next` already answers
no: `LootState` rule E2 refuses re-entry at or below `cleared_tier`
(`loot_state.gd:201-207`), the ledger key is `run_key(domain_id, tier_index)`
(`loot_state.gd:114`), and `LootTier` is the ordered, persisted, monotonic axis
(`loot_tier.gd:34-40`).

The open half is what escalation *is*, and there are three candidates in the repo already
and they are routinely confused:

- `LootTier.realm` / `.rarity` — the **drop context**. ADR 0166 ruled the band does not set
  a drop's magnitude; it owns rarity and draw count.
- `LootTier.vitality` — the **fight**. ADR 0199 generates it as
  `HITS_TO_KILL * BASE_HEALTH * RealmDef.power(realm)`.
- `DomainTemplateDef` / `DomainMap.seed` — the **map**. A template is a room pool; a seed
  is the layout of that pool (`ember_grotto.tres`, `stormwrack_reach.tres`).

## Decision

**A domain's difficulty across bands is carried by the TIER alone. It is not a new field
on the domain, and it is not a `layer` field anywhere.**

The one sentence: **the tier buys everything, and each of the three things it buys is
already authored on the tier.**

1. **The fight** — `LootTier.vitality`, and `LootTier.attack_for` / `defense_for` which
   price the boss's offense and defense off that same number (`loot_tier.gd:67-74`). One
   authored number already prices both halves, which is ADR 0076's ruling.
2. **The depth** — a different authored band means a different `domain_id`, a different
   `template_id` and seed, and therefore a different map with different rooms. Depth is
   expressed by *what the run is built from*, not by a flag on the run.
3. **The prize** — a different authored band binds different `boss_tables`
   (`loot_ember_vault.tres:13-17` vs `:26-30`: three tables at tier 1, three at tier 2).

**Why it is not a field on the domain.** A `layer` field would be a second ordered axis
next to the tier, and every one of the following would need it: the entry gate, the
persisted ledger key, the "cleared" predicate, the reward's claim token, and the minimap.
The tier already answers all five. A second axis does not add depth, it adds the question
"which of the two applies", and every existing rule would have to grow a tie-break.

**Why it is not a field on the template either.** A template is a *room pool* (ADR 0073),
and a pool is chosen by a seed. Depth is the seed's parameter, not the template's property:
the same `ember_grotto` pool assembled with a deeper pin set is the same kind of place,
deeper. A `layer` on `DomainTemplateDef` would make "deep" a thing you author once instead
of a thing you reach, which is exactly the wall BL-0848 is full of.

**One-shot per band is the correct answer, not a limitation.** E2 refusing re-entry is what
makes a band a *story* — a thing that happened once — and it is what lets the prize be an
object (ADR 0216) rather than a trickle. A domain that restocked would have to pay its
rewards in materials forever.

## Consequences

- **BL-0254 closes with no code and no data.** The model is already built; this ADR names
  it so the next agent does not add the field.
- **The bound is the content wave**: escalating a domain means authoring the next band, not
  adding a field. That is more work per band and it is the correct trade — a band authored
  is a band that is exactly the fight the designer wanted.
- **Do NOT add a restock timer.** E2 is tested behaviour; a timer would be a second answer
  to a question the ledger already answers.
- `LootTier` is already at the cap of what one resource should own (realm, rarity, vitality,
  boss_tables). If a future band needs one more authored dimension it belongs as a
  `boss_tables` binding's optional `vitality` (`loot_tier.gd:59-61`) or as a new tier —
  never as a domain field.
- The `DomainMap`'s own size does not scale with tier. A deeper band is a **deeper
  template**, not a bigger `extent` on the same one, so the generator's node budget
  (`ember_grotto.tres` min 6 / max 10 rooms) stays a constant per template.

## Rejected

- **A `layer` integer on `DomainDef`.** Rejected: two ordered depth axes, two gates, one
  encounter id. BL-0254 names this exact failure.
- **A restock / refresh timer on a cleared band.** Rejected: it converts a finished
  experience into a chore and makes every authored prize perishable.
- **Scaling `RoomDef.roster_band` by tier.** Rejected: `roster_band` is the room's
  authored *shape* band (ADR 0073, `room_def.gd:76-79`), and a tier that rewrote it would
  make the same `.tres` mean two different things depending on which run placed it.
- **A `depth` scalar multiplying vitality.** Rejected: `RealmDef.power` already supplies
  551x across the ladder (ADR 0199). A second multiplier on top of it is a
  power-shaped number with no owner.