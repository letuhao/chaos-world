# 0125 One tribulation is fought by one wave driver and one survival formula

- Status: Accepted
- Date: 2026-10-03
- Supersedes: ADR 0103 (only its "one roll in core" clause, which is kept and now load-bearing), and corrects its claim that `WAVES_BY_TIER`, `WAVE_TOLL`, `PREPARATION_*` and `fight_wave` "no longer exist anywhere" — they all do, and this ADR is where they live
- Amends: ADR 0061 (fought and paid once), ADR 0041 (decided and durable), ADR 0103 (ascent walked, tribulation fought)

## Context

ADR 0061 described one fight. Four implementations had grown, and they disagreed in
a way a player paid for.

- **The toll was optional.** `Tribulation.fight_wave` charged `WAVE_TOLL`
  (`core/tribulation.gd:51`, charged at `:159`). `TribulationFight.fight_wave` called
  `Breakthrough.advance_tribulation`, which walks the phase machine and charges
  nothing, then rolled and resolved the fight itself. The same fight cost one
  comprehension per wave through a breakthrough action and **zero** through the
  tribulation screen.
- **Two answers to "how often does this actor survive".** `Tribulation.endurance()`
  read `MAX - rating * PER`; `TribulationEndurance.endurance()`
  (`core/tribulation_endurance.gd:41`) read
  `MIN + dao_heart * 0.01 - rating * PER`. Same clamp, different question. For one
  elemental fight at Earth Immortal with a comprehension of 70 the first answered
  **0.1675** and the roll actually used **0.3192**. The first had zero `src/` callers.
- **Two derivations of which realm is owed.** `TribulationFight.target_index` and
  `TribulationEndurance._owed_realm` were the same rule in two homes, so the screen
  could price the odds against one realm while the gate waited on another. The
  module's own file named this a SEAM and owed the fix.

## Decision

- **`Tribulation.fight_wave` is the only wave driver.** `TribulationFight.fight_wave`
  calls it and reports what the record now says; it rolls nothing and resolves
  nothing. `Breakthrough.advance_tribulation` stays with a different job — it walks
  the phase machine *without* fighting, the phase half of ADR 0061's explicit-verdict
  pair — and is documented as not a fight path. Rejected: deleting it, which would
  have rewritten eight test fixtures across three cultivation slices for a verb that
  is not wrong; rejected: charging the toll inside `advance_wave`, which would have
  made walking the phase machine cost dao heart to callers that are not fighting.
- **`TribulationEndurance.endurance` is the only survival formula.**
  `Tribulation.endurance()` is **deleted**, not deprecated. The record keeps
  `MIN_ENDURANCE`, `MAX_ENDURANCE`, `RATING_SPAN` and `ENDURANCE_PER_RATING`: it owns
  the rating, so it owns the range that rating is spent across.
- **`Breakthrough.owed_index` / `owed_realm` are the only owed-realm derivation.**
  Public, in core, because `TribulationEndurance` must price a fight before it begins
  and cannot reach a module. `TribulationFight.target_index`/`target_realm` delegate.
- **Guards, because `tools arch` cannot see any of this:**
  `tests/core/test_tribulation_mechanism.gd` sweeps every `.gd` under `res://src` and
  fails if one outside the two files defining the mechanism names `advance_tribulation`
  or `advance_wave`; it also fails if `Tribulation` declares `endurance` again or the
  module re-derives the owed realm. `tests/core/test_tribulation_unified.gd` walks
  24 seeds and asserts both routes end decided the same way with the same dao heart.

## Consequences

- A fight costs the same and pays the same however it is started. Losing the screen
  route's free waves is a real balance change: the tribulation screen is now a second
  way to walk the same fight, not a cheaper one.
- **Stays deleted:** `Tribulation.endurance`, `TribulationEndurance.PREPARATION_SPAN`,
  `TribulationEndurance.RATING_SPAN` (dead aliases), `TribulationEndurance._owed_realm`,
  and the module's own roll and resolve. `TribulationCondition` and
  `TRIBULATION_REALM_THRESHOLD` stay deleted (ADR 0061).
- `resolve_tribulation` and `advance_tribulation` remain for a caller that already
  knows the outcome; production decides by roll through the record.
- ADR 0103's obligation — "`TribulationFight.endurance` and `_verdict` … the deletion
  is owed" — is discharged.