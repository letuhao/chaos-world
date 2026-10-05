# 0102 An auction lot escrows a realized instance, and a bidder's ceiling is their purse

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0093 (publish an event contract, never name a subscriber), ADR 0094 (one
  price), ADR 0100 (a margin lives in the coins), ADR 0085 (verdicts arrive from outside),
  ADR 0024, BL-0049
- Resolves: DEF-0136, DEF-0137

## Context

BL-0049 asks for an auction with NPC bidders: *"NPC bidders with wealth/personality; rare
items attract powerful cultivators; consequences emerge."* Three of those four words are
constraints rather than features, and each has already bitten once in this repo.

**A listing cannot be a `def_id`.** `Inventory._roll_instance` calls `rng.randomize()`, and
`EconomyExchange._plan` prices off `inventory.sample(def_id)` — which is the FIRST matching
stack, not the one you listed. So a `def_id`-only listing lets a player list a common roll,
substitute a legendary one before settlement, and pay the frozen low price. ADR 0094 closed
exactly this for base worth ("rarity is part of `ItemStack.signature_of`"); a listing that
freezes a price while delivering a *different* instance reopens it.

**A personality cannot be an `rng` draw.** ADR 0094 forbids a random number in a price, and
the same reasoning applies to a bid: a bid that varies run to run is not a bid, it is a slot
machine, and it makes an auction untestable without a seeded generator the test cannot
legitimately produce.

**"Rare items attract powerful cultivators" cannot be emergent.** It has to be *arithmetic*,
or it needs a simulation loop nobody has written, and DEF-0111 says there is no clock to run
one on.

## Decision

**A lot escrows the realized instance at list time. A bidder's ceiling is their purse times an
authored appetite. Nothing in an auction is random.**

- **A lot holds the realized `ItemInstance` payload** — `instance_id`, `rolled`, `rarity`,
  `realm`, and the `ItemStack.signature_of` string — and **escrows by removal from the
  seller's inventory at `list` time.** A save between listing and settlement therefore
  restores the exact roll. The price is computed once, by `EconomyValuation.price_of`, and
  frozen; it is the reserve, the opening and the bid step's base.
- **The escrow consequence is accepted, not worked around.** With the lot in no inventory,
  `EconomyExchange` cannot move it. **The primitive is extended, not forked:** a row may carry
  `"instance"`, honoured only when `inventory.find_instance(instance_id)` returns that exact
  object, else `not_carried`. Same plan-then-commit, one atomicity implementation, one price
  path. The rejected alternative — keep the lot in the seller's inventory and address it by
  `instance_id` — depends on `Inventory._instances` staying append-only so `sample()` keeps
  resolving to the same object, a private-array invariant in another module that `tools arch`
  cannot see and a save round-trip could reorder.
- **A bidder's ceiling is `purse × appetite_percent / 100`.** `EconomyApi.purse` already
  answers wealth, because the numéraire prices at exactly 1 — 200 coins *is* a price of 200
  through the one formula. `appetite` is an **authored percent keyed by a tag** on
  `Actor.tags` (ADR 0074: a tag read by content), so this needs `core` only: no `npc`
  dependency, no `sect` dependency, and **no rng**. Same purse, same tag, same lot ⇒ the same
  number, forever, which is what makes an auction replayable in a test.
- **"Rare items attract powerful cultivators" falls out of arithmetic.** A legendary lot's
  price is 4× a common one through `RARITY_WEIGHT`, so its opening bid is 4×, so only a deep
  purse clears it — and deep purses are deep-realm income. BL-0049's headline needs no
  simulation and no second formula.
- **The bid step is the lot's own price times an authored percent**, never a constant: a
  constant would let a 1-coin consumable take a 50-coin step. A bid must *strictly* exceed
  the high, so **ties are structurally impossible** and there is no tie-break rule and no
  seeded generator to break one.
- **Settlement is injected by a caller that owns time.** `summary()` reports which lots are
  due; the caller loops and calls `settle(seller, lot_id, winner, periods)`. `settle` walks
  the bids in descending order and the first bidder whose purse *still* covers their own bid
  wins — it re-reads that actor's purse, so a caller cannot hand-pick a winner.
- **A defaulting winner falls to the second-highest bidder at their own bid**, and to
  `unsold` if there is none. **The seller is never charged the shortfall**: they did nothing,
  and charging them turns the reserve into an author's liability.
- **No standing delta, anywhere.** `standing` is institutional recognition owned by `sect`
  (ADR 0083/0084); writing it here is a second writer and buys an `economy → sect` edge. The
  module emits `won_auction` / `outbid_in_auction` / `defaulted_on_a_bid` and `app/` wires
  them to `SocialApi.apply_cause` — ADR 0093's shape, which keeps the deps at three.

## Consequences

- **The structural pin is a test, not a comment.** `tools arch` cannot see a formula that is
  not there, so a test walks the auction files and fails if they name `base_worth`,
  `rarity_weight`, `RARITY_WEIGHT` or `RealmRate` at all. They may call only
  `EconomyValuation.price_of` and `numeraire_price`. That is how "one price path" becomes a
  property rather than an intention.
- **Escrow is a refusal with teeth.** A seller cannot withdraw a lot that has a bid
  (`lot_has_bids`): withdrawing after a bid confiscates a promise every bidder priced money
  against. Settle, or default. The refusal writes nothing.
- **An unpriced good cannot be listed** (`lot_unpriced`). A good with no base worth has no
  first price, and an auction is not where a designer invents one — ADR 0094's `maxi(1, …)`
  floor makes it *cheap*, not *listable*.
- **There is no world-simulated auction house.** Bids come from whoever the caller resolves,
  so a market that runs itself is blocked on DEF-0119's persistence root exactly as ADR 0101
  records for holdings.
- **The events are unwired until `app/` installs the causes**, which makes them dead content
  for one change. That is accepted deliberately: an unwired event is visible in `summary()`,
  whereas an unwired *effect* is invisible.