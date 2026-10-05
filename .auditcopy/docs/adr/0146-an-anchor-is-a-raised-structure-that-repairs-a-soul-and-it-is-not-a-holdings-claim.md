# 0146 An anchor is a raised structure that repairs a soul, and it is not a holdings claim

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0101 (a world object persists in an injected store), ADR 0127 (the soul
  outlives its actor), ADR 0130 (a soul re-embodies and the world never rewinds), DEF-0184 (no
  repair anchor), DEF-0185 (no building feature existed)
- Resolves: DEF-0184, DEF-0185

## Context

The rebirth program asked for the soul feature to "wire with the existing building feature".
Measured, there was no building feature: a search of `game/src` for
building/construction/shelter/homestead/dwelling/housing/estate returned zero gameplay hits,
`holdings` is a **claim over a node that already existed** with no build verb and no cost to
construct, and BL-0058's homestead was still `todo` with none of its six capabilities in any
form.

A damaged soul also had nowhere to be repaired. ADR 0127 shipped damage and reincarnation
deliberately without a repair verb, because the only building-adjacent module was at its
twelve-method facade cap and could not grow one.

## Decision

**An anchor is a structure the player RAISES, and it lives in its own module. `holdings` is
untouched.**

- **A new `anchor` module owns it.** `holdings` is at `MAX_FACADE_PUBLIC_METHODS` and has no
  construction verb at all, so an anchor could not be a thirteenth verb there. It is also a
  different shape: holdings is tenure over ground that already existed, an anchor is something
  built with a cost. Folding it in would have put two shapes in one module — the and-rule
  failure ADR 0066 names.
- **The ledger lives in an injected store, for ADR 0101's reason.** A raised anchor stands in a
  place and outlives the body that raised it, so a per-actor copy would let a rival read it as
  absent and raise their own on the same ground. That is the exact conquest ADR 0085 forbids,
  and it is silent — every single-actor test passes.
- **Repair is owned by `anchor`, never by `soul`.** `soul` owns the integrity number and must
  not know where it came from; if it did, repair would become a second writer of integrity and
  the soul ledger would stop being the single source of truth. `anchor` calls `SoulApi.repair`
  and `soul` never names `anchor`.
- **`periods` is explicit and there is no tick.** A caller that owns time passes how much passed
  (DEF-0111). A repair that accrued on its own clock would be a second source of truth for when
  time moved.
- **An anchor either REPAIRS or SHELTERS, and the id says which.** A hearth repairs what is
  already lost; a stone prevents a further loss. They are different promises, so they are
  different authored defs rather than one def with two flags — a flag pair is a shape content
  can contradict.
- **The authored coin price is RECORDED and the ITEM cost is the gate.** The purse belongs to
  `economy`, and this module declares no edge to it; subtracting from it directly would be a
  second place to disagree about a number. So `raise_anchor` gates on the items it can honestly
  check, and a purse-aware caller settles the coins before calling.

## Consequences

- **A rival cannot raise a second anchor on the same ground**, and the suite asserts it through
  two actors reading one store.
- **An anchor that repairs nothing and shelters nothing fails the content gate.** A building a
  player can raise for no reason is content that does nothing, and `validate` says so rather
  than shipping it.
- **A realm floor is a refusal by name, not a silent skip.** The stone is authored at
  `core_formation`; a mortal is told `realm_floor` instead of watching nothing happen.
- **Coins are not yet charged.** The price is authored and visible through `cost_of`, and the
  debt row records what is outstanding, but no purse is debited. Recorded rather than silently
  half-built, because a price nothing collects reads as an omission rather than a boundary.
- **Placement is an `at` string, not a world position.** An anchor names a place rather than
  living in one, which is enough for a ledger and not enough for a map. Honest while
  `domain` has no fixture-placement story to join.
- **A construction UI is owed.** The verbs exist and are tested headlessly; nothing renders them
  yet. The doors a screen needs are on the composition root — `raise_anchor` and
  `select_difficulty` — so a UI is a binding exercise rather than a design one.
- **An anchor repairs on the PERIOD boundary, which is the only place it can.**
  `advance_one_period` — the verb a screen's "wait a season" button and a headless probe both
  call — now repairs. That is the wiring which stops the hearth being a set of headless verbs:
  it exists, it is raisable, and it would otherwise heal nobody in play. The repair is reported
  in the period's own return value rather than swallowed, because a player who waits a season
  and sees nothing happen cannot tell a wiring fault from a feature that never fired.
- **A repairing anchor must restore at least one integrity over ONE period.** `repair_per_period`
  is authored as a float and `int(floor(rate * periods))` means a rate below `1.0` restores
  nothing over a single period. The hearth shipped at `0.5` and healed nobody while every
  module suite passed. `validate` now fails an anchor whose repairing rate is under `1.0`, and
  `repair` reports the rate and the periods when it restores nothing — because
  `nothing_to_repair` on a raised hearth reads as a wiring fault and is nearly always content.
