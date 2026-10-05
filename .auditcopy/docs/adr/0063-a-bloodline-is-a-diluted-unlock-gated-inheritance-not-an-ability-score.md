# 0063 A bloodline is a diluted, unlock-gated inheritance, not an ability score

- Status: Accepted
- Date: 2026-10-02
- Depends on: ADR 0062 (a race is a body plan)
- Corrects: an earlier draft of this ADR that used `0.55` retention with a `0.10` additive
  constant and thresholds of 0.55 / 0.70 / 0.85. That draft's arithmetic was wrong: its fixed
  point is `0.10 / (1 - 0.55) = 0.222`, so the named floor of `0.10` never applied, the
  first-generation ceiling was only `0.65`, and **the 0.70 and 0.85 tiers were unreachable by any
  inheritance path** — dead content that no test would have caught. The constants below are
  re-derived from the fixed point outward, and the reachability check is now a required test.

## Context

A race says what an actor *is*. It says nothing about what an actor *inherits*, and inheritance is
where the succubus and birth systems actually pay out: a child is expected to come from their
parents carrying something, and two bloodlines meeting in one body is the most interesting
mechanic the game owns.

The obvious design — an inherited ability score that grows with good parents — fails immediately:

- It is monotonically increasing. The best play is always to breed with the best partner, so it is
  a breeding simulator rather than a lineage system, and it compounds across generations until
  nothing is on the authored scale.
- It has no tension. If power is a number you accumulate, every actor converges upward and there is
  nothing to protect.

What is wanted instead is an **advantage that decays and must be defended**, which is why heritage
is a *concentration* that dilutes with every mixed pairing and whose powers are *gated* by that
concentration rather than scaled by it.

## Decision

- **Bloodline purity is one float per lineage id in [0, 1], stored per actor.** It is the
  concentration of that lineage in the actor's ancestry, not a stat and not a level. It is the only
  inherited quantity that changes what an actor can do.
- **Inheritance blends toward the floor, from the mean of both parents** —
  `child = clamp(mean(parent_a, parent_b) * RETENTION + BLEND_CONSTANT, 0, 1)`. The mean is
  load-bearing: taking the maximum would make every pairing behave identically and collapse the
  whole marriage-and-alliance layer this system exists to support. A low-purity spouse is a real
  cost, which is what makes the choice a decision.
- **The constants are defined by their fixed point, not by the additive term.** The effective floor
  of `x -> x * R + C` is `C / (1 - R)`, so the authored floor is stated first and the constant
  derived. Naming the additive term `BLEND_FLOOR` is what hid the original arithmetic error.
- **Purity gates; it does not scale.** A lineage power is locked until purity reaches its authored
  `awaken_threshold`. Once unlocked it contributes a **`PERCENT` modifier**, not a `FLAT` one.
  Scaling by purity would make the threshold meaningless and hand a deep-realm actor a compounding
  advantage; a `FLAT` value is instead dominated by the stat pool early and is noise by roughly
  realm 12, which kills the system on a 30-realm ladder. A bounded percent is relevant at every
  realm and cannot chain into a multiplier.
- **Purity is monotonically decaying within one actor's life — never raised.** Cultivation may
  raise a *race*-granted stat (ADR 0062), but no gameplay action raises bloodline purity. The only
  way to be born purer is to be born to purer parents. Dilution is an accepted cost, not a bug to
  be patched by a reset. A future restoration event is the sanctioned way to recover purity and is
  deliberately **not** built here.
- **`bloodline` is its own module** with `contracts` + `core` + `race` deps. It is not a dep of
  `clan`'s own state; clan reads purity through the bloodline facade.

## Numbers

Authored from the floor outward. `RETENTION = 0.70`, `FLOOR = 0.15`, so
`BLEND_CONSTANT = FLOOR * (1 - RETENTION) = 0.045`.

Pure-ancestor chain, both parents pure, one lineage:

| Gen | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 10 | ∞ |
|---|---|---|---|---|---|---|---|---|---|
| Purity | 1.000 | 0.745 | 0.567 | 0.442 | 0.354 | 0.293 | 0.250 | 0.174 | 0.150 |

| Tier | Threshold | Survives | Minimum parent purity |
|---|---|---|---|
| founding | 0.72 | 1 generation | 0.964 |
| rare | 0.55 | 2 generations | 0.721 |
| common | 0.42 | 3 generations | 0.536 |

- Every threshold lies strictly inside `(FLOOR, RETENTION + BLEND_CONSTANT] = (0.15, 0.745]`, which
  is the only band where a gate can be neither permanent nor dead.
- Each tier is worth **exactly one additional generation**, which is the property that makes the
  tiers legible as a ladder rather than as three arbitrary numbers.
- A mixed pairing (`1.0` with `0.2` → mean `0.6`) yields `0.465`: a viable carrier below `rare`.
  Breeding out is a real, survivable loss, not a dead end.

## Consequences

- **The reachability table above is a test, not a comment.** `tools test --suite bloodline` must
  assert, for each tier, the generation count at which it is met and the parent purity required.
  This is the check whose absence let the original constants ship dead tiers.
- The advantage is real and bounded: an awakened lineage is a genuine edge at its realm and exactly
  as strong at R5 as at R30, because a percent modifier rides the actor's own growth.
- Selective breeding cannot compound — the fixed point caps every line at `FLOOR`, and retention is
  a constant, not a multiplier on accumulated wealth.
- The birth systems get their payoff: conception resolves a race (ADR 0062) and per-lineage purity
  from the two parents, so a child is a real function of who the parents were.
- `bloodline` publishes a **gate** as well as a value, so later content can ask "is this lineage
  awake?" without reading stats.
- **Known gap, owned elsewhere:** a purity-restoration quest beat is the genre's answer to a
  bloodline going dormant, and nothing here can raise purity. Recorded, not hidden.