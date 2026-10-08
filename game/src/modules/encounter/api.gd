class_name EncounterApi
extends RefCounted

## Public facade for the `encounter` module.
## Other modules may reference ONLY this file (`api.gd`).
## Concrete implementations live beside this file and are wired in `app/`.
##
## **Encounters are earn-only** (ADR 0065). There is no purchase, no cheat,
## no removal. An encounter is seen once and stays seen. A prophecy is earned
## through an encounter and stays earned.
##
## The encounter system creates emergent storytelling: players explore the world,
## trigger encounters, and make fate choices that shape their destiny.

const MODULE_KEY := EncounterState.MODULE_KEY


## Attach the encounter module to `actor`. Restores any ledger a prior
## `Actor.from_dict` carried and normalizes it. Idempotent.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	var ledger := EncounterState.normalize(actor.get_module_data(MODULE_KEY))
	actor.set_module_data(MODULE_KEY, ledger)


## Trigger a random encounter for `actor` at the given location.
##
## Returns a dictionary with:
##   - `triggered`: bool — whether an encounter fired
##   - `encounter_id`: StringName — the encounter that fired (empty if none)
##   - `encounter`: EncounterDef — the full definition (null if none)
##   - `fate_choices`: Array[StringName] — the fates offered (empty if none)
##   - `prophecy_id`: StringName — the prophecy drop (empty if none)
##
## The encounter is selected from all eligible encounters (trigger met, not on
## cooldown, not already seen if unique) weighted by their `weight`.
## An RNG seed can be passed for deterministic selection (tests).
static func trigger_encounter(
	actor: Actor,
	current_location: StringName = &"",
	current_turn: int = 0,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	if actor == null:
		return _empty_result()
	var ledger := _ledger(actor)
	var eligible: Array[EncounterDef] = []
	for encounter_id in EncounterCatalog.instance().encounter_ids():
		var def := EncounterCatalog.instance().encounter_definition(encounter_id)
		if def == null:
			continue
		if not def.trigger_met(actor, current_location):
			continue
		if def.unique and EncounterState.has_seen(ledger, encounter_id):
			continue
		if EncounterState.on_cooldown(ledger, encounter_id, current_turn, def.cooldown):
			continue
		eligible.append(def)
	if eligible.is_empty():
		return _empty_result()
	# Weighted selection
	var total_weight := 0.0
	for def in eligible:
		total_weight += def.weight
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var roll := rng.randf() * total_weight
	var selected: EncounterDef = eligible[0]
	for def in eligible:
		roll -= def.weight
		if roll <= 0.0:
			selected = def
			break
	# Mark as seen
	ledger["seen"][String(selected.id)] = true
	ledger["cooldowns"][String(selected.id)] = current_turn
	_record(ledger, "encounter", selected.id, "triggered")
	_persist(actor, ledger)
	return {
		"triggered": true,
		"encounter_id": selected.id,
		"encounter": selected,
		"fate_choices": selected.fate_choices.duplicate(),
		"prophecy_id": selected.prophecy_id,
	}


## Resolve an encounter by making a fate choice.
##
## `encounter_id` is the encounter being resolved. `fate_index` is the index
## into the encounter's `fate_choices` array (0 or 1). The chosen fate is
## earned through `DestinyApi.earn_fate`. If the encounter has a prophecy,
## it is recorded as earned.
##
## Returns a dictionary with:
##   - `ok`: bool — whether the resolution succeeded
##   - `reason`: String — empty on success, or a named refusal
##   - `fate_id`: StringName — the fate that was earned (empty on refusal)
##   - `prophecy_id`: StringName — the prophecy earned (empty on refusal)
static func resolve_encounter(
	actor: Actor, encounter_id: StringName, fate_index: int
) -> Dictionary:
	if actor == null:
		return _refuse("no_actor")
	var ledger := _ledger(actor)
	if not EncounterState.has_seen(ledger, encounter_id):
		return _refuse("not_seen")
	if EncounterState.has_resolved(ledger, encounter_id):
		return _refuse("already_resolved")
	var def := EncounterCatalog.instance().encounter_definition(encounter_id)
	if def == null:
		return _refuse("unknown_encounter")
	if fate_index < 0 or fate_index >= def.fate_choices.size():
		return _refuse("invalid_fate_index")
	var fate_id := def.fate_choices[fate_index]
	# Earn the fate through the destiny module
	DestinyApi.earn_fate(actor, fate_id, "encounter:%s" % String(encounter_id))
	# Record resolution
	ledger["resolved"][String(encounter_id)] = {
		"fate_id": String(fate_id),
		"sequence": _next_sequence(ledger),
	}
	_record(ledger, "resolve", encounter_id, String(fate_id))
	# Earn prophecy if any
	var prophecy_id := def.prophecy_id
	if prophecy_id != &"" and not EncounterState.has_prophecy(ledger, prophecy_id):
		ledger["prophecies_earned"][String(prophecy_id)] = true
		_record(ledger, "prophecy", prophecy_id, "earned")
	_persist(actor, ledger)
	return {
		"ok": true,
		"reason": "",
		"fate_id": fate_id,
		"prophecy_id": prophecy_id,
	}


## Dismiss an encounter without making a fate choice.
## The encounter is marked as seen but not resolved. It can trigger again
## if it is not unique and the cooldown has passed.
static func dismiss_encounter(actor: Actor, encounter_id: StringName) -> Dictionary:
	if actor == null:
		return _refuse("no_actor")
	var ledger := _ledger(actor)
	if not EncounterState.has_seen(ledger, encounter_id):
		return _refuse("not_seen")
	if EncounterState.has_resolved(ledger, encounter_id):
		return _refuse("already_resolved")
	_record(ledger, "dismiss", encounter_id, "dismissed")
	_persist(actor, ledger)
	return {"ok": true, "reason": ""}


## The actor's encounter ledger exactly as core persists it.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return EncounterState.empty()
	return EncounterState.normalize(actor.get_module_data(MODULE_KEY))


## A read-only, primitive-only snapshot for a codex UI.
static func summary(actor: Actor) -> Dictionary:
	var ledger := _ledger(actor)
	var out := {
		"has_actor": actor != null,
		"seen_count": (ledger["seen"] as Dictionary).size(),
		"resolved_count": (ledger["resolved"] as Dictionary).size(),
		"prophecy_count": (ledger["prophecies_earned"] as Dictionary).size(),
		"prophecies": [],
		"encounters": [],
	}
	for prophecy_id in EncounterState.prophecies_earned(ledger):
		var def := EncounterCatalog.instance().prophecy_definition(prophecy_id)
		if def == null:
			continue
		(
			out["prophecies"]
			. append(
				{
					"id": String(def.id),
					"display_name": String(def.display_name),
					"description": String(def.description),
					"hint_text": String(def.hint_text),
					"hint_fate_id": String(def.hint_fate_id),
				}
			)
		)
	for encounter_id in EncounterCatalog.instance().encounter_ids():
		var def := EncounterCatalog.instance().encounter_definition(encounter_id)
		if def == null:
			continue
		var seen := EncounterState.has_seen(ledger, encounter_id)
		var resolved := EncounterState.has_resolved(ledger, encounter_id)
		(
			out["encounters"]
			. append(
				{
					"id": String(def.id),
					"display_name": String(def.display_name),
					"description": String(def.description),
					"seen": seen,
					"resolved": resolved,
					"fate_choices": _string_list(def.fate_choices),
					"prophecy_id": String(def.prophecy_id),
					"unique": def.unique,
				}
			)
		)
	return out


## All prophecies earned by the actor, as primitive dictionaries.
static func prophecies(actor: Actor) -> Array[Dictionary]:
	var ledger := _ledger(actor)
	var out: Array[Dictionary] = []
	for prophecy_id in EncounterState.prophecies_earned(ledger):
		var def := EncounterCatalog.instance().prophecy_definition(prophecy_id)
		if def == null:
			continue
		(
			out
			. append(
				{
					"id": String(def.id),
					"display_name": String(def.display_name),
					"description": String(def.description),
					"hint_text": String(def.hint_text),
					"hint_fate_id": String(def.hint_fate_id),
				}
			)
		)
	return out


## Whether the actor has earned a specific prophecy.
static func has_prophecy(actor: Actor, prophecy_id: StringName) -> bool:
	if actor == null:
		return false
	return EncounterState.has_prophecy(_ledger(actor), prophecy_id)


# --- Internals -------------------------------------------------------------


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return EncounterState.empty()
	var pending: Dictionary = actor.get_module_data(MODULE_KEY)
	if pending.is_empty():
		attach(actor)
		pending = actor.get_module_data(MODULE_KEY)
	return EncounterState.normalize(pending)


static func _next_sequence(ledger: Dictionary) -> int:
	var highest := 0
	for key in (ledger["resolved"] as Dictionary).keys():
		highest = maxi(highest, int((ledger["resolved"] as Dictionary)[key].get("sequence", 0)))
	return highest + 1


static func _record(ledger: Dictionary, kind: String, id: StringName, detail: String) -> void:
	var history: Array = ledger["history"]
	if history.size() >= EncounterState.HISTORY_LIMIT:
		return
	(
		history
		. append(
			{
				"kind": kind,
				"id": String(id),
				"detail": detail,
				"sequence": _next_sequence(ledger),
			}
		)
	)


static func _persist(actor: Actor, ledger: Dictionary) -> void:
	actor.set_module_data(MODULE_KEY, ledger)


static func _empty_result() -> Dictionary:
	return {
		"triggered": false,
		"encounter_id": &"",
		"encounter": null,
		"fate_choices": [],
		"prophecy_id": &"",
	}


static func _refuse(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"fate_id": &"",
		"prophecy_id": &"",
	}


static func _string_list(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
