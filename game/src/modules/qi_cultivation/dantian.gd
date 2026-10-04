class_name Dantian
extends RefCounted

## Qi storage vessel (ADR 0014). Owns quality and recoverable injury, plus the
## structural capacity a realm's seed sizes it to. Current/capacity live in the
## actor's `qi` ResourcePool (single reservoir) — this component reads and mutates
## that pool directly.
##
## There is deliberately NO tier, and no `LOWER`/`MIDDLE`/`UPPER`: the three-band
## ladder was authored on all 30 seeds, written by `synchronize` from the STANDING
## realm, published on `panel_state` and rendered as a row name — while nothing ever
## read it. Two measurements closed it. First, the bands are a restatement of the
## ladder's own tiers (9 Mortal / 9 Spirit / 12 above), so `dantian_tier` carried no
## information the realm line did not already print. Second, and decisively, the
## ladder is NOT monotone across the band edges: `tribulation(lower) ->
## spirit_condensation(middle)` and `spirit_ascension(middle) -> earth_immortal
## (upper)` are two boundaries where a tier floor could never be met, because the
## only writer is `synchronize` reading the realm the actor is standing in — so
## gating on it would have walled off exactly the two band crossings and left the
## other 27 free (ADR 0165).

signal changed

var quality: float = 0.5
var injured: bool = false
## Structural capacity from training/profile (not equipment-inflated).
var structural_capacity: float = 100.0


func effective_capacity() -> float:
	return structural_capacity * 0.75 if injured else structural_capacity


## Current qi from the shared reservoir pool.
func current(actor: Actor) -> float:
	var pool := actor.resource(QiStats.QI)
	return pool.current if pool != null else 0.0


## Maximum qi from the shared reservoir pool.
func maximum(actor: Actor) -> float:
	var pool := actor.resource(QiStats.QI)
	return pool.maximum if pool != null else 0.0


## Stored qi as a 0..1 fraction of usable capacity.
func ratio(actor: Actor) -> float:
	var usable := effective_capacity()
	return 0.0 if usable <= 0.0 else clampf(current(actor) / usable, 0.0, 1.0)


func is_full(actor: Actor) -> bool:
	return current(actor) >= effective_capacity()


func fill(actor: Actor, amount: float) -> void:
	var pool := actor.resource(QiStats.QI)
	if pool != null:
		pool.change(amount)
		_emit_changed()


func drain(actor: Actor, amount: float) -> void:
	var pool := actor.resource(QiStats.QI)
	if pool != null:
		pool.change(-amount)
		_emit_changed()


func damage(actor: Actor = null) -> void:
	injured = true
	if actor != null:
		var pool := actor.resource(QiStats.QI)
		if pool != null:
			pool.current = clampf(pool.current, 0.0, effective_capacity())
	_emit_changed()


func heal() -> void:
	injured = false
	_emit_changed()


func set_quality(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if quality != clamped:
		quality = clamped
		_emit_changed()


func set_structural_capacity(value: float) -> void:
	if structural_capacity != value:
		structural_capacity = maxf(0.0, value)
		_emit_changed()


func _emit_changed() -> void:
	changed.emit()


func to_dict() -> Dictionary:
	return {
		"quality": quality,
		"injured": injured,
		"structural_capacity": structural_capacity,
	}


static func from_dict(data: Dictionary) -> Dantian:
	var dantian := Dantian.new()
	dantian.quality = float(data.get("quality", 0.5))
	dantian.injured = bool(data.get("injured", false))
	dantian.structural_capacity = float(data.get("structural_capacity", 100.0))
	return dantian
