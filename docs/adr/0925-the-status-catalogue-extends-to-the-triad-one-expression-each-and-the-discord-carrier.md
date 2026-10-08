# 0925 the status catalogue extends to the triad: one expression each and the discord carrier

- Status: Accepted
- Date: 2026-10-08

## Context

The audit (BL-0927) found the tier-3 triad — void, chaos, time (ADR 0921) — with no
technique carrying it and no authored status: the cycle was authored, its stat families
published, and no attack could express it. The catalogue's contract (ADR 0090/0110/0920)
pinned twenty pair defs plus seven blessings over TEN elements, with a per-element PAIR
rule (two statuses, two mechanics), exactly one blessing each, and `tools
element_coverage` asserting a full ward package per element at 10/10.

## Decision

- **The triad joins the catalogue**: `StatusDef.AUTHORED_ELEMENTS` is the thirteen
  (`TIER_ONE + TIER_TWO + TIER_THREE`), the id set grows 27 → 30, and
  `tools element_coverage` reads the tier-3 list from `ElementStats` and asserts 13/13.
- **ONE expression each.** The pair rule reads as a one-member set for a tier-3 element:
  the cycle IS the design, and a second status per element would be a pair authored to
  satisfy a rule rather than a need. The three effects are the cycle's flavour:
  `void_severance` (a drain: the qi pool + regen), `chaos_discord` (the discord carrier),
  `time_drag` (a slow: the rate + movement). The cooldown axis is deliberately NOT moved
  — it is a zero-baseline rate a status cannot legally modify.
- **`discord` is the eleventh mechanic.** A carrier's payload authors a `table` of status
  ids; the DRAW is the combat engine's (it owns the rng) and the TABLE is the app's:
  `combat_boot.gd::_discord_members` composes each member's request INSIDE the carrier's
  staged request, and `StatusApply.apply` picks one after the carrier lands and runs it
  through the same pipeline. No new module edge, and the validation refuses a carrier
  that names itself, so a draw cannot recurse.
- **The tier-3 package stops at the statuses.** `element_coverage`'s ward, recipe and
  blessing claims stay tiers-1-2 claims; the triad's blessing/ward package is tracked
  (DEF-0380) rather than silently skipped or silently demanded.
- **The carriers ship**: one technique per element (`qi_void_erasure`, `qi_chaos_edict`,
  `qi_time_arrest`; magnitudes 4.2-4.4 at the roster's top, `min_path_realm` 27/28/29),
  delivered by sigils dropped from the deepest wardens (dao_ancestor, dao_fruit,
  primordial_origin). `can_use` already gates them at the Immortal realm.

## Consequences

- A chaos blow inflicts the carrier and ONE drawn member; void and time land their own
  effects. The discord resolves on the COMBAT landing path (the spine's S12 with the
  staged request); a non-combat application of the carrier lands the carrier alone.
- The catalogue's claims stay exact sets: `test_status_catalogue.gd` pins the three new
  ids, the triad's mechanics, and reads the pair rule the way this ADR states it.
- Extending the blessing contract to thirteen is DEF-0380's work, and it needs a
  producer row per element plus the three missing `element_defense_<triad>` pool options
  before the ward claims can tighten.
