class_name InstitutionContract
extends RefCounted

## The dispatch surface of the institution standard: which KIND carries which
## capability, and the four lifecycle verbs that ask a kind what its
## capabilities want (ADR 0922).
##
## ## What this file is, in one line
##
## `InstitutionCapability` is what a capability IS; this is how a KIND's
## capabilities are reached and consulted. One row per kind, keyed by id:
## a label and its capability implementations, exactly as
## `InstitutionRegistry` holds one row per kind with its def type.
##
## ## The capability set is OPEN, and that is the pack's licence
##
## A sort of closed name list — "only these nine ids may register" — would be
## the closed `OwnerRef.KINDS` defect one layer up: a modder shipping a whole new
## organization kind could then never ship a capability this build has not heard
## of. So registration refuses on FAILURE, never on unfamiliarity: an
## implementation must (1) be an `InstitutionCapability`, (2) name itself, and
## (3) pass its own `contract_findings()` suite. The nine shipped capabilities
## are published in [constant STANDARD] as VOCABULARY — a panel renders it, a
## test asserts each one ships a suite — and nothing gates on it.
##
## Rejected: **a `Dictionary` of callables per kind.** A dictionary has no name,
## so "any implementation of a `contracts/` interface must pass the same
## contract tests" would have nothing to point at — `DamageMechanism`'s
## rejection, restated for the same reason.
##
## Rejected: **registering a `Script` and instantiating per call.** A capability
## instance can be configured by the pack that built it and is graded ONCE at
## registration; a bare script would defer both the configuration and the suite
## to a call site, and the suite result would then be discovered mid-gameplay
## instead of refused at boot. `DoctrineRegistry.attach` grades an INSTANCE for
## the same reason.
##
## ## D3: the suite runs AT REGISTRATION, so a broken pack is refused at load
##
## [method register] runs [method InstitutionCapability.contract_findings] on
## every implementation and refuses the KIND as `contract_failed`, carrying the
## findings. This is the mechanism behind "a capability is a contract": an
## interface cannot check its own implementers, and a suite production code
## cannot call guards nothing at load. A pack that fights this by overriding
## `contract_findings` to return `[]` is making a FALSE DECLARATION in its own
## name — the same class of act as overriding any gated method, and the reason
## the findings are published on the refusal rather than merely logged.
##
## ## The three-state vocabulary, per lookup
##
## [method of] tells apart three situations the ADR 0083 vocabulary exists for:
##
##   - `{ok: false, reason: "unknown_kind", has: false}` — no such kind.
##   - `{ok: true, reason: "", has: false}` — the kind EXISTS and carries no such
##     capability. A legitimate authored state (a farmers' circle with no
##     offices), never a zero that looks like a bug.
##   - `{ok: true, reason: "", has: true, capability: <impl>}` — here it is.
##
## The first two are deliberately not collapsed into a `false`: a caller that
## could not tell them apart would gate a press on a kind that does not exist.
##
## ## The four lifecycle verbs FOLD the kind's capabilities, in canonical order
##
## `check`, `on_found`, `on_join` and `on_period` run EVERY capability the kind
## carries, in the canonical id order [method capabilities_of] reports, because
## the caller asks the KIND — not each capability — and the answer must be the
## same for two callers who enumerate in different orders. The first refusal
## wins and names the capability it came from; a success carries every
## capability's proposal merged under its own id, so a plan is dict-of-plans and
## never one flattened namespace two capabilities could collide in.
##
## A refusal at ANY capability refuses the WHOLE verb and returns no plan: a
## half-applied founding is the state nobody authorises, and the applier can
## rely on "refused" meaning "nothing was proposed to write".
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111). Every
## accrual takes an explicit `periods` from a caller that owns time.

## The refusal a registration with no kind id reaches.
const R_NO_KIND := "no_kind"
## The refusal a second registration of one kind reaches. Loud, never
## idempotent: two rows for one identity are two owners of one name, and
## `InstitutionRegistry` records the same rule.
const R_DUPLICATE_KIND := "duplicate_kind"
## The refusal a row that is not a capability reaches. An implementation this
## dispatcher cannot grade is not silently skipped: skipping it would register a
## kind whose answers are missing a capability nobody can find.
const R_NOT_A_CAPABILITY := "not_a_capability"
## The refusal a capability that names itself nothing reaches. An unnamed
## implementation cannot be looked up, refused by name, or told apart from
## another unnamed one.
const R_NO_CAPABILITY := "no_capability"
## The refusal a kind reaches when an implementation fails its own contract
## suite (D3). The findings travel in `findings`, so a modder reads what their
## pack got wrong instead of a boolean.
const R_CONTRACT_FAILED := "contract_failed"
## The refusal a lookup on an unregistered kind reaches. Distinct from
## `{ok: true, has: false}` — see the class note.
const R_UNKNOWN_KIND := "unknown_kind"

## Every reason this file authors, keyed by the name each is written with, so a
## caller can look one up without holding the constant. A capability's OWN
## reasons are deliberately absent: they are the capability's vocabulary, and a
## second table here would be a list somebody has to keep in step (ADR 0066).
const REASONS: Dictionary = {
	R_NO_KIND: R_NO_KIND,
	R_DUPLICATE_KIND: R_DUPLICATE_KIND,
	R_NOT_A_CAPABILITY: R_NOT_A_CAPABILITY,
	R_NO_CAPABILITY: R_NO_CAPABILITY,
	R_CONTRACT_FAILED: R_CONTRACT_FAILED,
	R_UNKNOWN_KIND: R_UNKNOWN_KIND,
}

## The nine capabilities the STANDARD ships, as published vocabulary. **A gate
## would be wrong here** — see the class note: registration is refused on a
## failed suite, never on an unfamiliar id. A test asserts every id below ships
## a class whose suite is empty, so this list cannot drift from the family.
const STANDARD: Array[StringName] = [
	&"admit_table",
	&"authorised",
	&"diplomatic",
	&"dutiable",
	&"expellable",
	&"schismatic",
	&"successive",
	&"teachable",
	&"territorial",
]

## The process-wide dispatcher. `null` until a boot wires one, so nothing reads
## a dispatcher that was never built — `InstitutionRegistry` records why this is
## an explicit instance and not a lazy global.
static var shared: InstitutionContract = null

## One row per kind: `{capabilities: {String: InstitutionCapability}}`. Keys are
## the STRING value of an id, because `Dictionary.has` is key-type strict and a
## `StringName`-keyed table silently matches nothing when read with a `String`.
var _rows: Dictionary = {}


## The shared dispatcher, created on first ask. Deliberately NOT auto-installed:
## a silent global that appears the first time somebody reads it is a global
## whose contents depend on read order.
static func instance() -> InstitutionContract:
	if shared == null:
		shared = InstitutionContract.new()
	return shared


## ## Record one kind and its capabilities, or refuse the whole kind.
##
## `{ok: true, reason: "", kind, capabilities}` or
## `{ok: false, reason: <named constant>}` — the three-state vocabulary, where a
## refusal is a third thing and never a silently absent row.
##
## Every fault below is eager and knowable from this call alone: no kind, a
## duplicate, an entry that is not a capability, one that names nothing, and one
## that fails its own suite (D3). A fault at ANY entry refuses the KIND — no row
## is written, so a kind is never half-registered.
##
## A duplicate capability INSIDE one call is folded rather than refused: a list
## naming the same implementation twice states the same thing twice, which is an
## authoring slip with no second meaning — unlike a duplicate KIND, which is two
## owners of one identity. `InstitutionRegistry.register` records the same rule.
##
## The `capabilities` parameter is untyped on purpose. A typed
## `Array[InstitutionCapability]` would make GDScript RAISE at the call boundary
## on a wrongly-shaped element — `Cannot convert argument ...` — so a corrupt
## list would abort the caller instead of being refused here, and a refusal that
## cannot receive the corrupt value cannot refuse it (`InstitutionRegistry`
## `register` records the identical reasoning for its `def_type`).
func register(kind: StringName, capabilities: Array = []) -> Dictionary:
	var key := String(kind)
	if key == "":
		return _error(R_NO_KIND)
	if _rows.has(key):
		return _error(R_DUPLICATE_KIND)
	var accepted: Dictionary = {}
	# A `for` over the CALLER's snapshot, writing into a NEW dictionary: the body
	# never grows the array being walked, so the bound is the caller's own list
	# and there is no shape here for a loop to grow in lockstep with its own
	# bound (`test_no_unbounded_wait.gd`).
	for entry in capabilities:
		if not (entry is InstitutionCapability):
			return _error(R_NOT_A_CAPABILITY)
		var impl := entry as InstitutionCapability
		var capability_id := impl.capability_id()
		if capability_id == &"":
			return _error(R_NO_CAPABILITY)
		var findings := impl.contract_findings()
		if not findings.is_empty():
			return InstitutionCapability.refuse(
				R_CONTRACT_FAILED,
				{"kind": key, "capability": String(capability_id), "findings": findings}
			)
		accepted[String(capability_id)] = impl
	_rows[key] = {"capabilities": accepted}
	return InstitutionCapability.ok({"kind": key, "capabilities": _names(accepted)})


## Drop every row, and answer how many were dropped. `tests/run_tests.gd` drives
## every suite in ONE process, so a registration a suite forgets to clear is
## handed to every suite after it — the reason this is part of the surface and
## not a test convenience.
func clear() -> int:
	var dropped := _rows.size()
	_rows.clear()
	return dropped


## Whether `kind` is registered. The cheap branch a caller takes when it only
## needs to know a kind exists.
func knows(kind: StringName) -> bool:
	return _rows.has(String(kind))


## Every registered kind id, canonically ordered by its STRING value. Sorted on
## `Array[String]` before converting back, because `Array[StringName].sort()` is
## not specified to order by string value and the ids are interned — the
## divergence `InstitutionRegistry._canonical` measured on this engine.
func kinds() -> Array[StringName]:
	var text: Array[String] = []
	for key in _rows.keys():
		text.append(String(key))
	text.sort()
	var out: Array[StringName] = []
	for entry in text:
		out.append(StringName(entry))
	return out


## Every capability id `kind` carries, canonically ordered by STRING value; `[]`
## for a kind nobody registered — the honest empty, because the caller asked
## about something that does not exist rather than about a kind with nothing.
func capabilities_of(kind: StringName) -> Array[StringName]:
	var row = _rows.get(String(kind))
	if not (row is Dictionary):
		return [] as Array[StringName]
	return _names((row as Dictionary)["capabilities"] as Dictionary)


## ## The kind's implementation of one capability, or the named reason it is not
## ## there. See the class note for the three answers.
##
## The success payload carries a live OBJECT, which is the one place in this
## family the primitives-only rule deliberately does not apply: `capability` is
## an in-process dispatch handle, never a save payload and never rendered. The
## row a dispatcher holds is process state that is NEVER serialized (the
## `InstitutionRegistry` rule, ADR 0271), so no save round trip can meet it.
func of(kind: StringName, capability_id: StringName) -> Dictionary:
	var row = _rows.get(String(kind))
	if not (row is Dictionary):
		return {"ok": false, "reason": R_UNKNOWN_KIND, "has": false}
	if capability_id == &"":
		return {"ok": true, "reason": "", "has": false}
	var found = ((row as Dictionary)["capabilities"] as Dictionary).get(String(capability_id))
	if not (found is InstitutionCapability):
		return {"ok": true, "reason": "", "has": false}
	return {"ok": true, "reason": "", "has": true, "capability": found}


## ## Ask the kind's every capability to vet `ctx`, in canonical order.
##
## `{ok: true, reason: "", unmet: [], checked: [...]}` or the first capability's
## refusal, with `capability` naming which one refused. A refusal's `reason` is
## the CAPABILITY's own named constant — this dispatcher does not translate one
## vocabulary into another.
##
## A kind with no capabilities succeeds with an empty `checked`: there is nothing
## to vet, which is a state and not a hole.
func check(kind: StringName, ctx: Dictionary) -> Dictionary:
	var row = _rows.get(String(kind))
	if not (row is Dictionary):
		return InstitutionCapability.refuse(R_UNKNOWN_KIND)
	var checked: Array = []
	# A `for` over the capability id list this ROW already holds, writing into a
	# fresh array: the body never writes to the list being walked, so the bound
	# is the kind's own capability count.
	for capability_id in capabilities_of(kind):
		var impl := (
			((row as Dictionary)["capabilities"] as Dictionary)[String(capability_id)]
			as InstitutionCapability
		)
		var answer := impl.check(ctx)
		if not bool(answer.get("ok", false)):
			return _refused_by(answer, capability_id)
		checked.append(String(capability_id))
	return InstitutionCapability.ok({"unmet": [], "checked": checked})


## ## Ask the kind's every capability what a founding should record.
##
## `{ok: true, reason: "", plan: {<capability_id>: <that capability's plan>}}`, a
## refusal from the first capability that has one, or `unknown_kind`. The plan is
## keyed by capability id, never flattened: two capabilities proposing one key
## is a collision the caller cannot resolve, and a refusal returns NO plan.
func on_found(kind: StringName, ctx: Dictionary) -> Dictionary:
	return _fold(kind, ctx, &"on_found", 0)


## ## Ask the kind's every capability what a join should record. See
## ## [method on_found] for the shape.
func on_join(kind: StringName, ctx: Dictionary) -> Dictionary:
	return _fold(kind, ctx, &"on_join", 0)


## ## Ask the kind's every capability what `periods` of time should record.
##
## `periods` is an explicit argument from a caller that owns time (DEF-0111),
## and a value below 1 is REFUSED rather than absorbed: a period verb that moved
## nothing is indistinguishable from one that never ran. See [method on_found]
## for the shape.
func on_period(kind: StringName, ctx: Dictionary, periods: int) -> Dictionary:
	if periods < 1:
		return InstitutionCapability.refuse(InstitutionCapability.R_NO_PERIODS)
	return _fold(kind, ctx, &"on_period", periods)


# --- Internals ---------------------------------------------------------------


## The shared body of the three proposing verbs: run every capability's verb in
## canonical order, merge the plans under each capability's id, and refuse the
## whole verb at the first refusal. `periods` is `0` for the two verbs that take
## none — a sentinel the verbs themselves never see.
func _fold(kind: StringName, ctx: Dictionary, verb: StringName, periods: int) -> Dictionary:
	var row = _rows.get(String(kind))
	if not (row is Dictionary):
		return InstitutionCapability.refuse(R_UNKNOWN_KIND)
	var plan: Dictionary = {}
	for capability_id in capabilities_of(kind):
		var impl := (
			((row as Dictionary)["capabilities"] as Dictionary)[String(capability_id)]
			as InstitutionCapability
		)
		var answer := (
			impl.on_period(ctx, periods) if verb == &"on_period" else _propose(impl, verb, ctx)
		)
		if not bool(answer.get("ok", false)):
			return _refused_by(answer, capability_id)
		var proposed = answer.get("plan", {})
		if proposed is Dictionary and not (proposed as Dictionary).is_empty():
			plan[String(capability_id)] = proposed
	return InstitutionCapability.ok({"plan": plan})


## One proposing verb by name, for the two that take no periods. A `match` here
## rather than three near-identical loops: the verbs differ only in which method
## they call, and three copies of the fold would be three places for the
## refusal shape to drift.
func _propose(impl: InstitutionCapability, verb: StringName, ctx: Dictionary) -> Dictionary:
	match verb:
		&"on_found":
			return impl.on_found(ctx)
		_:
			return impl.on_join(ctx)


## A capability's refusal, re-shaped so the caller can see WHICH capability
## refused. `reason` stays the capability's own name; this file adds no
## translation table (see [method check]).
func _refused_by(answer: Dictionary, capability_id: StringName) -> Dictionary:
	var extra: Dictionary = {"capability": String(capability_id)}
	var unmet = answer.get("unmet", [])
	if unmet is Array and not (unmet as Array).is_empty():
		extra["unmet"] = unmet
	return InstitutionCapability.refuse(InstitutionCapability.text(answer.get("reason", "")), extra)


## The capability ids of one row, canonically ordered by STRING value.
func _names(capabilities: Dictionary) -> Array[StringName]:
	var text: Array[String] = []
	for key in capabilities.keys():
		text.append(String(key))
	text.sort()
	var out: Array[StringName] = []
	for entry in text:
		out.append(StringName(entry))
	return out


## The refusal shape this file builds for its OWN faults. A capability's refusal
## travels through [method _refused_by] instead, because it names a rule this
## file does not own.
func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
