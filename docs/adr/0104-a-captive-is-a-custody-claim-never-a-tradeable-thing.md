# 0104 A captive is a custody claim, never a tradeable thing

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0002 (inject the constructor), ADR 0027 (JSON-safe `module_data`), ADR
  0044 (a refused verb writes nothing), ADR 0094 (an unpriced thing is not a tradeable
  thing), ADR 0101 (a world object persists in a store), BL-0191
- Resolves: DEF-0138

## Context

The brief asks that anything be tradeable, "including captured actors, captured mobs, not
only items". ADR 0094 already **refuses** that by construction: a captive is an `Actor`, an
`Actor` has no `ItemDef`, so `base_worth` is 0 and `EconomyExchange._plan` hits
`NO_SETTLEMENT` and writes nothing. That is a correct refusal, but a refusal is not a
feature, so this ADR decides what a captive actually is.

Three measured constraints shaped the answer:

- **A captive must never carry an `ItemDef`.** Doing so would put a person through
  `RARITY_WEIGHT` — which is keyed on `ItemRarity`'s four names — and through
  `RealmRate.factor`. Since the actor ladder spans 551x (ADR 0050), a stats-derived custody
  price would make a R30 captive worth hundreds of a R1 one, turning custody into a
  realm-scaling money printer and smuggling combat's magnitude table into the economy.
- **A captive is not an `InstitutionClaim`.** That type is a membership's `position` plus
  `standing` plus dues. A captive is not a member and holds no office; putting a term into a
  sect's `obligation` would make a sect hold a person through a shape designed for dues, and
  a `settle()` against a claim the sect never owed would be indistinguishable from a real
  dues payment.
- **An institution cannot own a claim today**, because `SectState` lives in the *player's*
  `module_data`. That is DEF-0119, and ADR 0101 already answered it for holdings and market:
  a world fact lives in an injected store.

## Decision

**A captive is a custody CLAIM on a subject id, held by an `OwnerRef`, carrying a term
ledger. It is never an `ItemInstance`, never an `Actor`, and never a price.**

```
{ "claim_id": "custody_guard_captain#3",   # stable across saves
  "subject_id": "guard_captain",           # an NpcDef id — NEVER an Actor
  "subject_kind": "npc",
  "holder": {"kind": "sect", "id": "iron_vow"},   # OwnerRef.to_dict()
  "term_id": "custody",                    # an authored term, never an amount
  "periods": 4,                            # periods still owed
  "opened_period": 12,                     # a caller-supplied count; no tick (DEF-0111)
  "status": "held" }                       # held | released
```

- **The subject is a DEF ID, never an `Actor`.** A live actor is minted on demand through
  the same injected-`Callable` seam `NpcApi.set_minter` already uses, so `custody` has no
  `npc` dependency and **`NpcPresence` is never touched** — presence is the npc module's read
  model, and custody is a ledger row it may consult. Storing an `Actor` would also mean
  storing a live stat-provider graph, which is not JSON-safe until it is a payload.
- **Custody persists in an injected store**, exactly as `holdings` and `market` (ADR 0101).
  `attach` still mirrors onto the actor for a single-player save; the mirror is documented as
  wrong the moment a second holder exists.
- **The term is a COUNT of periods, never a money amount**, which is
  `InstitutionClaim.obligation`'s discipline (ids and counts, so retuning a rate never
  rewrites a save) without reusing the type.
- **A holder may be an `actor`, a `clan`, a `sect` or a `nation`**, resolved through an
  injected `Callable` and the closed `OwnerRef.KINDS` — so `custody` has **zero** edges to any
  institution module and cannot build the code-only cycle `tools arch` cannot see.

**`holder == subject` is refused at capture.** An actor holding a claim on themself is a
record with no exit: transfer refuses self-transfer, release refuses a non-holder, and the
claim is permanent. A game rule, not validation.

**There is no escape verb, and that is the point.** Release is a *holder* verb. An escape
resolved here would be a stat check invented in the custody module — a second authority on
combat, and an rng-shaped outcome ADR 0077 refuses. If a captive escapes, **combat decides
it** and the caller then calls `release` afterwards.

**The coin leg runs FIRST, and the claim moves only after it succeeds.** `transfer` prices the
coins the caller agreed and runs `EconomyApi.trade`; only on `ok` does it write the new holder.
`EconomyExchange` plans against `Inventory.snapshot()` of both sides before its first
mutation, so a refused coin leg has written nothing and the custody state has not been
touched at all. The reverse order would be exactly the "granted but never written" failure
ADR 0101 records for holdings, and is unrecoverable without a rollback path.

**The price is a negotiated coin settlement the caller supplies, and the module computes no
price at all.** It reads `EconomyValuation` only for `numeraire_id()` — the unit of account,
not a valuation of the person. A transfer amount of zero is legitimate and skips the exchange
entirely, because a hand-off with no coin leg must not be forced to invent one.

## Consequences

- **`custody` is a new module with deps `["contracts", "core", "economy"]`** — no `items` (no
  `Inventory` is touched; the coin leg goes through `EconomyApi`), and no `npc`, `clan`,
  `sect` or `nation`. `UI_MODULES` gets `"custody": []`.
- **`Actor.to_dict` now carries `statuses`.** It did not, so an actor restored from a payload
  came back with depleted pools and full health — a save that lies, and the exact failure a
  captive-as-payload would inherit. `StatusEffect` gained `to_dict`/`from_dict` with enums as
  ints and a coerced read-back, and statuses restore **last**, after every pool they could
  modify, through `StatusRegistry.apply` so the merge rule still decides what survives. A
  save written before this key loads with no statuses, which is the day-one compatibility
  case.
- **A custody record has NO `description`, no `flavor`, and no `display_name`.** The subject's
  name is authored on its def and read through the catalog; prose in a save schema is how
  prose becomes what gets read. Vocabulary is exactly: `holder`, `claim`, `term`, `periods`,
  `transferred`, `released`.
- **A refused verb writes nothing anywhere**, including no coin movement: the coin leg
  precedes the claim write, so there is no state in which coins moved and custody did not.
- **Self-transfer is refused** for the same reason `SAME_ACTOR` is refused in the exchange:
  a same-party sale at an agreed price is a money printer.
- **Out of scope, named honestly:** capture *conditions* (the caller decides and calls
  `capture`; no combat check, no roll, no rng), the subject's own payload (that is `npc`'s
  job), a market for claims (that would make `market` depend on `custody`), escape, expiry,
  and a persistent world store (ADR 0101's own recorded debt, which custody inherits and does
  not pay).
- **The second ADR is the price decision**: *a custody term is a period count and a
  negotiated coin settlement, never a valuation.* It is written before the fact because the
  moment someone asks "what is a captured boss worth", the tempting answer is to add
  `RARITY_WEIGHT` to a person.