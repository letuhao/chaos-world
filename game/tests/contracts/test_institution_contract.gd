extends TestCase

## The capability dispatcher, and D3's enforcement point (ADR 0922).
##
## `InstitutionContract` is how a KIND's capabilities are reached and consulted,
## and this suite is the proof obligation of the dispatcher half of the family:
## identity, the three-state lookup vocabulary, the fold, and — the case that
## matters most — **D3: registration REFUSES a kind whose pack brought a broken
## implementation**. A green guard is not a tested guard (INC-0016), so the two
## deliberately broken capabilities below are PLANTED here and driven through
## the same `register()` body production uses: one mutates the context it is
## handed, one refuses without naming itself. If `register` stopped calling
## `contract_findings()`, these cases would go green and the mechanism would be
## a promise rather than a gate.
##
## ## Every loop in this file is a `for`
##
## There is not one `while`. The walks are over `InstitutionContract.STANDARD`,
## over fixed probe rows built above the loop, or over a materialised key list;
## none appends to the container it walks, so no bound can grow in lockstep
## with its own body and `test_no_unbounded_wait.gd` has nothing to reject.

## The refusal reasons the dispatcher itself authors, so a case can assert one
## arrived without holding a constant by hand.
const DISPATCH_REASONS: Array[String] = [
	InstitutionContract.R_NO_KIND,
	InstitutionContract.R_DUPLICATE_KIND,
	InstitutionContract.R_NOT_A_CAPABILITY,
	InstitutionContract.R_NO_CAPABILITY,
	InstitutionContract.R_CONTRACT_FAILED,
	InstitutionContract.R_UNKNOWN_KIND,
]


## A capability that is correct on every axis the family checks EXCEPT that it
## writes into the context it was handed. `InstitutionContract.register` must
## refuse the whole kind at `contract_failed` — a verb that mutates its context
## makes "a refusal writes nothing" unassertable and a preview indistinguishable
## from an execution.
class _MutatingCapability:
	extends InstitutionCapability

	func capability_id() -> StringName:
		return &"mutating_probe"

	func check(ctx: Dictionary) -> Dictionary:
		ctx["touched"] = true
		return {"ok": true, "reason": "", "unmet": []}


## A capability that refuses with a word it does not declare. The refusal shape
## is right and the VOCABULARY is wrong, which is exactly the defect a caller
## comparing reasons cannot see unless registration catches it: a reason that is
## not in `reasons()` is a panel comparing against a set it can never match.
class _UnnamedRefusalCapability:
	extends InstitutionCapability

	func capability_id() -> StringName:
		return &"unnamed_refusal_probe"

	func check(_ctx: Dictionary) -> Dictionary:
		return InstitutionCapability.refuse("mystery")


## A capability that proposes on every lifecycle verb, so the fold's
## keyed-by-capability-id merge has something real to fold.
class _ProposingCapability:
	extends InstitutionCapability

	var _id: StringName

	func _init(id: StringName = &"proposing_probe") -> void:
		_id = id

	func capability_id() -> StringName:
		return _id

	func on_found(_ctx: Dictionary) -> Dictionary:
		return {"ok": true, "reason": "", "plan": {"seat": "probe"}}

	func on_join(_ctx: Dictionary) -> Dictionary:
		return {"ok": true, "reason": "", "plan": {"opened": "probe_duty"}}


## A capability whose join refuses BY NAME, so the fold's first-refusal-wins
## path can be asserted with the capability's own word.
class _RefusingJoiner:
	extends InstitutionCapability

	func capability_id() -> StringName:
		return &"refusing_joiner"

	func own_reasons() -> Array[String]:
		return ["probe_refused"]

	func on_join(_ctx: Dictionary) -> Dictionary:
		return InstitutionCapability.refuse("probe_refused")


func setup() -> void:
	# The registry is process state and every suite shares one process, so it is
	# cleared on BOTH ends: `setup` clears what a previous suite left, `teardown`
	# clears what this one does.
	InstitutionContract.instance().clear()
	expect_assertions(2)


func teardown() -> void:
	InstitutionContract.instance().clear()


# --- identity and the lookup vocabulary -------------------------------------------


## Every capability the STANDARD publishes ships a class, the class names the id
## it is published under, and the base — which names nothing — reports that fact
## in its own suite rather than registering silently under an empty name.
func test_every_standard_capability_ships_a_named_class() -> void:
	assert_eq(InstitutionContract.STANDARD.size(), 8, "the standard publishes eight capabilities")
	for capability_id in InstitutionContract.STANDARD:
		var impl := _class_for(capability_id)
		assert_ne(impl, null, "%s ships a class" % capability_id)
		assert_eq(
			String(impl.capability_id()), String(capability_id), "%s names itself" % capability_id
		)
		assert_eq(
			impl.contract_findings().is_empty(), true, "%s passes its own suite" % capability_id
		)
	var bare := InstitutionCapability.new()
	assert_eq(bare.capability_id(), &"", "the base names nothing")
	assert_eq(bare.contract_findings().is_empty(), false, "and its own suite reports exactly that")


## The three-state lookup vocabulary, on the two answers a bare boolean would
## collapse: `{ok: false, reason: "unknown_kind"}` is "no such kind" and
## `{ok: true, reason: "", has: false}` is "this kind exists and carries no
## such capability". A caller that could not tell them apart would gate a press
## on a kind that does not exist.
func test_unknown_kind_is_a_refusal_while_a_missing_capability_is_not() -> void:
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(contract.register(&"lookup_probe", [AdmitTable.new()]).get("ok", false)),
		true,
		"the probe kind registers"
	)
	var unknown := contract.of(&"nobody_registered_this", &"admit_table")
	assert_eq(bool(unknown.get("ok", false)), false, "an unknown kind is refused")
	assert_eq(String(unknown.get("reason", "")), InstitutionContract.R_UNKNOWN_KIND, "by name")
	assert_eq(bool(unknown.get("has", true)), false, "and carries no capability")
	var missing := contract.of(&"lookup_probe", &"expellable")
	assert_eq(bool(missing.get("ok", false)), true, "a known kind is not refused")
	assert_eq(String(missing.get("reason", "")), "", "and answers with no reason")
	assert_eq(
		bool(missing.get("has", true)), false, "because the capability is absent, not refused"
	)
	assert_eq(unknown["has"] == missing["has"], true, "both say `has: false`, and that is why the")
	assert_ne(unknown["ok"], missing["ok"], "two answers are told apart by `ok` and `reason`")
	var present := contract.of(&"lookup_probe", &"admit_table")
	assert_eq(bool(present.get("has", false)), true, "and a carried capability is here")
	assert_eq(present.get("capability") is InstitutionCapability, true, "as a live implementation")


# --- registration refusals ---------------------------------------------------------


## Every shape fault the dispatcher can answer on its own, each refused BY NAME
## and none of them writing a row: no kind, a non-capability entry, an unnamed
## implementation, a duplicate kind. A kind is never half-registered.
func test_register_refuses_every_broken_shape_by_name() -> void:
	var contract := InstitutionContract.instance()
	assert_eq(
		String(contract.register(&"", []).get("reason", "")),
		InstitutionContract.R_NO_KIND,
		"a registration with no kind is refused `no_kind`"
	)
	assert_eq(
		String(contract.register(&"bad_entry", [RefCounted.new()]).get("reason", "")),
		InstitutionContract.R_NOT_A_CAPABILITY,
		"an entry that is not a capability is refused `not_a_capability`"
	)
	assert_eq(contract.knows(&"bad_entry"), false, "and no row was written")
	assert_eq(
		String(contract.register(&"empty_name", [InstitutionCapability.new()]).get("reason", "")),
		InstitutionContract.R_NO_CAPABILITY,
		"an unnamed capability is refused `no_capability`"
	)
	assert_eq(contract.knows(&"empty_name"), false, "and no row was written")
	assert_eq(
		bool(contract.register(&"duplicate_probe", [AdmitTable.new()]).get("ok", false)),
		true,
		"the first registration"
	)
	assert_eq(
		String(contract.register(&"duplicate_probe", [AdmitTable.new()]).get("reason", "")),
		InstitutionContract.R_DUPLICATE_KIND,
		"and the second is refused `duplicate_kind`, never idempotent"
	)


## A duplicate capability INSIDE one call is folded rather than refused: the
## same implementation named twice states the same thing twice, which is an
## authoring slip with no second meaning — unlike a duplicate KIND, which is two
## owners of one identity.
func test_a_duplicate_capability_in_one_call_is_folded() -> void:
	var contract := InstitutionContract.instance()
	var impl := AdmitTable.new()
	var answer := contract.register(&"folded_probe", [impl, impl])
	assert_eq(bool(answer.get("ok", false)), true, "the kind registers")
	var carried: Array = answer.get("capabilities", [])
	assert_eq(carried.size(), 1, "the duplicate is folded rather than listed twice")
	assert_eq(String(carried[0]), "admit_table", "and it is the capability named")


# --- D3: the red path ---------------------------------------------------------------


## ## The case the whole mechanism exists for, and its RED PATH
##
## A capability that mutates the context it was handed must fail its own suite
## and the KIND must be refused at `contract_failed`, with the findings
## published on the refusal. This is D3: "a pack claiming a capability must
## pass that capability's contract suite at load or its kind is refused by
## name" — enforced in `register` via `contract_findings()`.
func test_d3_a_capability_that_mutates_its_context_is_refused_at_registration() -> void:
	var broken := _MutatingCapability.new()
	var findings := broken.contract_findings()
	assert_eq(findings.is_empty(), false, "the mutant fails its own suite")
	assert_eq(_names(findings, "mutated the context").is_empty(), false, "naming the mutation")
	var contract := InstitutionContract.instance()
	var answer := contract.register(&"mutant_kind", [broken])
	assert_eq(bool(answer.get("ok", false)), false, "and the KIND is refused")
	assert_eq(String(answer.get("reason", "")), InstitutionContract.R_CONTRACT_FAILED, "by name")
	assert_eq(String(answer.get("capability", "")), "mutating_probe", "naming the offender")
	assert_eq(
		(answer.get("findings", []) as Array).is_empty(), false, "and publishing its findings"
	)
	assert_eq(contract.knows(&"mutant_kind"), false, "no row was written for a failed kind")


## The second red shape: a refusal that does not name itself in the
## capability's own vocabulary. The answer shape is right, so nothing but the
## suite can see it — which is precisely why registration runs the suite.
func test_d3_a_capability_that_refuses_without_naming_itself_is_refused() -> void:
	var broken := _UnnamedRefusalCapability.new()
	var findings := broken.contract_findings()
	assert_eq(findings.is_empty(), false, "the mutant fails its own suite")
	assert_eq(
		_names(findings, "not a named reason").is_empty(), false, "naming the unnamed refusal"
	)
	var contract := InstitutionContract.instance()
	var answer := contract.register(&"unnamed_kind", [broken])
	assert_eq(String(answer.get("reason", "")), InstitutionContract.R_CONTRACT_FAILED, "refused")
	assert_eq(String(answer.get("capability", "")), "unnamed_refusal_probe", "naming the offender")


## A kind with a good capability AND a broken one is refused WHOLE: the row is
## built from the caller's own snapshot and only written after every entry
## passed, so a kind is never half-registered with one capability of two.
func test_a_kind_with_one_broken_capability_is_refused_whole() -> void:
	var contract := InstitutionContract.instance()
	var answer := contract.register(&"half_probe", [AdmitTable.new(), _MutatingCapability.new()])
	assert_eq(bool(answer.get("ok", false)), false, "the kind is refused")
	assert_eq(String(answer.get("capability", "")), "mutating_probe", "at the broken entry")
	assert_eq(contract.knows(&"half_probe"), false, "and NOTHING of it was registered")
	assert_eq(
		contract.of(&"half_probe", &"admit_table")["reason"],
		InstitutionContract.R_UNKNOWN_KIND,
		"so even the good capability is unreachable"
	)


# --- the fold -------------------------------------------------------------------------


## The lifecycle verbs fold EVERY capability in canonical order and merge the
## plans under each capability's OWN id — never flattened, because two
## capabilities proposing one key is a collision the caller cannot resolve.
func test_the_fold_keys_every_plan_by_its_capability() -> void:
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(
			(
				contract
				. register(
					&"fold_kind",
					[
						_ProposingCapability.new(&"first_probe"),
						_ProposingCapability.new(&"second_probe")
					]
				)
				. get("ok", false)
			)
		),
		true,
		"the two-capability kind registers"
	)
	var found := contract.on_found(&"fold_kind", {})
	assert_eq(bool(found.get("ok", false)), true, "the fold succeeds")
	var plan: Dictionary = found.get("plan", {})
	assert_eq(plan.size(), 2, "one plan per capability")
	assert_eq(plan.has("first_probe"), true, "keyed by the first id")
	assert_eq(plan.has("second_probe"), true, "keyed by the second id")
	assert_eq((plan["first_probe"] as Dictionary).has("seat"), true, "and the row rides inside")
	var joined := contract.on_join(&"fold_kind", {})
	_judge_shape(found, "on_found")
	_judge_shape(joined, "on_join")


## The first refusal refuses the WHOLE verb, names the capability it came from,
## and returns NO plan: a half-applied join is the state nobody authorises, and
## the applier relies on "refused" meaning "nothing was proposed to write".
func test_the_fold_refuses_whole_at_the_first_refusal() -> void:
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(contract.register(&"refuse_kind", [_RefusingJoiner.new()]).get("ok", false)),
		true,
		"a capability whose join refuses still registers — refusing on a verb is policy"
	)
	var answer := contract.on_join(&"refuse_kind", {})
	assert_eq(bool(answer.get("ok", false)), false, "the join is refused")
	assert_eq(String(answer.get("reason", "")), "probe_refused", "with the capability's own word")
	assert_eq(String(answer.get("capability", "")), "refusing_joiner", "naming which one refused")
	assert_eq(answer.has("plan"), false, "and carrying NO plan")


## A non-positive period count is refused by the DISPATCHER before any
## capability runs: a period verb that moved nothing is indistinguishable from
## one that never ran, so it fails loud at the shared door.
func test_on_period_refuses_a_non_positive_period_count() -> void:
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(contract.register(&"period_kind", [_ProposingCapability.new()]).get("ok", false)),
		true,
		"the kind registers"
	)
	var answer := contract.on_period(&"period_kind", {}, 0)
	assert_eq(bool(answer.get("ok", false)), false, "zero periods is a refusal")
	assert_eq(String(answer.get("reason", "")), InstitutionCapability.R_NO_PERIODS, "by name")
	assert_eq(answer.has("plan"), false, "and proposes nothing")


# --- refusals write nothing -----------------------------------------------------------


## ADR 0044, measured on the exact object each verb was handed: the context is
## byte-identical after a refusal, compared by `JSON.stringify` against a
## snapshot taken BEFORE the call. The copy is taken first on purpose — a
## duplicate made afterwards would be pristine no matter what the verb did,
## which is a check that can never fire.
func test_every_refusal_writes_nothing_to_the_context_it_was_handed() -> void:
	var expellable := Expellable.new()
	var unpowered := {
		"kind": "probe",
		"institution": "probe",
		"authorities": [],
		"member": "probe_member",
		"target": "probe_target",
		"target_member": true,
		"target_authorities": [],
		"cost_expelled": 3,
		"cost_expeller": 9,
	}
	var pristine := JSON.stringify(unpowered)
	var handed := unpowered.duplicate(true)
	var answer := expellable.expel(handed)
	assert_eq(String(answer.get("reason", "")), Expellable.R_NOT_AUTHORISED, "the refusal is named")
	assert_eq(JSON.stringify(handed), pristine, "and the exact object handed is byte-identical")
	var contract := InstitutionContract.instance()
	var kind_ctx := {"kind": "somewhere", "institution": "somewhere"}
	var ctx_pristine := JSON.stringify(kind_ctx)
	var ctx_handed := kind_ctx.duplicate(true)
	var unknown := contract.check(&"no_such_kind", ctx_handed)
	assert_eq(String(unknown.get("reason", "")), InstitutionContract.R_UNKNOWN_KIND, "refused")
	assert_eq(JSON.stringify(ctx_handed), ctx_pristine, "and the dispatcher wrote nothing either")


# --- clear ----------------------------------------------------------------------------


## The registry is process state, so `clear()` is part of the surface and not a
## test convenience: the runner drives every suite in ONE process, so a
## registration a suite forgets to clear is handed to every suite after it.
func test_clear_drops_every_row_and_answers_how_many() -> void:
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(contract.register(&"clear_one", [AdmitTable.new()]).get("ok", false)), true, "one"
	)
	assert_eq(
		bool(contract.register(&"clear_two", [Authorised.new()]).get("ok", false)), true, "two"
	)
	assert_eq(contract.kinds().size() >= 2, true, "both are known")
	var dropped := contract.clear()
	assert_eq(dropped >= 2, true, "clear answers how many rows it dropped")
	assert_eq(contract.knows(&"clear_one"), false, "and the rows are gone")
	assert_eq(contract.clear(), 0, "a second clear is idempotent, answering zero")


# --- helpers --------------------------------------------------------------------------


## The class every STANDARD id is published under. A `match` rather than a
## lookup table so a missing arm is a `null` the case above names, never a
## silently absent row.
func _class_for(capability_id: StringName) -> InstitutionCapability:
	match capability_id:
		&"admit_table":
			return AdmitTable.new()
		&"authorised":
			return Authorised.new()
		&"dutiable":
			return Dutiable.new()
		&"expellable":
			return Expellable.new()
		&"schismatic":
			return Schismatic.new()
		&"successive":
			return Successive.new()
		&"teachable":
			return Teachable.new()
		&"territorial":
			return Territorial.new()
	return null


## The findings whose text contains `needle`, so a case can assert WHICH rule
## fired rather than only that something did.
func _names(findings: Array[String], needle: String) -> Array[String]:
	var out: Array[String] = []
	for entry in findings:
		if entry.contains(needle):
			out.append(entry)
	return out


## The shared shape every fold answer must hold on both paths.
func _judge_shape(answer: Dictionary, label: String) -> void:
	assert_eq(answer.has("ok"), true, "%s carries `ok`" % label)
	assert_eq(answer.has("reason"), true, "%s carries `reason`" % label)
	assert_eq(
		InstitutionCapability.is_primitive_payload(answer), true, "%s is primitives-only" % label
	)
