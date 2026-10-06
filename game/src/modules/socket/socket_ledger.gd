class_name SocketLedger
extends RefCounted

## The versioned socket payload for one actor (ADR 0027).
##
## It is stored in `actor.module_data["socket_state"]` as a plain dictionary, so
## `Actor` carries it without knowing a socket type exists; this class is the
## typed view over that payload and the only writer.
##
## Three independent sections:
##   `parents`  — per owning instance, the ordered slots it carries. A slot's
##                imputed effects live here, never on the inserted gem, so they
##                survive inserting and extracting any number of times.
##   `channels` — per target instance, the single replaceable enchantment and how
##                many treatments that target has already received.
##   `reforges` — per target instance, how many reforges it has received. Kept
##                as its own counter rather than read off the instance, because
##                the escalating cost and the cap are about ATTEMPTS, and an
##                attempt that produced the same affix still cost material.
##   `requests` — committed enchantment request ids, so a repeated callback or a
##                load-then-click cannot double-apply or double-charge.

const STATE_KEY := &"socket_state"
const VERSION := 1
## How many replaced option ids one instance keeps as an audit trail. An upper
## bound rather than a growing list: the ledger is persisted per actor, and the
## per-rarity cap already bounds the real count.
const REFORGE_HISTORY_CAP := 8

var data: Dictionary = {}


func _init(payload: Dictionary = {}) -> void:
	data = SocketLedger.migrate(payload)


## Bring any stored payload up to the current shape. A payload with no version
## at all (a legacy save, or no socket state ever written) loads as empty state
## rather than failing.
static func migrate(payload: Dictionary) -> Dictionary:
	if payload.is_empty():
		return SocketLedger.empty()
	var version := int(payload.get("version", 0))
	if version < 1:
		payload = payload.duplicate(true)
		payload["version"] = VERSION
	for section in ["parents", "channels", "reforges", "requests"]:
		if not payload.get(section) is Dictionary:
			payload[section] = {}
	payload["parents"] = _migrate_parents(payload["parents"])
	payload["channels"] = _migrate_channels(payload["channels"])
	payload["reforges"] = _migrate_reforges(payload["reforges"])
	return payload


static func empty() -> Dictionary:
	return {"version": VERSION, "parents": {}, "channels": {}, "reforges": {}, "requests": {}}


func to_dict() -> Dictionary:
	return data.duplicate(true)


## Copy the current payload onto the actor. Called after every mutation, so the
## persisted state can never lag the live one.
func commit(actor: Actor) -> void:
	if actor != null:
		actor.set_module_data(SocketLedger.STATE_KEY, data.duplicate(true))


func parent_ids() -> Array:
	return data["parents"].keys()


## The stored entry for one owning instance, or an empty dictionary.
func parent(parent_id: StringName) -> Dictionary:
	var entry: Dictionary = data["parents"].get(String(parent_id), {})
	return entry


## The stored entry for one owning instance, creating it when absent.
func ensure_parent(parent_id: StringName, def_id: StringName) -> Dictionary:
	var key := String(parent_id)
	if not data["parents"].has(key):
		data["parents"][key] = {"def_id": String(def_id), "slots": []}
	var entry: Dictionary = data["parents"][key]
	entry["slots"] = entry.get("slots", [])
	return entry


func drop_parent(parent_id: StringName) -> void:
	data["parents"].erase(String(parent_id))


## One slot's stored entry, or an empty dictionary when the index is beyond what
## this item currently carries.
func slot(parent_id: StringName, index: int) -> Dictionary:
	var slots: Array = parent(parent_id).get("slots", [])
	if index < 0 or index >= slots.size():
		return {}
	var entry: Dictionary = slots[index]
	return entry if entry is Dictionary else {}


func append_slot(parent_id: StringName, kind: StringName) -> Dictionary:
	var entry := ensure_parent(parent_id, &"")
	var slot_entry := {
		"index": entry["slots"].size(),
		"kind": String(kind),
		"imputed": [],
		"gem": {},
		"gem_effects": []
	}
	entry["slots"].append(slot_entry)
	return slot_entry


## Append effects to a slot's own imputed set, bounded by the slot's imprint cap.
func add_imputed(parent_id: StringName, index: int, effects: Array[Dictionary]) -> void:
	var slots: Array = ensure_parent(parent_id, &"")["slots"]
	if index < 0 or index >= slots.size():
		return
	var imputed: Array = slots[index].get("imputed", [])
	for effect in effects:
		imputed.append(effect.duplicate(true))
	slots[index]["imputed"] = imputed


## Record the gem sitting in a slot. The realized effects travel with it: the
## slot then answers "what does this gem contribute" without re-resolving
## anything, so the answer is identical before and after a save/load round trip
## and is never rerolled.
func set_gem(parent_id: StringName, index: int, gem: Dictionary, effects: Array) -> void:
	var slots: Array = ensure_parent(parent_id, &"")["slots"]
	if index < 0 or index >= slots.size():
		return
	slots[index]["gem"] = gem.duplicate(true)
	slots[index]["gem_effects"] = effects.duplicate(true)


## The enchantment channel for one target, or an empty dictionary when the
## target has never been treated. Read-only: a preview must never write state.
func channel(target_id: StringName) -> Dictionary:
	var entry: Dictionary = data["channels"].get(String(target_id), {})
	return entry


## The enchantment channel for one target, creating it when absent. Only a commit
## may create one. `generation` counts every treatment the target has ever
## received, which is what an exhausted cap is measured against.
func ensure_channel(target_id: StringName) -> Dictionary:
	var key := String(target_id)
	if not data["channels"].has(key):
		data["channels"][key] = {"generation": 0, "effect": {}, "reagent_id": ""}
	var entry: Dictionary = data["channels"][key]
	entry["generation"] = int(entry.get("generation", 0))
	if not entry.get("effect") is Dictionary:
		entry["effect"] = {}
	return entry


## Every instance this ledger has ever contributed through: an item carrying
## sockets, or an item carrying an enchantment. `SocketEffects` clears whatever
## is in this set and no longer worn, which is what stops an enchantment on an
## item with no slots from outliving its unequip.
func touched_ids() -> Array:
	var out := {}
	for parent_id in data["parents"].keys():
		out[String(parent_id)] = true
	for target_id in data["channels"].keys():
		out[String(target_id)] = true
	return out.keys()


## How many reforges `target_id` has received. Read by the escalating cost and by
## the cap, so a restored ledger prices the next attempt exactly as the live one
## did — a save/load round trip must never hand back the cheap first attempt.
func reforge_count(target_id: StringName) -> int:
	if target_id == &"":
		return 0
	var entry = data["reforges"].get(String(target_id), {})
	return maxi(0, int(entry.get("attempts", 0))) if entry is Dictionary else 0


## Record one reforge against `target_id` and report the new attempt count. Only
## a commit may call this: a preview is not an attempt and costs nothing.
func record_reforge(target_id: StringName, option_id: StringName) -> int:
	if target_id == &"":
		return 0
	var key := String(target_id)
	var entry: Dictionary = data["reforges"].get(key, {"attempts": 0, "replaced": []})
	entry["attempts"] = int(entry.get("attempts", 0)) + 1
	var replaced: Array = entry.get("replaced", [])
	# Bounded by the cap the policy allows, so this list cannot grow without limit.
	# It is the audit trail of what an investment spent, not the rollback source:
	# the replaced effect is also carried by the result each request recorded.
	if replaced.size() < REFORGE_HISTORY_CAP:
		replaced.append(String(option_id))
	entry["replaced"] = replaced
	data["reforges"][key] = entry
	return int(entry["attempts"])


## A committed enchantment request, or an empty dictionary.
func request(request_id: StringName) -> Dictionary:
	if request_id == &"":
		return {}
	var entry: Dictionary = data["requests"].get(String(request_id), {})
	return entry if entry is Dictionary else {}


## Remember a committed request with its result, so replaying the same request
## replays the same answer without consuming anything.
func record_request(request_id: StringName, result: Dictionary) -> void:
	if request_id != &"":
		data["requests"][String(request_id)] = result.duplicate(true)


static func _migrate_parents(parents: Dictionary) -> Dictionary:
	var out := {}
	for key in parents.keys():
		var entry: Dictionary = parents[key]
		if not entry is Dictionary:
			continue
		var slots: Array = []
		for raw in entry.get("slots", []):
			if not raw is Dictionary:
				continue
			var slot_entry: Dictionary = raw
			slot_entry["index"] = slots.size()
			slot_entry["kind"] = String(slot_entry.get("kind", SocketPolicy.KIND_ANY))
			if not slot_entry.get("imputed") is Array:
				slot_entry["imputed"] = []
			if not slot_entry.get("gem") is Dictionary:
				slot_entry["gem"] = {}
			if not slot_entry.get("gem_effects") is Array:
				slot_entry["gem_effects"] = []
			slots.append(slot_entry)
		out[String(key)] = {"def_id": String(entry.get("def_id", "")), "slots": slots}
	return out


static func _migrate_reforges(reforges: Dictionary) -> Dictionary:
	var out := {}
	for key in reforges.keys():
		var entry = reforges[key]
		if not entry is Dictionary:
			continue
		var replaced: Array = []
		for option_id in entry.get("replaced", []):
			if not replaced.has(option_id):
				replaced.append(option_id)
		out[String(key)] = {
			"attempts": maxi(0, int(entry.get("attempts", 0))),
			"replaced": replaced.slice(0, REFORGE_HISTORY_CAP),
		}
	return out


static func _migrate_channels(channels: Dictionary) -> Dictionary:
	var out := {}
	for key in channels.keys():
		var entry: Dictionary = channels[key]
		if not entry is Dictionary:
			continue
		var effect = entry.get("effect", {})
		out[String(key)] = {
			"generation": int(entry.get("generation", 0)),
			"effect": effect.duplicate(true) if effect is Dictionary else {},
			"reagent_id": String(entry.get("reagent_id", "")),
		}
	return out
