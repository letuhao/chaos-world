class_name DifficultyTable
extends Resource

## The authored per-difficulty scalar table (ADR 0129).
##
## ## Why a table and not a number in code
##
## Difficulty has one reason to change — what a difficulty id means — and a retune must not be
## a code edit. The table is keyed by a STABLE ID and never by an enum index and never by a
## realm: an inserted preset cannot shift every other preset onto the wrong number, which is
## exactly the failure `core/realm_power_table.tres` was built to prevent for realms.
##
## ## Why the scalar set is closed
##
## Four scalars, all of them fractions of something the player already holds. A fifth column
## would be a second power curve in disguise, and this repo has three power-shaped tables
## already with a written rule that adding a fourth needs an ADR. So the set is closed here
## and `uv run python -m tools difficulty check` fails on a fifth key rather than trusting a
## future author to remember.
##
## **`loot_ceiling` was the fifth, and it is deleted (BL-0779).** A `LootTier` is ORDINAL: it
## is selected by an authored `tier_index`, and scaling one by a difficulty is ADR 0050's
## category error one layer down — reading one number as two. The only fractions in
## `modules/loot/` are the `loot_bonus` axes, and those already sit under hard per-axis caps
## that a difficulty may not re-open. A column with no honest consumer is removed, not left
## authored.
##
## ## Why the default row is exactly 1.0
##
## Selecting the shipped default must be arithmetically a no-op, or picking the middle option
## silently retunes every number in the game. This is the "R1 at 1.0" rule of the realm power
## table applied to a preset axis, and the guard asserts it.

## The closed scalar vocabulary. A consumer may read these and nothing else, and the guard
## fails a table carrying a key outside this set.
##
## `death_loss_cap` was the fifth and it is deleted (BL-0887), on the same grounds as
## `loot_ceiling` before it (BL-0779): measured against the authored table the cap bound on NO
## preset, so its reader was a no-op rather than absent — a shape the earlier sweep, which
## looked only for scalars nothing read, did not catch.
const SCALARS: Array[String] = [
	"soul_damage_share",
	"guardian_effectiveness",
	"tribulation_preparation_credit",
]

## The preset every id resolves to when the table has no row for it. NOT a zero: an unknown id
## must be inert, never a silent deletion of the player's numbers.
const NEUTRAL: StringName = &"standard"

## Lower and upper bounds for any scalar. A preset must stay inside them, because a scalar
## outside this window is either decorative or a magnitude the game should own.
const MIN_SCALAR := 0.0
const MAX_SCALAR := 10.0

## Preset id -> scalar row. Every row carries every key in `SCALARS`; a missing key reads as
## absent and a consumer would read that as a zero rather than as the default.
@export var presets: Dictionary = {}


## The scalar row for `difficulty_id`, or the neutral row when this table has none. Never a
## zero and never a partial row: a missing scalar reads as `1.0` so an incomplete preset
## cannot make a consumer multiply by nothing.
func scalars_for(difficulty_id: StringName) -> Dictionary:
	var row = presets.get(String(difficulty_id))
	if row is Dictionary:
		return _filled(row as Dictionary)
	return _filled(presets.get(String(NEUTRAL), {}) as Dictionary)


## Every preset id, sorted. `DirAccess` scan order is not stable, and a settings screen listing
## them must not reorder itself between reads.
func ids() -> Array[StringName]:
	var strings: Array[String] = []
	for key in presets.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## Every key filled, so a consumer reads a number rather than deciding what absence means.
func _filled(row: Dictionary) -> Dictionary:
	var out := {}
	for scalar in SCALARS:
		out[scalar] = 1.0 if not row.has(scalar) else float(row[scalar])
	return out
