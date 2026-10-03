class_name TechniqueCodex
extends RefCounted

## One actor's codex: the permanent, unbounded set of techniques they have learned
## (ADR 0053), plus the versioned snapshot core persists.
##
## It is stored in `actor.module_data["technique_state"]` as a plain dictionary, so
## `Actor` carries it without knowing a technique type exists. The payload holds
## `StringName` def ids and mastery rungs, never `TechniqueDef.to_dict()`
## (ADR 0056): a designer retuning a technique must not rewrite every existing
## save, and a `CodexEntry` is a fact about the actor rather than a copy of the
## content.

const STATE_KEY := &"technique_state"
const VERSION := 1

var data: Dictionary = {}


func _init(payload: Dictionary = {}) -> void:
	data = TechniqueCodex.migrate(payload)


## Bring any stored payload up to the current shape. A payload with no version at
## all — a legacy save, or no technique state ever written — loads as an empty
## codex rather than failing. Realized data rides along with the id: it is a fact
## about what the actor actually rolled, so it is never re-rolled on load, only
## the authored definition is never stored.
static func migrate(payload: Dictionary) -> Dictionary:
	# The in-memory shape is always a Dictionary keyed by id, whatever arrives.
	# An empty payload still has to come back as `{}` rather than `[]`: `record`
	# and `row` index it by key, so an Array here silently swallows every write —
	# `learn` would report success and the codex would stay empty.
	var out := {"version": VERSION, "entries": {}}
	for raw in payload.get("entries", []):
		if not raw is Dictionary:
			continue
		var technique_id := StringName((raw as Dictionary).get("id", ""))
		if technique_id == &"":
			continue
		out["entries"][String(technique_id)] = {
			"id": String(technique_id),
			"rung": maxi(0, int((raw as Dictionary).get("rung", 0))),
			"realized": [],
		}
	return out


## The PERSISTED empty shape: a flat Array, because that is what `migrate` reads.
static func empty() -> Dictionary:
	return {"version": VERSION, "entries": []}


## The versioned snapshot as it is persisted. Deliberately id and rung only: the
## realized channel belongs to the instance that rolled it, and this module has no
## second consumer for it, so writing an always-empty array would be a shape that
## lies about holding data.
##
## NOTE the asymmetry, which is deliberate and is the source of the one bug worth
## naming: `data["entries"]` is a Dictionary keyed by id, because `record` writes by
## key and `row` reads by key. The PERSISTED form is a flat Array of row objects,
## because that is what `migrate` reads back and what a save file wants. `empty()`
## therefore returns the persisted shape (an empty Array) and `migrate` converts it
## to the in-memory shape on the way in. Anything that starts life from `empty()`
## and is never passed through `migrate` would hold an Array where a Dictionary is
## required, so every in-memory constructor goes through `_init`.
func to_dict() -> Dictionary:
	var entries: Array = []
	for technique_id in technique_ids():
		var entry: Dictionary = data["entries"][String(technique_id)]
		entries.append({"id": entry["id"], "rung": entry["rung"]})
	return {"version": VERSION, "entries": entries}


## Copy the current snapshot onto the actor. Called after every mutation, so the
## persisted state can never lag the live one.
func commit(actor: Actor) -> void:
	if actor != null:
		actor.set_module_data(TechniqueCodex.STATE_KEY, to_dict())


## The stored row for one technique id, or an empty dictionary.
func row(technique_id: StringName) -> Dictionary:
	var entry: Dictionary = data.get("entries", {}).get(String(technique_id), {})
	return entry if entry is Dictionary else {}


func knows(technique_id: StringName) -> bool:
	return not row(technique_id).is_empty()


## The `CodexEntry` for `technique_id`, or null when the codex does not carry it.
func entry(technique_id: StringName) -> CodexEntry:
	if not knows(technique_id):
		return null
	return CodexEntry.new(technique_id, [], int(row(technique_id).get("rung", 0)))


## Every known technique id, canonically ordered.
func technique_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in data.get("entries", {}).keys():
		out.append(StringName(key))
	out.sort()
	return out


func count() -> int:
	return (data.get("entries", {}) as Dictionary).size()


## Record a technique as known, at rung 0 or higher. Re-learning an entry already
## at a higher rung never lowers it: a duplicate manual is not a mastery loss.
func learn(technique_id: StringName, rung: int = 0) -> void:
	if technique_id == &"":
		return
	var key := String(technique_id)
	var current := int(row(technique_id).get("rung", 0))
	record(technique_id, maxi(current, rung))


## Raise a known technique to `rung`. False when the codex does not carry it or the
## rung would not move, so a caller never pays for a study that taught nothing.
func set_rung(technique_id: StringName, rung: int) -> bool:
	if not knows(technique_id):
		return false
	if int(row(technique_id).get("rung", 0)) >= rung:
		return false
	record(technique_id, maxi(0, rung))
	return true


## A `CodexEntry` for every known technique. Mastery is read here rather than kept
## in a parallel structure, so the rung and the id can never disagree.
func entries() -> Array[CodexEntry]:
	var out: Array[CodexEntry] = []
	for technique_id in technique_ids():
		out.append(entry(technique_id))
	return out


## Records a learned technique at a rung, or raises an existing one's rung.
## Not named `_set`: that is Object's property-assignment virtual, and overriding
## it with a two-argument signature makes the whole class fail to compile.
func record(technique_id: StringName, rung: int) -> void:
	var entries: Dictionary = data.get("entries", {})
	entries[String(technique_id)] = {"id": String(technique_id), "rung": rung}
	data["entries"] = entries
