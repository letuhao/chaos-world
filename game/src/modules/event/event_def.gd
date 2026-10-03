class_name EventDef
extends Resource

## One authored world event (BL-0054, ADR 0114). Six hundred years of sect wars,
## beast tides, auctions, disasters and invasions are all this shape: a name, a
## place, a trigger, a ladder of stages and a prize.
##
## ## The trigger is DATA in one shared requirement language
##
## `trigger` is a `DestinyGate` / `SocialGate` requirement verbatim —
## `{verb, id, need}` or `{verb: all_of | any_of | none_of, of: [...]}`. This module
## reads the world through the fact ledger, so it adds exactly ONE verb to that
## vocabulary (`{verb: "fact", id: <fact_id>, need: n}`) and reuses the composite
## verbs untouched. A second requirement language would have been ADR 0066's
## "fourth stat composer" wearing a different hat.
##
## ## `kind` names the shape; it never changes the arithmetic
##
## `sect_war` is the one kind that delegates: its resolution is a verdict from
## outside, and the prize is counted and paid by `NationApi.resolve_conflict`
## (ADR 0085). Every other kind resolves here. What `kind` decides is which
## resolution verb applies, nothing about how a number is produced.
##
## ## `pay` is paid EXACTLY ONCE, at resolution
##
## Rows are `{kind, id, amount}` with `kind` one of `PAY_FATE`, `PAY_DESTINY`,
## `PAY_NATION_STANDING` or `PAY_NOTHING`. `PAY_FATE` grants through
## `DestinyApi.earn_fate` with the exact source string `"event:" + id` (DEF-0108).

## A sect war: the conflict is a DECLARATION and its quota is `nation`'s, not
## this module's.
const KIND_SECT_WAR := &"sect_war"
const KIND_TOURNAMENT := &"tournament"
const KIND_BEAST_TIDE := &"beast_tide"
const KIND_AUCTION := &"auction"
const KIND_DISASTER := &"disaster"
const KIND_DEMONIC_INVASION := &"demonic_invasion"
const KIND_RARE_TREASURE := &"rare_treasure"
const KINDS: Array[StringName] = [
	KIND_SECT_WAR,
	KIND_TOURNAMENT,
	KIND_BEAST_TIDE,
	KIND_AUCTION,
	KIND_DISASTER,
	KIND_DEMONIC_INVASION,
	KIND_RARE_TREASURE,
]

## The closed pay vocabulary. `nothing` is authored explicitly so a prize with no
## number in it is a declared absence rather than a missing key.
const PAY_FATE := &"fate"
const PAY_DESTINY := &"destiny"
const PAY_NATION_STANDING := &"nation_standing"
const PAY_NOTHING := &"nothing"
const PAY_KINDS: Array[StringName] = [PAY_FATE, PAY_DESTINY, PAY_NATION_STANDING, PAY_NOTHING]

## The prefix of the source string a fate grant carries (DEF-0108). The exact
## string is `"event:" + <event id>`, so an audit can name the system that earned
## the fate without this module being consulted.
const FATE_SOURCE_PREFIX := "event:"

## A hard cap on `stages`. An event that never ends would otherwise sit in the
## ledger forever, and a `.tres` with four thousand sub-resources is a content bug
## nobody could see.
const MAX_STAGES := 8

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var kind: StringName = &""
## A requirement in the gate vocabulary. Empty means ungated — every actor may open
## it, which is the honest shape for a disaster nobody schedules.
@export var trigger: Dictionary = {}
## Where this event can occur, as a `WorldLocationDef.location_id` (ADR 0113).
## Empty means it is not tied to a place.
@export var location_id: StringName = &""
## The `on_enter` beats of the FIRST stage, folded in here so an author who wants a
## one-stage event (an auction, a treasure) does not have to author a ladder.
@export var on_enter: Array[Dictionary] = []
@export var stages: Array[EventStageDef] = []
## The prize, paid once when the event resolves. `{kind, id, amount}` per row.
@export var pay: Array[Dictionary] = []


## The stage count as authored, so a screen and a test read one number.
func stage_count() -> int:
	return stages.size()


## The first stage id, or `&""` for an event that authors no stage.
func first_stage_id() -> StringName:
	if stages.is_empty():
		return &""
	return stages[0].stage_id


## The stage at `index`, or null when the ladder does not reach it.
func stage_at(index: int) -> EventStageDef:
	if index < 0 or index >= stages.size():
		return null
	return stages[index]


## The stage carrying `stage_id`, or null.
func stage_named(stage_id: StringName) -> EventStageDef:
	for stage in stages:
		if stage.stage_id == stage_id:
			return stage
	return null


## The index of `stage_id`, or -1. `-1` rather than 0: an unknown stage is not the
## first stage, and folding the two together would silently rewind an event.
func stage_index_of(stage_id: StringName) -> int:
	for index in stages.size():
		if stages[index].stage_id == stage_id:
			return index
	return -1


## The stage after `stage_id`, or null when that was the last one — and `&""` when
## `stage_id` names no stage at all, because walking off the end of an unknown
## stage would hand the caller the first stage and rewind the event.
func next_stage_id(stage_id: StringName) -> StringName:
	var index := stage_index_of(stage_id)
	if index < 0:
		return &""
	var following := stage_at(index + 1)
	return &"" if following == null else following.stage_id


## The beats that fire when the event opens: the def's own `on_enter`, and — when
## there is a first stage — that stage's `on_enter` as well. Both are authored in
## the same shape, so a one-stage event needs only the def.
func opening_beats() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for beat in on_enter:
		out.append(beat.duplicate())
	var first := stage_at(0)
	if first != null:
		for beat in first.on_enter:
			out.append(beat.duplicate())
	return out


## The fate source string this event's grants carry, verbatim from DEF-0108.
func fate_source() -> String:
	return FATE_SOURCE_PREFIX + String(id)


## Every defect that must stop this def from reaching play, as one line each.
##
## Deliberately narrow: it checks SHAPE (ids, stage ids, the closed pay set, the
## ladder's length) and never whether a trigger is satisfied — that is the ledger's
## question at run time, not an authoring error. A content tree with an empty
## `problems()` list is the audited state.
func problems() -> Array[String]:
	var out: Array[String] = []
	if id == &"":
		out.append("event has no id")
	if display_name == "":
		out.append("%s has no display_name" % String(id))
	if not KINDS.has(kind):
		out.append("%s names kind '%s', which is not one this module reads" % [String(id), kind])
	if stages.size() > MAX_STAGES:
		out.append(
			(
				"%s authors %d stages; a ladder is bounded at %d"
				% [String(id), stages.size(), MAX_STAGES]
			)
		)
	var seen := {}
	for stage in stages:
		if stage == null:
			out.append("%s has an empty stage slot" % String(id))
			continue
		if stage.stage_id == &"":
			out.append("%s has a stage with no stage_id" % String(id))
			continue
		if seen.has(String(stage.stage_id)):
			out.append("%s authors stage '%s' twice" % [String(id), String(stage.stage_id)])
		seen[String(stage.stage_id)] = true
		if stage.duration_periods < 0:
			out.append(
				(
					(
						"%s stage '%s' holds for %d periods; a stage cannot hold for fewer "
						% [String(id), String(stage.stage_id), stage.duration_periods]
					)
					+ "than zero periods"
				)
			)
	for row in pay:
		var kind_text := StringName(row.get("kind", ""))
		if not PAY_KINDS.has(kind_text):
			out.append(
				(
					"%s pays kind '%s', which is not one of the four this module reads"
					% [String(id), String(kind_text)]
				)
			)
	for beat in opening_beats():
		if String(beat.get("fact", "")) == "":
			out.append("%s has an opening beat that names no fact" % String(id))
	return out
