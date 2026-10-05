# 0202 cultivate is priced on its overflow, because it is the sole source of the qi it would charge

- Status: Accepted
- Date: 2026-10-05
- Supersedes: ADR 0180 (ruling Q2, `cultivate` stays free — the owner overruled it)
- Amends: ADR 0096 (its fourth-role rejection, narrowed: not a role, a price)
- Relates: ADR 0201 (the item this price spends is the restored dantian catalyst)

## Context

ADR 0180 ruled `cultivate` free on a sound argument and made that argument a guard.
`dantian_fill_required` is `1.0` on all 30 seeds (re-verified: 30 of 30), so the gate
demands a reservoir the only verb that fills one produces, and charging that verb out of
the reservoir cancels the two demands into a deadlock `training.gd:44-48` documents
having already survived once. The owner has overruled the conclusion. The reasoning is
not overruled, so this ruling prices the verb somewhere the deadlock cannot reach.

**The sole-source fact, re-derived rather than assumed.** `QiStats.QI` has exactly one
writer. `breakthrough_transaction.gd:154` sets `pool.current = 0.0` on every ascent, so
each realm starts empty. `Actor._sync_core_resources` sizes `ResourcePool.regen` for
health and stamina only (`actor.gd:153`), and nothing in `game/src` consumes
`pool.regen` at all — the field is written and read by nobody. So a qi-denominated
price is unavailable, not merely unwise, and inventing a regen tick would be a change
to `core` and a second meter for a quantity the seed already meters.

**The dead shapes, checked before choosing.** Bounding `progress` by the qi the
reservoir stored was rejected because every realm demands a full reservoir: a meter
bounded by the room cannot be met while the room is full, so the gate could never be
paid for. Refusing a sitting at a full reservoir was rejected for the same reason, more
bluntly. Charging only the sittings that overflow would leave the meter unreachable
wherever `progress_required` exceeds the reservoir's capacity.

## Decision

**The price is on the OVERFLOW.** `cultivate` reads the room before filling
(`training.gd`), and a sitting whose circulation exceeds it spends one
`dantian_catalyst` (`ADR 0201`) to convert the refused qi into quality past the next
realm's floor. Everything the gate demands stays free and itemless: the reservoir still
fills, quality still climbs to the gate's own floor with an empty inventory, and
`progress` is metered from `gain` either way.

**So a qi-denominated price is refused structurally, not by taste.** Two new findings
read the module's CODE LINES ONLY and fail:

- `qi_cultivate_unpriced` — the verb spends no seed consumable, so the free sitting is
  back. The reverse of ADR 0180's own guard, which is deleted with the ruling.
- `qi_price_self_deadlock` — every verb that RAISES the qi reservoir also LOWERS it, so
  the module has no verb left that only raises it: the charging verb is the sole source
  of the resource it charges. This is the shape ADR 0180 refused, asserted so a future
  agent cannot reach for it unproved. `QiTraining.cultivate` today writes and does not
  drain; `QiBreakthroughTransaction.execute` drains and does not write.

Both take their sources as arguments, so `mutate.py` aims them at a throwaway module
fixture: the price guard follows `cultivate` ONE level into a `_`-prefixed helper it
calls (`_buy_overflow_quality` owns the all-or-nothing rule in one place), and only into
private verbs, so an unrelated public method that happens to spend something cannot
satisfy it.

**The deadlock does not exist, and the proof is a walk.** A fresh actor at R1 whose
inventory never holds a catalyst presses only public actions — cultivate, meditate,
train the gate's channels, recover, breakthrough — through all 30 realms, asserting zero
catalysts in every realm's two ids at every boundary. That is the claim ADR 0096's
objection needed: if a catalyst were a tax, the walk stalls at R1 on an empty inventory.

Rejected: *qi*, the sole-source deadlock above. Rejected: *time* — no qi verb reads a
clock, the three paths' verbs are uniform by design, and a price that must persist
across a save is a second counter for a quantity `progress_required` already meters,
inside the two sessions currently reworking the clock. Rejected: *the `training_item`
elixir*, which every boundary's channel gate already demands, so charging sittings with
it is a tax with extra steps. Rejected: *a new seed role for the sitting* — a fourth
role is the same objection ADR 0096 recorded.

## Consequences

- `game/tests/modules/qi_cultivation/test_qi_ruling_q4_cultivate_is_priced.gd` replaces
  `test_qi_ruling_q2_free_cultivate_is_the_price.gd`, which asserted the reverse and is
  **deleted**: a suite that pins a superseded ruling is a lie with a green tick. Its
  surviving claim — every realm demands `dantian_fill_required == 1.0`, all three
  original roles resolve in content — is kept in the new suite's assertions.
- Two new mutation probes, plus five in ADR 0201, all firing on a synthetic fixture
  (`cultivate mutate`: 27 guards, all red on their own mutation).
- The price is charged on the NORMAL case, not an edge case: `progress_required` runs
  100 → 2900 against a reservoir of 100-1000, so a player who has met the progress
  floor is nearly always overflowing.
- **What does not change:** `cultivate`'s signature, its return, the reservoir's fill,
  quality's free ceiling, `progress_required` as the meter, and all three priced verbs
  that existed before. The change is one read of the room and one optional consume.
- **Facade:** 9 public methods against a cap of 12. The addition is ADR 0201's
  `train_off_gate_channel`; this ruling adds none.