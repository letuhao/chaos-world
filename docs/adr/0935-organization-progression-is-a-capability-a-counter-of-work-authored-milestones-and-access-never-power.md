# 0935 organization progression is a capability: a counter of work, authored milestones, and access never power

- Status: Proposed
- Date: 2026-10-09
- Depends on: ADR 0922 (a capability is a contract), ADR 0084 (an institution grants
  recognition and access, and never power), ADR 0083 (three tiers, one vocabulary)
- Extends: ADR 0922's family with a tenth capability (D11: the cross-game comparison
  found organization progression had no backlog entry and no implementation)

## Context

An organization of any kind could be founded, joined and governed, but not GROWN.
Growth is the newest place a power-shaped number could enter the institution standard,
and ADR 0084 forbids a fourth grant: the whole political stat surface is one bounded
percent. The counter therefore has to be shaped so a magnitude has nowhere to sit, and
what it buys has to be access or capacity by construction.

## Decision

**`Progressive` (`contracts/progressive.gd`) is the tenth capability: a flat integer
counter the organization earns from its own activity, and AUTHORED milestones derived
from it.** A milestone may unlock exactly three things — authored office ids
(`positions`), authored capability ids (`capabilities`) and a member allowance
(`member_capacity`) — and the key set is CLOSED: any other key refuses `unknown_unlock`
by name, `standing_cap` first among them.

- **The counter accrues from WORK: `served` (duty periods settled) + `admitted`
  (people).** Time is not a source — `periods` is never read — so an idle organization
  earns nothing and the counter cannot be farmed free. The cost is member effort and
  people: every duty line is opened by admission or office and paid out of the member's
  own periods, and admission is gated by authored capacity and opens more duty.
- **A `standing_cap` raise is refused, with the measurement.** `standing_percent =
  min(0.10, 0.001 * standing)`: below a cap of 100 a raise lifts the ceiling a member
  can reach (POWER); at or above 100 the percent is saturated and a raise only dilutes
  `normalized()` (nothing). Power or nothing, never access.
- **Bound the OUTPUT, never the INPUT.** The counter is unbounded — a growth-rate cap
  dies because the rate must scale with the organization — while milestones are
  authored and finite, so the union of everything growth can unlock is the authored
  table. `MAX_MILESTONES = 64` is a corrupt-table guard, never the D8 bound.
- **The applier is `core/institution_progression.gd`.** The counter's subject is the
  organization, so it lives in a process store beside `InstitutionMembership`'s rosters
  (persistence is DEF-0119's gap, recorded there); `declare`/`record`/`summary` drive
  the capability and write only what its plan says, and a refused verb writes nothing
  (ADR 0044).

Rejected: a stat grant, a multiplier or anything realm-shaped (no method takes a realm
id and no answer returns a multiplier — the `DoctrineRule` shape answer, so there is
nowhere to put a magnitude); a treasury or second currency (the counter IS the cost
record); rolling a milestone (walked, never rolled, ADR 0058/0084); counting elapsed
periods (the free farm this design exists to refuse).

## Consequences

- Any kind can claim growth: the shipped trading guild grows with no
  sect/clan/nation code, exactly as it expels or teaches (test-proven).
- The authored table is caller-fed today (`declare` takes it, the `AdmitTable.join`
  pattern); its production home is an `InstitutionDef` field plus a boot call —
  reported with this slice, not taken.
- The closed key set is the structural guard against a power surface entering through
  content, and the contract suite plants a `standing_cap` row so the refusal stays
  red-testable.
