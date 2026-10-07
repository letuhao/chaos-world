extends TestCase

## ADR 0905: worldmap mutations ride the save envelope.
##
## The generator reproduces every untouched chunk from its seed, so the ONLY
## thing a save must carry is what the player changed. Every case here runs
## against a REAL envelope on disk — an overlay tested only in memory proves
## the dictionary and nothing about the persistence, and the persistence is
## the entire reason the ledger exists.
##
## ## WHY THE ROUND TRIP USES TWO STREAMERS
##
## A restore through the SAME streamer that recorded the mutation would pass
## with an overlay that never left the object. The second streamer is a new
## session: it imports what the envelope carried and regenerates from seed.

const ENV := "mortal_greenwood"
const SIZE := 8
const SEED := 1234

var _born: Array = []


func setup() -> void:
	_clear_disk()
	SaveApi.reset_clock()


func teardown() -> void:
	SaveApi._stores.erase(WorldmapLedger.WORLD_KEY)
	_clear_disk()
	SaveApi.reset_clock()
	for actor in _born:
		(actor as Actor).resources.clear()
	_born.clear()


func test_the_slot_is_declared_in_core_and_carried_in_the_envelope() -> void:
	assert_eq(WorldmapLedger.WORLD_KEY, "worldmap", "the ledger names its envelope key")
	assert_eq(SaveApi.WORLD_KEYS.has(WorldmapLedger.WORLD_KEY), true, "the envelope carries it")
	assert_eq(SaveSlot.ENVELOPE_VERSION, 1, "the envelope version did not move for a new key")


func test_the_container_the_ledger_owns_is_the_one_the_store_routes() -> void:
	var source := FileAccess.get_file_as_string("res://src/app/world_ledger_store.gd")
	var line := ""
	for candidate in source.split("\n"):
		if candidate.contains('"worldmap":'):
			line = candidate
			break
	assert_ne(line.is_empty(), true, "the store routes a worldmap container")
	assert_eq(
		line.contains('"mutations"') and line.contains('"position"'),
		true,
		"and it routes both containers this ledger owns"
	)
	assert_eq(
		WorldmapLedger.CONTAINERS, ["mutations", "position"], "and the ledger owns exactly two"
	)


func test_a_corrupt_overlay_repairs_instead_of_believed() -> void:
	var ledger := WorldmapLedger.new()
	(
		ledger
		. write_ledger(
			{
				"mutations":
				{
					"overworld:0,0":
					{
						"1,2": {"blocked": true},
						"nope": {"blocked": true},
						"3,4": "not-a-dict",
					},
					"overworld:9,9": "not-a-dict",
				}
			}
		)
	)
	var read := ledger.read_ledger()
	var chunks := read.get("mutations", {}) as Dictionary
	assert_eq(chunks.has("overworld:0,0"), true, "the well-formed chunk survives")
	assert_eq(
		(chunks.get("overworld:0,0") as Dictionary).has("1,2"),
		true,
		"and so does its well-formed cell"
	)
	assert_eq(
		(chunks.get("overworld:0,0") as Dictionary).has("nope"),
		false,
		"while a cell key that is not x,y is dropped"
	)
	assert_eq(chunks.has("overworld:9,9"), false, "and a chunk that is not a dict is dropped")
	assert_eq(WorldmapLedger.mutation_count(read), 1, "so the count answers what survived")


func test_a_hole_dug_this_session_is_still_open_after_the_quit() -> void:
	var first_session := _streamer()
	var victim := _blocking_cell(first_session)
	assert_ne(victim, Vector2i(-1, -1), "a blocking prop exists to destroy")
	first_session.mutate("overworld", 0, 0, victim.x, victim.y, false)
	assert_eq(_standable(first_session, victim), true, "which is walkable now")

	var ledger := WorldmapLedger.new()
	ledger.write_ledger(
		{
			"mutations": first_session.export_mutations(),
			"position": {"node": "overworld", "cell": [2, 1]}
		}
	)
	SaveApi.install_store(WorldmapLedger.WORLD_KEY, ledger)
	assert_eq(bool(SaveApi.persist(_hero(), "standard")["ok"]), true, "and the save landed")

	var envelope := SaveStore.restore()["envelope"] as Dictionary
	var carried = (envelope.get("world", {}) as Dictionary).get(WorldmapLedger.WORLD_KEY)
	assert_eq(carried is Dictionary, true, "mutations rode out in the envelope")
	assert_eq(
		((carried as Dictionary).get("position", {}) as Dictionary).get("node", ""),
		"overworld",
		"with the resume point beside them"
	)

	var next_session := WorldmapLedger.new()
	SaveApi.install_store(WorldmapLedger.WORLD_KEY, next_session)
	var published := SaveApi.publish_world()
	assert_eq(bool(published.get("ok", false)), true, "the world published")
	assert_eq(
		(published.get("restored", []) as Array).has(WorldmapLedger.WORLD_KEY),
		true,
		"and it names worldmap among the keys it restored"
	)
	var second_session := _streamer()
	second_session.import_mutations(next_session.read_ledger().get("mutations", {}) as Dictionary)
	assert_eq(_standable(second_session, victim), true, "so the hole is still open next session")


func test_import_replaces_the_overlay_and_drops_the_cache() -> void:
	var streamer := _streamer()
	streamer.mutate("overworld", 0, 0, 1, 1, true)
	assert_eq(streamer.export_mutations().size(), 1, "one chunk recorded")
	streamer.import_mutations({"overworld:5,5": {"2,2": {"blocked": true}}})
	assert_eq(streamer.export_mutations().has("overworld:0,0"), false, "the old overlay is gone")
	assert_eq(
		streamer.export_mutations().has("overworld:5,5"), true, "and the restored one is live"
	)
	assert_eq(
		streamer.summary().get("cached", -1) as int, 0, "with no stale chunks disagreeing with it"
	)


func test_a_resume_point_rides_along_and_repairs() -> void:
	var ledger := WorldmapLedger.new()
	ledger.write_ledger({"position": {"node": "overworld", "cell": [3, 1]}})
	var read := ledger.read_ledger()
	assert_eq(
		(read.get("position", {}) as Dictionary).get("node", ""), "overworld", "the node rides"
	)
	assert_eq((read.get("position", {}) as Dictionary).get("cell", []), [3, 1], "with the cell")
	ledger.write_ledger({"position": {"node": "", "cell": [3]}})
	assert_eq(
		(ledger.read_ledger().get("position", {}) as Dictionary).is_empty(),
		true,
		"while a malformed point restores nothing rather than somewhere wrong"
	)
	ledger.write_ledger({})
	assert_eq(
		(ledger.read_ledger().get("position", {}) as Dictionary).is_empty(),
		true,
		"and an absent point is a new arrival, not a corrupt save"
	)


func _streamer() -> WorldmapStreamer:
	var streamer := WorldmapStreamer.new()
	(
		streamer
		. configure(
			WorldmapApi.default_generator(),
			{
				"environment": ENV,
				"scatter": [{"archetype": "flora.shrub", "density": 0.05, "blocking": true}],
			}
		)
	)
	return streamer


func _blocking_cell(streamer: WorldmapStreamer) -> Vector2i:
	var chunk := streamer.chunk_data("overworld", 0, 0, SIZE, SEED)
	for prop in chunk.props:
		var placement := prop as Dictionary
		if not bool(placement.get("blocking", false)):
			continue
		var base := placement.get("cell", Vector2i(-1, -1)) as Vector2i
		if chunk.standable(base.x, base.y):
			continue
		return Vector2i(base.x, base.y)
	return Vector2i(-1, -1)


func _standable(streamer: WorldmapStreamer, cell: Vector2i) -> bool:
	var chunk := streamer.chunk_data("overworld", 0, 0, SIZE, SEED)
	return chunk.standable(cell.x, cell.y)


func _clear_disk() -> void:
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)


func _hero() -> Actor:
	var body := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	body.display_name = "hero"
	body.attach_core_resources()
	DifficultyApi.attach(body)
	_born.append(body)
	return body
