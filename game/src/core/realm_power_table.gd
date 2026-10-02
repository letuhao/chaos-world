class_name RealmPowerTable
extends Resource

## The authored per-realm stat multiplier table (ADR 0050).
##
## One multiplier per realm id. The runtime reads these numbers and does no arithmetic on
## them: which realm is how strong is content, and content is data.
##
## This file is what replaced the one power ladder. The difference is not cosmetic.
## `PowerLadder` computed `P(Θ)` from the realm index at runtime, so any change to the
## shape moved every magnitude in the game at once and the guard had to forbid private
## curves to keep the two honest. Here a realm's strength is one editable number; the
## shape is whatever the numbers say.
##
## Written by `uv run python -m tools realm_power emit`, guarded by `realm_power check`
## (one entry per realm and no others, R1 at 1.0, strictly rising, finite, and inside a
## readable range). The guard asserts those properties, not the recipe that first filled
## the file - if it asserted the recipe, this file would be a cache of a formula and the
## curve would only be hiding.
##
## Format note: Godot's text resource parser accepts no comment line inside `[resource]`
## - one silently swallows the property after it - so this note lives here, in the script,
## and `realm_power report` prints the id-to-number mapping.

@export var multipliers: Dictionary = {}


## The multiplier for a realm id, or 1.0 for anything missing. Keyed by id rather than by
## ladder position so a realm inserted in the middle of the ladder cannot silently shift
## every realm below it onto the wrong number. A missing entry must not scale a stat to
## zero either, so the fallback is the neutral 1.0.
func power_for(realm_id: StringName) -> float:
	return float(multipliers.get(realm_id, 1.0))
