# 0152 Awareness is a depleting combat reserve that one sitting of cultivation restores

- Status: Accepted
- Date: 2026-10-04
- Amends: none. Supersedes: none. Neither ADR 0013 nor ADR 0071 is contradicted — see
  "Which reading this adopts, and which it rejects".

## Context

ADR 0013:13 and ADR 0071:35 both describe the `awareness` reserve and read as if they
disagree about it. Measured (BL-0651), **nothing in `res://src` ever wrote it**:

- `MindStats.AWARENESS` (`stats.gd:68`), minted **empty** by
  `MindCultivationApi._ensure_resources` (`api.gd:210`, `_add_pool(..., full = false)`, so
  `current = 0.0` against a `100.0` maximum).
- Read by `MindProvider` (`provider.gd:41`) for `mind_focus_chance` and `mind_avoidance`
  (`provider.gd:61-62`).
- Read by `MindDamage` (`mind_damage.gd:595-602`, via `combat_damage.tres:37`) as
  `awareness_ratio`, spent twice: `coh = 1 - COHERENCE_DAMP * awareness_ratio`
  (`mind_damage.gd:532`) and an `ATTEND` erosion's `awareness_delta` (`mind_damage.gd:585`,
  applied at `effect_apply.gd:182`).

So `awareness_ratio` was a constant `0.0`. `coh` was `1.0` at every build, the shipped
`coherence_damp = 0.5` (`combat_damage.tres:23`) halved nothing, **ADR 0071:20's "1.0 -> 0.5
at full awareness" was unreachable**, and erosion `Kind.ATTEND` drained nothing. A resource
authored, gated, drained and damped by, and never moved.

The fiction is not the defect: `combat_engine` implements ADR 0071 completely, and
`tests/modules/combat_engine/test_mind_damage.gd:426` and `test_effect_apply.gd:303` both
prove the mechanism works when the reserve is funded. Only the funding was missing.

## Which reading this adopts, and which it rejects

**Adopted: one shape, two halves, and the refill was the missing half.** ADR 0013:13 lists
`awareness` as a `ResourcePool` beside `mind_power` and calls it "perceptual acuity"; ADR
0071:35 calls it "the depleting AWARENESS reserve" and names it lever (1) of four. The repo
already ships that exact shape for qi: `QiStats.QI` is minted full
(`qi_cultivation/api.gd:152`), spent per cast (`technique_casting.gd:355`) and restored by
the qi path's own sitting (`qi_cultivation/training.gd:49`). A depleting reserve a period
boundary refills. Neither ADR claims the refill, so **the finding is "the refill is missing",
not "two accepted ADRs conflict"** — and an ADR superseding either one would assert a
conflict that does not exist.

**Rejected: "it is a standing stat, so the depleting half is the stale one."** That reading
is what the code did, not what it says. `MindDamage` spends the reserve as a ratio
(`mind_damage.gd:585`), `EffectApply` writes a negative delta into it
(`effect_apply.gd:182`), and three suites prove both. A standing stat needs no writer on a
pool that something already drains; the half that is missing is the refill, and retiring the
depleting half would delete `COHERENCE_DAMP`, the erosion drain and their passing suites for
no gain.

## Decision

- **`cultivate` restores the reserve, and it is the only writer.** `MindTraining._restore_awareness`
  adds `amount * AWARENESS_RATE * pool.maximum`, with `AWARENESS_RATE = 0.01`, so one facade
  sitting (`CULTIVATE_STEP = 10.0`) restores 10% of the reserve's own maximum and ten sittings
  re-arm a fully drained one. `ResourcePool.change` clamps, so a full reserve keeps the surplus
  — the same contract `sea.fill` already has.
- **A share of the MAXIMUM, never `gain`.** `gain` carries `RealmRate.factor` and the meridian
  flow bonus; scaling a bounded `0..1` ratio by either is a second magnitude curve on a quantity
  ADR 0071 promises only in ratio form (AGENTS.md: a rate must never track a magnitude). The
  maximum stays the flat `100.0` `api.gd:216` authors at pool creation.
- **No new facade verb.** The facade is at its 12-method cap (`rules.MAX_FACADE_PUBLIC_METHODS`)
  and a refill needs no decision from a caller.
- **Cultivation, not `meditate`/`recover`/`strengthen_sea`.** Cultivation is the only candidate
  that is free, repeatable and already mandatory — the mind entry gate demands a filled sea
  (`sea_fill_required`), so this makes the reserve a reward for a sitting the player must make
  anyway. `meditate` is lever (2) and is refused when there is no turbulence to calm
  (`training.gd:164`); `recover` prices a deviation's wounds with `recovery_item`;
  `strengthen_sea` is a one-shot milestone. ADR 0071:35 calls this lever "the cheapest one to
  hold", and none of the three alternatives can re-arm a reserve a clean duel emptied.
- **One writer, asserted.** `test_meditating_re_arms_nothing` pins that lever (1) is not lever
  (2); fusing them would collapse two of the four defensive levers into one verb.

## The ceiling, and what stops the refill

**The ceiling is a flat `100.0` at every realm**, authored once at pool creation
(`api.gd:216`) and never rescaled: `MindTraining.synchronize` sets only `MIND_POWER`'s maximum,
from `MindRealmSeed.sea_capacity` (`training.gd:37`). **What stops the refill is the clamp** —
`ResourcePool.change` does `clampf(current + delta, 0.0, maximum)` (`resource_pool.gd:29`) — and
nothing else. There is therefore no per-realm reserve scale for a rate to scale against, which
is the first reason the rate below is realm-independent.

## Why the rate is realm-INDEPENDENT, and is that right across 29 boundaries

A realm-dependent rate was considered and rejected on the evidence, not on taste:

1. **There is nothing to scale against.** The ceiling is flat at every realm (above), so
   "realm-dependent" can only mean "deep realms refill faster for no authored reason" — a rate
   tracking realm strength with no magnitude behind it, which AGENTS.md forbids outright.
2. **Every alternative available in `training.gd` makes it worse.** Scaling the refill by
   `gain` would multiply it by `RealmRate.factor` at the top of the ladder — under 2x, against
   a drain that is already roughly **four** times slower *there* (erosion carries the factor in
   the numerator and `structural_capacity` grows `100 -> 825` beneath it) — so a full reserve
   becomes a standing discount rather than a budget. The only genuinely realm-fair option is a
   per-realm ceiling in `MindRealmSeed`: a new power-shaped number on another agent's file,
   needing its own ADR.
3. **The realm-dependent asymmetry is ADR 0071's, not the refill's.** `erosion = base *
   coherence / sea.structural_capacity` (`mind_damage.gd:238`), and `structural_capacity`
   climbs `100 -> 825` across the thirty `MindRealmSeed` resources (ADR 0071:29) while
   `mental_attack` grows by the bounded `RealmRate` factor alone (under 2x). So the drain per
   strike **shrinks** with realm, and a flat refill therefore buys proportionally more strikes at
   the top. That is the shipped mind formula's property, it lives in `combat_engine`, and this
   change does not touch it.

**The consequences were measured, not derived** — on the fixture `ActorFactory.build` +
`with_mind_cultivation`, `perception 40.0`, `mental_clarity 30.0`, via `--suite mind_cultivation`
(`Results: 16170 passed, 4 failed (36 suite(s))`). Every figure is read off the actor's own pool
and off the mechanism the composition root bound:

| ladder | `sea_capacity` | ceiling | sittings to full | coh empty | coh full | erosion empty | erosion full | `ATTEND` delta | strikes to spend | coh spent |
|---|---|---|---|---|---|---|---|---|---|---|
| `qi_refining` (idx 0) | 100.0 | 100.0 | **10** | 1.0000 | **0.5000** | 1.2500 | 0.6250 | -0.6250 | **2** | 1.0000 |
| `foundation` (idx 1) | 125.0 | 100.0 | 10 | - | - | - | - | - | 3 | - |
| `spirit_domain` (idx 15) | 475.0 | 100.0 | 10 | - | - | - | - | - | 13 | - |
| `dao_ancestor` (idx 28) | 800.0 | 100.0 | 10 | - | - | - | - | - | 18 | - |
| `primordial_origin` (idx 29) | 825.0 | 100.0 | **10** | 1.0000 | **0.5000** | 0.2691 | 0.1345 | -0.1345 | **18** | 0.9955 |

What that answers, in the order the question was asked:

- **The ceiling is `100.0` at every realm, and what stops the refill is the clamp** —
  `ResourcePool.change` does `clampf(current + delta, 0.0, maximum)` (`resource_pool.gd:29`).
  Nothing else, and nothing rescales it: `synchronize` sets only `MIND_POWER`'s maximum.
- **`coherence` moves, and it reaches the floor.** `1.0000` empty to **`0.5000`** full, at
  `qi_refining` and at `primordial_origin` alike — exactly `1 - coherence_damp` at the shipped
  `0.5`, so ADR 0071:20's "1.0 -> 0.5 at full awareness" is reachable at both ends.
- **Never trivially maxed.** A full reserve takes **2** `ATTEND` strikes to spend at R1 and
  **18** at R30, and coherence climbs back to `1.0000` / `0.9955` once it is gone. It is a
  per-duel budget everywhere, not a standing discount.
- **Never trivially unreachable.** **10 sittings** at every realm — the *same* number at both
  ends of the ladder.
- **So the realm-independent rate is correct across all 29 boundaries.** Ceiling, cost-to-fill
  and the coherence floor are identical at both ends; the only realm-dependent quantity is the
  *drain* (2 vs 18 strikes), and that is ADR 0071's `g /= sea.structural_capacity` term
  (`mind_damage.gd:238`) — `sea_capacity` runs `100 -> 825` while `mental_attack` carries only
  the bounded `RealmRate` factor — so the lever is worth *more* per sitting at the top of the
  ladder, and a realm-scaled refill would only exaggerate that.

One measured detail worth keeping: at `qi_refining` an **unfunded** target takes `erosion
1.2500` from a single strike, which clamps turbulence at `1.0` and collapses the sea. Funded, it
takes `0.6250`. At the bottom of the ladder the reserve is the difference between one exchange
and two — the sharpest statement of what ADR 0071:35's "cheapest lever to hold" now buys.

`test_the_lever_is_live_at_both_ends_of_the_realm_ladder` asserts these as invariants, not as
literals: the ceiling is positive and equal across realms, a full ratio costs more than one
sitting and lands inside the bound, a funded reserve lands exactly on `1 - coherence_damp` and
not on `1.0`, a full reserve takes more than one strike to spend and does spend inside the
bound, coherence climbs back once spent, and **both ends cost the same number of sittings** —
asserted as a difference, so a refill quietly scaled by `RealmRate.factor` fails even though it
would still move the number.

## Consequences

- ADR 0071:20's "1.0 -> 0.5 at full awareness" is reachable, and `coherence_damp` and erosion
  `Kind.ATTEND` are live. Holding the reserve is now a decision a player makes by cultivating
  before a mind duel, and the reserve emptying mid-duel is the observable consequence of an
  `ATTEND` erosion against a mind attacker.
- Observable where the game already reads it: the character sheet lists every pool an actor
  carries as `current/maximum` (`ui/screens/character_screen.gd:101-109`) under the authored
  label "Awareness" (`ui/panels/stat_presenter.gd:149`). `MindCultivationApi.summary()` does not
  publish it, so the mind screen itself does not yet show the reserve — a UI gap for the `ui`
  owner, not a mechanics one, and reaching it needs a facade method the facade has no room for.
- `test_awareness_reserve.gd` proves it through the facade only, on an actor built by
  `ActorFactory.with_mind_cultivation` — the enrolment `app/actor_factory.gd:151` performs in
  production — reading strike numbers from the mechanism the composition root bound.
- `test_mind_stat_reachability.gd`'s awareness case is **inverted, not deleted**. It used to
  pin inertness and its own docblock designated that red as the handoff ("the day a writer
  appears it goes red and someone checks whether ADR 0071's '1.0 -> 0.5 at full awareness' now
  holds"). The answer is yes, so the pin now asserts the reserve moves, that `coherence` is no
  longer pinned at `1.0`, that `coherence_damp` is reachable, and that the erosion follows —
  the same absence-assertion strength aimed at the direction that actually broke.
- **Not fixed here, and not this module's:**
  - `MindCultivationApi.summary()` (`api.gd:120-136`) publishes `mind_power`, `clarity`,
    `purity` and `turbulence` but **not** `awareness`, so the mind screen cannot show the
    reserve a player is being asked to spend. The character sheet can, because it lists every
    pool an actor carries (`ui/screens/character_screen.gd:101-109`). Reaching the mind screen
    needs a facade method and `api.gd` is at its 12-method cap, so this is a facade question
    for the module's owner, not a `ui/` one.
  - `game/data/item_options/master_option_pool.jsonl:98` authors a `restore_awareness`
    consumable option targeting this pool, and `derived/option_pools.json` lists it in four
    pools — but **no authored `.tres` carries it** (`rg -l restore_awareness game/data` returns
    only the two declaration files, zero `.tres`). That is a content gap today. It is also a
    decision this ADR should not make silently: if a generation wave rolls it onto a consumable
    it becomes a **second writer**, and "one writer, one sitting" above stops being true. Either
    retire the option or decide the item is a legitimate parallel source, deliberately.