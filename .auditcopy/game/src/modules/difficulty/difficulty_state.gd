class_name DifficultyState
extends RefCounted

## The versioned difficulty selection, stored under `actor.module_data` (ADR 0027 pattern).
##
## Only the SELECTED ID lives here. The numbers live in one authored table (ADR 0129), so
## retuning a preset never rewrites a save — a save naming `hard` reads today's `hard` row,
## which is what makes an old save still meaningful. Storing the resolved numbers instead would
## freeze a retune into every save already written.
##
## The id is what makes a save self-describing: it answers "what was this run playing under"
## without any table lookup, and an old save with no key reads as the neutral preset rather
## than as an error.

const SCHEMA_VERSION := 1
## `actor.module_data` key.
const MODULE_KEY := &"difficulty_state"


static func normalize(payload: Dictionary) -> Dictionary:
	var selected := String(payload.get("difficulty_id", ""))
	return {
		"version": SCHEMA_VERSION,
		# An absent or unreadable id is the neutral preset, not "unset": a save that cannot say
		# what it was playing under must still resolve to numbers that are the shipped
		# baseline, or it silently becomes the easiest difficulty.
		"difficulty_id": DifficultyTable.NEUTRAL if selected.is_empty() else selected,
	}


static func empty() -> Dictionary:
	return normalize({})
