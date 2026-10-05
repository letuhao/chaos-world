class_name InstitutionRegistry
extends RefCounted

## What an institution **kind** IS, and what it may do. One row per kind, keyed by
## id: the authored def type, the capabilities the kind has, and the def script
## itself. A modder adds a kind by REGISTERING it here, never by editing a module.
##
## ## Why `core/` and not `contracts/`
##
## Two independent reasons, and both are load-bearing:
##
## 1. **A `Resource` cannot be `@export`ed from `contracts/`.** The row a registration
##    builds holds an authored def type, and `RESOURCE_HOME_UNITS` is
##    `("core", "modules")` — the detector in `tools/arch/enforce.py` warns about a
##    Resource in `contracts/` because an authored content type filed as a contract is
##    how a save schema grows without a module ever owning it. `InstitutionClaim`
##    records the identical argument for itself.
## 2. **`core` is a LAYER, not a module, so the cross-module facade rule never applied
##    to it** and shared foundation here creates **zero new edges**. All of `clan`,
##    `sect` and `nation` already declare `core`. This is the `RealmRate` precedent
##    (ADR 0066): one table in `core`, shared by every path that needed it, existing
##    precisely because private copies could only be kept in sync **by hand**.
##
## ## How a def type is registered without `core/` referencing `modules/`
##
## **By handing the registry an opaque `Script` and a plain label, never a
## `res://` path and never a class name.** `LAYER_DEPS["core"]` is
## `{"core", "contracts"}` and the resolver reads a `res://` literal as a real edge,
## so a `preload("res://src/modules/sect/sect_def.gd")` here would be a violation the
## gate reports. It is also the dependency wearing a disguise — the shape
## `WorldFact` explicitly rejected ("a `res://` preload with a lazy resolve").
##
## So the row holds `def_type` as a **String label** (`"SectDef"`) and `def_script`
## as an **already-loaded `Script` value** the registering unit resolved in its OWN
## scope. `core/` stores it and hands it back; it never names a module to obtain it.
## The string is data a panel prints; the `Script` is what a catalog instantiates.
##
## ## An INSTANCE with a shared accessor, not a static table
##
## `ModuleRegistry` is an instance for a reason worth copying: a kind is a fact about
## one boot, and a static table that two boots in one process share is the
## cross-suite leak `WorldFact` had to build `clear_subscribers()` to survive. The
## runner drives every suite from `SceneTree._initialize()` **in one process**, so a
## suite that registers a kind and forgets to clear it hands that kind to every suite
## after it. `clear()` is therefore part of the surface, not a test convenience, and
## `teardown()` calls it.
##
## ## A duplicate kind is REFUSED, never idempotent and never a silent overwrite
##
## Refused, with `R_DUPLICATE_KIND` naming the offender. Idempotence was rejected
## because a same-id re-registration is only "the same" when both the def type and
## every capability flag agree — and a registry that guesses agreement on a mod's
## behalf is the silent id collision ADR 0184 §5 forbids ("an id collision requires an
## explicit `overrides:` declaration or it is a loud load error, never silent").
## Overwrite was rejected for the same reason with less information.
##
## ## An unknown kind is REFUSED BY NAME, and a known kind without a capability is NOT
##
## Two different questions, and `has_capability` answers both in one dictionary
## rather than collapsing them into a `false`:
##
##   - `{ok: false, reason: "unknown_kind"}` — there is no such kind. A caller that
##     treated this as "a kind that cannot teach" would gate on a kind that does not
##     exist, which is the invented-default defect.
##   - `{ok: true, has: false}` — the kind exists and lacks the capability. **A
##     legitimate state, not a zero that looks like a bug** (ADR 0084's `fit` case: a
##     clan authors no doctrine, so it has no fit axis at all).
##
## ## A `Script` may be unbound, and that is a state rather than a gap
##
## `def_script` is nullable because a kind can be registered before its def type is
## written — the registry names the kind and its capabilities, and the def lands
## later. `null` means "no def type bound yet" and is a different answer from "the
## def type is X", which is why they are two reads (`def_type_of`, `def_script_of`)
## rather than one that returns `""` for both. The precedent is `NationDef.own_claim`
## creating on demand rather than a caller null-checking an `@export` field.

## The refusal a lookup or a registration on a kind nobody registered reaches.
const R_UNKNOWN_KIND := "unknown_kind"
## The refusal a second registration of one kind reaches. Loud, per ADR 0184 §5.
const R_DUPLICATE_KIND := "duplicate_kind"
## The refusal a registration with no kind id reaches.
const R_NO_KIND := "no_kind"
## The refusal a registration naming no def type reaches. A kind nothing can author
## is a kind with no content, so it is refused rather than registered inert.
const R_EMPTY_DEF_TYPE := "empty_def_type"
## The refusal an unknown capability name reaches. The set is CLOSED, so an invented
## flag fails at registration instead of reading as a capability nothing has — the
## same discipline `InstitutionBudget.knows_tier` and `SectGate.VERBS` follow.
const R_UNKNOWN_CAPABILITY := "unknown_capability"

## The same reasons keyed by the name each is written with, so a caller can look one
## up without holding the constant. `InstitutionLedger.refuse` is the counterpart on
## the ledger side.
const REASONS := {
	R_UNKNOWN_KIND: R_UNKNOWN_KIND,
	R_DUPLICATE_KIND: R_DUPLICATE_KIND,
	R_NO_KIND: R_NO_KIND,
	R_EMPTY_DEF_TYPE: R_EMPTY_DEF_TYPE,
	R_UNKNOWN_CAPABILITY: R_UNKNOWN_CAPABILITY,
}

## Transmission: the kind teaches, so it HAS a fit axis and a doctrine (ADR 0084 —
## fit is a gate that projects zero stat modifiers). Absent means no fit axis at all,
## which is a legitimate authored state and never a zero.
const CAP_TEACHES := &"teaches"
## ADR 0085: the kind may author a claim over places. It grants no yield, no upkeep
## and no combat bonus — a claim decides who MAY fight and where.
const CAP_HAS_TERRITORY := &"has_territory"
## The kind authors positions a member may hold, so a founder is seated in the top
## one. Absent means positions are not part of this kind's shape.
const CAP_HAS_OFFICES := &"has_offices"
## ADR 0064: the kind is inherited rather than joined, so **it cannot be founded by
## an actor**. This flag is the ONLY place that answer is written: `found` derives its
## refusal from it rather than carrying a second `can_found` flag that could disagree.
const CAP_IS_BORN_TO := &"is_born_to"

## Every capability name a kind may carry. Closed, and membership is checked at
## registration so a typo fails where it was written rather than at the gate that
## silently never fires.
const CAPABILITIES: Array[StringName] = [
	CAP_TEACHES,
	CAP_HAS_TERRITORY,
	CAP_HAS_OFFICES,
	CAP_IS_BORN_TO,
]

## The process-wide registry. A boot wires one and hands it to the composition root;
## `null` until something does, so nothing reads a registry that was never built.
static var shared: InstitutionRegistry = null

## One row per kind: `{def_type: String, def_script: Script, capabilities: Array[StringName]}`.
## Keys are stored as the STRING value of the kind, because `Dictionary.has` is
## key-type strict and a `StringName`-keyed table silently matches nothing when read
## with a `String` — the failure `SectPositionDef.recognises` documents at length.
var _rows: Dictionary = {}


## The shared registry, created on first ask. Deliberately NOT auto-installed: a
## silent global that appears the first time somebody reads it is a global whose
## contents depend on read order, which is the coupling `ModuleRegistry`'s explicit
## construction exists to avoid.
static func instance() -> InstitutionRegistry:
	if shared == null:
		shared = InstitutionRegistry.new()
	return shared


## Record one kind. `{ok: true}` or `{ok: false, reason: <named constant>}` — the
## three-state vocabulary ADR 0083 declares, where a refusal is a third thing and
## never a silently absent row.
##
## Shape-local faults are eager, all four of them, because each is knowable from this
## call alone: no kind, no def type, an unknown capability name, and a duplicate. A
## duplicate is refused even when the row would be identical — see the class note.
##
## `def_script` may be `null`: the kind is registered and its def type is named, and
## the script is bound later. Nothing here resolves a `res://` path, so a caller that
## has not loaded its def yet is not blocked.
func register(
	kind: StringName,
	def_type: String,
	capabilities: Array[StringName] = [],
	def_script: Script = null
) -> Dictionary:
	var key := String(kind)
	if key == "":
		return _error(R_NO_KIND)
	if _rows.has(key):
		return _error(R_DUPLICATE_KIND)
	var label := _text(def_type)
	if label == "":
		return _error(R_EMPTY_DEF_TYPE)
	var flags: Array[StringName] = []
	for capability in capabilities:
		var name := StringName(String(capability))
		if not CAPABILITIES.has(name):
			return _error(R_UNKNOWN_CAPABILITY)
		# Duplicates inside one call are folded rather than refused: a list that
		# names the same flag twice states the same thing twice, which is a content
		# authoring slip with no second meaning — unlike a duplicate KIND, which is
		# two owners of one identity.
		if not flags.has(name):
			flags.append(name)
	flags.sort()
	_rows[key] = {
		"def_type": label,
		"def_script": def_script,
		"capabilities": flags,
	}
	return {"ok": true, "reason": ""}


## Drop every row, and answer how many were dropped. For a process that tears the
## wiring down or a suite leaving the process as it found it — `tests/run_tests.gd`
## runs every suite in ONE process, so a registration a suite forgets to clear is
## handed to every suite after it.
func clear() -> int:
	var dropped := _rows.size()
	_rows.clear()
	return dropped


## Whether `kind` is registered. The cheap branch a caller takes when it only needs
## to know a kind exists; `has_capability` when it needs to know what the kind does.
func knows(kind: StringName) -> bool:
	return _rows.has(String(kind))


## The row for `kind`, or `{}` when it is not registered. `{}` is ADR 0083's FIRST
## state — "this does not exist" — and it is a different answer from a refusal, so a
## caller that wants to know why gets [method has_capability].
func row(kind: StringName) -> Dictionary:
	var found = _rows.get(String(kind))
	return (found as Dictionary).duplicate(true) if found is Dictionary else {}


## What `kind` may do, in one read.
##
## `{ok: true, has: <bool>}` for a registered kind and `{ok: false, reason:
## "unknown_kind", has: false}` for one that is not. The two are deliberately not
## collapsed into a bare `false`: "no such kind" and "this kind does not teach" lead
## a caller to opposite actions, and a bare boolean makes it pick one by accident.
func has_capability(kind: StringName, capability: StringName) -> Dictionary:
	var found = _rows.get(String(kind))
	if not (found is Dictionary):
		return {"ok": false, "reason": R_UNKNOWN_KIND, "has": false}
	var flags: Array = (found as Dictionary)["capabilities"] as Array
	return {"ok": true, "reason": "", "has": flags.has(StringName(String(capability)))}


## Every capability `kind` carries, canonically ordered by its STRING value; `[]` for
## a kind nobody registered, which is the honest empty because the caller asked about
## something that does not exist rather than about a kind with nothing.
##
## `Array[StringName].sort()` is not specified to order by string value and the ids
## are interned, so the sort happens on `Array[String]` and converts afterwards — the
## reason `WorldFact.ids` sorts strings first.
func capabilities_of(kind: StringName) -> Array[StringName]:
	var found = _rows.get(String(kind))
	var out: Array[StringName] = []
	if not (found is Dictionary):
		return out
	var rows := (found as Dictionary)["capabilities"] as Array
	for capability in rows:
		out.append(StringName(String(capability)))
	out.sort()
	return out


## Every registered kind id, canonically ordered by its STRING value. Canonised for
## the same reason as [method capabilities_of]: a panel cycling the list must not
## reorder itself between reads.
func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _sorted_keys():
		out.append(StringName(key))
	return out


## The def type LABEL for `kind`, or `""` when `kind` is not registered. A label is
## what a panel prints and what a save may carry; it is not a reference and resolving
## it is the caller's business in the caller's own scope.
func def_type_of(kind: StringName) -> String:
	var found = _rows.get(String(kind))
	if not (found is Dictionary):
		return ""
	return String((found as Dictionary)["def_type"])


## The def SCRIPT for `kind`, or `null` when `kind` is unregistered OR registered
## without one bound. A caller that cannot tell those two apart should ask
## [method knows] first — which is why `def_type_of` exists as a separate read.
func def_script_of(kind: StringName) -> Script:
	var found = _rows.get(String(kind))
	if not (found is Dictionary):
		return null
	var script = (found as Dictionary)["def_script"]
	return script as Script if script is Script else null


## Whether `kind` is registered AND carries a def script. The question a catalog asks
## before it instantiates, because instantiating `null` is the failure this avoids.
func def_script_bound(kind: StringName) -> bool:
	return def_script_of(kind) != null


# --- Internals ---------------------------------------------------------------


## The registered keys, canonically ordered by their STRING value. See the class note
## on why the sort is on strings: `Dictionary.keys()` order is not specified to be
## stable across insertions, and an order that is load-bearing must not depend on it.
func _sorted_keys() -> Array[String]:
	var out: Array[String] = []
	# A `for` over a snapshot, building a NEW array: the body never writes to the
	# container being walked, so there is no shape here for a loop to grow in
	# lockstep with its own bound (`test_no_unbounded_wait.gd`).
	for key in _rows.keys():
		out.append(String(key))
	out.sort()
	return out


## The one text coercion in this file. A `String(...)` cast RAISES at runtime in
## GDScript on a float or a dictionary rather than yielding text — `String(42.0)` is
## a script error, not `"42.0"` — so a corrupt registration would abort the caller
## rather than read as absent, which is the one thing a corrupt input is allowed to
## do differently. `str()` does not raise, but it would turn a wrong-typed label
## into a plausible-looking one; an explicit type test that falls back is refusal.
func _text(value: Variant) -> String:
	if value is String or value is StringName:
		return String(value)
	return ""


## The refusal shape, and the only place this file builds one. `{"ok": false,
## "reason": R}` is ADR 0083's THIRD state and is a different thing from `{}` — so a
## caller can tell "this kind does not exist" from "you may not add it".
func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
