# 0124 The derived-stat census is 27, and combat now reads ten of them

- Status: Accepted
- Date: 2026-10-03
- Partly supersedes: ADR 0056 "A technique is a module-owned Resource, and a runtime system
  is a module" — its "Thirteen of the 25 derived combat stats are unread" sentence and the
  count behind it (`docs/adr/0056-a-technique-is-a-module-owned-resource.md`). Everything else
  in ADR 0056 — where a technique lives, ids-not-definitions, the `TechniqueDef` field list —
  is unchanged and stays Accepted.

## Context

ADR 0056 measured a "25 derived combat stats, 13 unread". Both halves of that are now wrong,
and the original number was wrong when written. Re-measured against the tree today:

- **`core/actor_stats.gd:146-172` derives 27 stats, not 25.** The count was already
  corrected once, by DEF-0094, which measured 27 and 15 fully write-only. 27 is right.
- **Ten of the 27 now have a reader that changes a decision.** `combat`'s exchange builds
  `offense`/`guard` bundles (`exchange.gd:118-142`) that `CombatDamage.resolve_hit`
  consumes: `ATTACK_PHYSICAL`, `ATTACK_SPIRITUAL`, `CRIT_CHANCE`, `CRIT_DAMAGE`,
  `PENETRATION`, `DEFENSE_PHYSICAL`, `DEFENSE_SPIRITUAL`, `DAMAGE_REDUCTION`, `EVASION`.
  `INSIGHT_GAIN` is read by both cultivation paths' training, `LOOT_BONUS` by `loot`,
  `COOLDOWN_REDUCTION` by `techniques`.
- **`combat_engine` reads three more in arithmetic**: `Stat.DAMAGE_REDUCTION`
  (`spine.gd:358`, `qi_damage.gd:180`), `Stat.CRIT_CHANCE` (`spine.gd:366`),
  `Stat.EVASION` (`spine.gd:377`).
- **`Stat.PENETRATION` is NOT read in combat.** `qi_damage.gd:373` reads the *combat-owned*
  `CombatStats.PENETRATION` id, a different channel (ADR 0068). Core's penetration is read
  only by `combat`'s share model, which is the shipped encounter — so "dead in combat" is
  now false, but "dead in the spine" is still true.
- **`combat_engine/api.gd:129-136` is a readout, not a consumer.** `summary()` populates a
  Dictionary for a panel. It reaches no arithmetic. Reading it as a reader is the mistake that
  would keep ADR 0056's number alive.
- **`combat` is live and `combat_engine` is not.** `loot_encounter.gd:124` calls
  `CombatApi.exchange`. `CombatEngineApi.resolve_hit` has no production caller (ADR 0123).
  So the ATTACK_*/DEFENSE_* ids have a real arithmetic consumer on the shipped path, and the
  551x realm ladder is now observable in a fight — which is what DEF-0078 asked for.

## Decision

- **27 derived stats; ten have a decision-affecting reader.** Use this count, not 25 and not 13.
  Re-measure before citing either figure again: `actor_stats.gd` is the only source of truth
  and the number has already moved once.
- **A reader is something that changes an outcome.** A value copied into a `summary()`
  dictionary for a panel is a readout. Counting readouts as readers is how a count goes stale
  while the tree looks busy.
- **`combat`'s share model is the shipped consumer of the four `RealmScaling` attack/defense
  feeds**, so DEF-0078's "no reader" premise is answered for the encounter, not for the spine.
- **Prototype retirement was 3 of 4, not 4 of 4.** `contracts/skill_def.gd`,
  `app/skill_system.gd`, `app/input_handler.gd` and `app/consumable_system.gd` are all gone;
  `app/player_adapter.gd` still exists and is legitimate wiring (a single `_physics_process`,
  below the arch check's two-signal floor). ADR 0056's own consequence sentence said deletion
  was a consequence, not a prerequisite — that was correct, and the shortfall is recorded here
  rather than by rewriting it.

## Consequences

- DEF-0094's 15-write-only figure is now 12 of 27; its `next` list of nine unread ids is
  partly consumed. The write-only remainder is MAX_QI, QI_REGEN, ATTACK_SPEED, POISE,
  STATUS_RESISTANCE, CULTIVATION_RATE, QI_ABSORPTION, BREAKTHROUGH_CHANCE, DAO_HEART,
  QI_COST_REDUCTION and the derived capacity pool ids.
- ADR 0056 must not be cited for the "13 of 25" sentence. Its placement decision and
  `TechniqueDef` field list remain current.
- `Stat.PENETRATION` still has no reader in the damage spine. Wiring it is spine work, and
  it is a real open item, not a closed one.
- Nothing here decides which of the two combat models ships. ADR 0123 owns that.
