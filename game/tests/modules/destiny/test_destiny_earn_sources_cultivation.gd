extends TestCase

## DEF-0106, closed: the three cultivation paths each decide — genuinely, and in
## their own code — whether a breakthrough happened, and none of them called
## `DestinyApi.earn_fate`. So a player could cross the barrier and hold no record of
## having crossed it, and every fate-gated destiny naming a path's oath refused
## forever.
##
## ## The sites, and why each sits where it does
##
##   - `qi`: `QiAdvancement.try_breakthrough`, wrapping the transaction's own `true`.
##     `QiCultivationApi.attempt_breakthrough` calls `QiBreakthroughTransaction
##     .execute` DIRECTLY and is never routed through here, so the UI's own
##     breakthrough button (`qi_cultivation_screen.gd:275`) has to earn at its own
##     site too. A gate wired at one of the two is a gate the other walks past.
##   - `body`: `BodyAdvancement.resolve_attempt`, the once-only grant point BOTH the
##     two-phase lifecycle and `try_breakthrough` pass through, so one call covers
##     every body entry point.
##   - `mind`: `MindAdvancement.resolve_attempt`, for the same reason, and because
##     `app/mind_cultivation_ui.gd` calls `try_breakthrough` directly and skips the
##     facade — the same argument that put the ADR 0109 gate at this layer.
##
## ## Every case drives the REAL breakthrough
##
## Nothing here calls `earn_fate` to set up its own expectation. Preparation is each
## module's own fixture, the roll is searched for DETERMINISTICALLY against a probe
## actor, and the assertion reads `DestinyApi.has_fate` afterwards. That is what
## makes the suite go RED if any one of the four `earn_fate` calls is deleted: the
## deed still happens, and only the fate stops. A suite that earned the fate by hand
## would pass on the un-wired build, which is how this gap survived two audits.
const BodyFixture := preload("res://tests/modules/body_cultivation/body_play_fixture.gd")
const MindProbe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")
const QiProbe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

## The fate the qi and mind paths earn, from its OWN text: "Walked into a forbidden
## ridge and came back with the ridge's name in your mouth."
const BARRIER := &"remembered_by_the_mountain"

## The fate the body path earns, from its OWN text: "Came back after a failure at
## the barrier in a body the sect records as a downgrade. The technique survived."
const VESSEL := &"reborn_in_a_lesser_vessel"

## A fate no breakthrough may grant. `oath_breaker` is about WITNESSING an oath
## broken — "Witnessed swearing an oath and witnessed breaking it, both in the same
## quarter hour" — and a breakthrough witnesses nothing and breaks nothing. It is
## also the fate `the_severed_calling.tres` gates on, so a false earn would open a
## quest for a player who did nothing.
const OATH_BREAKER := &"oath_breaker"

## Seeds searched before giving up on a roll. The bound names the condition that
## failed to converge rather than looping forever, and it is taken before the search
## and never moved by it.
const SEED_CAP := 256

# --- Lifecycle ----------------------------------------------------------------


## Install the fact->counter bridge for the length of one test.
##
## The bridge is installed at the composition root, and a hero built by a fixture
## never boots it — so the breakthrough fact is written and the counter the paths
## declare stays 0. Every case below would then fail on a missing SUBSCRIPTION
## rather than on a missing earn, which reads as "the paths never earn" when they
## earn correctly. Installed here and asserted, so the failure names the real cause.
func setup() -> void:
	DestinyProjection.subscribe_to_fact_ledger()
	assert_eq(
		DestinyProjection.is_subscribed_to_fact_ledger(),
		true,
		"the fact->counter bridge is live: the counters the paths declare are derived"
	)


func teardown() -> void:
	# Process-wide subscriber list: a suite that leaks it moves counters for every
	# suite that runs after it.
	DestinyProjection.unsubscribe_from_fact_ledger()


# --- Qi -----------------------------------------------------------------------


## The qi earn site under test. Driven through `QiAdvancement` because that is where
## the earn is; a test of the bare transaction would be measuring the wrong layer.
func test_a_qi_breakthrough_earns_the_barrier_fate() -> void:
	var hero := _qi_hero()
	assert_eq(DestinyApi.has_fate(hero, BARRIER), false, "nothing is earned before the attempt")
	var rng := _qi_roll(hero, true)
	assert_ne(rng, null, "a prepared qi hero with a winning roll exists")
	assert_eq(QiAdvancement.try_breakthrough(hero, rng), true, "the breakthrough was granted")
	assert_eq(DestinyApi.has_fate(hero, BARRIER), true, "and it earned the barrier fate")
	assert_eq(
		String(_source_of(hero, BARRIER)),
		QiAdvancement.EARN_SOURCE,
		"under the path's own source, naming the system and never the fate id (ADR 0065)"
	)
	assert_eq(
		DestinyApi.has_fate(hero, OATH_BREAKER),
		false,
		"and nothing else: a breakthrough witnesses no oath and breaks none"
	)


## A FAILED qi attempt must earn nothing. This is what separates "on the granted
## branch" from "somewhere in the function": a deviation is a real decision this path
## makes, and paying for it would pay for the one outcome the fate's own text is
## written against.
func test_a_failed_qi_breakthrough_earns_nothing() -> void:
	var hero := _qi_hero()
	var rng := _qi_roll(hero, false)
	assert_ne(rng, null, "a prepared qi hero with a losing roll exists")
	assert_eq(QiAdvancement.try_breakthrough(hero, rng), false, "the attempt deviated")
	assert_eq(DestinyApi.has_fate(hero, BARRIER), false, "so no fate was earned")


## ## The second qi entry point, which is a genuinely separate site
##
## `QiCultivationApi.attempt_breakthrough` calls `QiBreakthroughTransaction.execute`
## and never touches `QiAdvancement.try_breakthrough`, and `qi_cultivation_screen.gd
## :275` calls the FACADE. So the UI's own breakthrough button runs through this
## site, and a wiring that existed only on `QiAdvancement` would leave the button
## earning nothing — which is precisely the defect this suite exists to hold shut.
func test_the_qi_facade_entry_point_earns_too() -> void:
	var hero := _qi_hero()
	var rng := _qi_roll(hero, true)
	assert_ne(rng, null, "a prepared qi hero with a winning roll exists")
	assert_eq(
		QiCultivationApi.attempt_breakthrough(hero),
		true,
		"the facade's own entry point granted the breakthrough"
	)
	assert_eq(
		DestinyApi.has_fate(hero, BARRIER),
		true,
		"and earned the fate, so the UI's Breakthrough button is not a walk past it"
	)


# --- Body ---------------------------------------------------------------------


## The body's grant point is `resolve_attempt`, which `try_breakthrough` reaches and
## which the UI presses, so this is the production path rather than a test-only one.
func test_a_body_breakthrough_earns_the_vessel_fate() -> void:
	var hero := _body_hero()
	assert_eq(DestinyApi.has_fate(hero, VESSEL), false, "nothing is earned before the attempt")
	var rng := _body_roll(hero, true)
	assert_ne(rng, null, "a prepared body hero with a winning roll exists")
	assert_eq(BodyAdvancement.try_breakthrough(hero, rng), true, "the breakthrough was granted")
	assert_eq(DestinyApi.has_fate(hero, VESSEL), true, "and it earned the lesser-vessel fate")
	assert_eq(
		String(_source_of(hero, VESSEL)),
		BodyAdvancement.EARN_SOURCE,
		"under the path's own source, naming the system and never the fate id"
	)
	assert_eq(
		DestinyApi.has_fate(hero, BARRIER),
		false,
		(
			"and NOT the qi/mind fate: sharing one id between all three paths would make the "
			+ "pair a naming coincidence rather than a claim about which path earned what"
		)
	)


## The negative of the case above, and the one that bites if the earn is ever moved
## above the roll.
func test_a_failed_body_breakthrough_earns_nothing() -> void:
	var hero := _body_hero()
	var rng := _body_roll(hero, false)
	assert_ne(rng, null, "a prepared body hero with a losing roll exists")
	assert_eq(BodyAdvancement.try_breakthrough(hero, rng), false, "the attempt deviated")
	assert_eq(DestinyApi.has_fate(hero, VESSEL), false, "so no fate was earned")


## The earn is EXACTLY ONCE across repeated breakthroughs. ADR 0065 guarantees it,
## and it is what makes it safe for creation's `ARRIVAL_FATES`, `the_short_road` and
## this path to all name `reborn_in_a_lesser_vessel`: a second realm crossed must
## leave the sequence where the first one put it.
func test_a_second_body_breakthrough_pays_the_fate_nothing() -> void:
	var hero := _body_hero()
	var rng := _body_roll(hero, true)
	assert_ne(rng, null, "a prepared body hero with a winning roll exists")
	assert_eq(BodyAdvancement.try_breakthrough(hero, rng), true, "the first was granted")
	var first := _sequence_of(hero, VESSEL)
	assert_eq(BodyFixture.breakthrough(hero, _rng(4242)), true, "a second realm was entered")
	assert_eq(
		_sequence_of(hero, VESSEL),
		first,
		"the fate's sequence did not move, so the second earn appended nothing"
	)
	assert_ne(
		actor_rank(hero),
		&"qi_refining",
		"while the path really did advance — the earn did not block the second attempt"
	)


# --- Mind ---------------------------------------------------------------------


## The mind earn site is `resolve_attempt`, chosen for the same reason as body's and
## because the mind UI bypasses the facade entirely.
func test_a_mind_breakthrough_earns_the_barrier_fate() -> void:
	var hero := _mind_hero()
	assert_eq(DestinyApi.has_fate(hero, BARRIER), false, "nothing is earned before the attempt")
	var rng := _mind_roll(hero, true)
	assert_ne(rng, null, "a prepared mind hero with a winning roll exists")
	assert_eq(MindAdvancement.try_breakthrough(hero, rng), true, "the breakthrough was granted")
	assert_eq(DestinyApi.has_fate(hero, BARRIER), true, "and it earned the barrier fate")
	assert_eq(
		String(_source_of(hero, BARRIER)),
		MindAdvancement.EARN_SOURCE,
		"under the MIND path's own source, so the ledger can tell it from qi's"
	)
	assert_ne(
		MindAdvancement.EARN_SOURCE,
		QiAdvancement.EARN_SOURCE,
		"and the two paths that share a fate id still record different sources"
	)
	assert_eq(
		DestinyApi.has_fate(hero, VESSEL),
		false,
		"and not the body path's fate — qi and mind share `remembered_by_the_mountain`, body does not"
	)


## A failed mind attempt earns nothing.
func test_a_failed_mind_breakthrough_earns_nothing() -> void:
	var hero := _mind_hero()
	var rng := _mind_roll(hero, false)
	assert_ne(rng, null, "a prepared mind hero with a losing roll exists")
	assert_eq(MindAdvancement.try_breakthrough(hero, rng), false, "the attempt deviated")
	assert_eq(DestinyApi.has_fate(hero, BARRIER), false, "so no fate was earned")


# --- The claim is auditable ----------------------------------------------------


## Every id the three paths grant is AUTHORED, and each module's constant names the
## same fate this suite claims. Read off the real catalog, so a typo'd id fails here
## instead of turning every earn into a silent no-op — which is exactly what an
## unverified `earn_fate` cannot tell from success (ADR 0134 §1a).
func test_the_ids_the_paths_grant_are_authored() -> void:
	for fate_id in [BARRIER, VESSEL, OATH_BREAKER]:
		assert_ne(
			FateCatalog.instance().fate_definition(fate_id),
			null,
			"%s is an authored FateDef" % String(fate_id)
		)
	assert_eq(QiAdvancement.FATE_BARRIER, BARRIER, "qi earns what this suite claims")
	assert_eq(MindAdvancement.FATE_BARRIER, BARRIER, "and so does mind")
	assert_eq(BodyAdvancement.FATE_BARRIER, VESSEL, "body earns its own id, not qi's")


## Each granted fate declares a `breakthroughs` counter, so the pairing is a claim
## about the same event rather than a naming coincidence. It is also the honest reason
## the FATE is the earn rather than the counter: no shipped producer drives
## `breakthroughs` (DEF-0121), so `DestinyApi.record` would be the unwired path.
func test_each_granted_fate_declares_the_breakthrough_counter() -> void:
	for fate_id in [BARRIER, VESSEL]:
		var def := FateCatalog.instance().fate_definition(fate_id)
		var counters: Array = [] if def == null else Array(def.counters)
		assert_eq(
			counters.has(&"breakthroughs"),
			true,
			(
				"%s declares `breakthroughs`, which is what these three paths' grants are"
				% String(fate_id)
			)
		)


## ## The registry is the ONLY record of the edge, and this asserts it exists
##
## `BARE_REF_UNITS` in `tools/arch/rules.py` excludes `modules/*`, so a bare
## module-to-module call is invisible to `tools arch` AND to `_find_cycle`, which is
## fed by the registry alone (ADR 0134 §2 — the rule that already failed once, on
## `quest`, DEF-0167). Without the `deps` entry the earn works perfectly and the edge
## is unrecorded.
func test_each_cultivation_path_declares_destiny_in_the_arch_registry() -> void:
	var modules := _modules()
	for module_name in ["qi_cultivation", "body_cultivation", "mind_cultivation"]:
		var entry := modules.get(module_name, {}) as Dictionary
		assert_eq(
			(entry.get("deps", []) as Array).has("destiny"),
			true,
			(
				(
					"%s calls DestinyApi.earn_fate, so it must declare `destiny` in "
					+ "tools/arch/registry.json"
				)
				% String(module_name)
			)
		)


## …and that the earn calls are really in the SOURCE, so the registry cannot stay
## green after a call is deleted. Four sites: two on qi (its own surface plus the
## facade the UI presses) and one on each of body and mind. Counting them from the
## files rather than from a list is what makes a deleted call visible; the registry
## assertion alone would keep passing.
func test_each_path_source_really_earns() -> void:
	var expected := {"qi_cultivation": 2, "body_cultivation": 1, "mind_cultivation": 1}
	for module_name in expected:
		var earn_sites := 0
		for path in _module_files(String(module_name)):
			if FileAccess.get_file_as_string(path).split("#")[0].contains("DestinyApi.earn_fate"):
				earn_sites += 1
		assert_eq(
			earn_sites,
			int(expected[module_name]),
			(
				(
					"%s earns on %d site(s). Zero means the wiring is gone while the registry "
					+ "still claims the edge."
				)
				% [String(module_name), int(expected[module_name])]
			)
		)


# --- Fixtures ------------------------------------------------------------------


## A qi hero on the ladder's first rung. `DestinyApi.attach` runs before anything can
## earn, so the ledger exists before the deed does.
func _qi_hero() -> Actor:
	var actor := QiProbe.fresh_actor(&"qi_refining")
	DestinyApi.attach(actor)
	return actor


## A mind hero on the first rung, mirroring `test_breakthrough_attempt.gd`'s own
## fixture so the prepared state is one that suite already proves reachable.
func _mind_hero() -> Actor:
	var actor := Actor.new(
		&"earn_sources_hero", {Stat.COMPREHENSION: 40.0, MindStats.SEA_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 200)
	MindTraining.synchronize(actor)
	DestinyApi.attach(actor)
	return actor


## A body hero with the ledger attached and nothing earned. `BodyFixture.actor` is
## the module's own fixture, so the state it returns is one the body's suites already
## prove a player can produce.
func _body_hero() -> Actor:
	var actor := BodyFixture.actor(&"qi_refining")
	DestinyApi.attach(actor)
	return actor


func actor_rank(actor: Actor) -> StringName:
	return actor.path(BodyPath.PATH_ID).rank_id


## A prepared qi hero whose first roll decides the way `winning` asks.
##
## The roll is resolved against a THROWAWAY probe and only its seed is replayed on
## the actor under test. Preparation is the module's own probe and is deterministic,
## so the committed chance is a fixed number; searching seeds costs no playthroughs
## and never leaves a hero mid-ladder. `SEED_CAP` is the bound and it is taken before
## the search.
func _qi_roll(hero: Actor, winning: bool) -> RandomNumberGenerator:
	var target := RealmDefaults.ladder().next(hero.path(QiPath.PATH_ID).rank_id)
	if target == null:
		return null
	var seed := QiRealmSeed.for_realm(target.id)
	if seed == null or not _qi_prepare(hero, seed):
		return null
	var chance := float(QiAdvancement.chance(hero))
	return _seed_deciding(chance, winning)


## Bring a qi hero to the brink of `seed`'s realm through the production actions, in
## the order `qi_gate_probe`'s own `prepared` uses — recovery first so nothing an
## earlier attempt wounded refuses to climb, and the pill re-stocked last because
## `prepare`'s own note says a top-up before cultivation is undone by it.
func _qi_prepare(hero: Actor, seed: QiRealmSeed) -> bool:
	var ready := (
		QiProbe.recover_all(hero)
		and QiProbe.stock(hero, seed.breakthrough_item)
		and QiProbe.train_gate_channels(hero, seed)
		and QiProbe.recover_all(hero)
		and QiProbe.earn_progress(hero, seed)
		and QiProbe.meditate_to_floor(hero, seed.comprehension_required)
		and QiProbe.fill_and_refine(hero, seed)
		# Recovering closes a scar, and a scar costs 25% of capacity, so the
		# reservoir is topped up again afterwards.
		and QiProbe.fill_and_refine(hero, seed)
		and QiProbe.stock(hero, seed.breakthrough_item, 8)
	)
	return ready


## A prepared body hero whose first roll decides the way `winning` asks.
##
## The chance is read off the COMMITTED attempt rather than recomputed, because the
## number a roll is judged against is the one stored at commit — the same rule
## `resolve_attempt`'s own note states about an attempt that spans a save. The
## commit is then CANCELLED so the search spends no pill and leaves no record: the
## attempt under test must start from state the search did not consume.
func _body_roll(hero: Actor, winning: bool) -> RandomNumberGenerator:
	var target := RealmDefaults.ladder().next(hero.path(BodyPath.PATH_ID).rank_id)
	if target == null:
		return null
	BodyFixture.prepare(hero)
	var committed := BodyAdvancement.start_attempt(hero, null)
	if committed == null:
		return null
	var chance := float(committed.preparation.get("chance", 0.0))
	BodyAdvancement.cancel(hero)
	BodyFixture.prepare(hero)
	return _seed_deciding(chance, winning)


## A prepared mind hero whose first roll decides the way `winning` asks. The chance
## is the one `preview` publishes, which is exactly the roll's own input.
func _mind_roll(hero: Actor, winning: bool) -> RandomNumberGenerator:
	if _prepare_mind(hero).is_empty():
		return null
	var chance := float(MindAdvancement.preview(hero).get("chance", 0.0))
	return _seed_deciding(chance, winning)


## The smallest seed in `1..SEED_CAP` whose first draw decides the way `winning`
## asks, or null when none does. Null names the condition rather than looping, and
## every caller asserts on it so a model that cannot be rolled never reads as green.
func _seed_deciding(chance: float, winning: bool) -> RandomNumberGenerator:
	for candidate in range(1, SEED_CAP):
		var probe := _rng(candidate)
		if (probe.randf() < chance) == winning:
			return probe
	return null


## Bring a mind hero to the brink of its next realm, mirroring
## `test_breakthrough_attempt.gd::_prepare` step for step so the prepared state is the
## one that suite already proves a player can produce.
func _prepare_mind(hero: Actor) -> MindRealmSeed:
	var state := hero.path(MindPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var target_seed := MindRealmSeed.for_realm(target.id)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	if target_seed == null or source_seed == null:
		return null
	hero.meridians.unlock_for_realm(target.id)
	_stock(hero, target_seed.breakthrough_item)
	_stock(hero, source_seed.training_item)
	_stock(hero, source_seed.sea_catalyst)
	_stock(hero, source_seed.recovery_item)
	if not MindProbe.train_channels(hero, source_seed):
		return null
	MindTraining.strengthen_sea(hero)
	if not MindProbe.calm_sea(hero) or not MindProbe.sharpen_sea(hero):
		return null
	if not MindProbe.earn_gate(hero, target_seed) or not MindProbe.fill_sea(hero):
		return null
	_stock(hero, target_seed.breakthrough_item)
	return target_seed


## An authored item into the bag, resolved through the production reader so the real
## `max_stack`/`stackable` apply and a realm whose content does not exist fails here
## rather than passing on a fabricated stub.
func _stock(hero: Actor, def_id: StringName) -> void:
	if def_id == &"":
		return
	var def := Crafting.resolve(def_id)
	if def != null:
		ItemsApi.inventory(hero).add(def, 1)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## The `source` recorded against `fate_id` on `hero`'s ledger, or `""`. Read through
## `DestinyApi.state`, the save seam, never `actor.module_data`.
func _source_of(hero: Actor, fate_id: StringName) -> String:
	var fates := DestinyApi.state(hero)["fates"] as Dictionary
	return String((fates.get(String(fate_id), {}) as Dictionary).get("source", ""))


## The `sequence` the ledger stamped `fate_id` with; re-earning leaves it untouched,
## which is how "paid twice" is told from "paid once".
func _sequence_of(hero: Actor, fate_id: StringName) -> int:
	var fates := DestinyApi.state(hero)["fates"] as Dictionary
	return int((fates.get(String(fate_id), {}) as Dictionary).get("sequence", 0))


## `tools/arch/registry.json`'s module map, read through `res://../` because the file
## sits outside `game/`, which is what `res://` points at.
func _modules() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://../tools/arch/registry.json")
	)
	assert_eq(parsed is Dictionary, true, "tools/arch/registry.json is readable JSON")
	return {} if not (parsed is Dictionary) else (parsed as Dictionary)["modules"] as Dictionary


## Every `.gd` under `game/src/modules/<name>/`.
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
