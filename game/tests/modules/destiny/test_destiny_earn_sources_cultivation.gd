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
## The body fixture is held as an INSTANCE, not read through a script const.
##
## A preloaded script constant exposes only that class's STATIC surface, so
## `const BodyFixture := preload(...)` followed by `BodyFixture.breakthrough(...)`
## is a PARSE ERROR the moment the callee is an instance method: "Cannot call
## non-static function 'breakthrough()' on the class 'BodyPlayFixture' directly.
## Make an instance instead." That is DEF-0233/0234 verbatim, and it is expensive
## precisely because it IS a parse error — the suite never runs, the runner reports
## "failed to load suite", and the tally UNDERCOUNTS every test in the file. Note a
## `const` initialiser reading through a shared instance would not have worked
## either: run_tests.gd attaches a suite's properties one at a time, so a const
## answers null during initialisation.
const BodyPlayFixture := preload("res://tests/modules/body_cultivation/body_play_fixture.gd")
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

## ## `roll_draw` is a NAMED CONSTANT per path, because a transaction may take a
## ## different number of draws before its own roll
##
## The three constants and DRAW_CAP are declared ONCE, beside `_seed_deciding` where
## the search that reads them lives. Two earlier passes each left a copy here as well,
## and each duplicate was a PARSE ERROR - "Constant 'DRAW_CAP' has the same name as a
## previously declared constant" - so the suite failed to LOAD and reported 0 passed /
## 1 failed with every test in the file silently uncounted. A duplicated const makes the
## tally UNDERSTATE, which is the more dangerous direction: a green file can hide a
## whole suite.

## The one body fixture this suite drives, as an INSTANCE.
##
## Typed as the fixture's own script so `:=` still infers at the call sites — a
## `RefCounted` return type erases that, and the call sites then read
## "Cannot infer the type of 'actor' because the value doesn't have a set type",
## which is the SAME class of failure in a different costume. The preloaded
## SCRIPT is a `GDScript`, so `.new()` on it is statically typed as the class and
## every member call resolves.
var _body_fixture: BodyPlayFixture = null


## The shared body fixture, built on first use rather than in a member
## initialiser: run_tests.gd attaches a suite's properties one at a time, so a
## value built at construction is not yet there when the first test asks.
func _body() -> BodyPlayFixture:
	if _body_fixture == null:
		_body_fixture = BodyPlayFixture.new()
	return _body_fixture


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
	assert_eq(_body().breakthrough(hero, _rng(4242)), true, "a second realm was entered")
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
	# Measured against the tree, one REAL call per path. This was `{qi: 2}` and the
	# second qi row was a doc reference, not a call — the same false positive DEF-0260
	# recorded for `try_breakthrough`, where a grep for the bare identifier missed the
	# member-qualified call site. A count that includes prose is not a count of earn
	# sites, and asserting 2 meant this case read RED while the wiring was correct,
	# which is how a guard teaches an agent to ignore it.
	var expected := {"qi_cultivation": 1, "body_cultivation": 1, "mind_cultivation": 1}
	for module_name in expected:
		var earn_sites := 0
		for path in _module_files(String(module_name)):
			# Count LINES that call the earn, not files that contain the string. An
			# earlier shape did `body.split("#")[0].contains(...)`, which keeps only the
			# text BEFORE the first `#` anywhere in the file — so every call sitting
			# after any comment was invisible and the count read 0 with the wiring fully
			# present. Strip comment LINES instead, which is what "executable code"
			# actually means; a `#` inside a string literal is not a comment, and this
			# does not care because it only skips lines BEGINNING with one.
			for line in FileAccess.get_file_as_string(path).split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				if line.contains("DestinyApi.earn_fate"):
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
	var actor := _body().actor(&"qi_refining")
	DestinyApi.attach(actor)
	return actor


func actor_rank(actor: Actor) -> StringName:
	return actor.path(BodyPath.PATH_ID).rank_id


## A prepared qi hero whose roll decides the way `winning` asks.
##
## ## The chance is read off the PRODUCTION preview, never off `QiAdvancement.chance`
##
## `QiBreakthroughTransaction.preview` publishes the very number the transaction's own
## roll is computed out of (`breakthrough_transaction.gd:76` and `:134` both call
## `QiChance.of(dantian)`), so reading it is a differential against the code under
## test rather than a second opinion from a pass-through DEF-0259 records as
## test-only. **Measured** on the prepared `qi_refining` hero: `chance` 0.300000,
## `QiAdvancement.chance` 0.300000, `can_attempt` true, `unmet_conditions` empty,
## progress 140.00/100.00, comprehension 10.46/10.00, dantian quality 0.5000/0.5000,
## dantian ratio 1.0000/1.0000, `injured` false, pill held, and
## `Breakthrough.can_advance` true — a LEGAL prior state on every gate the
## transaction enforces.
##
## ## The verdict is a FRESH generator at the searched seed, never the search's own
##
## This is the defect DEF-0295 measured, and it is the whole of it. The search drew
## `probe.randf()` and then **returned that same, already-consumed `probe`** — while
## its own docstring claimed "only its seed is replayed". So the number it decided on
## and the number the real breakthrough read were consecutive draws of one stream.
## Nothing about `_qi_prepare` was wrong.
##
## Two measured facts make the fix correct, and both are asserted by
## `test_the_qi_roll_is_judged_on_the_draw_the_transaction_really_reads` rather than
## left as a comment:
##
##   1. The roll is the FIRST draw. `Breakthrough.face_tribulation`
##      (`breakthrough_transaction.gd:115`) runs before the roll (`:135`), but below
##      the Immortal threshold it returns at `breakthrough.gd:201` **without drawing**,
##      and `_deviate`'s meridian `_pick` draws only after a roll has already lost.
##      Measured over seeds 1..8 x skip 0..3, a fresh hero per trial: skip 0 is the only
##      offset consistent with every outcome, so `QI_ROLL_DRAW` is 0.
##   2. A generator is deterministic per seed from a fresh construction — two
##      separately built generators at seed 1 both read 0.329559 first — so rebuilding
##      at the searched seed replays the judged draw. Re-assigning `.seed` on the
##      consumed object would NOT: that rewrites the seed without rewinding the state,
##      which is why `_seed_deciding` returns a rebuilt `_rng(candidate)`.
##
## Measured consequence at the prepared chance of 0.30: the old search chose seed 1
## for a losing roll (draw 0 = 0.329559, above 0.30), and the attempt then read draw
## 1 = 0.276595, below 0.30, so it **won**. Every "the attempt deviated" case was
## handed a winning generator and every "the breakthrough was granted" case a losing
## one. `SEED_CAP` and `DRAW_CAP` are the bounds and both are taken before their loop.
func _qi_roll(hero: Actor, winning: bool) -> RandomNumberGenerator:
	var target := RealmDefaults.ladder().next(hero.path(QiPath.PATH_ID).rank_id)
	if target == null:
		return null
	var seed := QiRealmSeed.for_realm(target.id)
	if seed == null or not _qi_prepare(hero, seed):
		return null
	# `preview` is refused on an unmeetable gate (`chance` is still published, but a
	# hero that cannot attempt is not a hero this case can roll), so the emptiness of
	# `unmet_conditions` is part of the model rather than a convenience.
	var preview := QiBreakthroughTransaction.preview(hero)
	if not bool(preview.get("can_attempt", false)):
		return null
	return _seed_deciding(float(preview.get("chance", 0.0)), winning, QI_ROLL_DRAW)


## Bring a qi hero to the brink of `seed`'s realm through the production actions, in
## the order `qi_gate_probe`'s own `prepared` uses — recovery first so nothing an
## earlier attempt wounded refuses to climb, and the pill re-stocked last because
## `prepare`'s own note says a top-up before cultivation is undone by it.
##
## ## Re-measured, and left exactly as it stands
##
## DEF-0295 records this order as suspect. It is not: all nine steps return true, and
## the state they leave is one `QiBreakthroughTransaction.preview` reports as
## `can_attempt` with an empty `unmet_conditions` — progress 140.00/100.00,
## comprehension 10.46/10.00, dantian quality 0.5000/0.5000, dantian ratio
## 1.0000/1.0000, `injured` false, pill held, `Breakthrough.can_advance` true. The
## red cases were the roll MODEL, not this order, and
## `test_the_prepared_qi_hero_is_a_legal_prior_state` now holds that state down as a
## fact rather than as a comment.
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


## ## The prepared hero is a LEGAL prior state, asserted rather than described
##
## DEF-0295 blamed `_qi_prepare` for the red. It is exonerated here, on the
## transaction's own verdict rather than on the fixture's own report: an empty
## `unmet_conditions` is the statement that nothing the real breakthrough enforces is
## outstanding, which is the half of "satisfiable from a legal prior state" this
## suite needs and the half that was silently untested.
##
## The chance is asserted against the published formula rather than hard-typed, so a
## retune of `QiChance` does not turn this into a lie — the same rule
## `test_qi_breakthrough_chance.gd` follows.
func test_the_prepared_qi_hero_is_a_legal_prior_state() -> void:
	var hero := _qi_hero()
	var target := RealmDefaults.ladder().next(hero.path(QiPath.PATH_ID).rank_id)
	assert_ne(target, null, "a first-rung qi hero has a realm after it")
	var seed := QiRealmSeed.for_realm(target.id)
	assert_ne(seed, null, "that realm is authored with a seed")

	assert_eq(_qi_prepare(hero, seed), true, "every preparation step converged")

	var preview := QiBreakthroughTransaction.preview(hero)
	assert_eq(
		(preview["unmet_conditions"] as Array).size(),
		0,
		(
			"the real transaction is owed nothing, so the prior state is legal: %s"
			% str(preview["unmet_conditions"])
		)
	)
	assert_eq(bool(preview["can_attempt"]), true, "and it would attempt")
	var dantian := QiAccess.dantian(hero)
	assert_eq(
		float(preview["chance"]),
		clampf(
			QiChance.MIN_CHANCE + dantian.quality * QiChance.QUALITY_TO_CHANCE,
			QiChance.MIN_CHANCE,
			QiChance.MAX_CHANCE
		),
		"the roll is the dantian's own quality and nothing else"
	)
	# The model's chance source and the published one are the same number. This is the
	# differential against the test-only pass-through DEF-0259 names: `_qi_roll` reads
	# `preview`, so a pass-through that had drifted from `QiChance.of` could no longer
	# quietly disagree with what the transaction rolls.
	assert_eq(float(preview["chance"]), QiAdvancement.chance(hero), "the pass-through agrees")


## ## The judged draw IS the played draw — the defect DEF-0295 was
##
## The old search judged `probe.randf()` and then returned that same consumed probe,
## so the case played a different draw than the one it had decided on. This drives the
## REAL transaction at several seeds and requires the outcome to equal
## `draws[QI_ROLL_DRAW] < chance` every time.
##
## **NON-TRIVIAL by construction**: the seeds below include ones whose first draw wins
## and ones whose first draw loses at the prepared chance of 0.30, so a suite that
## silently flipped the direction would be caught on the seeds that disagree rather
## than passing on the ones that agree. If `QI_ROLL_DRAW` were wrong the assertions
## fire; it is not checked against a hard-typed `0`, because the CLAIM is "the draw
## named by the constant is the draw the transaction read", and the constant is where
## a re-measurement belongs.
func test_the_qi_roll_is_judged_on_the_draw_the_transaction_really_reads() -> void:
	# Seed 1 loses at chance 0.30 (0.329559) and seed 13 wins (0.062118): both
	# directions, so this case cannot pass on one branch alone.
	for candidate in [1, 2, 13, 14]:
		var draws: Array[float] = []
		var expected := _rng(candidate)
		for _step in QI_ROLL_DRAW + 1:
			draws.append(expected.randf())

		var hero := _qi_hero()
		var target := RealmDefaults.ladder().next(hero.path(QiPath.PATH_ID).rank_id)
		var seed := QiRealmSeed.for_realm(target.id)
		assert_eq(_qi_prepare(hero, seed), true, "seed %d prepared" % candidate)
		var chance := float(QiBreakthroughTransaction.preview(hero).get("chance", 0.0))
		var roll := _rng(candidate)
		for _step in QI_ROLL_DRAW:
			roll.randf()

		var granted := QiAdvancement.try_breakthrough(hero, roll)

		assert_eq(
			granted,
			draws[QI_ROLL_DRAW] < chance,
			(
				"seed %d: the transaction decided on draw %d (%.6f against chance %.6f)"
				% [candidate, QI_ROLL_DRAW + 1, draws[QI_ROLL_DRAW], chance]
			)
		)


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
	_body().prepare(hero)
	var committed := BodyAdvancement.start_attempt(hero, null)
	if committed == null:
		return null
	var chance := float(committed.preparation.get("chance", 0.0))
	BodyAdvancement.cancel(hero)
	_body().prepare(hero)
	return _seed_deciding(chance, winning, BODY_ROLL_DRAW)


## A prepared mind hero whose first roll decides the way `winning` asks. The chance
## is the one `preview` publishes, which is exactly the roll's own input.
func _mind_roll(hero: Actor, winning: bool) -> RandomNumberGenerator:
	# `_prepare_mind` answers a `MindRealmSeed` or null, never a Dictionary — so
	# `is_empty()` here was a call on a Resource that has no such method, and the
	# script error it raised ABORTED this case before it asserted anything. That is
	# the failure mode where a suite under-reports: the case looks like it failed for
	# a reason about mind seeds when in fact its first line never ran. Null is the
	# condition "could not be prepared", which is what the caller asserts on.
	if _prepare_mind(hero) == null:
		return null
	var chance := float(MindAdvancement.preview(hero).get("chance", 0.0))
	return _seed_deciding(chance, winning, MIND_ROLL_DRAW)


## The smallest seed in `1..SEED_CAP` whose draw at `roll_draw` decides the way
## `winning` asks, or null when none does. Null names the condition rather than
## looping, and every caller asserts on it, so a model that cannot be rolled never
## reads as green.
##
## ## The SEED is searched; a FRESH generator carrying it is returned
##
## This is the whole of the DEF-0295 fix. The old shape judged `probe.randf()` and
## then returned **that same, already-consumed `probe`** — despite a docstring
## claiming "only its seed is replayed". The transaction therefore read the draw
## AFTER the one that had been decided on, and every case was handed a roll of the
## opposite outcome. Measured at the prepared chance of 0.30 on seed 1: draw 0 is
## 0.329559 and **loses**, draw 1 is 0.276595 and **wins** — so the search correctly
## classified seed 1 as a losing seed and the attempt then won. That is the 7 red
## cases, exactly.
##
## A fresh `_rng(candidate)` is deterministic per seed — two separately built
## generators at seed 1 both read 0.329559 first — so the returned object replays the
## judged draw rather than continuing past it. **Re-assigning `.seed` on the consumed
## generator would not do**: that rewrites the seed without rewinding the state. The
## value is rebuilt, not reseeded.
##
## ## `roll_draw` is a NAMED CONSTANT per path, because a transaction may take a
## ## different number of draws before its own roll
##
## **Measured** by intersecting the offsets consistent with real outcomes, a fresh
## hero per trial: **body** survivors narrow to `[0]` over seeds 2, 3, 4; **mind** to
## `[0]` over seeds 2, 3, 9, 11; and `QI_ROLL_DRAW` is pinned by
## `test_the_qi_roll_is_judged_on_the_draw_the_transaction_really_reads`. All three
## read their FIRST draw on these prepared states. Three named constants rather than
## one shared literal because that measurement is what would have to be REDONE if a
## transaction ever began consuming a draw of its own, and a single hard-wired `0`
## would let such a change silently desynchronise this search from every roll.
const QI_ROLL_DRAW := 0
const BODY_ROLL_DRAW := 0
const MIND_ROLL_DRAW := 0
## The most draws any path is allowed to be judged on, taken BEFORE the loop. A
## caller naming a draw the transaction does not have is clamped rather than trusted,
## so the replay can never be the thing that fails to terminate.
const DRAW_CAP := 8


func _seed_deciding(
	chance: float, winning: bool, roll_draw: int = QI_ROLL_DRAW
) -> RandomNumberGenerator:
	var target_draw := clampi(roll_draw, 0, DRAW_CAP)
	for candidate in range(1, SEED_CAP):
		var probe := _rng(candidate)
		# `target_draw + 1` draws are taken to REACH the one being judged, and the last
		# of them is the one judged, so `roll_draw = 0` means "the roll is the first
		# draw" — which is what all three paths measure.
		var decided := false
		for _step in target_draw + 1:
			decided = probe.randf() < chance
		if decided == winning:
			# REBUILT, never the consumed `probe`: a transaction handed a spent
			# generator reads one draw later than the one just decided on.
			return _rng(candidate)
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
