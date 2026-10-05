extends TestCase

## ADR 0127: a soul outlives its body and lives in an injected store.
##
## ## The invariant that matters most
##
## **The ledger must live in the STORE, not in `actor.module_data`.** Every other module's
## state is per-actor and every other test in this repo passes when it is. A soul stored on the
## actor dies with the exact body it exists to outlive, and the failure is completely silent —
## which is why the first test here reads the actor's copy and asserts it is derived rather than
## asserting the soul's contents, which would pass either way.
##
## ## Assertion style
##
## The framework offers `assert_eq` / `assert_ne` / `assert_almost_eq` and nothing else, and
## every one requires a label. A boolean therefore asserts against its own negation, because
## `assert_eq(value, false, ...)` fails with the value in the report, which is what makes a
## boolean failure readable.

var _actor: Actor
var _store: SoulWorldLedger


func setup() -> void:
	_store = SoulWorldLedger.new()
	SoulApi.set_store(_store)
	_actor = Actor.new()
	_actor.id = &"soul_bearer"
	SoulApi.attach(_actor)


## The store is a process-wide static on the facade, so a suite that leaves it populated holds
## authored `SoulDef` content alive and lets the next suite read THIS suite's soul. Idempotent,
## and safe after an early return.
func teardown() -> void:
	_actor = null
	_store = null
	SoulApi.set_store(null)


# --- Where the ledger lives -------------------------------------------------


func test_the_ledger_lives_in_the_store_and_the_actor_carries_only_a_mirror() -> void:
	# ADR 0127's whole reason for existing. `module_data` has the actor's lifetime; a soul does
	# not. Asserting the soul's VALUES here would pass whether the truth is the store or the
	# actor, so this asserts the store is what changed and the actor's copy is derived.
	SoulApi.damage(_actor, 30, "test")
	assert_eq(int(_store.read_ledger()["integrity"]), 70, "the store holds the truth")
	assert_eq(
		(_actor.get_module_data(SoulState.MODULE_KEY) as Dictionary).is_empty(),
		false,
		"attach mirrors onto the actor so a save carries it"
	)


func test_the_soul_survives_the_actor_it_was_attached_to_being_discarded() -> void:
	# The whole feature in one assertion: the store is not the actor, so dropping the actor
	# drops nothing. A soul stored on `module_data` fails here and passes everywhere else.
	SoulApi.damage(_actor, 25, "test")
	_actor = null
	var fresh := Actor.new()
	fresh.id = &"second_body"
	assert_eq(int(SoulApi.soul(fresh).get("integrity", 0)), 75, "a new body reads the same soul")


func test_attach_is_idempotent_and_safe_before_a_soul_exists() -> void:
	var actor := Actor.new()
	actor.id = &"empty"
	SoulApi.attach(actor)
	SoulApi.attach(actor)
	assert_eq(
		int(SoulApi.soul(actor).get("integrity", -1)),
		SoulState.DEFAULT_INTEGRITY,
		"two attaches leave one soul"
	)


# --- Normalization ----------------------------------------------------------


func test_an_unreadable_payload_normalizes_to_empty_and_never_partially_applies() -> void:
	# Half a soul is worse than none: it would silently change what the player is owed a body
	# for. The `destiny_state` rule, applied to the numbers that decide a death.
	var out := SoulState.normalize({"integrity": "not a number", "lives": []})
	assert_eq(
		int(out["integrity"]), SoulState.DEFAULT_INTEGRITY, "unreadable integrity is the default"
	)
	assert_eq(int(out["lives"]), SoulState.DEFAULT_LIVES, "unreadable lives is the default")


func test_a_row_naming_an_unknown_arrival_is_dropped_rather_than_persisted() -> void:
	# A save written by a wider content build must not smuggle in an arrival this build does
	# not define, or the ledger would record a rebirth into something no content can explain.
	var out := SoulState.normalize(
		{"origins": ["the_walker_back_through_ash", "from_another_build"]},
		{"the_walker_back_through_ash": true}
	)
	assert_eq((out["origins"] as Array).size(), 1, "the unknown arrival is dropped")
	assert_eq(String(out["origin_id"]), "the_walker_back_through_ash", "the known one survives")


func test_the_damage_trail_is_bounded_so_a_save_cannot_grow_without_limit() -> void:
	# The `DestinyState.HISTORY_LIMIT` reason. A soul can die far more times than the cap.
	for _i in range(SoulState.HISTORY_LIMIT * 2):
		SoulApi.damage(_actor, 1, "test")
	assert_eq(
		(SoulApi.state(_actor)["damage"] as Array).size(),
		SoulState.HISTORY_LIMIT,
		"the trail keeps the recent past, not the whole run"
	)


func test_the_ledger_round_trips_through_a_json_hop_with_int_fields_int() -> void:
	# JSON has ONE number type: a copied amount comes back as a float and the ledger stops
	# comparing equal to itself across a save. Rebuilt field by field for that reason.
	SoulApi.damage(_actor, 7, "test")
	var once := SoulApi.state(_actor)
	var hopped: Dictionary = JSON.parse_string(JSON.stringify(once))
	var twice := SoulState.normalize(hopped, SoulCatalog.instance().known_arrivals())
	assert_eq(twice["integrity"], once["integrity"], "integrity survives as an int")
	assert_eq(typeof(twice["incarnation"]), TYPE_INT, "the incarnation is an int, not a float")


# --- Damage and repair ------------------------------------------------------


func test_damage_accumulates_across_incarnations_and_clamps_at_zero() -> void:
	SoulApi.damage(_actor, 60, "first")
	SoulApi.damage(_actor, 60, "second")
	assert_eq(int(SoulApi.soul(_actor)["integrity"]), 0, "integrity stops at zero, never below")


func test_damage_returns_what_it_actually_applied_not_what_it_was_asked_for() -> void:
	# A caller that over-reports must learn it over-reported, rather than the ledger
	# announcing a hit nothing took.
	var out := SoulApi.damage(_actor, 500, "overshoot")
	assert_eq(int(out["applied"]), SoulState.DEFAULT_INTEGRITY, "applied is the real delta")
	assert_eq(bool(out["ok"]), true, "the hit landed")


func test_repair_never_exceeds_the_maximum_and_never_lowers_integrity() -> void:
	SoulApi.damage(_actor, 40, "hurt")
	SoulApi.repair(_actor, 500, "over-repair")
	assert_eq(
		int(SoulApi.soul(_actor)["integrity"]), SoulState.DEFAULT_INTEGRITY, "capped at the ceiling"
	)
	assert_eq(
		bool(SoulApi.repair(_actor, -10, "negative")["ok"]), false, "a negative repair is refused"
	)


func test_repair_refuses_an_undamaged_soul_rather_than_reporting_a_gain() -> void:
	var out := SoulApi.repair(_actor, 10, "unneeded")
	assert_eq(int(out["applied"]), 0, "nothing moved")
	assert_eq(bool(out["ok"]), false, "an undamaged soul has nothing to repair")


# --- Rebirth ----------------------------------------------------------------


func test_incarnate_advances_the_incarnation_and_lowers_lives_exactly_once() -> void:
	var out := SoulApi.reincarnate(_actor, &"body_two")
	assert_eq(bool(out["ok"]), true, "the first rebirth lands: %s" % out.get("reason", ""))
	assert_eq(int(out["incarnation"]), 1, "one incarnation")
	assert_eq(int(SoulApi.soul(_actor)["lives"]), SoulState.DEFAULT_LIVES - 1, "one life spent")
	assert_eq(String(SoulApi.soul(_actor)["body_id"]), "body_two", "the new body is recorded")


func test_a_repeated_reincarnate_for_the_same_body_writes_nothing() -> void:
	# Re-running a resolution must not manufacture a second life cost. The once-rule of
	# ADR 0114: a beat is resolved once.
	SoulApi.reincarnate(_actor, &"body_two")
	var again := SoulApi.reincarnate(_actor, &"body_two")
	assert_eq(bool(again["ok"]), false, "the same body is refused: %s" % again.get("reason", ""))
	assert_eq(
		int(SoulApi.soul(_actor)["lives"]), SoulState.DEFAULT_LIVES - 1, "still one life spent"
	)


func test_a_soul_out_of_lives_cannot_rebody_and_the_reason_is_named() -> void:
	# Exhausted lives through the real verb, not by writing the ledger directly.
	for _i in range(SoulState.DEFAULT_LIVES):
		SoulApi.reincarnate(_actor, &"body_%d" % _i)
	var out := SoulApi.reincarnate(_actor, &"body_final")
	assert_eq(bool(out["ok"]), false, "no lives left")
	assert_eq(String(out["reason"]), "no_lives", "the refusal is named, not guessed at")


func test_the_next_arrival_is_the_first_unearned_one_and_is_never_offered_twice() -> void:
	# ADR 0130: the gate answers, the player never chooses. Determinism is the contract —
	# two souls that died identically must arrive identically.
	var first := String(SoulApi.next_arrival(_actor))
	assert_ne(first, "", "there is an arrival to earn")
	SoulApi.reincarnate(_actor, &"body_two")
	assert_ne(String(SoulApi.next_arrival(_actor)), first, "a spent arrival is never offered again")


func test_the_next_arrival_is_deterministic_so_two_souls_die_identically() -> void:
	var other := SoulWorldLedger.new()
	SoulApi.set_store(other)
	var other_actor := Actor.new()
	other_actor.id = &"other_bearer"
	SoulApi.attach(other_actor)
	assert_eq(
		String(SoulApi.next_arrival(_actor)),
		String(SoulApi.next_arrival(other_actor)),
		"the same ledger yields the same arrival"
	)


func test_the_arrival_is_the_gate_answer_and_not_a_caller_named_one() -> void:
	# `reincarnate` takes only a body id. A caller that could name its own arrival is the
	# picker ADR 0065 forbids, so the arrival is read from the gate, never from the caller.
	#
	# **The gate is asked again AFTER the write.** Asserting only `out["arrival"]` echoes the
	# value the same call just wrote and proves nothing: a gate that returned the SAME arrival
	# forever would pass it. This case therefore re-evaluates the gate afterwards, which is
	# what makes it fail when a death fails to mark its arrival spent — the ladder test in
	# `test_soul_arrival_ladder` carries the whole-ladder form of the same invariant.
	var expected := String(SoulApi.next_arrival(_actor))
	var out := SoulApi.reincarnate(_actor, &"body_two")
	assert_eq(String(out["arrival"]), expected, "the gate chose it")
	assert_ne(String(out["arrival"]), "", "an arrival was recorded even though none was requested")
	# Re-asked, not echoed: this is the assertion the old case was missing.
	assert_ne(
		String(SoulApi.next_arrival(_actor)),
		expected,
		"and the arrival just spent is not the one owed next"
	)
	assert_eq(
		(SoulApi.state(_actor)["origins"] as Array).has(expected),
		true,
		"the ledger is the receipt: it holds the arrival that was spent"
	)


# --- The verdict ------------------------------------------------------------


func test_the_verdict_answers_both_halves_so_a_caller_cannot_read_them_across_a_write() -> void:
	var verdict := SoulApi.verdict(_actor)
	assert_eq(verdict.has("ok"), true, "the verdict names whether it can rebody")
	assert_eq(verdict.has("arrival"), true, "the verdict names where it would arrive")


func test_the_summary_is_primitives_only_and_empty_without_an_actor() -> void:
	# The UI standard: `{}` with no actor, and primitives only so a panel can render it.
	assert_eq(SoulApi.summary(null), {}, "no actor is no summary")
	var summary := SoulApi.summary(_actor)
	for key in summary.keys():
		var value: Variant = summary[key]
		if typeof(value) == TYPE_ARRAY:
			for row in value as Array:
				assert_eq(
					typeof(row) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT],
					true,
					"%s row is primitive" % key
				)
		else:
			assert_eq(
				typeof(value) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL],
				true,
				"%s is primitive" % key
			)


func test_the_authored_arrivals_are_all_usable() -> void:
	# A content gate, so an arrival that names no body or has no name fails the build rather
	# than shipping as an arrival nothing can explain.
	assert_eq(SoulApi.validate(), [], "every authored arrival is well-formed")
