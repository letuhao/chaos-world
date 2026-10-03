extends TestCase

## BL-0054 / ADR 0113 / ADR 0114 / ADR 0085: **the world event director.**
##
## ## The properties, not the buttons
##
## Every test here asserts something that must be true of the DESIGN rather than of
## one authored event, because ADR 0077's standing warning is that an ADR can describe
## a spine with not one of its named symbols present. The load-bearing ones are:
##
##   1. **The director has no clock.** Advancing requires an explicit `periods`, the
##      source contains no clock spelling at all, and two identical pulls with no
##      elapsed time between them resolve nothing extra.
##   2. An event with an unmet trigger never appears in `available`.
##   3. Stage progression respects `duration_periods` — one period is not enough.
##   4. `pay` fires EXACTLY ONCE per event, across many `advance` calls (ADR 0061).
##   5. **The director owns no conflict arithmetic**: a conflict event DELEGATES to
##      `NationApi.resolve_conflict`, the standoff closes in `nation`, and no
##      `CombatApi`, no `rng` and no damage constant exists anywhere in `event/`.
##   6. A fate grant carries the exact source string `"event:" + event_id` (DEF-0108).
##
## The structural cases read the SOURCE, the same technique
## `test_nation_conflict.gd` uses: `tools arch` cannot see a method that does not
## exist, so a formula written into this module would fork the shared spine invisibly.
## Comments are stripped first — a module that DOCUMENTS the rule it obeys is not
## reported for obeying it in prose.

const MODULE_ROOT := "res://src/modules/event"
const EVENTS_ROOT := "res://data/event/events"

## The words a second damage model would be written with (ADR 0085's whole subject).
const DAMAGE_WORDS := ["resolve_attack", "damage", "crit", "mitigate", "army_strength", "hit_point"]
## The rng and the clock. `CombatApi` is here because an event director that calls
## combat is a second place verdicts are produced — ADR 0085 routes them to the
## caller, and the caller runs the exchange.
const FORBIDDEN_WORDS := [
	"CombatApi",
	"CombatEngineApi",
	"RandomNumberGenerator",
	"randf",
	"randi",
	"seed(",
	"shuffle",
	"Time.get_ticks",
	"get_tree()",
	"_process(",
	"_physics_process(",
	"_notification(",
]

const WAR := &"war_of_the_nine_fords"
const TOURNAMENT := &"tournament_of_the_spirit_peaks"
const TIDE := &"beast_tide_of_the_mortal_plains"
const AUCTION := &"auction_at_the_immortal_court"
const DISASTER := &"the_riven_peak_disaster"
const INVASION := &"the_dawn_descent"
const TREASURE := &"the_stone_that_answering"
const MARCH := &"march_of_the_nine_provinces"
const COURT := &"court_of_the_star"

## BL-0054's named list. A director that ships none of these has not closed BL-0054.
const NAMED_KINDS: Array[StringName] = [
	EventDef.KIND_SECT_WAR,
	EventDef.KIND_TOURNAMENT,
	EventDef.KIND_BEAST_TIDE,
	EventDef.KIND_AUCTION,
	EventDef.KIND_DISASTER,
	EventDef.KIND_DEMONIC_INVASION,
	EventDef.KIND_RARE_TREASURE,
]

# --- Fixtures ---------------------------------------------------------------


func _actor(at: String = &"spirit_peaks", founded: bool = false) -> Actor:
	var actor := Actor.new(&"event_actor", {Stat.PHYSIQUE: 10.0})
	DestinyApi.attach(actor)
	NationApi.attach(actor)
	EventApi.attach(actor)
	if founded:
		NationApi.found(actor, MARCH, String(actor.id))
	EventApi.set_location(actor, at)
	return actor


## Record a fact through the ONE ledger ADR 0113 fixes, with the shape a beat carries.
func _remember(actor: Actor, fact_id: StringName, amount: int = 1) -> void:
	var ledger := EventFacts.ledger(actor)
	EventFacts.record(ledger, fact_id, amount, 0)
	actor.set_module_data(EventFacts.MODULE_KEY, EventFacts.normalize(ledger))


func _stage_id(actor: Actor, event_id: StringName) -> String:
	var rows := EventApi.active(actor)
	for row in rows:
		if StringName(row["event_id"]) == event_id:
			return String(row["stage_id"])
	return ""


func _available_ids(actor: Actor, at: String = "") -> Array[String]:
	var out: Array[String] = []
	for row in EventApi.available(actor, at):
		out.append(String(row["event_id"]))
	return out


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


func test_an_ungated_event_is_available_anywhere_and_says_so() -> void:
	# The disaster authors an EMPTY trigger, because nobody schedules a disaster.
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
		true,
		"and an ungated event opens with no summons behind it"
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
	# `final` requires two rounds fought; `first_round` fires one per period. So a
	# single `advance(actor, 5)` must stop at `final`, not sprint past a requirement
	# that the beats it would have skipped were supposed to write.
	var actor := _actor()
	_remember(actor, &"tournament_called")
	EventApi.begin(actor, TOURNAMENT)
	EventApi.advance(actor, 6)
	assert_eq(
		_stage_id(actor, TOURNAMENT),
		"final",
		"a long pull stops where the next stage's requirement is not yet met"
	)
	assert_eq(int(EventApi.summary(actor)["active_count"]), 1, "and the event is still open")


func test_an_event_that_authors_no_stage_is_refused_by_name() -> void:
	# A one-shot event (the rare treasure) authors no ladder at all. Opening it is
	# refused rather than opening a stage that does not exist — so `stages` being
	# optional in content does not make it optional in behaviour.
	var actor := _actor(&"transcendent_realm")
	var refused := EventApi.begin(actor, TREASURE)
	assert_eq(bool(refused.get("ok", false)), false, "an event with no stages cannot open")
	assert_eq(String(refused.get("reason", "")), EventState.R_NO_STAGES, "with a named reason")
	assert_eq(int(EventApi.summary(actor)["active_count"]), 0, "and nothing was opened")


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


# --- 5. The director owns no conflict arithmetic ----------------------------


func test_a_conflict_event_delegates_resolution_to_the_nation_module() -> void:
	var actor := _actor(&"mortal_plains", true)
	_remember(actor, &"sect_war_called")
	var opened := EventApi.begin(actor, WAR)
	assert_eq(bool(opened.get("ok", false)), true, "the war was declared: %s" % opened)
	assert_eq(bool(opened.get("declared", false)), true, "and it declared itself")
	var standoff_id := StringName(opened["standoff_id"])
	assert_ne(String(standoff_id), "", "against a real standoff")

	# `nation` owns the quota. A siege is five; the event director must not decide how
	# many verdicts that takes, so this reads `NationApi.QUOTAS` rather than a literal.
	var quota := int(NationApi.QUOTAS["siege"])
	assert_eq(quota, 5, "the siege quota is `nation`'s to declare")
	for verdict in range(quota):
		var step := EventApi.resolve(actor, WAR, &"march_of_the_nine_provinces")
		assert_eq(
			bool(step.get("delegated", false)),
			true,
			"every resolution is a DELEGATION, not a computation: verdict %d" % verdict
		)
		assert_eq(
			bool(step.get("closed", false)), false, "and the war is still open at %d" % verdict
		)
	var closed := EventApi.resolve(actor, WAR, &"march_of_the_nine_provinces")
	assert_eq(bool(closed.get("closed", false)), true, "the declared quota closes it")
	assert_eq(bool(closed.get("paid", false)), true, "and the prize is paid once")
	var ledger := NationApi.state(actor)
	assert_eq(
		bool((ledger["standoffs"] as Dictionary)[String(standoff_id)]["closed"]),
		true,
		"and the standoff in `nation` — not here — is the thing that closed"
	)


func test_the_event_records_the_delegation_rather_than_the_outcome_arithmetic() -> void:
	var actor := _actor(&"mortal_plains", true)
	_remember(actor, &"sect_war_called")
	EventApi.begin(actor, WAR)
	EventApi.resolve(actor, WAR, &"march_of_the_nine_provinces")
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
	var facts := EventFacts.ledger(actor)
	assert_eq(
		EventFacts.count_of(facts, &"beast_tide_started"),
		1,
		"the def's own on_enter beat is recorded under ADR 0113's key"
	)
	assert_eq(
		EventFacts.count_of(facts, &"beast_tide_moving"),
		1,
		"and so is the first stage's, which is a BEAT and not a reward (ADR 0114)"
	)
	assert_eq(
		(actor.get_module_data(EventFacts.MODULE_KEY) as Dictionary).has("facts"),
		true,
		"the ledger lives where ADR 0113 says it does: actor.module_data['world_facts']"
	)


func test_a_beat_id_is_unique_per_occurrence_as_adr_0114_requires() -> void:
	# "A beat's id MUST be unique per occurrence — the caller mints `&"killed_boar@3"`
	# for the third boar — and the ledger records occurrence ids under a count."
	var actor := _actor()
	var ledger := EventFacts.ledger(actor)
	var ids: Array[String] = []
	for occurrence in range(1, 4):
		ids.append(String(EventFacts.occurrence_id(&"killed_boar", occurrence)))
		EventFacts.record(ledger, &"killed_boar", 1, occurrence)
	assert_eq(ids[0], "killed_boar@1", "the first occurrence is named 1")
	assert_ne(ids[0], ids[1], "two occurrences are never the same id")
	assert_ne(ids[1], ids[2], "and neither are three")
	assert_eq(EventFacts.count_of(ledger, &"killed_boar"), 3, "while the fact counts all three")


func test_a_fact_is_monotone_and_a_zero_amount_records_nothing() -> void:
	# ADR 0113: `record()` raises a count and never lowers one. A "consumed" thing is
	# a quest step, not a fact.
	var ledger := EventFacts.ledger(null)
	EventFacts.record(ledger, &"beast_slain", 2, 4)
	assert_eq(EventFacts.count_of(ledger, &"beast_slain"), 2, "it counted two")
	EventFacts.record(ledger, &"beast_slain", 0, 5)
	assert_eq(EventFacts.count_of(ledger, &"beast_slain"), 2, "a zero amount changes nothing")
	EventFacts.record(ledger, &"beast_slain", -5, 6)
	assert_eq(EventFacts.count_of(ledger, &"beast_slain"), 2, "and neither does a negative one")
	assert_eq(
		int((ledger["facts"] as Dictionary)["beast_slain"]["since"]),
		4,
		"`since` is the sequence at which it FIRST occurred, carried forward"
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
	EventApi.advance(actor, 1)
	bus.world_evolved.disconnect(on_evolved)
	assert_eq(seen.has("triggered"), true, "opening announced a conflict was triggered")
	assert_eq(seen.has("evolved"), true, "and the stage move announced the evolution")
	assert_eq(seen.size(), 2, "and nothing else fired")


# --- The catalog (BL-0054 content) -----------------------------------------


func test_the_catalog_ships_one_event_for_every_kind_bl_0054_names() -> void:
	var report := EventApi.catalog()
	for kind in NAMED_KINDS:
		assert_eq(
			int((report["by_kind"] as Dictionary).get(String(kind), 0)) >= 1,
			true,
			"BL-0054 names %s and the tree ships none" % kind
		)
	assert_eq(int(report["count"]) >= 6, true, "at least six authored events")
	assert_eq(
		(report["problems"] as Array).size(), 0, "and no content defect: %s" % report["problems"]
	)
	assert_eq((report["rejected"] as Array).size(), 0, "and nothing rejected")


func test_no_authored_trigger_names_a_verb_this_module_cannot_read() -> void:
	# The tool-facing half of `catalog()`: a typo in a `.tres` is caught here rather
	# than by a player failing to open the event it locked.
	var unknown := EventApi.catalog()["unknown_verbs"] as Array
	assert_eq(
		unknown.size(),
		0,
		"every authored requirement names a known verb: %s" % ", ".join(_verb_texts(unknown))
	)


func test_every_authored_event_is_tied_to_a_location_the_world_module_ships() -> void:
	# ADR 0113: the playfield is a `WorldLocationDef` reference. An event pointing at a
	# place that does not exist is an event nobody can open.
	var shipped: Array[String] = []
	for row in WorldApi.locations(null):
		shipped.append(String(row["location_id"]))
	assert_eq(shipped.size() >= 4, true, "the world module ships locations to check against")
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		assert_eq(
			shipped.has(String(def.location_id)),
			true,
			(
				"%s is tied to location '%s', which the world module does not ship"
				% [String(event_id), String(def.location_id)]
			)
		)


func test_every_authored_prize_names_content_the_build_actually_ships() -> void:
	# The authored tree may only name ids that exist, or the gate and the prize refuse
	# forever — which is exactly what DEF-0105/0106/0107 recorded about unreachable
	# gates. A fate the destiny catalog does not define would silently pay nothing.
	var report := EventApi.catalog()
	var war: Dictionary = (report["events"] as Dictionary)[String(WAR)]
	assert_eq(bool(war["is_conflict"]), true, "the sect war is authored as a conflict")
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		for row in def.pay:
			var kind := StringName(row.get("kind", ""))
			var id := StringName(row.get("id", ""))
			if kind == EventDef.PAY_FATE or kind == EventDef.PAY_DESTINY:
				var catalog := FateCatalog.instance()
				var known := (
					catalog.fate_definition(id) != null
					if kind == EventDef.PAY_FATE
					else catalog.destiny_definition(id) != null
				)
				assert_eq(
					known,
					true,
					(
						"%s pays %s '%s', which the destiny catalog does not ship"
						% [String(event_id), String(kind), String(id)]
					)
				)
			if kind == EventDef.PAY_NATION_STANDING:
				assert_ne(
					String(id),
					"",
					(
						"%s pays nation standing but names no polity to read the declaration from"
						% String(event_id)
					)
				)


func test_an_event_def_walk_is_not_vacuous() -> void:
	# A structural test that reads no files proves nothing. Prove the catalog is
	# actually loaded before every assertion above is believed.
	var ids := EventCatalog.instance().event_ids()
	assert_eq(ids.size() >= 6, true, "the catalog loaded: %d events" % ids.size())
	assert_eq(EventCatalog.instance().has(WAR), true, "the war is in it")
	assert_eq(EventCatalog.instance().has(TREASURE), true, "and the treasure")


func test_a_malformed_def_is_rejected_and_reported_rather_than_silently_absent() -> void:
	# An event that loads and can never open is the shape ADR 0077 named. A refusal
	# that is REPORTED is a content bug the author finds.
	var bad := EventDef.new()
	bad.id = &"an_event_with_a_kind_nobody_reads"
	bad.display_name = "Bad"
	bad.kind = &"doomsday"
	var accepted := EventCatalog.instance().register(bad)
	assert_eq(accepted, false, "a def with an unknown kind is refused")
	var reported: Array[Dictionary] = EventCatalog.instance().rejected()
	var named := false
	for entry in reported:
		if String(entry["id"]) == "an_event_with_a_kind_nobody_reads":
			named = true
	assert_eq(named, true, "and it is reported with its reason: %s" % reported)


# --- Plumbing ---------------------------------------------------------------


## Every `.gd` under `root`, found iteratively and sorted. The same reason
## `test_nation_conflict.gd` walks that way: a recursive `DirAccess` returned an empty
## list under this runner once, and an empty scan makes every assertion pass vacuously.
func _module_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path: String = current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)
			elif entry.ends_with(".gd"):
				out.append(path)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


## Code with every comment removed, so a module that DOCUMENTS the rule it obeys is
## not reported for obeying it in prose.
func _strip_comments(text: String) -> String:
	var out: Array[String] = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)


func _verb_texts(unknown: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in unknown:
		out.append(
			(
				"%s(%s) names '%s'"
				% [
					String((entry as Dictionary)["event_id"]),
					String((entry as Dictionary)["where"]),
					String((entry as Dictionary)["verb"])
				]
			)
		)
	return out
