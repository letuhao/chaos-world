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

## The distinct KINDS of act this bond has seen (`SocialCauseDef.kind`), as a set.
##
## This is the set the anti-farm rule reads, not `causes`. Two gifts are two causes and
## one kind; a gift and a battle are two kinds, and only the second earns a friendship.
## Sticky, like `causes`, so a save/load round trip cannot lose the history that put a
## bond where it is.
var kinds: Dictionary = {}

## The last cause applied, for display and for `SocialEntry` summaries.
var last_cause: StringName = &""

## ## The rung a qualifying cause has PROMISED this bond (`BL-0659`)
##
## `shared_brotherhood` is authored `promotes_to: SWORN`, and until ADR 0091's ladder had a
## reader for that field nothing could produce the deepest rung: `SWORN` sat in `POSITIVE`
## and in `label`, and no code path anywhere in `game/src` could return it. This is where
## the promise is kept.
##
## **Sticky, and a CEILING rather than an outcome — which is the whole safety argument.**
## A friendship earned by two gifts must not become an oath by a third gift, so recording
## the promise is not enough: `bond_class` hands it to `SocialBondClass.classify`, which
## returns it only when the AXES have already earned `PROMOTION_MIN_CLASS`. The cause
## names where the ladder may end; the axes decide whether it gets there.
##
## **It is stored, not re-derived, for the same reason `institutional` is.** The
## classification has to answer identically before and after a save/reload, and
## `shared_brotherhood` is an authored id a later build may have edited or a test may have
## replaced from the catalog — so whether this bond was sworn is a fact on the ledger, not
## a lookup that can change underneath a loaded game.
var promoted_to: StringName = &""

## Whether an INSTITUTION is the partner on this row rather than a person. **Stored,
## not re-derived.** `SocialState.regard` projects from exactly these rows, and the
## projection has to answer identically before and after a save/reload — so whether
## the partner was a sect rather than an npc is a fact on the ledger rather than a
## lookup into a catalog a later build may have edited or a test may have replaced.
var institutional: bool = false

## Accumulated seconds of decay applied, so decay is driven by the same tick that drives
## `Actor.tick_statuses` rather than by wall-clock time the tests cannot control.
var age: float = 0.0


func _init(p_partner_id: StringName = &"") -> void:
	partner_id = p_partner_id


## The derived class. Never stored, so it cannot disagree with the axes (ADR 0076).
##
## `promoted_to` is passed last and is a CEILING, not an outcome — the ladder decides
## whether a bond that has been sworn actually got far enough to be one.
func bond_class() -> StringName:
	return SocialBondClass.classify(standing, trust, distinct_kinds(), promoted_to)


## How many DIFFERENT KINDS of act this bond has seen — the number the anti-farm rule
## reads. Deliberately not `causes.size()`: two gift-tier causes are two causes and one
## kind, so counting causes let a shopkeeper be farmed into friendship.
func distinct_kinds() -> int:
	return kinds.size()


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
	# Sticky, never cleared: an institution stays an institution however many ordinary
	# causes land on the row afterwards. Clearing it would drop a sect out of `regard`
	# because a stranger was greeted on the same bond.
	if cause_def.institutional:
		institutional = true
	causes[String(cause_def.id)] = int(causes.get(String(cause_def.id), 0)) + 1
	# The kind ledger is what the anti-farm rule counts. A cause with no authored kind
	# falls back to its own id, so an un-authored cause still counts as ONE distinct kind
	# rather than silently joining every other un-authored cause in the same bucket.
	var kind := cause_def.kind if cause_def.kind != &"" else cause_def.id
	kinds[String(kind)] = true
	last_cause = cause_def.id
	# Record the promise, not the outcome. `promotes_to` names the top the ladder MAY reach
	# once the axes have earned `PROMOTION_MIN_CLASS`; taking it here would make the act
	# that promises the oath also grant it. Sticky, like every other ledger entry — the
	# last rung is not something a later betrayal or a dull month takes back on its own.
	if cause_def.promotes_to != &"":
		promoted_to = cause_def.promotes_to


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
		"kinds": kinds.duplicate(),
		"last_cause": String(last_cause),
		"promoted_to": String(promoted_to),
		"institutional": institutional,
		"age": age,
	}


static func from_dict(data: Dictionary) -> SocialBond:
	var bond := SocialBond.new(StringName(data.get("partner_id", "")))
	bond.standing = float(data.get("standing", 0.0))
	bond.trust = float(data.get("trust", 0.0))
	bond.standing_floor = float(data.get("standing_floor", 0.0))
	bond.trust_floor = float(data.get("trust_floor", 0.0))
	bond.last_cause = StringName(data.get("last_cause", ""))
	# A save written before BL-0659 has no `promoted_to`, and it restores as `&""` — no
	# promotion was ever promised on it. That is the safe direction: the field is a CEILING,
	# so a missing ceiling can only hold a bond at the class its axes earned, never lift it.
	bond.promoted_to = StringName(data.get("promoted_to", ""))
	bond.institutional = bool(data.get("institutional", false))
	bond.age = float(data.get("age", 0.0))
	for key in data.get("causes", {}).keys():
		bond.causes[String(key)] = int(data["causes"][key])
	# Restore the kind set. A save written before this field existed has no `kinds`, so
	# fall back to one kind per distinct cause: that is exactly what the rule counted
	# before kinds existed, and an old save therefore lands on the same class it always
	# did rather than dropping to acquaintance.
	if data.has("kinds"):
		for key in data["kinds"].keys():
			bond.kinds[String(key)] = true
	else:
		for key in bond.causes.keys():
			bond.kinds[String(key)] = true
	return bond
