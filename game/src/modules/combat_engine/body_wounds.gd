class_name BodyWounds
extends RefCounted

## The BODY path's wound ledger: per-meridian severity accumulating into NECROSIS
## (ADR 0070).
##
## ## Severity is measured in integrity, so a wound costs what it is worth
##
## `severity += damage / body_integrity.maximum`, exactly the shape
## `BodyAdvancement._deviate` already writes (`advancement.gd:345`, `integrity_maximum *
## 0.25`). That is what makes the two the SAME wound expressed twice: one costs a
## cultivator a realm through a failed breakthrough, and the other costs one through a
## good fighter, with no third number to keep in step. The divisor is the pool's
## `maximum`, never its `current` — severity is "how much of this body has been spent",
## and a body that is already hurt does not make every fresh gash cheaper.
##
## ## Two thresholds, two irreversible facts
##
## At `WOUND_THRESHOLD` the EXISTING `MeridianNetwork.damage_meridian` is called:
## recoverable, halves the channel's aggregate bonus, and is the one flag whose meaning
## is shared. At `NECROSIS_THRESHOLD` — deliberately one failed breakthrough's worth —
## the channel's surviving points are floored to `NECROSIS_QUALITY` and ONE is jammed.
## `necrotic` is a `bool` and not a number to be compared, so no decay rate, no repair
## and no future threshold can un-necrose a channel.
##
## ## Decay never crosses necrosis downward
##
## [method decay] bleeds severity, and floors it at `necrosis_threshold` for a channel
## that has crossed — so a necrotic channel is permanently "at least this bad" however
## long the fight runs. Decay does NOT repair: an injured channel stays injured until
## `MeridianNetwork.repair_meridian` runs through the realm's ADR 0031 recovery item,
## which is the single clearable route ADR 0070 names. Timed decay that also repaired
## would make waiting a second recovery path and the recovery item pointless.
##
## ## Which point necrosis jams is a PURE FUNCTION OF STATE
##
## The highest-quality surviving point on the channel, ties broken by id. Not a draw:
## ADR 0070's determinism rule is that every choice this path makes is state-derived so
## a player can be told what happened, and the best node is the one whose loss a
## cultivator will feel and can therefore be shown.
##
## ## No class of `body_cultivation` is named
##
## The acupoint set is read off `actor.components[&"acupoints"]` and every field and
## verb is reached through `get()` / `call()`, for the reason `QiDamage` sets: this
## module's deps are `["contracts", "core"]`, and a `StringName` key read out of DATA
## (`CombatTuning.integrity_pool_id`, `CombatTuning.acupoint_data_dir`) is the one
## honest way to reach another module without `registry.json` declaring an edge that
## exists only as a string concatenation.

## The key this module's own vocabulary uses for a wound, and the kind a
## `DamageProposal` effect carries. Primitives only, because `effects[]` travel into a
## UI `summary()` and a save payload (ADR 0038, ADR 0067).
const EFFECT_KIND := &"body.wound"
## The effect key naming the channel the wound is on.
const KEY_MERIDIAN := &"meridian"
## The effect key carrying the severity added by this hit.
const KEY_SEVERITY := &"severity"
## The result keys, so a readout and a test read the same names.
const KEY_WOUNDED := &"wounded"
const KEY_NECROSED := &"necrosed"
const KEY_JAMMED := &"jammed"
const KEY_FLOORED := &"floored"
const KEY_TOTAL := &"total"
## The component key the acupoint set is read through. A `StringName` here because this
## module may not name the module that owns it; the same key the body's own provider and
## its `api.gd` use, so there is one spelling.
const ACUPOINTS_KEY := &"acupoints"
## The key the ledger is restored from inside `Actor.module_data`, matching the raw-dict
## convention `Actor.to_dict` uses for `mind_attempt` and `acupoints`.
const MODULE_KEY := &"body_wounds"

## Meridian id -> accumulated severity. A float, never a `ResourcePool`: ADR 0028's
## one-reservoir rule means `body_integrity` stays the body's single reservoir and a
## wound is a number on the channel, not a second bar the player fills.
var severity: Dictionary = {}
## Meridian id -> true, once NECROSIS has been written. Never cleared by [method decay].
var necrotic: Dictionary = {}
## The ledger's bound `CombatTuning`, or null for a caller who passes one per call.
## [method threshold] reads it, and it is a FIELD rather than a per-call argument because
## the ledger is long-lived state a caller binds once — the same shape `BodyDamage.tuning`
## takes. Every read still tolerates a null, because a bare ledger must answer the
## documented fallbacks rather than crash a hit.
var tuning: CombatTuning = null


func severity_of(meridian_id: StringName) -> float:
	return maxf(0.0, _finite(float(severity.get(String(meridian_id), 0.0))))


func is_necrotic(meridian_id: StringName) -> bool:
	return bool(necrotic.get(String(meridian_id), false))


func is_wounded(meridian_id: StringName) -> bool:
	return severity_of(meridian_id) >= threshold(&"wound_threshold", 0.0)


## Apply one hit's wound. Returns the result keys above, all primitives.
##
## `damage` is the mechanism's OWN subtotal (S4), never the spine's post-reduction
## amount: a defender at full `DAMAGE_REDUCTION` has been hit just as hard, and basing
## severity on the post-S8 number would let the chip floor mint a wound out of a strike
## the flat subtraction had already refused. A non-positive or non-finite `damage`, or a
## body with no integrity pool, writes nothing and says so.
func add(
	target: Variant, meridian_id: StringName, damage: float, tuning: CombatTuning
) -> Dictionary:
	var result := {
		KEY_WOUNDED: false,
		KEY_NECROSED: false,
		KEY_JAMMED: &"",
		KEY_FLOORED: false,
		KEY_TOTAL: severity_of(meridian_id),
	}
	if meridian_id == &"":
		return result
	var amount := _finite(damage)
	if amount <= 0.0:
		return result
	var bound := _bound_of(tuning)
	var maximum := _integrity_maximum(target, bound)
	if maximum <= 0.0:
		return result
	var key := String(meridian_id)
	severity[key] = severity_of(meridian_id) + amount / maximum
	result[KEY_TOTAL] = float(severity[key])
	if severity_of(meridian_id) >= _read_threshold(bound, "wound_threshold", 0.0):
		result[KEY_WOUNDED] = _wound_channel(target, meridian_id)
	if (
		not is_necrotic(meridian_id)
		and severity_of(meridian_id) >= _read_threshold(bound, "necrosis_threshold", 0.0)
	):
		var necro := _necrose(target, meridian_id, bound)
		result[KEY_NECROSED] = bool(
			necro.get(KEY_JAMMED, &"") != &"" or necro.get(KEY_FLOORED, false)
		)
		result[KEY_JAMMED] = necro.get(KEY_JAMMED, &"")
		result[KEY_FLOORED] = necro.get(KEY_FLOORED, false)
	return result


## Apply every wound a proposal carried. The route the caller uses, and the only one
## that is safe to call from a `effects[]` applier: `apply_wound` in
## `contracts/location_resolver.gd` deliberately writes nothing, because the spine
## applies effects AFTER health and a resolver that wrote here would land the wound
## before the blow it was earned by.
func apply_all(target: Variant, effects: Array, tuning: CombatTuning) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (effects is Array):
		return out
	for entry in effects as Array:
		if not (entry is Dictionary):
			continue
		var typed := entry as Dictionary
		if StringName(typed.get(DamageProposal.KIND, &"")) != EFFECT_KIND:
			continue
		var meridian := StringName(typed.get(KEY_MERIDIAN, &""))
		out.append(add(target, meridian, float(typed.get(KEY_SEVERITY, 0.0)), tuning))
	return out


## One tick of decay for every channel on the ledger. Returns `{decayed, floored}`, both
## integers, so a combat tick can report what it did without reading the table.
##
## A channel that has crossed NECROSIS floors at `necrosis_threshold` and no lower: the
## irreversible fact is expressed by the FLOOR, not by refusing to decay it, so the
## number still visibly improves while the state it implies does not. That is what makes
## "never crosses necrosis downward" a property of the arithmetic rather than of an `if`.
func decay(delta: float, tuning: CombatTuning) -> Dictionary:
	var seconds := maxf(0.0, _finite(delta))
	var bound := _bound_of(tuning)
	var rate := maxf(0.0, _read_threshold(bound, "wound_decay", 0.0))
	var necrosis_floor := maxf(0.0, _read_threshold(bound, "necrosis_threshold", 0.0))
	var decayed := 0
	var floored := 0
	for key in severity.keys():
		var floor_value := 0.0
		if bool(necrotic.get(key, false)):
			floor_value = necrosis_floor
		var before := maxf(0.0, _finite(float(severity[key])))
		var after := maxf(floor_value, before - rate * seconds)
		if after < before:
			decayed += 1
		if after != before:
			floored += 1
		severity[key] = after
	return {"decayed": decayed, "floored": floored}


## The `combat_engine` spelling of a wound threshold, read out of DATA. The four are one
## vocabulary, so they are read through one function and a typo cannot leave one of them
## reading a field that does not exist — `CombatTuning` is this module's own type and is
## the only one named anywhere on the body path.
##
## The ledger's BOUND tuning, never the per-call one: [method add] and [method decay] bind
## their argument once through [method _bound_of] and read it through [method _read_threshold]
## below, so this is the query form of the same resolution and cannot answer differently.
func threshold(key: String, fallback: float) -> float:
	var source: CombatTuning = self.tuning
	if source == null:
		return fallback
	return _read_threshold(source, key, fallback)


## The tuning ONE operation reads: its own argument when it has one, then the ledger's
## bound one. `null` means "no vocabulary at all" — which writes no threshold and no pool,
## rather than falling through to a `CombatTuning.new()` whose every bound is `0.0` and
## whose every threshold is therefore crossed on the FIRST gash (BRIEF 1.7's deliberately
## degenerate default, honest only when nothing silently substitutes it).
##
## This is the root of group D: the per-call argument and the bound field were two
## separate reads, and [method add] resolving thresholds against the ARGUMENT while the
## pool id and the necrosis quality came from the FIELD left a ledger bound to the shipped
## `.tres` comparing severity against `0.0` — so a half-threshold gash wounded the channel
## and left it already sitting on the necrosis floor.
func _bound_of(tuning: CombatTuning) -> CombatTuning:
	return tuning if tuning != null else self.tuning


static func _read_threshold(tuning: CombatTuning, key: String, fallback: float) -> float:
	if tuning == null:
		return fallback
	var value: Variant = tuning.get(key)
	return _finite(float(value)) if (value is float or value is int) else fallback


## Raw dictionaries, because `Actor.to_dict` carries module state as data and never as a
## typed object. `severity` is a float per channel and `necrotic` is a flag set; both are
## written so a reader can tell "no wound" from "a wound that decayed to nothing".
func to_dict() -> Dictionary:
	return {"severity": severity.duplicate(), "necrotic": necrotic.duplicate()}


func load_from(data: Dictionary) -> void:
	severity = {}
	necrotic = {}
	var entries: Variant = data.get("severity", {})
	if entries is Dictionary:
		for key in (entries as Dictionary).keys():
			var value := maxf(0.0, _finite(float((entries as Dictionary)[key])))
			if value > 0.0:
				severity[String(key)] = value
	var flags: Variant = data.get("necrotic", {})
	if flags is Dictionary:
		for key in (flags as Dictionary).keys():
			if bool((flags as Dictionary)[key]):
				necrotic[String(key)] = true


# --- internals -----------------------------------------------------------------


## The integrity pool's `maximum`, or 0.0 when this body has no such pool. Read through
## the tuning's pool id rather than a named constant, and a missing pool reads as 0.0 --
## which writes no wound rather than dividing by zero, the same degradation `QiDamage`
## gives a 0.0 divisor.
func _integrity_maximum(target: Variant, tuning: CombatTuning) -> float:
	if target == null or tuning == null or tuning.integrity_pool_id == &"":
		return 0.0
	var resources: Variant = _read(target, &"resources", null)
	if not (resources is Dictionary):
		return 0.0
	var pool: Variant = (resources as Dictionary).get(tuning.integrity_pool_id, null)
	if pool == null:
		return 0.0
	return maxf(0.0, _finite(float(_read(pool, &"maximum", 0.0))))


## The EXISTING `MeridianNetwork.damage_meridian`, reached through the network this actor
## carries. ADR 0070 requires the call rather than a parallel flag: a wound must cost the
## channel's aggregate bonus for EVERY path, and a second boolean here would be halved by
## nothing and read by nothing.
func _wound_channel(target: Variant, meridian_id: StringName) -> bool:
	var network: Variant = _read(target, &"meridians", null)
	if network == null or not (network is Object):
		return false
	if not (network as Object).has_method(&"damage_meridian"):
		return false
	(network as Object).call(&"damage_meridian", meridian_id)
	return true


## NECROSIS: floor every surviving point on the channel to `necrosis_quality`, then jam
## ONE. The floor is a floor -- a gash must never be a promotion -- and the jam is the
## half a cultivator feels, because a blocked point leaves `AcupointSet.open_count` and
## reads nothing in `average_quality`.
func _necrose(target: Variant, meridian_id: StringName, tuning: CombatTuning) -> Dictionary:
	necrotic[String(meridian_id)] = true
	var quality := clampf(_read_threshold(tuning, "necrosis_quality", 0.0), 0.0, 1.0)
	var best_id := &""
	var best_quality := -INF
	var floored := false
	for point in _points_of(target, meridian_id):
		var current := clampf(_finite(float(_read(point, &"quality", 0.0))), 0.0, 1.0)
		if current > quality:
			if point is Object:
				(point as Object).set(&"quality", quality)
			floored = true
		# Highest-quality SURVIVING point: a jammed one is already lost, so jamming a
		# second point on the same channel would spend the necrosis on nothing.
		if bool(_read(point, &"blocked", false)):
			continue
		var id := StringName(_read(point, &"id", &""))
		if (
			current > best_quality
			or (current == best_quality and best_id != &"" and String(id) < String(best_id))
		):
			best_quality = current
			best_id = id
	if best_id != &"":
		for point in _points_of(target, meridian_id):
			if StringName(_read(point, &"id", &"")) != best_id:
				continue
			if point is Object and (point as Object).has_method(&"block"):
				(point as Object).call(&"block")
			break
	return {KEY_JAMMED: best_id, KEY_FLOORED: floored}


## The actor's acupoint set, read through the same key the body's own provider and its
## `api.gd` use, so there is one spelling. Null for a body nobody attached one to.
func _acupoint_set(target: Variant) -> Variant:
	var holder: Variant = _read(target, &"components", null)
	if not (holder is Dictionary):
		return null
	return (holder as Dictionary).get(ACUPOINTS_KEY, null)


## The actor's acupoints bound to one meridian, read through the authored point -> meridian
## map. Returns `[]` for a body nobody attached an acupoint set to, which is a training
## dummy rather than a crash: the wound is still written and still crosses its thresholds.
func _points_of(target: Variant, meridian_id: StringName) -> Array:
	var out: Array = []
	var points: Variant = _read(_acupoint_set(target), &"points", null)
	if not (points is Array):
		return out
	for point in points as Array:
		if BodyLocation.meridian_of_point(StringName(_read(point, &"id", &""))) == meridian_id:
			out.append(point)
	return out


## `Object.get` with a fallback, never `Object._get` -- the latter is an engine hook and
## a same-arity declaration collides with it, which fails the whole file to compile.
func _read(value: Variant, key: StringName, fallback: Variant) -> Variant:
	if value == null or not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(key)
	return result if result != null else fallback


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0
