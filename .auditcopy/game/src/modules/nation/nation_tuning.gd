class_name NationTuning
extends Resource

## Every balance number the nation module reads, in DATA — the ADR 0067 shape,
## copied from `CombatTuning`.
##
## `modules/nation/nation_tuning.tres` is the shipped instance; a read that
## reaches for a literal out of its own `.gd` is the defect this file exists to
## prevent. The point is the same one `RealmScaling` reading `RealmDef.power`
## instead of hardcoding 551.0 makes: **a rebalance is a `.tres` edit, and no test
## has to re-pin a number that changed on purpose.**
##
## ## The defaults are the schema's neutral state, not a shipped balance
##
## `NationTuning.new()` is deliberately degenerate — an empty tier table, a zero
## cap, a zero break — so a caller who forgets the `.tres` gets an obviously
## broken polity rather than a plausible one. `NationApi.tuning()` is the only
## supported way to obtain one.
##
## ## A tier is an INDEX, never an amount
##
## `tier_index` is on `NationTerritoryDef` and it selects one row here. Two
## territories of the same tier therefore read the same numbers by construction, and
## a new tier is a new row rather than a per-territory override that would drift.

## What a held claim of this tier is worth per period, as a percent of a nation
## standing cap. A RATE: how much one period of holding is worth, never a
## magnitude. Holding pays recognition, so this is recognition and nothing else.
@export var tier_yield: Array[float] = []
## What holding this tier costs per period, in standing points. An upkeep that
## exceeds what the tier yields is a trap, and an author can read that off this row
## rather than discovering it in play.
@export var tier_upkeep: Array[float] = []
## How dense the qi over a claim of this tier is, as a percent contribution to the
## holder's qi absorption. Capped by `qi_density_cap`, because an uncapped qi
## source is a cultivation ladder beside `realm_power_table.tres` (ADR 0050).
@export var tier_qi_density: Array[float] = []
## The standing floor a claim of this tier needs before it may be STAKED — a
## contest opened against it. The ordinary gate (ADR 0084 `standing_below_floor`),
## and it is a route, not a wall.
@export var tier_claim_standing_floor: Array[float] = []
## The standing floor a claim of this tier needs to be KEPT. Below it the claim
## lapses on the next accrual and is released. A defeat therefore costs ground
## slowly and by a declared floor, not by a script that resolves a war.
@export var tier_hold_standing_floor: Array[float] = []
## How many separate holders a seat of this tier may recognise at once. Ids and
## counts, never an amount: retuning a rate must never rewrite a save.

## The ceiling on every qi-density percent in this file, tiered rows included.
## This is what makes qi density a bounded recognition rather than a second
## progression curve.
@export var qi_density_cap: float = 0.0
## Standing a side loses per verdict it loses in a standoff. One number for every
## mode, so exhaustion cannot be a per-mode dial nobody can compare across modes.
@export var exhaustion_per_loss: float = 0.0
## The exhaustion at which a side must withdraw or forfeit. Reaching it is a
## REFUSAL to keep fighting, never an award of ground: a withdrawal moves no
## territory (ADR 0085), so the declaration and the counter cannot decide a war.
##
## **It must be strictly above what the LONGEST authored quota can reach.** At 12
## per loss the quotas are 3 / 5 / 1, so a break of 36 lands exactly on a
## contest's third verdict and a siege's third — and two rules then collide on
## one exchange: the quota that both sides declared, and a counter. That shipped at
## 36, and the result was that no standoff in the build ever resolved: a contest
## and a siege both withdrew on the verdict that was supposed to win them, and
## `test_nation_conflict.gd` could not tell that from a module that was simply
## broken. 72 is two contest quotas, and comfortably above a siege's five. A
## rebalance that moves `exhaustion_per_loss` must move this with it.
@export var war_break: float = 0.0
## Standing the winning side gains when a standoff closes.
@export var standing_on_win: int = 0
## Standing the losing side loses. A defeat lowers a number and never dissolves
## an institution (ADR 0085).
@export var standing_on_loss: int = 0
## Standing both sides lose when a standoff closes by surrender. Authored so a
## surrender is strictly worse for the surrendering side than a fought loss.
@export var standing_on_surrender: int = 0
## Standing returned per period of recovery, for a nation climbing out of a lost
## war. Bounded and slow on purpose: a defeat is a condition to climb out of,
## not a save-deletion.
@export var standing_recovery: float = 0.0
## What each half of a schism pays on the split, before the per-unassigned-territory
## charge. Schism costs BOTH halves (ADR 0085), because a free schism is a
## strictly-positive action and every crisis would end in a split.
@export var schism_cost: int = 0
## What each half pays per territory the split leaves unassigned.
@export var schism_cost_per_unassigned: int = 0


## A shipped, sane instance. The one place these numbers are written, so a caller
## who wants to rebalance edits the `.tres` rather than this file.
static func shipped() -> NationTuning:
	return load("res://src/modules/nation/nation_tuning.tres") as NationTuning


## The shipped tuning, or `null` when the build does not ship one.
##
## `load()` returns `null` for a `.tres` that cannot be read, and every field of
## this struct defaults to `0`, so a caller that treated that null as a tuning would
## read "a defeat costs nothing, and a side breaks at zero exhaustion". That second
## one is not a harmless default: exhaustion is compared with `>=`, so a break of
## zero declares EVERY side exhausted the moment it loses once, and every standoff
## in the build refuses its first verdict. A caller wanting the tuning rather than
## an answer should use `catalog.tuning()` — which resolves to `shipped_or_zero` —
## so that the missing case is the safe one rather than the surprising one.
static func shipped_or_zero() -> NationTuning:
	var tuning := shipped()
	return tuning if tuning != null else NationTuning.new()


## One tier row, or `0.0` for a tier this file does not author. A missing row is
## an obviously wrong answer rather than a plausible one, which is the same
## discipline `CombatTuning`'s degenerate defaults follow.
static func row(rows: Array[float], tier_index: int) -> float:
	return rows[tier_index] if tier_index >= 0 and tier_index < rows.size() else 0.0


## The yield rate for a tier.
func yield_for(tier_index: int) -> float:
	return row(tier_yield, tier_index)


## The upkeep rate for a tier.
func upkeep_for(tier_index: int) -> float:
	return row(tier_upkeep, tier_index)


## The qi density for a tier, capped. The cap is applied HERE rather than authored
## per row so no row can exceed it by editing one number.
func qi_density_for(tier_index: int) -> float:
	return minf(qi_density_cap, row(tier_qi_density, tier_index))


## The standing floor below which a claim of this tier may not be contested.
func claim_floor_for(tier_index: int) -> float:
	return row(tier_claim_standing_floor, tier_index)


## The standing floor below which a claim of this tier is no longer held.
func hold_floor_for(tier_index: int) -> float:
	return row(tier_hold_standing_floor, tier_index)
