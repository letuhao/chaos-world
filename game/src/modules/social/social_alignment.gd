class_name SocialAlignment
extends RefCounted

## One actor's alignment: three axis totals and the repeat ledger behind them
## (ADR 0253). Pure data plus the one accumulation rule — **no npc argument exists on
## any function here**, which is the owner's constraint expressed as a signature rather
## than a promise.
##
## **It is not persisted in its own slot.** It rides `actor.module_data[MODULE_KEY]`
## beside the bond ledger, so `Actor.to_dict` alone is a complete save and `core` never
## names a social type (ADR 0027). A save written before alignment existed has no
## `alignment` key and restores with every axis at zero — which is *neutral*, so an old
## save is not retroactively moralised by a band it never earned.
##
## **It is derived, never stored as an opinion.** There is no "alignment class" and no
## NPC-held alignment: the axes are the whole truth, and `band_for` is a pure function
## of DOMINION.

## The `module_data` sub-key this rides under, inside `SocialState`'s payload. Keyed by
## NAME so it cannot collide with the bond table it sits beside.
const MODULE_KEY := &"alignment"

## How many distinct causes this actor's repeat ledger may hold. Bounds the ledger
## itself: an actor who has met 40 000 distinct authored causes cannot make this
## dictionary grow forever. The shipped catalog judges 29, so this is generous and the
## bound is real.
const SEEN_LIMIT := SocialAlignmentMatrix.SEEN_LEDGER_LIMIT

## The three authored axis totals. Always whole or half numbers; never negative-clamped
## away — a player may legitimately sit at MERCY −40 and that is the design.
var axes: Dictionary = {}

## cause id → how many times it has already moved this actor. Feeds the taper in
## `SocialAlignmentMatrix.contribution`. Bounded by `SEEN_LIMIT`.
var seen: Dictionary = {}


func _init() -> void:
	for axis in SocialAlignmentMatrix.AXES:
		axes[String(axis)] = 0.0


## The value of one axis. `0.0` for an axis this build does not have, so a consumer
## never has to test `has` before reading.
func axis(axis_id: StringName) -> float:
	return float(axes.get(String(axis_id), 0.0))


## Which band these axes read in. Delegates to the matrix so the threshold exists once.
func band() -> StringName:
	return SocialAlignmentMatrix.band_for(axis(SocialAlignmentMatrix.DOMINION))


## Whether this actor has ever been judged by this act. `false` is a legitimate answer
## (the market tier), so this is a question and not a failure.
func judges(cause_id: StringName) -> bool:
	return seen.has(String(cause_id))


## ## The accumulation rule, in one sentence
##
## **An authored cause moves each axis by its authored weight scaled by
## `REPEAT_TAPER^times_this_actor_has_already_been_judged_by_it`.**
##
## That is `SocialAlignmentMatrix.contribution`, and nothing in this file re-implements
## it — one rule, one place (ADR 0066). The `seen` counter advances only for a cause
## the matrix actually judges, so an act with no moral reading cannot push a taper into
## a later one.
static func record(
	alignment: SocialAlignment, cause_id: StringName, scale: float = 1.0
) -> Dictionary:
	if alignment == null or not SocialAlignmentMatrix.judges(cause_id):
		return alignment.snapshot() if alignment != null else {}
	var repeats := int(alignment.seen.get(String(cause_id), 0))
	var moved := SocialAlignmentMatrix.contribution(cause_id, repeats, scale)
	for axis_id in SocialAlignmentMatrix.AXES:
		var key := String(axis_id)
		alignment.axes[key] = clampf(
			alignment.axis(axis_id) + float(moved.get(key, 0.0)),
			-SocialAlignmentMatrix.AXIS_CAP,
			SocialAlignmentMatrix.AXIS_CAP
		)
	# Counted AFTER the move, and only when there is room. A full ledger drops the
	# increment, which means a cause past the bound never taps out — the safer error of
	# the two, since losing the counter can only under-count a repeat, never invent a
	# fresh one.
	if alignment.seen.size() < SEEN_LIMIT or alignment.seen.has(String(cause_id)):
		alignment.seen[String(cause_id)] = repeats + 1
	return alignment.snapshot()


## A primitive read model for a panel or a gate. `{}` for no actor, so a consumer tests
## the contract rather than pixels — the shape `SocialApi.summary` already returns.
func snapshot() -> Dictionary:
	if axes.is_empty():
		return {}
	var out := {
		"band": String(band()),
		"seen_count": seen.size(),
		"corrupt": band() == SocialAlignmentMatrix.CORRUPT,
	}
	for axis_id in SocialAlignmentMatrix.AXES:
		out[String(axis_id)] = axis(axis_id)
	return out


func to_dict() -> Dictionary:
	var out := {}
	for key in axes.keys():
		out[key] = float(axes[key])
	return {
		MODULE_KEY:
		{
			"axes": out,
			"seen": seen.duplicate(),
		}
	}


## Restoring is total. A payload with no `seen` (an old save, or a hand-authored
## fixture) restores with an empty ledger, which makes every act count as a FIRST act —
## the generous direction. That is deliberate: an actor whose history was never tracked
## has not been proven to have repeated anything, and an empty ledger cannot fabricate
## a reputation it did not earn.
static func from_dict(payload: Variant) -> SocialAlignment:
	var alignment := SocialAlignment.new()
	if not (payload is Dictionary):
		return alignment
	var data: Dictionary = payload
	# Hoisted: a comprehension may not sit inside `in` in GDScript, so the list is
	# built once above the loop rather than re-evaluated per axis.
	var known_axes: Array[String] = []
	for axis in SocialAlignmentMatrix.AXES:
		known_axes.append(String(axis))
	for key in data.get("axes", {}).keys():
		var axis_id := String(key)
		if known_axes.has(axis_id):
			alignment.axes[axis_id] = clampf(
				float(data["axes"][key]),
				-SocialAlignmentMatrix.AXIS_CAP,
				SocialAlignmentMatrix.AXIS_CAP
			)
	for key in data.get("seen", {}).keys():
		# Bounded here rather than trusting the payload: a save is data, and an
		# unbounded ledger restored from one is the memory shape INC-0004/0005 punish.
		if alignment.seen.size() >= SEEN_LIMIT:
			break
		alignment.seen[String(key)] = maxi(0, int(data["seen"][key]))
	return alignment
