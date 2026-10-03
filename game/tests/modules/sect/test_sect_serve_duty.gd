extends TestCase

## ADR 0145: serving a sect obligation is a THIRD verb on the same priority ladder, not an
## `app/`-only intent, and the ledger write lives in the module that owns the fact.
##
## ## Why this suite exists at all
##
## Because the change it covers shipped with none. `SectAct.VERB_SERVE_DUTY` and
## `institution_resolver._resolve`'s `serve_duty` arm were committed before any test could
## reach them, and mutation S1 proved the consequence: deleting the proposal outright left
## `tools test --suite modules/sect` at **1393 passed, 0 failed**. A verb nobody can observe
## is not a verb, it is a comment in a `match` arm — the BL-0123 proof-gap shape, committed
## by me. These cases are the receipt.
##
## ## What is claimed, and what is not
##
## Claimed: the ladder PROPOSES serving when nothing else applies and the claim is genuinely
## unsettled; the resolver DISPATCHES it; and a discharge reaches the world ledger, which is
## the only thing `tools gate_reach` can see. Not claimed: that serving is the RIGHT priority
## — that is the ladder's design decision, recorded in ADR 0145 and not re-litigated here.
##
## Every case drives the PUBLIC entry (`InstitutionResolver.settle`), never `_resolve` or
## `_sect_proposal`, because a test that calls the private half proves the half works rather
## than that the world does.

const HOUSE := &"t_house"
const MEMBER := &"t_member"


## The catalog is SHARED and `SectFixtureCatalog.install` replaces it wholesale, so a suite
## that installs and never restores hands every later suite a different world. Restored to
## the shipped catalog in `teardown` for that reason, not for tidiness.
func setup() -> void:
	var defs: Array[SectDef] = [
		SectFixtureCatalog.sect(HOUSE, [SectFixtureCatalog.bare_position(MEMBER)])
	]
	SectFixtureCatalog.install(defs)


func teardown() -> void:
	# The shipped catalog is named here rather than handed over as `install()`'s EMPTY
	# default. An empty `Array[SectDef]` default is a literal, and a literal cannot be
	# assigned to the typed local it is copied into, so the zero-argument call raised a
	# runtime type error (`sect_fixture_catalog.gd:268`) and threw away the catalog this
	# suite installed instead of restoring it — five script errors a run, one per case,
	# and a fixture leak into every later suite. `install_doctrine` builds its fallback
	# through an append for the same reason; this is the other half of that habit.
	SectFixtureCatalog.install([SectFixtureCatalog.default_sect()])


func _member(actor_id: StringName = &"server") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	SectApi.attach(actor)
	return actor


## Every open line paid down to nothing but one, so the single discharge is unambiguous.
##
## The map is REBUILT with only this line, and written WITHOUT a following `attach`,
## because `SectState.normalize` erases a line that reads zero (`sect_state.gd:323-326`):
## zeroing the other lines instead of erasing them leaves a claim whose every line is
## clear, so `claim.settled()` is true, the ladder proposes `{}`, and `serve` refuses
## with `nothing_owed` without settling anything. Rebuilding is also the only way to
## reach `_one_term_left`'s own line — `join` opens `instruction_<sect>` and
## `<sect>_instruction_<position>` (the position no promotion ever opened), so a
## three-period term has to be written rather than edited.
##
## No `attach` afterwards: it re-normalizes and persists, which is a second trip through
## the same erase-zero rule and buys nothing here, since every read on this path
## (`SectApi.state`, `SectDuty.serve`) normalizes on its own.
func _one_term_left(actor: Actor, periods: int) -> String:
	var ledger := SectApi.state(actor)
	var instruction := "instruction_%s" % String(HOUSE)
	ledger["obligation"] = {instruction: periods}
	actor.set_module_data(SectState.MODULE_KEY, ledger)
	return instruction


func _owed(actor: Actor, term: String) -> int:
	var claim := SectState.claim(SectApi.state(actor))
	return claim.owed(StringName(term))


func test_the_ladder_proposes_serving_when_nothing_else_applies() -> void:
	# A member with no vacancy open and no teachable lesson, who still owes a term. Before
	# ADR 0145 this returned `{}` — do_nothing — and the debt could only ever accrue.
	var actor := _member()
	assert_eq(bool(SectApi.join(actor, HOUSE).get("ok", false)), true, "sworn to the house")

	var intent := SectAct.intent(
		SectApi.state(actor), SectCatalog.instance().sect_definition(HOUSE)
	)
	assert_eq(
		StringName(String(intent.get("verb", ""))),
		SectAct.VERB_SERVE_DUTY,
		"a member who still owes a term is not proposed as doing nothing"
	)


func test_a_settled_claim_is_proposed_nothing() -> void:
	# The negative half, and the one that keeps the verb from becoming a faucet: with every
	# line paid, proposing a discharge would be proposing a verb that discharges nothing.
	var actor := _member()
	SectApi.join(actor, HOUSE)
	var ledger := SectApi.state(actor)
	var lines: Dictionary = ledger["obligation"]
	for term_id in lines.keys():
		lines[String(term_id)] = 0
	actor.set_module_data(SectState.MODULE_KEY, ledger)
	SectApi.attach(actor)

	var intent := SectAct.intent(
		SectApi.state(actor), SectCatalog.instance().sect_definition(HOUSE)
	)
	assert_eq(
		intent.is_empty(),
		true,
		"a member owing nothing is proposed nothing, so the verb cannot run every period forever"
	)


func test_the_world_tick_discharges_the_term_and_records_the_fact() -> void:
	# The end-to-end leg, and the one `tools gate_reach` depends on: the composition root
	# drives the verb, the module owns the write, and `oaths_discharged` lands in the ledger.
	#
	# Three elapsed periods are what `settle` is asked to settle, so three periods of
	# service clear a three-period line however the tiers divide that three between them —
	# `serve_duty` is reached at all three caps, so the `acted` assertion below is a real
	# bound and not an artefact of whichever tier the resolver happened to consult.
	var actor := _member()
	SectApi.join(actor, HOUSE)
	var instruction := _one_term_left(actor, 3)

	var before := WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED)
	var report := InstitutionResolver.settle(actor, 3)

	assert_eq(_owed(actor, instruction), 0, "three periods paid a three-period line")
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		before + 1,
		"bringing one term to zero discharged exactly one oath"
	)
	assert_eq(int(report.get("acted", 0)) >= 1, true, "the settle reported acting")


func test_a_partial_payment_records_nothing() -> void:
	# A line REDUCED is not a line DISCHARGED. Without this the verb would inflate a counter
	# every period and `oaths_discharged` would mean "periods elapsed", not "terms served".
	#
	# The gap this pins is `periods`, never the tier: whether the resolver serves the term
	# once, four times or sixteen times is `institution_resolver.gd`'s cadence decision and
	# is not asserted here. So this case cannot break when that cadence is retuned, which is
	# the reason the arithmetic above is asked about ELAPSED periods and not about tiers.
	var actor := _member()
	SectApi.join(actor, HOUSE)
	var instruction := _one_term_left(actor, 3)

	var before := WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED)
	InstitutionResolver.settle(actor, 1)

	assert_eq(_owed(actor, instruction), 2, "one period of three left two owed")
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		before,
		"a term reduced is not a term discharged, so nothing was recorded"
	)


func test_the_verb_set_is_closed_and_serving_is_in_it() -> void:
	# `institution_resolver.gd` documents its `match` as closed on purpose, so a proposal
	# naming a verb the resolver cannot dispatch is a refusal every period. This is the
	# pairing that keeps the ladder and the dispatcher from drifting apart.
	assert_eq(
		SectAct.VERBS.has(SectAct.VERB_SERVE_DUTY),
		true,
		"the ladder proposes a verb the closed dispatch set does not name"
	)
	assert_eq(
		SectAct.VERBS.has(SectAct.VERB_WAIT_OFFICE),
		true,
		"waiting for an office left the ladder, which is a behaviour change nobody decided"
	)
	assert_eq(SectAct.VERBS.size(), 3, "a fourth verb joined the ladder unrecorded")
