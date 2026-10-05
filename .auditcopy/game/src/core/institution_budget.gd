class_name InstitutionBudget
extends Resource

## How many institutions may ACT in one period at each tier of distance (BL-0198).
##
## ## Why this lives in `core/` and not in either module
##
## Both `sect` and `nation` read it, and ADR 0083 makes those tiers **peers**: a
## nation does not contain a sect, and `sect` declares no `nation` edge. Filing the
## budget in either module would mean a dependency one of them does not have — and
## `BARE_REF_UNITS` excludes `modules/*` (`rules.py:60`), so a bare reference written
## that way is a code-only edge `tools arch` reports ZERO violations on. ADR 0083
## says so in its own Consequences: the `nation -> sect` edge is "enforced by review,
## not by the gate."
##
## `core` is a **LAYER** rather than a module, so the cross-module facade rule never
## applied to it, and both tiers already declare `core`. This is the reasoning
## `InstitutionClaim` already records for being in `core/`: *"holding shared
## foundation data here creates zero new edges"*, and it is the `RealmRate` precedent —
## one curve in `core`, shared by every path that needed it, existing precisely
## because private copies could only be kept in sync by hand (ADR 0066).
##
## ## The `.tres` is the shipped instance
##
## `core/institution_budget.tres` is the one place these numbers are written, so a
## rebalance is a data edit (ADR 0067's `CombatTuning` / `NationTuning` shape) and no
## test has to re-pin a number that changed on purpose.
##
## ## A cap is a COUNT OF INSTITUTIONS, never an amount
##
## **No cap here is ever multiplied by anything.** `near_cap` is a loop bound — the
## `for` inside `act` walks a candidate list already sorted and stops after this many
## — and a bound is the one shape `tests/arch_rules/test_no_unbounded_wait.gd`
## accepts. A cap multiplied by a period count, or by a yield rate, would be a second
## magnitude ladder beside `realm_power_table.tres` (ADR 0050).
##
## ## The tier buys FREQUENCY of action, never SIZE of effect
##
## `near`, `distant` and `strategic` name how OFTEN an institution acts, not how much
## its action is worth. A "near = 2x, distant = 0.5x" yield multiplier is exactly the
## second scale ADR 0097 refused for holdings, so the tier appears nowhere near a
## standing delta — only ever as a count of who acts.

## The simulation tiers, canonically ordered, so a caller cannot invent a fourth.
const TIERS: Array[StringName] = [&"near", &"distant", &"strategic"]

## How many institutions may act at the `near` tier in one period. Pinned to the
## ENTIRE shipped authored institution count — two sects and two nations — because a
## cap above the authored count is unimplementable and a cap below it would silently
## drop an institution the player can stand next to.
@export var near_cap: int = 0
## How many may act at the `distant` tier in one period. Half of near, so a pair of
## distant actors can exchange a turn without the outcome depending on dictionary
## ordering; one per period is a deterministic queue wearing an LOD costume.
@export var distant_cap: int = 0
## How many may act at the `strategic` tier in one period. Exactly one, never more:
## a strategic act is a standoff declaration or a defeat, and two closing in one
## settle means two transfer passes over the same claim row (ADR 0085).
@export var strategic_cap: int = 0


## A shipped, sane instance. The one place these numbers are written.
static func shipped() -> InstitutionBudget:
	return load("res://src/core/institution_budget.tres") as InstitutionBudget


## How many institutions may act at `tier` in one period, or `0` for a tier this file
## does not author. A missing row is an obviously wrong answer rather than a
## plausible one — the same discipline `NationTuning`'s degenerate defaults follow.
##
## Clamped at zero so a hand-edited `.tres` cannot make a cap negative and turn a
## loop bound into something a caller has to reason about before using it.
func cap_for(tier: StringName) -> int:
	match String(tier):
		"near":
			return maxi(0, near_cap)
		"distant":
			return maxi(0, distant_cap)
		"strategic":
			return maxi(0, strategic_cap)
		_:
			return 0


## Whether `tier` is one this file authors. A caller asking about `close` gets false
## rather than a nearest match, so an invented tier fails loudly instead of quietly
## acting at the wrong budget.
func knows_tier(tier: StringName) -> bool:
	return TIERS.has(tier)


## The worst case across all three tiers: how many actions one period can ever cost,
## with none of them multiplied. Published so a caller can assert the bound rather
## than trusting it — `SocialApi.tick`'s "returns a count so a caller can assert the
## tick is bounded" (ADR 0091), applied to a budget instead of a decay.
func worst_case() -> int:
	var total := 0
	for tier in TIERS:
		total += cap_for(tier)
	return total
