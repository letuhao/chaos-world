# 0250 A price that answers to who is buying

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0094 (one price formula), ADR 0100 (a margin lives in the coins),
  ADR 0091 (`regard`/`trust` belong to `social`), ADR 0044 (a refused verb writes nothing)
- Resolves: DEF-0127

## Context

Every price in this program is `unit_price = base_worth x rarity_weight x
RealmRate.factor(realm)`, floored at 1, and it is **the same number for everybody**. ADR
0094 fixed that formula deliberately and it is not the defect here; what is missing is that
the one price never answers to the person standing at the counter.

`social` already owns two axes that describe exactly this — `regard` per institution and a
`trust` axis that gates teaching — and `market/` read neither. A player everybody likes paid
precisely what a player nobody does.

Two boundaries constrain the shape of the answer:

- **`market` may not depend on `social`.** `tools/arch/registry.json` gives `market`
  `["contracts", "core", "economy", "items"]`, so a direct `SocialApi` reference from a
  pricing path is an *undeclared dependency the checker fails on*, not a convenience.
- **The offerer may never receive more value than it gives.** `EconomyExchange` settles on
  `received <= offered`, valued by the same formula on both legs. Anything that moves one
  leg relative to the other is the arbitrage ADR 0094 closed.

## Decision

**One buyer-dependent factor, injected as a `Callable`, clamped, and applied ONCE — to the
coin quantity, at `MarketTransfer.quote`, and nowhere else.**

- **The authority is a seam, not a formula.** `MarketFavour.set_reputation_reader(Callable)`
  takes `Callable(buyer: Actor) -> float`, the `CustodyApi.set_resolver` shape verbatim.
  `EconomyBoot._install_favour` binds `SocialApi.reputation` as a **bare static-function
  reference** — that is already the signature, so there is no adapter and no second copy of
  the axis. `app/` is the only layer allowed to know both modules, which is the same reason
  `_install_standing` exists for the auction bus.
- **ADR 0094's formula is untouched and remains the only price path.** `MarketFavour` prices
  nothing: it turns one injected number into one bounded multiplier. There is no
  `base_price`/`final_price` pair anywhere — the base is `EconomyValuation`'s, the coins are
  `MarketSpread`'s, and the factor sits between them.
- **The clamp is on the OUTPUT: `[FAVOUR_FLOOR 0.85, FAVOUR_CAP 1.25]`, from
  `1 + reputation x FAVOUR_RATE 0.15`.** The rate is safe by construction because
  `reputation` is authored in `[-1, 1]`; the clamp is the half that cannot be argued with,
  because a reader is a `Callable` and a bug, a hostile double, or a future axis authored at
  100 must not be able to reach 10x on one row. The cap is deliberately *tighter* than
  `MarketSpread`'s own 1.5 sell rate: fame is a discount, never a route to beating what the
  shop itself charges a stranger.
- **Never free money: the factor scales COINS, not `unit_price`.** The goods leg keeps
  travelling at `EconomyValuation`'s own number, so `received <= offered` is read in the
  units it was written for and **no leg can invert in either direction**. Scaling the unit
  price would value the goods once in `quote` and again inside the exchange — two prices for
  one good, the ADR 0066 failure this module exists to prevent. The floor stays at 1, so the
  most-regarded buyer still pays one coin rather than being handed goods.
- **The axis that is read is the COUNTER's regard of the buyer, and the DIRECTION is the
  yin-yang counterpart.** The seam takes `Callable(counter: Actor) -> float` and is applied
  to `shop_actor` whether the shop is selling or buying; `shop_is_seller` supplies only the
  **sign**. Passing the *player* when the shop is buying would mean the shop pays out on the
  *player's* reputation — a merchant pays a bigger cut to somebody it dislikes — which no
  merchant would honour and which the reader cannot even reach.
  - **Buying: a liked buyer is charged LESS. Selling: the same buyer is PAID MORE.** A
    well-regarded customer pays under the shelf price to buy and is paid over it to sell;
    a disliked one does exactly the reverse.
  - **The sign is load-bearing, not cosmetic, and a test caught it.** The first draft applied
    one sign to both directions, so a liked buyer paid *more* at the counter **and** was
    paid *more* for the same good — a strict best response with no counter-force, which is
    the defect AGENTS.md's yin-yang rule exists to prevent and which is worse than shipping
    no modifier at all. Two signs of one number is the whole pair; there is no second
    mechanic, no second axis and no second rate.
  - `MarketApi.list` is deliberately **excluded**: a lot freezes `EconomyValuation.price_of`
    once at escrow, and letting a bidder's standing move it would make the frozen reserve
    and the opening bid disagree.
- **The default is exactly neutral.** No reader, a dead reader, a null counter, or an answer
  that is not a finite NUMBER all read `1.0` — byte-identical to today's price. The type gate
  is `TYPE_INT`/`TYPE_FLOAT` rather than a cast, because the reader is a `Callable` and
  `float(null)` is a runtime error rather than a value.

## Consequences

- **New file `game/src/modules/market/market_favour.gd`**; `market_transfer.gd` gains one
  read and one wrapped call; `economy_boot.gd` gains `_install_favour` and a `favour` key in
  the install report. `registry.json` is unchanged: a `Callable` carries the edge, so
  `market` gains no dependency and no facade method — `MarketApi` is already at
  `MAX_FACADE_PUBLIC_METHODS`, so the clamp is published as a `summary()` read key.
- **`MarketApi.summary` gains `favour`**, so a panel and a test read the clamp from one
  place rather than restating three numbers.
- **The aggregated axis is the reader, not the merchant's own bond.** `bond_entry(buyer,
  merchant)["standing"]` is 0 for a stranger, which would make every first trade free;
  `reputation` is a standing across the bonds the buyer already has, so a stranger pays the
  shelf price and someone the world thinks well of is treated better by *every* counter.
- **Rejected:** a direct `SocialApi` reference in `market` (undeclared dependency, and a
  `market`->`social` edge would sit one `clan` away from a cycle); a second price function
  for the "real" price (two formulas is how the programme ended up with two); scaling
  `unit_price` (inverts a leg, and is a second valuation); a rate on the numeraire leg
  (`SETTLEMENT_SHORT` on the legitimate direction, per ADR 0100); honouring the axis in the
  auction (the frozen reserve and the opening bid would disagree); an unbounded or
  uncapped modifier (a 10x reputation is a broken economy); a clamp on the *input* instead of
  the output (`social` already authors a bounded axis, and this file may not enforce it).