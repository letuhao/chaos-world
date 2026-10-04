# 0159 An arrival is spent by the death that earns it, and the ledger is the only receipt

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0130 (a soul re-embodies into an arrival it earned), ADR 0065 (fate is
  earned, never chosen and never removed), ADR 0127 (the soul outlives its actor)
- Clarifies: ADR 0130's "first authored origin the ledger does not already hold"

## Context

An audit reported the rebirth ladder dead-ending at the second arrival: `ledger.origins`
receiving only ONE entry, so `SoulGate.next_arrival` returned the same arrival forever and the
authored third arrival `the_ledger_knows_your_name` was dead content. It proposed the cause
be `CharacterCreationFlow.build_forced` minting without granting an origin destiny.

**Measured, that cause is wrong and the behaviour is not reproducible.** `build_forced`
correctly writes NO destiny (ADR 0065: an arrival is a consequence, not a competing claim, so
it must not enter the `origin` exclusivity group), and the ladder is advanced by
`SoulState.incarnate`, which appends to `origins` — a code path it never touches. A
`MUTATION-B1` probe gated on that append reproduced the audited symptom exactly (third death
repeating the second, third arrival unreachable) and every pre-existing soul case still passed
**48/48 green**. So the invariant was untested, not broken; the fix is to pin it, not to
re-architect the gate.

## Decision

**An arrival is SPENT, and the death that earns it is the only thing that spends it. This is a
clarification of ADR 0130, not an amendment: ADR 0130 already says the gate answers "the first
authored origin the ledger does not already hold", and an entry in `origins` IS the proof that
an arrival was lived through.** No arrival is ever chosen, offered, or named by a caller.

- **`origins` is a receipt, not a counter.** It records arrivals LIVED THROUGH, so the gate
  derives "spent" from the ledger and holds no state of its own. The two numbers stay separate:
  `incarnation` counts bodies, `origins` counts arrivals.
- **Each death consumes exactly one.** `reincarnate` is once per body, so one body costs one
  arrival whatever a caller does afterwards.
- **A guardian death consumes none.** It costs the item and does not advance the incarnation,
  so it must not shorten the ladder — asserted, because a guardian that ate an arrival would
  silently discard authored content.
- **Exhaustion is named.** `no_lives` and `no_arrival` are distinct refusals and never stand in
  for each other.

## Consequences

- **`the_ledger_knows_your_name` is reachable, and the ladder is fully walkable.** The authored
  ladder is three long against `SoulState.DEFAULT_LIVES` of three, so every arrival is earned
  by a real run and the last life buys the last arrival.
- **The whole-ladder invariant is now tested, and the guard is proven to fire.** A green guard
  is not a tested guard (INC-0016), so the pre-existing case that read `out["arrival"]` — the
  value the same call had just written — was strengthened to re-ask the gate afterwards, and
  `test_soul_arrival_ladder` asserts the whole ladder plus the real `SoulDeath` play path
  through `build_forced`. Both go RED under the audited mutation; the old case did not.
- **`the_walker_back_through_ash` is both the first authored arrival and the initial body, and
  they are deliberately the same id.** The ledger is empty at incarnation 0, so a soul that has
  never died is still owed the first arrival. That overlap is left alone rather than "fixed": it
  is the one id that is both a first-life origin and a return, and collapsing them would make
  a returning soul arrive somewhere the player has never been.