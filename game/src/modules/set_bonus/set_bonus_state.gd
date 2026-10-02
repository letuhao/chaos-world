class_name SetBonusState
extends RefCounted

## Set-bonus state for one actor (ADR 0026/0027).
##
## One rule, applied everywhere: thresholds are recomputed from the equipment
## that is actually equipped right now, so equip / unequip / rebuild cannot
## drift or accumulate. The recompute is a full remove-then-apply pass:
##
##   - every threshold's stat modifiers are keyed by the set's own source id
##     (`set:<set_id>:<tier_index>`), never by a member's instance id, so
##     unequipping one member can never delete another member's contribution and
##     can never silently delete the set's own bonus;
##   - the pass first strips every threshold source it knows about, then adds
##     the currently active ones, so a threshold disappears exactly once when it
##     breaks and never doubles while it holds;
##   - the resulting snapshot is written to `actor.module_data["set_state"]` as a
##     versioned plain dictionary, which is how core persists it without ever
##     naming a set type (ADR 0027).

const SCHEMA_VERSION := 1
const MODULE_KEY := &"set_state"
const SOURCE_PREFIX := "set:"
## Bumped when the persisted shape changes; a payload from an older version is
## read as "no set state" rather than partially applied.
const MIN_SUPPORTED_VERSION := 1

var _actor: Actor = null
var _catalog: SetCatalog = null
var _applied: Array[StringName] = []
var _sets: Dictionary = {}


func _init(p_actor: Actor = null, p_catalog: SetCatalog = null) -> void:
	_actor = p_actor
	_catalog = p_catalog if p_catalog != null else SetCatalog.instance()


## The source id a threshold's whole contribution is keyed by.
static func tier_source(set_id: StringName, tier_index: int) -> StringName:
	return StringName("%s%s:%d" % [SOURCE_PREFIX, set_id, tier_index])


## Recompute every set from the actor's equipment and apply the result. This is
## the only place a set bonus is added or removed, and it is safe to call any
## number of times: each call fully replaces the previous contribution.
func recompute(actor: Actor) -> Dictionary:
	_actor = actor
	_ensure_bound(actor)
	_clear(actor)
	_sets = {}
	if actor != null:
		for set_id in _catalog.set_ids():
			_evaluate(actor, set_id)
	_write(actor)
	return to_dict()


## The persisted snapshot. Primitives only, so it survives a JSON round trip.
func to_dict() -> Dictionary:
	var out := {}
	for set_id in _sets.keys():
		var entry: Dictionary = _sets[set_id]
		out[String(set_id)] = {
			"distinct": int(entry["distinct"]),
			"members": (entry["members"] as Array).duplicate(),
			"slots": (entry["slots"] as Dictionary).duplicate(),
			"active_tiers": (entry["active_tiers"] as Array).duplicate(),
		}
	return {"version": SCHEMA_VERSION, "sets": out}


## A persisted payload, normalized. A payload that is absent, empty, from an
## unsupported version, or not a set-state dictionary yields the empty state a
## legacy save should load as.
static func normalize(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {"version": SCHEMA_VERSION, "sets": {}}
	if not data.has("sets") or not data["sets"] is Dictionary:
		return {"version": SCHEMA_VERSION, "sets": {}}
	if int(data.get("version", 0)) < MIN_SUPPORTED_VERSION:
		return {"version": SCHEMA_VERSION, "sets": {}}
	var out := {}
	for set_id in (data["sets"] as Dictionary).keys():
		var entry: Dictionary = (data["sets"] as Dictionary)[set_id]
		var members: Array = []
		for member_id in entry.get("members", []):
			members.append(String(member_id))
		members.sort()
		var slots := {}
		for member_id in entry.get("slots", {}).keys():
			slots[String(member_id)] = String(entry["slots"][member_id])
		var tiers: Array = []
		for index in entry.get("active_tiers", []):
			tiers.append(int(index))
		out[String(set_id)] = {
			"distinct": int(entry.get("distinct", 0)),
			"members": members,
			"slots": slots,
			"active_tiers": tiers,
		}
	return {"version": SCHEMA_VERSION, "sets": out}


## The threshold source ids currently on the actor's stat stack.
func applied_sources() -> Array[StringName]:
	return _applied.duplicate()


## Restore a persisted snapshot onto the actor and re-derive it from equipment.
## Equipment is the single source of truth, so a snapshot that disagrees with
## what is worn is reported, never trusted.
func restore(actor: Actor, data: Dictionary) -> Dictionary:
	var restored := normalize(data)
	recompute(actor)
	return restored


# --- Internals -------------------------------------------------------------


## Connect to the equipment `changed` signal so a raw `Equipment.equip` also
## re-derives the set state. Idempotent, and safe when items are not attached.
func _ensure_bound(actor: Actor) -> void:
	if actor == null:
		return
	var equipment := ItemsApi.equipment(actor)
	if equipment == null:
		return
	if not equipment.changed.is_connected(_on_equipment_changed):
		equipment.changed.connect(_on_equipment_changed)


func _on_equipment_changed() -> void:
	recompute(_actor)


## Strip every threshold contribution this module can have made: the ones
## recorded last pass, plus a full sweep of every authored threshold source, so
## a lost snapshot can never leave a stale bonus behind.
func _clear(actor: Actor) -> void:
	if actor == null:
		_applied.clear()
		return
	for source in _applied:
		actor.stats.remove_modifiers_from(source)
	_applied.clear()
	for set_id in _catalog.set_ids():
		var set_def := _catalog.set_definition(set_id)
		if set_def == null:
			continue
		for index in set_def.tiers.size():
			actor.stats.remove_modifiers_from(tier_source(set_id, index))
	actor.mark_stats_dirty()


## Count one set's distinct equipped members and apply the thresholds it reaches.
func _evaluate(actor: Actor, set_id: StringName) -> void:
	var set_def := _catalog.set_definition(set_id)
	if set_def == null:
		return
	var equipped := _distinct_equipped(set_def)
	var member_ids: Array = equipped.keys()
	member_ids.sort()
	var slots := {}
	for member_id in member_ids:
		slots[member_id] = equipped[member_id]
	var active := set_def.active_tier_indices(member_ids.size())
	for index in active:
		_apply_tier(actor, set_def, index)
	# A set with nothing worn is not recorded at all, so the persisted state
	# answers "which sets are engaged" rather than listing every authored set with
	# a zero count. An unworn set therefore reads as an absent key, and a legacy
	# payload is indistinguishable from one.
	if member_ids.is_empty():
		return
	_sets[String(set_id)] = {
		"distinct": member_ids.size(),
		"members": member_ids,
		"slots": slots,
		"active_tiers": active,
	}


## Distinct definition ids of `set_def` currently equipped, mapped to the first
## slot each occupies. Two copies of one piece in two accessory slots collapse to
## a single entry, so a threshold is never reached by duplication.
func _distinct_equipped(set_def: SetDef) -> Dictionary:
	var out := {}
	var equipment := ItemsApi.equipment(_actor)
	if equipment == null:
		return out
	for slot in Equipment.SLOTS:
		var def := equipment.definition(slot)
		if def == null or not set_def.is_member(def.id):
			continue
		if out.has(String(def.id)):
			continue
		out[String(def.id)] = String(slot)
	return out


func _apply_tier(actor: Actor, set_def: SetDef, tier_index: int) -> void:
	var source := tier_source(set_def.id, tier_index)
	var effects := _tier_effects(set_def, tier_index)
	for modifier in ItemEffects.stat_modifiers(effects, source):
		actor.stats.add_modifier(modifier)
	for modifier in ItemEffects.resource_modifiers(effects, source):
		actor.stats.add_modifier(modifier)
	if not _applied.has(source):
		_applied.append(source)
	actor.mark_stats_dirty()


## The threshold's authored options resolved through the master catalog. An
## option the set has no consumer for on the equipped channel is dropped, so a
## threshold can never apply a decorative effect.
func _tier_effects(set_def: SetDef, tier_index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tier: Dictionary = set_def.tiers[tier_index]
	for entry in tier.get("options", []):
		var option_id := StringName(entry.get("option_id", ""))
		if option_id == &"":
			continue
		if not OptionCatalog.instance().allows_activation(option_id, ItemActivation.EQUIPPED):
			continue
		var effect := OptionCatalog.instance().fixed_effect(
			option_id, float(entry.get("value", 0.0))
		)
		if not effect.is_empty():
			out.append(effect)
	return OptionCatalog.instance().with_bounds(out, set_def.realm, set_def.rarity)


func _write(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, to_dict())
