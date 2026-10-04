extends TestCase

## DEF-0121 / DEF-0181, closed: `DestinyApi.record` had ZERO callers in `src/`, so all
## nine authored counter ids were permanently 0 and the `counter` gate verb was
## theatre — a fate declaring `counters = [&"duels_won"]` advertised progress no
## player could make, and `{verb: &"counter", id: &"duels_won", need: 3}` could never
## open.
##
## ## The chain this file drives is the PRODUCTION one, and it starts at
## `WorldFact.record`
##
## The first version of this file drove `WorldPulse.offer` -> `BeatDirector.offer` and
## was green the whole time, because **that is not the path the game takes**. The
## director's dispatch was real code and the suite exercising it was real, and 0 of
## the 8 authored pairs could still fire: `BeatDirector.offer` has ONE production
## caller, `app/WorldPulse.offer`, and that offers the period fact and the four
## `app/WorldAmbient` roster facts, none of which any fate reads. Every real producer
## called `WorldFact.record` directly and bypassed the dispatch (ADR 0149).
##
## So nothing below constructs a beat or offers one to a director. Every assertion
## drives the WRITER THAT ACTUALLY PRODUCES the fact — `CombatApi.hit`,
## `CombatApi.spare`, `ClanHeir.register`, `SectApi.promote`, `SectDuty.serve`,
## `event/EventBeatWriter` through the world's own tick, and
## `app/CharacterCreationFlow` — and reads the counter the module's own rule moved.
## A test that still went through the director would go green on the old broken build,
## which is the whole reason the previous version of this file was worthless.
##
## **The bridge itself is assumed installed.** `tests/modules/destiny/
## test_destiny_fact_wiring_hook.gd` owns that question, and it owns it through the
## mounted composition root, because a bridge installed by a line in a test is not the
## same claim as one installed by the game. Everything below is "given a live bridge,
## does each production writer move its counter", which is the half that was broken
## even when a bridge existed.

## ## The census moved out, and this file is now the writer half of a pair
##
## `test_destiny_counter_mapping_census.gd` holds what used to be the third section
## below — "the mapping is authored, auditable, and matches the real tree" — because
## it reads the CONTENT TREE and the mapping TABLE rather than a counter, and a
## broken `.tres` fails there rather than here. Everything this file still asserts is
## about a production writer moving a counter or refusing to move one, which is the
## half the two earlier versions of this file got wrong.
##
## The fixtures and readers both halves drive live in
## `destiny_counter_wiring_support.gd`, so there is one answer to "what does the
## shipped fate tree declare" rather than two that could drift.
const Support := preload("res://tests/modules/destiny/destiny_counter_wiring_support.gd")

## The fact a duel writes. Authored in `what_the_rotation_cost.tres` (quest step 2)
## and read by `first_blood_duel.tres` (`counters = [&"duels_won", &"kills"]`).
const DUELS := &"duels_won"
## The 100th of the tide: `beast_tide_of_the_mortal_plains.tres` stage 2 records it
## and `one_hundredth_slain.tres` reads it. The only `event`-side beat wired to a
## fate, and the only counter the event module can reach.
const HUNDREDTH := &"hundredth_beast_slain"
## A counter the table deliberately does NOT wire to anything, so "no relationship
## was authored" is asserted rather than assumed.
const OATHS := &"oaths_sworn"

## The id both fixture catalogs' `t_` prefix reserves for a house that cannot collide
## with a shipped one.
const HOUSE := &"t_house"
## The fixture office `SectApi.promote` seats somebody into. Its name is derived from
## the house rather than written down twice, so a fixture rename is one edit.
const STEWARD := StringName("%s_steward" % String(HOUSE))

## Blows one duel may take before this suite calls it a stall, so a model that never
## decides a fight fails with a name instead of hanging. `tests/modules/combat/
## test_combat_facts.gd` states the same reason for the same constant; the bound is
## taken before the walk and never moved by it.
const BLOW_CAP := 200

## The seed the combat verbs take. A constant rather than a call to `randi`, because
## a suite whose result depends on the roll is a suite that fails for no reason a
## reader could find (ADR 0067).
const SEED := 20_260_904

## ## The bridge is installed per-test by [method setup], not assumed
##
## Every assertion below reads a fate counter, so every one of them is only true
## while a subscriber is listening. `DestinyApi.record` had zero callers in `src/`,
## so with nothing installed the whole file reads 0 — the "16 failures, all of
## them `got 0`" shape that reads like sixteen broken producers rather than one
## missing install.
##
## The install is asserted rather than assumed, because a `Callable` install can
## no-op without any error: `WorldFact.subscribe` refuses a duplicate, and a
## callable that resolved to nothing would be accepted just as quietly. The
## failure label names the WIRING instead of leaving sixteen zeros to be
## explained, which is the only thing this setup exists to do.
##
## ## Why this is a baseline DELTA and never an absolute count
##
## `WorldFact._subscribers` is a `static var`, so the slot is process-wide state
## this suite does not own: a sibling suite may legitimately hold a subscriber of
## its own while this file's `setup()` runs. Asserting `subscriber_count() == 0`
## would therefore be asserting that no other suite exists. So the count is a
## DELTA — "the slot holds exactly what it held when this test began, plus the
## one subscriber this suite installed" — which is the invariant a shared
## singleton can actually be observed under, and which fails on a real leak while
## staying quiet about a neighbour's honest subscriber.
var _baseline_subscribers: int = 0

## The support file's readers, bound on the LIVE instance in `setup()`.
##
## They are forwarders rather than direct calls, and bound rather than declared as
## `var f := func(): ...`, because `tests/run_tests.gd` builds a template instance
## and then COPIES its properties onto a second instance. A `Callable` created on
## the template stays bound to the template when it is copied, so a reader declared
## that way would answer out of a half-built object. Binding on the live instance
## inside `setup()` — which the runner calls before every `test_*` — is the one
## place where every read below is guaranteed to be bound.
var _hero_impl: Callable
var _fighter_impl: Callable
var _counter_impl: Callable
var _world_impl: Callable
var _clan_member_impl: Callable
var _sect_member_impl: Callable
var _install_sect_impl: Callable
var _fight_to_a_kill_impl: Callable
var _gate_impl: Callable
var _total_moved_impl: Callable


## Install the bridge for ONE test, and prove it is live.
##
## `tests/run_tests.gd` calls this before every `test_*` method, which is exactly
## the lifetime this process-wide state needs: present while the test drives the
## writers, gone the moment the test is over. A helper called from inside each
## test body would be one forgotten call away from leaking, and a leak here is
## silent — the counters keep moving for whichever suite runs next and that
## suite's failure names neither.
func setup() -> void:
	# Bound BEFORE the bridge goes in, so a fixture that could not be bound fails this
	# case by name instead of surfacing as a `null` fixture deep inside a test body.
	_bind_support()
	_baseline_subscribers = WorldFact.subscriber_count()
	DestinyProjection.subscribe_to_fact_ledger()
	assert_eq(
		WorldFact.has_subscriber(Callable(DestinyProjection, "on_fact_recorded")),
		true,
		(
			"the fact->counter bridge is LIVE for this test: every counter below is read "
			+ "through it, so a false here names the wiring rather than sixteen zeros"
		)
	)


## Leave the process exactly as this suite found it.
##
## Only the bridge THIS suite installed is removed, by identity — never
## `WorldFact.clear_subscribers()`, which is process-wide and would trade this
## suite's leak for whatever suite ran next.
##
## The assertion is a DELTA back to the count `setup()` recorded, not `0`, for
## the reason its own comment gives: a sibling suite may hold a subscriber here
## and that is not this suite's business. What this suite owes the process is
## exactly "as I found it", and a suite that broke that would show up as a
## baseline that no longer matches — which is a failure naming the leak, not a
## failure pointing at an innocent neighbour.
func teardown() -> void:
	DestinyProjection.unsubscribe_from_fact_ledger()
	assert_eq(
		WorldFact.subscriber_count(),
		_baseline_subscribers,
		(
			"the bridge is REMOVED again and the slot is back to the count this test found: "
			+ "the runner shares one process, and a subscriber left behind moves counters "
			+ "for every later suite"
		)
	)


## ## The shared fixtures and readers are ONE file, reached through a `const`
##
## `destiny_counter_wiring_support.gd` holds every fixture and reader below, because
## `test_destiny_counter_mapping_census.gd` drives the same readers and a second copy
## of "what does the shipped fate tree declare" is a second answer to a question both
## halves of this pair are making the same claim about. Nothing was lost in the move:
## each definition's docstring — which is where the reason it exists is written — went
## with it, and the names the cases already call did not change.


## Bind every forwarder above against THIS instance. The census binds its own seven
## readers out of the same support file, the same way, for the same reason.
func _bind_support() -> void:
	_hero_impl = Support._hero
	_fighter_impl = Support._fighter
	_counter_impl = Support._counter
	_world_impl = Support._world
	_clan_member_impl = Support._clan_member
	_sect_member_impl = Support._sect_member
	_install_sect_impl = Support._install_sect
	_fight_to_a_kill_impl = Support._fight_to_a_kill
	_gate_impl = Support._gate
	_total_moved_impl = Support._total_moved


## A hero with a destiny ledger attached, for the cases that assert on the NEGATIVE —
## a counter that must not move — where the fixture needs no resources.
func _hero() -> Actor:
	return _hero_impl.call()


## A body a duel can actually be fought over: pools attached, so a blow has something
## to spend and `defender_slain` is reachable. An `Actor.new` with no health pool
## cannot be damaged, so a duel could never be decided — the reason
## `tests/modules/combat/test_combat_facts.gd` builds the same thing.
func _fighter(id: StringName, physique: float = 10.0) -> Actor:
	return _fighter_impl.call(id, physique)


## The recorded value of one counter, read off the ledger [method DestinyApi.state]
## publishes rather than off a facade verb. `counter(actor, id)` was retired when
## the twelve-method cap forced a choice to pay for `events()`: it was the one
## public verb with no caller in `game/src` at all, so what it answered was already
## one dictionary key away from every one of its twenty read sites.
func _counter(actor: Actor, counter_id: StringName) -> int:
	return _counter_impl.call(actor, counter_id)


## The composition root's production chain, assembled the way
## `app/item_workbench_app.gd` does it: a fresh `BeatDirector` handed to a `WorldPulse`,
## which registers the sinks. Used only by the two world-tick cases; every other case
## here drives a module's own verb, because that is what the game does.
func _world(actor: Actor) -> WorldPulse:
	return _world_impl.call(actor)


## A clan member with a bloodline the fixture house admits, which is what
## `ClanHeir.register` reads before it writes the rank. The stat set is the one the
## `clan` module's own suite uses for a member, because admission is the only thing
## standing between this fixture and the fact.
func _clan_member() -> Actor:
	return _clan_member_impl.call()


## A sworn member of the fixture sect. `DestinyApi.attach` runs first because the
## counter a case reads is written into the same actor's ledger, and a `DestinyApi`
## that lazily attaches on first write would answer the same either way — attached
## explicitly so the fixture is complete before the act under test.
func _sect_member() -> Actor:
	return _sect_member_impl.call()


## The fixture sect: TWO PLAIN members, one seat with a standing floor, and one room
## so a second office exists. Installed rather than built per test, so a case that
## only cares about the fact does not have to know the board's shape.
func _install_sect() -> void:
	_install_sect_impl.call()


## Swing until one of the two is down, or until `BLOW_CAP` blows have been spent. The
## bound is a CONSTANT taken before the walk and the body never moves by it, which is
## the shape `tests/arch_rules/test_no_unbounded_wait.gd` accepts; returning `false`
## names the stall rather than looping forever.
func _fight_to_a_kill(actor: Actor, opponent: Actor) -> bool:
	return _fight_to_a_kill_impl.call(actor, opponent)


## The gate under test, authored exactly as a `.tres` would spell it. Data, never
## code — `DestinyGate` reads it and nothing here constructs a verdict by hand.
func _gate(counter_id: StringName, need: int) -> Dictionary:
	return _gate_impl.call(counter_id, need)


## The SUM of every counter this actor's ledger holds, across every authored id. Used
## by the creation case to assert that NOTHING moved — a per-id check would pass just
## as well on a hero who had earned nothing, which is the assertion it already makes.
func _total_moved(actor: Actor) -> int:
	return _total_moved_impl.call(actor)


# --- The writer exists, on the real path ------------------------------------


## THE gap, closed. A duel is won — through `CombatApi.hit`, the verb the game's
## attack resolver lands a blow through, which is where `CombatFacts.record_duel_won`
## is actually called — and the fate counter has moved. Before the hook this read 0
## forever, because `duels_won` is written by a module and the dispatch sat in a
## director this module never travels.
##
## ## Why a real fight and not `CombatFacts.record_duel_won(actor)` directly
##
## The `CombatFacts` verb IS the production writer, so calling it would be honest.
## It is not used here because a fight to a kill ALSO proves the producer is on the
## path a player's blow takes, and that the fact is written on the WINNER's ledger —
## two things a direct call to the fact verb would take on trust from the module's own
## docstring rather than measure. The direct call is covered in
## `test_destiny_fact_wiring_hook.gd`, so both halves are measured and neither is
## taken on faith.
func test_winning_a_duel_through_the_real_combat_verb_moves_the_duels_won_counter() -> void:
	var victor := _fighter(&"challenger")
	var ward := _fighter(&"ward")
	assert_eq(
		_counter(victor, DUELS),
		0,
		"a fresh fighter has moved no counter: nothing had ever written one"
	)

	assert_eq(_fight_to_a_kill(victor, ward), true, "the duel was decided by a killing blow")

	assert_eq(
		WorldFact.count(victor, DUELS),
		1,
		"the blow landed in the fact ledger — the write itself is not in doubt"
	)
	assert_eq(
		_counter(victor, DUELS),
		1,
		"and the SAME occurrence moved the fate counter, with no caller of DestinyApi.record"
	)
	assert_eq(
		_counter(ward, DUELS), 0, "the loser won nothing, so their counters stay where they were"
	)


## The second `combat` fact, and the SECOND shape of the same argument: it is
## recorded by a module verb from a path no director ever sees, and it maps to a
## DIFFERENT counter, so the two cannot be collapsed into one claim.
func test_sparing_an_opponent_through_the_real_combat_verb_moves_its_counter() -> void:
	var victor := _fighter(&"challenger")
	var ward := _fighter(&"ward")

	var spared := CombatApi.spare(victor, ward)

	assert_eq(bool(spared["ok"]), true, "the duel ended without a killing blow")
	assert_eq(
		WorldFact.count(victor, CombatFacts.FACT_THIRD_MAN_SPARED),
		1,
		"the world was told about the mercy, on the victor's ledger"
	)
	assert_eq(
		_counter(victor, &"enemies_spared"),
		1,
		"and the fate reading it moved, with no director on this path at all"
	)
	assert_eq(
		_counter(victor, DUELS),
		0,
		"a spared opponent is not a duel won: two facts, two counters, no collapsing"
	)


## `clan`'s producer, driven through the act that earns the fact rather than through
## the fact verb. This is the first module-owned fact whose counter is also authored
## into a shipped gate vocabulary by a quest — `the_station_you_held.tres` watches
## `household_heir_registered` — so the chain here is the full one: an act, a fact, a
## counter, and a counter a quest's own demand is written against.
func test_a_household_registration_through_the_real_clan_verb_moves_its_counter() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.open(HOUSE)])
	var actor := _clan_member()

	var registered := ClanHeir.register(actor)

	assert_eq(bool(registered["ok"]), true, "the registration landed")
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 1, "the world was told")
	assert_eq(
		_counter(actor, OATHS),
		1,
		"and the fate counting sworn houses moved by exactly one occurrence"
	)


## The other half of the hook's contract: a REFUSED write moves no counter. The
## registration is refused by asking for a house that publishes no heir rung at all,
## so the refusal is the module's own and not a hand-built claim.
func test_a_refused_registration_moves_no_counter() -> void:
	# A clan built WITHOUT the ladder, so `has_rank(HEIR_RANK)` fails and `register`
	# answers `no_heir_rank` before it writes anything. Authored through the fixture
	# catalog's own builder rather than by deleting a rung afterwards.
	var def := ClanFixtureCatalog.open(HOUSE)
	def.ranks = [&"outer", &"inner"]
	ClanFixtureCatalog.install([def])
	var actor := _clan_member()

	var refused := ClanHeir.register(actor)

	assert_eq(bool(refused["ok"]), false, "no heir rung was published, so it was refused")
	assert_eq(WorldFact.count(actor, ClanFacts.FACT_HEIR_REGISTERED), 0, "and no fact was written")
	assert_eq(_counter(actor, OATHS), 0, "so no fate counter moved either")


## `sect`'s producer, driven through `SectApi.promote` — a seating, not a fact call.
## `sect_post_held` maps to `oaths_sworn` rather than `oaths_broken` (see
## `COUNTER_FACTS`): an office that was actually held is a sworn house, and a counter
## that rose for both would answer a gate the player has not earned.
func test_seating_someone_through_the_real_sect_verb_moves_the_sworn_counter() -> void:
	_install_sect()
	var actor := _sect_member()
	SectApi.join(actor, HOUSE)
	SectApi.move_standing(actor, 100)

	var promoted := SectApi.promote(actor, STEWARD)

	assert_eq(bool(promoted["ok"]), true, "the promotion landed")
	# The seating is a TRANSITION and `SectApi.promote` says so before it records, so a
	# promotion that was really a re-confirmation writes nothing and would leave this
	# fact — and the counter below it — at 0. Asserted from the module's own read verb
	# rather than left to inference, because that transition guard is the one thing
	# standing between a real seating and a silent no-op on this path.
	assert_eq(
		SectState.position(SectApi.state(actor)),
		STEWARD,
		"and it was a real seating rather than a re-confirmation of the office already held"
	)
	assert_eq(WorldFact.count(actor, SectFacts.FACT_POST_HELD), 1, "a post was held, once")
	assert_eq(
		_counter(actor, OATHS),
		1,
		"and the counter a seated officer moves, with the ledger's own amount"
	)


## `oaths_discharged` is the one row whose producer takes an AMOUNT, so it is the one
## that proves the hook hands over the recorded delta rather than assuming one. Three
## lines cleared in one settlement is three oaths.
func test_serving_duty_through_the_real_sect_verb_moves_the_discharged_counter_by_its_amount(
) -> void:
	_install_sect()
	var actor := _sect_member()
	SectApi.join(actor, HOUSE)
	var ledger := SectApi.state(actor)
	# The obligation map is REBUILT rather than edited in place, and written AFTER
	# `attach` (which `_sect_member` already ran) — `attach` normalizes what it finds
	# and persists the normalized copy, so an edit made before it is re-derived from
	# the skeleton and the lines never open. The same two reasons
	# `tests/modules/sect/test_sect_facts.gd` gives, read from there rather than
	# re-derived here.
	ledger["obligation"] = {"instruction_%s": 1, "study_%s": 1, "drill_%s": 1}
	actor.set_module_data(SectState.MODULE_KEY, ledger)

	var served := SectDuty.serve(actor, 1)

	assert_eq(bool(served["ok"]), true, "a period of service landed")
	assert_eq(int(served["discharged"]), 3, "and three sworn terms were discharged in full")
	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		3,
		"the world was told three oaths were discharged"
	)
	assert_eq(
		_counter(actor, &"oaths_broken"),
		3,
		"so the fate counter moved by the RECORDED AMOUNT, not by one call"
	)


## The event module's own production write path, driven for real: the world's
## ambient news opens the beast tide on the pulse's own tick, and the ladder runs to
## the stage that records `hundredth_beast_slain`. No `EventApi.begin`, no
## hand-built beat — the composition root's `advance_periods` does it.
##
## This is the half the beat substrate could NEVER deliver: `EventBeatWriter` writes
## the fact ledger ITSELF and never reaches a director, so a dispatch living in
## `BeatDirector.offer` did not see this fact at all. That is why
## `DestinyProjection.on_beat_written` sat with zero callers while the fate reading
## this fact read 0 forever.
##
## **The hero is placed on the plain first**, because `EventApi.available` filters on
## where the actor is and the tide is authored at `mortal_plains`. Read off the
## authored def rather than restated, so a retuned location does not turn this into a
## failure about a string the test invented.
func test_the_ambient_world_tick_records_the_hundredth_and_moves_the_kill_counter() -> void:
	var catalog := EventCatalog.instance()
	var def := catalog.event_definition(&"beast_tide_of_the_mortal_plains")
	assert_ne(def, null, "the shipped tree still has the tide this suite drives")
	if def == null:
		return
	var actor := _hero()
	# Placed at the tide's authored location because `available()` filters on where the
	# actor stands, and attached so the event ledger is a real one rather than the bare
	# `location_id` row this test used to hand-write.
	EventApi.attach(actor)
	EventApi.set_location(actor, String(def.location_id))
	var pulse := _world(actor)

	# One period per authored ambient fact is where every one of them has been
	# reported, so the storm front that opens the tide has landed. Read rather than
	# restated, so this cannot go stale against the shipped world.
	for _step in WorldAmbient.ROSTER.size():
		pulse.advance_periods(1)

	# Ambient facts only make the tide AVAILABLE; its stages run once it opens, and
	# `WorldPulse` opens it for us the moment its trigger lands — which is why the
	# reason here is `already_active` and not `trigger`. Asserted rather than assumed:
	# a silent no-op would read as "the world never reached the hundredth" instead of
	# "the event was never opened", which is the distinction this test exists to draw.
	var opened := EventApi.begin(actor, &"beast_tide_of_the_mortal_plains", 0)
	assert_eq(
		String(opened.get("reason", "")),
		"already_active",
		(
			"the tide opened itself once its trigger fact landed, not by this call: %s"
			% JSON.stringify(opened)
		)
	)
	# `hundredth_beast_slain` sits on the tide's SECOND stage, and a stage whose
	# `requires` is unmet does not advance. Turn past every authored stage so the walk
	# is driven by the def rather than by a count that a retune would break.
	for _step in def.stages.size() + 2:
		pulse.advance_periods(1)

	assert_eq(
		WorldFact.count(actor, HUNDREDTH) > 0,
		true,
		(
			"the world reached the hundredth of the tide on its own: %s"
			% JSON.stringify(WorldFact.to_dict(actor))
		)
	)
	# The counter, not the boundary. `one_hundredth_slain`'s `kills` used to read 0
	# through this beat and the suite ASSERTED that, because a green test must never
	# assert a production defect as its expected state. It moves now, from the same
	# occurrence, because the hook is on the ledger's one writer — which is the writer
	# this beat uses.
	assert_eq(
		_counter(actor, &"kills"),
		WorldFact.count(actor, HUNDREDTH),
		(
			"the fate reading it ('one_hundredth_slain') moved WITH the authored event "
			+ "beat: the bridge is on the ledger's one writer, and this beat writes there"
		)
	)


## `CharacterCreationFlow` is the sixth writer and the only one in `app/` besides the
## director: it records `character_created` directly, after the grant it describes has
## landed. Nothing maps that fact to a counter today, and that is the CORRECT answer —
## a hero's creation is not an oath — so the assertion is the negative one, made on a
## real creation rather than on a hand-written ledger.
func test_creating_a_hero_records_its_fact_and_moves_no_counter() -> void:
	var flow := CharacterCreationFlow.new()
	var built := flow.build(&"the_one_who_stayed", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})

	assert_eq(bool(built["ok"]), true, "a hero was created: %s" % JSON.stringify(built))
	if not bool(built["ok"]):
		return
	var actor := built["actor"] as Actor
	assert_eq(
		WorldFact.count(actor, CharacterCreationFlow.FACT_ID),
		1,
		"the world's memory says a hero arrived"
	)
	assert_eq(
		DestinyProjection.counter_for_fact(CharacterCreationFlow.FACT_ID),
		&"",
		"and the mapping table maps it to nothing: a hero's creation is not an oath"
	)
	assert_eq(_total_moved(actor), 0, "so no fate counter moved at all on the creation path")


## A counter the fate tree does not read stays at 0 through a busy world. The busiest
## fact in the game is the elapsed period, offered once per whole period through the
## composition root's only offer point.
func test_a_beat_no_fate_reads_moves_no_counter() -> void:
	var actor := _hero()
	var pulse := _world(actor)

	pulse.offer(WorldPulse.PERIOD_FACT, 1, WorldPulse.PERIOD_SOURCE)

	assert_eq(WorldFact.count(actor, WorldPulse.PERIOD_FACT) > 0, true, "the fact landed")
	assert_eq(_counter(actor, DUELS), 0, "but a period is not a duel")


## `counter` is monotonic (ADR 0065), and monotonicity is the FACADE's rule rather
## than the bridge's — so the bridge is proved to route through it rather than to have
## grown a second write path with weaker guarantees. Three real duels this time, not
## three offers of a beat the game never offers.
func test_counters_only_rise_never_fall() -> void:
	var victor := _fighter(&"challenger")

	for round in 3:
		assert_eq(
			_fight_to_a_kill(victor, _fighter(StringName("ward_%d" % round))),
			true,
			"round %d was decided" % round
		)
	assert_eq(_counter(victor, DUELS), 3, "three decided duels, and no more")

	# A fourth duel is a fourth. Asserted on the write's OWN report as well as on the
	# ledger, so a bridge that moved the counter from somewhere other than this write
	# is not credited for it.
	var fourth := CombatFacts.record_duel_won(victor)
	assert_eq(bool(fourth.get("ok", false)), true, "the fourth write succeeded")
	assert_eq(_counter(victor, DUELS), 4, "a fourth duel is four")

	# A delta of zero cannot become a counter movement in either direction. The
	# ledger refuses a non-positive amount outright, and the hook fires only on
	# `ok: true`, so the refusal closes the door twice over. Asserted at the verb
	# rather than at `WorldPulse`, because the pulse's floor is `app/`'s rule and this
	# refusal is `core`'s.
	assert_eq(
		WorldFact.record(victor, DUELS, 0)["reason"],
		"non_positive",
		"a zero-amount write is refused by the ledger itself"
	)
	assert_eq(
		WorldFact.record(victor, DUELS, -3)["reason"], "non_positive", "and so is a negative one"
	)
	assert_eq(_counter(victor, DUELS), 4, "so nothing unwound a counter already earned")


## The bridge is a lookup and one facade call. It reads the ledger no further than
## `DestinyApi.record` does, answers for nobody gracefully, and refuses to lower
## anything — so a caller holding no actor gets 0 rather than a crash.
func test_the_bridge_is_total_over_null_actors_and_empty_ids() -> void:
	assert_eq(DestinyProjection.on_fact_recorded(null, DUELS, 3), 0, "no actor writes nothing")
	assert_eq(DestinyProjection.counter_for_fact(&""), &"", "no fact maps to no counter")
	assert_eq(DestinyProjection.counter_for_fact(&"not_a_fact"), &"", "and so does an unknown one")

	var actor := _hero()
	assert_eq(
		DestinyProjection.on_fact_recorded(actor, DUELS, 0),
		0,
		"a zero amount moves nothing, so the bridge never unwinds a counter"
	)
	assert_eq(_counter(actor, DUELS), 0, "and the counter is untouched")
	assert_eq(
		DestinyProjection.on_fact_recorded(actor, &"not_a_fact", 1),
		0,
		"an unmapped fact returns 0 rather than inventing a counter"
	)
	assert_eq(
		OATHS in DestinyProjection.counter_for_fact(&"character_created"),
		false,
		"character_created maps to nothing: a hero's creation is not an oath"
	)


# --- The gate opens on it ----------------------------------------------------


## The verb is not theatre any more. Two real duels and a `need: 3` gate refuse; the
## third opens it. Asserted at every rung so a bridge that moved the counter but not
## the gate would go red naming which half is broken.
##
## **The gate is asked of the fighter, not of a bystander.** A counter lives on the
## ledger of the body that did the deed, so a gate asked of a different actor reads 0
## of 3 forever — and a suite that did that would pass for the wrong reason.
func test_a_counter_gate_opens_at_need_and_refuses_below_it() -> void:
	var victor := _fighter(&"challenger")
	var gate := _gate(DUELS, 3)

	var before := DestinyApi.gate(victor, gate)
	assert_eq(bool(before["ok"]), false, "an unplayed hero is told no")
	assert_eq(String(before["reason"]), "unmet", "and the reason is 'not yet', not a refusal")
	assert_eq((before["unmet"] as Array)[0]["actual"], 0, "reporting 0 of 3")

	assert_eq(_fight_to_a_kill(victor, _fighter(&"ward_0")), true, "the first duel was decided")
	assert_eq(_fight_to_a_kill(victor, _fighter(&"ward_1")), true, "the second was decided")
	var below := DestinyApi.gate(victor, gate)
	assert_eq(bool(below["ok"]), false, "two duels still refuse a gate that needs three")
	assert_eq((below["unmet"] as Array)[0]["actual"], 2, "reporting 2 of 3")

	assert_eq(_fight_to_a_kill(victor, _fighter(&"ward_2")), true, "the third was decided")
	var above := DestinyApi.gate(victor, gate)
	assert_eq(bool(above["ok"]), true, "the third duel opens it")
	assert_eq(String(above["reason"]), "", "with nothing left to report")
	assert_eq(above["unmet"] as Array, [], "and no unmet entry")


## A counter cannot be opened by an occurrence that has not happened, and an
## occurrence moves it by exactly what the writer recorded. Driven through the one
## fact verb whose amount is authored by its caller, so the gate is asked after a real
## settlement rather than after a hand-built beat — and the negative rung comes first,
## because a gate that only ever sees a satisfied condition proves nothing.
func test_the_recorded_amount_is_the_delta_not_a_silent_one() -> void:
	_install_sect()
	var actor := _sect_member()
	SectApi.join(actor, HOUSE)
	var ledger := SectApi.state(actor)
	# One line, two periods, so the first service reduces it and discharges NOTHING
	# while the second clears it. `SectDuty` records on the crossing, not the payment.
	ledger["obligation"] = {"instruction_%s": 2}
	actor.set_module_data(SectState.MODULE_KEY, ledger)

	SectDuty.serve(actor, 1)

	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		0,
		"one period against a two-period line reduces it and discharges nothing"
	)
	assert_eq(
		bool(DestinyApi.gate(actor, _gate(&"oaths_broken", 1))["ok"]),
		false,
		"so a gate standing on one discharged oath stays shut"
	)

	SectDuty.serve(actor, 1)

	assert_eq(
		WorldFact.count(actor, SectFacts.FACT_OATHS_DISCHARGED),
		1,
		"the second period clears the line and records exactly one discharge"
	)
	assert_eq(
		bool(DestinyApi.gate(actor, _gate(&"oaths_broken", 1))["ok"]),
		true,
		"and the gate that needs one opens on the occurrence that earned it"
	)
	assert_eq(
		bool(DestinyApi.gate(actor, _gate(&"oaths_broken", 2))["ok"]),
		false,
		"while one that needs two does not: one oath is one oath"
	)


## A `counter` gate composed with another verb, which is how a `.tres` will actually
## author one. The composite reads the counter this bridge moved, and the fate half is
## earned through the facade so the composition is not the only thing under test.
func test_a_counter_gate_composes_with_the_other_verbs() -> void:
	var actor := _fighter(&"challenger")
	var gate := {
		"verb": &"all_of",
		"of":
		[
			{"verb": &"has_fate", "id": &"first_blood_duel"},
			{"verb": &"counter", "id": DUELS, "need": 2},
		],
	}

	assert_eq(bool(DestinyApi.gate(actor, gate)["ok"]), false, "an unearned fate refuses it")

	DestinyApi.earn_fate(actor, &"first_blood_duel", "combat")
	assert_eq(
		bool(DestinyApi.gate(actor, gate)["ok"]),
		false,
		"the fate alone does not open it: the counter is still 0"
	)

	assert_eq(_fight_to_a_kill(actor, _fighter(&"ward_0")), true, "the first duel was decided")
	assert_eq(
		bool(DestinyApi.gate(actor, gate)["ok"]),
		false,
		"one duel short it refuses, naming the counter it is still waiting on"
	)

	assert_eq(_fight_to_a_kill(actor, _fighter(&"ward_1")), true, "the second was decided")
	assert_eq(bool(DestinyApi.gate(actor, gate)["ok"]), true, "and the second duel opens it")
