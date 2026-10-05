# 0141 A burned channel is priced by the recovery elixir

- Status: Accepted
- Date: 2026-10-04
- Amends: ADR 0024 (the `train_channel` clause)

## Context

ADR 0024 gave `train_channel` two jobs: walk a channel a state with the realm's
elixir, and repair a damaged channel. ADR 0031 made `recovery_item` the third
per-realm role and named the burned channel as the thing it repairs. Both shipped,
and both prices landed on the same verb.

`MindTraining.train_channel` consumed `training_item` and then repaired. So the
channel elixir paid for the wound and `recovery_item` was demanded by nothing a
player could reach: `MindTraining.recover` was correct and `recover_next` — the
facade verb added for exactly this wound — was correct, and neither was a route
anyone would take, because the wrong item did the job at a price the player was
already paying. That is why the missing verb went unnoticed: a burned channel WAS
repairable through the facade, just not at the price the seeds author.

The suite agreed with the defect. Every fixture stocked `training_item` before a
repair and asserted only that the channel healed, so the price of a repair was
measured by nothing at all.

## Decision

- **A burn is priced by `recovery_item`. `train_channel` hands an injured channel to
  `recover`** and returns its result. Delegated, not reimplemented: one repair, one
  price, one code path, and a second copy of the consume in `train_channel` is
  exactly how the two prices drifted apart the first time.
- **A healthy channel is still priced by `training_item`.** Two consumables, two
  jobs; neither verb reaches the other's consumable.
- **The price is the same through either route** — `train_channel` or
  `recover_next`. They are one act at one price, not two routes to a discount.
- **A refusal spends nothing**, which `recover`'s all-or-nothing rule already
  guaranteed and the delegation inherits.
- **Every realm authors both roles and the two ids differ.** The difference is now
  asserted alongside ADR 0031's presence check: a realm whose two roles collapsed
  into one id would make the price undistinguishable and the split vacuous.

## Consequences

- `recovery_item` is load-bearing for all 30 realms, which is what ADR 0031 claimed
  and the code did not deliver.
- A deviation costs the elixir the seeds say it costs. The R1-R30 traversal still
  completes, so this is a price change and not a soft-lock.
- Delegating means `train_channel` also calms the sea and lifts clarity to the
  realm floor, because `recover` does both. Neither can lose ground, so pressing
  Train on a burned row undoes the whole deviation for the one authored price.
- **Mind is the only path fixed.** `QiTraining.train_channel` and
  `BodyTraining.strengthen` price an injured channel at their own training
  consumable for the same reason; neither module was in scope here.