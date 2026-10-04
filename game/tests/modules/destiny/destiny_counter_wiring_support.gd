extends RefCounted

## The fixtures and readers `test_destiny_counter_production_wiring.gd` and
## `test_destiny_counter_mapping_census.gd` both drive, in one place because a
## copy in either suite would be a second answer to a question both suites are
## making the same claim about.
##
## **NOT a suite, and deliberately not named `test_*`.** `tests/run_tests.gd`
## discovers `res://tests/**/test_*.gd` and instantiates whatever it finds, so a
## shared file under that prefix would be run as a suite with no tests in it.
## `class_name` is left off for the same reason the sibling
## `destiny_fixture_catalog.gd` leaves it off: nothing outside these two suites
## should be able to reach the fixtures, and `preload` is the narrow door.
##
## Nothing here installs or tears anything down. `WorldFact._subscribers` is a
## `static var` and the ledger the counters live on is per-actor, so the lifetime
## that has to be respected belongs to the SUITE, not to these helpers: each of the
## two suites installs the bridge in its own `setup()` and removes it in its own
## `teardown()`, both by BASELINE DELTA rather than by absolute count. That is why
## the baseline lives on the suite as a member var and not here.

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

## Blows one duel may take before a caller calls it a stall, so a model that never
## decides a fight fails with a name instead of hanging. `tests/modules/combat/
## test_combat_facts.gd` states the same reason for the same constant; the bound is
## taken before the walk and never moved by it.
const BLOW_CAP := 200

## The seed the combat verbs take. A constant rather than a call to `randi`, because
## a suite whose result depends on the roll is a suite that fails for no reason a
## reader could find (ADR 0067).
const SEED := 20_260_904

## The three authored rows with no producer anywhere in `game/src` and no authored
## event beat. Named here so the census in `test_destiny_counter_mapping_census.gd`
## cannot quietly grow a fourth while still passing, and so the failure text says
## which rows are dead rather than only how many.
const UNPRODUCED := [&"bound_name_called", &"mountain_circled_once", &"vigil_broken"]


## A hero with a destiny ledger attached, for the cases that assert on the NEGATIVE —
## a counter that must not move — where the fixture needs no resources.
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
## which registers the sinks. Used only by the world-tick cases; every other case
## drives a module's own verb, because that is what the game does.
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
## counter a case reads is written into the same actor's ledger, and a
## `DestinyApi` that lazily attaches on first write would answer the same either way
## — attached explicitly so the fixture is complete before the act under test.
func _sect_member() -> Actor:
	var actor := Actor.new(&"keeper", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	SectApi.attach(actor)
	return actor


## The fixture sect: TWO PLAIN members, one seat with a standing floor, and one room
## so a second office exists. Installed rather than built per test, so a case that
## only cares about the fact does not have to know the board's shape.
##
## **Two plain positions, and that is load-bearing rather than decoration.**
## `SectApi.join` puts its new member in `def.default_position`, so with only ONE
## plain position every member arrived ALREADY holding it. `SectApi.promote`
## records `sect_post_held` only when it actually SEATS somebody — `seated :=
## SectState.position(read) != office.id`, its own comment naming the rule as "an
## office being HELD is a transition" — so a single-position board made every
## promotion into the steward's seat a no-op re-confirmation, no fact was written,
## and the counter read 0 forever. The transition guard is correct code; the
## fixture was what made it unreachable. A second plain position is what makes the
## seating a real transition, and neither position is an office the cases care
## about, which is why both are plain.
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
							SectFixtureCatalog.bare_position(&"t_junior"),
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


## The gate under test, authored exactly as a `.tres` would spell it. Data, never
## code — `DestinyGate` reads it and nothing here constructs a verdict by hand.
func _gate(counter_id: StringName, need: int) -> Dictionary:
	return {"verb": &"counter", "id": counter_id, "need": need}


## The SUM of every counter this actor's ledger holds, across every authored id. Used
## by the creation case to assert that NOTHING moved — a per-id check would pass just
## as well on a hero who had earned nothing, which is the assertion it already makes.
func _total_moved(actor: Actor) -> int:
	var total := 0
	var counters := DestinyApi.state(actor)["counters"] as Dictionary
	for counter_id in counters.keys():
		total += int(counters[counter_id])
	return total


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
## open" takes, and the census is about whether the shipped tree can record it at
## all. Read from the real catalogs rather than from a file's memory of them.
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
## producer cannot be invisible to the census.
func _module_owned_facts() -> Array[Dictionary]:
	return [
		{"fact": CombatFacts.FACT_DUELS_WON, "writer": "combat/CombatFacts"},
		{"fact": CombatFacts.FACT_THIRD_MAN_SPARED, "writer": "combat/CombatFacts"},
		{"fact": ClanFacts.FACT_HEIR_REGISTERED, "writer": "clan/ClanFacts"},
		{"fact": SectFacts.FACT_POST_HELD, "writer": "sect/SectFacts"},
		{"fact": SectFacts.FACT_OATHS_DISCHARGED, "writer": "sect/SectFacts"},
		{"fact": CharacterCreationFlow.FACT_ID, "writer": "app/CharacterCreationFlow"},
	]


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


## Every `.tres` in the shipped content tree, so the census is over the whole
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


## Whether `body` names `id` in a line of CODE. One line at a time with the comment
## half stripped, the way every rule in `tests/arch_rules` reads source, so a file
## that merely DISCUSSES an id is not counted as naming it.
func _names_in_code(body: String, id: String) -> bool:
	for line in body.split("\n"):
		if line.split("#")[0].contains(id):
			return true
	return false
