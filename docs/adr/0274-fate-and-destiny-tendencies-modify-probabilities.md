# 0274 Fate and destiny tendencies modify probabilities

- Status: Proposed
- Date: 2026-10-06

## Context

The fate ledger (ADR 0065) ships stat modifiers — `flat_modifiers` and
`percent_modifiers` on `FateDef` — that shift stat magnitudes. What is missing
is the probability-modifier half: fortune/destiny tendencies that shift
probabilities (crit chance, breakthrough chance, loot bonus, etc.), not
magnitudes. BL-0064: "Fortune/destiny tendencies modify probabilities; random
encounters produce opportunities."

A magnitude and a rate are different kinds of number (AGENTS.md). A stat
modifier shifts a magnitude; a probability modifier shifts a rate. The two
must not be conflated: adding a flat `+7` to `attack_physical` and adding
`+0.05` to `crit_chance` are different operations on different kinds of
quantity.

## Decision

`FateDef` and `DestinyDef` each carry a `probability_modifiers` field — a
`Dictionary` mapping a probability/rate stat id to a float shift. These are
authored in `.tres` files, projected onto the actor on earn, and read through
the facade.

**Distinct from stat modifiers.** `flat_modifiers` and `percent_modifiers`
shift magnitudes. `probability_modifiers` shifts rates. A fate may carry both;
they are separate fields because they answer different questions and are
consumed by different systems.

**Derived, never stored.** Probability modifiers are computed on read from the
ledger — the same "derived, never stored" principle `DestinyProjection` uses
for stat modifiers. The facade's `probability_modifier(actor, probability_id)`
sums the shifts from all held fates and destinies. Nothing is written to the
actor's stat stack, so there is no second projection to drift from the ledger.

**Yin-yang.** Every positive probability shift carries a negative counterpart
authored in the same fate or destiny. A fate that grants `+0.05 crit_chance`
also carries `-0.02 breakthrough_chance`. The pair is authored together or
not at all — an unpaired advantage is a defect, not a feature (AGENTS.md).

**Data-driven.** Probability modifiers are authored in `.tres` files, not
hardcoded. The data audit gate validates that targets are rate stats.

## Consequences

- `FateDef` and `DestinyDef` each gain a `probability_modifiers` field and a
  `build_probability_modifiers()` accessor.
- `DestinyApi` gains `probability_modifier(actor, probability_id)` and
  `probability_modifiers(actor)` facade methods.
- Consumers (combat, loot, breakthrough) read probability modifiers through
  the facade when they need them — a pull model, not a push model.
- The earn-only invariant (ADR 0065) is preserved: probability modifiers are
  earned, never chosen, and never removed.
- The random-encounter half of BL-0064 is out of scope for this ADR; it builds
  on the probability-modifier foundation.
