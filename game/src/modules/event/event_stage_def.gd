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

## An OPTIONAL verdict this stage delivers to ANOTHER event (DEF-0315).
##
## Authored as `{war_id: StringName, winner_id: StringName}`. When the stage opens, the
## director calls [method EventApi.resolve] for `war_id` with `winner_id` — so a moment
## that DECIDES a contest (a tournament's final, a tribunal's ruling) is the caller
## `EventApi.resolve` never had, and the war's own ladder never decides itself.
##
## ## Why this is a field and not the war deciding
##
## ADR 0085: "verdicts arrive from outside." A sect war's prize is declared by `nation`
## and its winner comes from whatever RAN the contest — so the tournament event, not the
## war, authors this. The war's own `on_enter` beats only ever say the world remembers a
## stage; they can never name a winner, because that would be the political layer ruling
## on itself.
##
## ## Why it lives here rather than in the composition root
##
## The verdict is CONTENT: a `resolves`-bearing stage is a `.tres` edit and needs no
## wiring. The director applying it at the end of an advance keeps the record-then-resolve
## order the rest of this module holds, and a stage that names no war simply delivers
## nothing.
##
## Empty (the default) means this stage delivers no verdict, which is every shipped stage
## but the one that ends a tournament.
@export var resolves: Dictionary = {}


## Whether this stage is the last one, and so ends the event at its resolution.
func is_final(index: int, count: int) -> bool:
	return index >= count - 1
