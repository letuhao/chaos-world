class_name TechniqueMagnitudeTable
extends Resource

## The authored per-realm technique magnitude ladder (ADR 0055).
##
## One number per realm id, R1 at 1.0, top near 2.77x. It is a MAGNITUDE for a
## bonus that rides on top of the actor and on top of any item, which is why it
## sits two orders of magnitude below `RealmPowerTable` (1.0 → 551x): a technique
## on the actor table would multiply 551.46x by 551.46x and put ~304,000x on one
## skill. Nothing here may be derived from `realm_power_table.tres` or from a realm
## index - the three per-realm tables measure different things and an index is
## not a table.
##
## The shape is the point. A linear ladder's step SHRINKS as a percentage of a
## rising base, so a linear ladder is shortest exactly where the rule bites
## hardest: the authored item table breaks the work-budget floor on 19 of its 29
## pairs, and a constant-ratio ladder satisfies the floor everywhere once it
## satisfies it at the deep end. So the guard here is per pair, not an endpoint
## or a span check.
##
## Written by `uv run python -m tools technique_power emit`, guarded by
## `technique_power check`: one entry per realm and no others, R1 at 1.0, strictly
## rising, every consecutive ratio at or below `TECHNIQUE_STEP`, all finite and
## inside a readable range. Like `realm_power check` it asserts those properties
## and NOT the recipe that first filled the file, so a designer can retune one
## realm by editing one line of it. The recipe exists here only to say what the
## first draft was.
##
## Format note: Godot's text resource parser accepts no comment line inside
## `[resource]` - one silently swallows the property after it - so this note lives
## here, in the script, and `technique_power report` prints the id-to-number
## mapping with every ratio.

@export var values: Dictionary = {}


## The magnitude multiplier for a realm id, or 1.0 for anything missing. Keyed by
## id rather than by ladder position so a realm inserted in the middle of the
## ladder cannot silently shift every realm below it onto the wrong number, and a
## missing entry stays neutral rather than collapsing a technique to zero.
func magnitude_for(realm_id: StringName) -> float:
	return float(values.get(realm_id, 1.0))
