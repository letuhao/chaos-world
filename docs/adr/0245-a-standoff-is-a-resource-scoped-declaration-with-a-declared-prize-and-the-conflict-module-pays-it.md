# 0245 A standoff is a resource-scoped declaration with a declared prize, and the conflict module pays it

- Status: Accepted
- Date: 2026-10-05
- Depends on: ADR 0027 (`module_data` is String-keyed and JSON-round-tripped), ADR 0085 (a
  conflict is a declaration of sides and a prize), ADR 0093 (an event contract), ADR 0097
  (`ResourceNodeDef`, `OwnerRef`), ADR 0101 (a world object persists in an injected store),
  BL-0185
- Resolves: DEF-0311

## Context

ADR 0085 built the political layer and left one half of it unbuilt. `NationApi.declare_war` /
`resolve_conflict` speak of a *territory* and two polity ids; `HoldingsApi.apply_prize` speaks
of a *resource node* and an `OwnerRef`, and its own docstring says "Called by the conflict
module, never by the holder". **No conflict module exists.** A player can claim a vein, a rival
can contest it, and `HoldingsState.resolve_contest` is reachable only from `apply_prize` — so an
open standoff in a real save never closes. The program has a war and no treaty.

## Decision

**A standoff over a resource node lives in a NEW resource-scoped `conflict` module, as a
declaration plus a resolution. It is a sibling of `nation`'s war, not an extension of it.**

- **`declare(actor, node_id, sides, prize, quota)` writes the standoff.** It carries the sides
  (a holder `OwnerRef` and a challenger `OwnerRef`), the **declared prize** and a verdict quota.
  A prize outside the closed shape `{prize: ownership|recognition|tribute}` refuses
  `undeclared_prize` **by name** and writes nothing — a resolution may never invent a prize.
- **`resolve(actor, node_id, winner_id)` records a verdict that arrived from OUTSIDE** — a
  `CombatApi.exchange` the caller ran, a tribunal's ruling — and pays the DECLARED prize through
  `HoldingsApi.apply_prize`. This module **owns no `rng`, reads no combat stat, and computes no
  damage** (ADR 0085). Its only arithmetic is `verdicts` and `quota`.
- **The ledger is JSON-safe**: String keys throughout, no `StringName`, `Actor` or `Resource`
  anywhere inside, because `Actor.to_dict` converts only the OUTER `module_data` key
  (ADR 0027). A round trip over the whole ledger is asserted, not assumed.
- **A standoff is a WORLD fact and lives in an injected store**, exactly ADR 0101's ledgers:
  `set_store` takes any object with `read_ledger()` / `write_ledger(ledger)`. Two rivals each
  keeping their own copy is the silent-conquest bug ADR 0101 records — found and fixed twice in
  this program — so a verdict must resolve against a row the other side can see.
- **No claimant means no standoff.** `declare` refuses `no_challenger` on an absent or empty
  challenger: a node nobody contests has no prize to pay, and the refusal is the rule rather
  than a default winner.

**Why a sibling and not an extension of `nation`.** `nation`'s standoffs are keyed by a
**lexicographic pair of polity ids** inside `NationState.standoffs`, and its prize is
`{mode, transfer, standing}` applied to a **territory claim row** by `NationResolve`. A resource
standoff is keyed by a **node id**, its sides are `OwnerRef`s that may be an `actor`, a `clan`,
a `sect` or a `nation`, and its prize is paid by a **different module** (`holdings`). Folding it
into `nation` would buy a `nation -> holdings` edge (ADR 0083's tiers read DOWNWARD as ids, and
`holdings` owns a resource ledger, not a polity one), would put a node id into a ledger whose
three states are defined over nations, and would spend two of `nation`'s remaining facade slots
for a tier it does not govern. The registry already carries `forage -> holdings`;
`conflict -> holdings` is the same shape and no cycle — `conflict` deps are
`["contracts", "core", "holdings"]`, and `holdings` depends on nothing but `contracts`/`core`.

## Consequences

- **`registry.json` gains `conflict: ["contracts", "core", "holdings"]`; `UI_MODULES` does not.**
  No screen reads a standoff yet, and a permission granted ahead of the screen that needs it is
  the ADR 0104 mistake restated.
- **`holdings` gains no public method.** `market`, `holdings` and `custody` sit at the
  twelve-method cap, so the payout is reached through the existing `apply_prize` — which is the
  whole reason this module exists rather than a fourth verb on `holdings`.
- **Refusals are named authored constants**: `undeclared_prize`, `unknown_side`,
  `already_resolved`, `no_challenger`, `no_contest`, `unknown_node`, `quota_unmet`. They are
  announced on a `ConflictEvents` singleton, matching ADR 0093, so a panel renders the rule it
  was given rather than inventing one.
- **The standoff is opened by `HoldingsApi.claim`, not by `declare`.** A claim on held ground
  already writes the `{conflict_id, challenger}` contest row and leaves `holder` byte-identical
  (ADR 0085). `declare` binds the PRIZE and the quota to that row; it does not open a second one.
- **`DEF-0311` is answered for the payout; the other debt it named is not.** It also records
  that `HoldingsApi.accrue` has no production caller outside `ForageApi`'s settle. That is a
  `forage` wiring question and belongs to whoever wires it.
- **Unreachable by design, and recorded rather than half-wired.** Nothing in `app/` calls
  `declare` or `resolve` yet: a verdict source must decide to call them, and that call site is
  where a `CombatApi.exchange` becomes a political fact. ADR 0085's own consequence is that this
  module is fully testable now and wireable later, and the wiring is one call at the place
  combat decides.