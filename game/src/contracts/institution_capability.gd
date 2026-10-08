class_name InstitutionCapability
extends RefCounted

## One capability of an organization, and the shared base of the family (ADR 0922).
## The family is ONE CONTRACT PER CAPABILITY — `Expellable`, `Teachable`,
## `Territorial`, `Dutiable`, `Authorised`, `AdmitTable`, `Successive`,
## `Schismatic` — because a trading guild must implement the ability to expel
## without ever seeing the ability to teach (the interface-segregation rule this
## whole programme exists to make structural). `InstitutionContract` is the
## dispatcher that hands an implementation back by name; this file is what every
## implementation IS.
##
## ## Why a base at all, and what it REFUSES to grow
##
## Three shapes were weighed.
##
## 1. **No base: a plain object and a duck-typed call.** `impl.expel(ctx)` is an
##    unchecked call whose failure mode is a runtime error three call sites deep,
##    and `AGENTS.md`'s rule — "any script implementing a `contracts/` interface
##    must pass the same contract tests" — would have nothing to point at. Same
##    rejection as `DamageMechanism`'s: a dictionary has no name.
## 2. **One capability carrying every verb.** That is the god-contract the
##    per-capability split exists to forbid. A guild would inherit a `teach()`
##    it must never use, and a forgotten override would be a WRONG ANSWER
##    (teaching nobody) rather than an absent one.
## 3. **This file.** It owns exactly four things: IDENTITY (so a dispatcher can
##    refuse a mis-filed implementation instead of answering as the wrong
##    capability), the FAMILY-WIDE REFUSAL NAMES (a reason spelled in eight files
##    is the ADR 0066 failure mode), the LIFECYCLE HOOKS a dispatcher invokes
##    uniformly, and the PAYLOAD RULE at its one construction point.
##
## **A verb is added here only when a second capability refuses with it.** A
## capability-specific verb belongs on the capability: that is the ISP rule this
## family is built on, and a base that accumulates one-offs is shape 2 wearing a
## different hat.
##
## ## A capability DECIDES; it never commits, and that is forced, not chosen
##
## Every verb below returns a PLAN of primitives: ids, counts, and named
## refusals. `contracts/` is a leaf layer, so it may not name the claim store a
## member's membership lives in — writing one here would mean COPYING a storage
## key and a schema shape that belong to the layer above, and a key spelled in
## two places is a silent dead write the moment either is renamed. The holder of
## that storage is the applier: it reads the plan and writes what it says.
## Rejected: writing through a duck-typed `set_module_data` with a store key
## handed in — the KEY would travel, but the RECORD SHAPE around it would still
## have to be rebuilt here, which is the same copy with more steps. Rejected:
## mutating the context dictionaries in place — a read that wrote is
## unrenderable, and `DoctrineRule.boards` records the identical argument.
##
## The consequence is the one property the suites assert of ANY implementation:
## **a refusal writes nothing** (ADR 0044), because a refused verb that had
## already moved a number is a state nobody authorises.
##
## ## The actor arrives as `Variant`
##
## `contracts/` depends on nothing (`tools/arch/rules.py` `LAYER_DEPS` declares
## `contracts: {contracts}`), so naming `Actor` is a gate violation, not a style
## question. `DoctrineRule` and `BeatSink` are the precedents for typing a
## contract's actor argument loosely and saying so in the docstring, so the next
## agent does not "fix" it.
##
## ## Payloads are primitives-only, enforced at the ONE construction point
##
## Every answer this family builds goes through [method ok] or [method refuse],
## and [method ok] REFUSES a payload carrying a `Resource`, an `Object`, a
## `Vector2` or any other value a save cannot round-trip (ADR 0027): an inner
## value of that kind reaches `actor.module_data` untouched and no checker in
## this repo can see it, so the refusal is made where the payload is CONSTRUCTED,
## the same choice `DamageProposal.is_primitive_effect` makes. The predicate
## itself is DELEGATED to `DoctrineRule.is_primitive_payload`, not copied: the
## rule is that one predicate exists once, and this file hands it a second name
## rather than a second implementation.
##
## ## NOTHING HERE TICKS
##
## No `Time.get_ticks*`, no `_process`, no `get_tree()` (DEF-0111): a capability
## whose answer depended on when it was asked would not be a rule. Every accrual
## takes an explicit `periods` from a caller that owns time.

## ## The context keys every capability may read
##
## `ctx` is a plain `Dictionary`. Three keys are family-wide, and a capability
## adds its own documented keys on top:
##
##   - `kind` — the registered kind id, as a `String`.
##   - `institution` — the organization id, as a `String`.
##   - `actor` — the acting member as a `Variant`, and the ONE value that is
##     not a primitive: a plain primitive context cannot carry the member whose
##     result this is, and wrapping one would be a second vocabulary for one
##     actor (`DoctrineRule` records the identical choice). An implementation
##     casts it once at the top and MUST NOT mutate it.
##
## Everything else in a `ctx` a caller builds is primitives-only, so a context
## can be logged, compared between a preview and an execution, and rebuilt from
## a save. That is the same property [method is_primitive_payload] holds the
## ANSWERS to, applied one level up.
##
## The context this capability was handed cannot be read at all: a requirement
## that is not a map, a period count that is not a number where a number is the
## whole question. Distinct from every policy refusal below, and the one reason
## a caller can treat as "the request itself is broken".
const R_MALFORMED := "malformed"
## A verb that acts FOR an actor was handed none. The acting member is the
## subject of the verb, so their absence is not a policy answer.
const R_NO_ACTOR := "no_actor"
## The actor holds no claim in the organization this verb is about. The
## ordinary "not one of us", named once because every member-scoped capability
## refuses with it.
const R_NOT_A_MEMBER := "not_a_member"
## The organization the context names does not exist (an empty id): content
## nothing defines grants nothing, teaches nothing and casts nobody out.
const R_UNKNOWN_INSTITUTION := "unknown_institution"
## A payload this family was asked to build carries something a save cannot
## round-trip (ADR 0027). Refused at construction, not discovered at load.
const R_UNSAFE_PAYLOAD := "unsafe_payload"
## At least one requirement is unmet, and the named entries travel in `unmet`.
## A REFUSAL and not a `{}`: the requirement exists and this candidate fails it
## (ADR 0083's third state tells that apart from "no such requirement").
const R_UNMET := "unmet"
## A verb that accrues was handed no periods, or fewer than one. A settlement
## that moved nothing is indistinguishable from one that never ran, so it is
## refused rather than absorbed.
const R_NO_PERIODS := "no_periods"

## Every family-wide reason above, as one list, so a caller that must VALIDATE a
## refusal reads the set rather than keeping a second copy of it. A capability's
## OWN reasons are authored beside their verbs in its own file, because they
## name a rule only that capability can state; extending THIS list is an ADR.
const REASONS: Array[String] = [
	R_MALFORMED,
	R_NO_ACTOR,
	R_NOT_A_MEMBER,
	R_UNKNOWN_INSTITUTION,
	R_UNSAFE_PAYLOAD,
	R_UNMET,
	R_NO_PERIODS,
]

## How deep [method is_primitive_payload] will look, ALIASED from the doctrine
## contract so the family carries one number rather than a copy of one. Past the
## cap the answer is refused: a payload too deep to verify is a payload this
## family will not vouch for, and a recursive walk is a `while` in disguise that
## `test_no_unbounded_wait.gd` cannot see.
const MAX_PAYLOAD_DEPTH := DoctrineRule.MAX_PAYLOAD_DEPTH


## The id this capability is dispatched under, and the tail of every dispatcher
## row keyed by it. Empty by default, which is what makes an unnamed capability
## unregistrable rather than silently filed under nothing.
func capability_id() -> StringName:
	return &""


## ## The capability's own contract suite, as REUSABLE findings (D3)
##
## Empty means "this implementation satisfies the contract". This is the method
## a dispatcher runs AT REGISTRATION to refuse a kind whose pack brought an
## implementation that does not hold — and the method a test drives against
## reference implementations and against deliberately broken ones. One body,
## two drivers, so "a pack claiming a capability must pass that capability's
## contract suite at load" is a mechanism rather than a promise: an interface
## cannot check its own implementers, and a test suite production code cannot
## call is a suite that guards nothing at load.
##
## The base half is GENERIC — identity, answer shape, named refusals, payload
## safety, and context purity — and every capability OVERRIDES this, calls
## `super`, and appends its own probes: a capability-specific rule (the
## expeller's cost asymmetry, the walk's one-stage-per-call) is checkable with
## the capability's own verbs and is not, by construction, expressible here.
##
## Findings are STRINGS because they are read by three audiences and none of
## them is a machine: the registration refusal carries them in its payload, a
## test asserts on them, and a modder reads them to learn what their pack got
## wrong. A finding never names a code path — it names the rule that failed.
##
## **The context purity half is the ADR 0044 measurement**: each verb is handed
## a COPY of a probe context and the copy is compared by value afterwards, so
## "a refused verb writes nothing" is asserted as `handed == probe` rather than
## taken from the verb's own answer. `JSON.stringify` is the comparison because
## the probes are primitives-only by definition, and it is a comparison no
## object identity can fake. The copy is taken BEFORE the call — a duplicate
## made afterwards would be pristine no matter what the verb did, which is a
## check that can never fire.
func contract_findings() -> Array[String]:
	var found: Array[String] = []
	if capability_id() == &"":
		found.append(
			"identity: capability_id() is empty, so a mis-filed implementation cannot be refused by name"
		)
	var probe := {"kind": "contract_probe", "institution": "contract_probe"}
	var check_handed := probe.duplicate(true)
	_probe_verb(found, "check", probe, check(check_handed), check_handed)
	var found_handed := probe.duplicate(true)
	_probe_verb(found, "on_found", probe, on_found(found_handed), found_handed)
	var join_handed := probe.duplicate(true)
	_probe_verb(found, "on_join", probe, on_join(join_handed), join_handed)
	var period_handed := probe.duplicate(true)
	_probe_verb(
		found, "on_period", probe, on_period(period_handed, 1), period_handed
	)
	return found


## Every reason this capability can return: the family's plus the ones it authors
## itself, assembled at READ time rather than written out twice — a second
## hand-maintained list is the ADR 0066 failure mode inside the file that exists
## to prevent it.
func reasons() -> Array[String]:
	var out: Array[String] = []
	out.append_array(InstitutionCapability.REASONS)
	out.append_array(own_reasons())
	return out


## The reasons THIS capability adds beside its own verbs. Empty on the base, so
## a capability with no vocabulary of its own overrides nothing.
func own_reasons() -> Array[String]:
	return [] as Array[String]


## Assert `answer` is a refusal naming `reason`, recording everything else. The
## shared half of every capability's own suite: an implementation that answers
## with a DIFFERENT named reason is as broken as one that succeeded, and a probe
## that only checked `ok == false` would not see the difference.
func expect_refusal(
	found: Array[String], verb: String, answer: Variant, reason: String
) -> void:
	_judge(found, verb, answer)
	if not (answer is Dictionary):
		return
	var row := answer as Dictionary
	if bool(row.get("ok", false)):
		found.append("%s: should have been refused with '%s'" % [verb, reason])
		return
	if InstitutionCapability.text(row.get("reason", ""), "") != reason:
		found.append(
			"%s: refused as '%s' instead of '%s'" % [verb, row.get("reason", ""), reason]
		)


# --- Internals ---------------------------------------------------------------


## Run one lifecycle verb's answer and its purity through the family's checks.
## `pristine` is the probe as written down, `handed` is the exact object the verb
## received, and the two are compared by text after the call — see the class
## note on why the copy is taken before and never after.
func _probe_verb(
	found: Array[String], verb: String, pristine: Dictionary, answer: Variant, handed: Dictionary
) -> void:
	_judge(found, verb, answer)
	if JSON.stringify(handed) != JSON.stringify(pristine):
		found.append("%s: mutated the context it was handed" % verb)


## Everything the family requires of ONE answer: a Dictionary, an `ok` flag and
## a `reason` key on EVERY path, a refusal that names itself, a success whose
## reason is empty, and a payload a save can round-trip.
func _judge(found: Array[String], verb: String, answer: Variant) -> void:
	if not (answer is Dictionary):
		found.append("%s: did not return a Dictionary" % verb)
		return
	var row := answer as Dictionary
	if not row.has("ok"):
		found.append("%s: no `ok` key" % verb)
		return
	if not (row["ok"] is bool):
		found.append("%s: `ok` is not a bool" % verb)
		return
	if not row.has("reason"):
		found.append("%s: no `reason` key" % verb)
		return
	var reason := InstitutionCapability.text(row["reason"], "")
	if bool(row["ok"]):
		if reason != "":
			found.append("%s: succeeded with a non-empty reason" % verb)
	elif reason == "":
		found.append("%s: refused with no reason" % verb)
	elif not reasons().has(reason):
		found.append("%s: refused with '%s', which is not a named reason" % [verb, reason])
	if not is_primitive_payload(row):
		found.append("%s: the answer carries a value a save cannot round-trip" % verb)


## The id this capability is dispatched under, and the tail of every dispatcher
## row keyed by it. Empty by default, which is what makes an unnamed capability
## unregistrable rather than silently filed under nothing.
func capability_id() -> StringName:
	return &""


## Vets a scenario this capability has an opinion about, before anything is
## decided: the kind-level gate. Returns `{ok, reason, unmet}` on every path —
## `unmet` entries are `{kind, id, required, actual}` dictionaries a panel can
## render without re-deriving them.
##
## The default imposes NO requirement, which is not a stub that lies: a
## capability that does not override this has authored no requirement, and "no
## requirement" is the ungated state `SectGate` documents for `{}`.
func check(_ctx: Dictionary) -> Dictionary:
	return {"ok": true, "reason": "", "unmet": []}


## What this capability wants recorded when an organization is founded. The
## default proposes nothing.
func on_found(_ctx: Dictionary) -> Dictionary:
	return {"ok": true, "reason": "", "plan": {}}


## What this capability wants recorded when a member joins. The default
## proposes nothing.
func on_join(_ctx: Dictionary) -> Dictionary:
	return {"ok": true, "reason": "", "plan": {}}


## What this capability wants recorded when `periods` elapse. `periods` is an
## explicit argument from a caller that owns time (DEF-0111), never read from a
## clock. The default proposes nothing.
func on_period(_ctx: Dictionary, _periods: int) -> Dictionary:
	return {"ok": true, "reason": "", "plan": {}}


## The success shape. `ok` and `reason` are present on EVERY answer so a caller
## reads one key without knowing which verb it called, and `reason` is `""` on
## success because an empty reason and a missing key are a different thing to a
## panel.
##
## **Refuses an `extra` that is not primitives-only** (ADR 0027): the payload is
## walked at construction, and a payload this family cannot vouch for answers
## with [constant R_UNSAFE_PAYLOAD] rather than reaching a save and breaking it
## at load, in front of the player.
static func ok(extra: Dictionary = {}) -> Dictionary:
	if not is_primitive_payload(extra):
		return {"ok": false, "reason": R_UNSAFE_PAYLOAD}
	var out := {"ok": true, "reason": ""}
	for key in extra.keys():
		out[String(key)] = extra[key]
	return out


## The refusal shape. `{"ok": false, "reason": R}` is ADR 0083's THIRD state and
## is a different thing from `{}` — so a caller can tell "this action exists and
## is refused" from "there is no such thing". `reason` is a named constant and
## never free text, so a screen, a test and a log line can compare it.
static func refuse(reason: String, extra: Dictionary = {}) -> Dictionary:
	if not is_primitive_payload(extra):
		return {"ok": false, "reason": R_UNSAFE_PAYLOAD}
	var out := {"ok": false, "reason": reason}
	for key in extra.keys():
		out[String(key)] = extra[key]
	return out


## `value` when it really is text — a `String` or a `StringName` — otherwise
## `fallback`. A raw `String(...)` cast RAISES in GDScript on a number rather
## than yielding text, so a corrupt context would abort a verb instead of
## reading as absent. `core/institution_ledger.gd` owns the same pair for its
## layer; `contracts/` may not depend on `core/`, so the leaf re-authors the
## pair and this docstring is where the duplication is recorded. An explicit
## type test that falls back is refusal, not coincidence.
static func text(value: Variant, fallback: String = "") -> String:
	if value is String or value is StringName:
		return String(value)
	return fallback


## `value` as an integer count when it really is a number, otherwise `fallback`.
## Paired with [method text] for the same reason: a count read off an authored
## context is a number or it is absent, and it is never a plausible zero guessed
## from a string.
static func count(value: Variant, fallback: int = 0) -> int:
	if value is int or value is float:
		return int(value)
	return fallback


## `value` when it really is a bool, otherwise `fallback`. A hand-edited save or
## a JSON-authored row can carry a string where a flag was meant, and `bool()`
## would read `"false"` as true — so a flag is a flag or it is the default.
static func flag(value: Variant, fallback: bool = false) -> bool:
	if value is bool:
		return value
	return fallback


## `source`'s entry for `id`, matched by TEXT, or `null`. `Dictionary.has()` is
## key-type strict, so `has(String(id))` against a `StringName`-keyed map
## silently matches nothing — the failure `InstitutionProjection.recognises`
## documents at length. Every authored map here is keyed by whatever the
## authoring layer produced, so the lookup is textual.
static func entry(source: Dictionary, id: StringName) -> Variant:
	if id == &"":
		return null
	for key in source.keys():
		if String(key) == String(id):
			return source[key]
	return null


## Whether every value reachable inside `value` is a primitive this family will
## carry. **A delegate to `DoctrineRule.is_primitive_payload`, never a second
## implementation** — a predicate copied to a second file can only be kept in
## step by hand (ADR 0066), and `contracts/` may reference `contracts/`.
static func is_primitive_payload(value: Variant) -> bool:
	return DoctrineRule.is_primitive_payload(value)


## The keys of `required` that `payload` does not carry, so a caller can be told
## which ones are missing rather than discovering a blank field on a screen.
static func missing_keys(payload: Dictionary, required: Array[StringName]) -> Array[StringName]:
	return DoctrineRule.missing_keys(payload, required)
