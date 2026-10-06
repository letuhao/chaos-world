class_name StatusEffect
extends RefCounted

## A timed or permanent actor status. Modules own their own status ids.
##
## ADR 0086: **a status is data, not a class.** Every field below is defaulted so
## the live constructor calls keep compiling — `StatusEffect.new(&"heavenly_blessing",
## 86400.0)` and `PregnancyStatus.new(FertilityStats.PREGNANCY)` — and adding the
## twenty-first status is a def rather than a subclass. A subclass stays legal for
## a genuine state machine (`PregnancyStatus` is one); what is refused is a
## subclass per status, and any subclass that assumes a single source, because
## this class is the shared vocabulary rather than a combat-owned type.
##
## **No element TYPE.** `contracts/` may depend on `contracts/` alone and is in
## `BARE_REF_UNITS` (`tools/arch/rules.py:60`), so naming `ElementStats` here is an
## arch violation. An element is a `StringName` tag, which is all "one element per
## attack" (ADR 0069) needs.
##
## This class builds no `StatModifier` and applies no stat: it is data, and the
## module that applies it turns `magnitude` into modifiers.

enum Kind {
	DOT,  ## hurts on an interval, paying `magnitude` per tick.
	STAT_MODIFIER,  ## a magnitude the consumer resolves onto a stat.
	CONTROL,  ## gates an action; magnitude is the gate's strength.
	AMPLIFIER,  ## scales other statuses; magnitude is the factor.
	BURST,  ## lands once and expires; magnitude is the single hit.
}

enum Scope {
	COMBAT,  ## opposed by the combat status gate: power vs `status_defense` (ADR 0884).
	CULTIVATION,  ## never resisted: a blessing the game pays out must not tax the player.
}

enum Stacking {
	REFRESH,  ## keep the longer duration and the STRONGER magnitude.
	STACK,  ## add magnitudes up to `magnitude_cap`.
	REPLACE,  ## overwrite duration and magnitude outright.
}

## The ops a status may carry into a `StatModifier`. `Stat.Op` is REFERENCED here,
## never re-declared: a second enum is a second place to get FLAT-on-a-rate wrong
## (ADR 0068). `MULT` is banned because N instances would compound to 1024x and
## make a status's strength a function of how often it was applied.
const ALLOWED_OPS: Array = [Stat.Op.FLAT, Stat.Op.PERCENT]

var id: StringName

## The element this status rides, as a tag. Empty means "not element-bound".
var element: StringName = &""

var kind: Kind = Kind.STAT_MODIFIER

var scope: Scope = Scope.COMBAT

## How a re-application merges. Read off the INCOMING status, because a def
## declares how it stacks onto what is already there.
var stacking: Stacking = Stacking.REFRESH

## How strong this status is, in whatever unit its `kind` implies. Kept on the
## contract so combat, environment and consumables resolve strength the same way.
var magnitude: float = 0.0

## The ceiling `STACK` addition stops at. **Zero or less means uncapped**, so a def
## that never authors a cap compounds rather than silently resolving to zero. A
## def that wants a ceiling states it — this default is a provisional placeholder,
## not a balance number.
var magnitude_cap: float = 0.0

## How many applications this instance has absorbed. A freshly applied status is 1.
var stacks: int = 1

## Seconds left, or negative for permanent (see [method is_permanent]).
var remaining: float

## Seconds between periodic effects. Zero means this status is a plain timer and
## never pays one — a blessing and a pregnancy are both timers, not clocks.
var tick_interval: float = 0.0

## Accumulated seconds toward the next tick. Advanced only from the caller's
## delta, never from a wall clock, so a replay ticks exactly as it was driven.
var tick_elapsed: float = 0.0

## Who or what applied it. A tag, not a type: a status may be refreshed by
## anything, so no single source may be assumed.
var source: StringName = &""

## The levers that reduce this status. REQUIRED and non-empty for anything
## authored as a hazard; empty is an authoring error (ADR 0075), and it is the ONE
## purge vocabulary read by combat, environment and consumables alike. See
## [method has_mitigation].
var mitigation_tags: Array[StringName] = []

## Module-private scratch. Named keys so no consumer guesses at a shape.
var payload: Dictionary = {}


func _init(p_id: StringName, p_remaining: float = -1.0) -> void:
	id = p_id
	remaining = p_remaining


func is_permanent() -> bool:
	return remaining < 0.0


func is_expired() -> bool:
	return not is_permanent() and remaining <= 0.0


## Whether this status publishes a lever that reduces it. False is an authoring
## error, not a weaker status: a hazard with nothing to push back against is the
## flat tax ADR 0075 refuses.
func has_mitigation() -> bool:
	return not mitigation_tags.is_empty()


## Whether `op` may carry this status's magnitude onto a stat. Enforced against
## the OP, not the stat, because the op is what a status chooses (ADR 0086).
func allows_op(op: Stat.Op) -> bool:
	return ALLOWED_OPS.has(op)


## Whether this status is opposed by a `resistance` value. Only `Scope.COMBAT` is:
## taxing the player for a reward the game itself paid out is not a difficulty knob.
## The combat gate that supplies `resistance` is `StatusApply`'s power-vs-`status_defense`
## contest (ADR 0884).
func is_resisted_by(resistance: float) -> bool:
	return scope == Scope.COMBAT and resistance > 0.0


func tick(delta: float) -> void:
	if not is_permanent():
		remaining = maxf(0.0, remaining - delta)


## The JSON-safe payload a save carries. String keys and no `StringName` anywhere: `Actor
## .to_dict` converts only its OWN keys, so a `StringName` reaching the save here would
## break every round trip (ADR 0027).
##
## **Enums are stored as INTS and read back through the enum**, because a `String` of the
## name would need a name table and an int needs none. `kind`, `scope` and `stacking` are all
## defaulted, so an unknown int from a future content wave degrades to the default rather
## than failing to deserialize.
func to_dict() -> Dictionary:
	var tags: Array = []
	for tag in mitigation_tags:
		tags.append(String(tag))
	return {
		"id": String(id),
		"element": String(element),
		"kind": int(kind),
		"scope": int(scope),
		"stacking": int(stacking),
		"magnitude": magnitude,
		"magnitude_cap": magnitude_cap,
		"stacks": stacks,
		"remaining": remaining,
		"tick_interval": tick_interval,
		"tick_elapsed": tick_elapsed,
		"source": String(source),
		"mitigation_tags": tags,
		"payload": payload.duplicate(true),
	}


## Restore from [method to_dict]. An entry with no id is dropped rather than kept as a
## nameless status, because a status nobody can name is one nothing can purge.
static func from_dict(data: Dictionary) -> StatusEffect:
	var status_id := StringName(data.get("id", ""))
	if status_id == &"":
		return null
	var status := StatusEffect.new(status_id, float(data.get("remaining", -1.0)))
	status.element = StringName(data.get("element", ""))
	status.kind = _enum_or_default(data.get("kind", 0), Kind.STAT_MODIFIER)
	status.scope = _enum_or_default(data.get("scope", 0), Scope.COMBAT)
	status.stacking = _enum_or_default(data.get("stacking", 0), Stacking.REFRESH)
	status.magnitude = float(data.get("magnitude", 0.0))
	status.magnitude_cap = float(data.get("magnitude_cap", 0.0))
	status.stacks = maxi(1, int(data.get("stacks", 1)))
	status.tick_interval = float(data.get("tick_interval", 0.0))
	status.tick_elapsed = float(data.get("tick_elapsed", 0.0))
	status.source = StringName(data.get("source", ""))
	var payload = data.get("payload", {})
	if payload is Dictionary:
		status.payload = (payload as Dictionary).duplicate(true)
	for tag in data.get("mitigation_tags", []):
		status.mitigation_tags.append(StringName(tag))
	return status


## Coerce a persisted int back into an enum, falling back when the value is outside the
## current set. A content wave that retires a status kind must not make an old save unreadable.
static func _enum_or_default(value: Variant, fallback: int) -> int:
	var index := int(value)
	if index < 0:
		return fallback
	match index:
		Kind.DOT, Kind.STAT_MODIFIER, Kind.CONTROL, Kind.AMPLIFIER, Kind.BURST:
			return index
	return fallback
