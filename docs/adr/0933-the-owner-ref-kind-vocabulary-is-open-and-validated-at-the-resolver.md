# 0933 The owner-ref kind vocabulary is open and validated at the resolver

- Status: Proposed
- Date: 2026-10-09
- Depends on: ADR 0097 (one typed owner ref), ADR 0922 (a pack ships an organization),
  ADR 0083 (the three-state vocabulary)
- Supersedes: the CLOSED-`KINDS` half of ADR 0097 (0097 is never edited; this replaces
  its answer, not its text)
- Extends: ADR 0922 one layer down, to the holder vocabulary

## Context

ADR 0097 typed a resource node's holder as an `OwnerRef` whose `KINDS` was CLOSED to
`actor`, `clan`, `sect` and `nation`. ADR 0922 then opened the organization set: a pack
ships a kind with capabilities and no base-game edit. But the pack's kind could never
HOLD anything — three gates refused it: `OwnerRef.create` refused the kind, `from_dict`
dropped it, and the `holdings`/`custody` pre-filters (`OwnerRef.KINDS.has(kind)`)
refused it at claim and capture time.

Measured: `InstitutionRegistry` already knows every registered kind, and
`InstitutionDefCatalog` already lists authored organizations of ANY kind. The vocabulary
was open everywhere except at the holder — and the holder is the one place a leaf layer
cannot see a registry: `contracts/` may reference nothing (`LAYER_DEPS`), and a copy of
the kind list inside the leaf is a second vocabulary that drifts (ADR 0066's failure
mode).

## Decision

**The ref is a STRUCTURAL value; kind membership is validated where the registry is
visible — at the resolver.**

- `OwnerRef.create` refuses only an empty kind (`unknown_owner_kind`) and an empty id
  (`unknown_owner`). Any non-empty kind builds a ref.
- `OwnerRef.from_dict` KEEPS any non-empty kind it cannot check. It never drops and
  never coerces; a wrong-typed field is diagnosed as empty rather than aborting the load.
- `OwnerResolver.resolve` — the seam `holdings` and `custody` already consult — answers:
  `actor` by id (the one kind with no catalog); the three shipped tiers through their
  authored catalogs (unchanged); and **every other kind only if `InstitutionRegistry`
  knows it AND its id names an authored organization of that kind in the institutions
  family**. An unregistered kind refuses `unknown_owner_kind`; an unknown id of a
  registered kind refuses `unknown_institution`, the generic name `InstitutionLedger`
  already publishes.
- `OwnerRef.KINDS` stops being an acceptance vocabulary: it names the kinds whose
  resolution path ships statically (the four that resolve without the registry), and the
  module pre-filters that read it as a closed gate go away. The resolver's refusal is
  then the only kind gate on the path.

### Why an unregistered kind is KEPT on load — the other half of the ledger precedent

`clan_state.normalize` DROPS an id no def defines, "so a save from a wider content build
cannot smuggle in a clan the current build does not define". That rule is right where a
membership is ACTED ON — it grants recognition. A holder ref is not acted on: every use
goes through the resolver, which refuses by name, so keeping the key smuggles nothing in.
Dropping it, meanwhile, is destructive in the other direction: collapsing the ref turns a
held node into `vacant`, which is free ground for the next claimant and an erased world
fact on the next autosave.

## Rejected

- **An injected kind-checker on the ref (`set_kind_checker`).** Process-global mutable
  state inside a leaf value object: install-order dependence, and the cross-suite leak
  the registry and catalog instances carry explicit `clear()` to survive. The resolver is
  already installed and already the single answer to "does this name something real".
- **A copy of the registered kinds handed to the ref.** A second list that can drift
  from `InstitutionRegistry`.
- **Defaulting an unknown kind to `actor`.** Would let a stranger's holding pass a
  player's check.

## Consequences

- A pack's organization kind can hold a node, a captive and ground: register the kind (a
  `.tres` in the family, ADR 0922) and every path the four tiers walk is open to it.
- The three-state vocabulary is untouched: `{}` vs `{"vacant": true}` vs
  `{ok: false, reason}`.
- `holdings` and `custody` police no kind vocabulary of their own: their pre-filters are
  deleted and the resolver's refusal passes through verbatim, so one authority owns the
  rule.
- D8 pairing: opening the kind set costs a VALIDATION obligation, and the counter is that
  resolution refuses by name both an unregistered kind (`unknown_owner_kind`) and an
  unknown id of a registered kind (`unknown_institution`). The scarcity is that a kind
  exists only because a boot registered it from authored content — never because a save
  named it.
