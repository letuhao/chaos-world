# ADR 0249 — A passive is mastered by WEARING IT, and paying its upkeep is the gate

- Status: Accepted
- Date: 2026-10-06
- Depends on: ADR 0053 (three states), ADR 0054 (passive delivery, suspension), ADR 0055 (bounded ladders), ADR 0056 (facade cap of 12), ADR 0089 (the caller owns the clock), ADR 0160 (a rung scales a passive's stat channel and refuses pool capacity)
- Relates to: DEF-0304, DEF-0151, DEF-0207

## Context

DEF-0304 is VACUOUS-gate shaped. `TechniqueCasting._grant_mastery` is reached only
from `activate`; `activate` refuses a passive with `not_active`; every authored def
is either active or passive. So the eighteen authored passives have no path to rung
1, and `TechniqueReadModel.ladder_view` publishes each of them a five-rung ladder
the player cannot climb. ADR 0160 already made a rung SCALE a passive's stat
channel by `1.15^rung`, so the effect and the bound exist and are proven — only the
input was missing.

Three inputs were on the table. Each was checked against the shipped corpus rather
than against its appeal.

### 1. Re-studying the manual — REJECTED, and the reason is measured

`CodexEntry.raise_to` exists, `TechniqueCodex.learn` already takes
`maxi(existing, rung)`, and `TechniquesApi.learn` is reachable from production:
`ItemUse._apply_learned` → `TechniqueDelivery.study` → `bind_learner` →
`TechniquesApi.learn`, installed at `app/item_workbench_body.gd:588`. The verb is
live and its monotonicity is already tested.

What is not live is its **input**. Every one of the eighteen authored passive
manuals declares exactly ONE route, and
`test_no_two_defs_claim_the_same_manual` pins the manual→technique mapping as
one-to-one. Fifteen of the eighteen name a single `domain:` or `boss:`; three name a
`craft:`, and only those are repeatable by construction. So re-study would close
DEF-0304 for three techniques and leave fifteen at rung 0 — the same shape as
DEF-0203, where a correctly installed seam resolved against a vocabulary with an
intersection of zero and every study was refused while the suite stayed green.

### 2. Paying upkeep — REJECTED as the source, ADOPTED as the gate

`TechniqueUpkeep.settle` already visits every equipped technique per interval, and
`settle_upkeep` already has a live per-frame production caller
(`StatusLoop.tick`, `status_loop.gd:188`, driven from `item_workbench_app.gd:570`).

But upkeep as the *source* reaches almost nothing: `settle` skips a def whose
`upkeep` is empty, and only **three of the eighteen** authored passives declare any
upkeep at all (`dual_qi_body_tempered_frame` 8 stamina, `passive_second_wind` 6,
`passive_vital_organ_cycle` 3). Gating the rung on a bill that fifteen techniques
do not carry would leave fifteen unreachable.

### 3. Equipping and using its stat — REJECTED

It is not an input. A passive's stat is live from the equip; "using" it is
indistinguishable from holding it, so the rule would be unobservable and would
describe the state rather than an act.

## Decision

**A passive deepens while it is EQUIPPED and not SUSPENDED: one rung per settled
upkeep interval. Upkeep is the gate that can WITHHOLD a rung, never the source that
earns it.**

### Why "not suspended" is the whole gate

Suspension (`TechniqueUpkeep._pay` refusing) is the only state in which a passive is
equipped and contributing nothing — ADR 0054's "still equipped, never unequipped".
A technique that owes nothing can never be suspended, so a passive that authors no
upkeep is trivially paid. That is the same answer `TechniqueUpkeep._pay` already
gives it: an empty bill is a bill that is paid.

### The bill is charged BEFORE the rung is granted, and that order is the rule

A rung is earned for an interval that was actually **paid**. So:

- a passive that cannot afford its bill on its very first interval suspends having
  taught nothing — it never contributed, so it must not be paid in mastery for it;
- the interval that stops paying is the **penalty** and teaches nothing;
- the interval that revives a suspended passive pays the bill but earns **no rung**,
  so a technique cannot cash in the gap it was not worn through; it wears its way up
  again from the next interval.

Charging first and granting second is what makes each of those three true. The other
order — grant, then charge — hands rung 1 to a technique that contributed exactly
nothing, which is the one answer this feature must not give.

### What visits which technique

One predicate, `_is_settled`, replaces the bare `def.upkeep.is_empty()` test in
both `settle` and `_shortest_interval`: a def is settled when it **has a bill to
pay or a ladder to climb**. An ACTIVE with no upkeep is skipped exactly as before,
so the active path is bit-for-bit unchanged; a PASSIVE is now visited.

### One rung per period, one step, never two

`settle` moves exactly ONE rung per settled interval, via
`TechniqueScales.rung_for(held + 1, def.mastery_rungs)` — the identical expression
`TechniqueCasting._grant_mastery` uses — and refuses when the ladder has no room.
Monotonicity is not this ADR's claim: `TechniqueCodex.set_rung` refuses a rung that
is not strictly greater, so a lower rung can never replace a higher one, and
`advance` settles at most once per call (`_elapsed -= interval`), so one frame delta
covering ten intervals still grants one rung.

`RUNG_PERIODS` is named and is the balance knob. It is 1: at the shipped 60-second
`upkeep_interval`, rung 4 is four minutes of continuous wear. It counts SETTLED
INTERVALS in a session-scoped ledger rather than being derived from the rung, so
retuning it does not silently re-interpret every existing save; the rung remains the
only persisted fact.

### Time is the caller's, as always

No `_process`, no `Time.get_ticks_*`, no engine node. The period arrives as the
existing `delta` on `settle_upkeep`, which `StatusLoop.tick` already passes. The
rung is a pure function of (settled intervals, authored `mastery_rungs`, stored
rung), so it is testable without a scene tree.

### The ladder now says how it is climbed

`inspect` publishes `mastery_by`. A ladder rendered with no way to climb it is the
player-visible half of DEF-0304, and the constant lives on `TechniqueUpkeep` so the
read model and the settle loop cannot disagree about the verb.

## Consequences

- **The facade stays at 12 and gains nothing.** `settle_upkeep` is the existing
  method with a changed body, reached by an existing production caller. No new
  `_COMPONENT` constant, so `tools arch`'s facade-constant census is unchanged and
  this adds no member with no production caller.
- **One double rebuild per settled period.** `raise_mastery` rebuilds internally
  and `settle_upkeep` rebuilds again for `changed`. Idempotent by construction
  (remove-all-then-re-add, ADR 0054), and once per 60 seconds.
- **`result["technique_suspensions"]` now also carries mastery grants.** The key
  lives in `app/status_loop.gd`, which this ADR's author does not own, so the name
  lags its contents. Every consumer treats the list as "this technique's applied
  state moved", which is what it still means.
- **THE OPEN BALANCE QUESTION, stated rather than hidden.** One rung per minute of
  wear is fast: a player who equips their passives and walks reaches rung 4 in four
  minutes, and a passive out-climbs an active that must be cast. That may be the
  right game — a worn body-tempering frame is meant to be the slow investment —
  but it is a tuning decision, not a correctness one. It is `RUNG_PERIODS`, and
  raising it is a one-constant change that needs no migration.
