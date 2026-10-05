extends TestCase

## ADR 0128: the save ROUND TRIPS. The write half shipped and the read half did not, which
## means every requirement phrased as "sticks to a save" was half a feature.
##
## ## Why this suite exists when test_save_envelope already passes
##
## **The envelope suite proves the file is well-formed; it cannot prove anything reads it.** A
## `persist` wired at boot with no `restore` caller writes a correct envelope every period and
## builds a fresh hero on the next launch — cultivation progress, the soul and the anchors are
## saved and never observed. Every assertion in a format suite passes while the feature does not
## exist, which is DEF-0151's shape exactly. So the cases here assert the OBSERVABLE: what a
## body reads after a restore.

var _soul_store: SoulWorldLedger
var _anchor_store: AnchorWorldLedger
var _born: Array = []


func setup() -> void:
	_clear_disk()
	_soul_store = SoulWorldLedger.new()
	_anchor_store = AnchorWorldLedger.new()
	SoulApi.set_store(_soul_store)
	AnchorApi.set_store(_anchor_store)
	SaveApi.reset_clock()
	SaveApi.install_store("soul", _soul_store)
	SaveApi.install_store("anchor", _anchor_store)


func teardown() -> void:
	_clear_disk()
	for born in _born:
		(born as Actor).resources.clear()
	_born.clear()
	SoulApi.set_store(null)
	AnchorApi.set_store(null)
	SaveApi.reset_clock()
	SaveApi.install_store("soul", null)
	SaveApi.install_store("anchor", null)


# --- The round trip -----------------------------------------------------------


func test_the_soul_a_body_writes_is_the_soul_the_next_session_reads() -> void:
	# The requirement, verbatim: "a soul will stick on a save". Damage a soul, persist, then
	# read the envelope back through the SAME public path a boot uses and ask the store.
	var actor := _hero()
	SoulApi.attach(actor)
	SoulApi.damage(actor, 35, "test")
	assert_eq(bool(SaveApi.persist(actor, "standard")["ok"]), true, "the save landed")
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	var written := (envelope["world"] as Dictionary)["soul"] as Dictionary
	assert_eq(int(written["integrity"]), 65, "the soul rode out in the envelope")

	# A NEW session: a fresh store, published from that envelope, and a DIFFERENT body. This is
	# the half the write-only wiring never reached.
	var next_session := SoulWorldLedger.new()
	SaveApi.install_store("soul", next_session)
	SaveApi.publish_world()
	assert_eq(int(next_session.read_ledger()["integrity"]), 65, "and comes back in")
	var other_body := _hero_named(&"second_session")
	assert_eq(
		int(SoulApi.soul(other_body)["integrity"]), 65, "a different body reads the same soul"
	)


func test_the_actor_payload_round_trips_so_progress_is_not_written_and_forgotten() -> void:
	# DEF-0059's actual content: saving dropped realm, progress and the sea. The envelope carries
	# `Actor.to_dict()` whole, and this asserts the restore reconstructs a body that still has
	# them.
	#
	# The expectations are DERIVED from the body that saved, never written as literals: a
	# literal here would pass against a hero that happened to be at the default realm, which is
	# precisely the state a broken restore produces.
	var actor := _hero()
	actor.display_name = "Named Hero"
	# A realm above R1 with progress part-earned, a grown sea and a trained channel, so "the
	# sea rode out" cannot be satisfied by an actor that was never raised.
	ActorFactory.with_mind_cultivation(actor, &"core_formation")
	MindTraining.synchronize(actor)
	var state := actor.path(MindPath.PATH_ID)
	state.progress = 42.25
	state.stage = 2
	var sea := MindCultivationApi.sea(actor)
	sea.set_structural_capacity(137.5)
	sea.set_clarity(0.62)
	actor.meridians.get_meridian(&"lung").refinement = 3
	var expected_rank := String(state.rank_id)
	var expected_progress := float(state.progress)
	var expected_capacity := float(sea.structural_capacity)
	var expected_refinement := int(actor.meridians.get_meridian(&"lung").refinement)

	SaveApi.persist(actor, "standard")
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	var restored := Actor.from_dict(envelope["actor"] as Dictionary)
	_born.append(restored)
	assert_eq(restored != null, true, "the payload rebuilt a body")
	assert_eq(String(restored.display_name), "Named Hero", "and it is the same hero")
	assert_eq(
		int(restored.to_dict()["version"]),
		Actor.SCHEMA_VERSION,
		"with the actor schema untouched by the envelope's own version"
	)

	# The three claims the comment above makes, each read off the LIVE body rather than off a
	# re-serialised payload — a payload comparison cannot tell a restored sea from a sea that
	# was written by the thing under test.
	var restored_state := restored.path(MindPath.PATH_ID)
	assert_ne(restored_state == null, true, "the realm rode out")
	assert_eq(String(restored_state.rank_id), expected_rank, "the realm is the one that saved")
	assert_almost_eq(float(restored_state.progress), expected_progress, "the progress rode out")
	assert_eq(int(restored_state.stage), 2, "and so did the stage")
	var restored_sea := MindCultivationApi.sea(restored)
	assert_ne(restored_sea == null, true, "the sea rode out")
	assert_almost_eq(
		float(restored_sea.structural_capacity),
		expected_capacity,
		"with the capacity it was grown to"
	)
	assert_almost_eq(float(restored_sea.clarity), 0.62, "and its clarity")
	assert_eq(
		int(restored.meridians.get_meridian(&"lung").refinement),
		expected_refinement,
		"and a trained meridian channel"
	)
	assert_eq(
		float((restored.meridians.to_dict() as Dictionary)["resonance_rank"]),
		float((actor.meridians.to_dict() as Dictionary)["resonance_rank"]),
		"and the meridian resonance rank"
	)


func test_a_raised_anchor_survives_the_round_trip_because_it_is_a_world_fact() -> void:
	# ADR 0146's argument: an anchor outlives the body that raised it, so per-actor storage would
	# let a rival raise their own on the same ground after a reload.
	var actor := _hero()
	AnchorApi.attach(actor)
	_give(actor, &"vial_mending_elixir", 2)
	assert_eq(
		bool(AnchorApi.raise_anchor(actor, &"hearth_of_the_returning", "here")["ok"]),
		true,
		"the anchor was raised"
	)
	SaveApi.persist(actor, "standard")
	var next_session := AnchorWorldLedger.new()
	SaveApi.install_store("anchor", next_session)
	SaveApi.publish_world()
	var rival := _hero_named(&"rival")
	assert_eq(
		AnchorApi.is_raised(rival, &"hearth_of_the_returning"),
		true,
		"and a rival in the next session still sees it standing"
	)


func test_the_difficulty_the_run_was_playing_under_rides_out_with_it() -> void:
	# A save that cannot say what it was playing under is not self-describing, which is why the id
	# is in the envelope rather than only in the actor payload.
	var actor := _hero()
	DifficultyApi.attach(actor)
	DifficultyApi.select(actor, &"hard")
	SaveApi.persist(actor, String(DifficultyApi.current_id(actor)))
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	assert_eq(String(envelope["difficulty"]), "hard", "the preset id is in the envelope")


# --- The player's half ---------------------------------------------------------


func test_the_player_still_chooses_nothing_about_the_save() -> void:
	# `persist` takes no slot from a caller and `restore` is the only read, so there is no
	# "which save" question to answer. Asserted on the envelope's own shape: one live slot, one
	# private backup, and no slot list anywhere a player could pick from.
	assert_eq(bool(SaveApi.summary()["primary_present"]), false, "nothing saved yet")
	SaveApi.persist(_hero(), "standard")
	SoulApi.damage(_hero(), 1, "second")
	SaveApi.persist(_hero(), "standard")
	assert_eq(bool(SaveApi.summary()["backup_present"]), true, "a backup exists")
	assert_eq(int(SaveApi.summary()["generation"]) >= 2, true, "and the live slot is newer")
	var source := _code_only(FileAccess.get_file_as_string("res://src/modules/save/api.gd"))
	assert_eq(source.contains('&"backup"'), false, "no shipped caller can name the backup")


func test_no_readable_save_is_a_new_game_rather_than_an_error() -> void:
	# The refusal a boot flow branches on. `ok: false` here means "build a fresh hero", which is
	# why it is an answer rather than an exception.
	var restored := SaveApi.restore()
	assert_eq(bool(restored["ok"]), false, "nothing to read")
	assert_eq(String(restored["reason"]), "no_readable_save", "and it is named")
	assert_eq(SaveApi.exists(), false, "so no live slot exists either")


# --- Internals ------------------------------------------------------------------


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)


func _hero() -> Actor:
	return _hero_named(&"hero")


## An actor with a body plan, core pools and the modules the save carries.
func _hero_named(actor_id: StringName) -> Actor:
	var body := ActorFactory.build(actor_id)
	RaceApi.attach(body)
	RaceApi.set_race(body, &"stoneborn")
	body.attach_core_resources()
	DifficultyApi.attach(body)
	SoulApi.attach(body)
	AnchorApi.attach(body)
	_born.append(body)
	return body


## Put `def_id` in the bag, so an authored cost can be met.
func _give(actor: Actor, def_id: StringName, count: int) -> void:
	if ItemsApi.inventory(actor) == null:
		ItemsApi.attach(actor)
	var bag := ItemsApi.inventory(actor)
	var def := Crafting.resolve(def_id)
	if def != null and not bag.has(def_id, count):
		bag.add(def, count)


## `source` with every comment line removed, so a guard reads CODE and not the prose that
## describes what the code must not do.
func _code_only(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
