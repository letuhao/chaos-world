# 0097 A resource node is an authored holding with one typed owner ref

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0083 (three tiers, one vocabulary), ADR 0084 (recognition and access,
  never power), ADR 0085 (a claim never moves ground), ADR 0094 (one price formula),
  BL-0182/BL-0183/BL-0184/BL-0185 (territory is authored, claim, yield, contested)
- Resolves: BL-0183, BL-0185, DEF-0119 (no world tick)

## Context

The economy needs something to trade that is not sitting in an inventory. A mine, a farm,
a hunting ground or a spirit vein has to be **ownable and seizable** by an actor, a clan, a
sect or a nation, which makes it the reason a conflict exists (BL-0185) and therefore the
reason a story moves.

Two constraints make the obvious design wrong:

- **The four owner kinds are in four modules that do not contain each other.** `clan`
  depends on `bloodline` and `race`; `sect` depends on `clan`; `nation` depends on `sect`
  and `clan`. A holder check that calls into all three creates a code-only cycle, and
  `tools/arch`'s bare-reference detector **excludes `modules/*`** — so that cycle would be
  invisible to the gate. ADR 0085 already hit this and recorded the workaround: reach a
  sibling only through a `preload` of its facade.
- **A world object has nowhere durable to live.** `LootState` is `actor.module_data` and
  dies with the actor. `DomainApi` persists a whole map under `actor.module_data
  ["domain_run"]` and **erases it on leave**, keeping only `discovered` — the repo has
  already refused world-object persistence and substituted a player-scoped one. There is
  no file-backed world store; `ItemStateStore` is items-only.

## Decision

**A resource node is authored data plus one typed owner ref. A holder is resolved through an
injected `Callable`, never through a module edge.**

- **`ResourceNodeDef` is a new authored `Resource`**, placed into a `RoomDef.fixtures` entry
  as `{"kind": "resource", "node_id": "..."}`. **Placement only.** The fixture carries no
  state because `DomainGenerator._copy_def` deep-copies fixtures per map realization, so a
  fixture has no stable per-instance identity — state filed there would fork itself every
  time a domain was generated.
- **State lives in the holding module's ledger, keyed by `node_id`**:
  `{"owner": OwnerRef, "condition": int, "resting": int}`. `node_id` is the stable identity,
  which is what lets a node outlive the actor harvesting it.
- **Unowned is `"vacant": true`, not `{}` and not zero.** ADR 0083's three-state vocabulary
  is load-bearing: the node exists, its value is absent. `{}` means `node_id` is not a node.
- **`OwnerRef` is one value type in `contracts/`** with a closed `KINDS` of `actor`, `clan`,
  `sect`, `nation`, and `to_dict()` with **String keys throughout**. It is a value, not a
  `Resource`, and not an interface with four implementations: four subclasses of an 8-line
  value object would have to live in the three institution modules, turning every read into
  a facade call inside a summary loop and producing exactly the cycle the gate cannot see.
- **Resolution is an injected `Callable`** answering `{"ok": true}` or `{"ok": false,
  "reason": "unknown_sect"}` — the `NpcApi.set_minter` / `DomainSpawner.set_minter` seam,
  verbatim. **Zero module edges, zero preloads, zero cycles.** `set_resolver` on the
  facade is the one wiring point, and `app/` installs it.
- **`OwnerRef.normalize` refuses closed on an unknown `kind`** and names itself
  (`unknown_owner_kind`). A loud string beats an invisible cycle; `tools data audit`
  cross-references every authored ref.

**A node pays a ledger line, never items.** `accrue(owner, node_id, periods)` writes
`line[node_id] += yield_per_period * periods` — ids and counts, which is
`InstitutionClaim.obligation`'s exact shape. BL-0191 forbids a treasury of items, and
`institution_claim.gd:119` says so in a comment: *"a treasury in this shape is a ledger of
obligations, never a pile of items — the items module stays the only item authority."*
`periods <= 0` refuses `no_periods` and writes nothing; there is no tick (DEF-0111), so the
caller owns time.

**Realm enters as a gate, never as a multiplier on yield.** Scaling yield by realm power
would be a second magnitude ladder — ADR 0050's most expensive open debt, 551x of ore. A
R30 actor cannot harvest a R2 node, and pays the realm seed's own `work_required` for a R30
one, so a fixed authored yield per period stays meaningful at both ends. The moment a yield
becomes a price, ADR 0094's curve is where it belongs — not here.

**Four verbs, and only conflict resolution moves a holder.** `claim` on unheld ground writes
the holder and charges `claim_cost`; on held ground it writes one challenger row and opens
exactly one standoff with `holder` **byte-identical before and after** (ADR 0085's
invariant — this is what separates a claim from a conquest). `release` is always allowed
and always costs. `seize` declares the standoff and never flips a holder. `apply_prize` is
called *by the conflict module* paying a declared prize, so one module owns how a conflict
ends. Seizure pays `ownership`, `recognition` (a standing delta) or `tribute` (the loser
owes the line for N periods) — and **never power**, per ADR 0084.

## Consequences

- **There is no precedent for persisting a world object, and saying so is the honest
  outcome.** The first slice persists under `actor.module_data["holdings_state"]` and
  records the gap, exactly as ADR 0083 disclosed its own. Seizure cannot be durable until
  a world-scoped store exists; that is the next ADR, and it generalises DEF-0119 from a
  polity ledger to any world-scoped ledger.
- **A node is placed by a room, so harvesting is a domain concern and ownership is not.**
  The domain hands over a `node_id`; the holding module never names a room, a map or a
  coordinate. This is ADR 0045's split kept intact — a location is a place, a territory is a
  claim over places.
- **The no-power refusal is pinned structurally**, the ADR 0084 shape: `tools arch` cannot
  see a method that does not exist, so the test reads the facade's published method list and
  fails if `grant_stat`, `set_base`, `add_base`, `power_up`, `buff` or `apply_modifier`
  appears on it.
- **A second income scale needs its own ADR.** Yield is fixed per node and realm-blind by
  construction; if a design wants yield that grows with the holder's realm, that is
  ADR 0050's reconciliation and cannot be smuggled in here.
- **Out of scope for this slice:** conflict resolution itself (it hands off, BL-0185),
  markets and prices (ADR 0094 owns them), depletion of held ground, and any tick. A
  `tribute` prize accrues to the loser's ledger line even though the loser no longer holds
  the node — the debt follows the obligation, not the holder.