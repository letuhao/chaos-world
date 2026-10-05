class_name TechniqueSlots
extends RefCounted

## The limited, path-typed binding from codex to actor (ADR 0053). Observable.
##
## Slots are typed by PATH, not one flat pool: a fixed small count per path, plus
## a universal pool that grows one per realm tier. A loadout is therefore a
## statement about which path is being bet on, and every learned technique is an
## implicit argument for retiring another.
##
## The published budget:
##
##   | Tier         | realms | qi | body | mind | universal | total |
##   | Mortal       | 1-9    | 3  | 2    | 2    | 0         | 7     |
##   | Spirit       | 10-18  | 3  | 2    | 2    | 1         | 8     |
##   | Immortal     | 19-27  | 3  | 2    | 2    | 2         | 9     |
##   | Transcendent | 28-30  | 3  | 2    | 2    | 3         | 10    |
##
## Per-path counts are fixed for the whole ladder; only the universal pool grows.
## The tier comes from `RealmDefaults.ladder().tier_of()`, never from a ladder index,
## so an inserted realm cannot shift every actor below it onto the wrong count.
##
## A SHARED technique takes a UNIVERSAL slot and never a path slot, so spending one
## is a real cost against path depth. A DUAL technique takes a slot on EACH of its
## two paths, because it commits both (ADR 0059).

signal changed

## The persisted snapshot version. A binding is a plain `{slot_key, id}` pair —
## no authored definition travels with it (ADR 0056), so a designer retuning a
## technique cannot rewrite an existing save.
const VERSION := 1

## The universal pool's name. Every SHARED technique draws from it, and it is
## the only kind of slot a SHARED technique may take. It is a POOL, not a key:
## a key is `slot_key(UNIVERSAL, index)`.
const UNIVERSAL := &"universal"
const SLOT_PATH := &"slot_path"

## technique_id -> the slot key it occupies. A key is `slot_key(kind, index)`,
## e.g. `slot_path_qi_cultivation0`; how many of each exist is the tier's budget,
## never this table.
var _slots: Dictionary = {}

## Every technique id this table has EVER had bound, whether or not it is bound now.
##
## `rebuild` needs the difference between "is bound" and "was ever bound": a
## contribution left behind by a binding that vanished without passing through
## `unequip` has no other discoverable owner, because the modifier source tag is
## namespaced per technique and `ActorStats` can only remove a source it is handed
## the name of (DEF-0152). Tracked here rather than recomputed, because nothing
## outside this module can enumerate the `technique:` prefix on `ActorStats`.
var _applied: Array[StringName] = []


## Restored bindings, `payload["bindings"]` as a list of `{"slot", "id"}` rows.
##
## WITHOUT this, every equipped binding is lost on a reload while the codex and the
## cooldowns survive: the three states are meant to be equally persistent, and a
## save that keeps the technique but drops the loadout quietly empties the build.
func _init(payload: Dictionary = {}) -> void:
	for row in payload.get("bindings", []):
		if not row is Dictionary:
			continue
		var slot_key := StringName((row as Dictionary).get("slot", ""))
		var technique_id := StringName((row as Dictionary).get("id", ""))
		if slot_key == &"" or technique_id == &"":
			continue
		_slots[slot_key] = technique_id
	for technique_id in payload.get("applied", []):
		note_applied(StringName(technique_id))


## The bindings as a versioned payload, safe to write into an actor's module data.
##
## The `applied` record travels with them: a loadout restored with fewer bindings than
## the actor was running needs to know what to clear, and that list only exists here
## (DEF-0152).
func to_dict() -> Dictionary:
	var bindings: Array = []
	for slot_key in _slots:
		bindings.append({"slot": String(slot_key), "id": String(_slots[slot_key])})
	bindings.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return String(a["slot"]) < String(b["slot"])
	)
	var applied: Array = []
	for technique_id in _applied:
		applied.append(String(technique_id))
	return {"version": VERSION, "bindings": bindings, "applied": applied}


## Slot key for one path's slot 0. Most callers want an arbitrary free slot and
## should go through `_first_free_of` instead; this is here for keys that name a
## pool in a message.
static func path_key(path_id: StringName) -> StringName:
	return StringName("%s_%s" % [SLOT_PATH, path_id])


## Whether `def` may only occupy a universal slot. Null and shared both do: a
## technique with no known path has nothing to be exclusive to.
static func requires_universal(def: TechniqueDef) -> bool:
	return def == null or def.is_shared()


## Every slot key tier `tier` grants, in allocation order: the three path pools
## first, then the universal ones. Allocation within a kind is first-come, so this
## order decides only which of two equally-legal candidates wins.
##
## Each key is DISTINCT. A path with three slots yields three keys, not the same key
## three times: the slot table is a Dictionary, so a repeated key collapses into one
## entry and the pool silently holds one slot instead of three. That showed up as
## `no_free_slot` on the second of two qi techniques and looked like a budget bug.
static func slot_keys(tier: int) -> Array[StringName]:
	var budget := TechniquePolicy.slot_budget(tier)
	var out: Array[StringName] = []
	for path_id in PathState.ALL:
		for index in int(budget[path_id]):
			out.append(slot_key(path_id, index))
	for index in int(budget[UNIVERSAL]):
		out.append(slot_key(UNIVERSAL, index))
	return out


## One slot key: its pool and its index within that pool. The index is part of
## the key, so a pool's slots are individually addressable and individually free.
##
## `<SLOT_PATH><kind><index>`. `SLOT_PATH` already ends in `_`, so the kind needs
## no second separator and stays recoverable by taking everything up to the final
## digit run.
static func slot_key(kind: StringName, index: int) -> StringName:
	return StringName("%s%s%d" % [SLOT_PATH, String(kind), index])


## The pool a slot key belongs to: a path id, or `UNIVERSAL`.
##
## Only the trailing DIGITS are stripped. Path ids contain underscores themselves
## (`qi_cultivation`) and the universal pool name ends in a letter, so trimming the
## digit run is unambiguous — whereas scanning for the last `_` cut
## `qi_cultivation` down to `i`, and then every pool matched nothing and every equip
## refused with `no_free_slot`.
static func kind_of(slot_key: StringName) -> StringName:
	var text := String(slot_key)
	if not text.begins_with(String(SLOT_PATH)):
		return UNIVERSAL
	var tail := text.substr(String(SLOT_PATH).length())
	var cut := tail.length()
	while cut > 0 and tail[cut - 1] >= "0" and tail[cut - 1] <= "9":
		cut -= 1
	return StringName(tail.substr(0, cut))


## Every occupied slot, keyed by slot key. A defensive copy, so a caller cannot
## reach in and corrupt the binding.
func all() -> Dictionary:
	return _slots.duplicate()


## The technique id occupying `slot_key`, or an empty string.
func equipped_at(slot_key: StringName) -> StringName:
	return _slots.get(slot_key, &"")


## Whether `technique_id` is equipped right now.
func is_equipped(technique_id: StringName) -> bool:
	return _slots.values().has(technique_id)


## Record that `technique_id` was bound, so a later rebuild can find and clear it.
func note_applied(technique_id: StringName) -> void:
	if technique_id != &"" and not _applied.has(technique_id):
		_applied.append(technique_id)


## Forget a technique's applied record once nothing can be left behind for it.
func forget_applied(technique_id: StringName) -> void:
	_applied.erase(technique_id)


## The applied record, for a rebuild sweep.
func applied_ids() -> Array[StringName]:
	return _applied.duplicate()


## Every technique id that is actually bound, each ONCE, in tier key order
## followed by anything bound outside it.
##
## Walking only `slot_keys(tier)` looks equivalent but is not: a binding taken while
## the actor was a higher tier (a universal slot, or any pool that later shrinks)
## is absent from that list, so `rebuild` never visited it and its modifiers stayed
## on the actor for good — the inverse of the suspension rule, which does have an
## explicit clear path (DEF-0152). The tier decides ORDER and the budget for a NEW
## claim; it does not decide what is already bound.
func equipped(tier: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var seen := {}
	for slot_key in TechniqueSlots.slot_keys(tier):
		# `Dictionary.get` returns a Variant, so the id is narrowed explicitly;
		# inferred straight into `:=` it is an untyped inference, which this
		# project treats as an error.
		var technique_id := StringName(_slots.get(slot_key, &""))
		if technique_id != &"" and not seen.has(technique_id):
			seen[technique_id] = true
			out.append(technique_id)
	# Anything bound outside the published keys: still equipped, still owing a
	# rebuild, and still occupying a slot this tier no longer grants.
	for slot_key in _slots:
		var technique_id := StringName(_slots[slot_key])
		if technique_id != &"" and not seen.has(technique_id):
			seen[technique_id] = true
			out.append(technique_id)
	return out


## Every slot `def` would occupy at `tier` — one for a SHARED or path-exclusive
## technique, two for a DUAL one. Empty when the budget cannot hold the whole
## claim, because a DUAL technique is never half-placed.
func claimable(tier: int, def: TechniqueDef) -> Array[StringName]:
	var out: Array[StringName] = []
	if TechniqueSlots.requires_universal(def):
		var universal_slot := _first_free_of(tier, UNIVERSAL)
		# Built through the typed array rather than an `[slot]` literal: an array
		# literal is untyped `Array`, and returning one where `Array[StringName]` is
		# declared is a runtime type error, not a compile-time one.
		var claim: Array[StringName] = []
		if universal_slot != &"":
			claim.append(universal_slot)
		return claim
	for path_id in def.path_ids():
		var slot := _first_free_of(tier, path_id)
		if slot == &"":
			return []
		out.append(slot)
	return out


## Free slots in one pool at `tier`, from what is actually occupied rather than
## from the budget restated a third time.
func free_of(tier: int, kind: StringName) -> int:
	var free := 0
	for slot_key in TechniqueSlots.slot_keys(tier):
		if TechniqueSlots.kind_of(slot_key) == kind and _slots.get(slot_key, &"") == &"":
			free += 1
	return free


## Whether every slot in `slot_keys` is free, so a bind is legal. Checked in full
## BEFORE anything moves, which is what makes a refused equip change nothing.
func can_bind(slot_keys: Array[StringName]) -> bool:
	if slot_keys.is_empty():
		return false
	for slot_key in slot_keys:
		if _slots.get(slot_key, &"") != &"":
			return false
	return true


## Bind a technique into `slot_keys`. Re-binding an already-equipped technique
## releases its previous slots first, so one technique can never hold two.
func bind(technique_id: StringName, slot_keys: Array[StringName]) -> bool:
	if technique_id == &"" or slot_keys.is_empty():
		return false
	unequip(technique_id)
	for slot_key in slot_keys:
		_slots[slot_key] = technique_id
	note_applied(technique_id)
	changed.emit()
	return true


## Release a technique's binding. Returns the slot keys it held, empty when it was
## not equipped. Free, non-destructive and reversible: the entry is still in the
## codex, which is the whole of ADR 0053's "losing a slot never loses the
## technique".
func unequip(technique_id: StringName) -> Array[StringName]:
	var freed: Array[StringName] = []
	for slot_key in _slots.keys():
		if _slots[slot_key] == technique_id:
			freed.append(slot_key)
	for slot_key in freed:
		_slots.erase(slot_key)
	if freed.is_empty():
		return freed
	changed.emit()
	return freed


func clear() -> void:
	if _slots.is_empty():
		return
	_slots.clear()
	changed.emit()


func _first_free_of(tier: int, kind: StringName) -> StringName:
	for slot_key in TechniqueSlots.slot_keys(tier):
		if TechniqueSlots.kind_of(slot_key) != kind:
			continue
		if _slots.get(slot_key, &"") == &"":
			return slot_key
	return &""
