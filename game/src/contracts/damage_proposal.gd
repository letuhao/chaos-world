class_name DamageProposal
extends RefCounted

## What one damage mechanism produced for one landed hit (ADR 0067).
##
## A mechanism does not apply damage. It RETURNS a proposal and the spine owns
## every shared stage after it: crit (S6), amplification (S7), the chip floor
## (S8), the shield (S9), reflect (S10) and leech (S11). That is the whole point
## of the seam — there is no `if/else on path_id` anywhere in
## `modules/combat/`, because a fourth path costs one new file and one `app/`
## line.
##
## `amount` is the magnitude the mechanism produced and is NON-NEGATIVE: qi and
## body return a real damage number, mind returns `0.0` because it never
## subtracts health (ADR 0071) and erodes the sea through `effects` instead. The
## sign flip happens in exactly one place in the whole engine, S9's
## `change_resource(&"health", -overflow)`, so a negative amount is a defect and
## the constructor refuses to build one.
##
## `effects` are the path's OWN state writes and the spine applies them AFTER
## health, so a mechanism can never make a target's health depend on whether
## its own follow-up state write landed. Every entry is a primitives-only
## dictionary — a `StringName` kind plus numeric values — because these
## dictionaries travel into UI `summary()` payloads and save data. A `Resource`
## or an engine `Object` in this array would be a save-schema bug no gate can
## see, so `add_effect` refuses one at construction time rather than letting it
## travel three stages into a payload.
##
## An instance is a VALUE. `effects` is copied on the way in and on the way out,
## so two proposals can never alias one effect list.

## The key every effect entry carries: the path's own vocabulary for what the
## write is. Modules own the ids; `contracts/` names the shape, not the words.
const KIND := &"kind"

## The shared empty instance, which ADR 0067 and the spine's S4-null path name.
##
## ## WHY THIS EXISTS AT ALL, and why it is not what new code should call
##
## A GDScript object is a REFERENCE. Every holder of this constant shares ONE
## `effects` array, so a mechanism that appended to `DamageProposal.NONE.effects`
## would give the SAME entry to every other mechanism's proposal, and the damage
## would surface three stages later as a wound on the wrong actor — the exact
## class of failure `MechanismSlot` refuses to have. A shared empty value is only
## safe if it cannot be written through, and GDScript cannot express "read-only
## object": `effects` is a public `Array[Dictionary]` precisely so the spine can
## read it.
##
## So the call is not "constant or factory" but "who may write". Read-only
## sharing is safe, and the ONLY sanctioned use of this constant is as an argument
## handed to `mitigate` (which returns what it was given) and as a comparison
## value. Handing it out as something to BUILD on is not, and [method none] is the
## fresh instance for that. `DamageMechanism.resolve` returns `none()` for exactly
## this reason. It is a `static var` rather than a `const` because a `const` is
## evaluated while the script is still loading, and self-instantiation there is a
## cyclic reference — and a `static var` can be reassigned, so it must be treated
## as read-only in review the same way a `const` would be.
##
## Named `shared`, lowercase, because that is the repo's convention for a class-scope
## singleton (`OptionCatalog.shared`, `TechniqueCatalog.shared`, `SetCatalog.shared`) and
## gdlint's `class-variable-name` rule enforces it. It is READ-ONLY by contract: a
## mechanism that appended to it would corrupt every other mechanism's empty proposal,
## which is exactly the bug [method none] exists to avoid. Use `none()` to build one.
static var shared := DamageProposal.new()

var amount: float = 0.0
var effects: Array[Dictionary] = []


func _init(p_amount: float = 0.0, p_effects: Array[Dictionary] = []) -> void:
	amount = maxf(0.0, p_amount)
	effects = _sanitized(p_effects)


## A FRESH empty proposal nobody else holds, so it is safe to build on. This is
## the form new code calls; see [member NONE] for why the shared constant cannot
## be.
static func none() -> DamageProposal:
	return DamageProposal.new()


## Whether this proposal declines the hit: no magnitude and no state writes. A
## mechanism returns this rather than `0.0` alone so the spine can tell "nothing
## happened" from "this path hits differently".
func is_empty() -> bool:
	return amount <= 0.0 and effects.is_empty()


## A COPY carrying a different amount. The spine needs this when it applies crit
## (S6), amplification (S7) or the chip floor (S8): what a mechanism returned may
## already be in a caller's hands for a breakdown readout, so the shared stages
## transform a copy and leave the mechanism's own value intact.
func with_amount(value: float) -> DamageProposal:
	return DamageProposal.new(value, effects)


## Append one path-owned state write. `kind` is the path's own id; `values` are
## primitives only. A non-primitive value is dropped with a message rather than
## travelling into a save payload, because the payload is the one place this shape
## is unrecoverable.
func add_effect(kind: StringName, values: Dictionary = {}) -> void:
	effects.append(_primitive_only(kind, values))


## The first effect of `kind` as a copy, or an empty dictionary when there is
## none.
func effect_of(kind: StringName) -> Dictionary:
	for entry in effects:
		if entry.get(KIND, &"") == kind:
			return entry.duplicate(true)
	return {}


func has_effect(kind: StringName) -> bool:
	for entry in effects:
		if entry.get(KIND, &"") == kind:
			return true
	return false


## `amount` plus the effects flattened for a UI `summary()` or a log line. Keys
## become `String`s because the payload is serialised.
func summary() -> Dictionary:
	var rows: Array = []
	for entry in effects:
		rows.append(_stringified(entry))
	return {"amount": amount, "effects": rows}


## Whether every key and value in `entry` is a primitive this proposal is willing
## to carry. Public because the shape IS the contract: a rule nobody can ask
## about is a rule nobody checks.
static func is_primitive_effect(entry: Dictionary) -> bool:
	for key in entry.keys():
		if not (key is StringName or key is String):
			return false
		if not _is_primitive(entry[key]):
			return false
	return true


## Keys are normalised to `StringName`, so two paths writing the same effect shape
## produce byte-identical dictionaries and a save blob written by one is a blob the
## other can read.
static func _sanitized(source: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in source:
		var kind: Variant = entry.get(KIND, &"")
		out.append(_primitive_only(StringName(kind), entry))
	return out


static func _primitive_only(kind: StringName, values: Dictionary) -> Dictionary:
	var entry := {KIND: kind}
	for key in values.keys():
		if not _is_primitive(values[key]):
			push_error(
				(
					"DamageProposal: effect '%s' carries a non-primitive value for key '%s'"
					% [String(kind), String(key)]
				)
			)
			continue
		entry[StringName(key)] = values[key]
	return entry


static func _stringified(entry: Dictionary) -> Dictionary:
	var out := {}
	for key in entry.keys():
		out[String(key)] = entry[key]
	return out


static func _is_primitive(value: Variant) -> bool:
	return value is int or value is float or value is bool or value is StringName or value is String
