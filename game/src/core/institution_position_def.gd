class_name InstitutionPositionDef
extends Resource

## One authored office inside ANY institution: **a duty, not a level** (ADR 0083,
## ADR 0271). The generalisation of `SectPositionDef` for a kind that is not a sect.
##
## ## What is COMMON and what is NOT, and why this file is smaller than its model
##
## Taken from `SectPositionDef`: `id`, `display_name`, `description`, `capacity`,
## `duties` and `authorities`. Every one is read here by a method below, so this is
## not a field nothing reads.
##
## **Deliberately ABSENT**, each because shipping it would be authored-but-
## unreachable content — which `SectPositionDef`'s own note calls out for `contest`
## ("an authored-but-unreachable method is dead content"):
##
##   - `succession_method` / `succession_param` / `succession_periods`. A walk is
##     `SectSuccession`'s, inside `sect`, which may not be reached from a guild's
##     office. A generic position that named a method would be a word in every
##     `.tres` and a branch with no production caller.
##   - `standing_floor`. `InstitutionLedger.promote` takes a position id and NOTHING
##     else, so no promotion in the generic foundation ever reads a floor. sect's
##     `SectGate` reads its own, and a guild has no gate in this slice.
##   - `standing_percent_stats`. This is the sharpest omission and the deliberate
##     one. ADR 0084 makes the allowlist the ONLY stat surface an institution has,
##     but the code that CONSUMES it is `SectProjection`, inside `sect`. A generic
##     allowlist with no projection is an author writing numbers that go nowhere —
##     and the honest default for a guild position is recognition of **nothing**,
##     which `InstitutionClaim.standing_percent` already answers as `0.0` at zero
##     standing. The allowlist moves to `core/` in the slice that migrates `sect`.
##   - `teach_tax`. Transmission is a CAPABILITY (`teaches`) whose content is a
##     doctrine's floor, and a doctrine is `sect` content.
##
## ## Authority is data, never a number
##
## "May this member freeze a credit" is a `.tres` question, not `if rank >= 3`.
## `authorities` is an `Array[StringName]` of authored verb ids and this class never
## compares two positions against each other — the numeric hierarchy ADR 0064 kept
## out of the claim would come straight back through the back door the moment a
## position became an index.
##
## ## `capacity` is authored, and 0 is not 1
##
## `0` is unbounded, `1` is a single **seat** and anything above 1 is a **room**
## that can fill. ADR 0084 makes that distinction load-bearing — a seat produces a
## succession contest and a room produces a queue — so [method has_room] is the read
## that justifies the field, and the two words are left to the ADMITTING layer that
## actually renders a difference between them. A def is content and owns no verb,
## so this class answers "is there room" and never "what shall I tell the player";
## sect's `seat_occupied` / `capacity_full` pair belongs beside the gate that emits
## them and is removed by the sect migration, not restated here.
##
## ## A duty is a duty, and a guild that takes one gives one back
##
## `duty_per_period` is what the institution TAKES from the holder and
## `patronage_per_period` is what it GIVES. Both open obligation LINES — ids and
## counts, never authored amounts, so retuning a rate never rewrites a save. **Both
## fields exist as a pair** (AGENTS.md's yin-yang rule): an office that only takes is
## a debt collector, and an office that only gives is a faucet, and neither is a
## choice. An author who wants either reads `0` on the other, which is a statement.
##
## Neither is a CLOCK. Nothing here reads `Time.get_ticks*`, declares `_process` or
## calls `get_tree()`: a ledger whose contents depended on when the save was written
## is not a ledger (DEF-0111, ADR 0083).

## An office no member holds. The seat **exists** and its value is absent
## (ADR 0083): a visible row, never `0` and never hidden.
const NO_POSITION := &""

@export var id: StringName = NO_POSITION
@export var display_name: String = ""
## Clinical and mechanical, in the game's own voice: this is an office and the work
## it obliges (AGENTS.md). Never a rank and never a boast.
@export var description: String = ""

## How many members may hold this office at once. `0` is unbounded, so an office
## nobody capped is a room with no walls; `1` is a seat; above 1 is a room that can
## fill. See the class note for why the difference between the three is load-bearing.
@export var capacity: int = 0

## What the holder MUST do, as authored verb ids. Counted, never executed: this class
## owns no verb, and whoever spends the line is another layer's answer.
@export var duties: Array[StringName] = []
## What the holder MAY do, as authored verb ids. The whole of "authority" in this
## repo. A `0` here is a statement too: an office nobody grants anything to.
@export var authorities: Array[StringName] = []

## Periods of `duty_<office>` the holder owes each period. Zero means the office does
## not ask for work, which is an author's choice and never a default this class
## infers.
@export var duty_per_period: int = 0
## Periods of `patronage_<office>` the institution hands the holder each period. See
## the class note: this is the other half of the pair above, and an office that
## grants nothing has no member worth seating.
@export var patronage_per_period: int = 0


## Whether `authority_id` is one this office may exercise. An authored lookup, never
## a comparison between offices and never an index test.
func grants(authority_id: StringName) -> bool:
	return authority_id != &"" and authorities.has(authority_id)


## Whether `held` members may still be admitted, given this office's authored cap.
## Unbounded always answers true, so an uncapped office is never a wall.
func has_room(held: int) -> bool:
	return capacity <= 0 or held < capacity


## How many holders this office allows, as the authored cap reads. `0` is unbounded.
func room() -> int:
	return maxi(0, capacity)


## Whether this office is a single SEAT rather than a room — the distinction ADR
## 0084 makes load-bearing, published as a READ so the admitting layer can name the
## difference instead of inferring it from a cap it would otherwise have to re-derive.
func is_seat() -> bool:
	return capacity == 1


## The authored duty verbs, canonically ordered by their STRING value.
##
## Sorted on `Array[String]` and converted back, for the reason `WorldFact.ids` and
## `InstitutionLedger.sorted_keys` both state: `Array[StringName].sort()` is not
## specified to order by string value and the ids are interned, so the result could
## depend on which id loaded first.
func duty_terms() -> Array[StringName]:
	var text: Array[String] = []
	for duty in duties:
		if duty != &"":
			text.append(String(duty))
	text.sort()
	var out: Array[StringName] = []
	for entry in text:
		out.append(StringName(entry))
	return out


## The obligation lines this office opens, keyed by period count. **Ids and counts,
## never authored amounts**, so retuning a rate never rewrites a save — and this is
## the ONE shape `InstitutionLedger.positive_lines` accepts.
##
## A rate that is zero opens NO line rather than a line worth zero, because "nobody
## opened this debt" and "this debt is settled" are the same state
## (`InstitutionClaim.owed` states the rule).
func obligation_lines() -> Dictionary:
	var out := {}
	if duty_per_period > 0:
		out["duty_%s" % String(id)] = duty_per_period
	if patronage_per_period > 0:
		out["patronage_%s" % String(id)] = patronage_per_period
	return out
