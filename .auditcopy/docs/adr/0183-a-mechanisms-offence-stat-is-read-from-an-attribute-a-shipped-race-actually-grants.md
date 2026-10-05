# 0183 A mechanism's offence stat is read from an attribute a shipped race actually grants

- Status: Accepted
- Date: 2026-10-04

## Context

Two of the three damage mechanisms proposed nothing on any actor the game can build,
and every suite was green.

`QiDamage` prices its raw term `t_0 = m_0 * ATTACK_SPIRITUAL` (ADR 0069). `ATTACK_SPIRITUAL`
was `spirit * 2.0 + aptitude * 0.5`. Neither `spirit` nor `aptitude` is an attribute every
body is born with: `game/data/races/stoneborn.tres` — a shipped origin, and the FIRST entry
in `CharacterCreationFlow.RACE_BY_ORIGIN` — grants `{physique: 4.0, will: 1.0}` and nothing
else. Its spiritual attack was exactly `0.0`, its raw term `0.0`, and the whole blow
collapsed onto S8's chip floor: `hit · S4 proposed 0.00 · S6 amount 1.00`.

`MindDamage` reads `MENTAL_ATTACK`, which `MindProvider` derives from `perception` and
`mental_clarity` — the mind module's OWN base attributes, declared only in `MindStats`. **No
`RaceDef.base_attributes` in `game/data` names either.** All five races grant core's seven and
nothing else, so `MENTAL_ATTACK` read `(0 + 0) * factor == 0.0` on every actor the game can
build and ADR 0171's erosion was `0.0`.

Both were invisible because every fixture pins its own inputs: the qi fixture sets
`Stat.SPIRIT: 10.0` and the mind fixture sets `PERCEPTION: 20.0` / `MENTAL_CLARITY: 15.0`. A
pinned fixture proves the arithmetic and says nothing about reachability.

Two secondary defects are fixed here because they are what made the measurement impossible:
`game/tools/ui_driver.gd` hard-coded `PathState.BODY` on its drill swing, so `--path qi` and
`--path mind` changed the hero and not the mechanism; and the driver's hero is built with
`Actor.new`, which mounts no `ElementProvider`, so `element_power_<e>` read `0.0`.

## Decision

**An offence stat is read from an attribute a shipped race actually grants. Where none of the
attributes a formula names is allocated, the formula falls back to one that is.**

1. **`ATTACK_SPIRITUAL` gains `will * 0.6`** — `spirit * 2.0 + aptitude * 0.5 + will * 0.6`.
   `will` is not a new constant: core already treats it as a spiritual attribute and
   `DEFENSE_SPIRITUAL` one line below already reads `will * 0.6`, as do `POISE`,
   `STATUS_RESISTANCE` and `BREAKTHROUGH_CHANCE`. The defect was that the offence and defence
   halves of the same contest disagreed about which attributes were spiritual — a body could
   DEFEND against qi without being able to throw it. The coefficient is the defence side's
   own `0.6`, so the pair cannot drift apart again.

2. **`MindProvider` falls back to `Stat.WILL`** for `perception` and `mental_clarity` when
   the actor carries neither. `will` is already the DEFENSIVE term on the line below, so the
   module's two unreachable base attributes resolve to the one attribute every body has.
   An authored `cult_perception` / `cult_mental_clarity` FLAT still applies on top — this is
   the ADR 0022 baseline shape, not a replacement of the authored stat.

3. **A regression suite asserts the CLASS**: for all three mechanisms, the offence stat is
   non-zero on every `RaceCatalog` race walked through `RaceApi.set_race` with no hand-pinned
   attribute, plus an end-to-end case proving a stock `stoneborn`'s qi blow EXCEEDS
   `CombatSpine.chip_floor`. Liveliness, not a pinned literal — a balance edit must not fail
   this suite.

4. **The driver honours `--path`.** Its drill swing takes its path from `--path`, the hero is
   built with that path's attributes, a `fire` affinity and `ElementsApi.attach` are mounted,
   and the drill body is enrolled on the mind path so `MindTraining.synchronize` gives its sea
   a capacity. `--path body` is bit-for-bit unchanged.

## Consequences

- `actor_stats.gd` is realm-scaled, so every actor's qi numbers move by
  `0.6 x will x realm power`. **Every actor with `will == 0` is bit-for-bit unchanged**, which
  is every fixture that pins this stat. Real bodies all grant `will`, so all of them move.
- The qi body/realm balance figures quoted in `combat_boot.gd:91-98` were measured against a
  `spirit`-bearing actor and shift by `0.6 x will`. Re-measure before quoting them.
- `MindProvider`'s own fixtures set `PERCEPTION` and `MENTAL_CLARITY` explicitly and are
  unchanged, which is what keeps this a fallback rather than a rebalance. A mind actor with
  neither authored attribute and `will == 0` still reads `0.0`, which is correct: no body
  grants nothing.
- Nothing was invented to paper over this. Candidate (c), a floor constant on the formula, was
  rejected: a floor makes the arithmetic produce a number nobody allocated, which is the same
  defect wearing a constant. The fallback names the attribute the body actually has.
- **Content, not code:** the races are `game/data`, outside this slice. Giving
  `stoneborn` a `spirit` is the complementary authoring decision and was NOT made here. The
  code fix is the one that is right on its own terms; the race edit is a separate call.
- `MindStats.SEA_CAPACITY` has the same shape — `attach_sea` sizes a sea off a base attribute
  nothing allocates, so a sea is capacity `0.0` until `MindTraining.synchronize` runs. Same
  bug class, one call away, NOT fixed here: it is mind's own denominator and an owner should
  decide whether the path attaches the sea or the sea is authored.