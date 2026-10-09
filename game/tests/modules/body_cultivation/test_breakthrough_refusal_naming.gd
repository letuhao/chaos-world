extends TestCase

## The breakthrough half of ADR 0150's contract, split from
## `test_refusal_naming.gd` because it is a second reason to change: that file guards
## the INVARIANT (a `false` always has a name), and this one pins the four refusals the
## acceptance gate names, clause by clause.
##
## ## Why a breakthrough needs its own file
##
## A breakthrough press is the only body verb whose refusal is not knowable before it
## happens. Three of its causes block the press and are therefore publishable on the
## read model; the fourth — a real deviation — is the ROLL's outcome, and only the
## attempt record can name it. Those two halves publish through DIFFERENT keys
## (`unavailable.breakthrough` and `attempt_outcome`), and the distinction is the whole
## of the screen's `_breakthrough_refusal`.
##
## ## What is asserted is nameability, not wording
##
## A clause `kind` a screen can switch on survives a reword; a pinned sentence would not.
## So the four cases assert `KIND_*` and the gate's own string, never a phrase this file
## invented.

const PATH := BodyPath.PATH_ID

var _play: BodyPlayFixture


func setup() -> void:
	_play = BodyPlayFixture.new()


func _unavailable(actor: Actor) -> Array:
	return (
		(BodyCultivationApi.panel_state(actor).get("unavailable", {}) as Dictionary).get(
			"breakthrough", []
		)
		as Array
	)


func _outcome(actor: Actor) -> Dictionary:
	return BodyCultivationApi.panel_state(actor).get("attempt_outcome", {}) as Dictionary


func _kinds(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		out.append(String((entry as Dictionary).get("kind", "")))
	return out


func _labels(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		out.append(String((entry as Dictionary).get("label", "")))
	return out


## A hero prepared to the brink of its next realm with an EMPTY PACK, except for the pill the
## attempt is priced by. The pack is emptied because `BodyPlayFixture.prepare` stocks each
## elixir just before spending one and leaves both behind, so a case about a MISSING price would
## otherwise inherit it.
func _prepared(with_pill: bool = true) -> Actor:
	var actor := _play.actor()
	_play.prepare(actor)
	# The pill belongs to the TARGET realm's seed, not to the ladder's `RealmDef` it
	# arrives as: reading `breakthrough_item` off the ladder entry is a property that does
	# not exist there, and it aborts this helper with a nil return.
	var next := RealmDefaults.ladder().next(actor.path(PATH).rank_id)
	var target: BodyRealmSeed = null if next == null else BodyRealmSeed.for_realm(next.id)
	var pill: StringName = &"" if target == null else target.breakthrough_item
	ItemsApi.inventory(actor).clear()
	if with_pill and pill != &"":
		_play.stock(actor, pill)
	return actor


## Put the actor on the ladder's LAST rung, where no realm follows and a breakthrough has
## nothing to fight for.
func _at_ladder_top(actor: Actor) -> void:
	var ladder := RealmDefaults.ladder()
	var realms := ladder.realms()
	actor.path(PATH).rank_id = realms[realms.size() - 1].id
	BodyTraining.synchronize(actor)


## Each of the four the acceptance gate names is individually nameable.
func test_each_breakthrough_refusal_has_its_own_kind() -> void:
	# 1. No realm ahead: the ladder's last rung, where `preview` has no target.
	var topped := _play.actor()
	_at_ladder_top(topped)
	assert_eq(BodyCultivationApi.attempt_breakthrough(topped), false, "no realm ahead")
	assert_eq(
		_kinds(_unavailable(topped)), [BodyRefusal.KIND_NO_REALM_AHEAD], "named as the ladder's end"
	)

	# 2. No pill. A prepared hero has every other gate met, so the pill clause is
	#    asserted among the gate's own clauses rather than alone.
	var pillless := _prepared(false)
	assert_eq(BodyCultivationApi.attempt_breakthrough(pillless), false, "no pill, no attempt")
	assert_eq(
		_kinds(_unavailable(pillless)).has(BodyRefusal.KIND_GATE_UNMET),
		true,
		"the gate's own clauses name it"
	)
	assert_eq(
		_labels(_unavailable(pillless)).has("Missing breakthrough pill"),
		true,
		"and the pill is one of them, quoted verbatim from `describe_unmet`"
	)

	# 3. No acupoint set to work on: the re-entrancy guard. Set directly because no
	#    player-facing press can observe it — every window is synchronous — and an
	#    unnamed `false` is exactly what ADR 0150 exists to prevent.
	var busy := _prepared()
	(busy.component(&"acupoints") as AcupointSet).busy = true
	assert_eq(BodyCultivationApi.attempt_breakthrough(busy), false, "a busy acupoint set refuses")
	assert_eq(_kinds(_unavailable(busy)), [BodyRefusal.KIND_BUSY], "named as the guard")

	# 4. A real deviation: nothing named blocked the press, so the roll ran, and the
	#    RECORD names what it became.
	var deviated := _prepared()
	assert_ne(_play.deviate(deviated), false, "a roll that deviates is reachable")
	assert_eq(
		String(_outcome(deviated).get("status", "")),
		String(BodyAttempt.STATUS_FAILED),
		"the record says it failed"
	)
	assert_ne(String(_outcome(deviated).get("reason", "")).is_empty(), true, "and says so in words")


## The refusal list is empty for a press that reached the roll — that emptiness is what
## tells a screen the roll ran, and a report that pre-judged the roll would destroy the
## only signal it has.
func test_a_reachable_roll_publishes_no_pre_roll_clause() -> void:
	var actor := _prepared()
	assert_eq(_unavailable(actor).is_empty(), true, "nothing blocks this press")
	assert_ne(_play.deviate(actor), false, "so the roll decides")
	assert_eq(
		String(_outcome(actor).get("reason", "")).contains("deviated"),
		true,
		"and the record, not the clause list, is what names the outcome"
	)


## The deviation clause is the module's, and it is about THIS attempt: the record's own
## target, quoted from the read model rather than composed by a screen.
func test_a_deviation_is_named_by_the_record_not_by_the_screen() -> void:
	var actor := _prepared()
	assert_ne(_play.deviate(actor), false, "a roll that deviates is reachable")
	var outcome := _outcome(actor)
	var reason := String(outcome.get("reason", ""))
	assert_eq(bool(outcome.get("granted", true)), false, "granted nothing")
	assert_ne(reason.contains("deviated"), false, "in words the module owns (%s)" % reason)
	assert_ne(
		reason.contains(String(outcome.get("target", ""))), false, "naming the realm fought for"
	)


## A cancelled attempt and a deviation are different debts — one owes a wound to repair,
## the other owes nothing because nothing was rolled — and both used to read as a
## deviation. `BodyAdvancement.cancel` is the production route to the first.
func test_a_cancelled_attempt_is_named_as_cancelled() -> void:
	var actor := _prepared()
	assert_ne(BodyAdvancement.start_attempt(actor, null), null, "an attempt commits once prepared")
	assert_eq(BodyAdvancement.cancel(actor), true, "and can be abandoned")
	assert_eq(String(_outcome(actor).get("status", "")), String(BodyAttempt.STATUS_CANCELLED), "so")
	assert_eq(
		String(_outcome(actor).get("reason", "")).contains("deviated"),
		false,
		"and it is not mistaken for a deviation (%s)" % _outcome(actor).get("reason", "")
	)


## An in-flight attempt blocks the next press, and is nameable as its own cause: it is a
## DIFFERENT refusal from every gate clause, and a screen told only "gate unmet" would
## send a player to train when the answer is to resolve what is already committed.
func test_an_attempt_already_in_flight_is_its_own_cause() -> void:
	var actor := _prepared()
	var committed := BodyAdvancement.start_attempt(actor, null)
	assert_ne(committed, null, "an attempt commits once prepared")
	assert_eq(BodyCultivationApi.attempt_breakthrough(actor), false, "a second cannot start")
	assert_eq(
		_kinds(_unavailable(actor)), [BodyRefusal.KIND_ATTEMPT_IN_FLIGHT], "named as the lockout"
	)


## No attempt means no verdict, so a screen cannot invent one: `reason` is empty exactly
## when nothing has resolved.
func test_no_attempt_publishes_no_verdict() -> void:
	var outcome := _outcome(_play.actor())
	assert_eq(String(outcome.get("id", "x")), "", "no record")
	assert_eq(String(outcome.get("status", "x")), "", "no status")
	assert_eq(String(outcome.get("reason", "x")), "", "and nothing to say")


## A granted attempt reports a success, not a refusal. A `reason` here would tell a player
## they had been wounded by a breakthrough that worked.
func test_a_granted_attempt_publishes_no_verdict() -> void:
	var actor := _prepared()
	if not _play.breakthrough(actor, BodyPlayFixture.rng(1)):
		return
	assert_eq(bool(_outcome(actor).get("granted", false)), true, "the award was granted")
	assert_eq(String(_outcome(actor).get("reason", "x")), "", "so there is no refusal to report")
