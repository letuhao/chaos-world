extends TestCase

## DEF-0105, closed: `combat` decided defeats and recorded wins, and never once
## called `DestinyApi.earn_fate` — so a player could finish a duel and gain nothing
## for it. The decision points existed the whole time
## (`CombatExchange._record_defeat`, `CombatDuel.record_defeat`), which is why this
## was an UNWIRED gap rather than a missing feature.
##
## ## What is asserted here is the WIRING, over the real production verbs
##
## Nothing in this file constructs a ledger by hand to stand in for a fight. Every
## case drives `CombatExchange.exchange` or `CombatApi.hit` — the two verbs the game
## itself presses — and reads `DestinyApi.has_fate` afterwards. A suite that earned
## the fate directly would have passed on the old broken build, which is the shape of
## test that let this gap survive two audits.
##
## ## Why these fates, from their OWN text
##
## `first_blood_duel`: "Opened a duel and closed it, alone, without assistance ...
## the second party filed nothing." — `CombatDuel.record_win` fires on the killing
## blow and on nothing else, so both halves are already true when it is granted.
##
## `vigil_broken_by_hand`: "Came off the wall mid-watch to settle a private matter
## ... Two of its dead were not the reason anyone remembers you." — the boss run a
## loss ends IS the private matter, and this fate declares `duels_won` as a counter.
##
## Read off the real catalog rather than assumed, so a renamed or typo'd id fails
## here instead of silently changing which fate `combat` pays.
const Support := preload("res://tests/modules/destiny/destiny_counter_wiring_support.gd")

## The fate a LOST duel earns. See `vigil_broken_by_hand` above.
const FELL := &"vigil_broken_by_hand"

## The fate a WON duel earns. See `first_blood_duel` above.
const BLOOD := &"first_blood_duel"

## A fate `combat` must NOT be able to grant on its own. `the_third_man_spared` is
## about SPARING — "Stood at killing distance with the advantage held and did not
## close" — and `CombatDuel.record_spare` is deliberately reached without a killing
## blow, so paying it there would make the fate's own claim false.
const SPARED := &"the_third_man_spared"

## A band the deepest authored entry reaches, where a bare actor LOSES. Taken from
## `tests/modules/combat/test_combat_exchange.gd`'s own fixture rather than
## invented: that suite already proves this band beats an actor with no gear, which
## is the fact a loss test needs and cannot establish for itself.
const DEEP_DOMAIN := &"elemental_transcendent_domain"
const DEEP_TIER := 1

## Exchanges one fight may take before this calls it a stall. The cap names the
## condition that failed to converge rather than looping forever, and it is taken
## before the walk and never moved by it.
const EXCHANGE_CAP := 200

## The seed the combat verbs take. A constant rather than a call to `randi`, because
## a suite whose result depends on the roll is a suite that fails for no reason a
## reader could find (ADR 0067).
const SEED := 20_260_910

## **`Support` is a script constant, so it exposes only the STATIC surface.**
## `_fighter` and `_fight_to_a_kill` are instance methods and do not resolve through
## one. The helper is therefore held as ONE instance and bound in `setup()`, which
## the runner calls before every `test_*` — the same shape, and the same stated
## reason, as `test_destiny_counter_production_wiring.gd`.
var _support: RefCounted = null


func setup() -> void:
	_support = Support.new()
	# The bridge that turns a written FACT into a fate COUNTER is installed at the
	# composition root, which a fixture-built actor never boots. Without it the
	# duel fact is recorded and the counter stays 0, so every case here fails on a
	# missing subscription rather than on a missing earn — which reads as "combat
	# never earns" when combat earns fine. Installed per test and asserted, so a
	# suite that cannot see the bridge says so instead of blaming the earn.
	DestinyProjection.subscribe_to_fact_ledger()
	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		true,
		"the fact->counter bridge is live for this suite: the counters below are derived"
	)


func teardown() -> void:
	# The subscriber list is PROCESS-WIDE, so a suite that leaves the bridge
	# installed moves counters for every later suite in the run.
	DestinyProjection.unsubscribe_from_fact_ledger()


# --- The earn is wired ---------------------------------------------------------


## THE gap, on the boss-exchange path. `CombatExchange._record_defeat` is where
## DEF-0105 names the decision, and it now calls the facade — so a player who loses
## a run earns the fate rather than only being counted.
func test_a_defeat_in_the_exchange_earns_a_fate() -> void:
	var actor: Actor = _delver()
	assert_eq(DestinyApi.has_fate(actor, FELL), false, "nothing is earned before the fight")
	if not _entered(actor):
		return
	assert_eq(
		String(_fight(actor)["outcome"]),
		CombatExchange.OUTCOME_PLAYER_LOST,
		"a bare actor loses the deepest authored band, so a defeat was really decided"
	)
	assert_eq(DestinyApi.has_fate(actor, FELL), true, "and that defeat earned the fate")
	assert_eq(
		String(_source_of(actor, FELL)),
		CombatDuel.EARN_SOURCE,
		"and the ledger names `combat` as the system, never the fate id (ADR 0065)"
	)
	# The two writes are SEPARATE, so both are asserted: a version that counted the
	# duel and dropped the fate, or the reverse, fails one half of this pair.
	assert_eq(
		int(CombatExchange.duel(actor)["defeats"]),
		1,
		"and the duel ledger still counted the loss it already counted before"
	)


## The same earn reached through the OTHER verb. `CombatDuelHit` → `CombatApi.hit` is
## what the duelling screen presses, and it is a DIFFERENT call site from
## `CombatExchange` — a gate wired at one is a gate the other walks past, which is
## the same shape DEF-0106's three paths had.
func test_a_won_duel_earns_first_blood() -> void:
	var victor: Actor = _support._fighter(&"victor")
	var loser: Actor = _support._fighter(&"loser", 4.0)
	assert_eq(DestinyApi.has_fate(victor, BLOOD), false, "nothing is earned before the fight")
	assert_eq(
		_support._fight_to_a_kill(victor, loser),
		true,
		"the duel was decided: a blow landed and the defender did not get up"
	)
	assert_eq(DestinyApi.has_fate(victor, BLOOD), true, "a duel closed with a kill earned it")
	assert_eq(
		String(_source_of(victor, BLOOD)),
		CombatDuel.EARN_SOURCE,
		"and the ledger names `combat` as the source"
	)


## The fate goes to the VICTOR and to nobody else. ADR 0137 puts `duels_won` on the
## winner's ledger for exactly this reason, so the fate follows the fact; paying the
## loser would be a different claim about who did what.
func test_the_win_fate_lands_on_the_victor_not_the_loser() -> void:
	var victor: Actor = _support._fighter(&"victor")
	var loser: Actor = _support._fighter(&"loser", 4.0)
	assert_eq(_support._fight_to_a_kill(victor, loser), true, "the duel was decided")
	assert_eq(DestinyApi.has_fate(victor, BLOOD), true, "the victor holds it")
	assert_eq(
		DestinyApi.has_fate(loser, BLOOD),
		false,
		"the loser holds nothing: the fate is about the hand that closed the duel"
	)


## Exactly-once is ADR 0065's guarantee, and it is what makes it SAFE for `combat`,
## `quest` and `event` to name the same fate from three systems. A second duel must
## therefore pay nothing — asserted on the sequence, which is what a second append
## would move, rather than on `has_fate`, which cannot tell the two apart.
func test_a_second_duel_pays_the_same_fate_nothing() -> void:
	var victor: Actor = _support._fighter(&"victor")
	assert_eq(
		_support._fight_to_a_kill(victor, _support._fighter(&"loser", 4.0)),
		true,
		"the first duel was decided"
	)
	var first := _sequence_of(victor, BLOOD)
	assert_eq(
		_support._fight_to_a_kill(victor, _support._fighter(&"loser_two", 4.0)),
		true,
		"a second, unrelated duel was decided"
	)
	assert_eq(
		_sequence_of(victor, BLOOD),
		first,
		"the fate's ledger sequence did not move, so the second earn appended nothing"
	)
	assert_eq(
		int(CombatDuel.normalize(victor.get_module_data(CombatDuel.MODULE_KEY))["wins"]),
		2,
		"while the duel ledger counted both — the counter and the fate are one deed, paid once"
	)


## A MERCY is not a kill and must not pay a kill's fate. `record_win` fires on the
## killing blow and on nothing else (`duel_hit.gd` states the rule), so this asserts
## the negative half with the duel genuinely still open: a spared fighter is walking
## away, so nothing `combat` owns may pay for a kill that did not happen.
func test_a_spare_earns_no_kill_fate_and_leaves_the_duel_unclosed() -> void:
	var victor: Actor = _support._fighter(&"victor")
	var loser: Actor = _support._fighter(&"loser")
	var spared := CombatApi.spare(victor, loser)
	assert_eq(bool(spared["ok"]), true, "the mercy took effect")
	assert_eq(DestinyApi.has_fate(victor, BLOOD), false, "and a spared opponent is not a kill")
	assert_eq(DestinyApi.has_fate(victor, SPARED), false, "and combat grants no fate for it")
	assert_eq(
		String(CombatDuelHit.resolve(victor, loser, _rng())["reason"]),
		"defender_spared",
		(
			"the mercy still terminates the duel, so the earn could not have been skipped by "
			+ "the mercy never landing"
		)
	)


## A LEDGER with no actor still works. `record_defeat`/`record_win` take an optional
## `Actor` precisely because the existing callers pass a bare dictionary, and a
## fate-side write must not turn that into a crash.
func test_the_ledger_writers_still_work_without_an_actor() -> void:
	var bare := CombatDuel.record_defeat(CombatDuel.blank(), {"outcome": "player_lost"})
	assert_eq(int(bare["defeats"]), 1, "a pure ledger write still counts")
	assert_eq(
		bare.has("fates"),
		false,
		"and gains no fate row: the two ledgers are separate and only the actor's carries one"
	)
	assert_eq(
		int(CombatDuel.record_win(CombatDuel.blank(), {"outcome": "duel_won"})["wins"]),
		1,
		"the win writer is unchanged for the same reason"
	)


# --- The claim is auditable ----------------------------------------------------


## The ids this suite claims are AUTHORED, and the catalog agrees with the constants
## the module's own code earns under. Without this a typo'd `FATE_FELL` would make
## the negatives pass vacuously, and a renamed-but-resolving constant would silently
## swap WHICH fate `combat` pays with nothing else here noticing.
func test_the_ids_this_suite_claims_are_authored() -> void:
	for fate_id in [FELL, BLOOD, SPARED]:
		assert_ne(
			FateCatalog.instance().fate_definition(fate_id),
			null,
			(
				"%s is an authored FateDef; a name the catalog does not define grants nothing"
				% String(fate_id)
			)
		)
	assert_eq(
		CombatDuel.FATE_FELL,
		FELL,
		"the module's defeat constant and this suite's id are the same fate"
	)
	assert_eq(CombatDuel.FATE_FIRST_BLOOD, BLOOD, "and so are the win ones")


## Each granted fate declares a counter that is really about a fight, so the pairing
## is not a naming coincidence. Both read `duels_won`, which is the fact ADR 0137
## puts on the winner's ledger and the one `CombatFacts` writes.
func test_each_granted_fate_declares_a_duel_counter() -> void:
	for fate_id in [FELL, BLOOD]:
		var def := FateCatalog.instance().fate_definition(fate_id)
		var counters: Array = [] if def == null else Array(def.counters)
		assert_eq(
			counters.has(&"duels_won"),
			true,
			"%s declares `duels_won`, the counter a duel decision actually moves" % String(fate_id)
		)


## ## The registry is the ONLY record of the edge, and this asserts it exists
##
## `BARE_REF_UNITS` in `tools/arch/rules.py` excludes `modules/*`, so a bare
## module-to-module call is invisible to `tools arch` AND to `_find_cycle`, which is
## fed by the registry alone (ADR 0134 §2 — the rule that has already failed once,
## on `quest`). Without the `deps` entry the earn works perfectly and the edge is
## unrecorded, and a module cycle would ship unnoticed.
func test_combat_declares_destiny_in_the_arch_registry() -> void:
	var combat := _modules().get("combat", {}) as Dictionary
	assert_eq(
		(combat.get("deps", []) as Array).has("destiny"),
		true,
		(
			"combat calls DestinyApi.earn_fate, so it must declare `destiny` in "
			+ "tools/arch/registry.json; a bare module reference is reported as an unresolved "
			+ "count rather than enforced, so the registry is the only place this edge lives"
		)
	)


## …and that the earn call is really there, read off the SHIPPED SOURCE. Without
## this the registry assertion could stay green after the call was deleted, which is
## the same UNWIRED failure one layer down: a recorded edge with nothing behind it.
func test_combat_source_really_earns_and_the_registry_has_not_drifted() -> void:
	# Count LINES that call the earn, not files that contain the string. An earlier
	# shape did `body.split("#")[0].contains(...)`, which keeps only the text BEFORE
	# the first `#` anywhere in the file — so every call sitting after any comment
	# was invisible and the count read 0 with the wiring fully present. Strip
	# comment lines instead, which is what "executable code" actually means.
	var earn_sites := 0
	for path in _module_files("combat"):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			if line.contains("DestinyApi.earn_fate"):
				earn_sites += 1
	assert_eq(
		earn_sites,
		2,
		(
			"combat earns on exactly two sites — `CombatDuel.record_defeat` and "
			+ "`CombatDuel.record_win`. Zero means the wiring is gone while the registry "
			+ "still claims the edge; three means a earn crept into a module that does not own "
			+ "the moment."
		)
	)


## The registry is still well formed. `tools arch` reads this file, so a mangled
## array would make every module's boundaries unresolvable rather than one of them
## wrong — a failure that would read as "the gate is broken" on an unrelated change.
func test_the_registry_is_still_well_formed() -> void:
	var modules := _modules()
	assert_eq(modules.has("destiny"), true, "the module being consumed is itself declared")
	var deps := (modules.get("combat", {}) as Dictionary).get("deps", []) as Array
	assert_eq(
		deps.has("contracts") and deps.has("core") and deps.has("loot") and deps.has("status"),
		true,
		"combat keeps every dep it had before `destiny` was added"
	)
	var ordered := deps.duplicate()
	ordered.sort()
	assert_eq(deps, ordered, "and its deps stay in the alphabetical order the file uses")


# --- Fixtures and readers -----------------------------------------------------


## A bare delver — no gear, no cultivation — which is the one `test_combat_exchange
## .gd` already proves loses the deep band. `DestinyApi.attach` runs first so the
## ledger the earn writes into exists before the fight does.
func _delver() -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor)
	LootApi.attach(actor)
	DestinyApi.attach(actor)
	return actor


## Enter the deep band, asserting rather than returning quietly: a test that silently
## fought nothing would report green for the wrong reason.
func _entered(actor: Actor) -> bool:
	var result := LootApi.enter_domain(actor, DEEP_DOMAIN, DEEP_TIER, SEED)
	assert_eq(bool(result.get("ok", false)), true, "entered %s" % String(DEEP_DOMAIN))
	return bool(result.get("ok", false))


## Swap blows until the exchange decides something. The cap names the condition that
## failed to converge; a model where no fight ends reports `"unresolved"` rather than
## spinning.
func _fight(actor: Actor) -> Dictionary:
	for index in EXCHANGE_CAP:
		var result := CombatExchange.exchange(actor, SEED + index)
		if String(result.get("outcome", "")) != "":
			return result
	return {"outcome": "unresolved"}


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


## The `source` recorded against `fate_id` on `actor`'s ledger, or `""`. Read off
## `DestinyApi.state`, which is the save payload core persists — never off
## `actor.module_data`, which is the boundary ADR 0134's Consequences name.
func _source_of(actor: Actor, fate_id: StringName) -> String:
	var fates := DestinyApi.state(actor)["fates"] as Dictionary
	return String((fates.get(String(fate_id), {}) as Dictionary).get("source", ""))


## The `sequence` the ledger stamped `fate_id` with. Re-earning leaves it untouched,
## which is how "paid twice" is told from "paid once".
func _sequence_of(actor: Actor, fate_id: StringName) -> int:
	var fates := DestinyApi.state(actor)["fates"] as Dictionary
	return int((fates.get(String(fate_id), {}) as Dictionary).get("sequence", 0))


## `tools/arch/registry.json`'s module map. The file sits outside `game/`, which is
## what `res://` points at, so it is read through `res://../`.
func _modules() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://../tools/arch/registry.json")
	)
	assert_eq(parsed is Dictionary, true, "tools/arch/registry.json is readable JSON")
	return {} if not (parsed is Dictionary) else (parsed as Dictionary)["modules"] as Dictionary


## Every `.gd` under `game/src/modules/<name>/`, so the earn-site count is read off
## real source rather than from a list maintained beside it.
func _module_files(module_name: String) -> Array[String]:
	var out: Array[String] = []
	_scan("res://src/modules/%s" % module_name, out)
	return out


func _scan(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := dir_path.path_join(name)
			if dir.current_is_dir():
				_scan(full, out)
			elif name.ends_with(".gd"):
				out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
