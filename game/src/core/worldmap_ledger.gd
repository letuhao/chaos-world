class_name WorldmapLedger
extends RefCounted

## The persisted shape of worldmap chunk mutations (ADR 0905).
##
## The generator reproduces every untouched chunk from its seed, so the ONLY
## thing a save must carry is what the player changed: per-chunk overlays of
## `"x,y" -> {"blocked": bool}`. This file owns that shape; `WorldmapStreamer`
## owns the live overlay and moves it here through `export_mutations` /
## `import_mutations` on its own side.
##
## An instance, never a static: the headless runner drives every suite in ONE
## process, so a static ledger would leak one suite's holes into every later
## suite. A store is handed to `SaveApi.install_store` and its state dies with
## the reference the caller holds.
##
## The envelope key is declared HERE as well as in `SaveSlot.WORLD_KEYS`,
## because `modules/save` may not name this file's internals and this file may
## not name `modules/save`. The two are asserted equal by test, not by import.

const WORLD_KEY := "worldmap"

const SCHEMA_VERSION := 1

## The containers this ledger owns. `app/world_ledger_store.gd` routes a key
## by container NAME and may not reach this file's normalizer, so the table is
## authored here and asserted against the store's copy by test. `mutations`
## is what changed; `position` is where the player stood (node + cell) — the
## one fact a resume needs that regeneration cannot answer.
const CONTAINERS: Array[String] = ["mutations", "position"]

## Bounds, not budgets. A mutation overlay grows one entry per destroyed cell,
## so a save that never prunes is a save that grows without a ceiling — the
## same runaway shape as an unbounded log, one dictionary entry at a time.
## Normalization keeps the first entries of the first chunks in sorted order
## and drops the rest, so the same oversized payload answers the same ledger
## on every run. Hitting either cap means the game accepted more destruction
## than the format promises to remember, and the count is what a test asserts.
const MAX_CHUNKS := 256
const MAX_CELLS_PER_CHUNK := 1024

var _ledger: Dictionary = {}


func _init() -> void:
	_ledger = empty()


## The empty ledger. A missing slot, an unreadable payload and this are the
## same value, so "nothing was ever changed" has one spelling, not three.
static func empty() -> Dictionary:
	return normalize_payload({})


## A ledger rebuilt from a saved payload. Normalization is the MIGRATION and
## it is total: chunk ids are strings, cells are `"x,y"` keys with a bool
## `blocked`, and anything else is repaired or dropped — never believed. An
## OLD version folds onto the current shape; a FUTURE version is refused by
## `app/world_ledger_store.gd`, never silently read.
static func normalize_payload(payload: Dictionary) -> Dictionary:
	var raw = payload.get("mutations", {})
	var mutations := {}
	if raw is Dictionary:
		for chunk_id in (raw as Dictionary).keys():
			var cells = (raw as Dictionary).get(chunk_id)
			if not (cells is Dictionary):
				continue
			var kept := {}
			for cell_key in (cells as Dictionary).keys():
				var entry = (cells as Dictionary).get(cell_key)
				if not (entry is Dictionary):
					continue
				var parts := String(cell_key).split(",")
				if parts.size() != 2:
					continue
				if not _is_int(parts[0]) or not _is_int(parts[1]):
					continue
				kept[String(cell_key)] = {
					"blocked": bool((entry as Dictionary).get("blocked", false))
				}
			if not kept.is_empty():
				mutations[String(chunk_id)] = kept
	var sorted_ids := mutations.keys()
	sorted_ids.sort()
	var capped := {}
	for chunk_id in sorted_ids:
		if capped.size() >= MAX_CHUNKS:
			break
		var cells := mutations[chunk_id] as Dictionary
		var sorted_cells := cells.keys()
		sorted_cells.sort()
		var kept_cells := {}
		for cell_key in sorted_cells:
			if kept_cells.size() >= MAX_CELLS_PER_CHUNK:
				break
			kept_cells[cell_key] = cells[cell_key]
		capped[chunk_id] = kept_cells
	return {
		"version": SCHEMA_VERSION, "mutations": capped, "position": _normalize_position(payload)
	}


## The resume point as the disk should carry it: node plus cell, both present
## and well-shaped, or nothing. An absent or malformed position is a new
## arrival, not a corrupt save — the entry row is the honest answer for it.
static func _normalize_position(payload: Dictionary) -> Dictionary:
	var raw = payload.get("position", {})
	if not (raw is Dictionary):
		return {}
	var node := String((raw as Dictionary).get("node", ""))
	var cell := (raw as Dictionary).get("cell", []) as Array
	if node.is_empty() or cell.size() != 2:
		return {}
	if not (str(cell[0]).is_valid_int() and str(cell[1]).is_valid_int()):
		return {}
	return {"node": node, "cell": [int(cell[0]), int(cell[1])]}


## A ledger as the disk should carry it, JSON-safe. String keys, plain bools.
static func to_dict(ledger: Dictionary) -> Dictionary:
	return normalize_payload(ledger)


## How many changed cells `ledger` carries, across all chunks. The one number
## a status line or a cap test wants.
static func mutation_count(ledger: Dictionary) -> int:
	var total := 0
	var mutations = normalize_payload(ledger).get("mutations", {})
	for chunk_id in (mutations as Dictionary).keys():
		total += ((mutations as Dictionary).get(chunk_id) as Dictionary).size()
	return total


## The current ledger, normalized. Returns a copy so a caller cannot mutate
## the store by holding on to what it was handed.
func read_ledger() -> Dictionary:
	return normalize_payload(_ledger)


## The restore path. Takes the whole normalized payload the envelope carried,
## so there is no spelling of "replace one cell" for a caller to reach for.
func write_ledger(ledger: Dictionary) -> void:
	_ledger = normalize_payload(ledger)


static func _is_int(text: String) -> bool:
	return (text as String).is_valid_int()
