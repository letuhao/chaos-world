extends TestCase

## ADR 0029: a mind breakthrough attempt is persisted, and the Mind system's own
## state (sea, reservoir, channels, path, attempt) survives an Actor save/load
## round trip. `Actor` serializes the attempt as raw data — core never imports a
## module class — and `SCHEMA_VERSION` dispatches what an older payload carries.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")


func _actor() -> Actor:
	var actor := Actor.new(
		&"persist_hero", {Stat.COMPREHENSION: 40.0, MindStats.SEA_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 200)
	MindTraining.synchronize(actor)
	return actor


func _stock(actor: Actor, def_id: StringName) -> void:
	var def := ItemDef.new()
	def.id = def_id
	def.stackable = true
	def.max_stack = 99
	ItemsApi.inventory(actor).add(def, 1)


## Bring the actor to the brink of the next realm so an attempt can start.
##
## No drain and no hand-written progress: a state the fixture can only reach by
## reaching behind the module proves nothing about a persisted mid-attempt actor.
func _prepare(actor: Actor) -> MindRealmSeed:
	var state := actor.path(MindPath.PATH_ID)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var target_seed := MindRealmSeed.for_realm(target.id)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	if target_seed == null or source_seed == null:
		return null
	actor.meridians.unlock_for_realm(target.id)
	_stock(actor, target_seed.breakthrough_item)
	_stock(actor, source_seed.training_item)
	_stock(actor, source_seed.sea_catalyst)
	assert_eq(
		Probe.train_channels(actor, source_seed), true, "channels trained in %s" % state.rank_id
	)
	MindTraining.strengthen_sea(actor)
	assert_eq(Probe.calm_sea(actor), true, "sea calm in %s" % state.rank_id)
	assert_eq(Probe.sharpen_sea(actor), true, "sea sharpened in %s" % state.rank_id)
	assert_eq(Probe.earn_gate(actor, target_seed), true, "progress earned for %s" % target.id)
	assert_eq(Probe.fill_sea(actor), true, "sea filled for %s" % target.id)
	return target_seed


## A seed whose first draw wins the evaluated chance.
##
## Arithmetic over `MindAttemptRoll.replay` — the generator `resolve_attempt` itself
## builds — rather than a full prepare-and-resolve per candidate. Preparation was
## identical for every probe, so the roll was always the only variable; asking the
## helper directly asks the same question without rebuilding a hero 63 times.
func _winning_seed() -> int:
	var probe := _actor()
	if _prepare(probe) == null:
		return 0
	var chance := float(MindAdvancement.preview(probe).get("chance", 0.0))
	for candidate in range(MindAttemptRoll.MIN_SEED, 256):
		if MindAttemptRoll.replay(candidate).randf() < chance:
			return candidate
	return 0


## An actor mid-attempt, with sea, reservoir, channel, and path state that is
## distinctive enough to catch a payload key that is silently dropped.
func _mid_attempt() -> Actor:
	var actor := _actor()
	assert_ne(_prepare(actor), null, "prepared")
	var rng := RandomNumberGenerator.new()
	rng.seed = _winning_seed()
	var started := MindAdvancement.start(actor, rng)
	assert_ne(started, null, "attempt started")
	var sea := MindCultivationApi.sea(actor)
	sea.set_tier(SeaOfConsciousness.DEEP)
	sea.set_clarity(0.62)
	sea.set_purity(0.58)
	sea.add_turbulence(0.25)
	sea.set_structural_capacity(137.5)
	sea.trained_stage = 2
	var pool := actor.resource(MindStats.MIND_POWER)
	pool.change(42.5 - pool.current)
	var channel := actor.meridians.get_meridian(&"lung")
	channel.refinement = 3
	actor.meridians.damage_meridian(&"stomach")
	actor.path(MindPath.PATH_ID).progress = 42.25
	return actor


# --- Round trip -------------------------------------------------------------


func test_full_round_trip_preserves_mind_state() -> void:
	var actor := _mid_attempt()
	var attempt := MindAdvancement.attempt(actor)
	assert_ne(attempt == null, true, "an attempt is in flight")
	var payload := actor.to_dict()
	assert_eq(payload.get("version"), Actor.SCHEMA_VERSION, "payload carries the current version")
	assert_eq(
		payload.get("mind_attempt").get("attempt_id"),
		String(attempt.attempt_id),
		"attempt is in the payload"
	)
	var restored := Actor.from_dict(payload)

	var sea := MindCultivationApi.sea(restored)
	assert_ne(sea == null, true, "sea restored")
	assert_eq(sea.tier, SeaOfConsciousness.DEEP, "sea tier preserved")
	assert_almost_eq(sea.clarity, 0.62, "clarity preserved")
	assert_almost_eq(sea.purity, 0.58, "purity preserved")
	assert_almost_eq(sea.turbulence, 0.25, "turbulence preserved")
	assert_almost_eq(sea.structural_capacity, 137.5, "structural capacity preserved")
	assert_eq(sea.trained_stage, 2, "trained stage preserved")

	var pool := actor.resource(MindStats.MIND_POWER)
	assert_almost_eq(
		restored.resource(MindStats.MIND_POWER).current, 42.5, "stored mind power preserved"
	)
	assert_almost_eq(
		restored.resource(MindStats.MIND_POWER).maximum, pool.maximum, "reservoir size preserved"
	)

	var lung := restored.meridians.get_meridian(&"lung")
	assert_eq(lung.state, MeridianState.STRENGTHENED, "channel state preserved")
	assert_eq(lung.refinement, 3, "channel refinement preserved")
	assert_eq(lung.is_injured(), false, "healthy channel stayed healthy")
	assert_eq(restored.meridians.get_meridian(&"stomach").is_injured(), true, "injury preserved")

	assert_eq(restored.path(MindPath.PATH_ID).rank_id, &"qi_refining", "rank preserved")
	assert_almost_eq(restored.path(MindPath.PATH_ID).progress, 42.25, "progress preserved")

	var reloaded := MindAdvancement.attempt(restored)
	assert_ne(reloaded == null, true, "attempt restored")
	assert_eq(reloaded.attempt_id, attempt.attempt_id, "attempt id preserved")
	assert_eq(reloaded.status, MindAttempt.STATUS_COMMITTED, "attempt still active")
	assert_eq(reloaded.target_rank, attempt.target_rank, "attempt target preserved")
	assert_eq(reloaded.pill_consumed, true, "the spent pill is still recorded")
	assert_eq(MindAdvancement.active_attempt(restored) == null, false, "still resolvable")


func test_restored_actor_can_resolve_the_loaded_attempt() -> void:
	var actor := _mid_attempt()
	var restored := Actor.from_dict(actor.to_dict())
	MindCultivationApi.attach(restored)
	ItemsApi.attach(restored)
	MindTraining.synchronize(restored)
	var committed := MindAdvancement.active_attempt(restored)
	assert_ne(committed == null, true, "the loaded attempt is active")
	# The attempt was committed against its own preparation, so the stored chance
	# decides it, not whatever the reloaded sea looks like now.
	assert_eq(
		float(committed.preparation.get("chance")) > 0.0, true, "the chance travelled with it"
	)
	# No generator is handed in: the roll comes out of the record, which is the
	# property under test. This used to rebuild a generator FROM `rng_state` and
	# pass it in, which agreed with the record by construction and so could not
	# tell a resolve that reads the record from one that was handed a stream.
	assert_eq(
		MindAdvancement.resolve_attempt(restored),
		(
			MindAttemptRoll.replay(committed.rng_state).randf()
			< float(committed.preparation.get("chance"))
		),
		"the loaded attempt resolved on the roll its own record names"
	)
	assert_eq(restored.path(MindPath.PATH_ID).rank_id, &"foundation", "advanced once")


func test_a_legacy_v2_payload_loads_with_defaults() -> void:
	var legacy := {
		"version": 2,
		"id": "legacy_hero",
		"display_name": "Legacy",
		"base": {},
		"paths":
		{
			"mind_cultivation":
			{
				"path_id": "mind_cultivation",
				"rank_id": "qi_refining",
				"stage": 2,
				"progress": 12.5,
				"unlocked": [],
			},
		},
		"meridians": {},
		"resources": {},
	}
	var actor := Actor.from_dict(legacy)
	assert_eq(actor.id, &"legacy_hero", "identity restored")
	assert_eq(actor.path(MindPath.PATH_ID).rank_id, &"qi_refining", "rank restored")
	assert_almost_eq(actor.path(MindPath.PATH_ID).progress, 12.5, "progress restored")
	# v2 carries neither slot, so both load as "absent" rather than as garbage.
	assert_eq(actor.component(&"sea_of_consciousness") == null, true, "no sea from a v2 payload")
	assert_eq(MindAdvancement.attempt(actor) == null, true, "no attempt from a v2 payload")
	assert_eq(MindAdvancement.active_attempt(actor) == null, true, "nothing to resolve")
	assert_eq(MindAdvancement.start(actor) == null, true, "no sea, no attempt to start")
	# Re-attaching the module gives a sane sea instead of a half-built one.
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	MindTraining.synchronize(actor)
	var sea := MindCultivationApi.sea(actor)
	assert_eq(sea.tier, SeaOfConsciousness.SHALLOW, "default sea tier")
	assert_almost_eq(sea.turbulence, 0.0, "default turbulence")
	assert_almost_eq(sea.clarity, 0.5, "default clarity")
	assert_eq(sea.structural_capacity > 0.0, true, "capacity derived from the realm seed")


func test_a_v3_payload_keeps_its_sea_and_has_no_attempt() -> void:
	var actor := _mid_attempt()
	var payload := actor.to_dict()
	payload["version"] = 3
	payload["mind_attempt"] = {}
	var restored := Actor.from_dict(payload)
	var sea := MindCultivationApi.sea(restored)
	assert_ne(sea == null, true, "v3 sea restored")
	assert_almost_eq(sea.structural_capacity, 137.5, "v3 sea values preserved")
	assert_eq(MindAdvancement.attempt(restored) == null, true, "no attempt to restore")


## The attempt rides in its own versioned payload slot and is written EXACTLY once.
## `Actor.to_dict` copies `module_data` key by key, so an attempt left in there as
## well would be serialized twice. Two copies is not merely untidy: `from_dict`
## restores `module_data` unconditionally and only then applies the versioned
## slots, so the copy outside the slot would silently win and a v3 load would
## resurrect an attempt the schema says it does not carry.
func test_the_attempt_is_serialized_exactly_once() -> void:
	var actor := _mid_attempt()
	var payload := actor.to_dict()
	var attempt := MindAdvancement.attempt(actor)
	assert_ne(attempt == null, true, "an attempt is in flight")
	# In the versioned slot...
	assert_ne(
		payload.get("mind_attempt", {}).get("attempt_id"),
		"",
		"the attempt rides its own payload slot"
	)
	# ...and NOT also in the generic module_data bag.
	var module_data: Dictionary = payload.get("module_data", {})
	assert_eq(
		module_data.has(MindAdvancement.ATTEMPT_KEY),
		false,
		"the attempt is not duplicated into module_data"
	)
	# Exactly one serialized copy in total, and it is the whole record.
	var serialized := payload.get("mind_attempt", {}) as Dictionary
	var complete := attempt.to_dict()
	complete.erase("outcome_granted")
	complete.erase("trial_complete")
	for key in complete.keys():
		assert_eq(serialized.get(key), complete[key], "the single copy carries %s" % key)
	# The two flags the once-only guarantee rides on are present too — a slot
	# missing them would restore an attempt that could be granted a second time.
	assert_eq(
		serialized.get("outcome_granted"),
		attempt.outcome_granted,
		"the outcome flag travels with the record"
	)
	assert_eq(serialized.get("trial_complete"), attempt.trial_complete, "the trial flag travels")
	# A payload rebuilt by hand with the slot removed carries no attempt at all,
	# which is what makes the version gate load-bearing rather than decorative.
	var stripped := payload.duplicate(true)
	stripped["mind_attempt"] = {}
	stripped["module_data"] = {}
	var bare := Actor.from_dict(stripped)
	assert_eq(MindAdvancement.attempt(bare) == null, true, "no slot means no attempt")


## The payload version is what gates the slot, so it must be the current one and
## must not drift silently: a save written by an older Actor would otherwise
## carry no attempt and reopen a slot that was already spent.
func test_the_payload_version_is_the_current_schema() -> void:
	var actor := _mid_attempt()
	assert_eq(actor.to_dict().get("version"), Actor.SCHEMA_VERSION, "current version")
	# The attempt slot arrived in v4 and must keep round-tripping whatever the schema has
	# moved on to since (ADR 0140 bumped it to 5 for wounds). Asserting the literal 4 here
	# would pin the whole schema to the mind path's addition, which is not what this test
	# is about — the attempt's durability is.
	assert_eq(Actor.SCHEMA_VERSION >= 4, true, "the schema still carries the attempt slot")
	var slot: Variant = actor.to_dict().get("mind_attempt", {})
	assert_eq(slot is Dictionary and not (slot as Dictionary).is_empty(), true, "and it is present")
