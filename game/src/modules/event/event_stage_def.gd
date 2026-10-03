class_name EventStageDef
extends Resource

## One stage of an authored world event (ADR 0114). A stage is a beat the world
## reaches, and it is where the world records that it reached it.
##
## ## `on_enter` entries are BEATS, not rewards
##
## An entry is `{fact: StringName, amount: int}` — a claim that something happened,
## offered to the one fact ledger ADR 0113 built. Nothing here grants a fate, moves
## a currency or touches a stat: an event that pays is a `pay` row on the
## `EventDef`, paid once at resolution, and a stage only ever says what the world
## now remembers.
##
## `requires` is a requirement in the SAME shape `DestinyGate` / `SocialGate`
## read, so this module authors no second requirement language. The stage opens only
## when that requirement passes against the ledger.
##
## `duration_periods` is how many periods the stage holds before the NEXT stage may
## open. It is a count, never a duration in seconds: there is no clock (DEF-0111).

@export var stage_id: StringName = &""
@export var display_name: String = ""
## A requirement in the gate vocabulary. Empty means ungated — the stage opens as
## soon as its predecessor's `duration_periods` have elapsed.
@export var requires: Dictionary = {}
## Beats the world records when this stage opens. `{fact, amount}` per entry.
@export var on_enter: Array[Dictionary] = []
## How many periods this stage holds open. Zero resolves at the next pull, which is
## the right shape for a stage that only a condition advances.
@export var duration_periods: int = 0


## Whether this stage is the last one, and so ends the event at its resolution.
func is_final(index: int, count: int) -> bool:
	return index >= count - 1
