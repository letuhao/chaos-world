# A base attribute is moved by a `base_grant` verb that refuses an unpaid gain and bounds the rate, never the amount

Status: accepted. Supersedes nothing; closes DEF-0321's "a sanctioned verb is owed".

## The finding this closes

- `ItemActivation.BY_CATEGORY` (`game/src/modules/items/item_activation.gd:14`) maps exactly one category to `LEARNED`, and it is `TECHNIQUE`.
- `ItemUse.apply` dispatches `LEARNED` to `_apply_learned`, whose **first line** sends `category == TECHNIQUE` to `_study_technique` (`game/src/modules/items/item_use.gd:212`), which calls an injected `Callable` and writes no stat.
- So the `set_base` loop in `_apply_learned` (`game/src/modules/items/item_use.gd:217`) **cannot run**. Dead code that reads exactly like the missing feature.
- A consumable is no help: `game/src/modules/items/item_use.gd:170` reports a base-attribute consumable's gains in the refusal and returns `REASON_NO_EFFECT` — declared `&"no_applicable_effect"` at `game/src/modules/items/item_use.gd:39` — correctly, under ADR 0001.
- Measured: of every `set_base` call site under `game/src/`, the only **generic** one is that dead branch. The rest belong to a progression system's own rewards.

## Why B (a new module) and not A (revive the branch)

A — giving a non-`TECHNIQUE` category a `LEARNED` activation — was measured, not assumed, and it is worse than "content-visible":

- `OptionCatalog.activations_for` derives an option's allowed activations from its declared `categories` (`game/src/modules/items/option_catalog.gd:118`), and `ItemDef.effects` **drops any fixed modifier whose option fails `allows_activation`** (`game/src/modules/items/item_def.gd:104`). So flipping a category does not add a channel — it **silently strips every option declared on it**. Measured from `game/data/item_options/master_option_pool.jsonl`: flipping `consumable` strips **20** options (nine `restore_*`, ten `element_defense_*`, `extend_lifespan`); flipping `material`/`misc` strips **2** each (`craft_potency`, `craft_yield` — the property channel `Crafting` reads); `key`/`quest`/`currency` strip **1** each (`key_reach`, `quest_potency`, `trade_value` — read by `loot` and `economy`).
- Measured over `game/data/items/`: **8028** authored `.tres` — 3503 consumable, 1781 equipment, 1778 material, 231 misc, 233 quest, 230 key, 221 currency, 51 technique. A flip re-activates all of one class.
- `property` → `learned` also un-refuses the read channel: `spend_gate` refuses `PROPERTY` (`game/src/modules/items/item_use.gd:97`) with `REASON_NO_SPEND_CONSUMER` (`game/src/modules/items/item_use.gd:37`), which is the BL-0110 fix. Losing it means "using" a key destroys it for nothing.
- `game/src/modules/items/` was held by two live sessions at the time of writing.

B costs **zero** new cross-module edges: `base_grant` declares `deps: [contracts, core]`, and `core` is a layer (`game/src/core/actor_stats.gd` already publishes `set_base`), so the facade rule never applies to it.

## The verb

`BaseGrantApi` in `game/src/modules/base_grant/`. `grant` is the only mutator; `preview`, `state` and `summary` are reads. The gate is `BaseGrantRequest`.

**One inequality.** `net = sum(gains) - sum(costs)`:

- `net <= 0` is a **transfer** — legal free, because nobody is stronger afterwards, so there is no advantage to answer.
- `net > 0` is a **purchase** — legal only when a `cost_pool` is named and `cost_amount >= net`.

`costs` cannot launder a gain: `removed` is subtracted first, so `+100 physique / -1 spirit` is `net == 99` and still pays for 99. Paying *less* than `net` is `unpaid`, not a discount — two presses of "+1 for 0.5" are "+2 for 1".

## Bound the OUTPUT, never the INPUT

- **Nothing bounds a base attribute.** It is a magnitude that must climb to 551x, so a ceiling on one is the ADR 0200 defect; and a ceiling on the per-grant *amount* is a ceiling on an input, the same defect in a different hat. The authored amount stays free.
- The only bound is `MAX_GRANTS_PER_SOURCE = 64` presses **per source**, in `BaseGrantLedger`. A rate, not a magnitude: it caps how fast one source injects permanent power into a save, and it cannot die as the ladder grows because it multiplies nothing. It is persisted under `actor.module_data`, because a counter that a reload resets is theatre.
- Rejected: a per-actor total of granted magnitude — the ceiling this verb exists to avoid.

## The rest of the shape

- **Never a magnitude** (ADR 0273): no method takes a realm id; `REQUEST_KEYS` has no realm key. Pinned on source by `test_base_grant.gd`.
- **No clock** (DEF-0111): no `Time.get_ticks*`, no `_process`, no `get_tree()`. Pinned on source.
- **A refusal leaves the actor untouched** structurally: every gate runs to completion before `_apply` is reachable, and a refusal carries no `plan` at all — there is nothing for a caller to apply even if it ignored `ok`.
- **Refuse loudly**: ten closed reasons, and the two that are only diagnosable by id (`unknown_attribute`, `below_floor`) carry the id.
- **`preview` and `grant` cannot disagree**: both are one `BaseGrantRequest.evaluate`.

## A transfer, and its floor

Nothing else in this tree subtracts from a base stat, so this is the half with no precedent and the one most likely to go negative by arithmetic. A `costs` entry is checked against the **post** value — a gain and a cost may name the same attribute and the net is what lands — and `0.0` is reachable (`-4 agility` from `4.0` is granted). Refused below the floor: `below_floor`, naming the attribute.

## Not decided here

- **Wiring `doctrine` → `base_grant`** (the board row that calls it) is a later slice; it needs one registry edge.
- **Reaching the dead branch in `items/`** — its correct fate is deletion, once `game/src/modules/items/` frees. Until then it stays as the trap it is.
