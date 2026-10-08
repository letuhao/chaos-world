# 0931 Inter-organization debt, grant and stance verbs over the world polity ledger

- Status: Proposed
- Date: 2026-10-08
- Answers (partially): DEF-0119 (where ledgers persist), DEF-0179 (graph sees schisms/wars)

## Context

`WorldPolityLedger` normalized inter-institution debts but published no writer, so no
caller could open favour, a grant, a schism or a war between two institutions. The
relation graph read the authored catalog only. Two measurements forced the shape: the
fold relabelled every winning row onto the canonical key, which made "larger owes
smaller" inexpressible and misattributed any reversed spelling that won; and `String(int)`
does not exist in Godot 4.7, so one corrupt key aborted a whole load.

## Decision

**Verbs live beside the ledger in `core/institution_relation.gd`; storage and the fold
stay in `WorldPolityLedger`.** `declare`/`settle`/`reconcile`, `declare_schism`/`declare_war`,
`grant`/`escheat`, `relations_of`/`grants_of`. Favour is the creditor's read of a debt
(`is_owed`), not a second number. Terms are ids+counts; sequence counts opens and orders
rival spellings, lower wins. One row per pair: a crossed opposite-direction debt refuses
as `crossed_lines` (settle first) rather than netting silently. Grants ride a `grants`
container beside the pinned two, with terms living once as a real debt row; `escheat`
refuses over open lines and always costs a one-period forfeit. The graph takes an optional
world ledger and reads only stance flags from it — debt terms map to no stance. D8 gate:
no fee to record a fact (the debt is the cost), bounded outputs (`PERIOD_CAP`, `DEBT_LIMIT`,
`GRANT_LIMIT`, `TERM_LIMIT`), counted receipts, priced revocation. Rows keep the winner's
true direction; empty debt rows and non-text keys are dropped, never aborted on.

## Consequences

- `owed` reads the canonical row plus its recorded direction; the pinned fold test is
unchanged and green, plus a new pin for the reversed-wins case.
- Bare `graph()` still answers authored-only; `graph(ledger)` sees schisms/wars with
`polity` provenance. Wiring the store into it needs a `save` dep on relations (reported,
not taken); sect/nation writers route through these verbs in a later slice.
- Follow-up: widen `CONTAINERS` + the store table + the pinned literal to `grants`.
