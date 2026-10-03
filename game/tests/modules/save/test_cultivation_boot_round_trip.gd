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
		0.001,
		"the realm progress survived the boot"
	)
	assert_almost_eq(
		float(state["sea_capacity"]),
		float(expected["sea_capacity"]),
		0.001,
		"the sea kept its grown capacity and was not shrunk back to the R1 seed"
	)
	assert_eq(state["sea_tier"], expected["sea_tier"], "and its tier")
	assert_almost_eq(float(state["sea_clarity"]), float(expected["sea_clarity"]), 0.001, "and clarity")
	assert_eq(state["lung"], expected["lung"], "and a trained channel survived")
	assert_eq(state["resonance"], expected["resonance"], "and the meridian resonance rank")


func test_an_attempt_in_flight_is_still_in_flight_after_the_boot() -> void:
	# A breakthrough attempt is the one piece of cultivation state that is neither a
	# component nor a path, so it rides the versioned `mind_attempt` slot. Losing it means a
	# player mid-breakthrough silently returns to the gate, having already spent the item.
	var hero := _hero(&"qi_refining")
	var started := _start_attempt(hero)
	_born.append(hero)
	assert_ne(started == null, true, "the hero began a real breakthrough")
	if started == null:
		return
	var attempt_id := String(started.attempt_id)
	var lives := int((MindAdvancement.attempt(hero) as MindAttempt).lives)
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
	assert_eq(int(restored.lives), lives, "with the lives it had left")


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
	assert_eq(
		MindCultivationApi.sea(restored) == null,
		true,
		"BL-0523: and must not acquire a Sea of Consciousness it was never enrolled in"
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
		0.001,
		"at the capacity it saved with"
	)
	assert_eq(restored.path(QiPath.PATH_ID) == null, true, "while the absent qi path stays absent")
	assert_eq(restored.component(&"dantian") == null, true, "so no dantian is minted for it")


# --- Idempotence ---------------------------------------------------------------


func test_restoring_twice_yields_the_same_state_with_no_duplicated_ledger() -> void:
	# Silently disagreeing state after a round trip is its own defect class: a second load
	# must read the same slot and produce the same body, and it must not append to any ledger
	# on the way. `module_data` is compared key-by-key AND size-by-size, because a duplicated
	# ledger entry is a value change inside a key before it is ever a new key.
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
	assert_eq(
		one.get("module_data", {}), two.get("module_data", {}), "with the same contents"
	)
	assert_eq(one.get("paths", {}), two.get("paths", {}), "and the same paths")
	assert_eq(one.get("sea", {}), two.get("sea", {}), "and the same sea")
	assert_eq(
		one.get("mind_attempt", {}), two.get("mind_attempt", {}), "and the same in-flight attempt"
	)


func test_a_restore_does_not_stack_a_second_element_realm_modifier() -> void:
	# `apply_realm_modifiers` strips before it applies, so the refresh the restore runs after
	# mounting is safe — but "safe by construction" is a claim, and a second modifier would
	# halve every elemental term on a restored body with nothing to show for it.
	var hero := _hero(&"core_formation")
	_born.append(hero)
	assert_eq(bool(SaveApi.persist(hero, "standard")["ok"]), true, "the save landed on disk")
	var restored := _restore()
	assert_ne(restored, null, "the payload restored")
	if restored == null:
		return
	var counted := 0
	for modifier in restored.stats.modifiers:
		if String(modifier.source_id) == RealmScaling.SOURCE:
			counted += 1
	assert_eq(counted, 7, "one realm modifier per element id, and no second copy")


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
		restore_body.contains("with_mind_cultivation") or restore_body.contains("with_qi_cultivation")
		or restore_body.contains("with_body_cultivation"),
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
## unmistakable: a deep sea with a non-default capacity and clarity, one trained channel, and
## a partly filled realm. Distinctive enough that a reset to `qi_refining` cannot pass.
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
	sea.set_structural_capacity(137.5)
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
		"sea_tier": -1 if sea == null else int(sea.tier),
		"sea_capacity": -1.0 if sea == null else float(sea.structural_capacity),
		"sea_clarity": -1.0 if sea == null else float(sea.clarity),
		"lung": -1 if channel == null else int(channel.refinement),
		"resonance": int(actor.meridians.resonance_rank),
	}


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)