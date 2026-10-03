class_name SectTuning
extends Resource

## Every balance number the sect module reads for its POLITICAL costs, in DATA —
## the ADR 0067 shape, copied from `CombatTuning` and `NationTuning`.
##
## `modules/sect/sect_tuning.tres` is the shipped instance; a read that reaches for a
## literal out of its own `.gd` is the defect this file exists to prevent. The point
## is the same one `NationTuning` makes: **a rebalance is a `.tres` edit, and no
## test has to re-pin a number that changed on purpose.**
##
## ## The defaults are the schema's neutral state, not a shipped balance
##
## `SectTuning.new()` is deliberately degenerate — a zero cost, a zero ceiling —
## so a caller who forgets the `.tres` gets a schism that costs nothing rather
## than a plausible one. `SectTuning.shipped()` is the only supported way to obtain
## a tuned instance, and `SectApi` reads it through `SectCatalog`.
##
## ## A cost is a MAGNITUDE the institution loses, never a rate on growth
##
## Standing is a continuous earned integer that can fall (ADR 0064), and a
## schism divides it and charges each half. None of these is a stat modifier and
## none may become one: the only stat surface an institution owns is the bounded
## `PERCENT` `InstitutionClaim.standing_percent` produces (ADR 0084), and a
## schism moves the number that percent is read from rather than adding a second
## one.

## What EACH half of a split pays on the declaration, in standing, before the
## per-unassigned-territory charge. Schism costs BOTH halves (ADR 0085): a free
## schism is a strictly-positive action, so every crisis would end in a split and
## no institution would ever have to answer for one.
@export var schism_cost: int = 0
## What each half pays per territory the declaration leaves UNASSIGNED. A schism
## is a split, not a transfer: ground neither half took is nobody's ground, and the
## price of leaving it that way is charged to both halves rather than to one.
@export var schism_cost_per_unassigned: int = 0
## The ceiling on the `periods` one treasury settlement call may be asked to
## settle. A bounded parameter rather than an unbounded one: there is **no clock in
## this repo** (DEF-0111), so every accrual takes an explicit `periods` from a
## caller that owns time — and "settle until it clears" must not be a way to skip
## the institution's own terms (the `SectSuccession.MAX_WAIT_PERIODS` precedent).
@export var max_settle_periods: int = 8


## A shipped, sane instance. The one place these numbers are written, so a caller
## who wants to rebalance edits the `.tres` rather than this file.
static func shipped() -> SectTuning:
	return load("res://src/modules/sect/sect_tuning.tres") as SectTuning


## What one half of a schism pays when `unassigned` territories are left
## unclaimed: the declared cost plus the per-territory charge. One place, so the
## two costs cannot be added in a different order by two callers.
func schism_price(unassigned: int) -> int:
	return maxi(0, schism_cost) + maxi(0, schism_cost_per_unassigned) * maxi(0, unassigned)


## The price a settlement of `periods` may ask for, clamped into
## `[0, max_settle_periods]`. Zero-or-less settles nothing and is never a negative
## accrual.
func settle_period_cap(periods: int) -> int:
	return clampi(periods, 0, maxi(1, max_settle_periods))
