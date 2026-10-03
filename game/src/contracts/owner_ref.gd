class_name OwnerRef
extends RefCounted

## One typed reference to whoever holds something (ADR 0097). A value, not an interface:
## four implementations would have to live in `clan`/`sect`/`nation`, and `tools/arch`'s
## bare-reference detector excludes `modules/*`, so the resulting code-only cycle would be
## invisible to the gate. A loud string beats an invisible cycle.
##
## ## Why `contracts/` and not `core/`
##
## Nothing may depend on it except its holder, so it is the leaf layer's business. It is a
## `RefCounted`, not a `Resource`, because it is never an `@export` on a `.tres` — the
## authored node definition names it by `kind` and `id`, never by holding a live reference.
##
## ## The three-state vocabulary is load-bearing
##
## An absent holder is `{"vacant": true}` (ADR 0083): the thing exists and its value does
## not. `{}` means there is no thing at all. These are different answers and a screen that
## collapses them cannot render a claim on unowned ground.

## The closed set of holder kinds. A ref naming anything else refuses closed — an unknown
## kind is a content bug, and defaulting it to `actor` would let a sect's holding answer to
## a player's check.
const KINDS: Array[StringName] = [&"actor", &"clan", &"sect", &"nation"]

const UNKNOWN_KIND := "unknown_owner_kind"
const VACANT := "vacant"

## The kind of holder. Always one of `KINDS` on a normalized ref.
var kind: StringName = &""
## The id of the holder, scoped by `kind`.
var id: StringName = &""


func _init(p_kind: StringName = &"", p_id: StringName = &"") -> void:
	kind = p_kind
	id = p_id


## A holder that exists but has no value, as the payload of an unowned node.
static func vacant() -> Dictionary:
	return {VACANT: true}


## True when `data` names no holder at all.
static func is_vacant(data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).get(VACANT, false) == true


## Build a ref, refusing an unknown kind. `{ok: false, reason: ...}` rather than a
## half-formed ref, so a typo in authored content fails loudly at load instead of
## answering as somebody else.
static func create(kind_value: StringName, id_value: StringName) -> Dictionary:
	if not KINDS.has(kind_value):
		return {"ok": false, "reason": UNKNOWN_KIND, "kind": String(kind_value)}
	if id_value == &"":
		return {"ok": false, "reason": "unknown_owner", "kind": String(kind_value)}
	return {"ok": true, "reason": "", "owner": new(kind_value, id_value)}


## The ref as a JSON-safe payload. String keys throughout and no `StringName` anywhere:
## `Actor.to_dict` converts only the OUTER `module_data` key, so an inner `StringName` would
## reach the save untouched and break every round trip (ADR 0027).
func to_dict() -> Dictionary:
	return {"kind": String(kind), "id": String(id)}


## Restore from `to_dict`. An unknown kind normalizes to the empty ref rather than being
## kept, because a ref that names a holder kind the game does not have cannot be resolved
## by anything and would sit in a ledger forever.
static func from_dict(data: Variant) -> OwnerRef:
	var ref := OwnerRef.new()
	if not data is Dictionary:
		return ref
	var source := data as Dictionary
	if bool(source.get(VACANT, false)):
		return ref
	var kind_value := StringName(source.get("kind", ""))
	if not KINDS.has(kind_value):
		return ref
	ref.kind = kind_value
	ref.id = StringName(source.get("id", ""))
	return ref


## Whether this ref names somebody. An empty ref is the unowned state, which is a real
## answer and not an error.
func is_empty() -> bool:
	return kind == &"" or id == &""


## The stable string key a ledger stores this holder under. Ordered by kind then id so two
## holders never collide and the key is stable across a save round trip.
func storage_key() -> String:
	return "%s:%s" % [String(kind), String(id)]


## Parse a `storage_key` back into a ref.
static func from_storage_key(key: String) -> OwnerRef:
	var parts := key.split(":")
	if parts.size() != 2:
		return OwnerRef.new()
	return from_dict({"kind": parts[0], "id": parts[1]})
