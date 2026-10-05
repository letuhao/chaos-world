# 0263 A captive is a claim and a term is a count, neither is ever priced

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0104 (custody is a claim and a term), ADR 0094 (one price formula),
  ADR 0247 (a custody claim is produced by a terminal stage advance), ADR 0139 (the
  numéraire is a held item), ADR 0050 (the 551x realm ladder), ADR 0027 (the ledger is JSON)
- Resolves: DEF-0138, DEF-0146
- Pins: `game/tests/modules/custody/test_custody_captive_is_never_tradeable.gd`,
  `game/tests/modules/custody/test_custody_term_is_never_a_valuation.gd`

## Context

DEF-0138 and DEF-0146 are two decision records written **ahead of the question**, by ADR
0094 and ADR 0104, and both have sat at `status: deferred` with an **empty `next`** — which
is the shape DEF-0163 names: a row that reads as open work with no owner. Neither row asked
for code. Each asked for the moment somebody puts a price on a person to be **refused**.

**What was measured, before anything was written:**

- `game/src/modules/custody/` ships `api.gd`, `custody_state.gd`, `custody_world_ledger.gd`.
  Reading `custody_state.gd` with comments stripped: a claim row is built in
  `normalize` from a **closed literal** — `claim_id, subject_id, subject_kind, holder,
  term_id, periods, opened_period, status`. `settle_term` is `owed - periods` on an int.
  Nothing in the module reaches a price, an item type, or the realm ladder.
- The one valuation call the module is allowed is `EconomyValuation.numeraire_id()` — the
  unit of account. It is read exactly once, and this ADR keeps it that way.
- `custody_state.gd` had, until this pass, **one uncommitted diff**: a formatter reflow of
  `settle_term`'s return literal. An agent had earlier injected a running `worth` onto the
  term; that was reverted before this ADR was written, and `settle_term` is now verified to
  carry nothing but `{ok, reason, settled, periods_left}`.

## Decision

**The two invariants are already true in the shipped code. This ADR records the decision
and the two test files that make it load-bearing, and proves the tests fail when the
invariant is broken.**

### DEF-0138 — a captive is a custody claim, never a tradeable thing

**The authority is the REPRESENTATION, not a check.** `CustodyApi.capture` takes a subject
**DEF id** and an `OwnerRef` holder and writes a ledger row. It never mints an `ItemInstance`,
and that is the whole mechanism: the economy's only door into a price is
`EconomyApi.quote` → `Crafting.resolve(def_id)` → `EconomyValuation.price_of`, so a subject
with **no `ItemDef`** is unreachable by construction rather than by a rule somebody can
delete.

Five doors, each asserted to refuse **by name** — `ok == false` alone passes for a screen
that refuses everything:

1. **Inventory** — a capture mints no `ItemInstance`, no stack, nothing named the subject.
2. **`EconomyValuation`** — `base_worth` reads `fixed_modifiers` against `ItemRarity`, so a
   def-backed captive would reach `RARITY_WEIGHT` and `RealmRate` and become a 551x money
   printer (ADR 0050). It prices at the floor.
3. **`EconomyApi.valuation` / `quote`** — `{}`, and `quote` emits **no priced row at all** so
   a caller cannot read a missing number as zero and settle.
4. **`MarketApi.list` / `drop` / `take`** — the floor refuses and writes nothing.
5. **A shop** — `MarketApi.sell` and `MarketApi.buy` refuse in **both** directions.

Plus the **structural** half, which cannot be defeated by adding a *sixth* door: with
comments stripped, `capture`'s body names none of `Inventory.add`, `add_instance`,
`add_batch`, `ItemInstance`, `ItemDef`, `unit_price`, `RARITY_WEIGHT`, `rarity_weight`, and
neither custody file names `ItemsApi`, `MarketApi`, `Crafting` or `AuctionState`.

**Anti-vacuity is asserted, not assumed.** The fixture subject is `smith_bearcutter`, a
**real authored `NpcDef`** read from `res://data/npc`. An id this build does not ship
resolves to null everywhere, so "it priced at nothing" would prove only that a nonexistent
thing prices at nothing.

### DEF-0146 — a custody term is a period count and a negotiated coin settlement

Three layers, each pinned:

1. **The stored row is exactly `{term_id, periods}`** — no `price`, `worth`, `value`,
   `valuation`, `base_worth`, `unit_price`, `coins`, `coin_value`, `amount`, `rate`,
   `rarity_weight` or `realm_factor`. Asserted on the persisted row, on `capture`'s
   **result**, on `CustodyApi.summary` (what a panel reads), and after a **JSON round trip**
   (ADR 0027) — because a key that appeared only after `normalize` would be a key the
   serializer invented.
2. **A price key is REJECTED, not ignored.** `CustodyState.normalize` rebuilds every row from
   a **closed literal**, so each of the twelve spellings is fed through `put` and asserted
   absent afterwards. Dropping an injected price would be a weaker guarantee than refusing
   it: dropping hides the author, refusing reports them. This is the **attack surface**, not
   a hypothetical — `put` duplicates the caller's dictionary, so any caller handing it a
   hand-built claim would otherwise write arbitrary keys into the world ledger.
3. **Settlement moves COINS, never a balance** (ADR 0139 supersedes ADR 0099). The numéraire
   is a held `curr_spirit_coin` stack, so the proof that money moved is `Inventory.count`
   changing **on both sides** — one side alone cannot prove movement, and this program has
   shipped a settlement that debited the payer and credited nobody. Three amounts (`0, 1, 7`)
   settle for exactly the caller's number, at a realm, with `RealmRate` unreachable from all
   three custody sources.

### The default is the shipped shape

There is nothing to configure and no new seam. **The absence of a price IS the default.**

## Consequences

- **`--suite custody` is 616 passed, 0 failed** and both files are now committed. They were
  written and passing while **uncommitted**, which is the state DEF-0163 is really about: an
  invariant nobody can find is not an invariant.
- **Both files read the SHIPPED SOURCE with comments stripped** rather than only calling
  verbs. `tools arch` reads `res://src` and cannot see what a *script text* says; asserting
  on prose instead would make a boundary check into a typo detector, because both custody
  files name "price" in their doc comments on purpose.
- **Nothing changed in `game/src/modules/custody/`.** That is the finding, not an omission:
  the module was already correct and the gap was that nobody had proved it.
- **Rejected:** a runtime `refuse_to_price(subject_kind)` check in the economy — the absence
  of an `ItemDef` already makes it unreachable, so a check would be a second copy of a fact
  that is structural; a `worth` column on `NpcDef` (the tempting answer DEF-0146 names
  explicitly — it would put a person through `RARITY_WEIGHT` and the realm ladder); a
  captive `ItemDef` plus a price (this is the change that would make both suites RED, and
  the change the ADR forbids); storing the negotiated amount on the claim (a coin count on a
  custody row is a balance, and ADR 0139's numéraire is inventory-held).

## The mutation record

Both suites were mutation-proven on `--suite custody`, baseline
`Results: 616 passed, 0 failed (5 suite(s))`.

| # | Injected | Result |
|---|----------|--------|
| A | `capture` mints an inventory stack for the subject | `Results: 614 passed, 2 failed (5 suite(s))` |
| A | reverted | `Results: 616 passed, 0 failed (5 suite(s))` |
| B | `settle_term` writes a running `worth` onto the term | `Results: 616 passed, 0 failed (5 suite(s))` — **GREEN, and that is the finding** |
| B' | `normalize`'s closed literal carries a `worth` key | `Results: 611 passed, 5 failed (5 suite(s))` |
| B' | reverted | `Results: 616 passed, 0 failed (5 suite(s))` |

**Mutation B stayed green and it is the most useful result here.** Every read path in the
module normalizes: `CustodyApi.state` and `CustodyApi._state` both wrap the answer in
`CustodyState.normalize`, and `CustodyWorldLedger.read_ledger` normalizes on read as well as
on write. So an injected key is dropped **structurally** before any caller sees it — the
suite cannot observe it, and the guarantee is real but enforced by a *second* layer.

The lesson recorded for whoever strengthens this: **the closed literal in `normalize` is
the load-bearing layer, not the arithmetic in `settle_term`.** Mutating B' proves it,
because only B' makes the injected key survive to the reader. A defence-in-depth guarantee
whose *inner* layer is untested is a guarantee with one untested wall in it, not two.

All five mutations were reverted; `git diff` on `game/src/modules/custody/` afterwards is
byte-identical to how this pass found it.