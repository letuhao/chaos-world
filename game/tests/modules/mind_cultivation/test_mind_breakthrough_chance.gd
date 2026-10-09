extends TestCase

## Shared fixtures for the Mind path: bounded, production-action setup. Named to
## sit outside the `test_*` discovery pattern, so the runner ignores it.
const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## ADR 0028's defect class, audited on the Mind path. `BodyAdvancement` refused
## to read `Stat.BREAKTHROUGH_CHANCE` because comprehension drives that stat and
## comprehension is the body path's entry GATE, so the gate's own floor made the
## roll certain. The Mind path has the same gate on the same stat and read the
## same stat, so the same thing happened one path over: at attempt time the roll
## evaluated above the 0.95 clamp at R4->R5 and stayed pinned there for the
## remaining 25 transitions. `_deviate`, the recoverable-deviation loop, and the
## ADR 0031 recovery item were unreachable content above R4.
##
## A roll that preparation alone decides is not a roll. These tests pin the rule
## the body path established: the chance reads the sea's clarity and nothing the
## entry gate has already pinned.
##
## Every expectation is DERIVED from the code under test — the clamp and the floor
## from `MindAdvancement`, the legal clarity ceiling from the realm's own seed and
## the sea's own clamp, and the comprehension sweep from the seed's gate floor. No
## pasted literal but the comprehension multipliers, which are sweep positions.

## The strongest legal reading of the gate's comprehension floor, and two steps
## past it. The gate only demands `>=`, so both are pre-states a player may hold.
const GATE_FLOOR := 1.0
const ONE_STEP_PAST := 2.0

## How many cultivate steps preparing one realm may take. Replaces the 4096/8192
## caps this file used to carry: a cap that large does not prevent the runaway,
## it only makes it write gigabytes before stopping. Sized above the deepest
## authored work budget (heaven_immortal progress_required 7148) divided by what
## one 500.0 cultivate is worth, with slack — a ceiling on failure, not a licence
## to spin (AGENTS.md disk-safety).
const CULTIVATE_STEP_CAP := 2048


func _actor_at(rank_id: StringName) -> Actor:
	var actor := Actor.new(&"chance_hero", {Stat.COMPREHENSION: 0.0})
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	actor.meridians.unlock_for_realm(rank_id)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	MindTraining.synchronize(actor)
	# BL-0951: a fixture standing at `rank_id` implies it LEFT every realm below it; backfill
	# the history a real climb would have snapshotted, or the foundation wall refuses.
	Probe.backfill_foundation(actor)
	return actor


## The evaluated chance at `rank_id` for a pre-state holding `comprehension_multiple`
## times the entry gate's own floor. Clarity defaults to the highest value legal
## while standing in that realm: `MindTraining.cultivate` caps it at the CURRENT
## realm's `clarity_required` and `SeaOfConsciousness.set_clarity` clamps to 1.0,
## so the seed value is the ceiling and a negative multiple reads as no
## preparation at all.
func _chance_at(
	rank_id: StringName, comprehension_multiple: float, clarity_multiple: float = 1.0
) -> float:
	var source_seed := MindRealmSeed.for_realm(rank_id)
	var actor := _actor_at(rank_id)
	var ceiling := minf(1.0, source_seed.clarity_required)
	var sea := MindCultivationApi.sea(actor)
	if clarity_multiple < 0.0:
		sea.set_clarity(0.0)
	else:
		sea.set_clarity(ceiling * clarity_multiple)
	actor.stats.set_base(
		Stat.COMPREHENSION, source_seed.comprehension_required * comprehension_multiple
	)
	actor.mark_stats_dirty()
	return float(MindAdvancement.preview(actor).get("chance", -1.0))


# --- The clamp is never reached from a legal pre-state -----------------------


## Every boundary on the ladder, not just the ends: a regression that reintroduces
## a gate-fed term only bites where that gate's floor is low enough to matter.
func test_no_boundary_evaluates_the_roll_as_certain() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		var target: RealmDef = ladder.next(realm.id)
		if target == null:
			continue
		audited += 1
		for multiple: float in [GATE_FLOOR, ONE_STEP_PAST]:
			var chance := _chance_at(realm.id, multiple)
			assert_eq(
				chance < MindAdvancement.MAX_CHANCE,
				true,
				(
					"%s -> %s roll %s stays under certainty at x%s comprehension"
					% [realm.id, target.id, chance, multiple]
				)
			)
			assert_eq(
				chance > MindAdvancement.MIN_CHANCE,
				true,
				"%s -> %s roll %s stays above the floor" % [realm.id, target.id, chance]
			)
	assert_eq(audited, 29, "every boundary on the ladder was audited")


## The gate's floor is not a difficulty curve. Holding more comprehension than the
## gate demands must not move the roll, or the requirement converts preparation
## into certainty.
func test_preparing_past_the_gate_does_not_move_the_roll() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		if ladder.next(realm.id) == null:
			continue
		audited += 1
		assert_almost_eq(
			_chance_at(realm.id, ONE_STEP_PAST),
			_chance_at(realm.id, GATE_FLOOR),
			"the roll ignores comprehension past the gate at %s" % realm.id,
			0.0001
		)
	assert_eq(audited, 29, "every boundary on the ladder was audited")


## Clarity is the one input, and it is preparation quality, so it does move the
## roll. Without this the invariance above would also be satisfied by a constant.
func test_clarity_is_the_chances_one_input() -> void:
	var source := &"qi_refining"
	var prepared := _chance_at(source, GATE_FLOOR)
	var raw := _chance_at(source, GATE_FLOOR, -1.0)
	assert_eq(prepared > raw, true, "a sharpened sea raises the roll")
	# The spread is the whole legal clarity range times the authored weight, and
	# neither end is clamped away at this realm.
	var seed := MindRealmSeed.for_realm(source)
	assert_almost_eq(
		prepared - raw,
		minf(1.0, seed.clarity_required) * MindAdvancement.CLARITY_TO_CHANCE,
		"the spread is the legal clarity range times its authored weight",
		0.0001
	)
	assert_almost_eq(raw, MindAdvancement.MIN_CHANCE, "an unprepared sea sits on the floor", 0.0001)


# --- A real deviation is reachable where the defect began -------------------


func _stock(actor: Actor, def_id: StringName) -> void:
	Probe.stock(actor, def_id)


## A fully prepared actor standing in `rank_id`, reached only through the
## production actions — the same legal pre-state the traversal prepares, and for
## the same reason it may not drain the sea or hand-write progress.
func _prepared_actor(rank_id: StringName) -> Actor:
	var actor := _actor_at(rank_id)
	ItemsApi.attach(actor, 500)
	var state := actor.path(MindPath.PATH_ID)
	var target := RealmDefaults.ladder().next(rank_id)
	var source_seed := MindRealmSeed.for_realm(rank_id)
	var target_seed := MindRealmSeed.for_realm(target.id)
	_stock(actor, source_seed.sea_catalyst)
	MindTraining.strengthen_sea(actor)
	assert_eq(Probe.train_channels(actor, source_seed), true, "channels trained in %s" % rank_id)
	assert_eq(Probe.calm_sea(actor), true, "sea calm in %s" % rank_id)
	assert_eq(Probe.sharpen_sea(actor), true, "sea sharpened in %s" % rank_id)
	assert_eq(Probe.earn_gate(actor, target_seed), true, "progress earned for %s" % target.id)
	assert_eq(Probe.fill_sea(actor), true, "sea filled for %s" % target.id)
	_stock(actor, target_seed.breakthrough_item)
	return actor


## R4->R5 is where the gate-fed roll first evaluated above the certainty clamp. A
## deviation has to be rollable there in practice, not merely possible in theory,
## or the whole recovery loop is unreachable content at every realm above it.
## A trial that is never lost is not a trial. At the boundary where the defect
## began, some seed must produce a deviation — searched deterministically, never
## hoped for, exactly as the other attempt tests do.
func _losing_seed_at(source: StringName) -> int:
	var probe := _prepared_actor(source)
	var chance := float(MindAdvancement.preview(probe).get("chance", -1.0))
	for candidate in range(MindAttemptRoll.MIN_SEED, 256):
		if MindAttemptRoll.replay(candidate).randf() >= chance:
			return candidate
	return 0


func test_a_deviation_is_rollable_where_the_defect_began() -> void:
	var source := &"spirit_transformation"
	var target_seed := MindRealmSeed.for_realm(RealmDefaults.ladder().next(source).id)
	var probe := _prepared_actor(source)
	var chance := float(MindAdvancement.preview(probe).get("chance", -1.0))
	assert_eq(
		chance < MindAdvancement.MAX_CHANCE,
		true,
		"R4 -> R5 evaluates at %s, under certainty" % chance
	)

	var losing_seed := _losing_seed_at(source)
	assert_ne(losing_seed, 0, "a losing roll exists at R4 -> R5")

	var actor := _prepared_actor(source)
	_stock(actor, target_seed.breakthrough_item)
	var rng := RandomNumberGenerator.new()
	rng.seed = losing_seed
	assert_ne(MindAdvancement.start(actor, rng), null, "attempt started")
	assert_eq(MindAdvancement.resolve_attempt(actor), false, "the trial deviated")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, source, "the deviation kept the realm")
	assert_eq(MindCultivationApi.sea(actor).turbulence > 0.0, true, "the deviation clouded the sea")
	# And the deviation is recoverable here, so the loop closes at this depth.
	var burned := &""
	for meridian_id in target_seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel != null and channel.is_injured():
			burned = meridian_id
			break
	assert_ne(burned, &"", "a channel burned")
	_stock(actor, MindRealmSeed.for_realm(source).recovery_item)
	assert_eq(MindTraining.recover(actor, burned), true, "recovered at the same realm")
	assert_eq(MindCultivationApi.sea(actor).turbulence, 0.0, "sea calmed")


## A cancelled attempt is a separate terminal outcome from a failed one, and it
## must be reachable at the same depth: the slot cannot be stuck full.
func test_cancel_is_reachable_where_the_defect_began() -> void:
	var source := &"spirit_transformation"
	var actor := _prepared_actor(source)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	assert_ne(MindAdvancement.start(actor, rng), null, "attempt started")
	assert_eq(MindAdvancement.cancel(actor), true, "cancelled")
	assert_eq(MindAdvancement.attempt(actor).status, MindAttempt.STATUS_CANCELLED, "recorded")
	assert_eq(
		MindCultivationApi.sea(actor).turbulence,
		0.0,
		"no deviation was owed, so the sea is untouched"
	)
