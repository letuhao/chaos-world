extends TestCase

## ADR 0061 / ADR 0083: **the once-guard, and the test that proves it FIRES.**
##
## ## Why this is its own file
##
## `test_event.gd` already carries the claim that the guard is *written from the
## ledger* — that `paid` and `active` cannot disagree because they are written
## together. That claim is true and it is cheap, but it is NOT the claim that
## matters. A guard nobody has ever seen fire is a comment, not a guard, so this
## file exists to make the guard **load-bearing**: delete it and something here
## goes red.
##
## ## What was UNPROVEN, and precisely why
##
## `EventApi._pay` opens with `if EventState.has_paid(ledger, event_id): return
## ...already_paid` (`game/src/modules/event/api.gd`). A reader of the existing
## suite could delete that branch and every test would still pass, because:
##
##   - `advance` reaches `_pay` only for an ACTIVE event, and `_pay` writes `paid`
##     and erases `active` in the SAME write. A resolved event is therefore never
##     active again, so `advance` can never call `_pay` on a paid event.
##   - `begin` refuses an event with `already_resolved` before any pay is reached.
##   - `has_fate` is a BOOLEAN over a set that holds a fate once, so even a double
##     `earn_fate` would not move it.
##
## So the branch had **zero reachable callers in the whole suite**. That is the
## "green is not evidence" failure in its purest form: the tests described the
## guard and never executed it.
##
## ## The state that makes it reachable
##
## The one state in which `_pay` is re-entered with `paid` already set is **an
## active row for an event whose prize was already granted** — the torn write
## between `_pay`'s two ledger mutations, or a save restored mid-resolution. No
## module verb produces it, which is correct: a verb that produced it would be the
## bug. `resolve` is the only verb that can then REACH `_pay` with that row live,
## because for a non-conflict event `resolve` delegates straight to `_pay`.
##
## This test therefore reconstructs the torn ledger by hand and calls `resolve`
## twice. It is the only test in the module that mutates `module_data` directly to
## build an impossible state, and the comment says why at the point of the write.

const TREASURE := &"the_stone_that_answering"
## The `nation_standing` row on the treasure's `pay`. A NUMBER, not a boolean —
## see `_actor`'s note on why the standing is the probe and not the fate.
const STANDING_ROW := "march_of_the_nine_provinces"


## An actor founded in the March and standing in the transcendent realm, so the
## treasure — whose prize includes a `nation_standing` row — can open.
##
## **The probe is the STANDING, not the fate.** The treasure also pays a fate
## (`heaven_s_warning_unread`), and `has_fate` is a boolean over a once-set, so a
## second grant would be invisible: the assertion would pass with the guard
## deleted. Standing is an accumulating NUMBER (clamped at `standing_cap`, which
## the authored claim leaves well above the first grant), so paying twice moves it
## twice. That is what makes this a real probe rather than a re-read of a flag.
func _actor(at: String = &"transcendent_realm") -> Actor:
	var actor := Actor.new(&"event_once_guard_actor", {Stat.PHYSIQUE: 10.0})
	DestinyApi.attach(actor)
	NationApi.attach(actor)
	EventApi.attach(actor)
	NationApi.found(actor, &"march_of_the_nine_provinces", String(actor.id))
	EventApi.set_location(actor, at)
	return actor


## **THE MUTATION TEST.** Remove `has_paid`'s early-return from
## `EventApi._pay` and this goes red, which is what makes the guard load-bearing
## rather than described.
func test_a_paid_but_still_active_event_is_not_paid_a_second_time() -> void:
	var actor := _actor()
	EventApi.begin(actor, TREASURE)
	var first := EventApi.resolve(actor, TREASURE)
	assert_eq(bool(first.get("paid", false)), true, "the first resolution pays: %s" % first)
	var standing_after_first := int(NationApi.summary(actor)["standing"])
	assert_eq(
		standing_after_first > 0, true, "and the standing row moved a real number, not a flag"
	)
	var period_of_the_first_pay := EventState.resolved_period(EventApi.state(actor), TREASURE)

	# **The torn write.** The active row is restored by hand with `paid` left set —
	# precisely what a crash between `_pay`'s two ledger mutations leaves behind, and
	# what no module verb may ever produce. Written through the persisted module
	# data, because writing it through a verb would be inventing the bug this guards.
	var ledger := EventApi.state(actor)
	(ledger["active"] as Dictionary)[String(TREASURE)] = {
		"stage_id": "read",
		"opened_period": 0,
		"periods_held": 0,
		"last_resolved_period": 0,
		"territory_id": "",
		"standoff_id": "",
		"declared": false,
		"history": [],
	}
	# `resolved` is deliberately left in place: it is what makes `begin` refuse, and
	# this test is about `resolve` reaching a paid row, not about reopening.
	actor.set_module_data(EventState.MODULE_KEY, ledger)
	assert_eq(
		EventState.has_paid(EventApi.state(actor), TREASURE), true, "the ledger is torn: paid"
	)
	assert_eq(EventState.is_active(EventApi.state(actor), TREASURE), true, "and still active")

	# **The second resolution re-enters `_pay` with a live row** — the only way back
	# into it, and the only place `has_paid` has ever been executed by a test.
	var second := EventApi.resolve(actor, TREASURE)
	assert_eq(
		bool(second.get("already_paid", false)), true, "the guard answers instead of paying again"
	)
	assert_eq(bool(second.get("ok", false)), true, "and still reports the resolution, not a crash")
	assert_eq(
		(second["granted"] as Array).size(),
		0,
		"granting nothing — the early-return names the already-paid row rather than paying"
	)
	assert_eq(
		int(NationApi.summary(actor)["standing"]),
		standing_after_first,
		"**the standing is unchanged**, which is the assertion that dies with the guard"
	)
	assert_eq(
		EventState.resolved_period(EventApi.state(actor), TREASURE),
		period_of_the_first_pay,
		"and `resolved` still names the period the FIRST pay recorded"
	)


## The guard's refusal is **a report, not a crash and not a silent success**. ADR
## 0083's third state: the action EXISTS and is refused, and the payload carries
## the ids it concerns. A caller rendering "what happened to my prize" reads
## `already_paid`, and the guard's own period is handed back so the caller does not
## have to invent one.
func test_the_once_guard_reports_the_period_it_already_recorded() -> void:
	var actor := _actor()
	EventApi.begin(actor, TREASURE)
	EventApi.resolve(actor, TREASURE)
	var ledger := EventApi.state(actor)
	var period := EventState.resolved_period(ledger, TREASURE)
	assert_eq(period >= 0, true, "the first resolution recorded a real period")

	(ledger["active"] as Dictionary)[String(TREASURE)] = {
		"stage_id": "read",
		"opened_period": 0,
		"periods_held": 0,
		"last_resolved_period": 0,
		"territory_id": "",
		"standoff_id": "",
		"declared": false,
		"history": [],
	}
	actor.set_module_data(EventState.MODULE_KEY, ledger)

	var again := EventApi.resolve(actor, TREASURE)
	assert_eq(String(again.get("event_id", "")), String(TREASURE), "the refusal NAMES the event")
	assert_eq(
		int(again.get("resolved_period", -1)),
		period,
		"and reports the period the ledger already holds, not the one this call saw"
	)
	assert_eq(bool(again.get("paid", false)), true, "and still says the prize WAS paid — once")


## The standing row is what makes the guard observable; this pins that the prize
## being probed actually contains one, so a future re-authoring that drops it makes
## the mutation test above vacuous and THAT goes red rather than the guard.
func test_the_probed_prize_really_moves_a_number() -> void:
	var actor := _actor()
	var def := EventCatalog.instance().event_definition(TREASURE)
	assert_ne(def, null, "the treasure is in the catalog")
	var numeric_rows := 0
	for row in def.pay:
		if StringName(row.get("kind", "")) == EventDef.PAY_NATION_STANDING:
			numeric_rows += 1
	assert_eq(numeric_rows > 0, true, "the prize has a numeric row, or the guard probe is vacuous")
	assert_eq(
		String(STANDING_ROW),
		"march_of_the_nine_provinces",
		"and it pays the nation this file's fixture founded"
	)
