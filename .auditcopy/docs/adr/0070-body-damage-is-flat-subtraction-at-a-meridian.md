# 0070 Body damage is flat subtraction at a meridian, with necrosis

- Status: Accepted
- Date: 2026-10-02

## Context

One spine, one seam (ADR 0067) and one defensive vocabulary (ADR 0068) carry all three paths. Body owes a shape that is the INVERSE of qi's (ADR 0069): qi always lands something, so body must sometimes refuse a strike outright and sometimes not. `body_cultivation` already owns `actor.meridians` (20 channels, ADR 0017) and an `AcupointSet` (60 points, ADR 0015), and `BodyAdvancement` already puts both halves of a deviation wound on ONE meridian because "the damage has a location".

## Decision

`resolve` returns, for a clean hit:

```
gross        = attacker ATTACK_PHYSICAL
meridian     = resolve_location(...)          # 20 meridians
point        = the acupoint within it
channel      = target.meridians.get_meridian(meridian_id)
resistance   = DEFENSE_PHYSICAL * MERIDIAN_ARMOUR_STEP * channel.state_rank()
             + tissue_defence(meridian_id, target)
penetration  = maxf(gross - resistance, gross * MIN_PENETRATION_RATIO)   # 0.10
mitigated    = penetration * point_multiplier(point) * channel_multiplier(channel)
damage       = mitigated * (1 - DAMAGE_REDUCTION)
```

**Flat subtraction, NOT Keepverse's ratio `off*K/(K+def)`.** Four reasons. (1) A ratio never reaches zero, so it has no vocabulary for "this point is not defended" — and refusing a strike outright is the whole premise. (2) Body's premise is the inverse of qi's: ADR 0004 `NOURISH = 0.75` means qi always does something; body must be allowed a null. (3) Dimensional: under a ratio `defense` is un-authorable — doubling it moves the result by less than doubling, so no designer can read it off the data. (4) A flat number is a literal hit-point value, which is the only form a balance table can be reviewed in.

**Granularity is the MERIDIAN (20), not the 60 acupoints and not the 7 tissues.** `actor.meridians` already exists on every actor for all three paths and already has an injury vocabulary (`MeridianState.injured`, `damage_meridian`, `repair_meridian`); 20 aim buckets is legible at 2D sprite scale in a 2D game; the 60 acupoints are the weak point WITHIN a location (measured `data/body_cultivation/acupoints`: 60 defs over 20 meridians, 3 each for the 14 primary/organ meridians, 2..4 for the 8 extraordinary). Tissues (`skin/muscle/bone/marrow/tendon/organ/blood` + metals) are NOT a third axis — they are a per-meridian WEIGHTING of the defender's existing `bone_density`/`muscle_fiber`/`organ_vitality` across four archetypes (skeletal/muscular/vascular/visceral).

**`MIN_PENETRATION_RATIO` is load-bearing.** Without it, enough defense drives `penetration` to 0, the location multiplier multiplies nothing, and the entire mechanic is deleted by a stat the defender already had.

**One flag, opposite meaning.** `Acupoint.blocked` is a lost investment for the cultivator (`AcupointSet.open_count` drops, `average_quality` ignores it) and simultaneously the BEST aim point for the attacker (`BLOCKED_MULT`) — an inversion no other path has. `MeridianState.injured` halves the channel's aggregate bonus to EVERY path via `get_bonus() = 0.5` AND raises damage taken there. That inversion is the identity of the path.

**Deterministic aim.** `named` (the technique authors `aim_meridian`), `random` (lands on the highest `point_multiplier` — a PURE FUNCTION OF STATE, not an RNG roll, so it is testable and the UI can say "it found the jammed Lung node"), `broad` (an area technique, `effect_radius > 0`, hits every unlocked meridian at `BROAD_MULT`). A blind roll makes the location unreadable and the whole mechanic opaque.

**Wounds and necrosis.** Severity accumulates per meridian: `severity += damage / body_integrity.maximum`. At `WOUND_THRESHOLD 0.05` call the existing `damage_meridian(id)`. At `NECROSIS_THRESHOLD 0.25` floor surviving point quality to `NECROSIS_QUALITY 0.30` and jam one. Decay never crosses necrosis downward. **`0.25` is deliberately ONE failed breakthrough's worth**: `BodyAdvancement._deviate` charges `actor.change_resource(BodyStats.BODY_INTEGRITY, -seed.integrity_maximum * 0.25)` — the identical shape, already shipped, at `advancement.gd:351`. So a good fighter costs a cultivator a realm through the same wound the existing failure path already writes. `Actor.SCHEMA_VERSION` goes **4 -> 5** so wounds persist; that is the cost.

**What body must NOT share with qi.** Not the element table and not the multiplicative elemental shape (ADR 0069). Not `Stat.EVASION` as the outcome roll — evasion removes the location question before it can be asked. Not a `ResourcePool` per location (ADR 0028's one-reservoir rule): `body_integrity` stays the single pool, and wounds are severities on top of it.

## Consequences

- `resolve_location` returns a `(meridian, point)` pair; the aim mode is authored on `TechniqueDef.aim_meridian`, a new additive `@export` — module-owned per ADR 0056, not a `contracts/` change. `contracts/skill_def.gd` is a legacy app-level prototype and stays untouched.
- `MIN_PENETRATION_RATIO`, `MERIDIAN_ARMOUR_STEP`, `BLOCKED_MULT`, `BROAD_MULT`, `WOUND_THRESHOLD`, `NECROSIS_THRESHOLD` and `NECROSIS_QUALITY` live in a `BodyDamageProfile` Resource, never in the mechanism `.gd` (ADR 0067).
- `channel.state_rank()` is `MeridianState.STATE_ORDER` lookup: closed 0, open 1, expanded 2, strengthened 3. A `closed` channel contributes `0` defence and can still be struck, which is the refusal the flat subtraction exists to make expressible.
- `random` aim is asserted state-derived: same actor state resolves the same point with no seeded RNG. A test must prove the same actor twice picks the same point, or the claim is decorative.
- Necrosis is irreversible downward, so a jammed huyệt must be clearable through the existing ADR 0031 recovery item path, not by decay. `BodyRealmSeed.recovery_item` already exists to make that reachable.
- `BODY_INTEGRITY` stays the single pool: `AcupointSet._pool` is one shared `ResourcePool`, and `AcupointDef.base_capacity` is authored but unread precisely so no second reservoir can appear. Severity is a float on the meridian, not a pool.
- The schema bump to 5 is an ADR-level decision per the repo's save rule; v4 saves migrate with zero wound severities and a `mind_attempt` bag that already exists at v4.
- `DAMAGE_REDUCTION` is the one stat body DOES share with qi — both are landed physical/spiritual hits and the spine's S7 runs after `resolve`. Sharing it is not sharing the element table, the multiplicative shape or the location vocabulary.
- Cross-references: ADR 0069's qi always lands something; ADR 0071 refuses health entirely; this one can produce `0.0` and is the only mechanism that does.