class_name InstitutionGate
extends RefCounted

## The ONE requirement evaluator, for any institution kind (ADR 0922, ADR 0942).
##
## ## What this replaces, measured
##
## `sect_gate.gd` (442 lines) and `clan_gate.gd` (469) both evaluated a requirement
## dictionary against a claim. The scout measured the two side by side: **identical**
## `_pass()` (3 lines) and an identical 12-line `_composite` tail including the
## poison-check that a malformed child refuses the whole composite. What differed was
## the verb KEY NAMES, the refusal entry's value types, and whether the actor was
## threaded on a probe or passed explicitly.
##
## So the shared half is a RULE — one envelope, one composite semantics, one refusal
## shape — and the verb table is what a kind supplies. A kind's own verbs are its own
## business (`has_rank` is a clan's, `fit_at_least` is a sect's), and this file may not
## name either. That is the interface-segregation rule applied to a gate: a table plus
## a resolver, never a subclass.
##
## ## The envelope, stated once
##
## Every verb returns exactly one of three shapes, and the third is the one that gets
## collapsed by accident:
##
##   - `{ok: true, reason: "", unmet: []}` — satisfied.
##   - `{ok: false, reason: "unmet", unmet: [{kind, id, required, actual, label}]}` —
##     a normal failure. The member is told no, with the numbers that say how far.
##   - `{ok: false, reason: "malformed"|"unknown_verb", unmet: [...]}` — the
##     REQUIREMENT is unreadable. That is a content bug rather than a player outcome,
##     and it refuses CLOSED: a requirement nothing can read must never be treated as
##     satisfied, or a typo in a `.tres` becomes a free pass.
##
## ## Why the actor travels on the probe in one tier and beside it in another
##
## `sect` copied the requirement and wrote the caller's actor into it, so a composite
## child could be re-entered through the same public `evaluate`. `clan` passed the
## actor as an explicit argument. Both work; the probe is the one that generalises,
## because a requirement AUTHORED AS CONTENT (a nested `all_of` in a `.tres`) has to be
## evaluable with no actor at all, and `probe["actor"]` is the slot that says which.
## The probe also has to be rebuilt per child — see [method composite].
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111).

## The refusal a requirement naming no verb reaches. Distinct from `unmet`: there is no
## question to answer, so the answer is not "no".
const R_MALFORMED := "malformed"
## The refusal a requirement naming a verb the kind does not author reaches. The kind
## reports it rather than the caller, because only the kind knows its own table.
const R_UNKNOWN_VERB := "unknown_verb"
## The reason a satisfied composite's failed children would carry. A composite that
## fails reports `unmet` with every child's own entries, so a panel renders the whole
## story rather than the first bar.
const R_UNMET := "unmet"

## The five keys an unmet entry carries, and no others. `required` and `actual` are
## deliberately untyped: a bar may be a count, a share, an id or a boolean, and the
## entry reports what the verb actually compared.
const ENTRY_KEYS: Array[String] = ["kind", "id", "required", "actual", "label"]


## A requirement is satisfied.
##
## Named `passed`, never `pass`: `pass` is a reserved GDScript keyword, so a
## `func pass()` does not parse. Because this class is resolved by NAME, one
## unparseable function here aborted every suite that referenced `InstitutionGate`:
## 50 script errors and one failed suite load, which reads as a broken gate rather
## than a broken word. The two tier gates this replaces spelled it `_pass()`, which
## is why nobody hit this until the underscore came off.
static func passed() -> Dictionary:
	return {"ok": true, "reason": "", "unmet": []}


## A requirement the member failed, carrying one entry that says where.
static func fail(
	kind: StringName, id: StringName, required: Variant, actual: Variant, label: String
) -> Dictionary:
	return {
		"ok": false,
		"reason": R_UNMET,
		"unmet": [entry(kind, id, required, actual, label)],
	}


## One unmet row. `id` is a `StringName` here because every caller has one; it is
## published as text because a panel renders it.
static func entry(
	kind: StringName, id: StringName, required: Variant, actual: Variant, label: String
) -> Dictionary:
	return {
		"kind": String(kind),
		"id": String(id),
		"required": required,
		"actual": actual,
		"label": label,
	}


## A REFUSAL — the requirement itself is unreadable. Distinct from a normal failure
## and it refuses CLOSED, naming the verb it could not read so the fix is visible in
## the log rather than in a player's confusion.
##
## `verb` is named by the CALLER rather than read off the requirement: an unreadable
## requirement has no readable verb to report, so the caller names the one it could not
## match. `label` is the human sentence.
static func refuse(reason: String, label: String, verb: String = "") -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet": [entry(&"gate", StringName(verb), "a_readable_requirement", "unreadable", label)],
	}


## ## The composite, and the one mistake it must not make
##
## A child IS the next requirement, so the probe's `actor` and `ledger` are carried
## across and **everything else comes from the child**. Building the child from the
## parent and overwriting only `of` instead would leave the parent's `verb` in place, so
## every child would be re-entered as the same composite and recurse on the parent's own
## children forever. That is a recursion a `while` scan cannot see, which is why the
## rebuild is spelled out here rather than left to each caller.
##
## `resolve` is the kind's own verb resolver: `Callable(actor, requirement) -> Dictionary`.
## A malformed or unknown-verb child POISONS the whole composite — a nested gate that
## cannot be read is never treated as satisfied.
##
## `refuse_when_any` inverts the fold: `none_of` passes only when NO child passed.
static func composite(
	resolve: Callable, probe: Dictionary, require_all: bool, refuse_when_any: bool
) -> Dictionary:
	var children = probe.get("of", null)
	if not (children is Array) or (children as Array).is_empty():
		return refuse(R_MALFORMED, "A composite gate names no children.", "all_of")
	var actor = probe.get("actor", null)
	var ledger = probe.get("ledger", {})
	var unmet: Array[Dictionary] = []
	var passed := 0
	var total := (children as Array).size()
	for child in children as Array:
		if not (child is Dictionary):
			return refuse(
				R_MALFORMED, "A composite gate names a child that is not a map.", "all_of"
			)
		# The child IS the requirement. Only the two context slots are inherited, so a
		# child carrying its own `verb` and its own arguments reads as itself.
		var nested := {"actor": actor, "ledger": ledger}
		for key in (child as Dictionary).keys():
			nested[String(key)] = (child as Dictionary)[key]
		var verdict: Variant = resolve.call(nested)
		if not (verdict is Dictionary):
			return refuse(R_MALFORMED, "A composite child returned no verdict.", "all_of")
		var row: Dictionary = verdict as Dictionary
		if bool(row.get("ok", false)):
			passed += 1
			continue
		var nested_reason := String(row.get("reason", ""))
		if nested_reason == R_MALFORMED or nested_reason == R_UNKNOWN_VERB:
			return row
		for item in row.get("unmet", []) as Array:
			unmet.append(item)
	var ok := passed >= total if require_all else passed > 0
	if refuse_when_any:
		ok = passed == 0
	if ok:
		return passed()
	return {"ok": false, "reason": R_UNMET, "unmet": unmet}


## ## The ledger a requirement is read against
##
## A gate that needs the actor reads the actor's own slot; a gate that is PURE AUTHORED
## DATA — an `all_of`, or any content author writing a nested requirement — carries its
## own `ledger` under that key, which is what lets a requirement be evaluated with no
## actor at all. An `actor` key that is not an `Actor` is the ordinary case for an
## ungated panel question, and it is not a ledger and does not become one.
##
## `read` is the kind's own reader: `Callable(actor) -> Dictionary`.
static func ledger_for(
	requirement: Dictionary, actor: Variant, read: Callable, shape: Dictionary = {}
) -> Dictionary:
	if actor is Actor and read.is_valid():
		var from_actor: Variant = read.call(actor)
		if from_actor is Dictionary:
			return from_actor as Dictionary
	var authored = requirement.get("ledger", null)
	if authored is Dictionary:
		return InstitutionEnvelope.normalize(authored as Dictionary, {}, shape)
	return InstitutionEnvelope.normalize({}, {}, shape)


## Whether `requirement` names a verb at all. The first question every resolver asks,
## and the one whose answer is a REFUSAL rather than an `unmet`.
static func verb_of(requirement: Dictionary) -> StringName:
	return StringName(InstitutionLedger.text(requirement.get("verb", ""), ""))
