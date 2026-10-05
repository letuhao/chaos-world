class_name SectPositionDef
extends Resource

## One authored office inside a sect: **a duty, not a level** (ADR 0083).
##
## A position is what an institution gives a member in exchange for standing, and
## it carries three things an author writes down: what the holder MUST do
## (`duties`), what the holder MAY do (`authorities`), and how the seat changes
## hands (`succession_method` + `succession_param`).
##
## ## Authority is data, never a number
##
## "May this member expel another" is a `.tres` question, not `if rank >= 3`.
## The numeric hierarchy ADR 0064 kept out of the clan claim would come straight
## back in through the back door the moment a position became an index, so
## `authorities` is an `Array[StringName]` of authored verbs and this module
## never compares two positions against each other.
##
## ## `capacity` is authored, and 1 is a different word from 2
##
## A seat with capacity 1 is a **seat** and it is `occupied`. A seat with a cap
## above 1 that is also full is **full**. ADR 0084 makes that distinction
## load-bearing: they are different player-facing situations and a single
## `capacity_full` reason would collapse a succession contest into a closed door.
##
## ## `standing_percent_stats` is the only stat surface a position has
##
## The allowlist a position recognises — stat ids on which the member's standing
## projects as a bounded PERCENT (ADR 0084). Authored per position, not global,
## so an author chooses which stats this office is recognised *for*.
##
## Adding a position is authoring a `.tres` under `res://data/sect/`, never code.

## ## `succession_method` is the AUTHORED shape of the walk, not its outcome
##
## A succession is **walked, never rolled** (ADR 0084, taking ADR 0058's ascension
## shape): it advances one authored stage per call, refuses a further step until a
## period elapses, and consults no `rng` at all. So the outcome is a function of the
## ledger and a test needs no seeded generator. Three walks, and every other
## method value refuses `walk_complete` by naming itself:
##
##   - `heir`      — three stages: propose, accept, hold. The holder's own heir is
##                   taken by name, because a name is an authored fact rather than a
##                   score.
##   - `trial`     — three stages: hold the trial, answer for it, hold the seat. Each
##                   stage must be completed by a period rather than in a second, so
##                   the walk cannot be stumbled through.
##   - `appointed` — two stages: propose, seat. The route where the house simply
##                   names somebody and the naming is the whole of it.
##
## **`contest` is deliberately ABSENT.** Nothing can call it until a tournament
## exists, and an authored-but-unreachable method is dead content: it would ship as
## a word in every `.tres` an author reads and as a branch with no production
## caller. `WorldAnchor.ascend` is the precedent — an entry point with no caller yet
## is recorded, not dressed up as content. When a tournament lands it gets its own
## stage chain and its own ADR, on top of `SectApi.advance_succession`.
##
## `seniority`, `named` and `inherited` remain in the set as **spelled refusal
## reasons**: content on disk names them today and an `is_walkable_method` check
## that silently accepted anything would turn an old `.tres` into an instantly
## completed walk. They read as what they are, and a test pins the list.
const SUCCESSION_HEIR := &"heir"
const SUCCESSION_TRIAL := &"trial"
const SUCCESSION_APPOINTED := &"appointed"
const SUCCESSION_SENIORITY := &"seniority"
const SUCCESSION_NAMED := &"named"
const SUCCESSION_INHERITED := &"inherited"

## The walks this module can actually take, and the number of stages each takes.
## Bounded on purpose: a walk is four steps at most, so it can never be a loop.
const SUCCESSION_STAGES := {
	SUCCESSION_HEIR: 3,
	SUCCESSION_TRIAL: 3,
	SUCCESSION_APPOINTED: 2,
}

## An office no member holds. The seat **exists** and its value is absent
## (ADR 0083): a row visible, `is_filled()` true, never `0` and never hidden.
const NO_POSITION := &""

@export var id: StringName = NO_POSITION
@export var display_name: String = ""
## Clinical and mechanical, in the game's own voice: this is an office and the
## work it obliges (AGENTS.md).
@export var description: String = ""

## Standing this office needs before `promote` will grant it. **It is a route, not
## a wall**: a promotion on thin standing stays expressible because ADR 0064's
## two-part split exists for exactly that gap, so the refusal names
## `standing_below_floor` and the caller decides what to do about it.
@export var standing_floor: int = 0

## How many members may hold this office at once. 0 means unbounded; 1 means one
## seat, and anything above 1 is a room that can fill and then be `capacity_full`.
@export var capacity: int = 1

## What the holder must do, as authored verb ids. Counted, never executed: this
## module owns no verbs, so `duty_per_period` opens obligation lines in the claim
## and whoever spends them is another module's answer.
@export var duties: Array[StringName] = []
## What the holder may do, as authored verb ids. The whole of "authority" in this
## repo — there is no rank comparison anywhere in this module.
@export var authorities: Array[StringName] = []

## How this seat changes hands. One of the walkable `SUCCESSION_*` values above
## when the sect walks it, and one of the older authored values otherwise — which
## `is_walkable_method` refuses by name rather than guessing at.
@export var succession_method: StringName = SUCCESSION_APPOINTED
## The parameter `succession_method` reads. Named rather than a bare int so a walk
## can be authored as `{"order": "most_standing"}` and a later reader does not have
## to guess which number meant what. **Never consulted for its magnitude** — a
## succession is walked, never rolled (ADR 0084).
@export var succession_param: Dictionary = {}

## Periods a seat spends VACANT before the next walk may begin. The one clock a
## succession may have, and it is a count of periods handed in by a caller that owns
## time rather than a read of `Time` — nothing in this module owns a clock
## (DEF-0111, ADR 0083). `1` is the ordinary figure: an empty seat that refills in the
## same instant is not a succession anybody could observe.
@export var succession_periods: int = 1

## What one session of teaching costs the HOLDER of this office, on top of the
## doctrine's own `teach_tax`. A real cost is the whole of BL-0188: teaching that is
## free and unlimited makes disciples a resource faucet. Zero means the office does
## not teach by standing alone, which is a choice an author makes rather than a
## default the code infers.
@export var teach_tax: float = 0.0

## The stat ids this office recognises. `standing_percent(standing)` is applied
## to each as a `Stat.Op.PERCENT` modifier tagged `sect:<sect_id>` and to nothing
## else, so the entire political stat surface of the game is one capped percent.
@export var standing_percent_stats: Dictionary = {}

## Periods of `patronage_<office>` this office opens against its holder each
## period, and of `duty_<office>` against its holder's door. Ids and counts, so
## retuning a rate never rewrites a save (ADR 0064's obligation vocabulary).
@export var patronage_per_period: int = 0
@export var duty_per_period: int = 0


## The stat source id this office contributes under. Namespaced through the sect
## it belongs to, because the modifier stack is keyed by source and the strip
## half of `SectProjection` has to be able to find it again.
func source_id(sect_id: StringName) -> StringName:
	return SectState.source_for(sect_id)


## Whether `authority_id` is one this office may exercise. An authored lookup,
## never a comparison between offices.
func grants(authority_id: StringName) -> bool:
	return authority_id != &"" and authorities.has(authority_id)


## Whether this office recognises `stat_id`, i.e. whether its standing may
## project onto it. A stat that is not on this list can never be touched by a
## sect, however high the member's standing climbs.
##
## The keys are compared **as strings, whatever type they were authored with.**
## A `.tres` stores plain String keys, but a def built in GDScript or in a test
## fixture authors `Stat.INSIGHT_GAIN`, which is a `StringName` — and
## `Dictionary.has()` is key-type strict, so `has(String(x))` against a
## `StringName`-keyed dict silently matches nothing. That failure is invisible
## from the outside: the projection grants nothing, every derived stat stays put,
## and the suite reads as "the institution correctly touched nothing" rather than
## as an allowlist that was never consulted. Comparing as text is what makes the
## authored shape and the saved shape agree.
func recognises(stat_id: StringName) -> bool:
	if stat_id == &"":
		return false
	for key in standing_percent_stats.keys():
		if String(key) == String(stat_id):
			return true
	return false


## The number of holders this office allows. `0` is unbounded, so a seat nobody
## authored a cap for is not a wall — it is a room with no walls.
func room() -> int:
	return maxi(0, capacity)


## Whether this office's succession can be WALKED at all.
##
## The check is membership of `SUCCESSION_STAGES` rather than a
## "not empty and not one of the refusals" test, so a method nobody authored cannot
## become an instantly-completed walk by omission. `contest` is deliberately not in
## the table; see the note above.
func is_walkable_method() -> bool:
	return SUCCESSION_STAGES.has(succession_method)


## How many stages a full walk of this office's method takes, or `0` when the
## method is not one this module walks. The `0` matters: it is what makes the
## refusal read as "this method has no walk" rather than as a walk of no length.
##
## ## Derived from `stages()`, not from the table beside it
##
## `SUCCESSION_STAGES` is the authored content — "heir is three stages long" — and
## `stages()` is the list that walk is made of. The two are counted from ONE place:
## `walk_length()` is `stages().size()`. Reading the table twice let them drift, and
## a published stage count that disagreed with the authored walk length is a lie in
## the read model: `summary()` renders `stages` beside `walked`, so a panel would
## draw "2 of 3 stages" for a three-stage walk. The table remains the source of the
## walk LENGTH; `stages()` is what names them, and it names exactly that many.
func walk_length() -> int:
	return stages().size()


## The stages that complete a walk of this office's method, in order. Never a
## `while`: the walk is a `for` over an authored list of at most three names, and
## `stages_walked` is a count a caller clamps against `walk_length` — so no
## `SectState` key can talk this module into a walk of fifty thousand steps.
##
## The count is read straight off `SUCCESSION_STAGES`, the authored content, and
## `walk_length()` is counted back off THIS list — so the number of stage names and
## the number the module clamps against are the same number by construction, and a
## walkable method always publishes exactly as many stages as its authored length.
func stages() -> Array[StringName]:
	if not is_walkable_method():
		return []
	var out: Array[StringName] = []
	for index in int(SUCCESSION_STAGES.get(succession_method, 0)):
		out.append(StringName("%s_%d" % [String(succession_method), index + 1]))
	return out


## Whether this office may be reached by succession at all, or must be filled by a
## plain promotion. True exactly when its method names a walk — which is what
## `top_position` asks, and what stops founding from seating a founder in an office
## whose culture only ever appoints.
func succeeds_by_walk() -> bool:
	return is_walkable_method()


## Whether `held` members may still be admitted, given this office's cap.
## Unbounded always answers true.
func has_room(held: int) -> bool:
	return capacity <= 0 or held < capacity


## The obligation line ids this office opens, keyed by period count. Ids, never
## authored amounts: `patronage` is what the institution gives and `duty` is what
## it takes, and both are settled in periods by `InstitutionClaim`.
func obligation_lines() -> Dictionary:
	var out := {}
	if patronage_per_period > 0:
		out["patronage_%s" % String(id)] = patronage_per_period
	if duty_per_period > 0:
		out["duty_%s" % String(id)] = duty_per_period
	return out
