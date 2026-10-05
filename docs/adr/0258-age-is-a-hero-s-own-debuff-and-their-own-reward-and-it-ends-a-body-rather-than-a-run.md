# 0258 Age is a hero's own debuff and their own reward, and it ends a body rather than a run

- Status: Accepted
- Date: 2026-10-05

## Context

`ADR 0169` made a lifespan computable: `core/realm_lifespan_table.gd` +
`realm_lifespan_table.tres` carry authored per-realm-tier multipliers and
`race/provider.gd:44` contributes `RaceStats.LIFESPAN` from them, so the stat has a
real production computation and the lineage screen renders it.

It is inert. Measured on this tree: `age_years`, `elapsed_days`, `born_year` and
`born_on` return **zero hits** across `game/src`; the only `age` is `SocialBond.age`
(a bond-strengthening counter) and `FightLoop`/`BossEncounter.age` (a combat rate
gate), neither of which is an age; and `Actor.to_dict()` serializes no age, so the
number cannot survive a save. A lifespan with nothing to be outlived by is a number
on a screen.

`BL-0892` tracked the decision as UNDEFINED: death-by-age or a soft cap. That is now
decided, and the answer is **both, in that order** — because the programme already has
the machinery that makes "both" coherent rather than a contradiction.

## Decision

### 1. Age is measured in WORLD PERIODS, against `TimeLadder`

There is no new clock and no new constant. `core/time_ladder.gd` is already the one
authority: authored whole-number ratios, one integer division per authored magnitude,
no `Time.get_ticks*`, no frame callback, no `get_tree()` (ADR 0173). `PERIOD_SECONDS` is
the base ratio and `ratio_for(&"year")` converts periods to years by division.

The reader is named, not invented: `app/status_loop.gd` holds
`SECONDS_PER_GESTATION_DAY_TURN` with its conversion documented, because
`FertilityApi.advance` already measures its step in days. Age uses **the same named
conversion against a persistent elapsed-time root**, and never a second frame-delta
constant. A lifespan is an absolute duration and needs an absolute root — ADR 0259.

### 2. Age lives on the BODY, and is carried like other body state

`age_years` is a body fact, not a soul fact: the soul outlives the body, so an age that
lived in `SoulState` would survive a rebirth and make every successive body old. It is
serialized in `Actor.to_dict()` and restored in `Actor.from_dict`, and a reborn body
starts at the authored starting age for its species.

### 3. Age is a PAIR, and the pair is authored — old is weaker AND better

This is the design commitment, and it is the reason age is interesting rather than a
timer. An aged hero suffers and gains, from the same fact:

| Direction | Axis | Why it is not a tax |
|---|---|---|
| **Debuff** | cultivation gain rate falls | the cost of a long life is a slower climb |
| **Debuff** | body recovery and combat refresh slow | the cost of carrying a worn body |
| **Buff** | comprehension / dao-heart floor rises | what a long life bought with its time |
| **Buff** | social standing and recognition accumulate | a known quantity is a social quantity |

**Both halves ship in the same change.** A debuff with no counterpart is a tax on whoever
is unlucky, and AGENTS.md already forbids it: "any new mechanic is a pair, or it is a bug."
The axes are named per AGENTS.md's pair table — a rate that falls has a rate that rises, and
a stat that decays has a stat that accrues.

The crossing point is **authored data, not code**: an age-band table beside the lifespan
table, keyed by NAME (ADR 0050 — never by index, so an inserted band shifts nothing).

### 4. Age does not touch a magnitude

Age scales **rates and shares of what the player holds**, never a realm power table, never
a cultivation rate curve, never a drop tier, never a pool maximum. This is ADR 0129's
forbidden list applied to a new axis, and ADR 0050's category error avoided one layer
down: a realm tier is an ordinal and an age is a duration, so multiplying one by the other
reads one number as two.

### 5. Reaching the lifespan ends the body

`SoulDeath.resolve` gains an age cause beside the existing damage and guardian causes. A
soul that has run out of bodies (`SoulGate.can_rebody`) is the one case where age-death
cannot re-body, and it is reported by name rather than as a silent end.

## Consequences

- `realm_lifespan_table` gains a sibling age-band table, both authored, both keyed by name.
- `status/` gains an age read model, because the age bands ARE statuses and the module
  already owns `StatusDef`/`StatusCatalog` — extending it is the composition move, adding
  a parallel system is not.
- `SoulDeath` gains one cause. It does **not** gain a second end-of-life path.
- `Actor.to_dict()`/`from_dict` serialize an age, which is the first body field to do so.
- A player who reaches the lifespan and has lives left loses the body and keeps the run.
- BL-0892 is answered. BL-0891 is answered by ADR 0259, which this depends on.

## Rejected

- **A soft cap only.** It would make age a difficulty slider and leave death-by-age
  undecided forever; the programme already has a death path, so declining to use it is a
  worse answer than using it.
- **A new clock.** `TimeLadder` exists precisely so this does not happen (ADR 0173).
- **Age in `SoulState`.** A soul that accumulates age across rebirths makes every later body
  older than the last, which is not what "a new vessel" means.
- **Age as a flat multiplier.** A single scalar cannot be the pair AGENTS.md requires, and
  it would be exactly the "reading one number as two" error ADR 0050 names.
