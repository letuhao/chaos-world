class_name DeclarationBlock
extends RefCounted

## Parse and validate ONE mod declaration block (ADR 0275).
##
## ## Why this is separate from the SEAM that receives it
##
## `RegistrationContext` is the locked registration surface: five seams plus
## `declare_stats`, and it RECORDS what it is given. This file DECIDES whether
## what it is given is legal, and it decides it without touching the ctx — which
## is what makes [method parse] a pure function of `(block, mod_id)`. Three
## consequences, all of them the reason for the split:
##
## - A refused block leaves NO partial state behind, because nothing was written
##   until every row had passed. A seam that recorded as it validated would leave
##   half a mod registered when the third row was bad, and there is no rollback
##   verb in a locked surface.
## - The rules are readable in one place and testable without a ctx, so the
##   refusals can be pinned by name rather than inferred from a boot.
## - `rules.LINE_BUDGET` does not read the seam as a file with three reasons to
##   change.
##
## ## ONE block, TWO arrays
##
## `{stats: [{id, op, resource, zero_baseline}], resources: [{id}]}` beside
## `mod.json`. The split is not taste. A `stats[]` row's `resource` is a
## REFERENCE, so the vocabulary it resolves against has to be declared somewhere
## that is not the reference itself: with one array, naming `raeg` in a `resource`
## field would DECLARE it and the typo would pass. With two, the closed set is
## `resources[]` ∪ `DeclarationVocabulary.core_resource_ids()`, so a mod brings
## its own pools — the `CultivationPathDef.resource_ids` answer, in JSON — and a
## typo is refused.
##
## ## Every refusal NAMES the mod AND the bad id
##
## ADR 0184 d9 wants a loud exemption rather than a silent pass, and a message is
## only actionable if it answers both questions the author has. `'raeg' reads
## resource 'raeg'…` naming the mod, the row and the id is one line to act on; a
## bare reason code sends them back to grep.
##
## ## Closed key sets
##
## A row carrying a key outside [constant STAT_KEYS] is refused, not ignored. The
## defect being closed here is a declaration field that reads as working and does
## nothing, and a silently-ignored `resorce` is the same defect one level down.

## Every key a `stats[]` row may carry.
const STAT_KEYS: Array[String] = ["id", "op", "resource", "zero_baseline"]

## Every key a `resources[]` row may carry.
const RESOURCE_KEYS: Array[String] = ["id"]

## The closed set of reasons [method parse] refuses with. Names, not prose, for
## the reason `DoctrineRule.REASONS` is: a screen, a test and a log line all
## compare them. Extending this set is an ADR.
const BAD_BLOCK := "bad_block"
const BAD_ROW := "bad_row"
const UNKNOWN_KEY := "unknown_key"
const BAD_ID := "bad_id"
const UNKNOWN_STAT := "unknown_stat"
const BAD_OP := "bad_op"
const UNKNOWN_OP := "unknown_op"
const BAD_RESOURCE := "bad_resource"
const UNKNOWN_RESOURCE := "unknown_resource"
const BAD_ZERO_BASELINE := "bad_zero_baseline"
const ZERO_BASELINE_WITHOUT_RESOURCE := "zero_baseline_without_resource"
const UNKNOWN_VOCABULARY := "unknown_vocabulary"

## Every reason above as one list, so a caller that must VALIDATE a refusal reads
## the set rather than keeping a second copy — the decay BL-0619 is about.
const REASONS: Array[String] = [
	BAD_BLOCK,
	BAD_ROW,
	UNKNOWN_KEY,
	BAD_ID,
	UNKNOWN_STAT,
	BAD_OP,
	UNKNOWN_OP,
	BAD_RESOURCE,
	UNKNOWN_RESOURCE,
	BAD_ZERO_BASELINE,
	ZERO_BASELINE_WITHOUT_RESOURCE,
	UNKNOWN_VOCABULARY,
]

## Why an absent pool is a refusal rather than a free `0.0`: `Actor.resource` on an
## id no pool carries returns null, `ensure_resources` will mint a pool for ANY
## id, and a typo'd pool therefore reaches its read site as a silent `0.0` — a
## System whose whole economy is one pool, paying nothing and granting nothing,
## with nothing in the log. `DoctrineRule.UNDECLARED_POOL` does not catch it,
## because that reason catches a System spending a pool it did not itself DECLARE,
## which is a different question from whether the id exists at all.
const RESOURCE_HINT := "LOC_MODS_A31A8D2FC5"


## Parse `block` as `mod_id`'s declaration. Returns
## `{ok, reason, detail, stats, resource_ids, refusals}`:
##   stats: Array[{mod_id, id, op, resource, zero_baseline}] — accepted, normalised
##   resource_ids: Array[String] — the pools this mod brings, declaration order
##   refusals: Array[{mod_id, reason, detail}] — EVERY offender, not just the first
##
## `ok` is true only when nothing was refused. Pure in `(block, mod_id)`: it reads
## no file, touches no ctx, and calls no clock, so the same block yields the same
## answer on every boot — which is what makes the refusals assertable at all.
##
## The two lists come back UNTYPED on purpose, and the caller converts them. A
## `Dictionary` value reads back as an untyped `Array` whatever it held, so a helper
## returning `Array[StringName]` inside one would deliver an `Array` and fail at the
## assignment — `RegistrationContext.declare_stats` says so where it does the copy.
static func parse(block: Dictionary, mod_id: String) -> Dictionary:
	var state := _new_state(mod_id)
	var resources := _read_resources(block, state)
	var stats := _read_stats(block, resources, state)
	_refuse_unreadable_block(block, state)
	var refused := not (state["refusals"] as Array).is_empty()
	return {
		"ok": not refused,
		"reason": "" if not refused else String((state["refusals"] as Array)[0]["reason"]),
		"detail": "" if not refused else String((state["refusals"] as Array)[0]["detail"]),
		"stats": stats,
		"resource_ids": (resources as Dictionary).keys(),
		"refusals": state["refusals"],
	}


## The refusal reasons this parser can produce, as a copy — so a caller asserting
## on a reason has one spelling of the set rather than a literal of its own.
static func reasons() -> Array[String]:
	return REASONS.duplicate()


static func _new_state(mod_id: String) -> Dictionary:
	return {"mod_id": mod_id, "refusals": []}


## A block carrying neither readable key is refused — UNLESS it carries nothing at all.
## Those are three answers, not two, and collapsing any pair of them is how a gate
## starts passing a file it never read:
##
## - **no file at all** — declares nothing; the reader never opens one (ADR 0083:
##   does-not-exist).
## - **`{}`, or `{"stats": []}`** — declares nothing; an author who wrote the keys
##   and left them empty meant that.
## - **`{"nope": true}`** — a file this parser cannot interpret: a renamed key, or a
##   block authored against a shape that does not exist. Refused, because reading it
##   as "declares nothing" is a gate reporting ok on a tree it never looked at.
##
## Checked AFTER the rows so a row-level refusal keeps its own, more specific, cause:
## the first refusal a reader sees should be the one they can act on most precisely.
## `tools/data.py:_check_block` draws the same three-way line, and the two must not
## drift — a Python finding that a GDScript run would call clean is worse than no gate.
static func _refuse_unreadable_block(block: Dictionary, state: Dictionary) -> void:
	if block.is_empty() or block.has("stats") or block.has("resources"):
		return
	_refuse(
		state,
		BAD_BLOCK,
		(
			(
				"declares neither 'stats' nor 'resources' but carries %s; an EMPTY block "
				% _names(block)
			)
			+ "declares nothing, and this one is not empty"
		)
	)


## The `resources[]` half: `{pool_id: true}`, after each row is an object with a
## non-empty string `id` and no key outside [constant RESOURCE_KEYS].
static func _read_resources(block: Dictionary, state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rows: Variant = block.get("resources", [])
	if typeof(rows) != TYPE_ARRAY:
		_refuse(state, BAD_BLOCK, "'resources' must be an array")
		return out
	# `rows` is the AUTHORED array and this loop appends to `out`, a different
	# container, so it cannot outrun its input (INC-0002). The bound is the array
	# the file supplied, snapshotted by the `for` itself.
	for entry in rows as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			_refuse(state, BAD_ROW, "a 'resources' entry must be an object")
			continue
		var source := entry as Dictionary
		var extra := _extra_key(source, RESOURCE_KEYS)
		if not extra.is_empty():
			_refuse(state, UNKNOWN_KEY, "a 'resources' entry carries unknown key '%s'" % extra)
			continue
		var pool_id := String(source.get("id", ""))
		if pool_id.is_empty():
			_refuse(state, BAD_RESOURCE, "a 'resources' entry needs a non-empty 'id'")
			continue
		out[pool_id] = true
	return out


## The `stats[]` half, checked against `resources` (this mod's own pools) plus the
## pools core owns. A row is accepted whole or refused whole: half a declaration is
## the partial-write shape the class docstring exists to prevent.
##
## ## The vocabulary is checked FIRST, and an unreadable one refuses EVERY row
##
## If `stat_ids()` is empty the reader failed (ADR 0275's "unknown is not empty"),
## and returning the rows unchecked would be a gate that reports ok on a tree it
## never looked at. So this returns one refusal naming the cause and accepts
## nothing — the loud direction, and the same one `tools/data.py:_read_fate_tags`
## forces its callers into.
static func _read_stats(block: Dictionary, resources: Dictionary, state: Dictionary) -> Array:
	var out: Array = []
	if DeclarationVocabulary.stat_ids().is_empty():
		_refuse(
			state,
			UNKNOWN_VOCABULARY,
			"no stat id could be read from contracts/stat.gd, so none can be checked"
		)
		return out
	var rows: Variant = block.get("stats", [])
	if typeof(rows) != TYPE_ARRAY:
		_refuse(state, BAD_BLOCK, "'stats' must be an array")
		return out
	for entry in rows as Array:
		var accepted := _check_stat_row(entry, resources, state)
		if not accepted.is_empty():
			out.append(accepted)
	return out


## One row's verdict: `{}` when refused (the refusal is already recorded, naming
## this mod and the bad id) and the normalised row when it is legal. Every
## offending branch RETURNS, so there is no fall-through that could accept a row it
## has just refused.
static func _check_stat_row(entry: Variant, resources: Dictionary, state: Dictionary) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		_refuse(state, BAD_ROW, "a 'stats' entry must be an object")
		return {}
	var source := entry as Dictionary
	var extra := _extra_key(source, STAT_KEYS)
	if not extra.is_empty():
		_refuse(state, UNKNOWN_KEY, "a 'stats' entry carries unknown key '%s'" % extra)
		return {}
	var stat_id := String(source.get("id", ""))
	if stat_id.is_empty():
		_refuse(state, BAD_ID, "a 'stats' entry needs a non-empty 'id'")
		return {}
	if not DeclarationVocabulary.is_stat_id(stat_id):
		_refuse(state, UNKNOWN_STAT, "'%s' is not a stat id contracts/stat.gd declares" % stat_id)
		return {}
	if not source.has("op"):
		_refuse(
			state,
			BAD_OP,
			"'%s' needs an 'op', one of %s" % [stat_id, _names(DeclarationVocabulary.stat_ops())]
		)
		return {}
	var op := String(source.get("op", "")).to_lower()
	if not DeclarationVocabulary.is_stat_op(op):
		_refuse(
			state,
			UNKNOWN_OP,
			"'%s' is not a stat op, one of %s" % [op, _names(DeclarationVocabulary.stat_ops())]
		)
		return {}
	var resource := String(source.get("resource", ""))
	if not _is_known_resource(resource, resources, state):
		return {}
	var zero_baseline: Variant = source.get("zero_baseline", false)
	if typeof(zero_baseline) != TYPE_BOOL:
		_refuse(state, BAD_ZERO_BASELINE, "'%s' has a 'zero_baseline' that is not a bool" % stat_id)
		return {}
	if bool(zero_baseline) and resource.is_empty():
		_refuse(
			state,
			ZERO_BASELINE_WITHOUT_RESOURCE,
			"'%s' declares 'zero_baseline' with no 'resource' to apply it to" % stat_id
		)
		return {}
	return {
		"mod_id": String(state["mod_id"]),
		"id": StringName(stat_id),
		"op": op,
		"resource": StringName(resource),
		"zero_baseline": bool(zero_baseline),
	}


## Whether `resource` is a pool this mod may name. `""` is legal — a stat row with
## no pool is an ordinary flat stat — and everything else must be either in the
## mod's own `resources[]` or in the pools core owns. An unknown id is refused HERE,
## which is the point of the whole seam: the refusal replaces a silent `0.0`.
static func _is_known_resource(resource: String, resources: Dictionary, state: Dictionary) -> bool:
	if resource.is_empty() or (resources as Dictionary).has(resource):
		return true
	if DeclarationVocabulary.is_core_resource(resource):
		return true
	_refuse(
		state,
		UNKNOWN_RESOURCE,
		(
			"'%s' is not a resource this mod declares and no pool core owns it; %s"
			% [resource, L.t(RESOURCE_HINT) % String(state["mod_id"])]
		)
	)
	return false


## The first key of `source` that `allowed` does not name, or `""`. ONE key, not
## all of them: a row with three unknown keys is one typo repeated, and a message
## listing all three teaches the author to read past the first.
static func _extra_key(source: Dictionary, allowed: Array[String]) -> String:
	for key in source:
		if not allowed.has(String(key)):
			return String(key)
	return ""


## Record one refusal against `state`, stamped with the mod that declared it so a
## caller holding several mods' refusals attributes each without a second field.
##
## The mod id is ALSO prefixed onto the detail, and that is deliberate duplication: the
## structured field is what a caller compares, and the prefixed detail is what a human
## reads in a log line. A log line carrying only "'raeg' is not a resource this mod
## declares" names no mod, so a boot with three mods reporting the same typo produces
## three identical lines.
static func _refuse(state: Dictionary, reason: String, detail: String) -> void:
	(
		(state["refusals"] as Array)
		. append(
			{
				"mod_id": String(state["mod_id"]),
				"reason": reason,
				"detail": "%s: %s" % [String(state["mod_id"]), detail],
			}
		)
	)


## The vocabulary as a sorted, comma-joined list, so a refusal prints what WOULD
## have been legal rather than only what was not. Shared by both vocabularies and by
## the unreadable-block message, which needs the same "here is what I looked for"
## shape.
static func _names(vocabulary: Dictionary) -> String:
	var keys: Array[String] = []
	for key in vocabulary:
		keys.append(String(key))
	keys.sort()
	return ", ".join(keys)
