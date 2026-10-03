# 0100 A margin lives in the coins, and a shop is an actor

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0094 (one price, no margin), ADR 0092 (an npc is an actor), ADR 0044 (a
  refused verb writes nothing), BL-0048, BL-0049
- Supersedes: the "never a margin" clause of ADR 0094, **only**. "Never a roll" and "never a
  buyer" are kept unchanged.

## Context

ADR 0094 deliberately shipped a price with no spread and deferred the margin to a second
ADR (DEF-0126). It also deferred buyer-dependent pricing (DEF-0127). This is that second
ADR, and it exists because two measured facts block the obvious design.

**The obvious design cannot work.** A market's natural implementation is to scale the
numéraire leg by a rate — the shop buys at 0.5× and sells at 1.5×. But `EconomyExchange`'s
settlement rule is `received <= offered`: an offerer may never end up richer. When the
*player* sells, the numéraire is the `want` leg and therefore the `received` side, so any
per-leg rate above 1 trips `SETTLEMENT_SHORT` on the legitimate direction. The rule that
closed the arbitrage hole in ADR 0094 also blocks a naive margin.

The alternative — adding a direction-aware parameter to `exchange` — is the "and" rule: one
function with two behaviours, which is the ADR 0066 failure mode in a new place, and it
re-opens exactly the comparison whose reversal shipped an arbitrage.

**A shop is not a ledger.** `EconomyExchange.exchange(from, to, …)` takes two Actors and
nothing else. A stock ledger keyed by shop id forces one of three failures: a second
transfer implementation, a throwaway `Actor` minted per call, or a shop that "owns" items
outside the items module — which `institution_claim.gd:119` explicitly refuses (*"a treasury
in this shape is a ledger of obligations, never a pile of items — the items module stays the
only item authority"*).

## Decision

**The margin is a number of COINS, and a shop is an Actor holding real items.**

```
const BUY_RATE  := 0.5   # a shop pays this fraction of the one price
const SELL_RATE := 1.5   # a shop charges this multiple
```

Both directions then pass the **unmodified** `received <= offered` guard, because the
comparison runs on the GOODS at base price and only the coin *quantity* carries the margin:

| direction | offered | received | passes |
|---|---|---|---|
| shop sells (goods for coins) | `good × SELL_RATE` | `good` | `good ≤ good × 1.5` ✔ |
| player sells (goods for coins) | `good` | `good × BUY_RATE` | `good × 0.5 ≤ good` ✔ |

**Zero lines change in `economy_exchange.gd`.** That is the whole reason this wins.

- **A shop is an `Actor` carrying an `Inventory`,** because a merchant is a role tag
  (ADR 0092: a role is a `StringName` on `Actor.tags`, never a class). `bound_to`,
  `has_rolled_worth`, capacity and `_deliver`'s merge-on-signature all come free, and the
  items module stays the only item authority.
- **Self-arbitrage is structurally impossible, in four independent ways.** `SAME_ACTOR`
  already refuses seating the shop on both sides; the commit loop conserves coin count
  because nothing mints the numéraire; a round-trip profit requires `BUY_RATE > SELL_RATE`,
  which is a **constant invariant a test asserts** (the ADR 0084 shape — `tools arch` cannot
  compute a value it does not compute); and selling back to the same shop costs the player
  `SELL_RATE − BUY_RATE`.
- **The spread is published** in `valuation()` and `summary()["spread"]`, so a panel and a
  test read the invariant from one place rather than restating it.
- **No per-shop margin.** That is a second place to look up a number. A traveling merchant
  differentiates by **stock and `location_id`**, never by a different formula.

**Reactivity is expressed through stock and refusal, not a price index.** A region where
the good is absent refuses `NOT_CARRIED`; a region that does not buy refuses by authored
`buys: false`. That yields regional trade, black markets and traveling merchants with **zero
new floats**. A real index *is* a multiplier on `unit_price`, which contradicts ADR 0094's
"never an index", so it is its own ADR and must name the ledger holding it, its only
writer, a bounded clamped authored percent (ADR 0063/0068), and a test that it cannot go
negative or unbounded.

## Consequences

- **`market` is its own module.** `EconomyApi` publishes 8 public methods against a cap of
  12, so 4 remain; a shop facade plus an auction facade does not fit. New module,
  `"market": {"deps": ["contracts", "core", "items", "economy"]}`, with `UI_MODULES`
  permission granted **in the same change** — `domain/api.gd`'s header records the
  precedent, and a registered-but-absent module is only a warning.
- **ADR 0094's "never a margin" clause is superseded by this one.** Its "never a roll" and
  "never a buyer" clauses stand, and this ADR says so explicitly rather than leaving two
  ADRs to be read as agreeing.
- **Buyer-dependent pricing stays deferred** (DEF-0127). A per-buyer multiplier is a
  haggling table, and the no-rng rule cuts both ways.
- **A shop's stock is player-contact only in v1.** Off-stage stock persists as
  `Actor.to_dict()` keyed by shop id, capped — refuse, never trim, the `NpcState.ensure_entry`
  shape. A world-simulated merchant is DEF-0119's persistence question, not this ADR's.
- **The margin is one global authored pair.** A per-`ShopDef` multiplier needs its own
  rounding rule and a second lookup, so it is rejected until a design shows a shop that
  cannot be differentiated by stock.
- **An auction rides the same exchange** with a frozen realized-instance price, so escrow
  cannot launder a better roll into an older price — the exact hole ADR 0094 closed for base
  worth. That is the auction's own ADR, recorded as work rather than decided here.