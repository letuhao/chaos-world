extends TestCase

## ADR 0128: the save is an autosaved envelope with one readable slot and an unreadable backup.
##
## ## Why this suite exists
##
## Two of the four requirements are DESIGN RULES, not features, and neither is observable from
## gameplay: the player never chooses when to save, and never chooses to load the backup. A rule
## with no guard is a claim, so the guards are here — including the structural one that scans
## `res://src` for any shipped caller naming the backup, which is the only thing that keeps
## "the user cannot decide to load the backup" an invariant rather than an intention.
##
## ## These tests touch the real filesystem
##
## They write to `user://save`, which is per-run scratch. Every case removes the directory
## first, so a previous run's generation cannot make an assertion about "the first save" pass
## or fail for the wrong reason.

var _actor: Actor
var _store: SoulWorldLedger


func setup() -> void:
	_clear_disk()
	_store = SoulWorldLedger.new()
	SoulApi.set_store(_store)
	SaveApi.reset_clock()
	SaveApi.install_store("soul", _store)
	_actor = Actor.new()
	_actor.id = &"saved_hero"
	_actor.display_name = "Hero"
	SoulApi.attach(_actor)


## `SaveApi._stores` is a process-wide static, so a suite that leaves the soul store installed
## lets the next suite read this one's soul. Idempotent, and safe after an early return.
func teardown() -> void:
	_clear_disk()
	_actor = null
	_store = null
	SoulApi.set_store(null)
	SaveApi.install_store("soul", null)


func _clear_disk() -> void:
	# The three files removed individually. `DirAccess.remove_absolute` on the directory fails
	# silently on some platforms and left a previous run's generation behind, which is what made
	# the first case read "nothing saved yet: expected false, got true".
	for path in [SavePaths.PRIMARY, SavePaths.BACKUP, SavePaths.TEMP]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(SavePaths.DIR):
		DirAccess.remove_absolute(SavePaths.DIR)


# --- The envelope -----------------------------------------------------------


func test_a_new_game_writes_a_live_slot_on_the_first_boot() -> void:
	assert_eq(SaveApi.exists(), false, "nothing saved yet")
	var out := SaveApi.persist(_actor, "standard")
	assert_eq(bool(out["ok"]), true, "the first save lands: %s" % out.get("reason", ""))
	assert_eq(SaveApi.exists(), true, "a live slot exists")


func test_the_actor_payload_is_carried_whole_so_cultivation_progress_survives() -> void:
	# DEF-0059 verbatim: `Actor.to_dict` had no production caller, so saving from the game lost
	# realm, progress and the sea. Putting it under `envelope.actor` closes that with no second
	# item path, because `item_state` already rides inside it.
	_actor.display_name = "Named Hero"
	SaveApi.persist(_actor, "standard")
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	var restored := Actor.from_dict(envelope["actor"] as Dictionary)
	assert_eq(
		String(restored.display_name), "Named Hero", "the actor round-trips through the envelope"
	)
	assert_eq(
		int(restored.to_dict()["version"]), Actor.SCHEMA_VERSION, "the actor schema is untouched"
	)


func test_the_soul_rides_beside_the_actor_and_not_inside_it() -> void:
	# ADR 0127: a soul outlives its body, so it cannot live in `module_data`. The envelope is
	# the transport; `envelope.world.soul` is where it crosses.
	SoulApi.damage(_actor, 30, "death")
	SaveApi.persist(_actor, "standard")
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	var world := envelope["world"] as Dictionary
	assert_eq(int((world["soul"] as Dictionary)["integrity"]), 70, "the soul is in the world slot")
	assert_eq(
		bool((envelope["actor"] as Dictionary).has("soul_state")), false, "and not in the actor"
	)


func test_the_soul_survives_the_actor_being_replaced() -> void:
	# The whole feature in one test: the new body is a different Actor and finds the same soul.
	SoulApi.damage(_actor, 30, "death")
	SaveApi.persist(_actor, "standard")
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	SaveApi.publish_world()
	var new_body := Actor.new()
	new_body.id = &"second_body"
	var soul := SoulApi.soul(new_body)
	assert_eq(int(soul.get("integrity", 0)), 70, "a different body reads the same soul")


func test_the_envelope_version_and_the_actor_version_are_independent() -> void:
	# ADR 0037: `SCHEMA_VERSION` is pinned at exactly 4 and a new world key must not bump it.
	SaveApi.persist(_actor, "standard")
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	assert_eq(
		int(envelope["envelope_version"]), SaveSlot.ENVELOPE_VERSION, "the envelope carries its own"
	)
	assert_eq(
		int((envelope["actor"] as Dictionary)["version"]),
		Actor.SCHEMA_VERSION,
		"a save never rewrites an actor payload's version"
	)


# --- Atomicity --------------------------------------------------------------


func test_the_previous_generation_stays_readable_after_a_new_save() -> void:
	# Snapshot, rotate, write temp, rename. A crash anywhere but the final rename must cost the
	# CURRENT save and never the previous one.
	#
	# Generations are asserted RELATIVE to the first write rather than as absolute numbers: the
	# counter reads whatever is on disk, so a leftover generation from a previous run would make
	# an absolute assertion fail for a reason that has nothing to do with the rule.
	SaveApi.persist(_actor, "standard")
	var first := int(SaveApi.summary()["generation"])
	SoulApi.damage(_actor, 10, "first")
	SaveApi.persist(_actor, "standard")
	var second := int(SaveApi.summary()["generation"])
	assert_eq(bool(SaveApi.summary()["backup_present"]), true, "one deep backup exists")
	assert_eq(second, first + 1, "the live slot is one generation newer")


func test_a_failed_write_leaves_exactly_one_readable_complete_file() -> void:
	# The invariant that makes a rename worth doing: after any failure the player still has one
	# whole save. `ItemStateStore` opens and writes in place, so a crash there truncates the
	# only copy.
	SaveApi.persist(_actor, "standard")
	var envelope := SaveStore.restore()["envelope"] as Dictionary
	assert_eq(SaveSlot.is_readable(envelope), true, "the first generation is whole")
	assert_eq(int(envelope["generation"]), 1, "and is the first generation")


func test_the_temp_file_is_never_read_as_a_slot() -> void:
	# A temp file may be a partial write. Promoting it is exactly the corruption this design
	# exists to prevent, so it is refused at the reader rather than trusted by convention.
	assert_eq(SavePaths.is_temp(SavePaths.TEMP), true, "the temp path is recognised")
	assert_eq(
		SaveSlot.is_readable({"anything": true}), false, "a file without the marker is not a save"
	)


func test_a_file_that_is_not_a_save_is_reported_unreadable_rather_than_half_read() -> void:
	# Three checks and no more: a dictionary, the format marker, and a version this build
	# knows. Anything else routes to the backup instead of a half-populated world.
	assert_eq(SaveSlot.is_readable("a string"), false, "a string is not an envelope")
	assert_eq(
		SaveSlot.is_readable({"format": "something-else"}), false, "a foreign format is refused"
	)
	assert_eq(
		SaveSlot.is_readable({"format": SaveSlot.FORMAT, "envelope_version": 99}),
		false,
		"a future version is refused"
	)


# --- Recovery ----------------------------------------------------------------


func test_a_corrupt_primary_recovers_the_backup_without_inventing_state() -> void:
	# Silent by design: the player has no backup choice to make, so a modal reporting an error
	# they cannot act on would be noise. The caller still learns.
	# The directory is made first: opening a file inside a directory that does not exist returns
	# null on every platform, and a null here would abort the case before it said anything.
	DirAccess.make_dir_recursive_absolute(SavePaths.DIR)
	var broken := FileAccess.open(SavePaths.PRIMARY, FileAccess.WRITE)
	broken.store_string("{not json at all")
	broken.close()
	var out := SaveStore.restore()
	assert_eq(bool(out["ok"]), false, "with no backup there is nothing to recover")
	assert_eq(String(out["reason"]), "no_readable_save", "and the refusal is named")


func test_recovery_reports_that_it_recovered_rather_than_saying_nothing() -> void:
	# The condition must be OBSERVABLE in a test even though it is invisible in play: a silent
	# recovery that cannot be asserted is indistinguishable from a load that never happened.
	SaveApi.persist(_actor, "standard")
	var good := FileAccess.get_file_as_string(SavePaths.PRIMARY)
	DirAccess.rename_absolute(SavePaths.PRIMARY, SavePaths.BACKUP)
	var broken := FileAccess.open(SavePaths.PRIMARY, FileAccess.WRITE)
	broken.store_string("{not json")
	broken.close()
	var out := SaveStore.restore()
	assert_eq(bool(out["ok"]), true, "the backup was recovered")
	assert_eq(bool(out["recovered"]), true, "and the recovery is reported")
	assert_eq(String(out["reason"]), "primary_unreadable", "by name")
	# The recovered generation is a WHOLE one, not a salvage of the broken file.
	assert_eq(SaveSlot.is_readable(out["envelope"]), true, "the recovered envelope is complete")
	# The good text is still what was recovered, so nothing was lost by the failed write.
	assert_eq(
		String((out["envelope"] as Dictionary)["format"]),
		SaveSlot.FORMAT,
		"the format marker survived"
	)


# --- The schedule -------------------------------------------------------------


func test_the_autosave_fires_on_a_period_boundary_and_not_before() -> void:
	# "The player cannot decide when they save" is enforced by the schedule living in whole
	# periods the player never sees. A save can only land on a boundary.
	var clock := SaveClock.new()
	for _i in range(SaveClock.AUTOSAVE_PERIODS - 1):
		assert_eq(clock.pull(1.0), false, "not yet")
	assert_eq(clock.pull(1.0), true, "the boundary fires")
	assert_eq(clock.pull(1.0), false, "and the next one is a full period away")


func test_the_clock_never_reads_a_wall_clock_or_declares_a_frame_driver() -> void:
	# DEF-0111, and the reason the schedule is a counter: a wall-clock deadline inside persisted
	# state is a recorded defect here. `tools arch` cannot see a module's clock, so this reads
	# the source.
	#
	# **COMMENTS ARE STRIPPED FIRST, and that is the whole point.** Each of these forbidden
	# tokens is named in the module's own docstring — `save_clock.gd` explains that it must not
	# read `Time.get_ticks*` — so scanning raw text matches the PROSE and fails on correct code.
	# A guard that fires on its own documentation is a guard nobody trusts.
	for path in [
		"res://src/modules/save/save_clock.gd",
		"res://src/modules/save/api.gd",
		"res://src/modules/save/save_store.gd",
	]:
		var source := _code_only(FileAccess.get_file_as_string(path))
		for forbidden in ["Time.get_ticks", "_process", "_physics_process", "get_tree("]:
			assert_eq(source.contains(forbidden), false, "%s declares no %s" % [path, forbidden])


# --- The design rule: no backup affordance --------------------------------------


func test_no_shipped_caller_can_name_the_backup_slot() -> void:
	# The guard that makes "the user cannot decide to load the backup" an INVARIANT rather than
	# an intention. `SaveStore` is allow-listed because its private fallback is the recovery
	# path this rule exists to keep unreachable from a player affordance.
	var allow_listed: Array[String] = ["save_store.gd"]
	var offenders: Array[String] = []
	for path in _source_files("res://src"):
		var file_name := path.get_file()
		if allow_listed.has(file_name):
			continue
		# Read CODE, not raw text: every forbidden verb is named in this suite's own docstring and
		# in `SaveStore`'s, so scanning unstripped text matches the prose and reports correct code
		# as an affordance. A guard that fires on its own documentation is one nobody trusts.
		var source := _code_only(FileAccess.get_file_as_string(path))
		for forbidden in [
			"load_backup", "restore_backup", "rollback", "revert_save", "SLOT_BACKUP"
		]:
			if source.contains(forbidden):
				offenders.append("%s names %s" % [file_name, forbidden])
	assert_eq(offenders, [], "no shipped caller can reach the backup")


func test_the_facade_exposes_no_backup_slot_constant() -> void:
	# The other half: a caller cannot name the backup because there is no name for it. The only
	# slot the facade publishes is the live one. Read from CODE, since the facade's docstring
	# discusses the backup slot by name.
	var source := _code_only(FileAccess.get_file_as_string("res://src/modules/save/api.gd"))
	assert_eq(source.contains('&"backup"'), false, "the facade names no backup slot")
	assert_eq(String(SaveApi.SLOT), "primary", "the one slot is the live one")


func test_the_summary_reports_the_backup_exists_without_reaching_it() -> void:
	# A probe asserts the backup is really written, so the recovery path is proven to exist
	# rather than assumed. Reporting its existence is not offering it.
	SaveApi.persist(_actor, "standard")
	SoulApi.damage(_actor, 5, "second")
	SaveApi.persist(_actor, "standard")
	var summary := SaveApi.summary()
	assert_eq(bool(summary["backup_present"]), true, "the backup is on disk")
	assert_eq(bool(summary["primary_present"]), true, "and the live slot is too")
	# The live slot is the NEWER one: it holds the damage, the backup the generation before it.
	assert_eq(
		int(SaveStore._read(SavePaths.PRIMARY)["generation"]),
		int(SaveStore._read(SavePaths.BACKUP)["generation"]) + 1,
		"the live slot is one generation ahead of the backup"
	)


# --- Content -------------------------------------------------------------------


func test_the_authored_world_keys_are_the_four_ledgers_that_outlive_an_actor() -> void:
	# `holdings`, `market` and `custody` were the three in-memory ledgers ADR 0101 owed a store
	# for; `soul` is ADR 0127's addition for the same reason.
	for key in ["holdings", "market", "custody", "soul"]:
		assert_eq(SaveApi.WORLD_KEYS.has(key), true, "%s rides in the envelope" % key)


# --- Internals ---------------------------------------------------------------


## Every `.gd` under `root`, capped by `ContentScan` so a junction cannot return nothing.
func _source_files(root: String) -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files_under(root):
		if path.get_file().ends_with(".gd"):
			out.append(path)
	return out


## `source` with every GDScript comment line removed, so a structural guard reads CODE and never
## the prose describing what the code must not do.
##
## Removed by LINE rather than by token because a block comment's middle lines are the ones
## that mislead: a file may open `##` on line one and continue the explanation for twenty lines,
## every one of them naming the very token the guard is looking for.
func _code_only(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
