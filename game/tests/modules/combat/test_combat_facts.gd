extends TestCase

## `duels_won` and `third_man_spared` — ADR 0137's two facts whose real owner is
## `combat`.
##
## `CombatDuel` counted DEFEATS only, so a win had no ledger anywhere in the program, and
## there was no surrender or spare outcome at all: `CombatDuelHit.resolve` could end a
## fight two ways and both of them were somebody dying. `what_the_rotation_cost.tres`
## asked for three duels the sect counted and a third man let walk, and neither was an
## instance of anything the module could do.
##
## ## What these hold
##
##   - a duel won is counted on the WINNER and only on a killing blow;
##   - a spare is a terminal state on the LOSER, and the next blow is REFUSED against
##     it, so mercy is not a note the following swing can undo;
##   - each fact is recorded once per occurrence, and reading the duel never records;
##   - neither id is named outside `combat_facts.gd` in `res://src` (ADR 0137).

const SEED := 20_260_903

## Blows one duel may take before this suite calls it a stall. A share is floored at
## `CombatDamage.MIN_SHARE`, so a working model reaches a kill well inside this; it names
## the condition that failed to terminate rather than bounding a walk that might not end.
const BLOW_CAP := 200


func _fighter(id: StringName, physique: float = 10.0) -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: physique, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	return actor


func _health(actor: Actor) -> float:
	var pool := actor.resource(&"health") as ResourcePool
	return 0.0 if pool == null else pool.current


## Swing until one of the two is down, or until `BLOW_CAP` blows have been spent. The
## bound is a CONSTANT taken before the walk and the body never moves it, which is the
## shape `tests/arch_rules/test_no_unbounded_wait.gd` accepts; returning `false` names
## the stall rather than looping forever.
func _fight_to_a_kill(actor: Actor, opponent: Actor) -> bool:
	for blow in BLOW_CAP:
		var result := CombatApi.hit(actor, opponent, SEED + blow)
		if String(result["reason"]) != "":
			return false
		if bool(result["defender_slain"]):
			return true
	return false


# --- duels_won -----------------------------------------------------------------


func test_the_blow_that_slays_records_a_duel_won_on_the_winner() -> void:
	var winner := _fighter(&"challenger")
	var loser := _fighter(&"ward")
	assert_eq(WorldFact.count(winner, CombatFacts.FACT_DUELS_WON), 0, "no duel fought yet")

	assert_eq(_fight_to_a_kill(winner, loser), true, "the duel was decided")

	assert_eq(WorldFact.count(loser, CombatFacts.FACT_DUELS_WON), 0, "the loser won nothing")
	assert_eq(
		WorldFact.count(winner, CombatFacts.FACT_DUELS_WON),
		1,
		"and the winner's ledger says exactly one duel was won"
	)
	assert_eq(int(CombatApi.duel(winner)["wins"]), 1, "and the duel record agrees with it")


func test_a_duel_that_is_still_being_fought_records_nothing() -> void:
	# A survivor's tenth exchange is not a tenth duel won. `duels_won` counts duels, not
	# blows, so a monotone ledger written per swing would be a number that grows with how
	# hard somebody fought rather than with what they achieved. One blow at a full pool is
	# the same non-lethal case `test_combat_duel_hit.gd` already pins.
	var winner := _fighter(&"challenger")
	var loser := _fighter(&"ward")

	var landed := CombatApi.hit(winner, loser, SEED)

	assert_eq(bool(landed["ok"]), true, "the blow landed")
	assert_eq(bool(landed["defender_slain"]), false, "and nobody died to it")
	assert_eq(
		WorldFact.count(winner, CombatFacts.FACT_DUELS_WON),
		0,
		"so no duel was won and nothing was recorded"
	)
	assert_eq(WorldFact.count(loser, CombatFacts.FACT_DUELS_WON), 0, "on either ledger")


func test_three_decided_duels_are_three_and_not_nineteen() -> void:
	var winner := _fighter(&"challenger")
	for round in 3:
		var loser := _fighter(StringName("ward_%d" % round))
		assert_eq(_fight_to_a_kill(winner, loser), true, "round %d was decided" % round)
	assert_eq(
		WorldFact.count(winner, CombatFacts.FACT_DUELS_WON),
		3,
		"three duels won, whatever the number of blows each took"
	)


func test_reading_the_duel_record_never_records_a_win() -> void:
	var winner := _fighter(&"challenger")
	assert_eq(_fight_to_a_kill(winner, _fighter(&"ward")), true, "one duel decided")
	var before := WorldFact.count(winner, CombatFacts.FACT_DUELS_WON)
	for cycle in 5:
		CombatApi.duel(winner)
		CombatApi.preview(winner)
	assert_eq(WorldFact.count(winner, CombatFacts.FACT_DUELS_WON), before, "reads record nothing")


func test_a_blow_that_lands_on_nobody_records_no_win() -> void:
	var winner := _fighter(&"challenger")
	var corpse := _fighter(&"ward")
	assert_eq(_fight_to_a_kill(winner, corpse), true, "the duel was decided")
	assert_eq(_health(corpse), 0.0, "and the ward is down")

	var refused := CombatApi.hit(winner, corpse, SEED + BLOW_CAP)

	assert_eq(String(refused["reason"]), "defender_slain", "a corpse spends nothing")
	assert_eq(
		WorldFact.count(winner, CombatFacts.FACT_DUELS_WON),
		1,
		"and a blow on a body already down is not a second duel won"
	)


# --- third_man_spared ----------------------------------------------------------


func test_sparing_an_opponent_records_it_on_the_one_who_showed_mercy() -> void:
	var victor := _fighter(&"challenger")
	var loser := _fighter(&"ward")

	var spared := CombatApi.spare(victor, loser)

	assert_eq(bool(spared["ok"]), true, "the duel ended without a killing blow")
	assert_eq(bool(spared["spared"]), true, "and it is published as a spare")
	assert_eq(
		WorldFact.count(victor, CombatFacts.FACT_THIRD_MAN_SPARED),
		1,
		"the world was told on the victor's ledger, once"
	)
	assert_eq(
		WorldFact.count(loser, CombatFacts.FACT_THIRD_MAN_SPARED),
		0,
		"mercy is not a thing that happened TO the loser"
	)


func test_a_spare_leaves_the_loser_on_their_feet_and_ends_the_duel() -> void:
	var victor := _fighter(&"challenger")
	var loser := _fighter(&"ward")
	var before := _health(loser)

	CombatApi.spare(victor, loser)

	assert_eq(_health(loser), before, "nobody's health moved: nothing was spent")
	var refused := CombatApi.hit(victor, loser, SEED)
	assert_eq(
		String(refused["reason"]),
		"defender_spared",
		"and the next blow is refused, because the duel is already over with them"
	)
	assert_eq(_health(loser), before, "so the refusal spent nothing either")


func test_sparing_the_same_opponent_twice_records_nothing_a_second_time() -> void:
	var victor := _fighter(&"challenger")
	var loser := _fighter(&"ward")
	CombatApi.spare(victor, loser)
	assert_eq(WorldFact.count(victor, CombatFacts.FACT_THIRD_MAN_SPARED), 1, "spared once")

	for repeat in 3:
		var refused := CombatApi.spare(victor, loser)
		assert_eq(String(refused["reason"]), "already_spared", "repeat %d" % repeat)
	assert_eq(
		WorldFact.count(victor, CombatFacts.FACT_THIRD_MAN_SPARED),
		1,
		"three repeats recorded nothing: the ledger is monotone"
	)


func test_a_defeat_is_an_ordinary_outcome_rather_than_one_that_can_be_spared() -> void:
	var victor := _fighter(&"challenger")
	var corpse := _fighter(&"ward")
	assert_eq(_fight_to_a_kill(victor, corpse), true, "the duel was decided")
	assert_eq(_health(corpse), 0.0, "and the ward is down")

	var refused := CombatApi.spare(victor, corpse)

	assert_eq(String(refused["reason"]), "loser_slain", "a corpse cannot be shown mercy")
	assert_eq(
		WorldFact.count(victor, CombatFacts.FACT_THIRD_MAN_SPARED), 0, "and nothing was recorded"
	)


func test_a_spare_of_yourself_or_of_nobody_is_refused_by_name() -> void:
	var actor := _fighter(&"challenger")
	assert_eq(
		String(CombatApi.spare(actor, actor)["reason"]), "same_actor", "a duel needs two parties"
	)
	assert_eq(
		String(CombatApi.spare(null, _fighter(&"ward"))["reason"]),
		"no_actor",
		"and a missing party is named rather than raised"
	)
	assert_eq(
		WorldFact.count(actor, CombatFacts.FACT_THIRD_MAN_SPARED), 0, "no refusal records anything"
	)


func test_a_spare_is_not_a_duel_won_and_a_kill_is_not_a_spare() -> void:
	# Two different endings of the same fight, and two different facts. Collapsing them
	# would make the counter mean "a fight ended" instead of "a fight was won".
	var victor := _fighter(&"challenger")
	var spared := _fighter(&"ward")
	var killed := _fighter(&"ward")

	CombatApi.spare(victor, spared)
	assert_eq(_fight_to_a_kill(victor, killed), true, "and a second duel was decided")

	assert_eq(WorldFact.count(victor, CombatFacts.FACT_DUELS_WON), 1, "one duel WON")
	assert_eq(
		WorldFact.count(victor, CombatFacts.FACT_THIRD_MAN_SPARED),
		1,
		"one opponent SPARED, and the sparing added no win"
	)


func test_reading_the_spare_state_never_records_it() -> void:
	var victor := _fighter(&"challenger")
	var loser := _fighter(&"ward")
	CombatApi.spare(victor, loser)
	var before := WorldFact.count(victor, CombatFacts.FACT_THIRD_MAN_SPARED)
	for cycle in 5:
		CombatApi.duel(victor)
		CombatApi.duel(loser)
		CombatApi.preview(victor)
	assert_eq(
		WorldFact.count(victor, CombatFacts.FACT_THIRD_MAN_SPARED), before, "reads record nothing"
	)


# --- ADR 0137's refusal, held as an assertion ---------------------------------


func test_no_duel_fact_is_named_outside_the_one_fact_file_or_the_fate_mapping() -> void:
	# These ids are the ACT's. A world roster that reported them would be the quest's
	# demand echoed back, and would falsify
	# `tests/app/test_world_ambient_facts.gd`'s
	# `test_a_fact_the_world_never_reports_is_still_outstanding`.
	#
	# `modules/destiny/destiny_projection.gd`'s `COUNTER_FACTS` also names them, and that
	# table LOOKS like a producer and is not one (ADR 0137), so the expected set is exactly
	# the fact file and that mapping — and only the fact file reaches the writer.
	for fact in [CombatFacts.FACT_DUELS_WON, CombatFacts.FACT_THIRD_MAN_SPARED]:
		var naming: Array[String] = []
		var reaching := 0
		for path in _gdscript_files("res://src"):
			if not _names_in_code(path, fact):
				continue
			naming.append(path)
			if FileAccess.get_file_as_string(path).contains("WorldFact.record"):
				reaching += 1
		naming.sort()
		assert_eq(reaching, 1, "exactly one file writes '%s'" % String(fact))
		assert_eq(
			naming,
			[
				"res://src/modules/combat/combat_facts.gd",
				"res://src/modules/destiny/destiny_projection.gd"
			],
			"'%s' is named by its producer and by the fate mapping, and nowhere else" % String(fact)
		)
	assert_eq(
		_named_in_code("res://src/app"),
		0,
		"and no file in app/ names a duel fact, so nothing ambient can produce one"
	)
	assert_eq(_named_in_event_content(), 0, "and no authored event beat names one either")
	assert_eq(
		_record_calls("res://src/modules/combat/combat_facts.gd", "FACT_DUELS_WON"),
		1,
		(
			"the producer hands its own same-file consts to that writer, once each, which is "
			+ "the only spelling `tools gate_reach.py` resolves"
		)
	)
	assert_eq(
		_record_calls("res://src/modules/combat/combat_facts.gd", "FACT_THIRD_MAN_SPARED"),
		1,
		"and so does the spare"
	)


## Whether `path` names `id` in a line of CODE. One line at a time with the comment half
## stripped, the way every other rule in `tests/arch_rules` reads source, so a file that
## merely DISCUSSES the id is not counted as naming it.
func _names_in_code(path: String, id: StringName) -> bool:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.split("#")[0].contains(String(id)):
			return true
	return false


## How many lines of `path` hand `const_name` to the ledger's writer as its id argument.
## Zero means the const is declared beside the writer without reaching it, which would be
## a fact id the census can read and nothing produces.
func _record_calls(path: String, const_name: String) -> int:
	var hits := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.split("#")[0].contains("WorldFact.record(actor, %s" % const_name):
			hits += 1
	return hits


## How many files under `root` name either id in a line of CODE.
func _named_in_code(root: String) -> int:
	var hits := 0
	for path in _gdscript_files(root):
		for fact in [CombatFacts.FACT_DUELS_WON, CombatFacts.FACT_THIRD_MAN_SPARED]:
			if _names_in_code(path, fact):
				hits += 1
	return hits


## How many authored event `.tres` name either id. `res://data/event` is where an ambient
## producer would be written, because `EventStageDef.on_enter` is a beat list and a beat
## list is content — and it is deliberately NOT the whole of `res://data`, because the
## quest step that DEMANDS the fact names it too and a demand is not a producer.
func _named_in_event_content() -> int:
	var hits := 0
	for path in _content_files("res://data/event"):
		var text := FileAccess.get_file_as_string(path)
		for fact in [CombatFacts.FACT_DUELS_WON, CombatFacts.FACT_THIRD_MAN_SPARED]:
			if text.contains(String(fact)):
				hits += 1
	return hits


## Every `.gd` under `root`, recursively. A `while` over `DirAccess` is the one shape
## `tests/arch_rules/test_no_unbounded_wait.gd` accepts as terminating, and a `for` over
## the collected list is used everywhere else — the same walk that rule itself performs.
func _gdscript_files(root: String) -> Array[String]:
	return _files(root, ".gd")


## Every authored `.tres` under `root`, recursively. Same walk, one extension.
func _content_files(root: String) -> Array[String]:
	return _files(root, ".tres")


func _files(root: String, suffix: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_files(path, suffix))
			elif entry.ends_with(suffix):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
