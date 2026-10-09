class_name InstitutionEnvelope
extends RefCounted

## The ONE claim-envelope normalizer, for any institution kind (ADR 0922).
##
## ## What this owns, and what it deliberately does not
##
## `InstitutionClaim` owns the CLAIM (position, standing, obligation). This owns the
## ENVELOPE around it: the version stamp, the institution and kind ids, the
## standing/cap pair, the applied-grant record, the history trail — and the ONE
## corruption policy every kind shares.
##
## Measured before this file existed: `sect_state.gd`, `clan_state.gd` and
## `nation_state.gd` each carried a `normalize()` body of 100-180 lines, and the three
## disagreed on the ONE question a normalizer exists to answer — what survives an
## unreadable payload. Three answers under one name is the ADR 0066 failure mode, and
## it is why a guild could not be given a normalizer at all: the shape lived inside
## `sect`.
##
## ## The corruption policy, stated once
##
## **Strict where the claim itself is unreadable, lenient where only a neighbour is.**
##
## The id fields and the standing pair ARE the claim. A payload carrying one of them
## as the wrong type is not a ledger with a bad field — it is not a ledger, and
## coercing it would invent a membership and a standing out of bytes. So a wrong-typed
## claim field rejects the WHOLE payload and the member reads as unaffiliated.
##
## Every map beside them is a different case, and the difference is the point: an
## unreadable `obligation`, `fit` or `granted_percent` is one unusable line beside
## three good fields, so it drops THAT line and keeps the member's earned standing.
## Losing standing because an unrelated line went bad is a worse failure than losing
## the line.
##
## ## An absent field is not corruption
##
## Absent is the normal state — a member who holds no position has none, a kind that
## teaches nothing writes no `fit` key. `is_text`/`text` cannot tell absent from
## wrong-typed on their own, so both are asked separately: the type test decides
## corruption, the coercion reads the value.
##
## ## The extension seam, and why it is a TABLE rather than a subclass
##
## A kind's own fields — a doctrine, a rank, a territory claim — are its business, and
## this file may not name them. So a caller hands over a SHAPE: one row per field,
## each naming how to read it. The vocabulary is closed and small, so a new kind
## composes from it rather than adding a branch here.
##
##   - `{kind: "text", default: ""}` — a text id. Wrong type refuses the record.
##   - `{kind: "count", default: 0, cap: 0}` — an int, clamped `[0, cap]`; `cap: 0`
##     means unbounded. Wrong type refuses the record.
##   - `{kind: "ratio", default: 0.0}` — a float map of `{id: float}`. A wrong-typed
##     row is dropped, never the record.
##   - `{kind: "lines", cap: 0, prefix: ""}` — a `{id: int}` map of positive counts,
##     optionally namespaced by a prefix read off another field.
##   - `{kind: "map", row: <Callable>, known: <field name>, limit: 0}` — a map whose
##     rows are normalized by `row`; a row that returns `{}` is dropped. `known` names
##     another field whose value is a `Dictionary` used as a known-content filter.
##   - `{kind: "list", limit: 0}` — a bounded array of dictionaries, copied verbatim.
##   - `{kind: "id_map", known: <field name>}` — a `{id: text}` map, filtered.
##
## A field whose type is not in this vocabulary is a content bug and refuses the
## record by name, never silently skipping — the same policy ADR 0184 gives an unknown
## content family.

## The version stamped on a normalized envelope. One number for every kind, because
## the envelope is one shape; a kind that needs its own migration history keeps it in
## its own extension fields rather than forking this stamp.
const LEDGER_VERSION := 1

## The refusal an extension row reaches when its `kind` is not in the vocabulary.
## Loud rather than skipped: a shape a caller invented is a shape nothing reads.
const R_UNKNOWN_FIELD_KIND := "unknown_field_kind"

## The claim fields, in the order the strict test reads them. Every one must be text
## or absent, and a wrong type refuses the whole record.
const STRICT_TEXT_FIELDS: Array[String] = ["institution", "kind", "position"]
## The claim's numbers. A wrong type refuses the whole record for the reason the class
## note gives: `standing` and `standing_cap` ARE the claim.
const STRICT_COUNT_FIELDS: Array[String] = ["standing", "standing_cap"]

## The envelope keys every kind gets, before its own shape is laid over them.
const BASE_DEFAULTS := {
	"version": LEDGER_VERSION,
	"kind": "",
	"institution": "",
	"position": "",
	"standing": 0,
	"standing_cap": InstitutionClaim.DEFAULT_STANDING_CAP,
	"obligation": {},
	"history": [],
}

## How many history records survive a normalize. ONE number for every kind — the three
## copies this replaces were all 64, and a kind that wants a longer trail is asking for
## a different envelope rather than a longer one.
const HISTORY_LIMIT := 64


## ## The one entry point
##
## `payload` is whatever arrived under the kind's save slot — untrusted, possibly
## absent, possibly a foreign type. `known` is the caller's known-content filter:
## `{field_name: {id: true}}`, consulted by any shape row that names a `known` field.
## An EMPTY filter is an unanswered question and accepts what it is handed, never a
## denial — the rule `destiny` and `race` already follow.
##
## `shape` is the kind's own fields. Returns the canonical envelope, which is always a
## usable dictionary: an unreadable payload reads as the empty envelope, never as an
## error a caller has to branch on. A shape fault is different and IS reported — see
## [method refuse].
static func normalize(
	payload: Variant, known: Dictionary = {}, shape: Dictionary = {}
) -> Dictionary:
	var out := BASE_DEFAULTS.duplicate(true)
	# An absent slot is the normal state, not corruption: a fresh actor has no claim.
	if payload == null or not (payload is Dictionary):
		return out
	var data := payload as Dictionary
	if data.is_empty():
		return out
	# ## Strict first, and it is the WHOLE record that goes
	#
	# `bool` is excluded from the numeric test below on purpose: `int(true)` would
	# disguise a corrupt count as `1`, which is a membership nobody has.
	for key in STRICT_TEXT_FIELDS:
		var text_value = data.get(key, null)
		if text_value != null and not InstitutionLedger.is_text(text_value):
			return BASE_DEFAULTS.duplicate(true)
	for key in STRICT_COUNT_FIELDS:
		var count_value = data.get(key, null)
		if count_value != null and not (count_value is int or count_value is float):
			return BASE_DEFAULTS.duplicate(true)

	out["version"] = int(data.get("version", LEDGER_VERSION))
	out["kind"] = InstitutionLedger.text(data.get("kind", ""), "")
	out["institution"] = InstitutionLedger.text(data.get("institution", ""), "")
	# A position is CONTENT. When the caller supplies a filter, a claim naming a
	# position it does not define is an unaffiliated claim, never a claim with an
	# invented position. Standing survives regardless: a member who earned standing
	# did so even if the seat they held is no longer authored.
	var position := InstitutionLedger.text(data.get("position", ""), "")
	out["position"] = position if _accepts(known, "position", position) else ""
	out["standing_cap"] = maxi(1, int(data.get("standing_cap", InstitutionClaim.DEFAULT_STANDING_CAP)))
	out["standing"] = clampi(int(data.get("standing", 0)), 0, int(out["standing_cap"]))
	out["obligation"] = InstitutionLedger.positive_lines(data.get("obligation", {}) as Dictionary)
	out["history"] = _history(data.get("history", []))

	for field_name in InstitutionLedger.sorted_keys(shape):
		var row = shape[field_name]
		if not (row is Dictionary):
			continue
		var spec: Dictionary = row as Dictionary
		var read_back: Variant = _read_field(spec, data.get(field_name, null), known, out)
	# ## A shape fault refuses the WHOLE record, never one field
	#
	# The shape is the CALLER's own table, so a row naming a kind this
	# vocabulary does not hold is a programming error rather than a player
	# state. Nesting the refusal under its field name would hand back a
	# dictionary that looks like an envelope and carries one inexplicable
	# value inside it — the "plausible payload" ADR 0184's unknown-family
	# policy exists to forbid. So the refusal is the ANSWER.
		if read_back is Dictionary and (read_back as Dictionary).has("ok"):
			var verdict: Dictionary = read_back as Dictionary
			if not bool(verdict.get("ok", true)):
				return verdict
		out[field_name] = read_back
	return out


## Whether `field`'s filter admits `id`. An ABSENT or empty filter is an unanswered
## question and admits everything — the rule the class note states, kept in one place
## so a new shape row cannot invent a second answer.
static func _accepts(known: Dictionary, field: String, id: String) -> bool:
	var filter = known.get(field, null)
	if not (filter is Dictionary) or (filter as Dictionary).is_empty():
		return true
	return (filter as Dictionary).has(id)


## One extension field, read through its own shape row. `out` is passed because a
## `prefix` row reads another field's VALUE to build its namespace, and reading it off
## the payload instead would use a pre-normalization string.
static func _read_field(
	spec: Dictionary, value: Variant, known: Dictionary, out: Dictionary
) -> Variant:
	var kind := InstitutionLedger.text(spec.get("kind", ""), "")
	match kind:
		"text":
			var fallback := InstitutionLedger.text(spec.get("default", ""), "")
			return InstitutionLedger.text(value, fallback)
		"count":
			if value == null:
				return int(spec.get("default", 0))
			if not (value is int or value is float):
				return int(spec.get("default", 0))
			var ceiling := int(spec.get("cap", 0))
			var held := maxi(0, int(value))
			return mini(held, ceiling) if ceiling > 0 else held
		"ratio":
			return _ratio_map(value)
		"lines":
			var lines := InstitutionLedger.positive_lines(
				value as Dictionary if value is Dictionary else {}, 0, int(spec.get("cap", 0))
			)
			var prefix := InstitutionLedger.text(spec.get("prefix", ""), "")
			if prefix == "":
				return lines
			var space := InstitutionLedger.text(out.get(prefix, ""), "")
			return _prefixed_lines(lines, space)
		"id_map":
			return _id_map(value, known, InstitutionLedger.text(spec.get("known", ""), ""))
		"list":
			return _bounded_list(value, int(spec.get("limit", 0)))
		"map":
			return _row_map(spec, value, known, out)
		_:
			# A shape row naming a kind this vocabulary does not hold is a content
			# bug in the CALLER's own table, so it refuses by name rather than
			# reading as an empty field nobody can explain.
			return InstitutionLedger.refuse(R_UNKNOWN_FIELD_KIND)


## A `{id: float}` map. A wrong-typed ROW drops that row and keeps the rest — the
## lenient rule, one level down. Deliberately NOT filtered by known content: a
## projection that applied a value has to be able to take it back, and losing a
## definition is exactly when it would otherwise be stranded.
static func _ratio_map(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	for key in InstitutionLedger.sorted_keys(value as Dictionary):
		if not InstitutionLedger.is_text(key):
			continue
		var entry = (value as Dictionary)[key]
		if entry is float or entry is int:
			out[InstitutionLedger.text(key, "")] = float(entry)
	return out


## A `{id: int}` map of positive lines whose ids must carry `space`. A line
## belonging to some OTHER organization is dropped rather than settled here: two
## organizations share one actor's ledger and neither may touch the other's dues.
static func _prefixed_lines(lines: Dictionary, space: String) -> Dictionary:
	var out: Dictionary = {}
	if space == "":
		return lines
	var prefix := "%s_" % space
	for key in InstitutionLedger.sorted_keys(lines):
		if key.begins_with(prefix):
			out[key] = int(lines[key])
	return out


## A `{id: text}` map, filtered by known content. A non-text key is CORRUPTION, not
## content, so it is dropped rather than coerced — a coerced key would persist an id
## no build defines.
static func _id_map(value: Variant, known: Dictionary, known_field: String) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	for key in InstitutionLedger.sorted_keys(value as Dictionary):
		if not InstitutionLedger.is_text(key):
			continue
		var entry = (value as Dictionary)[key]
		if not (entry is String):
			continue
		var id := InstitutionLedger.text(key, "")
		if _accepts(known, known_field, id):
			out[id] = String(entry)
	return out


## A map whose rows are normalized by the shape's own `row` Callable. A row that
## returns `{}` is dropped whole — the lenient-one-line rule — and `limit` is a
## hand-edited-save guard read BEFORE the loop, never a size of the container being
## built (INC-0002: a bound that grows with the body never terminates).
static func _row_map(
	spec: Dictionary, value: Variant, known: Dictionary, out: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		return result
	var row_fn = spec.get("row", null)
	var limit := int(spec.get("limit", 0))
	var known_field := InstitutionLedger.text(spec.get("known", ""), "")
	# A `for` over a snapshot of the KEYS, filling a NEW dictionary toward a bound
	# taken before the loop: the accepted "fills toward a fixed count" shape.
	for key in InstitutionLedger.sorted_keys(value as Dictionary):
		if limit > 0 and result.size() >= limit:
			break
		if not InstitutionLedger.is_text(key):
			continue
		var id := InstitutionLedger.text(key, "")
		if known_field != "" and not _accepts(known, known_field, id):
			continue
		var entry = (value as Dictionary)[key]
		if not (entry is Dictionary):
			continue
		if not (row_fn is Callable):
			continue
		var row: Variant = (row_fn as Callable).call(entry as Dictionary, out)
		if row is Dictionary and not (row as Dictionary).is_empty():
			result[id] = row
	return result


## A bounded array of dictionaries, copied so a caller cannot mutate the payload
## through the normalized copy.
static func _bounded_list(value: Variant, limit: int) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for record in value as Array:
		if limit > 0 and out.size() >= limit:
			break
		if record is Dictionary:
			out.append((record as Dictionary).duplicate(true))
	return out


## The history trail, bounded by `HISTORY_LIMIT`. A trail rather than an audit log:
## a save must not be able to carry an unbounded one, and the bound is read before the
## loop for the reason [method _row_map] states.
static func _history(value: Variant) -> Array:
	return _bounded_list(value, HISTORY_LIMIT)


## The empty envelope, which is what a fresh actor reads as and what `leave` returns
## to. A named entry point so a caller never spells the defaults a second time.
static func empty(shape: Dictionary = {}) -> Dictionary:
	return normalize({}, {}, shape)


## The envelope as a caller can persist it, with the save-safety question ANSWERED
## rather than hoped for. `InstitutionLedger.is_save_safe` is the checker; this is the
## place a writer asks it, so a `StringName` key or a `Resource` reaching a save is
## caught where the payload is built instead of at load in front of the player.
static func save_ready(payload: Dictionary) -> Dictionary:
	if InstitutionLedger.is_save_safe(payload):
		return InstitutionLedger.ok({"payload": payload})
	return InstitutionLedger.refuse(InstitutionLedger.R_CORRUPT_PAYLOAD)
