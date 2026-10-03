class_name SocialBond
extends RefCounted

## One relationship's axes, and the cause ledger that moved them (ADR 0076).
##
## **Two axes and a floor.** `standing` is how much they regard you; `trust` is whether
## they will rely on you. They are distinct because a famous liar has high standing and
## no trust, and because trust is what gates teaching while standing is what gates price.
##
## **`respect` is deliberately not an axis.** A nemesis you admire is expressed by
## `standing` being negative while the class ladder still reads the respect recorded on
## the cause ledger; adding a fourth number would make every axis a tuning knob and every
## consumer ambiguous about which one it wanted.
##
## Each axis carries a floor: the persistent part that decay never eats. An honoured debt
## raises the floor, so time moves a bond toward the promise it was given rather than
## toward a stranger.

var partner_id: StringName = &""
var standing: float = 0.0
var trust: float = 0.0
var standing_floor: float = 0.0
var trust_floor: float = 0.0

## Every cause that has ever moved this bond, as `{cause_id: times}`. The ledger is the
## audit trail: it is why a class can require *distinct* causes, and it is what makes
## "why are we enemies" answerable after a save/load round trip.
var causes: Dictionary = {}

## The last cause applied, for display and for `SocialEntry` summaries.
var last_cause: StringName = &""

## Accumulated seconds of decay applied, so decay is driven by the same tick that drives
## `Actor.tick_statuses` rather than by wall-clock time the tests cannot control.
var age: float = 0.0


func _init(p_partner_id: StringName = &"") -> void:
	partner_id = p_partner_id


## The derived class. Never stored, so it cannot disagree with the axes (ADR 0076).
func bond_class() -> StringName:
	return SocialBondClass.classify(standing, trust, distinct_causes())


func distinct_causes() -> int:
	return causes.size()


## Record that `cause_def` moved this bond. `scale` lets a caller attenuate a cause
## without authoring a second id, which is what keeps a partial win from reading as a
## total one.
##
## The floor rises only for a persistent cause, and only when the axis moves past it.
## A cause can therefore never lower a promise it previously granted, and a decay toward
## the floor is always a move toward truth rather than toward amnesia.
func apply(cause_def: SocialCauseDef, scale: float = 1.0) -> void:
	if cause_def == null:
		return
	var scaled_standing := cause_def.standing * scale
	var scaled_trust := cause_def.trust * scale
	standing = clampf(standing + scaled_standing, -100.0, 100.0)
	trust = clampf(trust + scaled_trust, 0.0, 1.0)
	if cause_def.persistent:
		standing_floor = maxf(standing_floor, standing)
		trust_floor = maxf(trust_floor, trust)
	causes[String(cause_def.id)] = int(causes.get(String(cause_def.id), 0)) + 1
	last_cause = cause_def.id


## Move the transient part of each axis toward its floor. Linear, framerate-independent,
## and clamped at the floor so it cannot pass it and then oscillate around it.
func decay(delta: float) -> void:
	if delta <= 0.0:
		return
	age += delta
	# Calibrated to the authored cause magnitudes, not to the clamp bounds: the shipped
	# causes move standing by 1..12 per act, so a friendship worth ~8 should take a
	# season of silence to fade rather than a decade, and a grudge should not outlive
	# the player by centuries. `move_toward` clamps at the floor, so no amount of time
	# can drive an axis past the promise it was given.
	const DRIFT_PER_SECOND := 1.0 / (30.0 * 24.0 * 60.0 * 60.0)
	standing = move_toward(standing, standing_floor, DRIFT_PER_SECOND * delta)
	trust = move_toward(trust, trust_floor, DRIFT_PER_SECOND * delta * 30.0)


func to_dict() -> Dictionary:
	return {
		"partner_id": String(partner_id),
		"standing": standing,
		"trust": trust,
		"standing_floor": standing_floor,
		"trust_floor": trust_floor,
		"causes": causes.duplicate(),
		"last_cause": String(last_cause),
		"age": age,
	}


static func from_dict(data: Dictionary) -> SocialBond:
	var bond := SocialBond.new(StringName(data.get("partner_id", "")))
	bond.standing = float(data.get("standing", 0.0))
	bond.trust = float(data.get("trust", 0.0))
	bond.standing_floor = float(data.get("standing_floor", 0.0))
	bond.trust_floor = float(data.get("trust_floor", 0.0))
	bond.last_cause = StringName(data.get("last_cause", ""))
	bond.age = float(data.get("age", 0.0))
	for key in data.get("causes", {}).keys():
		bond.causes[String(key)] = int(data["causes"][key])
	return bond
