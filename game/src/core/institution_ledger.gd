class_name InstitutionLedger
extends RefCounted

## The ledger machinery every institution shares: the JSON-safe coercion, the refusal
## shape, the ordered-key walk and the two independent writers. `InstitutionClaim` owns
## the CLAIM (position, standing, obligation); this owns the ENVELOPE around it.
##
## ## What is genuinely shared, measured, and what is NOT
##
## Measured across `clan`, `sect`, `nation` and `WorldPolityLedger`, these are
## byte-for-byte or near-identical and belong in one place:
##
##   - `_text(value, fallback)` — `ClanState._text` documents itself as "`sect_state.gd`'s
##     `_text`, carried over unchanged", `SectState._text` is the original, and
##     `WorldPolityLedger._text` is a third copy with a different signature.
##   - `_is_text(value)` — `ClanState._is_text` asks the question `_text` answers by
##     converting, so a normalizer can tell a corrupt field from an absent one.
##   - `_sorted_keys(source)` — `WorldPolityLedger._sorted_keys` and the same walk in
##     `WorldFact.ids`, both stating WHY it is not `sort()` on the raw array: the order
##     is load-bearing, so a hand-edited save folds in the same sequence every run.
##   - `{ok, reason}` — the refusal shape, written out separately in every module.
##
## **What is deliberately NOT shared**, and forcing it would be a wrong abstraction:
##
##   - **`SCHEMA_VERSION`.** Four independent ledgers, four migration histories. One
##     constant would make a bump in `clan` silently re-stamp `nation`.
##   - **`MODULE_KEY`.** Each ledger names its own save slot, and `modules/save` may not
##     name a core class's internals, so the key is declared where the ledger owns it and
##     asserted equal by test, never imported.
##   - **`SOURCE_PREFIX` and its three verbs.** The SHAPE is shared; the prefix is not,
##     and it must not be: a `sect:` modifier reaching a `clan` strip half is the bug the
##     namespace exists to prevent. [method source_tagged] builds the tag from a prefix
##     the CALLER supplies, so the construction lives here and the namespace does not.
##   - **The gate files.** 469 and 407 lines measured: a CLOSED VERB TABLE plus a
##     per-tier unmet model, and the verb sets genuinely differ (`has_rank` and a
##     bloodline hinge against `holds_authority`, `fit_at_least` and a doctrine). The
##     shared half is a RULE, not a function. Left alone.
##   - **The per-tier `normalize()` bodies.** Clan discards the WHOLE record on a
##     wrong-typed id, sect drops entries naming unshipped content, polity folds pair
##     keys: three corruption policies under one name.
##
## ## `_text` exists because a raw `String(...)` cast RAISES at runtime
##
## `String(42.0)` raises in GDScript rather than yielding `"42.0"`. A corrupt save whose
## id field arrived as a number would therefore ABORT the load instead of reading as the
## unaffiliated member it actually is — the exact opposite of the documented rule that an
## unreadable payload is diagnosed as empty. The reader gets a script error and no actor
## rather than a plausible actor, and the failure reads as a crash in the composition
## root rather than a bad field in one save slot. `str()` does not raise, but it turns a
## corrupt field into a plausible-looking id a known-content filter must reject by
## accident. **An explicit type test that falls back is refusal, not coincidence.**
## Kept here because this is the ONE place the reasoning is written, and a copy that
## paraphrases it is how it decays.

## The refusals, authored ONCE as constants and indexed from them. `REASONS` was a
## hand-written table of the same eight strings, which is the ADR 0066 failure mode inside
## the very file that exists to stop it: a reason added to a constant and forgotten in the
## table leaves a caller looking one up by name and getting a silent null.
const R_NO_ACTOR := "no_actor"
const R_UNKNOWN_KIND := "unknown_kind"
const R_UNKNOWN_INSTITUTION := "unknown_institution"
const R_ALREADY_FOUNDED := "already_founded"
const R_NO_TOP_POSITION := "no_top_position"
const R_FOUNDING_COST_UNMET := "founding_cost_unmet"
const R_KIND_CANNOT_BE_FOUNDED := "kind_cannot_be_founded"
## The reason a record that cannot be read is given. Carried on the READ rather than
## thrown, because a corrupt save's correct answer is an absent institution and a
## script error is not.
const R_CORRUPT_PAYLOAD := "corrupt_payload"

## The refusal vocabulary, re-exported so a caller does not have to know which file
## authored the reason it was handed. ADR 0083's THIRD state: `{"ok": false, "reason": R}`
## is a REFUSAL, which is neither `{}` (does not exist) nor a value of `0`.
const REASONS := {
	R_NO_ACTOR: R_NO_ACTOR,
	R_UNKNOWN_KIND: R_UNKNOWN_KIND,
	R_UNKNOWN_INSTITUTION: R_UNKNOWN_INSTITUTION,
	R_ALREADY_FOUNDED: R_ALREADY_FOUNDED,
	R_NO_TOP_POSITION: R_NO_TOP_POSITION,
	R_FOUNDING_COST_UNMET: R_FOUNDING_COST_UNMET,
	R_KIND_CANNOT_BE_FOUNDED: R_KIND_CANNOT_BE_FOUNDED,
	R_CORRUPT_PAYLOAD: R_CORRUPT_PAYLOAD,
}

## How deep [method is_save_safe] will walk before it answers "not save safe".
## Real authored ledgers are two or three levels deep; anything deeper is a
## hand-edited payload, and answering "not save safe" for it is the safe answer rather
## than the deep one. A recursive walk is a `while` in disguise, so
## `test_no_unbounded_wait.gd` cannot see it and a self-referential dictionary would
## recurse until the stack died — the `ContentScan.MAX_DEPTH` reasoning.
const SAVE_SAFE_MAX_DEPTH := 16

## The refusal a promotion reaches on a ledger that names no institution. Distinct from
## a refusal on an unknown position: there is nothing here to be promoted within.
const R_NOT_AN_INSTITUTION := "not_an_institution"
## The refusal a zero-delta standing change reaches. A caller computing a delta of zero
## has a bug, and absorbing it would leave the ledger claiming a move that did not
## happen.
const R_NON_POSITIVE := "non_positive"


## The refusal shape. The ONE place this file builds one, so a caller can tell a
## refusal from an absent value without a second convention: `{}` means "this does not
## exist" and `{"ok": false, "reason": R}` means "this was refused and here is why".
static func refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


## The success shape. `ok` and `reason` are present on EVERY answer so a caller reads one
## key without knowing which verb it called, and `reason` is `""` on success because an
## empty reason and a missing key are a different thing to a panel.
static func ok(extra: Dictionary = {}) -> Dictionary:
	var out := {"ok": true, "reason": ""}
	for key in extra.keys():
		out[String(key)] = extra[key]
	return out


## `value` when it really is text — a `String` or a `StringName` — otherwise `fallback`.
## See the class note for why a raw `String(...)` cast is the wrong tool on a save payload:
## it RAISES on a float rather than yielding text.
static func text(value: Variant, fallback: String = "") -> String:
	if value is String or value is StringName:
		return String(value)
	return fallback


## Whether `value` is genuinely text. The ASK, paired with [method text] which CONVERTS:
## a normalizer needs both, because `text` cannot tell a corrupt field from an absent one
## and those must not be repaired the same way. An absent field is normal — a member who
## holds no position has none — and a present field of the wrong TYPE is corruption.
static func is_text(value: Variant) -> bool:
	return value is String or value is StringName


## The keys of `source`, canonically ordered by their STRING value.
##
## Not `sort()` on the raw array: `Array[StringName].sort()` is not specified to order by
## `StringName`'s string value and the ids are interned, so the result could depend on
## which id loaded first. **The order is load-bearing** — two runs over the same payload
## must fold in the same sequence and persist the same bytes — so a hand-edited save whose
## two spellings of one row disagree produces the SAME winner every time. `WorldFact.ids`
## states the same reason for the same walk.
##
## A `for` over a snapshot building a NEW array: the body never writes to the container
## being walked, so there is no shape here for a loop to grow in lockstep with its bound.
static func sorted_keys(source: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in source.keys():
		out.append(String(key))
	out.sort()
	return out


## A stat/trait source tag under `prefix` for `id`. The shared CONSTRUCTION, with the
## namespace left to the caller — see the class note on why `SOURCE_PREFIX` is
## deliberately not shared. Here so the `%s%s` shape is written once rather than four
## times, and so a caller wanting a namespaced tag does not invent a third spelling.
static func source_tagged(prefix: String, id: StringName) -> StringName:
	if prefix == "" or id == &"":
		return &""
	return StringName("%s%s" % [prefix, String(id)])


## Whether `source` sits under `prefix`. The counterpart of [method source_tagged],
## and the read every strip half of a re-projection needs. `prefix` is the CALLER's,
## so a sect modifier never satisfies a clan's strip.
static func owns_source(prefix: String, source: StringName) -> bool:
	if prefix == "":
		return false
	return String(source).begins_with(prefix)


## Every `key: value` in `rows` whose value is a strictly positive integer, keyed by the
## STRING value of `key`, in canonical key order.
##
## This is the ONE obligation-line shape every institution ledger stores: ids and counts,
## never authored amounts, so retuning a rate never rewrites a save. A line never opened
## and a line settled both come out absent, which is correct — "nobody opened this debt"
## and "this debt is settled" are the same state (`InstitutionClaim.owed` states the rule).
##
## `limit` bounds how many lines survive. **Snapshot the bound BEFORE the loop**, never as
## a size of the container being built: a limit read as `rows.size()` rises in lockstep
## with the body and never terminates (INC-0002). It is a parameter here precisely so it
## cannot become a size.
static func positive_lines(rows: Dictionary, limit: int = 0, cap: int = 0) -> Dictionary:
	var out: Dictionary = {}
	var ceiling := maxi(0, limit)
	# A `for` over a snapshot of the KEYS, filling a NEW dictionary toward a bound taken
	# before the loop: the accepted "fills unconditionally toward a fixed count" shape.
	for key in sorted_keys(rows):
		if ceiling > 0 and out.size() >= ceiling:
			break
		if not (rows[key] is int or rows[key] is float):
			continue
		var count := int(rows[key])
		if cap > 0:
			count = mini(count, cap)
		if count > 0:
			out[String(key)] = count
	return out


## Whether `payload` carries nothing a save cannot round-trip: no `StringName` KEY
## anywhere, no `Resource`, no `Object`, no `Vector2`, no `Array` of them.
##
## `Actor.to_dict` copies `module_data` VERBATIM and converts only the OUTER key, so an
## inner `StringName` key, a `Resource`, an `Actor` or a `Vector2` reaches the save
## untouched and silently breaks every round trip. **No checker in this repo can see it**
## — `tools arch` reads references, not value types, and `JSON.parse_string` fails at
## LOAD time in front of the player rather than at write time in front of the author. So
## the property is a callable, and the test asserts the callable is RED on each of the
## four.
##
## Recursive over dictionaries and arrays, and **depth-capped at
## [constant SAVE_SAFE_MAX_DEPTH]** for the reason `ContentScan` caps at `MAX_DEPTH`: a
## recursive walk is a `while` in disguise, so `test_no_unbounded_wait.gd` cannot see it
## and a self-referential dictionary would recurse until the stack died.
static func is_save_safe(payload: Variant) -> bool:
	return _save_safe(payload, 0)


static func _save_safe(value: Variant, depth: int) -> bool:
	if depth >= SAVE_SAFE_MAX_DEPTH:
		return false
	if value == null:
		return true
	var kind := typeof(value)
	match kind:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		TYPE_STRING_NAME:
			# A `StringName` VALUE is legal — every id in this repo is one in memory
			# and every payload converts it on the way out. It is a `StringName` KEY
			# or a `Resource`/`Object` that is not, and those are the branches below.
			return true
		TYPE_DICTIONARY:
			var row := value as Dictionary
			for key in row.keys():
				if key is StringName:
					return false
				if not _save_safe(row[key], depth + 1):
					return false
			return true
		TYPE_ARRAY:
			var items := value as Array
			# A `for` over the array itself reading only: it appends to nothing and
			# mutates nothing, so it is bounded by the array's own length.
			for item in items:
				if not _save_safe(item, depth + 1):
					return false
			return true
		_:
			# A `Resource`, an `Actor`, a `Vector2`, an `Object` — everything a
			# dictionary can hold that JSON cannot.
			return false


## ## The two writers, and they write different numbers
##
## [method promote] writes `position` and NEVER reads `standing`; [method move_standing]
## writes `standing` and NEVER reads `position`. That is ADR 0064's split carried forward
## by ADR 0083, and it is why they are TWO verbs rather than one `set(field, value)`: a
## single setter takes one field name as data, so nothing in the code would stop it being
## handed the other one. The test asserts both directions separately — a combined check
## would pass a design that had collapsed the pair into one number, because such a design
## has no second number to contradict.


## The institution `ledger` holds, repaired:
## `{ok, reason, exists, corrupt, institution, kind, position, standing, standing_cap,
## holds_position, normalized}`.
##
## `exists` is false for `{}` — ADR 0083's FIRST state, "this does not exist" — and that
## is a DIFFERENT answer from `corrupt`, which means a record was present and could not be
## read. Half a ledger is worse than none, because it silently changes what the player is
## owed, so a wrong-typed id field discards the WHOLE record rather than just itself. An
## ABSENT field is different again and normal: a member who holds no position has none.
##
## Every field is coerced, and a `standing_cap` of zero or less is REPAIRED to at least 1
## for the reason `InstitutionClaim.from_dict` repairs it: a cap that cannot be computed
## reports a normalized ratio of zero and reads as an institution nobody respects.
static func read(ledger: Dictionary) -> Dictionary:
	var out := {
		"ok": true,
		"reason": "",
		"exists": false,
		"corrupt": false,
		"institution": "",
		"kind": "",
		"position": "",
		"standing": 0,
		"standing_cap": 1,
		"holds_position": false,
		"normalized": 0.0,
	}
	if ledger.is_empty():
		return out
	# Checked through `is_text` rather than coerced through `text`, because `text`
	# cannot tell a corrupt field from an absent one and those must not be repaired the
	# same way. `String(42.0)` RAISES in GDScript rather than yielding `"42.0"`, so a
	# cast here would abort the whole load — see the class note.
	for key in ["institution", "kind", "position"]:
		if ledger.has(key) and not is_text(ledger[key]):
			return _corrupt(out)
	for key in ["standing", "standing_cap"]:
		if ledger.has(key) and not (ledger[key] is int or ledger[key] is float):
			return _corrupt(out)
	for key in ["roster", "treasury", "obligation", "fit"]:
		if ledger.has(key) and not (ledger[key] is Dictionary):
			return _corrupt(out)
	var institution := text(ledger.get("institution", ""), "")
	if institution == "":
		# A record naming no institution names nothing, so it is "does not exist"
		# rather than a corrupt row: there is no subject for it to be wrong about.
		return out
	var position := text(ledger.get("position", ""), "")
	out["exists"] = true
	out["institution"] = institution
	out["kind"] = text(ledger.get("kind", ""), "")
	out["position"] = position
	out["holds_position"] = position != ""
	out["standing_cap"] = maxi(
		1, int(ledger.get("standing_cap", InstitutionClaim.DEFAULT_STANDING_CAP))
	)
	out["standing"] = clampi(int(ledger.get("standing", 0)), 0, int(out["standing_cap"]))
	out["normalized"] = float(out["standing"]) / float(out["standing_cap"])
	return out


## `ledger` as a NEW dictionary with `position` set. **The only writer of `position`,
## and it writes only `position`** — never `standing`, never a value derived from it. A
## member holding `t_head` on zero standing is a legitimate character rather than a bug
## (ADR 0064), and a `promote` that "fixed" that would delete the politics.
##
## An empty `position_id` is the legitimate "holds no position at all" state and is
## therefore NOT a refusal. A ledger naming no institution IS refused: there is nothing
## here to be promoted within.
##
## ## The replacement is RETURNED under `"ledger"`, never written into the argument
##
## Every writer here and in `InstitutionFounding` hands its replacement back under
## `"ledger"`, and **none of them mutates the dictionary it was given**. The first version
## of this function built the copy and dropped it, which type-checked perfectly and left
## every caller's ledger untouched: the case written to assert "a promotion moves the
## position" reported that the position had NOT moved, and nothing in that failure
## distinguishes a writer that discards its work from a promotion that does nothing.
## Returning it makes ignoring the result a MISSING KEY rather than a silent no-op — the
## DEF-0310 shape, "an earn site whose participant is a defaulted parameter is a site that
## can wire to nothing and still typecheck".
static func promote(ledger: Dictionary, position_id: StringName) -> Dictionary:
	if not bool(read(ledger)["exists"]):
		return refuse(R_NOT_AN_INSTITUTION)
	var out := ledger.duplicate(true)
	out["position"] = String(position_id)
	return ok({"ledger": out, "position": String(position_id)})


## `ledger` as a NEW dictionary with `standing` moved by `delta`, clamped at zero and
## at the authored cap.
##
## **The only writer of `standing`, and it writes only `standing`** — it never reads
## `position`. Standing can go UP and DOWN: it is earned, so it can be lost, and a
## module that could only raise it would be a favour rather than a standing. The
## applied amount is returned so a caller publishes how much of a requested change
## actually landed instead of assuming it did.
##
## A zero delta is REFUSED rather than absorbed: a caller computing a delta of zero has a
## bug, and absorbing it would leave the ledger claiming a move that did not happen.
## Returned under `"ledger"` for the reason [method promote] states.
static func move_standing(ledger: Dictionary, delta: int) -> Dictionary:
	if not bool(read(ledger)["exists"]):
		return refuse(R_NOT_AN_INSTITUTION)
	if delta == 0:
		return refuse(R_NON_POSITIVE)
	var out := ledger.duplicate(true)
	var read_out := read(out)
	var cap := int(read_out["standing_cap"])
	var before := int(read_out["standing"])
	out["standing"] = clampi(before + delta, 0, cap)
	return ok(
		{"ledger": out, "standing": int(out["standing"]), "applied": int(out["standing"]) - before}
	)


## The bounded percent an institution's standing may project onto an allowlisted stat
## (ADR 0084). **A delegate to `InstitutionClaim.standing_percent` and never a second
## copy of the formula** — the `RealmRate` reasoning from ADR 0066: a rate that lives
## in two files can only be kept in sync by hand, and one retune would then mean two
## different answers to "how much recognition is this".
static func standing_percent(standing: int) -> float:
	return InstitutionClaim.standing_percent(standing)


## `out` marked corrupt: the WHOLE record refused, per the class note.
static func _corrupt(out: Dictionary) -> Dictionary:
	out["ok"] = false
	out["reason"] = R_CORRUPT_PAYLOAD
	out["corrupt"] = true
	return out
