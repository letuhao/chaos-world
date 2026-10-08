extends TestCase

## THE failure-branch clause of the DONE criterion, audited.
##
## Six legs are proved end to end by `test_r30_is_earned_end_to_end.gd`: enrol,
## train, break through, survive a tribulation, reach the terminal realm. The
## seventh — **fail recoverably** — was nobody's job. This file is that job, and it
## asks one question of every refusal a player can be handed: **can a player cause
## it, and can the player see it?**
##
## ## The finding that shapes the file
##
## The task named the refusal shape `{ok: false, reason: R}`. **On four of the six
## legs that shape does not exist.** Enrol and tribulation speak it; train,
## breakthrough, recovery and the terminal-realm gates answer `false`, `{}` or
## `null`. So a grep for `ok: false` finds almost nothing on four legs and finds it
## in a place that is not a player gate at all. Both halves are asserted here — one
## BEHAVIOURALLY (the return type of each facade verb) and one STRUCTURALLY (which
## entry-point file authors the shape), because a grep alone survives neither being
## refactored.
##
## ## What "reachable" means here
##
## Reachable = a caller acting only through a **production entry point** can cause
## it. Not "a test can": several refusals are trivially reachable by naming an id
## the shipped program never offers, which is a test-only door, not a player's.
## Every loop below is bounded by a constant naming the condition it stops on, and
## nothing instantiated here is left unfreed.

# --- The refusal shapes, named once ------------------------------------------
#
# Named so a test asserts the SHIPPED string rather than a restatement of it: a copy
# in this file would let the wording drift and the assertion pass anyway.

## `TribulationFight.begin`, below the Immortal tier.
const R_NOT_OWED := "no realm above the Immortal gate is owed yet"
## `TribulationFight.begin`, with a fight already in the air.
const R_IN_PROGRESS := "a tribulation is already in progress"
## `TribulationFight.begin`, when the record would not start. PROVED DEAD below.
const R_WOULD_NOT_BEGIN := "the tribulation would not begin"
## `TribulationFight.fight_wave`, with no record.
const R_NOT_BEGUN := "no tribulation has begun"
## `TribulationFight.fight_wave`, on a decided record.
const R_ALREADY_DECIDED := "the tribulation is already decided"

## `CharacterCreationFlow.build` / `grant_origin`.
const R_UNKNOWN_ORIGIN := "unknown_origin"
const R_ALREADY_CREATED := "already_created"
const R_GATE_UNMET := "gate_unmet"
## `CharacterCreationFlow.build_forced`.
const R_UNKNOWN_ARRIVAL := "unknown_arrival"
const R_ARRIVAL_NO_BODY := "arrival_names_no_body"
## `CharacterCreation.act_commit`, with no seam wired.
const R_NO_SEAM := "no_creation_seam"

# --- Fixtures ------------------------------------------------------------------

## The scene the creation screen ships as.
const CREATION_SCENE := "res://src/ui/screens/character_creation.tscn"
## The scene the body panel ships as — the production caller of the durable half.
const BODY_SCREEN := "res://src/ui/screens/body_cultivation_panel.tscn"

## Stops a sweep over a ladder that stopped ending.
const LADDER_GUARD := 64
## Stops a wave driver whose phase machine stopped converging.
const WAVE_GUARD := 24
## Stops a wave driver that never reaches its verdict. `TribulationFight.WAVE_GUARD`
## is two full fights of headroom over the longest authored one, and a single fight
## cannot exceed that, so this bound is never the reason a loop stops.
const VERDICT_GUARD := 16
## Stops a scan that stopped finding occurrences, which would otherwise be a loop
## whose bound is derived from the thing it counts.
const OCCURRENCE_GUARD := 4096


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


## Ladder index of the first realm a tribulation is owed for.
func _gate() -> int:
	return Breakthrough.IMMORTAL_REALM_THRESHOLD


## A body-path hero standing at `index`, with the meridian network unlocked so the
## fight has something to damage. Nothing about its high-tier state is written: no
## ascension, no world, no tribulation record.
func _hero(index: int = -1) -> Actor:
	var at := _gate() - 1 if index < 0 else index
	var realm_id := _realm_id(at)
	var actor := Actor.new(&"refusal_hero", {Stat.COMPREHENSION: 60.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	return actor


## The same hero with the body module attached the way `app/` attaches it, so the
## cultivation verbs have a reservoir, a provider and a huyệt set to act on.
func _body_hero(index: int = 0) -> Actor:
	var actor := _hero(index)
	ItemsApi.attach(actor)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	BodyTraining.synchronize(actor)
	return actor


## A body hero brought to the brink of its next realm through the same field writes
## the shipped training uses. Only needed where a refusal has to be reached past the
## preparation gate, because a hero that is not ready is refused by a DIFFERENT
## guard than the one under test.
func _prepared_hero() -> Actor:
	var actor := _body_hero()
	var state := actor.path(BodyPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	assert_ne(target, null, "the ladder has a realm ahead of this hero")
	if target == null:
		return actor
	var seed := BodyRealmSeed.for_realm(target.id)
	assert_ne(seed, null, "that realm ships a body seed")
	if seed == null:
		return actor
	actor.meridians.unlock_for_realm(target.id)
	for meridian_id in seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		if channel.is_injured():
			actor.meridians.repair_meridian(meridian_id)
		actor.meridians.open_meridian(meridian_id)
		actor.meridians.expand_meridian(meridian_id)
		actor.meridians.strengthen_meridian(meridian_id)
		var refine := 0
		while (
			actor.meridians.refine_meridian(meridian_id, seed.required_refinement) and refine < 32
		):
			refine += 1
	var points: AcupointSet = actor.component(&"acupoints")
	for point in points.points:
		point.clear_block()
		point.quality = maxf(point.quality, seed.quality_required)
	points.fill(seed.integrity_maximum)
	state.progress = seed.progress_required
	if actor.stats.get_base(Stat.PHYSIQUE) < seed.physique_required:
		actor.stats.set_base(Stat.PHYSIQUE, seed.physique_required)
	var meditate := 0
	while (
		meditate < OCCURRENCE_GUARD
		and actor.stats.get_base(Stat.COMPREHENSION) < seed.insight_required
	):
		meditate += 1
		BodyTraining.meditate(actor, 1.0)
	_stock(actor, seed.breakthrough_item)
	return actor


## One authored item into the actor's inventory, asserted rather than assumed.
func _stock(actor: Actor, def_id: StringName, quantity: int = 1) -> void:
	var inventory := ItemsApi.inventory(actor)
	assert_ne(inventory, null, "the actor carries an inventory")
	if inventory == null:
		return
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	inventory.add(def, quantity)


## A generator on a pinned seed whose first draw is below every possible endurance,
## so a fight driven with it always survives. `TribulationEndurance.MIN_ENDURANCE`
## is the floor every rating clamps to, so a draw under it wins whatever the
## rating — which is what makes the seed a guarantee rather than a hope.
func _roll_winning() -> RandomNumberGenerator:
	return _seeded(TribulationEndurance.MIN_ENDURANCE, false)


func _seeded(threshold: float, above: bool) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var guard := 0
	while guard < OCCURRENCE_GUARD:
		guard += 1
		rng.seed = guard
		if (rng.randf() >= threshold) == above:
			return rng
	return null


func _reason(verdict: Dictionary) -> String:
	return String(verdict.get("reason", "<no reason key>"))


func _refused(verdict: Dictionary) -> bool:
	return not bool(verdict.get("ok", true))


## Begin the owed fight, then press the screen's own verb until the record is
## DECIDED. Which way it is decided is irrelevant here: every assertion below is
## about the refusal a decided record gives, and going through the facade means no
## module internal is reached.
func _decided_fight() -> Tribulation:
	var hero := _hero()
	var begun := HeavenlyTribulationApi.begin(hero)
	assert_eq(_refused(begun), false, "the fight begins: %s" % _reason(begun))
	var guard := 0
	while guard < VERDICT_GUARD and hero.tribulation.outcome == Tribulation.OUTCOME_UNRESOLVED:
		guard += 1
		HeavenlyTribulationApi.fight_wave(hero)
	return hero.tribulation


# --- 1. Which vocabulary each leg speaks ---------------------------------------


## THE shape of the finding, asserted by RUNNING each verb rather than by reading
## its signature: the tribulation verbs hand back a dictionary that NAMES its
## refusal, and the cultivation verbs hand back a bare `false` that names nothing.
##
## Both halves are load-bearing. Dropping the named shape from the tribulation leg
## fails the first; ADDING one to a cultivation leg fails the second — and adding
## one is the change this file exists to argue for.
func test_only_the_tribulation_leg_hands_back_a_named_refusal() -> void:
	var mortal := _hero(0)
	assert_eq(bool(mortal.path(BodyPath.PATH_ID).rank_id == _realm_id(0)), true, "R1 hero is on R1")
	assert_eq(
		bool(HeavenlyTribulationApi.state(mortal)["owed"]),
		false,
		"and owes no tribulation, so begin has something to refuse"
	)
	var not_owed := HeavenlyTribulationApi.begin(mortal)
	assert_eq(bool(not_owed.has("ok")), true, "the tribulation leg answers with an `ok` key")
	assert_eq(_reason(not_owed), R_NOT_OWED, "and names why: %s" % _reason(not_owed))

	var hero := _body_hero()
	assert_eq(
		typeof(BodyCultivationApi.cultivate(hero, 25.0)),
		TYPE_BOOL,
		"body train answers with a bare bool, which has nowhere to put a reason"
	)
	assert_eq(
		typeof(BodyCultivationApi.attempt_breakthrough(hero)),
		TYPE_BOOL,
		"body breakthrough answers with a bare bool"
	)
	assert_eq(
		typeof(BodyCultivationApi.recover_next(hero)),
		TYPE_BOOL,
		"body recovery answers with a bare bool"
	)
	assert_eq(
		typeof(QiCultivationApi.attempt_breakthrough(hero)),
		TYPE_BOOL,
		"qi breakthrough answers with a bare bool"
	)
	assert_eq(
		typeof(MindCultivationApi.try_breakthrough(hero)),
		TYPE_BOOL,
		"mind breakthrough answers with a bare bool"
	)


## The same fact from the other side, because the behaviour above only covers the
## verbs this file happened to call. This catches a fourth entry point added later.
##
## INVENTORY, not a rule: a refactor that gives a cultivation leg a named refusal
## turns this RED, and the answer is to widen the expected set — not to delete it.
func test_no_cultivation_entry_point_authors_the_named_shape() -> void:
	var entry_points := [
		"res://src/modules/body_cultivation/api.gd",
		"res://src/modules/qi_cultivation/api.gd",
		"res://src/modules/mind_cultivation/api.gd",
		"res://src/modules/heavenly_tribulation/api.gd",
		"res://src/core/breakthrough.gd",
		"res://src/core/world_anchor.gd",
	]
	for path: String in entry_points:
		assert_eq(
			_code_of(path).contains('"ok": false'),
			false,
			(
				(
					"INVENTORY: %s now authors an {ok:false} refusal, so a cultivation leg speaks "
					+ "the named shape and this inventory is stale"
				)
				% path
			)
		)
	# The contrast, pinned. Without it the loop above would also pass on a tree where
	# nothing refuses by name anywhere.
	assert_eq(
		_code_of("res://src/modules/heavenly_tribulation/tribulation_fight.gd").contains(
			'"ok": false'
		),
		true,
		"the tribulation module is where the named shape actually lives"
	)


# --- 2. Leg 5, tribulation: every refusal, named -------------------------------


## Below the gate nothing is owed, and `begin` refuses **by name**. Causeable on
## purpose: open the tribulation screen below R19 and press Begin.
func test_begin_refuses_by_name_when_no_realm_is_owed() -> void:
	var mortal := _hero(0)
	var refused := HeavenlyTribulationApi.begin(mortal)
	assert_eq(_refused(refused), true, "so Begin refuses")
	assert_eq(_reason(refused), R_NOT_OWED, "and names the gate it is waiting for")
	assert_eq(
		bool(refused.get("decided", true)),
		false,
		"and reports no verdict, because nothing was fought"
	)


## A second Begin while a fight is in the air — the refusal that exists to stop a
## caller discarding the waves already survived. Causeable by pressing Begin twice:
## the state that makes the second press refuse is the one the first press created.
func test_begin_refuses_a_second_time_while_a_fight_is_in_the_air() -> void:
	var hero := _hero()
	var first := HeavenlyTribulationApi.begin(hero)
	assert_eq(_refused(first), false, "the first Begin starts the fight")
	assert_eq(bool(HeavenlyTribulationApi.state(hero)["active"]), true, "which is now active")
	var second := HeavenlyTribulationApi.begin(hero)
	assert_eq(_refused(second), true, "a second Begin refuses")
	assert_eq(_reason(second), R_IN_PROGRESS, "and names the fight already running")
	assert_eq(hero.tribulation.wave, 0, "and the fight it would have replaced is untouched")


## `fight_wave` with no record at all: pressing Fight on a screen whose state has
## not been re-read, and any caller that fights before it begins.
func test_fight_wave_refuses_by_name_with_no_record() -> void:
	var refused := HeavenlyTribulationApi.fight_wave(_hero())
	assert_eq(_refused(refused), true, "fighting a fight that has not begun refuses")
	assert_eq(_reason(refused), R_NOT_BEGUN, "and says which half of the lifecycle is missing")


## Once decided, a fight is finished: the waves are spent and the gate is open or
## shut for good. Causeable by pressing Fight after the verdict button.
func test_fight_wave_refuses_a_fight_that_is_already_decided() -> void:
	var record := _decided_fight()
	assert_ne(record, null, "a fight was fought to a verdict")
	assert_ne(record.outcome, Tribulation.OUTCOME_UNRESOLVED, "so it is decided")
	var hero := _hero()
	hero.tribulation = record
	var again := HeavenlyTribulationApi.fight_wave(hero)
	assert_eq(_refused(again), true, "fighting it again refuses")
	assert_eq(_reason(again), R_ALREADY_DECIDED, "and names the verdict as the reason")


## `withdraw` is the one verb a player uses to ABANDON a fight they cannot win —
## the fail-recoverably instinct — and it answers with a bool, so "there was no
## fight", "the fight is already decided" and "you walked away from it" are one
## answer with nowhere to put which.
func test_withdraw_answers_with_a_bool_so_its_two_refusals_are_one_answer() -> void:
	var idle := _hero()
	assert_eq(HeavenlyTribulationApi.withdraw(idle), false, "withdrawing nothing is false")
	var hero := _hero()
	assert_eq(_refused(HeavenlyTribulationApi.begin(hero)), false, "a fight can be begun")
	assert_eq(HeavenlyTribulationApi.withdraw(hero), true, "so withdrawing it is true")
	assert_eq(HeavenlyTribulationApi.withdraw(hero), false, "and withdrawing it twice is false")
	var decided := _decided_fight()
	var fresh := _hero()
	fresh.tribulation = decided
	assert_eq(
		HeavenlyTribulationApi.withdraw(fresh),
		false,
		"and a DECIDED fight refuses exactly as a nonexistent one does — same false, no reason"
	)


# --- 3. UNREACHABLE: two refusals nothing can cause ----------------------------


## `"the tribulation would not begin"` is DEAD CODE.
##
## `TribulationFight.begin` only calls `Breakthrough.begin_tribulation` after
## `target_index(actor) >= 0`, and `Breakthrough.owed_index` returns -1 for
## anything below `IMMORTAL_REALM_THRESHOLD` — so the index handed down is always at
## or above the threshold. `begin_tribulation`'s ONE `return null` is the
## sub-threshold guard, so it cannot fire from here. The refusal reads as a designed
## failure and nothing in the shipped program can produce it.
##
## Two proofs, because they fail differently. The sweep is BEHAVIOURAL: it walks
## every ladder position a hero can stand at. The source read is STRUCTURAL: it
## catches a SECOND `return null` added to `begin_tribulation` later, which the
## sweep would only reach by luck.
func test_begin_never_refuses_as_would_not_begin_anywhere_on_the_ladder() -> void:
	var ladder := RealmDefaults.ladder().realms()
	var guard := 0
	var walked := 0
	while guard < LADDER_GUARD and walked < ladder.size():
		guard += 1
		var index := walked
		walked += 1
		var hero := _hero(index)
		var owed := bool(HeavenlyTribulationApi.state(hero)["owed"])
		var refused := HeavenlyTribulationApi.begin(hero)
		assert_eq(
			_reason(refused),
			R_NOT_OWED if not owed else "",
			"R%d answers the gate or names it owed, never 'would not begin'" % (index + 1)
		)
		assert_eq(
			_reason(refused) == R_WOULD_NOT_BEGIN,
			false,
			"R%d cannot produce the dead refusal" % (index + 1)
		)
		# Re-pressing on the same hero lands on the in-progress refusal — the one
		# refusal on this leg a second press really can reach.
		var second := HeavenlyTribulationApi.begin(hero)
		assert_eq(
			_reason(second),
			R_IN_PROGRESS if owed else R_NOT_OWED,
			"R%d's second press names the one refusal it can reach" % (index + 1)
		)
	assert_eq(walked, ladder.size(), "every ladder position was walked")


## The structural half: `begin_tribulation` has exactly ONE null return and it is
## the sub-threshold guard, and the only caller has already excluded that condition.
func test_begin_tribulations_only_null_return_is_the_sub_threshold_guard() -> void:
	var source := FileAccess.get_file_as_string("res://src/core/breakthrough.gd")
	var body := _function_body(source, "begin_tribulation")
	assert_ne(body, "", "begin_tribulation was found in core/breakthrough.gd")
	if body == "":
		return
	assert_eq(
		_occurrences(body, "return null"),
		1,
		"begin_tribulation has exactly one `return null`, so the caller's refusal has one trigger"
	)
	assert_eq(
		body.contains("next_index < IMMORTAL_REALM_THRESHOLD"),
		true,
		"and it is the sub-threshold guard"
	)
	var fight := FileAccess.get_file_as_string(
		"res://src/modules/heavenly_tribulation/tribulation_fight.gd"
	)
	var begin_body := _function_body(fight, "begin")
	assert_eq(
		begin_body.contains("if index < 0:"),
		true,
		"TribulationFight.begin refuses index < 0 before it calls down"
	)
	assert_eq(
		_function_body(source, "owed_index").contains("index >= IMMORTAL_REALM_THRESHOLD"),
		true,
		"and owed_index only ever reports an index at or above the threshold"
	)


## The second dead refusal: `"the tribulation did not reach a verdict in N waves"`.
##
## `fight_to_verdict` is bounded by `TribulationFight.WAVE_GUARD` and the deepest
## authored fight is `WAVES_BY_TIER[TRANSCENDENT]` waves. If the guard leaves room
## for the longest authored fight plus the wave that decides it, the loop always
## exits through `decided` and the trailing refusal cannot fire.
func test_the_wave_guard_outlives_the_longest_authored_fight() -> void:
	var longest := 0
	for waves in Tribulation.WAVES_BY_TIER.values():
		longest = maxi(longest, int(waves))
	assert_ne(longest, 0, "the authored wave counts were read")
	assert_eq(
		longest + 2 <= TribulationFight.WAVE_GUARD,
		true,
		(
			"the guard (%d) outlives the longest authored fight (%d waves) plus its deciding one"
			% [TribulationFight.WAVE_GUARD, longest]
		)
	)


## And the consequence, RUN rather than argued: on the deepest tier, where the
## authored fight is longest, one press reaches a verdict and the guard's trailing
## refusal never fires.
func test_fighting_to_a_verdict_on_the_deepest_tier_never_trips_the_guard() -> void:
	var hero := _hero(WorldAnchor.COMMIT_MICRO)
	assert_eq(
		int(HeavenlyTribulationApi.begin(hero).get("max_waves", 0)),
		int(Tribulation.WAVES_BY_TIER[RealmDefaults.TRANSCENDENT]),
		"the deepest tier really does begin the longest authored fight"
	)
	var result := HeavenlyTribulationApi.fight_to_verdict(hero)
	assert_eq(bool(result.get("decided", false)), true, "and it reaches a verdict in one press")
	assert_eq(
		_reason(result), "", "so the guard's trailing refusal never fires: %s" % _reason(result)
	)


# --- 4. Leg 1, enrol: the named refusals, and the door that is not there --------


## The refusals `build` names, each driven once and asserted by its exact string.
## `unknown_origin` needs an id the CATALOG ships but this layer does not create,
## because a bare nonsense id would prove only that nonsense is refused.
func test_build_names_every_refusal_it_can_give() -> void:
	var nonsense := CharacterCreationFlow.new().build(&"no_such_arrival")
	assert_eq(_refused(nonsense), true, "an id nothing defines is refused")
	assert_eq(_reason(nonsense), R_UNKNOWN_ORIGIN, "and named")
	assert_eq(nonsense.has("actor"), false, "and mints no hero")

	# `the_oath_bound` is a REAL authored destiny this layer does not create: it has
	# no body to arrive in. Refusing it is the point — granting it would mint a
	# raceless hero, which is the defect the creation layer exists to close.
	var authored := CharacterCreationFlow.new().build(&"the_oath_bound")
	assert_eq(_refused(authored), true, "an authored arrival this layer does not create is refused")
	assert_eq(_reason(authored), R_UNKNOWN_ORIGIN, "and named, not granted raceless")

	var flow := CharacterCreationFlow.new()
	assert_eq(
		bool(flow.build(&"the_one_who_stayed").get("ok", false)), true, "the first arrival commits"
	)
	var second := flow.build(&"the_one_who_returned")
	assert_eq(_refused(second), true, "a second hero is refused")
	assert_eq(_reason(second), R_ALREADY_CREATED, "and named")


## The exclusivity refusal, on the verb that reports it.
##
## `grant_origin` is where ADR 0065's "closes the other two for good" lands, and it
## is a NAMED refusal carrying the gate's own `unmet` entries. Reachable — but note
## WHO reaches it: the shipped creation screen calls `build`, not this.
func test_grant_origin_names_the_exclusivity_refusal_with_the_gates_own_reason() -> void:
	var created := CharacterCreationFlow.new().build(&"the_one_who_stayed")
	var hero := created.get("actor", null) as Actor
	assert_ne(hero, null, "an arrival committed")
	for other: StringName in [&"the_one_who_returned", &"the_chosen_instrument"]:
		var refused := CharacterCreationFlow.new().grant_origin(hero, other)
		assert_eq(_refused(refused), true, "%s is closed for good" % String(other))
		assert_eq(
			_reason(refused), R_GATE_UNMET, "and named as the gate's refusal, not a local rule"
		)
		assert_eq(
			(refused.get("unmet", []) as Array).is_empty(),
			false,
			"and it carries the gate's own reason, so a screen has something to show"
		)


## `build`'s own `gate_unmet` is UNREACHABLE on today's content: every arrival the
## catalog offers commits on a fresh flow. So it is a content-drift guard rather
## than a player gate. Read over the catalog rather than a kept list, so an added
## `.tres` turns this red on its own.
func test_builds_gate_unmet_is_unreachable_on_todays_content() -> void:
	var offered := CharacterCreationFlow.new().candidates()
	assert_eq(offered.is_empty(), false, "the creation screen offers at least one arrival")
	for entry in offered:
		var origin_id := StringName((entry as Dictionary).get("id", ""))
		var created := CharacterCreationFlow.new().build(origin_id)
		assert_eq(
			bool(created.get("ok", false)),
			true,
			(
				"offered arrival '%s' commits, so build's gate_unmet never fires: %s"
				% [String(origin_id), _reason(created)]
			)
		)


## `build_forced`, the rebirth arrival. `unknown_arrival` and
## `arrival_names_no_body` are guards over authored data: no player action changes
## which `.tres` files ship, and the one production caller validates the arrival id
## before it calls down. So both are TEST-ONLY, and this asserts the content half of
## that claim rather than asserting it in prose.
func test_build_forceds_content_guards_have_nothing_to_fire_on() -> void:
	var arrivals := ContentScan.files_under("res://data/soul/arrivals", ".tres")
	assert_eq(arrivals.is_empty(), false, "the arrival catalogue ships something")
	var nameless := 0
	for path: String in arrivals:
		var source := FileAccess.get_file_as_string(path)
		if not source.contains('race_id = &"') or source.contains('race_id = &""'):
			nameless += 1
	assert_eq(
		nameless,
		0,
		"every authored arrival names a body, so 'arrival_names_no_body' has no shipped trigger"
	)
	var unknown := CharacterCreationFlow.build_forced(&"no_such_arrival")
	assert_eq(_refused(unknown), true, "and an id outside the catalogue is refused")
	assert_eq(_reason(unknown), R_UNKNOWN_ARRIVAL, "and named")
	assert_eq(unknown.get("actor", null), null, "and mints no body")


## **THE LEG-1 REACHABILITY HALF.** The enrol leg has a screen, a route, and a seam.
##
## This was the file's biggest finding and it was TRUE when first written: the screen
## shipped unrouted, `bind_creation` had no caller in `res://src`, and a passing suite
## covered a screen no player could open — the shape `CharacterCreationProgram`'s own
## docstring records. A concurrent agent routed the screen and landed the program that
## wires the seam. The assertions below are the re-measurement, kept because BL-0619 is
## the whole lesson: a tracked finding decays silently, so the state that makes it FALSE
## is itself asserted.
##
## What is still true, and what the classification below relies on: nothing in
## `res://src` mounts a creation screen WITHOUT its seam, so `no_creation_seam` guards a
## wiring mistake rather than anything a player can hit.
func test_the_creation_screen_is_routed_and_given_a_seam() -> void:
	assert_eq(
		ScreenRoutes.id_for_scene(CREATION_SCENE),
		&"character_creation",
		"the creation screen is routed, so a player can open it"
	)
	var wiring := ""
	var callers := 0
	for path: String in ContentScan.files_under("res://src", ".gd"):
		# A screen's own definition is not a caller of its own method.
		if path.ends_with("ui/screens/character_creation.gd"):
			continue
		if FileAccess.get_file_as_string(path).contains("bind_creation"):
			callers += 1
			wiring = path
	assert_eq(
		callers,
		1,
		"and exactly one production caller hands the screen its arrivals and commit callable"
	)
	assert_eq(
		wiring,
		"res://src/app/character_creation_program.gd",
		"and it is the composition root's creation program"
	)


## The enrol leg's own program adds five more named refusals on top of the flow's
## three. Each is driven and classified here, because a new `{ok:false, reason}` on a
## six-leg entry point is exactly what this file exists to account for — and a
## concurrent agent added five while it was being written.
##
## Four are TEST-ONLY: they fire on a program constructed without its stack, flow or
## route opener, which is a wiring mistake and not a player's situation.
## `already_has_hero` is a RETURNING-PLAYER guard and is unreachable through the only
## production caller, which opens creation precisely when no hero exists. It is the one
## refusal here that would start mattering if the nav bar's route button were ever made
## to go through the program rather than straight to the route.
func test_the_creation_programs_own_refusals_are_named_and_classified() -> void:
	var unmounted := CharacterCreationProgram.new()
	var no_stack := unmounted.open()
	assert_eq(_refused(no_stack), true, "a program with no stack refuses to open")
	assert_eq(_reason(no_stack), "not_mounted", "and says the program is not mounted")
	var no_flow := unmounted.commit(&"the_one_who_stayed")
	assert_eq(_refused(no_flow), true, "and refuses to commit")
	assert_eq(_reason(no_flow), "not_mounted", "with the same reason")

	# The next two refusals sit BEHIND the mounted check, so reaching them needs a
	# stack — which is why a program built as `new(null, flow)` still answers
	# `not_mounted` and not the more specific reason. A test that constructed it the
	# obvious way would assert the wrong string and pass for the wrong reason.
	var stack := ScreenStack.new()
	var flow_only := CharacterCreationProgram.new(stack, CharacterCreationFlow.new())
	assert_eq(
		_reason(flow_only.open()),
		"no_route_opener",
		"TEST-ONLY: a mounted program with no route opener names the missing piece"
	)
	var returning := CharacterCreationProgram.new(stack, CharacterCreationFlow.new())
	returning.adopt(Actor.new(&"returning"))
	assert_eq(returning.has_hero(), true, "a program given a hero holds one")
	assert_eq(
		_reason(returning.open()),
		"already_has_hero",
		"TEST-ONLY TODAY: a returning player is refused creation by name"
	)
	stack.free()


## `no_creation_seam` is TEST-ONLY, therefore: a screen no production caller mounts
## unbound. It refuses by name, which is the one thing it does right — and the reason
## it is classed this way is asserted above, not assumed.
func test_a_creation_screen_with_no_seam_refuses_every_commit_by_name() -> void:
	var packed := load(CREATION_SCENE) as PackedScene
	assert_ne(packed, null, "the creation scene loads")
	if packed == null:
		return
	var screen := packed.instantiate() as CharacterCreation
	assert_ne(screen, null, "and instantiates")
	if screen == null:
		return
	var outcome := screen.act_commit(&"the_one_who_stayed")
	assert_eq(_refused(outcome), true, "an unwired screen refuses the commit")
	assert_eq(_reason(outcome), R_NO_SEAM, "and names the missing seam")
	screen.free()


# --- 5. The classification, one row per refusal -------------------------------


## Every `{ok: false, reason: R}` on the six legs, each classified by CAUSING it
## rather than by describing it.
##
## `PLAYER-REACHABLE` — a caller doing only what the shipped program does can cause
## it. `TEST-ONLY` — a test can, by naming something the program never offers or by
## wiring a seam no caller wires. `DEAD` — nothing can cause it at all.
##
## This is the file's deliverable, so the assertions are per row rather than
## computed: a row that changes class has to be argued here.
func test_every_named_refusal_on_the_six_legs_is_classified_by_being_caused() -> void:
	# --- Leg 5, tribulation: four PLAYER-REACHABLE ---
	assert_eq(
		_reason(HeavenlyTribulationApi.begin(_hero(0))),
		R_NOT_OWED,
		"PLAYER-REACHABLE: below the gate, Begin refuses by name"
	)
	assert_eq(
		_reason(_begin_twice()), R_IN_PROGRESS, "PLAYER-REACHABLE: a second Begin refuses by name"
	)
	assert_eq(
		_reason(HeavenlyTribulationApi.fight_wave(_hero())),
		R_NOT_BEGUN,
		"PLAYER-REACHABLE: Fight with no record refuses by name"
	)
	var decided := _decided_fight()
	var on_decided := _hero()
	on_decided.tribulation = decided
	assert_eq(
		_reason(HeavenlyTribulationApi.fight_wave(on_decided)),
		R_ALREADY_DECIDED,
		"PLAYER-REACHABLE: Fight on a decided record refuses by name"
	)
	# --- Leg 5, tribulation: one DEAD ---
	assert_eq(
		_reachable_reason(R_WOULD_NOT_BEGIN),
		false,
		"DEAD: nothing can make begin refuse 'the tribulation would not begin'"
	)
	# --- Leg 1, enrol: wired, so one refusal is a player's and the rest are TEST-ONLY ---

	assert_eq(
		_reason(CharacterCreationFlow.new().build(&"the_oath_bound")),
		R_UNKNOWN_ORIGIN,
		"TEST-ONLY: unknown_origin needs an id the screen never offers"
	)
	var flow := CharacterCreationFlow.new()
	flow.build(&"the_one_who_stayed")
	assert_eq(
		_reason(flow.build(&"the_one_who_returned")),
		R_ALREADY_CREATED,
		"PLAYER-REACHABLE: a second press on another arrival row names already_created"
	)
	var hero := CharacterCreationFlow.new().build(&"the_one_who_stayed").get("actor", null) as Actor
	assert_eq(
		_reason(CharacterCreationFlow.new().grant_origin(hero, &"the_one_who_returned")),
		R_GATE_UNMET,
		"TEST-ONLY: gate_unmet needs a caller holding an actor, which the screen never is"
	)
	assert_eq(
		_reason(CharacterCreationFlow.build_forced(&"no_such_arrival")),
		R_UNKNOWN_ARRIVAL,
		"TEST-ONLY: unknown_arrival needs an id outside the shipped arrival catalogue"
	)
	assert_eq(
		_reachable_reason(R_ARRIVAL_NO_BODY),
		false,
		"TEST-ONLY: arrival_names_no_body needs an authored arrival with an empty race_id"
	)
	var screen := (load(CREATION_SCENE) as PackedScene).instantiate() as CharacterCreation
	assert_eq(
		_reason(screen.act_commit(&"the_one_who_stayed")),
		R_NO_SEAM,
		"TEST-ONLY: the wired screen never refuses this; only an unbound mount does"
	)
	screen.free()


func _begin_twice() -> Dictionary:
	var actor := _hero()
	HeavenlyTribulationApi.begin(actor)
	return HeavenlyTribulationApi.begin(actor)


## Whether any ladder position a hero can stand at produces `reason`. The sweep is
## what turns "I read the code and it cannot fire" into an assertion: every verb the
## tribulation screen presses is driven at every realm, twice, because the two
## refusals that depend on an existing record need one.
func _reachable_reason(reason: String) -> bool:
	var ladder := RealmDefaults.ladder().realms()
	var found := false
	var guard := 0
	var index := 0
	while guard < LADDER_GUARD and index < ladder.size():
		guard += 1
		var actor := _hero(index)
		if _reason(HeavenlyTribulationApi.begin(actor)) == reason:
			found = true
		if _reason(HeavenlyTribulationApi.begin(actor)) == reason:
			found = true
		HeavenlyTribulationApi.fight_wave(actor)
		if _reason(HeavenlyTribulationApi.fight_wave(actor)) == reason:
			found = true
		index += 1
	return found


# --- 6. The two-phase breakthrough lifecycle is reachable in play -------------


## `BodyCultivationApi.begin_breakthrough` and `resolve_breakthrough` are the
## documented "durable half": the pill is spent there and the record is persisted so
## a save taken mid-attempt resolves on reload. The facade's docstring promises a
## panel will read `panel_state`'s `attempt` and "offer resolve rather than a fresh
## breakthrough".
##
## This section used to pin them as UNREACHABLE: `attempt_breakthrough` was the only
## verb the screen pressed and it ran both halves inside one call, so no state a
## player could produce had an attempt in flight. The panel now presses the two
## halves itself (commit, then resolve), so the assertion is inverted: both verbs
## have a production caller, and the state the durable half exists for is one a
## player can produce.
func test_the_two_phase_breakthrough_lifecycle_has_a_production_caller() -> void:
	for verb: StringName in [&"begin_breakthrough", &"resolve_breakthrough"]:
		var callers := 0
		for path: String in ContentScan.files_under("res://src", ".gd"):
			# The definition itself is not a caller.
			if path.ends_with("body_cultivation/api.gd"):
				continue
			if FileAccess.get_file_as_string(path).contains("BodyCultivationApi.%s(" % verb):
				callers += 1
		assert_eq(
			callers >= 1,
			true,
			"BodyCultivationApi.%s is reachable in play: a shipped file calls it" % verb
		)
	# And the field that depends on it, driven the way the panel drives it: press once
	# to COMMIT (the attempt is in flight), press again to resolve it to terminal.
	var packed := load(BODY_SCREEN) as PackedScene
	assert_ne(packed, null, "the body panel scene loads")
	if packed == null:
		return
	var screen := packed.instantiate() as Control
	assert_ne(screen, null, "and instantiates")
	if screen == null:
		return
	var hero := _prepared_hero()
	screen.call("setup", hero)
	assert_eq(
		String(BodyAdvancement.preview(hero).get("attempt", "")),
		"",
		"a prepared hero with nothing attempted reports no attempt in flight"
	)
	screen.call("act_breakthrough")
	assert_ne(
		String(BodyAdvancement.preview(hero).get("attempt", "")),
		"",
		"and the panel's first press leaves one in flight — the durable state"
	)
	screen.call("act_breakthrough")
	assert_eq(
		String(BodyAdvancement.preview(hero).get("attempt", "")),
		"",
		"and the panel's second press resolves it to terminal"
	)
	screen.free()


## What makes that terminal: every exit from `resolve_attempt` ends the record, so no
## non-terminal attempt can survive the one call that could have created it. A future
## refactor that adds a mid-attempt `return` without an `_end` turns this red instead
## of silently reintroducing a stranded attempt.
func test_a_body_attempt_is_terminal_the_moment_the_one_call_returns() -> void:
	var hero := _prepared_hero()
	BodyCultivationApi.attempt_breakthrough(hero)
	var stored := BodyAdvancement.attempt(hero)
	assert_ne(stored, null, "a prepared hero's press wrote an attempt record")
	if stored == null:
		return
	assert_eq(
		stored.is_active(), false, "and it is terminal the moment the single-call verb returns"
	)


## The unit half of the pair: the durable lifecycle works when driven directly — it
## commits an attempt the panel renders as "an attempt is committed", and the resolve
## half rolls it. The reachability half is the test above, which drives the same two
## halves through the panel's own presses.
func test_the_durable_half_works_when_a_caller_drives_it() -> void:
	var hero := _prepared_hero()
	var committed := BodyCultivationApi.begin_breakthrough(hero)
	assert_eq(committed.is_empty(), false, "a caller can still commit an attempt")
	assert_ne(String(committed.get("attempt", "")), "", "which carries an attempt id")
	assert_eq(
		String(BodyAdvancement.preview(hero).get("attempt", "")),
		String(committed.get("attempt", "")),
		"and the preview reports it as in flight — the durable state"
	)
	assert_eq(BodyAdvancement.active_attempt(hero) != null, true, "the record is active")
	BodyCultivationApi.resolve_breakthrough(hero)
	assert_eq(
		BodyAdvancement.active_attempt(hero), null, "and resolving it leaves nothing in flight"
	)


## The refusal the durable half has and the one-press verb does not: an attempt
## already in flight blocks a second one. The panel never makes this call — it offers
## resolve once committed — so this is a caller-shape guard rather than a player
## press, and the body path reports it by returning an EMPTY dictionary rather than a
## named reason, so even the caller that reaches it is told nothing.
func test_an_attempt_already_in_flight_is_refused_without_a_reason() -> void:
	var hero := _prepared_hero()
	var first := BodyCultivationApi.begin_breakthrough(hero)
	assert_eq(first.is_empty(), false, "the first commit lands")
	var second := BodyCultivationApi.begin_breakthrough(hero)
	assert_eq(second.is_empty(), true, "a second commit is refused")
	assert_eq(
		second.has("reason"),
		false,
		"and the refusal is an EMPTY view, not a named one: there is nowhere to say why"
	)


# --- Source helpers ------------------------------------------------------------


## `source` with every comment line dropped.
##
## Not cosmetic. `heavenly_tribulation/api.gd` DOCUMENTS the refusal shape inside a
## docstring — `## `{"ok": false,` — so a raw substring search reports a facade that
## authors no refusal at all as one that does. The question this file asks is "does
## this file BUILD the shape", and prose about the shape is not building it.
func _code_of(path: String) -> String:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var stripped := String(line).strip_edges()
		if stripped.begins_with("#"):
			continue
		out.append(String(line))
	return "\n".join(out)


## The body of `func_name` in `source`: from its declaration to the next line at or
## below its indent. `""` when the function is not found, which every caller treats
## as a failure rather than as an empty read.
func _function_body(source: String, func_name: String) -> String:
	var lines := source.split("\n")
	var start := -1
	var indent := ""
	for index in lines.size():
		var line := String(lines[index])
		var stripped := line.strip_edges()
		var is_declaration := stripped.begins_with("func ") or stripped.begins_with("static func ")
		if is_declaration and stripped.contains("%s(" % func_name):
			start = index
			indent = line.substr(0, line.length() - stripped.length())
			break
	if start < 0:
		return ""
	var out: Array[String] = []
	for index in range(start + 1, lines.size()):
		var line := String(lines[index])
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		var here := line.substr(0, line.length() - stripped.length())
		if here.length() <= indent.length() and not stripped.begins_with("#"):
			break
		out.append(line)
	return "\n".join(out)


func _occurrences(haystack: String, needle: String) -> int:
	var count := 0
	var at := haystack.find(needle)
	while at >= 0 and count < OCCURRENCE_GUARD:
		count += 1
		at = haystack.find(needle, at + needle.length())
	return count
