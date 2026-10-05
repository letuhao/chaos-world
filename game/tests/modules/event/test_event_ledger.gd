extends "res://tests/modules/event/event_director_fixture.gd"

## ## This file holds the LEDGER half of the world event director
##
## The director owns no conflict arithmetic -- a war DELEGATES to
## `NationApi.resolve_conflict` -- the DEF-0108 fate source string is exact, beats land
## in the ONE fact ledger (ADR 0113 / 0114), the save round-trips, and the bus announces
## rather than requests (ADR 0093).
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every case below is the original body verbatim, and every constant and
## private helper it uses lives in `event_director_fixture.gd`, which this file
## `extends`.
##
## The clock, trigger-gate, stage and once-paid-prize half is `test_event.gd`.

# --- 5. The director owns no conflict arithmetic ----------------------------


func test_a_conflict_event_delegates_resolution_to_the_nation_module() -> void:
	var actor := _actor(&"mortal_plains", true)

	_remember(actor, &"sect_war_called")

	var opened := EventApi.begin(actor, WAR)

	assert_eq(bool(opened.get("ok", false)), true, "the war was declared: %s" % opened)

	assert_eq(bool(opened.get("declared", false)), true, "and it declared itself")

	var standoff_id := StringName(opened["standoff_id"])

	assert_ne(String(standoff_id), "", "against a real standoff")

	# **The winner is the actor's OWN id, not the `nation_id`.** `NationApi

	# .declare_war` keys a standoff's two sides by `String(actor.id)` and the

	# authored `other_id`, so the sides here are `{event_actor, court_of_the_star}`.

	# `march_of_the_nine_provinces` is the `NationDef` id the actor was founded

	# UNDER and is not a side, so injecting it makes `nation` refuse

	# `unknown_winner` — which is `nation` answering correctly about a verdict the

	# caller invented, not this module failing to delegate.

	var winner := StringName(actor.id)

	# `nation` owns the quota. A siege is five; the event director must not decide how

	# many verdicts that takes, so this reads `NationApi.QUOTAS` rather than a literal.

	var quota := int(NationApi.QUOTAS["siege"])

	assert_eq(quota, 5, "the siege quota is `nation`'s to declare")

	for verdict in range(quota):
		var step := EventApi.resolve(actor, WAR, winner)

		assert_eq(
			bool(step.get("delegated", false)),
			true,
			"every resolution is a DELEGATION, not a computation: verdict %d — %s" % [verdict, step]
		)

		assert_eq(
			bool(step.get("closed", false)), false, "and the war is still open at %d" % verdict
		)

	var closed := EventApi.resolve(actor, WAR, winner)

	assert_eq(bool(closed.get("closed", false)), true, "the declared quota closes it")

	assert_eq(bool(closed.get("paid", false)), true, "and the prize is paid once")

	var ledger := NationApi.state(actor)

	assert_eq(
		bool((ledger["standoffs"] as Dictionary)[String(standoff_id)]["closed"]),
		true,
		"and the standoff in `nation` — not here — is the thing that closed"
	)


func test_resolving_a_war_for_a_side_that_is_not_one_of_its_two_is_refused() -> void:
	# The counterpart of the test above, and the reason the winner above is

	# `actor.id`: a verdict naming a third polity is not a tally this module may

	# count. `nation` refuses it, and this module reports that refusal rather than

	# substituting a side of its own.

	var actor := _actor(&"mortal_plains", true)

	_remember(actor, &"sect_war_called")

	EventApi.begin(actor, WAR)

	var refused := EventApi.resolve(actor, WAR, &"court_of_another_star")

	assert_eq(bool(refused.get("ok", false)), false, "a stranger cannot win a declared war")

	assert_eq(String(refused.get("reason", "")), EventState.R_UNKNOWN_WINNER, "with a named reason")

	assert_eq(int(EventApi.summary(actor)["active_count"]), 1, "and the war stays open")


func test_the_declaration_lands_on_the_event_row_not_wherever_the_builder_looks() -> void:
	# **This is the test that pins the `_declare` arity.**

	#

	# `EventApi._declare` is a BUILDER: it takes `(actor, def, period)`, writes into

	# `nation`'s ledger and nowhere else, and the caller copies the result onto the

	# row it persists. The call site once passed a fourth `ledger` argument, which

	# is a compile error in GDScript — the whole facade failed to load, so nothing

	# about this module was measurable. The argument was dropped rather than added

	# to the definition, so this test exists to prove that was safe: if the

	# declaration reached the ledger through the builder rather than through the

	# caller, `standoff_id` and `territory_id` would be empty on the persisted row

	# and `resolve` could never find the standoff to hand `nation`.

	var actor := _actor(&"mortal_plains", true)

	_remember(actor, &"sect_war_called")

	var opened := EventApi.begin(actor, WAR)

	assert_eq(bool(opened.get("ok", false)), true, "the war opened: %s" % opened)

	# Read the PERSISTED ledger, not the returned payload: the return value is what

	# the builder said, and the ledger is what a later `resolve` reads.

	var entry: Dictionary = (EventApi.state(actor)["active"] as Dictionary)[String(WAR)]

	assert_eq(
		String(entry["standoff_id"]),
		String(opened["standoff_id"]),
		"the standoff id is ON THE ROW, so `resolve` can hand it back to `nation`"
	)

	assert_eq(String(entry["territory_id"]), "river_march", "and so is the declared territory")

	assert_eq(bool(entry["declared"]), true, "and the row says it was declared")

	# The whole point: the standoff id on the row is one `nation` actually holds,

	# so the delegation downstream is real rather than a dangling reference.

	assert_eq(
		(NationApi.state(actor)["standoffs"] as Dictionary).has(String(entry["standoff_id"])),
		true,
		"and `nation` holds that standoff, so the declaration landed in BOTH ledgers"
	)


func test_the_event_records_the_delegation_rather_than_the_outcome_arithmetic() -> void:
	var actor := _actor(&"mortal_plains", true)

	_remember(actor, &"sect_war_called")

	EventApi.begin(actor, WAR)

	EventApi.resolve(actor, WAR, StringName(actor.id))

	var ledger := EventApi.state(actor)

	var entry: Dictionary = (ledger["active"] as Dictionary)[String(WAR)]

	var kinds: Array[String] = []

	for row in entry["history"]:
		kinds.append(String((row as Dictionary)["kind"]))

	assert_eq(kinds.has("declared"), true, "the declaration is on the event's own row")

	assert_eq(kinds.has("delegated"), true, "and so is the delegation")


func test_a_conflict_with_no_winner_is_refused_rather_than_defaulted() -> void:
	# A war with no winner is a WITHDRAWAL, and `nation` owns that word. Defaulting

	# the winner to one side here would let an event decide a war nobody fought.

	var actor := _actor(&"mortal_plains", true)

	_remember(actor, &"sect_war_called")

	EventApi.begin(actor, WAR)

	var refused := EventApi.resolve(actor, WAR, "")

	assert_eq(bool(refused.get("ok", false)), false, "an empty winner is refused")

	assert_eq(String(refused.get("reason", "")), EventState.R_NO_WINNER, "with a named reason")

	assert_eq(int(EventApi.summary(actor)["active_count"]), 1, "and the war stays open")


func test_a_war_whose_declaration_fails_does_not_open_at_all() -> void:
	# ADR 0085: `war` is reachable ONLY through the declaration verb, so no war may

	# exist without a declared prize. An event that names a polity nobody lives under

	# cannot declare, so it cannot open — and nothing is recorded in either ledger.

	var actor := _actor(&"mortal_plains")

	_remember(actor, &"sect_war_called")

	var refused := EventApi.begin(actor, WAR)

	assert_eq(bool(refused.get("ok", false)), false, "a war cannot open without a nation")

	assert_eq(int(EventApi.summary(actor)["active_count"]), 0, "and nothing was opened")


func test_no_module_file_contains_damage_arithmetic_or_a_roll() -> void:
	# `tools arch` cannot see a method that does not exist, so ADR 0085's rule is

	# pinned by reading the SOURCE. Comments are stripped first.

	var scanned := 0

	for path in _module_files(MODULE_ROOT):
		scanned += 1

		var code := _strip_comments(FileAccess.get_file_as_string(path))

		for word in DAMAGE_WORDS:
			assert_eq(
				code.contains(word),
				false,
				(
					(
						"%s contains '%s'; an event decides WHEN and WHO WON, never "
						% [path.get_file(), word]
					)
					+ "how much was struck (ADR 0085)"
				)
			)

	assert_eq(scanned >= 10, true, "the walk visited the module's files")


func test_no_module_file_names_a_combat_module_or_owns_a_rng() -> void:
	# Verdict sources belong to the CALLER: a `CombatApi.exchange` the caller ran, a

	# tournament result, a tribunal's ruling. An event that called combat would be a

	# second place a verdict is produced, which is the fork ADR 0085 refuses.

	for path in _module_files(MODULE_ROOT):
		var code := _strip_comments(FileAccess.get_file_as_string(path))

		for banned in FORBIDDEN_WORDS:
			assert_eq(
				code.contains(banned),
				false,
				(
					(
						"%s uses '%s'; a conflict counts injected verdicts and pays a "
						% [path.get_file(), banned]
					)
					+ "declared prize, and owns no combat and no rng (ADR 0085)"
				)
			)


func test_the_nation_conflict_has_exactly_one_caller_and_it_is_here() -> void:
	# ADR 0114's consequence: the three zero-caller seams get ONE caller each, at the

	# one place that owns their decision. So `NationApi.resolve_conflict` must appear

	# in this module and nowhere else in `res://src`.

	var callers := 0

	for path in _module_files("res://src"):
		var code := _strip_comments(FileAccess.get_file_as_string(path))

		if code.contains("NationApi.resolve_conflict("):
			callers += 1

			assert_eq(
				path.get_file(),
				"api.gd",
				(
					(
						"%s calls resolve_conflict; the conflict is resolved in ONE place, "
						% path.get_file()
					)
					+ "and that place is the event director (ADR 0114)"
				)
			)

	assert_eq(callers, 1, "exactly one caller of NationApi.resolve_conflict exists in src/")


func test_the_nation_standing_prize_is_declared_not_granted_here() -> void:
	# ADR 0085 settles where a standing delta belongs: inside the prize `declare_war`

	# fixes up front. `NationApi` has no verb that writes one, so the pay row REFUSES

	# and names where the number lives rather than reaching through a seam.

	var actor := _actor(&"mortal_plains", true)

	_remember(actor, &"storm_front_sighted")

	EventApi.begin(actor, TIDE)

	EventApi.advance(actor, 6)

	var ledger := EventApi.state(actor)

	var paid: Dictionary = (ledger["paid"] as Dictionary)[String(TIDE)]

	assert_eq(int(paid["rows"]), 1, "the tide declares exactly one pay row")

	var summary := EventApi.summary(actor)

	assert_eq(int(summary["paid_count"]), 1, "and the event is marked paid once")


# --- 6. DEF-0108: the fate source string is EXACT ---------------------------


func test_a_fate_grant_carries_the_exact_def_0108_source_string() -> void:
	var actor := _actor()

	_remember(actor, &"tournament_called")

	EventApi.begin(actor, TOURNAMENT)

	EventApi.advance(actor, 6)

	var ledger := DestinyApi.state(actor)

	var entry: Dictionary = (ledger["fates"] as Dictionary)["first_blood_duel"]

	assert_eq(
		String(entry["source"]),
		"event:" + String(TOURNAMENT),
		(
			'DEF-0108: "Call DestinyApi.earn_fate(actor, fate_id, "event:<event_id>") '
			+ "from the event's own resolution\""
		)
	)

	assert_eq(
		EventCatalog.instance().event_definition(TOURNAMENT).fate_source(),
		"event:tournament_of_the_spirit_peaks",
		"and the def builds that string the same way"
	)


# --- Beats and the ledger (ADR 0113 / 0114) --------------------------------


func test_an_opened_stage_records_its_beats_in_the_one_fact_ledger() -> void:
	var actor := _actor(&"mortal_plains")

	_remember(actor, &"storm_front_sighted")

	EventApi.begin(actor, TIDE)

	assert_eq(
		EventFacts.count_of(actor, &"beast_tide_started"),
		1,
		"the def's own on_enter beat is recorded under ADR 0113's key"
	)

	assert_eq(
		EventFacts.count_of(actor, &"beast_tide_moving"),
		1,
		"and so is the first stage's, which is a BEAT and not a reward (ADR 0114)"
	)

	assert_eq(
		(actor.get_module_data(WorldFact.MODULE_KEY) as Dictionary).has("facts"),
		true,
		"the ledger lives where ADR 0113 says it does: actor.module_data['world_facts']"
	)


# --- One ledger, one normaliser (ADR 0066) -----------------------------------


func test_the_event_module_declares_no_second_writer_over_the_world_fact_ledger() -> void:
	# ADR 0066's shape, spelled: two normalisers over ONE key.

	# `core/world_fact.gd` owns `actor.module_data["world_facts"]` and emits

	# `{version, facts:{id:{count, since}}}`. `EventFacts` shipped a SECOND

	# normaliser emitting `{version, facts:{id:{id, count}}, sequence}` over the same

	# key, plus its own `record`. Two writers on one key means each truncates the

	# other's rows on the way out, silently.

	#

	# Asserted over the SOURCE because `tools arch` cannot see a method that does not

	# exist — a normaliser that reappears in a future edit is invisible to every other

	# gate in the repo, and the two tests below would only catch it if a beat happened

	# to land on the right key.

	var offenders: Array[String] = []

	for path in _module_files(MODULE_ROOT):
		var code := _strip_comments(FileAccess.get_file_as_string(path))

		if not code.contains("WorldFact"):
			continue

		if code.contains("func normalize(") or code.contains("func record("):
			offenders.append(path.get_file())

	assert_eq(
		offenders,
		[],
		(
			"`event/` reads and writes the ledger through `WorldFact` and must not "
			+ "declare a normaliser or a write verb of its own over it (ADR 0066)"
		)
	)


func test_a_beat_recorded_by_an_event_survives_the_worlds_own_reader() -> void:
	# The round trip that matters. A beat the event director records is a FACT, and

	# it must be readable by the module that owns the ledger, with `since` intact.

	# While `EventFacts.normalize` wrote rows of `{id, count}` over a ledger whose

	# rows are `{count, since}`, one event beat deleted the `since` of every OTHER

	# system's facts in the same ledger — and `since` is what

	# `WorldFact`'s "has this happened exactly once" gate reads.

	var actor := _actor(&"mortal_plains")

	WorldFact.record(actor, &"a_beast_was_slain", 1)

	assert_eq(
		WorldFact.fact(actor, &"a_beast_was_slain").since, 1, "the world's own row carries a since"
	)

	_remember(actor, &"storm_front_sighted")

	EventApi.begin(actor, TIDE)

	assert_eq(
		WorldFact.fact(actor, &"a_beast_was_slain").since,
		1,
		"an event beat recording OTHER facts did not delete this row's since"
	)

	assert_eq(WorldFact.count(actor, &"a_beast_was_slain"), 1, "and did not change its count")

	assert_eq(
		WorldFact.count(actor, &"beast_tide_started"),
		1,
		"while the event's own beat IS visible to the world's reader"
	)


func test_a_fact_the_world_and_an_event_both_record_stays_one_monotone_count() -> void:
	# Two writers over one key is not only a lost field — it is a count that can

	# disagree. `WorldFact.record` reads the stored row before adding to it, so a

	# writer that stores a DIFFERENT row shape leaves the next reader repairing a

	# value rather than counting it.

	var actor := _actor(&"mortal_plains")

	WorldFact.record(actor, &"beast_slain", 2)

	_remember(actor, &"storm_front_sighted")

	EventApi.begin(actor, TIDE)

	WorldFact.record(actor, &"beast_slain", 3)

	assert_eq(
		WorldFact.count(actor, &"beast_slain"),
		5,
		"the world's own reader counts every accrual, whichever system recorded it"
	)


func test_a_beat_id_is_unique_per_occurrence_as_adr_0114_requires() -> void:
	# "A beat's id MUST be unique per occurrence — the caller mints `&"killed_boar@3"`

	# for the third boar — and the ledger records occurrence ids under a count."

	var actor := _actor()

	var ids: Array[String] = []

	for occurrence in range(1, 4):
		ids.append(String(EventFacts.occurrence_id(&"killed_boar", occurrence)))

		WorldFact.record(actor, &"killed_boar", 1)

	assert_eq(ids[0], "killed_boar@1", "the first occurrence is named 1")

	assert_ne(ids[0], ids[1], "two occurrences are never the same id")

	assert_ne(ids[1], ids[2], "and neither are three")

	assert_eq(EventFacts.count_of(actor, &"killed_boar"), 3, "while the fact counts all three")


func test_a_fact_is_monotone_and_a_non_positive_amount_records_nothing() -> void:
	# ADR 0113: the ledger's write verb raises a count and never lowers one. A

	# "consumed" thing is a quest step, not a fact. A zero or negative amount is

	# REFUSED with a reason rather than absorbed: a caller computing a delta of zero

	# has a bug, and absorbing it leaves the ledger claiming a thing that did not

	# happen.

	var actor := _actor()

	var written := WorldFact.record(actor, &"beast_slain", 2)

	assert_eq(bool(written.get("ok", false)), true, "it counted two")

	assert_eq(EventFacts.count_of(actor, &"beast_slain"), 2, "which is what the reader sees")

	var refused := WorldFact.record(actor, &"beast_slain", 0)

	assert_eq(bool(refused.get("ok", false)), false, "a zero amount is refused")

	assert_eq(String(refused.get("reason", "")), "non_positive", "with a named reason")

	assert_eq(EventFacts.count_of(actor, &"beast_slain"), 2, "and changes nothing")

	WorldFact.record(actor, &"beast_slain", -5)

	assert_eq(EventFacts.count_of(actor, &"beast_slain"), 2, "and neither does a negative one")

	assert_eq(
		WorldFact.fact(actor, &"beast_slain").since,
		2,
		"`since` is the count at FIRST record, carried forward"
	)


# --- Persistence ------------------------------------------------------------


func test_the_ledger_survives_a_json_round_trip_with_string_keys_only() -> void:
	# `Actor.to_dict` converts only the OUTER key, so an inner `StringName` key

	# reaches the save untouched and breaks every round trip (the `NationState` rule).

	var actor := _actor()

	_remember(actor, &"tournament_called")

	EventApi.begin(actor, TOURNAMENT)

	EventApi.advance(actor, 2)

	var restored := Actor.from_dict(JSON.parse_string(JSON.stringify(actor.to_dict())))

	EventApi.attach(restored)

	EventApi.set_location(restored, &"spirit_peaks")

	var ledger := EventApi.state(restored)

	assert_eq(
		String(ledger["location_id"]), "spirit_peaks", "the location survives a JSON round trip"
	)

	assert_eq(
		(ledger["active"] as Dictionary).has(String(TOURNAMENT)),
		true,
		"and the open event survives it"
	)

	assert_eq(int(ledger["period"]), 2, "and so does the period count")

	assert_eq(_stage_id(restored, TOURNAMENT), "first_round", "and the event resumes where it was")


func test_an_unreadable_payload_is_diagnosed_as_empty_never_partially_applied() -> void:
	var actor := _actor()

	actor.set_module_data(EventState.MODULE_KEY, {"active": "not a dictionary", "period": 7})

	var ledger := EventApi.state(actor)

	assert_eq((ledger["active"] as Dictionary).size(), 0, "an unreadable active map is dropped")

	assert_eq(int(ledger["period"]), 7, "while a readable field beside it is still read")

	assert_eq((ledger["resolved"] as Dictionary).size(), 0, "and the skeleton is complete")


func test_a_save_naming_an_event_this_build_does_not_ship_is_dropped() -> void:
	var known := EventCatalog.instance().known_ids()

	var payload := EventState.normalize(
		{"active": {"an_event_that_was_deleted": {"stage_id": "x"}}, "resolved": {}}, known
	)

	assert_eq(
		(payload["active"] as Dictionary).has("an_event_that_was_deleted"),
		false,
		"an event this build no longer ships cannot be smuggled in from a save"
	)


# --- The bus announces, never requests (ADR 0093) ---------------------------


func test_the_world_event_bus_is_the_existing_contract_and_is_singleton() -> void:
	var bus := EventApi.events()

	assert_eq(bus is WorldEvents, true, "the bus IS the declared `WorldEvents` contract")

	assert_eq(EventApi.events(), bus, "and the same instance every time, so a listener survives")


func test_opening_and_closing_an_event_announces_through_the_contract() -> void:
	var seen: Array[String] = []

	var bus := EventApi.events()

	var on_triggered := func(_actor_id: String, _conflict: StringName, _severity: float) -> void:
		seen.append("triggered")

	var on_evolved := func(_actor_id: String, _old: StringName, _new: StringName) -> void:
		seen.append("evolved")

	bus.world_conflict_triggered.connect(on_triggered)

	bus.world_evolved.connect(on_evolved)

	var actor := _actor()

	_remember(actor, &"tournament_called")

	EventApi.begin(actor, TOURNAMENT)

	# TWO periods, because `registered` is authored `duration_periods = 1` and a

	# stage holds for that many WHOLE periods. This test asserted the evolution on

	# ONE pull, which is only true of the off-by-one that made `duration_periods = 0`

	# and `= 1` behave identically.

	EventApi.advance(actor, 2)

	bus.world_evolved.disconnect(on_evolved)

	assert_eq(seen.has("triggered"), true, "opening announced a conflict was triggered")

	assert_eq(seen.has("evolved"), true, "and the stage move announced the evolution")

	assert_eq(seen.size(), 2, "and nothing else fired")
