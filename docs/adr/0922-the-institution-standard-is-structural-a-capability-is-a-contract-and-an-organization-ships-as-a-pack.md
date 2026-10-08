# 0922 The institution standard is structural, a capability is a contract, and an organization ships as a pack

- Status: Proposed
- Date: 2026-10-08
- Supersedes: the NESTING half of ADR 0083 (0083 is never edited; this replaces
  its answer, not its text)
- Extends: ADR 0184 (the locked registration context and its named-failure policy,
  one level down: a pack's capabilities are graded at load)

## Context

ADR 0271 registered a kind with capability FLAGS — `teaches`, `has_territory`,
`has_offices`, `is_born_to` — and left three gaps:

- The flag list is CLOSED, so a modder shipping a new organization kind can never
  ship a capability this build has not heard of.
- A flag DECLARES; nothing checks what sits behind it. Two kinds carrying
  `teaches` may behave differently and no gate sees it.
- ADR 0083's three tiers still arrive as module-graph edges
  (`clan → sect → nation`), and the edges carried the abilities. Measured:
  `lantern_exchange.tres` authors `expel` on its top seat and its only reader
  lived inside `sect`, so a trading guild's authored authority was executable by
  nothing at all.

## Decision

**The standard is structural: one contract per capability, in `contracts/`.**
Each is an `InstitutionCapability` — identity, a named refusal vocabulary,
lifecycle verbs that return PLANS of primitives, and its own
`contract_findings()` suite. One capability per contract is the
interface-segregation rule made structural: a guild implements `Expellable`
without ever seeing `Teachable`, and a class a pack never loads cannot break it.

**An organization ships as a pack: a kind is a registration carrying its def
type and its capability implementations.** The set is OPEN — registration
refuses a FAILED suite, never an unfamiliar id — so a modder ships a new
capability beside a new kind, and `InstitutionContract.STANDARD` is published
VOCABULARY, never a gate.

**D3 — a pack claiming a capability must pass that capability's contract suite
at load, or the KIND is refused by name.** `InstitutionContract.register` runs
`impl.contract_findings()` on every entry and refuses as `contract_failed`,
carrying the findings. An interface cannot check its own implementers, and a
suite production code cannot call guards nothing at load, so the suite and the
mechanism are ONE body with two drivers. A pack that overrides
`contract_findings` to return `[]` makes a false declaration in its own name —
the same class of act as overriding any gated method, which is why the findings
are published on the refusal rather than merely logged.

**This supersedes the NESTING half of ADR 0083.** 0083 said the tiers are not a
containment tree; the module graph nested them anyway, and the edges carried the
abilities. Under a pack, a kind's abilities ARE its capability implementations,
so authority, offices, expulsion, teaching, territory, duty, admission and
succession are no longer load-bearing module edges: any kind carries any
capability and nothing nests.

**This extends ADR 0184's mod seam.** 0184 locks the loader and requires a
named boot failure for a broken pack, never a silent skip; this is that policy
one level down — a capability that fails its suite refuses its kind by the same
named-cause discipline.

**Rejected alternatives:**

- **A god-contract** — one capability carrying every verb. A guild would inherit
  a `teach()` it must never use, and a forgotten override would be a WRONG
  ANSWER (teaching nobody) rather than an absent one.
- **A `Dictionary` of callables** — a dictionary has no name, so AGENTS.md's
  "any implementation of a `contracts/` interface must pass the same contract
  tests" would have nothing to point at. `DamageMechanism` rejected it for the
  same reason.

## Consequences

- A capability DECIDES; it never commits. Every verb returns a plan of
  primitives and the applier writes it, so **a refusal writes nothing**
  (ADR 0044) is structural rather than a discipline each caller remembers —
  and `contracts/` may not name the store a membership lives in.
- The eight capabilities ship with per-capability suites, and
  `tests/contracts/test_institution_capabilities.gd` drives each on its own
  terms; `tests/contracts/test_institution_contract.gd` plants DELIBERATELY
  BROKEN capabilities and asserts `register` refuses them by name — the
  expected-red path, because a green guard is not a tested guard (INC-0016).
- The reference implementation is content: the shipped trading guild's top seat
  authors `expel` and its `clerk` does not, and the capability suite drives both
  through `Authorised` + `Expellable` with NO tier module loaded — which is what
  makes the deletion of tier duplication (a later slice) a measurement rather
  than a hope.
- Extending the family is adding a capability file with a suite, not editing
  this one; a capability-specific verb stays on its capability, because a base
  that accumulates one-offs is the god-contract wearing a different hat.
