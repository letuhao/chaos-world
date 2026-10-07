class_name DialogueVariables
extends RefCounted

## The typed primitive store a conversation reads and writes (ADR 0862).
##
## ## WHY A TYPE, WHEN JSON HAS NONE
##
## `Actor.to_dict` round-trips a save through JSON, and JSON has no bool and no
## int/float distinction — a `true` comes back as `1.0` and an `int` as a float.
## So every row is stored as `{type, value}` and read back through that declared
## type, exactly as `DomainFixtures._record_of` normalises a trap ledger for the same
## reason. A store that guessed would make `equals: true` on one read and
## `equals: 1.0` on the next, and a gate whose answer changes across a save is worse
## than one that refuses.
##
## ## FOUR TYPES, NAMED
##
## [constant KIND_BOOL] `bool` · [constant KIND_INT] `int` · [constant KIND_FLOAT]
## `float` · [constant KIND_STRING] `String`. Primitives ONLY, so the whole store
## round-trips through `module_data` with no `Vector2`, no `StringName` and no engine
## type anywhere in it — the rule `DomainFixtures`' ledger docblock states and the one
## that makes `Actor.to_dict` the entire save.
##
## The names are `KIND_*` and NOT `TYPE_*` on purpose: `TYPE_BOOL` is Godot's own global
## enum constant (the `Variant.Type` values `typeof()` returns), so a local `TYPE_BOOL`
## SHADOWS it and `typeof(value) == TYPE_BOOL` silently compares an `int` to a `String`.
## That is a compile error Godot reports as "Invalid operands int and String for ==",
## which is exactly how this file was found: nothing loaded the module, so it had never
## been compiled.
##
## `StringName` is NOT a stored type even though the authored keys are `StringName`: a
## `StringName` in a save is a reference the loader resolves by name, so a save written
## on a machine that had interned a different id can disagree with one written
## elsewhere. Keys go in as `String` and come back as `StringName`, and that conversion
## happens at the boundary rather than in the payload.

const MODULE_KEY := &"dialogue_state"
## Where the variable rows live INSIDE `module_data[MODULE_KEY]`, so a save can carry
## the store beside the rest of the conversation state without a second top-level key.
const STATE_KEY := "variables"
const SCHEMA_VERSION := 1

const KIND_BOOL := "bool"
const KIND_INT := "int"
const KIND_FLOAT := "float"
const KIND_STRING := "string"
## CLOSED, so a save carrying an unknown type is refused rather than read as a String
## and quietly compared against a float.
const TYPES: Array[String] = [KIND_BOOL, KIND_INT, KIND_FLOAT, KIND_STRING]

## Rows this store may hold. A conversation cannot grow a save without limit, so a
## store past the cap REFUSES the write and reports it rather than dropping the oldest
## silently — a silently dropped flag is a door that opens forever after.
const MAX_VARIABLES := 64

var _rows: Dictionary = {}


func has(key: StringName) -> bool:
	return _rows.has(String(key))


## The stored value normalised to its DECLARED type, or `null` when the key is absent.
## `null` is the honest answer for "never written" and is why `UNSET` exists as a verb
## separate from `equals`: reading an absent store as `0` is the defect.
func get_value(key: StringName) -> Variant:
	if not _rows.has(String(key)):
		return null
	var kind := String(_rows[String(key)]["type"])
	var raw: Variant = _rows[String(key)]["value"]
	# Read back through the DECLARED type rather than handing the payload out as it
	# arrived, so `1.0` from a JSON bool reads as `true` on every load and not once.
	if kind == KIND_BOOL:
		return _as_bool(raw)
	if kind == KIND_INT:
		return int(raw)
	if kind == KIND_FLOAT:
		return float(raw)
	return String(raw)


## The declared type of `key`, or `""` when absent. Published by the read model so a
## panel can render "you have not told her yet" against "you told her twice" without
## naming a dialogue type.
func type_of(key: StringName) -> String:
	if not _rows.has(String(key)):
		return ""
	return String(_rows[String(key)]["type"])


## Whether `candidate` is the SAME declared type as `key`'s stored value. The check a
## comparison runs first, so a threshold authored as the wrong type refuses by name
## (`type_mismatch`) instead of comparing across types and answering nonsense.
func matches_type(key: StringName, candidate: Variant) -> bool:
	var declared := type_of(key)
	if declared == "":
		return false
	return _type_of_value(candidate) == declared


## The SIGNED comparison of the stored value against `candidate`, in the stored value's
## own type. `< 0` means the stored value is BELOW the candidate, so `at_least` is
## `>= 0`. One function rather than three, so the three verbs cannot disagree about
## which direction "less" is.
##
## Refuses by returning `0` for an absent key or a type mismatch — the same answer as
## equality — because a caller must have run `matches_type` to get here, and a gate
## that asked without checking gets "not met" rather than an exception.
func compare(key: StringName, candidate: Variant) -> int:
	var held: Variant = get_value(key)
	if held == null or not matches_type(key, candidate):
		return 0
	match type_of(key):
		KIND_BOOL, KIND_INT:
			return _sign(int(held) - int(candidate))
		KIND_FLOAT:
			return _sign(float(held) - float(candidate))
		KIND_STRING:
			return _sign(float(String(held).naturalnocasecmp_to(String(candidate))))
	return 0


## Write one variable. Returns `{ok, refusal}`; a refusal is NAMED and is never a
## silent no-op.
##
## ## Refuses rather than overwrites a declared type
##
## A node that writes `bond` as a String after a choice wrote it as an int would leave
## a store whose row has changed shape underneath a condition that was authored against
## the old one. So `STRICT_TYPES` (the default) refuses a mismatch by name, and an
## author who genuinely means to re-declare the type passes `false` deliberately. The
## permissive path exists because a conversation that starts a variable mid-run has no
## earlier row to match — `strict = false` is how an author says so.
func set_value(
	key: StringName, value: Variant, strict: bool = true
) -> Dictionary:
	if key == &"":
		return _answer(false, REFUSAL_NO_KEY)
	var text := String(key)
	var kind := _type_of_value(value)
	if not TYPES.has(kind):
		return _answer(false, REFUSAL_UNSUPPORTED_TYPE)
	if strict and _rows.has(text) and String(_rows[text]["type"]) != kind:
		return _answer(false, REFUSAL_TYPE_MISMATCH)
	if not _rows.has(text) and _rows.size() >= MAX_VARIABLES:
		return _answer(false, REFUSAL_STORE_FULL)
	_rows[text] = {"type": kind, "value": _normalize(kind, value)}
	return _answer(true, "")


## Read the whole store as primitives, SORTED by key text.
##
## The sort is on the TEXT and not on the key itself because `StringName` compares by an
## internal pointer-derived id, so an unsorted list would read in a different order on a
## different machine — `NpcState.npc_ids` records that finding for the roster, and this
## store has the identical property.
func to_dict() -> Dictionary:
	var texts: Array[String] = []
	for key in _rows.keys():
		texts.append(String(key))
	texts.sort()
	var out: Dictionary = {}
	for text in texts:
		out[text] = {"type": String(_rows[text]["type"]), "value": _rows[text]["value"]}
	return out


func count() -> int:
	return _rows.size()


func is_empty() -> bool:
	return _rows.is_empty()


## Every key held, in the same deterministic TEXT order `to_dict` publishes.
func keys() -> Array[StringName]:
	var texts: Array[String] = []
	for key in _rows.keys():
		texts.append(String(key))
	texts.sort()
	var out: Array[StringName] = []
	for text in texts:
		out.append(StringName(text))
	return out


static func from_dict(data: Dictionary) -> DialogueVariables:
	var store := DialogueVariables.new()
	var rows: Variant = data.get(STATE_KEY, {})
	if rows is Dictionary:
		store._absorb(rows as Dictionary)
	return store


## Absorb authored rows. Bounded by [constant MAX_VARIABLES] with the bound SNAPSHOT
## before the walk: the body appends one row per pass, so testing `_rows.size()`
## against the cap would grow in lockstep and never terminate. A save carrying more
## rows than the cap keeps the first `MAX_VARIABLES` in AUTHORED order and reports the
## overflow rather than dropping a row the middle of the file.
func _absorb(rows: Dictionary) -> void:
	var texts: Array[String] = []
	for key in rows.keys():
		texts.append(String(key))
	texts.sort()
	var kept := 0
	var cap := MAX_VARIABLES
	for text in texts:
		if kept >= cap:
			return
		var row: Variant = rows[text]
		if not row is Dictionary:
			continue
		var named := row as Dictionary
		var kind := String(named.get("type", ""))
		if not TYPES.has(kind):
			continue
		_rows[text] = {"type": kind, "value": _normalize(kind, named.get("value", null))}
		kept += 1


## The whole payload the store persists as, nested under the module key so
## `Actor.to_dict` carries it with no bespoke path (ADR 0027).
static func to_payload(store: DialogueVariables) -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		STATE_KEY: {} if store == null else store.to_dict(),
	}


# --- refusals. Named, and every one is an AUTHORING or cap error ---------------

const REFUSAL_NO_KEY := "no_key"
const REFUSAL_UNSUPPORTED_TYPE := "unsupported_type"
const REFUSAL_TYPE_MISMATCH := "type_mismatch"
const REFUSAL_STORE_FULL := "variable_store_full"


# --- internals -----------------------------------------------------------------


## The declared type of a GDScript value, mapping to the four stored types. `null` and
## anything else answer `""`, which is what makes `set_value` refuse rather than
## invent a fifth type.
func _type_of_value(value: Variant) -> String:
	if value == null:
		return ""
	if typeof(value) == TYPE_BOOL:
		return KIND_BOOL
	if typeof(value) == TYPE_INT:
		return KIND_INT
	if typeof(value) == TYPE_FLOAT:
		return KIND_FLOAT
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		return KIND_STRING
	return ""


## Coerce into the DECLARED type. This is the whole point of storing a type: JSON
## hands back `1.0` for `true` and `1` for `1.0`, so the row is normalised on the way
## in and read back through the same type, and the two never disagree.
func _normalize(kind: String, value: Variant) -> Variant:
	match kind:
		KIND_BOOL:
			return _as_bool(value)
		KIND_INT:
			return int(value)
		KIND_FLOAT:
			return float(value)
		KIND_STRING:
			return String(value)
	return null


## A JSON `true` arrives as `1.0` and a JSON `false` as `0.0`, so the threshold is
## "is it non-zero" rather than "is it a bool" — reading `int(value) != 0` is what
## makes a save's `1.0` come back as `true` and not as `false`.
func _as_bool(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	return int(value) != 0


## Three-way comparison to an int, so `compare` has exactly one place that decides what
## "less than" means. `naturalnocasecmp_to` returns a large negative/positive rather
## than -1/1, so normalising here is what makes the three verbs agree on equality.
func _sign(value: float) -> int:
	if value < 0.0:
		return -1
	if value > 0.0:
		return 1
	return 0


static func _answer(ok: bool, refusal: String) -> Dictionary:
	return {"ok": ok, "refusal": refusal}