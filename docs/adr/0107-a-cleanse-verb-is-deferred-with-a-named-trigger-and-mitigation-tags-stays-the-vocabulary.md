# 0107 A cleanse verb is deferred with a named trigger, and mitigation_tags stays the vocabulary

- Status: Proposed
- Date: 2026-10-03
- Extends: ADR 0086 (the ONE purge vocabulary), read against ADR 0075 and ADR 0090

## Context

ADR 0086 made `mitigation_tags` "REQUIRED and non-empty … It is the ONE purge vocabulary,
read by the combat layer, environment and consumables alike", and ADR 0090 and ADR 0075
both enforce it as an authoring error (`modules/status/status_def.gd:228`,
`modules/domain/domain_map_contract.gd:167`). The vocabulary is authored, validated and
audited.

**No verb reads it.** The only consumer-shaped code today is `EnvironmentField`'s lever
resolution, which *chooses* a mitigation at apply time
(`modules/domain/environment_field.gd:387`, `_lever_for`, called at `:272`) rather than
removing a status later. `StatusApi` exposes 7 public methods (`status_ids`, `definition`, `has_status`,
`apply`, `tick_statuses`, `clear_combat_scope`, `summary`) and none of them purges by tag.
`clear_combat_scope` is a scope purge, not a mitigation purge.

So a player can be slowed and has no authored way to answer it. That is the gap, and it is
narrower than "no cleanse verb" — it is specifically that the vocabulary has no verb.

## Decision

**A cleanse verb is DEFERRED, with its shape named now so the deferral is not a
forgetting. `mitigation_tags` remains the only purge vocabulary, and nothing in this
change introduces a second one.**

- **The shape, named so it can be built without re-deciding:**
  `StatusApi.cleanse(actor, lever: StringName) -> Dictionary` — remove every status whose
  authored `mitigation_tags` contains `lever`, through `StatusRegistry`'s existing erase
  path, releasing its modifiers exactly as `clear_combat_scope` does
  (`modules/status/api.gd:146`). One lever in, one vocabulary, no percentage and no
  `id`-in/percentage-out second dialect. A `levers: Array[StringName]` parameter is the
  only growth it gets.
- **The trigger to build it is named: the first authored CONSUMABLE that answers a
  mitigation lever.** `StatusDef.LEVERS` is `[affinity, gear, technique, pill]`
  (`status_def.gd:83`). `affinity` is a character-creation fact and `gear`/`technique` are
  passive states — neither removes anything on its own, so of the four levers exactly ONE
  is a removal event, and it is the pill. `items/consumable` is the module that owns
  `ItemUse`, and ADR 0075 already named a consumable pill as one of the four levers. When
  a pill `.tres` exists whose payload names a lever, the verb is built in the same change
  and `items` gains `status` in `registry.json`.
- **It is not built speculatively now.** A cleanse with no consumer is the exact defect
  class ADR 0089 recorded five times over (`attach_shield`, `ElementsApi.attach`,
  `tick_statuses`, `path_def`, `PlayerAdapter.attack`) — a public method whose only caller
  is its own test. Spending the 12-method cap's remaining headroom on it now buys nothing
  and would make `StatusApi` 8 methods with 7 of them reachable.
- **What ships instead is the authored guarantee, unchanged.** Every one of the ten `.tres`
  must keep naming a non-affinity-only lever set or the audit rejects it
  (`status_def.gd:236-241`), so counterplay is declared from day one even though the verb
  that spends it is deferred. That is a deliberate ordering: the content states the answer
  exists; the code that delivers it arrives with the first item that is one.
- **`clear_combat_scope` is not the cleanse and is not renamed.** ADR 0089's purge is a
  combat-lifecycle fact; a cleanse is a player action against a named lever. Two verbs, two
  meanings — and conflating them would let a combat exit silently answer a poison pill.

## Consequences

- The 428 status assertions and the ten authored defs stand unchanged; this ADR adds no
  production code and removes none.
- `StatusApi` stays at 7 public methods, five headroom under
  `MAX_FACADE_PUBLIC_METHODS = 12` (`tools/arch/rules.py:112`), and the eighth is reserved
  for the cleanse's named trigger rather than spent on an unused verb.
- `no ui/` file reads `mitigation_tags` today, and none may until the verb exists —
  `status` is not in `rules.UI_MODULES` until ADR 0106 adds it, and a screen rendering an
  unactionable tag would be a promise the module does not keep.
- The cost of the deferral is admitted and small: a player who is slowed has no in-fight
  answer this build. That is a content gap for one combat screen, not a broken contract,
  and the trigger above is the whole of it.
- The contract test when it lands is a lever, not a population: a status tagged `pill` is
  removed by `cleanse(actor, &"pill")`, one tagged only `gear` is not, and a cleanse that
  names an unknown lever changes nothing and says so.