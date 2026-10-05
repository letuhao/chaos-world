extends TestCase

## ADR 0061: the tribulation MECHANISM, checked by name and by behaviour.
##
## `test_tribulation_fight.gd` proves the fight, `test_tribulation_once.gd` proves
## the award and the entry point, and `test_tribulation_entry.gd` proves the gate per
## path. This file proves the two things they cannot: that the names the ADR and the
## reviewers use still EXIST (a mechanism silently reverted leaves a suite that stops
## collecting, which reads as a pass), and the three behaviours that only the
## production path exercises.
##
## A grep is cheap and insufficient on its own — a name can exist while the behaviour
## behind it is wrong — so every name below is paired with a behavioural claim in the
## same file or in the suites above it.

const TRIBULATION_SRC := "res://src/core/tribulation.gd"
const TRIBULATION_ENDURANCE_SRC := "res://src/core/tribulation_endurance.gd"
const BREAKTHROUGH_SRC := "res://src/core/breakthrough.gd"
const CONDITION_SRC := "res://src/core/tribulation_condition.gd"
const FIGHT_SRC := "res://src/modules/heavenly_tribulation/tribulation_fight.gd"

## Every `src/` file. The wave driver and the survival curve are only single if
## NOTHING reaches around them, and "no `src/` file" is a claim only a sweep of all
## of them can make.
const SRC_FILES := "res://src"

## The two wave verbs that descend a wave WITHOUT charging `WAVE_TOLL`. Legal in
## the files that define the mechanism; a fight driven through either is a free
## fight.
const FREE_WAVE_VERBS := ["advance_tribulation(", ".advance_wave("]

## Depth cap for the `src/` sweep. `res://src` is a tree with no cycles, so the cap
## is unreachable by construction — it is here because an unbounded recursive walk is
## an unbounded loop with a slower fuse, and this one reads every file in the game.
const MAX_WALK_DEPTH := 12

## One bound, naming what it catches: a fight that stopped converging would spin the
## wave descent instead of descending it.
const WAVE_GUARD := 16

# --- Fixtures -----------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _actor_at_r18(path_id: StringName = QiPath.PATH_ID) -> Actor:
	var actor := Actor.new(&"mechanism_hero", {Stat.COMPREHENSION: 40.0})
	actor.set_path(PathState.new(path_id, _realm_id(17)))
	actor.meridians.unlock_for_realm(_realm_id(17))
	return actor


## A generator whose next draw is below every possible endurance, so the fight is won
## whatever the rating works out at.
func _won_roll() -> RandomNumberGenerator:
	return _seeded(Tribulation.MIN_ENDURANCE, true)


## A generator whose next draw is at or above every possible endurance, so the fight
## is lost whatever the rating works out at.
func _lost_roll() -> RandomNumberGenerator:
	return _seeded(Tribulation.MAX_ENDURANCE, false)


func _seeded(threshold: float, below: bool) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(1, 4096):
		rng.seed = seed_value
		if (rng.randf() < threshold) == below:
			rng.seed = seed_value
			return rng
	return rng


# --- The names are there ------------------------------------------------------


## Every identifier ADR 0061 lands by name. A silent revert of `tribulation.gd`
## removes them, and the suites that use them then FAIL TO LOAD — which the runner
## reports as a warning rather than a failure, so the structure is asserted here where
## a missing name is red.
func test_every_named_identifier_of_the_mechanism_is_present() -> void:
	for name in [
		"WAVE_TOLL",
		"MIN_ENDURANCE",
		"MAX_ENDURANCE",
		"WAVES_BY_TIER",
		"BASE_WAVES",
		"PREPARATION_AIDS",
		"PREPARATION_FLOOR",
	]:
		assert_eq(name in _source(TRIBULATION_SRC), true, "Tribulation names %s" % name)
	for signature in ["func fight_wave(", "func rate(", "func apply_result("]:
		assert_eq(
			signature in _source(TRIBULATION_SRC), true, "Tribulation declares %s" % signature
		)
	for signature in [
		"static func face_tribulation(",
		"static func resolve_tribulation(",
		"static func owed_index(",
	]:
		assert_eq(
			signature in _source(BREAKTHROUGH_SRC), true, "Breakthrough declares %s" % signature
		)


## ONE answer to "how often does this actor survive". The record used to carry a
## second, actor-free `endurance()` that no `src/` file called — same slope, same
## clamp, and no dao heart, so a screen quoting it would have shown a worse number
## than the roll actually used. Deleted (ADR 0125); this fails if it comes back.
func test_the_survival_formula_is_single_sourced() -> void:
	assert_eq(
		"func endurance(" in _source(TRIBULATION_SRC),
		false,
		"Tribulation answers no survival question of its own"
	)
	assert_eq(
		_code_of(TRIBULATION_ENDURANCE_SRC).count("func endurance("),
		1,
		"TribulationEndurance declares the one curve"
	)
	assert_eq(_code_of(TRIBULATION_ENDURANCE_SRC).count("func survives("), 1, "and the one roll")


## ONE derivation of "which realm is owed". `TribulationFight.target_index` and a
## private `TribulationEndurance._owed_realm` were the same rule in two homes, so a
## change to one was invisible to a test on the other — and they priced the odds
## against one realm while the fight was fought for another.
func test_the_owed_realm_rule_has_one_home() -> void:
	assert_eq(
		"_owed_realm" in _code_of(TRIBULATION_ENDURANCE_SRC),
		false,
		"core's curve no longer keeps a private copy"
	)
	assert_eq(
		"func owed_index(" in _code_of(FIGHT_SRC),
		false,
		"and the module delegates rather than re-deriving"
	)
	assert_eq(
		"Breakthrough.owed_index(actor)" in _code_of(FIGHT_SRC),
		true,
		"to the one derivation core owns"
	)


## ONE wave driver. `advance_tribulation` and `advance_wave` walk the phase machine
## without charging `WAVE_TOLL`, and the tribulation screen used to fight through the
## first of them — so the same fight cost one comprehension per wave from a
## breakthrough action and nothing at all from the screen. Only the two files that
## DEFINE the mechanism may name a free verb; every other file in `res://src`,
## `heavenly_tribulation/tribulation_fight.gd` INCLUDED, must descend a fight through
## `Tribulation.fight_wave`.
func test_no_production_call_site_fights_a_wave_without_paying_the_toll() -> void:
	var offenders: Array[String] = []
	for path in _gd_files(SRC_FILES):
		if path == TRIBULATION_SRC or path == BREAKTHROUGH_SRC:
			continue
		var code := _code_of(path)
		for verb in FREE_WAVE_VERBS:
			if verb in code:
				offenders.append("%s calls %s" % [path.get_file(), verb])
	assert_eq(offenders.is_empty(), true, "a free wave is never a fight: %s" % str(offenders))


## The threshold has ONE home. `Tribulation.TRIBULATION_REALM_THRESHOLD` duplicated
## `Breakthrough.IMMORTAL_REALM_THRESHOLD`, and a second copy of the tier boundary is a
## boundary that can drift from the gate that reads it.
func test_the_realm_threshold_is_not_duplicated() -> void:
	assert_eq(
		"TRIBULATION_REALM_THRESHOLD" in _source(TRIBULATION_SRC),
		false,
		"Tribulation names no threshold of its own"
	)
	assert_eq(
		"const IMMORTAL_REALM_THRESHOLD := 18" in _source(BREAKTHROUGH_SRC),
		true,
		"and Breakthrough still owns the one copy"
	)


## The second gate nothing could satisfy is gone, not deprecated: a condition whose
## keys nothing in `src/` ever wrote was permanently false.
func test_the_permanently_false_condition_is_deleted() -> void:
	assert_eq(FileAccess.file_exists(CONDITION_SRC), false, "the condition file is gone")
	assert_eq(
		"TribulationCondition" in _source(BREAKTHROUGH_SRC), false, "and core names no such gate"
	)


## The reward belongs to the fight, so no path's post-advance step decides one. This
## used to be five call sites, and entering R19 paid 70 insight for a 35-insight fight.
func test_no_module_decides_a_tribulation_after_advancing() -> void:
	for path in [
		"res://src/modules/body_cultivation/advancement.gd",
		"res://src/modules/qi_cultivation/advancement.gd",
		"res://src/modules/qi_cultivation/breakthrough_transaction.gd",
		"res://src/modules/mind_cultivation/advancement.gd",
	]:
		assert_eq(
			"apply_result(" in _code_of(path), false, "%s decides no tribulation" % path.get_file()
		)


## The source with every whole-line comment removed. The qi's file still NAMES
## `apply_result(actor, true)` in the comment that records deleting it, and a grep that
## counted prose would report the deletion as the defect it removed.
func _code_of(path: String) -> String:
	var kept: Array[String] = []
	for line in _source(path).split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)


## Every `.gd` under `root`, capped at `MAX_WALK_DEPTH` so the walk itself cannot be
## the runaway. `DirAccess.get_next()` returning "" is what ends each listing.
func _gd_files(root: String, depth: int = 0) -> Array[String]:
	var found: Array[String] = []
	if depth >= MAX_WALK_DEPTH:
		return found
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_gd_files(path, depth + 1))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


# --- Behaviours the phase-machine suites cannot see ---------------------------


## The toll is charged on the PRODUCTION path, not only when a test calls
## `fight_wave` directly. A toll that only a test pays is not a toll.
func test_the_production_entry_point_charges_the_wave_toll() -> void:
	var actor := _actor_at_r18()
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	Breakthrough.face_tribulation(actor, QiPath.PATH_ID, _won_roll())
	assert_ne(actor.tribulation, null, "a fight was begun")
	assert_eq(actor.tribulation.wave, 1, "and one wave was fought")
	assert_eq(
		actor.stats.get_base(Stat.COMPREHENSION),
		before - Tribulation.WAVE_TOLL,
		"and it cost one toll"
	)


## A path below the tier owes nothing, so the entry point is a no-op rather than a
## fight nobody asked for — and a no-op that costs no dao heart.
func test_the_production_entry_point_is_free_below_the_tier() -> void:
	var actor := Actor.new(&"mortal_hero", {Stat.COMPREHENSION: 40.0})
	actor.set_path(PathState.new(QiPath.PATH_ID, _realm_id(0)))
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	assert_eq(Breakthrough.face_tribulation(actor, QiPath.PATH_ID, _won_roll()), true, "")
	assert_eq(actor.tribulation, null, "nothing descended")
	assert_eq(actor.stats.get_base(Stat.COMPREHENSION), before, "and nothing was charged")


## The roll decides the fight on the production path too. Before the fight had a roll
## at all, every call site passed a literal `true` and defeat was unreachable content.
func test_the_production_entry_point_can_lose() -> void:
	var actor := _actor_at_r18()
	var guard := 0
	while guard < WAVE_GUARD and not _decided(actor):
		guard += 1
		Breakthrough.face_tribulation(actor, QiPath.PATH_ID, _lost_roll())
	assert_eq(actor.tribulation.outcome, Tribulation.OUTCOME_FAILED, "the roll lost the fight")
	assert_eq(Breakthrough.tribulation_ok(actor, 18), false, "and the gate stays shut")
	assert_eq(actor.has_status(&"heavenly_blessing"), false, "and it paid nothing")


## Whether the record carries a verdict yet. A decided record is what the gate reads,
## so there is nothing left to drive.
func _decided(actor: Actor) -> bool:
	return actor.tribulation != null and actor.tribulation.outcome != Tribulation.OUTCOME_UNRESOLVED


## `apply_result` answers whether THIS call decided the fight. A `void` return cannot
## be once-guarded observably, so the guard is what makes the once-only award provable
## from outside the record.
func test_apply_result_reports_whether_it_decided() -> void:
	var actor := _actor_at_r18()
	var tribulation := Breakthrough.begin_tribulation(actor, 18)
	var guard := 0
	while guard < WAVE_GUARD and not tribulation.is_complete():
		guard += 1
		tribulation.advance_wave()
	assert_eq(tribulation.apply_result(actor, true), true, "the first call decided")
	assert_eq(tribulation.apply_result(actor, true), false, "the second decided nothing")
	assert_eq(tribulation.apply_result(actor, false), false, "and neither did a loss")


## `to_dict` is the single serialization point, and it writes the price actually paid:
## a resumed fight must not re-derive a softer or a harsher one. Proven by handing the
## loader a doctored rating — if `from_dict` re-derived anything, the doctored value
## would be overwritten.
func test_a_restored_fight_keeps_the_price_it_was_paid_not_a_re_derived_one() -> void:
	var actor := _actor_at_r18()
	var tribulation := Breakthrough.begin_tribulation(actor, 18)
	var paid := tribulation.difficulty
	var payload := tribulation.to_dict()
	payload["difficulty"] = paid * 0.5
	payload["preparation"] = {"formation": 0.125}
	var restored := Tribulation.from_dict(payload)
	assert_eq(restored.difficulty, paid * 0.5, "the recorded rating is what is read back")
	assert_eq(restored.preparation["formation"], 0.125, "and so is the recorded aid")
	# A re-derived record would price this fight at `restored.preparation`, not at the
	# rating actually paid. This is what a resumed fight must not do.
	assert_eq(restored.rate(actor), tribulation.rate(actor) * 0.875, "the aid is what re-rates")
	assert_ne(restored.rate(actor), restored.difficulty, "so the two disagree, as they must")


func _source(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	assert_ne(text.is_empty(), true, "%s is readable" % path)
	return text
