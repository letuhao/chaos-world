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

## The three authored rows with no producer anywhere in `game/src` and no authored
## event beat. Named here so the census below cannot quietly grow a fourth while
## still passing, and so the failure text says which rows are dead rather than only
## how many.
const UNPRODUCED := [&"bound_name_called", &"mountain_circled_once", &"vigil_broken"]


## The gate under test, authored exactly as a `.tres` would spell it. Data, never
## code — `DestinyGate` reads it and nothing here constructs a verdict by hand.
func _gate(counter_id: StringName, need: int) -> Dictionary:
	return {"verb": &"counter", "id": counter_id, "need": need}


func _hero() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	return actor


## A body a duel can actually be fought over: pools attached, so a blow has something
## to spend and `defender_slain` is reachable. An `Actor.new` with no health pool
## cannot be damaged, so a duel could never be decided — the reason
## `tests/modules/combat/test_combat_facts.gd` builds the same thing.
func _fighter(id: StringName, physique: float = 10.0) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: physique, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	DestinyApi.attach(actor)
	return actor


## The counters the shipped fate tree declares, keyed by id. Each fate that declares
## one keeps its OWN key rather than the last writer's, so a value here says which
## `.tres` asked for it.
func _declared_counters() -> Dictionary:
	var declared: Dictionary = {}
	for fate_id in FateCatalog.instance().fate_ids():
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		for counter_id in def.counters:
			declared[String(counter_id)] = String(fate_id)
	return declared


## Every counter id the bridge can move, sorted, read from the table itself rather
## than restated — a copy here would let a deleted row stay green.
func _wired_ids() -> Array[String]:
	var out: Array[String] = []
	for row in DestinyProjection.COUNTER_FACTS:
		out.append(String((row as Dictionary).get("counter", "")))
	out.sort()
	return out


## Every fact id the SHIPPED content tree authors as a beat: an event's opening beats
## and every stage's `on_enter` rows, plus every quest step's watched fact.
##
## A quest step is a DEMAND rather than a producer and is included deliberately: a
## fact named by a quest and produced by nothing is the shape "a gate that can never
## open" takes, and this census is about whether the shipped tree can record it at
## all. Read from the real catalogs rather than from this file's memory of them.
func _authored_fact_ids() -> Dictionary:
	var known: Dictionary = {}
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		for fact in def.watched_facts():
			known[String(fact)] = true
	for event_id in EventCatalog.instance().event_ids():
		var event_def := EventCatalog.instance().event_definition(event_id)
		if event_def == null:
			continue
		for beat in event_def.opening_beats():
			known[String(beat.get("fact", ""))] = true
		for stage in event_def.stages:
			if stage == null:
				continue
			for beat in stage.on_enter:
				known[String(beat.get("fact", ""))] = true
	known[String(WorldPulse.PERIOD_FACT)] = true
	return known


## The module-owned fact producers ADR 0137 added, as `{"fact": StringName,
## "writer": String}`. Every id read off the owning module's own `const`, so a rename
## in a module changes this answer without a line here changing — which is the
## difference between a census and a claim.
##
## **This list IS the answer to "which writer makes this fact happen".** It is
## asserted in full against the shipped writer set below, so a module that gains a
## producer cannot be invisible to this suite.
func _module_owned_facts() -> Array[Dictionary]:
	return [
		{"fact": CombatFacts.FACT_DUELS_WON, "writer": "combat/CombatFacts"},
		{"fact": CombatFacts.FACT_THIRD_MAN_SPARED, "writer": "combat/CombatFacts"},
		{"fact": ClanFacts.FACT_HEIR_REGISTERED, "writer": "clan/ClanFacts"},
		{"fact": SectFacts.FACT_POST_HELD, "writer": "sect/SectFacts"},
		{"fact": SectFacts.FACT_OATHS_DISCHARGED, "writer": "sect/SectFacts"},
		{"fact": CharacterCreationFlow.FACT_ID, "writer": "app/CharacterCreationFlow"},
	]


## The recorded value of one counter, read off the ledger [method DestinyApi.state]
## publishes rather than off a facade verb. `counter(actor, id)` was retired when
## the twelve-method cap forced a choice to pay for `events()`: it was the one
## public verb with no caller in `game/src` at all, so what it answered was already
## one dictionary key away from every one of its twenty read sites.
func _counter(actor: Actor, counter_id: StringName) -> int:
	var ledger := DestinyApi.state(actor)
	return int((ledger["counters"] as Dictionary).get(String(counter_id), 0))


## The composition root's production chain, assembled the way
## `app/item_workbench_app.gd` does it: a fresh `BeatDirector` handed to a `WorldPulse`,
## which registers the sinks. Used only by the two world-tick cases; every other case
## here drives a module's own verb, because that is what the game does.
func _world(actor: Actor) -> WorldPulse:
	return WorldPulse.new(actor, BeatDirector.new())


## A clan member with a bloodline the fixture house admits, which is what
## `ClanHeir.register` reads before it writes the rank. The stat set is the one the
## `clan` module's own suite uses for a member, because admission is the only thing
## standing between this fixture and the fact.
func _clan_member() -> Actor:
	var actor := (
		Actor
		. new(
			&"member",
			{
				Stat.PHYSIQUE: 10.0,
				Stat.WILL: 5.0,
				Stat.SPIRIT: 4.0,
				Stat.AGILITY: 6.0,
				Stat.COMPREHENSION: 3.0,
				Stat.APTITUDE: 3.0,
			}
		)
	)
	DestinyApi.attach(actor)
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, &"hearthborn", 0.5)
	ClanApi.join(actor, HOUSE)
	return actor


## A sworn member of the fixture sect. `DestinyApi.attach` runs first because the
## counter this suite reads is written into the same actor's ledger, and a
## `DestinyApi` that lazily attaches on first write would answer the same either way
## — attached explicitly so the fixture is complete before the act under test.
func _sect_member() -> Actor:
	var actor := Actor.new(&"keeper", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	SectApi.attach(actor)
	return actor


## The fixture sect: a plain member, one seat with a standing floor, and one room so
## a second office exists. Installed rather than built per test, so a case that only
## cares about the fact does not have to know the board's shape.
func _install_sect() -> void:
	(
		SectFixtureCatalog
		. install(
			[
				(
					SectFixtureCatalog
					. sect(
						HOUSE,
						[
							SectFixtureCatalog.bare_position(&"t_member"),
							SectFixtureCatalog.seat(STEWARD, 60),
							SectFixtureCatalog.wide_position(&"t_archivist", 2, 40),
						],
						100,
						0
					)
				)
			]
		)
	)


## Swing until one of the two is down, or until `BLOW_CAP` blows have been spent. The
## bound is a CONSTANT taken before the walk and the body never moves by it, which is
## the shape `tests/arch_rules/test_no_unbounded_wait.gd` accepts; returning `false`
## names the stall rather than looping forever.
func _fight_to_a_kill(actor: Actor, opponent: Actor) -> bool:
	for blow in BLOW_CAP:
		var result := CombatApi.hit(actor, opponent, SEED + blow)
		if String(result["reason"]) != "":
			return false
		if bool(result["defender_slain"]):
			return true
	return false


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


# --- The mapping is authored, auditable, and matches the real tree -----------


## The table is an EXPLICIT map, never a fuzzy name match. Every row is checked
## against the real shipped `FateDef` that reads it, over the real catalog rather
## than a copy, so deleting a row here cannot quietly retire a fate.
##
## **This asserts the coverage that is TRUE, not coverage that is hoped for.** No
## shipped `.tres` uses the `counter` gate verb, so zero counters need a writer
## today — the census, not a silent pass and not a failing assertion. The moment
## somebody authors `{verb: &"counter", ...}`, this goes RED naming the ids with no
## writer, which is the check the gap needed all along: a fate's `counters` entry
## cannot quietly become a promise nothing keeps.
##
## Widened to assert total coverage once every authored counter has a producer.
func test_every_wired_counter_is_declared_by_a_shipped_fate() -> void:
	var declared := _declared_counters()
	assert_eq(
		declared.is_empty(),
		false,
		"the shipped fate tree declares counters; this suite must read it, not assume"
	)
	var unwired: Array[String] = []
	for counter_id in declared.keys():
		# `counter_for_fact` answers FACT -> counter, so asking it with a COUNTER id
		# is a category error that happens to be truthy for `duels_won` alone (the one
		# id that is spelled the same on both sides). Read the table directly instead,
		# so an id is "wired" only because a row really moves it.
		if not _wired_ids().has(String(counter_id)):
			unwired.append(String(counter_id))
	unwired.sort()
	var wired := _wired_ids()
	var gates := _authored_counter_gate_ids()
	if gates.is_empty():
		# The census, stated rather than assumed: nothing in content stands on a
		# counter yet, so an unwired id is not yet a broken promise. Both halves are
		# asserted so the suite can never go green by being wrong about either.
		assert_eq(gates, [], "no shipped .tres anywhere in the content tree gates on `counter`")
		assert_eq(
			unwired.size() + wired.size(),
			declared.size(),
			(
				(
					"%d of %d FateDef.counters are wired (%s); the %d unwired are reported "
					% [wired.size(), declared.size(), str(wired), unwired.size()]
				)
				+ "here because nothing gates on them yet"
			)
		)
		return
	var ungated: Array[String] = []
	for counter_id in unwired:
		if not gates.has(counter_id):
			ungated.append(counter_id)
	assert_eq(
		ungated,
		[],
		(
			"a shipped .tres gates on `counter`, so every FateDef.counters id it could "
			+ "gate on needs a fact that moves it"
		)
	)


## Every fact on the left is a fact the shipped tree can actually record: an authored
## event beat, a fact a quest's own demand names, a composition-root beat, or one of
## the five module-owned producers ADR 0137 added.
##
## ## What this claims about the three dead rows
##
## It claims the HONEST thing, which is a census rather than a flat pass: the shipped
## content tree authors no beat for `vigil_broken`, `bound_name_called` or
## `mountain_circled_once`, and nothing in `game/src` produces them either. Those
## three stay dead and this suite says so BY NAME, because a test that went green
## while they were dead — and listed them as expected — is the inverted proof this
## file was rewritten to delete.
##
## Inventing a producer for them is NOT this file's work and would be wrong: the
## quests that ask for them are other modules' content, and an authored counter only
## a test could reach is the exact shape DEF-0105/DEF-0106 record.
func test_every_wired_fact_is_authored_content_or_a_named_module_producer() -> void:
	var reachable := _authored_fact_ids()
	for entry in _module_owned_facts():
		reachable[String((entry as Dictionary).get("fact", ""))] = true

	var orphans: Array[String] = []
	for row in DestinyProjection.COUNTER_FACTS:
		var fact := String((row as Dictionary).get("fact", ""))
		if not reachable.has(fact):
			orphans.append(fact)
	orphans.sort()
	assert_eq(
		orphans,
		[],
		(
			(
				"these rows name facts nothing in the shipped tree can record: %s. Authoring "
				% str(orphans)
			)
			+ "their producers is other modules' work (DEF-0105/DEF-0106) and a test must not "
			+ "stand in for it — add the producer and this goes green by itself."
		)
	)


## The dead rows are named HERE, exactly, so the census above cannot quietly grow a
## fourth while still passing. If this list ever shrinks, the assertion that shrank it
## says why; if it is deleted wholesale, the next author inherits a suite that claims
## full coverage and does not have it.
func test_the_unproduced_rows_are_named_so_the_census_cannot_grow_quietly() -> void:
	var unreachable := _unproduced_facts()
	unreachable.sort()

	assert_eq(
		unreachable,
		[
			String(UNPRODUCED[0]),
			String(UNPRODUCED[1]),
			String(UNPRODUCED[2]),
		],
		(
			(
				"exactly three authored rows have no producer in `game/src` and no authored "
				+ (
					"beat: %s. They read 0 forever and stay that way until the owning module "
					% str(unreachable)
				)
			)
			+ "writes them (DEF-0105/DEF-0106). When one lands, delete it from UNPRODUCED in "
			+ "the same change that adds the producer — this suite is a census, not a wish."
		)
	)


## Every id this suite treats as module-owned really is named in the shipped module
## that claims to produce it, in a line of CODE. Read from the files rather than
## restated, because the two have already drifted once — `what_the_rotation_cost.tres`
## once watched `vigil_broken` and now watches `sect_post_held`, and a suite that
## believed the docstring rather than the tree would still have been green.
func test_the_module_owned_producer_list_is_read_from_the_modules_that_claim_it() -> void:
	var expected := {
		"res://src/modules/combat/combat_facts.gd":
		[String(CombatFacts.FACT_DUELS_WON), String(CombatFacts.FACT_THIRD_MAN_SPARED)],
		"res://src/modules/clan/clan_facts.gd": [String(ClanFacts.FACT_HEIR_REGISTERED)],
		"res://src/modules/sect/sect_facts.gd":
		[String(SectFacts.FACT_POST_HELD), String(SectFacts.FACT_OATHS_DISCHARGED)],
		"res://src/app/character_creation_flow.gd": [String(CharacterCreationFlow.FACT_ID)]
	}
	var listed: Array[String] = []
	for entry in _module_owned_facts():
		listed.append(String((entry as Dictionary).get("writer", "")))
	listed.sort()

	for path in expected.keys():
		var body := FileAccess.get_file_as_string(path)
		assert_ne(body, "", "%s ships, so this is not a silent skip" % path)
		for fact in expected[path] as Array:
			assert_eq(
				_names_in_code(body, String(fact)),
				true,
				(
					"%s names '%s' in a line of code, so the census is reading a real producer"
					% [path, String(fact)]
				)
			)
	assert_eq(
		listed,
		[
			"app/CharacterCreationFlow",
			"clan/ClanFacts",
			"combat/CombatFacts",
			"combat/CombatFacts",
			"sect/SectFacts",
			"sect/SectFacts"
		],
		"and every module-owned producer is listed here, so a new one cannot be invisible"
	)


## One fact moves ONE counter, and every row says both names. A `counter` value that
## no fate reads would be a number nothing gates on; a second counter on one fact
## would make the first one a sum of unrelated deeds.
func test_every_row_names_a_fact_and_exactly_one_counter() -> void:
	var facts: Dictionary = {}
	for row in DestinyProjection.COUNTER_FACTS:
		var entry := row as Dictionary
		var fact := String(entry.get("fact", ""))
		var counter_id := StringName(entry.get("counter", &""))
		assert_ne(fact, "", "a mapping row names the fact it answers to")
		assert_ne(String(counter_id), "", "'%s' names the counter it moves" % fact)
		assert_eq(facts.has(fact), false, "'%s' is mapped exactly once" % fact)
		facts[fact] = String(counter_id)


## Every counter a shipped `FateDef` names is one the bridge can move. The converse
## census is `test_every_wired_counter_is_declared_by_a_shipped_fate`; this direction
## is the one that catches a typo in the TABLE, which would otherwise move a number
## nothing gates on.
func test_every_wired_counter_is_one_the_shipped_tree_declares() -> void:
	var declared := _declared_counters()
	var unknown: Array[String] = []
	for counter_id in _wired_ids():
		if not declared.has(counter_id):
			unknown.append(counter_id)
	assert_eq(unknown, [], "no row moves a counter no fate reads")


## Every counter id any SHIPPED `.tres` anywhere in the content tree names in a
## `counter` gate requirement — walked from RAW FILE TEXT rather than from a catalog,
## because no catalog exposes every requirement field and a scan that missed a type
## would under-report the census and pass it for the wrong reason.
##
## Empty today, and **that is exactly the fact the census turns on**: the `counter`
## verb is unused in content, so no authored gate is yet standing on a counter that
## cannot move. Read live, so it becomes non-empty by itself the moment somebody
## authors one — which is what turns DEF-0121 from a comment into a failure.
func _authored_counter_gate_ids() -> Array[String]:
	var found: Array[String] = []
	for path in _data_files():
		var body := FileAccess.get_file_as_string(path)
		var cursor := 0
		while true:
			cursor = body.find('"verb": &"counter"', cursor)
			if cursor < 0:
				break
			cursor += 1
			var id_at := body.find('"id": &"', cursor)
			if id_at < 0 or id_at - cursor > 200:
				continue
			var quote := id_at + 9
			found.append(body.substr(quote, body.find('"', quote) - quote))
	found.sort()
	return found


## Every `.tres` in the shipped content tree, so the census above is over the whole
## corpus and not over one module's idea of it.
func _data_files() -> Array[String]:
	var out: Array[String] = []
	_walk_data("res://data", out)
	out.sort()
	return out


func _walk_data(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_walk_data(full, out)
		elif name.ends_with(".tres"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


## Every mapped fact the shipped tree can NEITHER author as a beat NOR read out of a
## module producer, sorted. The list [constant UNPRODUCED] claims to BE this, and the
## two are compared to each other rather than to a hard-coded literal — so the claim
## lives in one place and the census is computed.
func _unproduced_facts() -> Array[String]:
	var reachable := _authored_fact_ids()
	for entry in _module_owned_facts():
		reachable[String((entry as Dictionary).get("fact", ""))] = true
	var out: Array[String] = []
	for row in DestinyProjection.COUNTER_FACTS:
		var fact := String((row as Dictionary).get("fact", ""))
		if not reachable.has(fact):
			out.append(fact)
	out.sort()
	return out


## Whether `body` names `id` in a line of CODE. One line at a time with the comment
## half stripped, the way every rule in `tests/arch_rules` reads source, so a file
## that merely DISCUSSES an id is not counted as naming it.
func _names_in_code(body: String, id: String) -> bool:
	for line in body.split("\n"):
		if line.split("#")[0].contains(id):
			return true
	return false


## The SUM of every counter this actor's ledger holds, across every authored id. Used
## by the creation case to assert that NOTHING moved — a per-id check would pass just
## as well on a hero who had earned nothing, which is the assertion it already makes.
func _total_moved(actor: Actor) -> int:
	var total := 0
	var counters := DestinyApi.state(actor)["counters"] as Dictionary
	for counter_id in counters.keys():
		total += int(counters[counter_id])
	return total
