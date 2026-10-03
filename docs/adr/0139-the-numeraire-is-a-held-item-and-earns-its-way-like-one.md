# 0139 The numeraire is a held item and earns its way like one

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0094 (one price), ADR 0027 (save shape), ADR 0025 (realized instances)
- **Supersedes: ADR 0099**, which said a numeraire "is never acquired as an item"
- Resolves: DEF-0189

## Context

ADR 0099 exempted the spirit coin from the acquisition requirement on a stated premise:
*"Nothing ever puts a coin `ItemDef` in an inventory"*, so a numéraire was *"held as an
integer purse"* and must declare no source at all. `tools/data.py` enforced that in two
places — `_audit()` reported any source on a `subcategory = "numeraire"` item as a finding,
and `_unobtainable()` excluded it from the orphan check.

**That premise was false against the tree it shipped into.** Measured, not assumed:

- `economy/api.gd:142` reads the coin with `inventory.count(...)`.
- `market/market_transfer.gd:64` reads it with `payer_inventory.has(...)` and builds **coin
  rows** returned as the `offer` or `want` leg of a trade.
- `market/api.gd:541` and `custody/api.gd:274` pass coin rows straight into
  `EconomyApi.trade`.
- `EconomyExchange` then physically does `from_inventory.remove(...)` and
  `_deliver(to_inventory, row)` on that stack.

So the coin is an ordinary held stackable, and the exemption was not describing a unit of
account — **it was hiding an unreachable item.** `tools data audit` said so itself:
`curr_spirit_coin` is reported as *"obtainable in the content graph but not through any
shipping route."* There is no integer balance anywhere in the repo; `EconomyApi.purge` is a
**derivation** (`inventory.count`), and ADR 0094 explicitly rejects *"a flat numeric
balance"* as realm-blind.

ADR 0099 named its own escape hatch, and it has now fired: *"If the economy later grows held
currency — coins as inventory rather than a balance — this decision is wrong and must be
superseded, because the exemption would then hide a genuinely unreachable item."*

## Decision

**The numéraire is a held item and acquires a real route. The exemption is removed.**

- Both exemptions in `tools/data.py` are gone. A numéraire is now audited exactly like any
  other item: it needs a source, and it is an orphan if nothing can produce it.
- **`sources = ["starter"]`, and the id is in `STARTER_ITEMS`.** `starter` is chosen
  deliberately and not by convenience: it is the only route that both **roots the acquisition
  graph** and is **actually granted at runtime** (`item_workbench_app.gd`'s grant loop).
  `gather` was the obvious candidate and is wrong — `ItemSources.KINDS[gather]` is
  `shipped: false`, so a gather source is graph-rooted but still *runtime*-unreachable, which
  is the worse failure: the audit would go quiet while the item stayed unobtainable.
- `subcategory = "numeraire"` **stays**, and keeps its meaning. It is what tells a designer
  which currency item is the unit of account rather than a tradeable good; it is no longer a
  marker that exempts an item from being obtainable.

## Consequences

- **`data audit` stops reporting the coin as unroutable**, and the "starter delivers nothing"
  warning clears because the route now has an item that declares it. Both were symptoms of
  the same false premise.
- **A player starts with coins**, which is what makes the economy reachable at all: without
  one, every trade in the game refuses `no_settlement` on first run.
- **The marker no longer lies.** A designer who marks an item `numeraire` to dodge the audit
  gets the ordinary "has no acquisition source" finding, exactly as for any other item.
- **`EconomyApi.purse` keeps returning an `int`.** That is unchanged and is not in tension
  with this ADR: a purse is a *derived read* of a held stack, and ADR 0094's rejection is of a
  *stored* balance, not of a convenient accessor.
- **The remaining honest gap** is that `starter` is the only earn route, so coins are
  effectively an infinite faucet at world start. That is a balance question, not a schema
  one, and it is the first thing a designer should tune — the schema now permits a real earn
  route (a domain drop, a boss) without any further change to the audit.
