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
const VERSION := 2

var data: Dictionary = {}


func _init(payload: Dictionary = {}) -> void:
	data = TechniqueCodex.migrate(payload)


## Bring any stored payload up to the current shape. A payload with no version at
## all — a legacy save, or no technique state ever written — loads as an empty
## codex rather than failing.
##
## ## The `realized` column, and why v2 exists
##
## `realized` is the manual's MARGIN: the annotations one copy picked up, realized
## once at the learn that stored them and read back verbatim from then on (see
## `TechniqueMarginalia` and ADR 0196). It rides along with the id rather than in a
## column of its own because a save is a flat list of rows and a second keyed map
## would be a second thing that could be written without the first.
##
## **A v1 row migrates to `[]`, not to a roll.** A row written before this column
## existed has no annotations recorded, and there is no seed to replay them from:
## the value the player paid for was never drawn. Filling the gap at load time would
## make every pre-existing save silently stronger or weaker depending on when it
## was opened, and would do it AGAIN on every subsequent load, because nothing in
## a v1 row records that a roll already happened. An absent margin is the honest
## read, and it is stable. A re-learn of the same technique is the deliberate way
## to get a margin onto one — and `learn` never lowers an existing one.
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
			"realized": _marginalia((raw as Dictionary).get("realized", [])),
		}
	return out


## The stored margin, as owned by the entry: primitives in, copies out. A malformed
## row is skipped rather than repaired, because a save is untrusted input and a
## half-written effect that got repaired into a plausible shape would be a value
## nobody rolled.
static func _marginalia(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not raw is Array:
		return out
	for effect in raw as Array:
		if effect is Dictionary:
			out.append((effect as Dictionary).duplicate(true))
	return out


## The PERSISTED empty shape: a flat Array, because that is what `migrate` reads.
static func empty() -> Dictionary:
	return {"version": VERSION, "entries": []}


## The versioned snapshot as it is persisted. Deliberately id, rung and the
## manual's MARGIN, and never a serialized definition (ADR 0056): a designer
## retuning a technique must not rewrite every existing save.
##
## The margin IS written, unlike the always-empty array it used to carry. It is the
## only record of what one copy rolled, so a snapshot that dropped it would make
## every reload re-derive the answer — and a reload that re-derives is how a
## learned technique quietly changes between save and load.
func to_dict() -> Dictionary:
	var entries: Array = []
	for technique_id in technique_ids():
		var entry: Dictionary = data["entries"][String(technique_id)]
		(
			entries
			. append(
				{
					"id": entry["id"],
					"rung": entry["rung"],
					"realized": (entry.get("realized", []) as Array).duplicate(true),
				}
			)
		)
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
##
## The entry is built from the STORED margin, never from a fresh roll: a rebuild,
## an `inspect` and a re-equip all reach this, and a draw here would make the
## contribution of an equipped technique depend on how many times it had been read.
func entry(technique_id: StringName) -> CodexEntry:
	if not knows(technique_id):
		return null
	var stored: Dictionary = row(technique_id)
	return CodexEntry.new(
		technique_id, _marginalia(stored.get("realized", [])), int(stored.get("rung", 0))
	)


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
##
## A margin already on the row is KEPT. A duplicate manual teaches the same
## technique, so the copy the actor already owns still carries the annotations it
## was copied with; a second copy that silently replaced them would make re-reading
## a book a way to gamble an investment. `TechniquesApi.learn` is the deliberate way
## to draw a new margin onto a row that has none.
func learn(technique_id: StringName, rung: int = 0, realized: Array[Dictionary] = []) -> void:
	if technique_id == &"":
		return
	record(technique_id, maxi(int(row(technique_id).get("rung", 0)), rung), realized)


## Raise a known technique to `rung`. False when the codex does not carry it or the
## rung would not move, so a caller never pays for a study that taught nothing.
func set_rung(technique_id: StringName, rung: int) -> bool:
	if not knows(technique_id):
		return false
	var current: Dictionary = row(technique_id)
	if int(current.get("rung", 0)) >= rung:
		return false
	record(technique_id, maxi(0, rung), current.get("realized", []))
	return true


## A `CodexEntry` for every known technique. Mastery is read here rather than kept
## in a parallel structure, so the rung and the id can never disagree.
func entries() -> Array[CodexEntry]:
	var out: Array[CodexEntry] = []
	for technique_id in technique_ids():
		out.append(entry(technique_id))
	return out


## Records a learned technique at a rung with its margin, or raises an existing
## one's rung.
##
## `record` is the ONE writer, and it never lets a caller empty a margin that is
## already there: every mutation reaches this row and a dropped `realized` would be
## a contribution silently reverted to authored values — the player keeps the same
## rung and silently loses the copy they bought.
##
## Not named `_set`: that is Object's property-assignment virtual, and overriding
## it with a two-argument signature makes the whole class fail to compile.
func record(technique_id: StringName, rung: int, realized: Array[Dictionary] = []) -> void:
	var entries: Dictionary = data.get("entries", {})
	var current: Dictionary = entries.get(String(technique_id), {})
	# Typed explicitly rather than inferred: `Dictionary.get` returns a Variant, and
	# a `:=` inferred from one makes the whole class fail to parse at load.
	var margin: Array[Dictionary] = TechniqueCodex._marginalia(realized)
	if margin.is_empty():
		margin = TechniqueCodex._marginalia(current.get("realized", []))
	entries[String(technique_id)] = {
		"id": String(technique_id),
		"rung": rung,
		"realized": margin,
	}
	data["entries"] = entries
