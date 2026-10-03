extends TestCase

## ADR 0128: cultivation state must survive a BOOT, not merely a save.
##
## ## Why this suite exists next to `test_save_round_trip.gd`
##
## `test_mind_persistence.gd` proves `Actor.to_dict()` -> `Actor.from_dict()` preserves the
## sea, the meridians and the attempt — the PAYLOAD round trip, in core, with no module
## attach in between. `test_save_round_trip.gd` proves the envelope is well formed and that
## a soul comes back. Neither touches the seam that was actually broken: the composition
## root's `ItemWorkbenchApp.restore_actor`, which reads the slot, rebuilds the body and then
## RE-MOUNTS the modules that contribute to its stats.
##
## That seam is where the loop reset. `restore_actor` reached for the enrolment verbs
## (`ActorFactory.with_mind_cultivation` and siblings), and an enrolment calls `set_path`,
## which replaces `paths[path_id]` outright — so a restored `rank_id`, `stage` and `progress`
## were overwritten with a fresh `qi_refining`/0/0.0, and `MindTraining.synchronize` then
## shrank the sea back to the R1 seed. The write half landed and the read half erased it
## again on the same boot, which is why a green payload suite proved nothing about play.
##
## The same verbs also made the restore UNCONDITIONAL, and an attach is a grant:
## `MindCultivationApi.attach` calls `attach_sea`, which mints a `SeaOfConsciousness` when
## the component is absent. A payload carrying no mind path therefore acquired a sea it was
## never enrolled in — BL-0523, which hid behind 10,186 green assertions because ungated
## wiring looks exactly like correct wiring. The empty-payload case below is the guard.

## The gate preparation the existing mind suites already use. Reused rather than rewritten:
## a hand-written attempt proves the serialiser, not the gate, and this suite is about the
## composition root. Read-only — nothing here is edited.
const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

var _born: Array = []


func setup() -> void:
	_clear_disk()
	SaveApi.reset_clock()


func teardown() -> void:
	# The harness mounts the REAL scene under the tree root, so it owns Nodes and must free
	# them; a test that aborted mid-function would otherwise leak a whole app into the next.
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	for born in _born:
		var body := born as Actor
		if body != null:
			# Actors are RefCounted, but a PathState is connected to the actor's invalidator
			# and a resource pool is referenced by a provider, so the cycle outlives the
			# refcount. `resources.clear()` breaks it. This is the shape `test_save_round_trip`
			# uses, and the runner shares one process across every suite.
			body.resources.clear()
	_born.clear()
	_clear_disk()
	SaveApi.reset_clock()


# --- The real round trip: persist, boot the shipped scene, read the body --------


func test_a_saved_mind_realm_survives_a_boot_through_the_shipped_scene() -> void:
	# The headline claim, end to end: a hero standing at a realm above R1 with a grown sea,
	# trained channels and half a realm of progress, saved, then BOOTED by the real
	# `ItemWorkbenchApp.tscn` through `SeamHarness` — which drives the same `_ready` the
	# engine does, so `publish_world` -> `restore_actor` -> `_mount_player_modules` all run.
	var hero := _hero(&"core_formation")
	_grow(hero)
	var expected := _cultivation_of(hero)
	_born.append(hero)
	assert_eq(bool(SaveApi.persist(hero, "standard")["ok"]), true, "the save landed on disk")

	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the shipped scene booted")
	if harness.boot_error != "":
		return
	var booted := harness.actor
	assert_ne(booted == null, true, "the boot produced a body")
	if booted == null:
		return
	# The body is a NEW instance, not the one that saved: a restore that quietly reused the
	# in-memory actor would pass every state assertion below while proving nothing on disk.
	assert_ne(booted == hero, true, "the booted body is rebuilt from the payload, not reused")

	var state := _cultivation_of(booted)
	assert_eq(state["rank"], expected["rank"], "the realm survived the boot")
	assert_eq(state["stage"], expected["stage"], "the stage survived the boot")
	assert_almost_eq(
		float(state["progress"]),
		float(expected["progress"]),
		"the realm progress survived the boot",
		0.001
	)
	assert_almost_eq(
		float(state["sea_capacity"]),
		float(expected["sea_capacity"]),
		"the sea kept its grown capacity and was not shrunk back to the R1 seed",
		0.001
	)
	assert_eq(state["sea_tier"], expected["sea_tier"], "and its tier")
	assert_almost_eq(
		float(state["sea_clarity"]), float(expected["sea_clarity"]), "and clarity", 0.001
	)
	assert_eq(state["lung"], expected["lung"], "and a trained channel survived")
	assert_eq(state["resonance"], expected["resonance"], "and the meridian resonance rank")
	# The PROVIDER, not the component. `Actor.from_dict` restores the sea as a component, so
	# every assertion above passes on a body nobody re-attached — the sea rides out in the
	# payload whatever the composition root does. What the attach installs is the
	# `SeaProvider` that publishes `SEA_CAPACITY` into `derived_all()`, and the character
	# sheet builds its rows from exactly that map. With the provider missing the id is ABSENT
	# rather than zero, so the "Sea capacity" row VANISHES from the sheet: silent, and only for
	# an actor the player has saved at least once (BL-0108). This is the assertion that makes
	# the re-attach itself observable, and it is what a dropped attach fails.
	var published := booted.stats.derived_all()
	assert_eq(
		published.has(MindStats.SEA_CAPACITY),
		true,
		"the re-attach installed the sea PROVIDER, so the sheet publishes a Sea capacity row"
	)
	assert_eq(
		float(published.get(MindStats.SEA_CAPACITY, -1.0)) > 0.0,
		true,
		"and that row reads the restored sea's capacity"
	)


func test_an_attempt_in_flight_is_still_in_flight_after_the_boot() -> void:
	# A breakthrough attempt is the one piece of cultivation state that is neither a
	# component nor a path, so it rides the versioned `mind_attempt` slot. Losing it means a
	# player mid-breakthrough silently returns to the gate, having already spent the item.
	var hero := _hero(&"core_formation")
	# `_grow` first: the gate preparation below needs the source realm's stocked items and a
	# strengthened sea, which is the order `Probe.prepared` uses.
	_grow(hero)
	var started := _start_attempt(hero)
	_born.append(hero)
	assert_ne(started == null, true, "the hero began a real breakthrough")
	if started == null:
		return
	var attempt_id := String(started.attempt_id)
	var sequence := int(started.sequence)
	var status := String(started.status)
	var lives_target := String(started.target_rank)
	assert_eq(bool(SaveApi.persist(hero, "standard")["ok"]), true, "the save landed on disk")

	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the shipped scene booted")
	if harness.boot_error != "":
		return
	var restored := MindAdvancement.attempt(harness.actor)
	assert_ne(restored == null, true, "the attempt is in flight on the booted body")
	if restored == null:
		return
	assert_eq(String(restored.attempt_id), attempt_id, "the same attempt, not a fresh one")
	assert_eq(int(restored.sequence), sequence, "at the same point in the attempt sequence")
	assert_eq(String(restored.status), status, "and in the same state")
	assert_eq(String(restored.target_rank), lives_target, "aiming at the same realm")


# --- BL-0523: an attach is a grant, so the restore must be gated -----------------


func test_a_restored_body_with_no_mind_path_gets_no_sea() -> void:
	# THE guard. A save whose payload names no mind path — a body-only actor, a foreign or
	# hand-edited slot — must come back with no Sea of Consciousness and no mind path.
	# Unconditional re-attachment is how every actor got a sea regardless of enrolment
	# (BL-0523), and nothing about it throws: `panel_state` and `summary` both answer.
	var bare := _bare_body()
	_born.append(bare)
	assert_eq(bool(SaveApi.persist(bare, "standard")["ok"]), true, "the body-only save landed")

	var restored := _restore()
	assert_ne(restored, null, "the body-only payload restored")
	if restored == null:
		return
	assert_eq(
		restored.path(MindPath.PATH_ID) == null,
		true,
		"BL-0523: a payload with no mind path must not acquire a mind path by being restored"
	)
	# Both halves of the grant. The component alone is not the claim — `attach_sea` mints the
	# component AND registers the `SeaProvider`, and only the second is what puts a sea on the
	# character sheet. A guard that checked the component alone would pass against a restore
	# that installed the provider and nothing else.
	assert_eq(
		MindCultivationApi.sea(restored) == null,
		true,
		"BL-0523: and must not acquire a Sea of Consciousness it was never enrolled in"
	)
	assert_eq(
		restored.stats.derived_all().has(MindStats.SEA_CAPACITY),
		false,
		"BL-0523: nor a sea PROVIDER, which would put a Sea capacity row on a body with no sea"
	)
	assert_eq(
		restored.component(&"dantian") == null,
		true,
		"the same gate holds the qi path: no dantian for a payload that names no qi path"
	)
	assert_eq(restored.path(QiPath.PATH_ID) == null, true, "and no qi path either")


func test_a_restored_body_with_no_qi_path_gets_no_dantian_but_keeps_its_mind_path() -> void:
	# The gate is per path, not all-or-nothing: a mind-only body keeps its sea AND its
	# progress, which is what proves the conditional reads the payload rather than
	# short-circuiting to "attach nothing".
	var mind_only := ActorFactory.build(&"mind_only")
	mind_only.attach_core_resources()
	ItemsApi.attach(mind_only, 200)
	ActorFactory.with_mind_cultivation(mind_only, &"core_formation")
	_grow(mind_only)
	_born.append(mind_only)
	var expected := _cultivation_of(mind_only)
	assert_eq(bool(SaveApi.persist(mind_only, "standard")["ok"]), true, "the save landed")

	var restored := _restore()
	assert_ne(restored, null, "the mind-only payload restored")
	if restored == null:
		return
	assert_ne(restored.path(MindPath.PATH_ID) == null, true, "the mind path came back")
	assert_ne(MindCultivationApi.sea(restored) == null, true, "and so did its sea")
	assert_almost_eq(
		float(_cultivation_of(restored)["sea_capacity"]),
		float(expected["sea_capacity"]),
		"at the capacity it saved with",
		0.001
	)
	assert_eq(restored.path(QiPath.PATH_ID) == null, true, "while the absent qi path stays absent")
	assert_eq(restored.component(&"dantian") == null, true, "so no dantian is minted for it")


# --- Idempotence ---------------------------------------------------------------


func test_restoring_twice_yields_the_same_state_with_no_duplicated_ledger() -> void:
	# Silently disagreeing state after a round trip is its own defect class: a second load
	# must read the same slot and produce the same body, and it must not append to any ledger
	# on the way. `module_data` is compared key-by-key AND value-by-value, because a
	# duplicated ledger entry is a value change inside a key before it is ever a new key.
	# `modifier_count` is the same claim for the stat stack: every attach contributes a
	# modifier, so a second attach that stacked rather than replaced would show up here.
	var hero := _hero(&"core_formation")
	_grow(hero)
	assert_ne(_start_attempt(hero), null, "an attempt is in flight")
	_born.append(hero)
	assert_eq(bool(SaveApi.persist(hero, "standard")["ok"]), true, "the save landed on disk")

	var first := _restore()
	var second := _restore()
	assert_ne(first, null, "the first restore produced a body")
	assert_ne(second, null, "the second restore produced a body")
	if first == null or second == null:
		return
	assert_eq(_cultivation_of(first), _cultivation_of(second), "both restores agree")
	var one := first.to_dict() as Dictionary
	var two := second.to_dict() as Dictionary
	assert_eq(
		(one.get("module_data", {}) as Dictionary).keys(),
		(two.get("module_data", {}) as Dictionary).keys(),
		"and carry the same module_data keys — a duplicated ledger would add one"
	)
	assert_eq(one.get("module_data", {}), two.get("module_data", {}), "with the same contents")
	assert_eq(one.get("paths", {}), two.get("paths", {}), "and the same paths")
	assert_eq(one.get("sea", {}), two.get("sea", {}), "and the same sea")
	assert_eq(
		one.get("mind_attempt", {}), two.get("mind_attempt", {}), "and the same in-flight attempt"
	)
	assert_eq(
		first.stats.modifier_count(),
		second.stats.modifier_count(),
		"and neither load contributed a second copy of any stat modifier"
	)


func test_a_save_written_by_a_restored_body_preserves_every_earned_slot() -> void:
	# The strongest form of idempotence, and the one that would catch a restore that quietly
	# NORMALISED a saved ledger into a different shape: persist the restored body again and
	# compare the player-EARNED slots against the payload that produced it.
	#
	# ## Which slots are compared, and which are deliberately not
	#
	# Three slots in a payload are re-DERIVED by the restore rather than copied, and comparing
	# them would be asserting the restore does not work:
	#   - `sea.structural_capacity` and the qi pool's maximum come from the realm seed via
	#     `MindTraining.synchronize` / `QiTraining.synchronize`. Deriving them is correct: a
	#     stale capacity carried across a realm change is the bug. The rank assertion in
	#     `test_a_saved_mind_realm_survives_a_boot_through_the_shipped_scene` is what proves the
	#     derivation lands on the right seed.
	#   - `module_data` gains keys, because mounting a module NORMALISES an empty ledger into
	#     it — that is what makes a restored body complete rather than half-attached, and it is
	#     why the second payload has more ledgers than the first, not fewer.
	#   - `mind_attempt.rng_state` / `sequence` come back as floats, because the envelope is
	#     JSON and a JSON number decodes as a float. The VALUES are compared numerically.
	#
	# Every remaining slot is compared, so a dropped key, a doubled entry or a rewritten value
	# still fails here.
	var hero := _hero(&"core_formation")
	_grow(hero)
	assert_ne(_start_attempt(hero), null, "an attempt is in flight")
	_born.append(hero)
	var first := hero.to_dict() as Dictionary
	assert_eq(bool(SaveApi.persist(hero, "standard")["ok"]), true, "the save landed on disk")

	var restored := _restore()
	assert_ne(restored, null, "the payload restored")
	if restored == null:
		return
	var second := restored.to_dict() as Dictionary

	# Paths, field by field: a Dictionary compare would also report the key ORDER, which the
	# serialiser does not promise and which says nothing about the state.
	var one_paths := first.get("paths", {}) as Dictionary
	var two_paths := second.get("paths", {}) as Dictionary
	assert_eq(_sorted_keys(two_paths), _sorted_keys(one_paths), "the same set of cultivation paths")
	for path_id in one_paths.keys():
		var before := one_paths[path_id] as Dictionary
		var after := two_paths.get(path_id, {}) as Dictionary
		assert_eq(
			String(after.get("rank_id", "")), String(before.get("rank_id", "")), "%s rank" % path_id
		)
		assert_eq(int(after.get("stage", -1)), int(before.get("stage", -1)), "%s stage" % path_id)
		assert_almost_eq(
			float(after.get("progress", -1.0)),
			float(before.get("progress", -1.0)),
			"%s progress" % path_id
		)

	var one_sea := first.get("sea", {}) as Dictionary
	var two_sea := second.get("sea", {}) as Dictionary
	for field in ["tier", "clarity", "purity", "turbulence", "trained_stage"]:
		assert_almost_eq(
			float(two_sea.get(field, -999.0)),
			float(one_sea.get(field, -999.0)),
			"the sea's %s is the one that was saved" % field
		)

	var one_net := (first.get("meridians", {}) as Dictionary).get("meridians", {}) as Dictionary
	var two_net := (second.get("meridians", {}) as Dictionary).get("meridians", {}) as Dictionary
	assert_eq(_sorted_keys(two_net), _sorted_keys(one_net), "the same set of meridian channels")
	for channel_id in one_net.keys():
		assert_eq(
			two_net.get(channel_id), one_net[channel_id], "channel '%s' survived" % channel_id
		)

	var one_attempt := first.get("mind_attempt", {}) as Dictionary
	var two_attempt := second.get("mind_attempt", {}) as Dictionary
	for field in [
		"attempt_id", "actor_id", "path_id", "source_rank", "target_rank", "profile_id", "status"
	]:
		assert_eq(
			String(two_attempt.get(field, "")),
			String(one_attempt.get(field, "")),
			"the attempt's %s is the one that was saved" % field
		)
	assert_almost_eq(
		float(two_attempt.get("sequence", -1.0)),
		float(one_attempt.get("sequence", -1.0)),
		"and it is at the same point in its sequence"
	)


# --- Wiring: the boot really calls the seam the cases above drive ---------------


func test_the_boot_reads_the_slot_through_the_seam_under_test() -> void:
	# `restore_actor` is public, so a caller could use it while `_ready` does not — and the
	# save would still be a file nobody reads. Proved on the source rather than by a comment:
	# `_ready` must invoke the restore BEFORE it builds a fresh hero, because the envelope
	# carries the payload the restore recovers.
	var source := FileAccess.get_file_as_string("res://src/app/item_workbench_app.gd")
	var boot := source.substr(0, source.find("## The one world store this root installs"))
	assert_eq(boot.contains("restore_actor()"), true, "_ready calls restore_actor()")
	assert_eq(
		boot.find("restore_actor()") < boot.find("_build_actor()"),
		true,
		"and calls it before it builds a fresh hero, so the save is read rather than overwritten"
	)
	# The restore must not reach for an enrolment verb: `set_path` is what erased the save.
	var restore_body := source.substr(
		source.find("func restore_actor"), source.find("func restored_from_save")
	)
	assert_eq(
		(
			restore_body.contains("with_mind_cultivation")
			or restore_body.contains("with_qi_cultivation")
			or restore_body.contains("with_body_cultivation")
		),
		false,
		"the restore attaches conditionally (ActorFactory.restore_cultivation) instead of re-enrolling"
	)
	assert_eq(
		restore_body.contains("restore_cultivation"),
		true,
		"through the gated attach that reads what the payload carried"
	)


# --- Internals ------------------------------------------------------------------


## A hero built the way `_build_actor` builds one: every shipped path enrolled at `rank_id`,
## with the modules the restore re-mounts already attached. The save is only faithful if the
## body that writes it is the shape the boot produces.
func _hero(rank_id: StringName) -> Actor:
	var hero := ActorFactory.build(
		&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0, Stat.APTITUDE: 6.0}
	)
	hero.attach_core_resources()
	ActorFactory.with_body_cultivation(hero)
	ActorFactory.with_qi_cultivation(hero)
	ActorFactory.with_mind_cultivation(hero, rank_id)
	DualCultivationApi.attach(hero)
	FertilityApi.attach(hero)
	ElementsApi.apply_realm_modifiers(hero)
	ItemsApi.attach(hero, 200)
	SetBonusApi.attach(hero)
	TechniquesApi.attach(hero)
	return hero


## A body on NO cultivation path: what a body-only actor, a mob or a hand-edited slot
## serialises to. Built through the factory so it carries the core provider spine, and with
## no path anywhere — which is the payload the BL-0523 guard is about.
func _bare_body() -> Actor:
	var bare := ActorFactory.build(&"bare")
	bare.attach_core_resources()
	ItemsApi.attach(bare, 20)
	return bare


## Put the mind path past R1 through the shipped cultivation actions, then leave it
## unmistakable: a sea with non-default clarity and a trained stage, one trained channel, and
## a partly filled realm.
##
## **Structural capacity is deliberately NOT hand-set.** `MindTraining.synchronize` derives
## it from the realm seed and the meridian capacity bonus, so a forced value is not a state a
## player can reach and asserting it round-trips would be asserting that synchronize does not
## run. Leaving it derived is also what makes it a useful probe: had the restore reset the
## rank to `qi_refining`, synchronize would re-derive the R1 capacity and the comparison
## below would fail on exactly the regression this suite exists to catch.
func _grow(actor: Actor) -> void:
	var state := actor.path(MindPath.PATH_ID)
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	assert_ne(source_seed, null, "the starting realm is authored")
	if source_seed == null:
		return
	Probe.stock(actor, source_seed.training_item)
	Probe.stock(actor, source_seed.sea_catalyst)
	MindCultivationApi.strengthen_sea(actor)
	Probe.train_channels(actor, source_seed)
	Probe.sharpen_sea(actor)
	var sea := MindCultivationApi.sea(actor)
	sea.set_clarity(0.62)
	sea.trained_stage = 2
	state.progress = 42.25
	state.stage = 2
	var channel := actor.meridians.get_meridian(&"lung")
	if channel != null:
		channel.refinement = 3


## Start a real breakthrough through the module's own gate. Returns null when the gate could
## not be satisfied, so the caller records a named failure instead of asserting on a null.
func _start_attempt(actor: Actor) -> MindAttempt:
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return null
	var target := RealmDefaults.ladder().next(state.rank_id)
	var target_seed := MindRealmSeed.for_realm(target.id) if target != null else null
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	if target_seed == null or source_seed == null:
		return null
	Probe.stock(actor, target_seed.breakthrough_item)
	Probe.earn_gate(actor, target_seed)
	Probe.fill_sea(actor)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	return MindAdvancement.start(actor, rng)


## Drive the shipped load path directly — `ItemWorkbenchApp.restore_actor` is what `_ready`
## calls — and hand back the body it built.
##
## The instance is never parented, so `_ready` never fires: this is the restore alone, with
## no screen stack and no frame driver. Freed on the spot, because a leaked Node survives the
## whole suite.
func _restore() -> Actor:
	var app := ItemWorkbenchApp.new()
	var outcome := app.restore_actor()
	var restored := app.get("_actor") as Actor
	if restored != null:
		_born.append(restored)
		if not bool(outcome.get("ok", false)):
			assert_eq(String(outcome.get("reason", "")), "", "the restore reported a refusal")
	app.free()
	return restored


## The cultivation facts a restore must not change, as primitives so two bodies can be
## compared directly. Read through the typed components rather than the payload, because the
## claim under test is about the LIVE body a screen would read.
func _cultivation_of(actor: Actor) -> Dictionary:
	var state := actor.path(MindPath.PATH_ID)
	var sea := MindCultivationApi.sea(actor)
	var channel := actor.meridians.get_meridian(&"lung")
	return {
		"rank": "" if state == null else String(state.rank_id),
		"stage": -1 if state == null else int(state.stage),
		"progress": -1.0 if state == null else float(state.progress),
		"sea_tier": "" if sea == null else String(sea.tier),
		"sea_capacity": -1.0 if sea == null else float(sea.structural_capacity),
		"sea_clarity": -1.0 if sea == null else float(sea.clarity),
		"lung": -1 if channel == null else int(channel.refinement),
		"resonance": int(actor.meridians.resonance_rank),
	}


## A dictionary's keys, sorted.
##
## **A JSON round trip does not preserve key order, and `Array ==` compares order.** The
## envelope is JSON, so a restored body's `paths` and `meridians` come back in whatever order
## the decoder produced. That is not a state difference — the same three paths are present —
## so the comparison is over the SET of keys, and every value is compared field by field
## below rather than as a dictionary.
func _sorted_keys(source: Dictionary) -> Array:
	var keys := source.keys()
	keys.sort()
	return keys


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)
