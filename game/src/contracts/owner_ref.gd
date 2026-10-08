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
## ## The kind vocabulary is OPEN, and this file does not police it (ADR 0933)
##
## A holder kind is valid when the build has REGISTERED it — a pack's `trading_guild` as
## much as a shipped tier — and the institution registry lives above this leaf layer, so
## membership is decided where the registry IS visible: `OwnerResolver.resolve`, ADR 0097's
## injected seam, which refuses an unregistered kind by name. A copy of that vocabulary
## here would be a second list that can drift; an injected checker would make a value
## object carry process-global state. So this file validates STRUCTURE only — a non-empty
## kind and a non-empty id. `actor` is not special here either: it is special at the
## resolver, which resolves it by id because it is the one kind with no catalog.
##
## ## The three-state vocabulary is load-bearing
##
## An absent holder is `{"vacant": true}` (ADR 0083): the thing exists and its value does
## not. `{}` means there is no thing at all. These are different answers and a screen that
## collapses them cannot render a claim on unowned ground.

## The refusal an empty kind reaches HERE, and the one an unregistered kind reaches at the
## resolver — one rule, one name, written once.
const UNKNOWN_KIND := "unknown_owner_kind"
const VACANT := "vacant"

## The kind of holder. Any non-empty kind on a normalized ref; see the class note.
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


## Build a ref, refusing only a structurally incomplete one: an empty kind names no kind,
## and an empty id names nobody. Membership is NOT checked here — a kind this build does
## not register still builds a ref, and every USE of it refuses by name at
## `OwnerResolver.resolve` (class note). Rejected: defaulting a missing kind to `actor`,
## which would let a sect's holding answer to a player's check.
static func create(kind_value: StringName, id_value: StringName) -> Dictionary:
	if kind_value == &"":
		return {"ok": false, "reason": UNKNOWN_KIND, "kind": String(kind_value)}
	if id_value == &"":
		return {"ok": false, "reason": "unknown_owner", "kind": String(kind_value)}
	return {"ok": true, "reason": "", "owner": new(kind_value, id_value)}


## The ref as a JSON-safe payload. String keys throughout and no `StringName` anywhere:
## `Actor.to_dict` converts only the OUTER `module_data` key, so an inner `StringName` would
## reach the save untouched and break every round trip (ADR 0027).
func to_dict() -> Dictionary:
	return {"kind": String(kind), "id": String(id)}


## Restore from `to_dict`. A kind this build does not register is KEPT, never dropped and
## never coerced: an institution holding ground is a WORLD FACT (ADR 0097), and collapsing
## the ref is how a held node reads as VACANT — free ground for the next claimant, erased
## for good by the next autosave. Keeping it smuggles nothing in, because nothing acts on
## an unresolvable holder: every use refuses by name at the resolver. Contrast
## `clan_state.normalize`, which DROPS an id no def defines — a membership there is acted
## on (it grants recognition), which is the difference.
##
## A corrupt (wrong-typed) field is diagnosed as empty, never aborted: `StringName(42.0)`
## RAISES in GDScript, and a save load that crashes reads as a composition-root bug rather
## than as one bad field (`InstitutionLedger._text` records the same rule).
static func from_dict(data: Variant) -> OwnerRef:
	var ref := OwnerRef.new()
	if not data is Dictionary:
		return ref
	var source := data as Dictionary
	if bool(source.get(VACANT, false)):
		return ref
	var kind_source: Variant = source.get("kind", "")
	var id_source: Variant = source.get("id", "")
	if not (kind_source is String or kind_source is StringName):
		return ref
	if not (id_source is String or id_source is StringName):
		return ref
	var kind_value := StringName(kind_source)
	if kind_value == &"":
		return ref
	ref.kind = kind_value
	ref.id = StringName(id_source)
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
