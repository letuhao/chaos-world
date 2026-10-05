# 0068 the defensive vocabulary is one omni-only band

- Status: Accepted
- Date: 2026-10-02

## Context

`Stat` already ships the six derived stats this vocabulary needs — `Stat.EVASION` (`minf(0.6, agility * 0.0015)`), `Stat.CRIT_CHANCE` (`minf(0.75, 0.05 + ...)`), `Stat.CRIT_DAMAGE` (`1.5 + comprehension * 0.004`), `Stat.PENETRATION` (`spirit * 0.5`), `Stat.DAMAGE_REDUCTION` (`0.0`) and `Stat.POISE` (`physique * 0.5 + will * 0.5`) — derived in `core/actor_stats.gd`. Everything else in the defensive families is new.

Keepverse carries 72 per-element slots for these families: `CombatDerivedReader` resolves each of them as `omni + element` (`snap.Get(CombatParryRateOmni) + snap.Get(CombatParryRate(e))`), with a roster-generated switch per family, and D14 had to close a real defect where parry/block/reflect were reading the omni half only and the other nine families were not. chaos-world has six wuxing elements and a fully shared spine (ADR 0067), so the same vocabulary would be paid for three times over and tested in a shape nothing else in the repo uses.

## Decision

The vocabulary is `parry.rate/break/strength/shred`, `block.rate/break/strength/shred`, `accuracy`, `penetration`, `absorption`, `amplification`, `reduction`, `reflect.rate/damage` + `reflect.resist.rate/damage`, and the shield's `capacity/toughness/pen/regen`. `penetration`, `reduction` and `absorption` are read-only inputs to the mechanisms; the rest are authored.

**The band roll is ONE `rng` draw.** Cumulative bands, mutually exclusive:

```
miss    = r >= p_hit
parried = !miss && r >= p_hit - p_parry
blocked = !parry && r >= p_hit - p_parry - p_block
```

Parry and block are carved out of the TOP of the would-have-been-a-hit region, so at zero parry and zero block this collapses to exactly `r < p_hit` by arithmetic, with no special case. Band total caps at `AVOIDANCE_BAND_CAP = 0.95`, so every attack always lands `>= 5%` and no stack of defensive stats reaches immunity. Crit is a SECOND draw, on clean hits only: a parried or blocked hit never reaches it.

**Rates are LINEAR-from-zero, not sigmoid**, and that is load-bearing:
`clampf(maxf(0.0, rate - resist) / 1000.0, 0.0, 1.0)`. A sigmoid returns `0.5` at parity, so an actor with ZERO parry stat would parry 50% of the time — a default nobody chose, and an empty band that is not a no-op. Keepverse's `ElementalResolver.RateFromZero` is the same shape for the same reason; a sigmoid IS correct for `accuracy` vs `EVASION`, a contest between two actors who both intend to hit and to dodge, and wrong for a rate that must read zero when unstated.

**Reflection is POST-shield**, so a fully absorbed hit reflects nothing — `Shield.absorb` returns the overflow (ADR 0067 S9) and only that overflow is reflected. The bounce carries no element payload, so it is not re-mitigated and cannot crit, and it terminates on `CHAIN_DEPTH_LIMIT = 6` by being DROPPED, never by clamping to zero. `reflect.share` is bounded below 1.0, so thorns can at most tie against an equal-health attacker and never win a trade outright.

**Omni-only, by decision.** Keepverse's per-element channel family is not ported. The cost of reversing this is one per-element channel family per stat above plus a weighted read at every call site, the way `CombatDerivedReader` does `omni + element`; the three mechanisms already supply variety (ADR 0069/0070/0071), so per-element defensive stats would buy a fourth axis nobody plays against.

**The ADR 0022 trap, stated as a rule.** `Stat.DAMAGE_REDUCTION` is FLAT with baseline `0.0` and is deliberately ABSENT from `RATE_STATS`. For any new rate channel with a `0.0` baseline, a `PERCENT` modifier evaluates to `(0.0 + 0.0) * (1 + p) = 0.0` — a silent no-op that shipped on 44 items. `RATE_STATS` is hand-written over STATIC ids, so a new combat-owned id is invisible to it. **Rule: author `op: FLAT`, `unit: "rate"`, and add a SHAPE TEST.** Do not try to add dynamic ids to `RATE_STATS`; ADR 0022's own cheaper guard is to derive membership from the baselines.

**Tuning constants live in DATA**: `modules/combat/combat_damage.tres` bound to a `CombatTuning` Resource. No numeric balance literal in a mechanism's `.gd`, the same rule `RealmScaling` follows by reading `RealmDef.power` instead of hardcoding 551.0.

## Consequences

- The channel ids above are `StringName`s owned by `modules/combat/`, not `contracts/stat.gd` constants — a module may define its own ids, and adding twenty ids to `Stat` would put combat vocabulary in core.
- `game/tests/modules/combat/` pins four properties: bands are exclusive and partition the draw; an unstatted actor has `p_parry == p_block == 0.0` and parries 0% of the time; a fully shielded hit reflects 0.0; a chain at depth 6 is dropped, not applied.
- Every new rate channel ships a SHAPE TEST asserting a FLAT modifier at a `0.0` baseline is non-zero. Without it the defect class is silent by construction, and `tools data audit` cannot catch it — it validates the flag against a contract that was itself wrong (ADR 0022).
- The band cap and the chip floor are DISTRIBUTIONAL bounds on outcomes, not caps on authored stats, so ADR 0050's ceiling ban holds (ADR 0067).
- Reversing omni-only later is additive but not cheap: it touches every read site and every shape test, and it revives the class of bug where one family of a channel is read per-element and its nine siblings are not (Keepverse D14).