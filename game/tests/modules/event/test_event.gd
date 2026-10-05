extends "res://tests/modules/event/event_director_fixture.gd"

## ## This file holds the DELIVERY half of the world event director
##
## The director has NO clock, the trigger gate hides what the world has not called,
## stage progression respects `duration_periods`, and the prize is paid EXACTLY ONCE
## (ADR 0061) -- driven end to end through `EventApi`, with the ledger read on both
## sides of the move.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every case below is the original body verbatim, and every constant and
## private helper it uses lives in `event_director_fixture.gd`, which this file
## `extends`.
##
## The delegation, ledger, persistence and bus half is `test_event_ledger.gd`.

# --- 1. The director has NO clock -------------------------------------------


func test_no_module_file_contains_a_clock_or_a_process_loop() -> void:
	# ADR 0085: "There is no world tick, so nothing accrues on its own." DEF-0111:

	# "Do not give it its own timer: a second clock is a second source of truth for

	# when a save happened." Nothing in this module may read real time.

	var scanned := 0

	for path in _module_files(MODULE_ROOT):
		scanned += 1

		var code := _strip_comments(FileAccess.get_file_as_string(path))

		for banned in ["Time.get_ticks", "get_tree()", "_process(", "_physics_process("]:
			assert_eq(
				code.contains(banned),
				false,
				(
					(
						"%s uses '%s'; the event director is PULL-BASED — a caller owns "
						% [path.get_file(), banned]
					)
					+ "time and hands this module a period count (ADR 0085, DEF-0111)"
				)
			)

	assert_eq(
		scanned >= 10, true, "the walk visited the module's files, so a green verdict is real"
	)


func test_advance_declares_no_default_period_count() -> void:
	# The signature is the assertion. A `periods := 1` default would make

	# `advance(actor)` legal, and a module that can be advanced without being told how

	# much time passed IS a clock — it just happens to have a default.

	var source := _strip_comments(FileAccess.get_file_as_string("res://src/modules/event/api.gd"))

	assert_eq(
		source.contains("static func advance(actor: Actor, periods: int) -> Dictionary:"),
		true,
		(
			"advance must declare `periods` with NO default; a default is a timer that "
			+ "fires whether or not any time was owed to it"
		)
	)


func test_the_world_does_not_move_when_nobody_pulls_it() -> void:
	# The property itself: an open event at a stage that holds for three periods is

	# still at that stage after a second identical pull. Two calls, the same `periods`

	# argument, no elapsed time between them — and each call advances exactly what it

	# was told to, so nothing extra happens because the call was made.

	var actor := _actor()

	_remember(actor, &"tournament_called")

	EventApi.begin(actor, TOURNAMENT, 0)

	assert_eq(_stage_id(actor, TOURNAMENT), "registered", "it opens on the first stage")

	# One period is NOT enough: `registered` holds for one, so period 1 only counts it.

	var first := EventApi.advance(actor, 1)

	assert_eq((first["advanced"] as Array).size(), 0, "one period does not open the next stage")

	assert_eq((first["held"] as Array).size(), 1, "the event says it is holding")

	var second := EventApi.advance(actor, 1)

	assert_eq((second["advanced"] as Array).size(), 1, "the second period moves it")

	assert_eq(_stage_id(actor, TOURNAMENT), "first_round", "and it lands on the second stage")

	# A pull of ZERO settles nothing: a settlement is not a negative accrual.

	var nothing := EventApi.advance(actor, 0)

	assert_eq((nothing["advanced"] as Array).size(), 0, "zero periods advanced nothing")

	assert_eq((nothing["resolved"] as Array).size(), 0, "and resolved nothing")

	assert_eq(_stage_id(actor, TOURNAMENT), "first_round", "and moved the world nowhere")


# --- 2. The trigger gate ----------------------------------------------------


func test_an_event_with_an_unmet_trigger_never_appears_in_available() -> void:
	var actor := _actor()

	assert_eq(
		_available_ids(actor).has(String(TOURNAMENT)),
		false,
		"a tournament nobody called is not available"
	)

	var refused := EventApi.begin(actor, TOURNAMENT)

	assert_eq(bool(refused.get("ok", false)), false, "and it cannot be opened")

	assert_eq(String(refused.get("reason", "")), EventState.R_TRIGGER_UNMET, "with a named reason")

	_remember(actor, &"tournament_called")

	assert_eq(
		_available_ids(actor).has(String(TOURNAMENT)),
		true,
		"once the world remembers the summons it is available"
	)


func test_a_location_the_event_is_not_tied_to_hides_it() -> void:
	# `location_id` filters what is available, and `begin` re-checks it: a caller

	# cannot open a locked event by skipping the filter.

	var actor := _actor(&"mortal_plains")

	_remember(actor, &"tournament_called")

	assert_eq(
		_available_ids(actor).has(String(TOURNAMENT)),
		false,
		"a tournament in the spirit peaks is not happening on the mortal plains"
	)

	var moved := EventApi.set_location(actor, &"spirit_peaks")

	assert_eq(bool(moved.get("ok", false)), true, "the actor moves to a shipped location")

	assert_eq(
		_available_ids(actor).has(String(TOURNAMENT)),
		true,
		"and the tournament is available where it can happen"
	)

	EventApi.set_location(actor, &"mortal_plains")

	var refused := EventApi.begin(actor, TOURNAMENT)

	assert_eq(String(refused.get("reason", "")), EventState.R_WRONG_LOCATION, "and only there")


func test_a_gated_event_is_hidden_until_the_world_says_why() -> void:
	# **The riven peak is NOT ungated.** It used to author `trigger = {}`, which every

	# bare actor already passes — audit criterion 6b: a guard nobody can fail is

	# theatre. It now waits on `storm_front_sighted`, which `WorldAmbient.ROSTER`

	# really produces (`app/world_ambient.gd`, period 1). ADR 0065: a gate is DATA and

	# must be satisfiable — neither a theatre nor a tombstone.

	var actor := _actor(&"mortal_plains")

	assert_eq(
		_available_ids(actor).has(String(DISASTER)),
		false,
		"a disaster at the riven peak is still tied to the spirit peaks"
	)

	var moved := EventApi.set_location(actor, &"spirit_peaks")

	assert_eq(bool(moved.get("ok", false)), true, "the actor moves")

	assert_eq(
		_available_ids(actor).has(String(DISASTER)),
		false,
		"and an unmet gate hides it even where it can happen"
	)

	# **The world says a front arrived** — the roster's own producer, not a test-only

	# fact — and the same gate that held it back now lets it through.

	_remember(actor, &"storm_front_sighted")

	assert_eq(
		_available_ids(actor).has(String(DISASTER)),
		true,
		"and a precondition the world really produces is what opens it"
	)


func test_an_unknown_gate_verb_refuses_closed_and_names_itself() -> void:
	# Refuse-with-cause (the `DestinyGate` precedent). A typo in a `.tres` must fail

	# loudly rather than silently unlocking content or silently locking it.

	var verdict := EventGate.evaluate(_actor(), {"verb": &"has_dignity", "id": &"nobody"})

	assert_eq(bool(verdict.get("ok", false)), false, "an unknown verb does not open the gate")

	assert_eq(String(verdict.get("reason", "")), "unknown_verb", "with a named reason")

	assert_eq(
		String((verdict["unmet"] as Array)[0]["id"]),
		"has_dignity",
		"and it names itself, so a panel can render what it could not read"
	)


func test_a_requirement_with_no_verb_is_malformed_never_ungated() -> void:
	# An EMPTY requirement is ungated. A NON-empty one that names no verb is a content

	# bug, and treating it as ungated would open every locked event in the tree.

	var verdict := EventGate.evaluate(_actor(), {"id": &"storm_front_sighted", "need": 1})

	assert_eq(bool(verdict.get("ok", false)), false, "a verbless requirement is refused")

	assert_eq(String(verdict.get("reason", "")), "malformed", "as malformed, not unmet")

	assert_eq(bool(EventGate.evaluate(_actor(), {}).get("ok", false)), true, "empty stays ungated")


func test_the_composite_verbs_are_reused_not_reimplemented() -> void:
	var actor := _actor()

	_remember(actor, &"court_invitation_received")

	var any_of := EventGate.evaluate(
		actor,
		{
			"verb": &"any_of",
			"of":
			[
				{"verb": &"fact", "id": &"never_happened"},
				{"verb": &"fact", "id": &"court_invitation_received"}
			]
		}
	)

	assert_eq(bool(any_of.get("ok", false)), true, "any_of opens on one held fact")

	var all_of := EventGate.evaluate(
		actor,
		{
			"verb": &"all_of",
			"of":
			[
				{"verb": &"fact", "id": &"never_happened"},
				{"verb": &"fact", "id": &"court_invitation_received"}
			]
		}
	)

	assert_eq(bool(all_of.get("ok", false)), false, "all_of does not")

	var none_of := EventGate.evaluate(
		actor, {"verb": &"none_of", "of": [{"verb": &"fact", "id": &"court_invitation_received"}]}
	)

	assert_eq(bool(none_of.get("ok", false)), false, "none_of refuses a held fact")


func test_the_declare_verb_is_readable_because_the_shipped_war_authors_one() -> void:
	# A `sect_war` authors its declaration inside its own trigger, so `declare` is a

	# verb in the requirement language. The gate did not know it, so every authored

	# `sect_war` refused its OWN trigger and `catalog_report` called it a typo — a war

	# that exists in content and cannot happen in the game.

	assert_eq(
		EventGate.KNOWN_VERBS.has(EventGate.VERB_DECLARE),
		true,
		"`declare` is a verb this module reads"
	)

	assert_eq(
		EventApi.catalog()["unknown_verbs"] as Array,
		[],
		"and the shipped war no longer reports one"
	)

	var declared := EventGate.evaluate(
		_actor(), {"verb": &"declare", "other_id": &"court_of_the_star", "mode": &"siege"}
	)

	assert_eq(
		bool(declared.get("ok", false)), true, "a declaration naming its other side is readable"
	)


## ## `tagged` is a DELEGATED verb too, and both halves must be in step.

##

## `DestinyGate` grew `tagged` over `FateDef.tags` (ADR 0196, fate tag vocabulary); this

## module hands it to `DestinyApi.gate` verbatim. Two lists must name it and the failure

## modes are OPPOSITES: `DELEGATED_VERBS` alone leaves the runtime refusing a valid trigger,

## `KNOWN_VERBS` alone leaves `EventReadModel` calling a row the runtime evaluates a

## typo — the same disagreement `declare` above was added for.


func test_the_tagged_verb_is_delegated_and_known_so_the_tool_and_runtime_agree() -> void:
	for vocabulary in [EventGate.DELEGATED_VERBS, EventGate.KNOWN_VERBS]:
		assert_eq(vocabulary.has(&"tagged"), true, "`tagged` is delegated, so both name it")

	assert_eq(
		EventReadModel.unknown_verbs(),
		[] as Array[Dictionary],
		"and no shipped .tres reports an unknown verb, so the two cannot disagree"
	)

	assert_eq(
		String(EventGate.evaluate(_actor(), {"verb": &"tagged", "id": "nope"})["reason"]),
		"unknown_tag",
		"a coined lineage keeps DestinyGate's own refusal, not an event re-shaped one"
	)


func test_a_declaration_naming_no_other_side_is_malformed_never_passed() -> void:
	# A war whose sides cannot be read must not open with no declared prize

	# (ADR 0085): passing it would let `begin` write the active row and then be

	# refused by `_declare` a few lines later — a war that exists for one call.

	var verdict := EventGate.evaluate(_actor(), {"verb": &"declare", "mode": &"siege"})

	assert_eq(bool(verdict.get("ok", false)), false, "a declare row with no other_id is refused")

	assert_eq(String(verdict.get("reason", "")), "malformed", "as malformed, not unmet")


# --- 3. Stages and duration -------------------------------------------------


func test_a_stage_holds_for_exactly_the_authored_number_of_periods() -> void:
	var actor := _actor()

	_remember(actor, &"tournament_called")

	var def := EventCatalog.instance().event_definition(TOURNAMENT)

	assert_eq(def.stage_at(0).duration_periods, 1, "the first stage holds one period")

	EventApi.begin(actor, TOURNAMENT)

	var early := EventApi.advance(actor, 1)

	assert_eq((early["advanced"] as Array).size(), 0, "one period is not enough for a second stage")

	var ready := EventApi.advance(actor, 1)

	assert_eq((ready["advanced"] as Array).size(), 1, "the second period is")

	assert_eq(_stage_id(actor, TOURNAMENT), "first_round", "and the stage moved")


func test_a_multi_period_pull_walks_one_stage_per_period_not_one_per_call() -> void:
	# `final` requires two rounds fought; `first_round` fires its beats once, when it

	# opens. So a single `advance(actor, 5)` must stop at `final`, not sprint past a

	# requirement that the beats it would have skipped were supposed to write.

	#

	# FIVE, not six. `registered` and `first_round` each hold one whole period and

	# `final` holds one more, so the sixth period is the one that would resolve it.

	# The comment here always said five; the call said six.

	var actor := _actor()

	_remember(actor, &"tournament_called")

	EventApi.begin(actor, TOURNAMENT)

	EventApi.advance(actor, 5)

	assert_eq(
		_stage_id(actor, TOURNAMENT),
		"final",
		"a long pull stops where the next stage's requirement is not yet met"
	)

	assert_eq(int(EventApi.summary(actor)["active_count"]), 1, "and the event is still open")


func test_a_zero_period_stage_resolves_at_the_next_pull_and_not_before() -> void:
	# The boundary that the off-by-one collapsed. `duration_periods = 0` must mean

	# "hold for no time", so the FIRST pull moves the ladder — and, on the last

	# stage, RESOLVES the event. Under the old `<` comparison, `0` and `1` moved on

	# the same pull and an authored `0` was indistinguishable from an authored `1`.

	#

	# The auction's `hammer` is the final stage and authors `duration_periods = 0`,

	# so it settles on the pull that reaches it.

	var actor := _actor(&"immortal_court")

	# **The auction's gate is `has_fate first_blood_duel`, satisfied the way the world

	# satisfies it** — through `DestinyApi.earn_fate`, the verb

	# `tournament_of_the_spirit_peaks.tres` pays it by. It used to record a

	# `court_invitation_received` fact, an id **no writer in `game/src` produces**, so

	# ADR 0065's rule was violated by the FIXTURE, not the content.

	DestinyApi.earn_fate(actor, &"first_blood_duel", "test:tournament")

	var opened := EventApi.begin(actor, AUCTION)

	assert_eq(bool(opened.get("ok", false)), true, "the auction opened: %s" % opened)

	assert_eq(_stage_id(actor, AUCTION), "lots_read", "on its first stage")

	# p1: `lots_read` holds. p2: `bids_open` opens. p3: `bids_open` holds.

	# p4: `hammer` (duration 0) opens on this pull rather than holding.

	# p5: `hammer` is final and holds for nothing, so this pull RESOLVES it.

	var fifth := EventApi.advance(actor, 5)

	assert_eq((fifth["resolved"] as Array).size(), 1, "the zero-period final stage resolved")

	assert_eq(int(EventApi.summary(actor)["active_count"]), 0, "and the event is closed")

	assert_eq(
		EventState.has_resolved(EventApi.state(actor), AUCTION),
		true,
		"the once-guard records it as resolved"
	)


func test_an_event_that_authors_no_stage_is_refused_by_name() -> void:
	# The ladder-less shape is built and registered here rather than shipped as a

	# `.tres`; the header above says why. The gate is one no actor can satisfy, so the

	# fixture never perturbs another test's `available` list.

	var actor := _actor(&"transcendent_realm")

	var hollow := EventDef.new()

	hollow.id = &"an_event_that_authors_no_stage"

	hollow.display_name = "An Event That Authors No Stage"

	hollow.kind = EventDef.KIND_RARE_TREASURE

	hollow.location_id = &"transcendent_realm"

	hollow.trigger = {"verb": &"fact", "id": &"no_world_produces_this_fact", "need": 1}

	assert_eq(EventCatalog.instance().register(hollow), true, "the hollow def is well formed")

	assert_eq(
		_available_ids(actor).has(String(hollow.id)),
		false,
		"and never in `available`, so registering it cannot perturb another test"
	)

	var refused := EventApi.begin(actor, &"an_event_that_authors_no_stage")

	assert_eq(bool(refused.get("ok", false)), false, "an event with no stages cannot open")

	assert_eq(
		String(refused.get("reason", "")),
		EventState.R_NO_STAGES,
		"with a named reason, and NOT `trigger_unmet` — the ladder is read first"
	)

	assert_eq(int(EventApi.summary(actor)["active_count"]), 0, "and nothing was opened")

	# **And the shipped treasure, which authors its one stage, still OPENS.** If the

	# refusal above passed only because the ref was closed, this line would go red.

	var opened := EventApi.begin(actor, TREASURE)

	assert_eq(bool(opened.get("ok", false)), true, "the one-stage event opens: %s" % opened)

	assert_eq(_stage_id(actor, TREASURE), "read", "on the single stage it authors")


func test_the_rare_treasure_refuses_itself_a_second_time_through_none_of() -> void:
	# `none_of` over its own fact: once the stone has been read the event is finished

	# with, whether or not anyone advanced it. The gate is the once-rule, expressed as

	# data (ADR 0113: "adding a fact-gated content type is a content edit").

	var actor := _actor(&"transcendent_realm")

	# A def with no stages cannot open at all, so the `none_of` gate is asserted on a

	# ladder-bearing event instead: the same requirement shape, read the same way.

	var verdict := EventGate.evaluate(
		actor, {"verb": &"none_of", "of": [{"verb": &"fact", "id": &"treasure_stone_read"}]}
	)

	assert_eq(bool(verdict.get("ok", false)), true, "the stone is unread, so the gate is open")

	_remember(actor, &"treasure_stone_read")

	var after := EventGate.evaluate(
		actor, {"verb": &"none_of", "of": [{"verb": &"fact", "id": &"treasure_stone_read"}]}
	)

	assert_eq(bool(after.get("ok", false)), false, "and reading it closes the gate for good")


# --- 4. Pay fires EXACTLY ONCE (ADR 0061) -----------------------------------


func test_the_prize_is_paid_exactly_once_across_many_advances() -> void:
	var actor := _actor()

	_remember(actor, &"tournament_called")

	EventApi.begin(actor, TOURNAMENT)

	var payouts := 0

	for pull in range(8):
		var result := EventApi.advance(actor, 1)

		payouts += (result["resolved"] as Array).size()

	assert_eq(payouts, 1, "the prize was paid on exactly one pull, out of eight")

	assert_eq(
		DestinyApi.has_fate(actor, &"first_blood_duel"), true, "and the fate it paid for is held"
	)

	assert_eq(int(EventApi.summary(actor)["resolved_count"]), 1, "one event resolved")

	assert_eq(int(EventApi.summary(actor)["paid_count"]), 1, "and one was marked paid")


func test_a_resolved_event_does_not_reopen_and_does_not_repay() -> void:
	var actor := _actor()

	_remember(actor, &"tournament_called")

	EventApi.begin(actor, TOURNAMENT)

	EventApi.advance(actor, 6)

	var again := EventApi.begin(actor, TOURNAMENT)

	assert_eq(
		String(again.get("reason", "")),
		EventState.R_ALREADY_RESOLVED,
		"a resolved event refuses to open again"
	)

	for pull in range(4):
		EventApi.advance(actor, 2)

	assert_eq(
		int(EventApi.summary(actor)["resolved_count"]),
		1,
		"and four more pulls resolve nothing, because it is closed"
	)


func test_the_once_guard_is_read_from_the_ledger_not_from_a_flag_in_the_caller() -> void:
	# The guard is `EventState.paid`, written under the same write that erases the

	# active row. So the paid map and the active map can never disagree — which is the

	# property a caller-owned boolean would not have.

	var actor := _actor()

	_remember(actor, &"tournament_called")

	EventApi.begin(actor, TOURNAMENT)

	EventApi.advance(actor, 6)

	var ledger := EventApi.state(actor)

	assert_eq((ledger["active"] as Dictionary).has(String(TOURNAMENT)), false, "it left `active`")

	assert_eq((ledger["paid"] as Dictionary).has(String(TOURNAMENT)), true, "and entered `paid`")

	assert_eq(
		EventState.has_resolved(ledger, TOURNAMENT),
		true,
		"the once-guard reads `resolved`, which is set in the same write"
	)

# **Whether the guard FIRES is `test_event_once_guard.gd`** — `advance` erases the

# active row in the same write that populates `paid`, so `has_paid`'s early-return

# has no reachable caller through this path.
