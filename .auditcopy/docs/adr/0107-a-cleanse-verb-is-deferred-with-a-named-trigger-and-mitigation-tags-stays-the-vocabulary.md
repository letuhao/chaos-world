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

**No verb read it.** The only consumer-shaped code was `EnvironmentField`'s lever
resolution, which *chooses* a mitigation at apply time
(`modules/domain/environment_field.gd:387`, `_lever_for`) rather than removing a status
later. `clear_combat_scope` is a scope purge, not a mitigation purge.

So a player could be slowed and had no authored way to answer it. That was the gap, and it
was narrower than "no cleanse verb" — it was specifically that the vocabulary had no verb.

## Decision

**The verb was DEFERRED, with its shape named first so the deferral was not a forgetting.
`mitigation_tags` remains the only purge vocabulary, and nothing introduced a second one.**

- **The shape, named so it could be built without re-deciding:**
  `StatusApi.cleanse(actor, lever: StringName) -> Dictionary` — remove every status whose
  authored `mitigation_tags` contains `lever`, through `StatusRegistry`'s existing erase
  path, releasing its modifiers exactly as `clear_combat_scope` does. One lever in, one
  vocabulary, no percentage and no `id`-in/percentage-out second dialect.
- **The trigger was a CONSUMABLE that answers a mitigation lever.** `StatusDef.LEVERS` is
  `[affinity, gear, technique, pill]` (`status_def.gd:83`). `affinity` is a
  character-creation fact and `gear`/`technique` are passive states — neither removes
  anything on its own, so of the four levers exactly ONE is a removal event: the pill.
  ADR 0075 already named a consumable pill as one of the four levers.
- **It was not built speculatively.** A cleanse with no consumer is the exact defect class
  ADR 0089 recorded five times over (`attach_shield`, `ElementsApi.attach`,
  `tick_statuses`, `path_def`, `PlayerAdapter.attack`) — a public method whose only caller
  is its own test. Spending the 12-method cap's headroom on it early would have bought
  nothing.
- **`clear_combat_scope` is not the cleanse and was not renamed.** ADR 0089's purge is a
  combat-lifecycle fact; a cleanse is a player action against a named lever. Conflating
  them would let a combat exit silently answer a poison pill.

## Amendment 2026-10-04 (BL-0306): the trigger as a CHECKABLE predicate

The original trigger was a phrase — "the first authored CONSUMABLE that answers a
mitigation lever" — which had to be re-derived by hand every time somebody asked "is it
time yet?". DEF-0306 re-measured it rather than assuming, and it had not fired. It was
rewritten as the greppable predicate:

> **The trigger fires when a `.tres` under `game/data/items` carries `subcategory = "pill"`
> AND a non-empty mitigation-lever field** — `mitigation_tags`, `mitigation_levers`,
> `cleanse_lever`, `cleanse_levers`, `removes_statuses` or `payload["lever"]` — whose lever
> id is a member of `StatusDef.LEVERS`. At this commit, 237 pills matched the first
> conjunct and **0** matched the second.

The measurement also killed the tempting shortcut: `venom_purging_pill.tres` and
`venom_antidote_pill.tres` are the closest the corpus comes, and both grant a stat
(`core_qi_regen`, `core_status_resistance`). They are stat draughts named like antidotes,
not a `mitigation_tags` payload — building a cleanse on the strength of their filenames
would be inferring a rule from a noun. The counterplay was authored on the STATUS side and
entirely absent on the CONSUMABLE side: 12 of the 20 shipped statuses publish a `pill`
counterplay that no pill delivered.

## Amendment 2026-10-04 (BL-0306): the trigger FIRED, and the verb shipped

**The trigger FIRED, and the verb shipped. The carrier is a named field, and two pills
name it, not one.**

- **The carrier is a named field, not a key dug out of `fixed_modifiers`.**
  `ItemDef.cleanse_lever` (`modules/items/item_def.gd:39`) is `&""` on every other
  authored item. A fixed-modifier entry is an `{option_id, value}` pair about a STAT, and
  keying a status purge out of it would be inventing a stat option with no magnitude
  window and no roll — the `data audit` magnitude check would rightly reject it. One
  scalar named for what it is, and it defaults inert.
- **The production path is the real item-use path, not a test.**
  `ItemUse._apply_consumed` (`modules/items/item_use.gd:133`) spends it through
  `StatusApi.cleanse`, so pressing Use on the pill reaches the verb. The module says
  WHICH lever; `status` decides what that lever removes. That is the whole of ADR 0086's
  ONE-vocabulary rule, respected from both sides.
- **The refusal vocabulary is reused, not invented.** A pill that removes nothing returns
  the module's existing `REASON_NO_EFFECT` (`no_applicable_effect`) rather than reporting
  `ok` — spending it would decrement the stack and leave the actor identical, which is
  BL-0110's defect one channel over. `cleanse` answers in `status`'s own nouns: `no_actor`
  and `unknown_lever` against the closed `StatusDef.LEVERS` set.
- **The pill is obtainable.** `sources = [craft:cleansing_jade_pill_recipe]` resolves
  through a real recipe (`data/recipes/cleansing_jade_pill_recipe.tres`), so `data audit`'s
  obtainability check stays honest.

**Scope is deliberately NOT filtered.** A pill that answers `pill` removes what the pill
names, including a CULTIVATION-scope status that published `pill` as its counterplay.
Filtering by scope would hand the player a pill that silently does nothing to the blessing
they are looking at — the "read model advertising counterplay the game cannot deliver"
defect ADR 0086's `mitigation_tags` exists to prevent. What the authored tag set says is
what happens, and `cleanse` releases the status's modifiers through the same `_purge` path
`clear_combat_scope` uses, so the debuff stops costing anything.

## Correction 2026-10-04: the census in the amendment above is stale, and the pill is not the first

Two measured facts in the amendment above are wrong against the tree. Neither changes the
decision; both are the kind of number that sends the next agent re-deriving a census.

- **238 pills, 2 of them carry a lever — not 1.** A sweep of `game/data/items` for
  `subcategory = &"pill"` finds 238 pills, and `cleanse_lever` is authored on
  **two**: `consumable/cleansing_jade_pill.tres:16` and `consumable/alchemy_clarity_pill.tres:23`.
  Both are `&"pill"`, and they are the only two items in the whole 7954-item corpus carrying
  the field. The amendment's "238 pills, 1 of them carrying a lever" undercounts by one, so
  the amendment's claim that `cleansing_jade_pill` is "the first authored pill to name a
  lever" is not what the tree shows. `alchemy_clarity_pill.tres` is tracked-modified and is
  the pill DEF-0145 names; whichever landed first, the shipped predicate is **2**.
- **The reachable count is 13 authored statuses, not 12 or 14.** Of the 20 defs in the
  authored catalogue (`res://data/statuses`, which is what
  `StatusCatalog.STATUSES_ROOT` reads — `status_catalog.gd:31`), **12** publish `pill`. A
  13th does, and it is reachable: `src/data/statuses/env_scourge.tres:26` publishes
  `pill` and is a real `StatusDef` read by `EnvironmentField.SCOURGE_DEF_PATH`
  (`environment_field.gd:286`). `ash_furnace.tres:14` also lists `pill`, but that is an
  `EnvironmentZoneDef`, not a status, and is not a fourteenth. So the honest number a pill
  answers today is **13**, and the "fourteen" in `alchemy_clarity_pill.tres:17-20` and in
  DEF-0145 overstates it by one. That count lives in a `.tres` comment, which this wave is
  barred from editing; it is reported here rather than fixed.

Nothing else in the amendment is affected: the verb, the refusal vocabulary, the deliberate
non-filtering by scope, and the test shape all hold as written, and
`tests/modules/status/test_status_cleanse.gd` passes 33/33 against the tree.

## Consequences

- `StatusApi` is 10 public methods, under `MAX_FACADE_PUBLIC_METHODS = 12`
  (`tools/arch/rules.py:112`); `items` gained its declared `status` edge in
  `tools/arch/registry.json`. No facade cap was spent on a verb without a consumer.
- The contract test is a LEVER, not a population (`tests/modules/status/test_status_cleanse.gd`):
  a status tagged `pill` is removed, one tagged only `gear` is not, an unknown lever
  changes nothing and says so, and the authored pill drives the whole thing through
  `ItemUse.apply`. The one content assertion re-checks the trigger predicate itself, so
  renaming the field or emptying it fails the build instead of silently orphaning the verb.
- `venom_purging_pill` and `venom_antidote_pill` remain stat draughts. Their filenames are
  not a promise, and nothing in this change made them one.