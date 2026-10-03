# 0105 A landed blow applies its element's status from the exchange, and the spine stays unbuilt

- Status: Proposed
- Date: 2026-10-03
- Amends: ADR 0087 (S12 placement), read against ADR 0067 and ADR 0076

## Context

The status system is built and unreachable. `StatusApi.apply` (`modules/status/api.gd:60`)
has no production caller, and ADR 0087's S12 (`modules/combat_engine/status_apply.gd:161`)
runs only from `CombatSpine.resolve_hit`, which nothing calls: `CombatEngineApi` appears
in `game/src` only inside a comment (`modules/techniques/technique_casting.gd:35`).

The player's real blow is `CombatExchange.exchange` (`modules/combat/exchange.gd:48`), which
builds its own generator at `exchange.gd:61-62` and resolves through
`CombatDamage.resolve_hit` (`modules/combat/damage.gd:62`) — a pure share-of-pool function
returning `{share, crit, evaded, power, mitigation}` and never naming an element.

**The conflict, named.** ADR 0067 mandates ONE spine in `modules/combat/`, "unchangeable
without an ADR". ADR 0076 mandates that `CombatDamage.resolve_hit` is "the whole damage
model", the exchange is press-driven and has "no time axis". ADR 0087 then placed status
application on a spine ADR 0076's decision made unreachable. Those two Accepted ADRs
cannot both be the player's fight, and 0087 is `Proposed`, so it is the one that yields.
Nothing here decides a new damage model.

**Two measured facts decide the shape.** The boss is **not an `Actor`**: it is a
`Dictionary` in `actor.module_data` (`modules/loot/loot_state.gd:523-547`, frozen
`attack`/`defense`/`vitality`), so `StatusApi.apply(actor, …)` cannot be pointed at it at
all. And the player's blow is **elementless** — `CombatExchange.offense`
(`exchange.gd:92`) reads four stat ids and no `element_power_<e>`, because
`ElementsApi.attach` has no production caller (ADR 0088's own consequence).

## Decision

**The producer is one status call inside `CombatExchange.exchange`, gated on a landed
blow and an authored `status_chance`. S12 is retired as the application site, not
re-routed; the spine is not built to reach it.**

- **One call site: `CombatExchange.exchange`, after `LootApi.strike` returns (`:64`) and
  before the `_still_standing` branch (`:83`)**, so a killing blow applies nothing and the
  call never runs on a refused exchange. The gate is `not evaded`. ADR 0087's `is_clean()`
  has no counterpart in ADR 0076's model, but its reasoning transfers verbatim:
  `CombatDamage.resolve_hit` already returns `evaded` (`damage.gd:66,84`) from the same
  single draw, so a blow that was avoided applies nothing and a landed blow may.
- **The roll is a SUBSTREAM of the exchange's own generator, never a draw off it.** That
  stream is already shared with the boss's return stroke (`exchange.gd:177`), so
  consuming from it would re-roll the answer. The seed is
  `StatusApply.status_seed(rng.seed, actor, target, technique, hit_index)`
  (`status_apply.gd:392`), the ADR 0087 shape which is `LootState._encounter_seed`'s exact
  form. `status_seed` (`:392`) and `potency_of` (`:361`) are `combat_engine`'s own code and
  are called in place — no new facade verb and no registry edge, because `combat` already
  declares `contracts` and `core` and the per-element ids are string prefixes on
  `CombatTuning`.
- **The status id comes from the ATTACKER'S ELEMENT, read through the status module.**
  `status/api.gd` gains one verb: `status_for_element(element, chance) -> StringName`,
  returning `""` for an unelemental or refused one. It is the element→status mapping ADR
  0090's catalogue implies and ADR 0087 assumed but never placed: the authored
  `.tres` under `game/data/statuses/` already names one `id` per tier-1 element.
  It lives in `status` because the catalogue is `status`'s content, and ADR 0090's own
  rule is that a def belongs to its owning module — an element→status table authored in
  `techniques` or `combat` would be a second copy of a file that already exists.
- **`TechniqueDef` gains NO status field.** Verified: `technique_def.gd` authors `element`
  (`:28`) and `element_share` (`:96`) and no status key; ADR 0056 puts a def in its owning
  module, and `techniques` is at the 12-method facade cap so exposing anything new needs a
  split. The element is already the authored carrier: ADR 0088 states mastery "never gates
  a status by name" and a status is unlocked "by its element's tier … and by authoring it
  on a technique" — the mapping above IS that authoring, and a per-technique override is
  additive later.
- **Potency reuses `element_power_<e>` exactly as ADR 0088 decided**
  (`StatusApply.potency_of`), so no new stat id and no second magnitude vocabulary. Where
  that id is `0.0` today the floor (`status_potency_floor`) applies; ADR 0088 already
  accepted that and named the dependency.
- **The status rides the ATTACKER, not the defender, this pass.** `exchange.gd:78`
  applies to `actor` (the player), and the exchange's return dict gains
  `status: {applied, id, potency}` — primitives only per ADR 0038, so a screen renders it
  unchanged. This is what makes the player a *subject* of a status for the first time and
  gives `summary()` something real to report.

**Rejected, and why.**

- **Route the exchange through `CombatSpine` (Option B).** It requires a `DamageMechanism`
  bound per actor (`combat_engine/api.gd:47`) and rewrites ADR 0076's damage model, whose
  share-of-pool form is exactly what makes a 551x realm table meet 12x authored vitality
  safely. S12 is one stage of twelve; paying for it by replacing the shipped model is the
  wrong trade.
- **Delete `StatusApply` outright.** It is the only implementation of the resist formula
  (`StatusApply.elemental_resist`, `status_apply.gd:274`) and of the ADR 0088 potency reuse,
and those two are what 0086,
  0087 and 0088 decided. It stays as the `combat_engine` stage it is, exercised by its own
  tests; the stage is retired as the *player path*, not deleted. When the spine ships, S12
  is wired from it and this call site is deleted in the same change.

## Consequences

- The player can be burnt, slowed, rooted or braced by their own blow, which is the first
  thing ADR 0086, ADR 0071 and ADR 0075 were built to make possible.
- `combat` gains `status` in `tools/arch/registry.json` and calls `StatusApi` through its
  facade — the one edge `enforce.py:179-186` gates. No `ui/` edge is created here.
- `CombatApi` stays at 7 public methods and `StatusApi` goes to 8, both under
  `MAX_FACADE_PUBLIC_METHODS = 12` (`tools/arch/rules.py:112`).
- **ADR 0087's placement is superseded, not its arithmetic.** Its formula, its substream,
  its `P_MIN_APPLY` floor and its "an avoided blow applies nothing" reasoning all survive
  in `StatusApply` and are now read from the exchange. A future spine re-adopts the stage
  and drops this call site.
- The contract test is the seam, not a population: a landed blow with an open gate is
  reported applied and the actor answers `has_status`; an avoided blow applies nothing and
  consumes no draw from the shared stream.