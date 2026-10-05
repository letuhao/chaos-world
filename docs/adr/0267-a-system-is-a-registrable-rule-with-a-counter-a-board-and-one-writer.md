# 0267 A System is a registrable rule with a counter, a board and one writer

- Status: Proposed
- Date: 2026-10-05

## Context

A `doctrine` (道統) is a transmitted body of rules a practitioner opts into on a
destiny path and then farms: a counter, tiers derived from it, a currency, rows to
spend that currency on, and possibly new stats and new resource pools.

Two properties are new here, and both constrain the SHAPE rather than the behaviour.

- **It is EXTRADIEGETIC** — the player's own transmitted rules, not a fact about the
  world, which is why its counter may run far past the world's thirty realms. That is
  the licence to be unbounded and the reason nothing in the realm machinery may be
  reused, or extended.
- **It is registrable, not authored in place.** A System arrives from a module, a
  template or a mod, so its implementation comes from outside this repo's review and
  an override that is forgotten is the normal case.

Three failure shapes were available, and all three are shapes rather than bugs. A
`Dictionary` of callables has no name, so `AGENTS.md`'s rule that every
implementation of a `contracts/` interface passes the same contract tests has nothing
to point at (`BeatSink` argues this for the beat seam). A read that mutates makes a
board unrenderable — it moved under the reader — and a price untrustworthy, because
asking what it costs would cost it. A payload carrying a `Resource`, an actor or a
`Callable` is a second vocabulary reaching `ui/` through a side door, and these
payloads are what a module writes through `Actor.set_module_data`, so it is a
save-schema bug no gate can see.

## Decision

`game/src/contracts/doctrine_rule.gd` declares `DoctrineRule`, a `RefCounted` in the
leaf layer. Twelve methods, in three groups.

1. **Identity: `system_id`, `display_name`, `data_key`.** `data_key` is derived from
   the id (`"doctrine/<id>"`) so there is one spelling of the save key in the repo,
   and it is **empty for an unnamed System**: every unnamed System would otherwise
   share one dictionary, and two Systems writing the same one is a save that restores
   one System's board into another's.
2. **Pure reads: `resource_ids`, `progress`, `tier_for`, `boards`, `price`.** `price`
   is its own method rather than a field on a row because `owned` and `affordable`
   come from the actor's ledger and balance, so a caller cannot derive them from
   `boards`. `tier_for` is DERIVED from `progress` and from nothing else.
3. **`redeem` is the only mutator; `earn` proposes.** An earn is event-driven and two
   Systems may answer the same occurrence, so the arbitration belongs to the caller
   owning the event — ADR 0067's proposal, ADR 0114's `resolve`. A spend is one
   press, one row, one self-contained transaction, so it needs no arbiter. Writes go
   through the actor's **existing** universal verbs and nowhere else: the grant is
   `Actor.add_status`, the ledger is `Actor.set_module_data`. No new grant path, no
   stat composer, no save key of its own.
4. **Every return is primitives-only, and the required keys are declared constants** —
   `ROW_KEYS`, `PRICE_KEYS`, `REDEEM_KEYS`, `EARN_KEYS`, `PROGRESS_KEYS`, `TIER_KEYS`
   — because `DamageProposal.is_primitive_effect` argues that a shape nobody can ask
   about is a shape nobody checks. `is_primitive_payload` is the same rule as a
   question: this contract constructs nothing, so unlike `DamageProposal` it cannot
   refuse at construction and must publish the predicate. `missing_keys` makes the
   declared lists enforceable rather than decorative.
5. **A named class, not a `Dictionary` of callables**, for the reason in Context.
6. **Every default is a no-op that fails SAFE** — empty id, empty `data_key`, empty
   board, zero counter, `tier_for` reporting tier 0 **of 0** so every gated row stays
   locked, `earn` claiming nothing so no balance rises, `price`/`redeem` declining. A
   System that forgets an override renders a board it cannot pay for: inert, and
   visibly so. A default that returned an affordable price would be a stub that lies.
7. **`{}` is not a refusal.** `price`/`redeem` answer `{}` for a row that does not
   exist and `{"ok": false, "reason": R}` for one that is refused — ADR 0083's three
   states. There is deliberately no reason string for a missing row, because nothing
   refused; giving it one is how a panel draws a refusal on a row that was never
   there. `REASONS` is the closed set, and extending it is an ADR.
8. **The actor arrives as `Variant`.** `contracts/` is a leaf (`LAYER_DEPS` declares
   `contracts: {contracts}`), so naming `Actor` is a violation the gate reports.
   `StatProvider.contribute(context: StatContext)` shows the contrast: a contract MAY
   type a parameter whose type lives in `contracts/`. The loose signature is the rule,
   not a looser style, and the docblock says so before the next agent "fixes" it.

## Consequences

- **A doctrine cannot become a magnitude table, by shape.** No method takes a realm id
  and none returns a multiplier; there is nowhere in this contract to put one. The
  contract test additionally refuses any declared key whose name is magnitude-shaped,
  with a negative control so the sweep is a check and not a tautology. A System that
  needs a magnitude is a new power-shaped number and needs its own ADR — ADR 0001
  already makes `core/realm_power_table.tres` the only one.
- **The yin-yang pairing is checkable.** `resource_ids` is the earn side and `boards`
  the sink side, so a declared currency with no row spending it is an accumulating
  debt a test detects. The suite asserts it, again with the negative control.
- **Open gap, deliberately not papered over:** there is still **no validation list for
  resource ids anywhere in the repo**, so a pool id the game does not know is a silent
  `0.0`. The honest place to close it is the declaration seam that owns the
  vocabulary; `UNDECLARED_POOL` catches only a System spending a pool it did not itself
  declare.
- **Contract tests are not optional here.** `AGENTS.md` requires them for a new
  `contracts/` interface, and this one would otherwise be testable but unproven: the
  suite carries a hand-written implementation and holds every payload it returns
  against the same checks the defaults get.
- Left to the module slices, not decided here: opt-in on a destiny path, the authored
  content family, the registry, and how a counter is persisted beyond the key this
  contract derives.
