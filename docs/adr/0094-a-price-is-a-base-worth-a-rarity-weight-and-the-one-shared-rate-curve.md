# 0094 A price is a base worth, a rarity weight and the one shared rate curve

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0025 (realized options), ADR 0063 (a percent, never a flat), ADR 0066
  (one shared rate), ADR 0068 (a FLAT on a zero baseline is a silent no-op), ADR 0084 (an
  institution grants recognition and access, never power), ADR 0092 (an npc is an actor)
- Resolves: BL-0048, BL-0191, DEF-0208 (the orphaned `trade_value` consumer)

## Context

`OptionTarget.TRADE_VALUE` has existed since ADR 0025 with the comment
`# ItemsApi.trade_value: reagent worth`. **That method has never existed, and no method
may be added: `ItemsApi` is frozen at its twelve public methods.** So the property has
been authored for its whole life with a consumer-shaped name and no consumer, which is
the dead content ADR 0063 shipped as unreachable tiers.

The authored numbers make it worse, and this is the part that has to be measured rather
than assumed. `master_option_pool.jsonl` registers the option as:

```
"op": "FLAT", "unit": "magnitude", "magnitude_policy": "realm_rarity",
"contexts": ["base", "prefix", "postfix"], "categories": ["currency"], "weight": 3.0
```

Two facts follow, and both disqualify `trade_value` as a price:

- **`contexts` includes `base`.** Currency `.tres` files carry `roll_spec = {"count": 4,
  "contexts": ["base"]}`, so `trade_value` is inside the rollable pool for every currency
  item. A realized coin's worth is an `rng` draw. A price that varies per instance cannot
  be a price, and ADR 0094's own no-rng rule is the reason.
- **The authored values are magnitude-window filler, not prices.** `OptionCatalog.
  magnitude_bounds("magnitude", realm, rarity)` is `[1,10] × realm_scale × (1 + r·0.25)`.
  The recurring values in the content — `6`, then the cluster `33.69 / 34.65 / 35.62 /
  36.58 / 37.54` — sit inside that window at common/low-tier and legendary/high-tier
  respectively, because that is what `roll_value` emits. They are generator artifacts.

Meanwhile `ItemDef.value: int = 0` is a **second** price channel. It is authored on roughly
fifty items — scrolls at 10 to 5000, socket reagents, unique items at 26000 — and **read by
no code anywhere in `src/`**, so those numbers are dead content today. They are also an
`int`, which is realm-blind by construction.

## Decision

**A price is one function of a base worth, a rarity weight, and the one shared rate curve.
It is never a roll, a margin, a buyer, or an index.**

```
unit_price(base_worth: float, rarity: StringName, realm: StringName) -> int:
    maxi(1, roundi(base_worth * RARITY_WEIGHT[rarity] * RealmRate.factor(realm)))
```

- **`base_worth` replaces `trade_value` as the authored input, and is fixed-only.** The
  option record stops being rollable; the flag is structural, not a convention.
- **`RARITY_WEIGHT` is four authored constants** — `{common: 1.0, magic: 1.6, rare: 2.6,
  legendary: 4.0}` — over `ItemRarity`'s existing four names. Authored, never derived
  from `item_magnitude_scale.json`: reconciling the item and actor tables is ADR 0050's
  open debt and needs its own ADR.
- **`RealmRate.factor(realm)` is the only realm term, and it is not a new curve.** It is
  `core/realm_rate.gd`, `1.02^ordinal`, under 2x across 30 realms. AGENTS.md already
  budgets it for exactly this use: *"RATE_STEP must stay at or below the smallest
  per-realm step in the authored work budget, or the rate outruns the price and the deep
  realms get cheap."* `realm = &""` resolves to `NEUTRAL`, so the numéraire prices at 1
  with no special case — one formula covers money and goods.
- **Quantity is strictly multiplicative**, applied by the caller. No bulk curve in v1.

**The load-bearing property is that price is realm-invariant in ratio while income is
not.** A R30 buyer pays the same price for a given good as a R1 buyer; a R30 buyer earns
far more. So the economy cannot be beaten by out-scaling the price ladder — deep realms
accumulate a larger pile, not a 551x one. This is ADR 0063's sentence inverted, and it is
why this survives the objection that killed a flat numeric balance.

**Fixing the base worth is also the anti-arbitrage property.** Rarity is part of
`ItemStack.signature_of`, so a rolled instance and its base roll price identically and a
better roll cannot out-price itself. A rollable worth would compound with the item's own
power, which is the inflation the repo already prices in `item_magnitude_scale.json`.

**Money is one authored currency item, and the other 249 are goods.** A numéraire must be
`stackable`, `max_stack 9999`, `roll_spec = {}`, and carry a fixed base worth of 1.0. Every
existing currency def is realm- and rarity-stamped by the generator, so none can be the
unit of account: a numéraire with a realm makes `RealmRate.factor` meaningless for it. The
remaining 249 currency items are priced by **the same function as a sword** — no conversion
table, because a 250-row rate table is a second price formula that can never be kept in
sync (ADR 0066).

**`ItemDef.value` is deleted in the same change.** It is read by nothing, so deleting the
export breaks no code — and leaving it beside the new formula is exactly how this repo got
`trade_value` in the first place: a second number with a price-shaped name, awaiting a
consumer that never arrives. The ~50 authored `value = ...` lines in `game/data/` are
removed with it.

## Consequences

- **`items/api.gd` does not change.** The consumer reads the property the way `LootApi`
  reads `key_reach` — `ItemsApi.inventory(actor)` then `def.property_total(instance,
  OptionTarget.TRADE_VALUE)` — which is why `loot`'s registry entry is the precedent for
  `economy`'s. The stale comment on `option_target.gd:24` names a method that never
  existed; it is corrected to name the real consumer.
- **`no_settlement` is a refusal, so an unpriced thing is not a tradeable thing.** It is a
  gift, and gifts belong to `SocialApi.apply_cause` (ADR 0091's gift-spam guard).
- **The structural guard is a test**, because `tools arch` cannot see a value it does not
  compute: walk realized instances and fail if any *rolled* effect targets the price input.
  That is the ADR 0084 shape.
- **No buyer-dependent price in v1.** A price that varies per *buyer* is a haggling table,
  and the no-rng rule cuts both ways. Reputation-scaled and friendship-scaled pricing are
  the second ADR, because they are the first thing an agent will bolt onto `valuation.gd`.
- **No margin and no index.** A shop buys at the same price it sells, so a market cannot
  become a money printer before a spread exists; spread is the second ADR too.
- **The ~250 authored `trade_value` numbers are wrong as prices and are not rewritten
  here.** A re-value wave regenerates them from one authored ladder; until it lands they
  are floor-set to 1 by `maxi(1, ...)`, which is honest — an unauthored worth reads as
  "cheap", not as a lie.
- **Institutions keep a ledger, never a vault.** `InstitutionClaim.obligation` is the shape
  a yield pays into (BL-0191), and a sect treasury that held items would make two
  authorities for what an institution owns.