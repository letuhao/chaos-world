class_name NationOfficeDef
extends Resource

## One authored seat a polity may fill. **A seat that nobody holds still exists**
## (ADR 0083), which is why this is an authored row rather than a value.
##
## It lives in `modules/`, not `contracts/`: it is an authored content type an
## author fills in as a `.tres`, and every other authored `Resource` in this repo
## sits in the module that owns it or in `core/`.
##
## **A position is a duty, not a level** (ADR 0083). `powers` is the authority the
## holder is granted — "may this member levy a levy" is a `.tres` question and
## never `if rank >= 3`. Authority grants recognition and access, and no power at
## all: it decides who may act, never what they are worth.

## The authored methods a seat may be filled by. `contest` is declared but is
## deliberately not shipped in content: an authored-but-unreachable succession is
## the dead content ADR 0063 shipped as unreachable realms (ADR 0085).
const HEIR := &"heir"
const TRIAL := &"trial"
const CONTEST := &"contest"
const APPOINTED := &"appointed"
const SUCCESSION_METHODS: Array[StringName] = [HEIR, TRIAL, CONTEST, APPOINTED]

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## Authored verbs the holder of this seat may exercise. Data, never a number.
@export var powers: Array[StringName] = []
## How many members may hold it at once. `1` is the ordinary seat and the reason
## `seat_occupied` is a distinct refusal from `capacity_full` (ADR 0084).
@export var capacity: int = 1
@export var succession_method: StringName = APPOINTED
## Whatever the method needs: a `term_id` for `heir`, an `office_id` for
## `appointed`, nothing for `trial`. Ids and counts, never authored amounts.
@export var succession_param: Dictionary = {}
## The stats this seat RECOGNISES. Each id must have a non-zero baseline in its
## derivation or a `PERCENT` on it is ADR 0068's silent no-op; the projection
## writes nothing outside this list.
@export var standing_percent_stats: Dictionary = {}


## Whether the seat is authored to hold anyone at all. A `capacity` of zero is a
## mis-authored seat, and answering "yes, fillable" to it would make every fill
## attempt fail on the cap instead of on a named reason.
func has_seats() -> bool:
	return capacity > 0


## Whether `actor_id` may hold this seat at all. **Recognition, not power** (ADR
## 0084): the answer is about who may sit, never about what sitting is worth.
func admits(actor_id: String) -> bool:
	return actor_id != "" and has_seats()


## The stat ids this seat recognises, canonically ordered. The projection reads
## this allowlist and nothing else, which is what makes the political stat surface
## authored rather than global.
func percent_stats() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in standing_percent_stats.keys():
		out.append(StringName(String(key)))
	out.sort()
	return out
