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

## The floor [method _source_files]'s walk must clear before "no shipped caller reached the
## backup" is a verdict rather than an empty list. Measured 2026-10-04 at 487 `.gd` under
## `res://src`; the floor is deliberately well below that rather than equal to it, so deleting
## modules does not redden a guard while a walk covering a fraction of the tree still does.
const SOURCE_FILE_FLOOR := 200

## The census needs a floor of its own, so "no offenders" cannot be reported over an empty
## population. ONE below the measured reads: the file scan has a 200-file floor for
## "the walk covers the tree" and this has a 2-read floor for "the walk found the slot".
const BACKUP_READER_FLOOR := 2

## `save/store.gd`'s own private recovery, the one admissible content read. Compared by full
## `res://` path rather than by `get_file()`, so a second `save_store.gd` elsewhere in the
## tree cannot inherit the exemption — the allow-list in the version this replaced was
## `path.get_file()`-keyed, which any directory could satisfy.
const SAVE_STORE_PATH := "res://src/modules/save/save_store.gd"

## The only spelling that names the backup's CONTENT. `SavePaths` publishes `PRIMARY`,
## `BACKUP`, `TEMP` and no verb, so a read that hands this to anything is a read of the spare
## generation whatever the caller calls it afterwards.
const BACKUP_READER := "SavePaths.BACKUP"

## Argument names that would let a caller name a slot, matched as SUBSTRINGS so `p_slot`,
## `slot` and `path` are all caught and a typed `path: String` is caught with its annotation.
const _SLOT_ARGUMENT_NAMES := ["path", "slot", "file_name", "filename", "backup", "save_id"]

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
	#
	# **The verb takes a COUNT, not seconds** (ADR 0179): the autosave was the last wall-clock
	# holdout among the accrual verbs, so `advance` is handed whole periods by the caller that
	# owns time and this module no longer knows how long a period is at all.
	var clock := SaveClock.new()
	for i in range(SaveClock.AUTOSAVE_PERIODS - 1):
		assert_eq(clock.advance(1), false, "not yet (period %d)" % (i + 1))
	assert_eq(clock.advance(1), true, "the boundary fires")
	assert_eq(clock.advance(1), false, "and the next one is a full period away")


func test_a_count_of_periods_is_fired_by_in_one_call_just_as_by_twelve() -> void:
	# The schedule is arithmetic on a count, so a caller that moved six periods at once pays
	# the same boundary as one that moved six in a row. Nothing here counts CALLS.
	var whole := SaveClock.new()
	for _i in range(SaveClock.AUTOSAVE_PERIODS - 1):
		assert_eq(whole.advance(1), false, "eleven periods is not the boundary")
	assert_eq(whole.advance(1), true, "and the twelfth fires it")

	var lumped := SaveClock.new()
	assert_eq(lumped.advance(SaveClock.AUTOSAVE_PERIODS), true, "one call, the whole count")
	assert_eq(lumped.saves(), 0, "recorded only by record_saved, never by the boundary itself")


func test_a_save_lands_only_on_a_boundary_because_the_clock_owns_no_ratio() -> void:
	# The regression guard for the call-count bug, restated for the verb that replaced it.
	# **There is no `PERIOD_SECONDS` on `SaveClock` any more**, so "a frame's worth of
	# something" is not expressible as input: the verb's only argument is a whole-period count,
	# and a fraction cannot be passed at all. At 60fps the old schedule fired every 12 FRAMES
	# — about 0.2 seconds, twelve disk writes a second — while reporting twelve periods.
	assert_eq(
		_save_clock_source().contains("const PERIOD_SECONDS"),
		false,
		"the clock declares no seconds-per-period ratio: the SSOT owns it and nothing reads it here"
	)
	assert_eq(
		_save_clock_source().contains("func advance(periods: int)"),
		true,
		"and its one verb takes an explicit whole-period count"
	)


func test_surplus_periods_are_dropped_rather_than_banked() -> void:
	# ADR 0179 / `world_pulse.gd:90-94`: a banked surplus is a backlog that pays out at a rate
	# nobody chose. Thirteen periods in one call resets the counter rather than leaving one
	# period owed, so the NEXT save is a full schedule away and not one period after this one.
	var clock := SaveClock.new()
	assert_eq(clock.advance(SaveClock.AUTOSAVE_PERIODS + 1), true, "the boundary is crossed")
	assert_eq(clock.advance(1), false, "and the surplus is gone, not owed")
	# One period is counted above, so ten more reach eleven and the twelfth fires — a banked
	# surplus would have made the next `advance(1)` land on the boundary instead.
	for i in range(SaveClock.AUTOSAVE_PERIODS - 2):
		assert_eq(clock.advance(1), false, "a fresh full schedule (period %d of 11)" % (i + 2))
	assert_eq(clock.advance(1), true, "which fires on its own boundary")


func test_a_zero_or_negative_count_is_not_elapsed_time() -> void:
	# A caller that moved no periods is not an autosave boundary and not an error. Before the
	# period-driven change this was the one input that could still fire the schedule
	# (`delta > 0.0` was the only gate on the resetting branch).
	var clock := SaveClock.new()
	for _i in range(SaveClock.AUTOSAVE_PERIODS + 4):
		assert_eq(clock.advance(0), false, "zero is not time")
		assert_eq(clock.advance(-1), false, "negative is not time")
	assert_eq(clock.advance(1), false, "only one period has really passed")


func test_reset_clears_the_schedule_so_a_new_game_inherits_nothing() -> void:
	# A fresh run must not start a period short of its first autosave. The counter is session
	# state, and `reset` is what a new game calls.
	var clock := SaveClock.new()
	clock.advance(SaveClock.AUTOSAVE_PERIODS - 1)
	clock.record_saved()
	clock.reset()
	assert_eq(clock.saves(), 0, "a fresh clock records nothing until it fires")
	for i in range(SaveClock.AUTOSAVE_PERIODS - 1):
		assert_eq(clock.advance(1), false, "a fresh clock starts empty (period %d)" % (i + 1))
	assert_eq(clock.advance(1), true, "and fires on its own first full schedule")


func test_the_schedule_keeps_no_wall_clock_no_ratio_and_no_frame_driver() -> void:
	# DEF-0111 and ADR 0179, and the reason the schedule is a counter: a wall-clock deadline
	# inside persisted state is a recorded defect here. `tools arch` cannot see a module's
	# clock, so this reads the source.
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


## The save module's CODE, with whole-line `##` comments removed, so the boundary guard reads the
## declarations rather than the prose that explains them.
func _save_clock_source() -> String:
	return _code_only(FileAccess.get_file_as_string("res://src/modules/save/save_clock.gd"))


func test_no_shipped_caller_drives_the_autosave_from_a_frame_delta() -> void:
	# ADR 0179, and the rule the whole decision exists to serve: an accrual verb takes an
	# explicit count from the caller that owns time. `poll_save` used to be handed the engine's
	# `delta` from the one `_process`, which is the defect's last remaining seam — fix the
	# clock and a frame callback still hands the save a duration.
	#
	# Read CODE, not raw text: `poll_save`'s own docstring names the frame delta it no longer
	# takes, so an unstripped scan would fail on the explanation.
	var offenders: Array[String] = []
	for path in _source_files("res://src"):
		var source := _code_only(FileAccess.get_file_as_string(path))
		for line in source.split("\n"):
			var code := String(line)
			if code.contains("poll_save(delta)") or code.contains("clock.pull("):
				offenders.append("%s: %s" % [path.get_file(), code.strip_edges()])
	assert_eq(
		offenders,
		[],
		(
			"the autosave is period-driven: nothing may hand it seconds (ADR 0179). Found: "
			+ str(offenders)
		)
	)


func test_the_autosave_is_fed_by_the_world_fold_and_nothing_else() -> void:
	# The periods have to come from SOMEWHERE, and the honest place is the explicit path that
	# already computes whole periods (`WorldPulse.advance_periods`). Pinned structurally
	# because a second accrual path is exactly what ADR 0173's rule refuses: `advance_world`
	# calls `poll_save`, and `poll_save` is the only thing that asks the schedule anything.
	var play := _code_only(FileAccess.get_file_as_string("res://src/app/item_workbench_play.gd"))
	assert_eq(
		play.contains("func poll_save(periods: int)"), true, "the verb takes a whole-period count"
	)
	assert_eq(
		play.contains("SaveApi.clock.advance(periods)"),
		true,
		"and hands it to the schedule as periods rather than converting anything"
	)
	assert_eq(
		play.contains("poll_save(_advanced_by(outcome))"),
		true,
		"and is fed by the world fold's own report, which knows how many periods it moved"
	)


# --- The design rule: no backup affordance --------------------------------------


func test_no_shipped_caller_can_name_the_backup_slot() -> void:
	# ## What this guard measures, and what it used to measure
	#
	# It used to grep CODE for five forbidden VERB SPELLINGS (`load_backup`, `restore_backup`,
	# `rollback`, `revert_save`, `SLOT_BACKUP`). **A name list cannot tell a working guard from
	# a deleted one**: `SaveStore._read(SavePaths.BACKUP)` handed to a screen contains none of
	# them and passes completely, and so does any differently-spelled affordance. That is BL-0886
	# — the predicate is theatre while the population was sound.
	#
	# It now enumerates every READ of the backup VALUE in `res://src` and classifies each one.
	# The needle is `SavePaths.BACKUP`, the only way to name the slot's content — `SavePaths`
	# publishes `PRIMARY`, `BACKUP`, `TEMP` and nothing else — so this is a census of readers,
	# not a list of forbidden words: a NEW verb, a new caller, a new module all appear in the
	# census and must classify.
	#
	# ## The two admissible shapes, and why each is safe
	#
	# 1. a `FileAccess.file_exists` PROBE — reports whether a file is there, never what is in
	#    it. `api.gd:171` (the `backup_present` summary flag) and `world_ledger_store.gd:343`
	#    (the "is any save on disk" probe) are the two shipped examples.
	# 2. `save/store.gd`'s own PRIVATE RECOVERY inside `restore()` — reached only when the
	#    primary is unreadable, and it returns an envelope to the restore path, not to a
	#    player-selectable verb.
	#
	# Anything else is a read of backup CONTENT outside the save module, and it fails here.
	var sources := _source_files("res://src")
	# **The population assertion belongs IN this guard, not beside it.** An empty walk would
	# otherwise report `unreaders == []` — byte-identical to a tree with no backup reader at
	# all, and therefore an all-clear that no player action could ever turn red.
	assert_eq(
		sources.size() >= SOURCE_FILE_FLOOR,
		true,
		(
			(
				"the backup guard read %d .gd files under res://src, below the floor of %d: its "
				% [sources.size(), SOURCE_FILE_FLOOR]
			)
			+ (
				"census would be an empty list rather than a clean tree. `ContentScan.files_under` "
				+ "defaults its suffix to `.tres` — pass `.gd` EXPLICITLY in `_source_files`."
			)
		)
	)
	var read: Array[String] = []
	var offenders: Array[String] = []
	for path in sources:
		# Read CODE, not raw text: this suite's own docstring names the backup slot and every
		# forbidden verb, so an unstripped scan matches the prose and reports correct code as
		# an affordance. A guard that fires on its own documentation is one nobody trusts.
		var source := _code_only(FileAccess.get_file_as_string(path))
		if not source.contains(BACKUP_READER):
			continue
		for line in source.split("\n"):
			var code := String(line).strip_edges()
			if not code.contains(BACKUP_READER):
				continue
			read.append("%s: %s" % [path.get_file(), code])
			if _is_an_admissible_backup_read(path, code, source):
				continue
			offenders.append(
				(
					(
						"%s reads the backup CONTENT and is not one of the two admissible shapes "
						% path.get_file()
					)
					+ "(a `file_exists` probe, or save/store.gd's private fallback): %s" % code
				)
			)
	# The census must FIND the readers, or "classified every reader legally" is an empty list.
	# Measured 2026-10-07: two code sites name the backup literally in res://src —
	# api.gd (`backup_present` probe) and app/world_ledger_store.gd (exists probe).
	# Two more readers exist but resolve per-slot through `SavePaths.for_slot`
	# rather than naming the literal: save_store.gd's rotation write and its
	# private fallback (ADR 0903). They did not become unnecessary; they moved
	# behind the resolver, which this literal needle cannot see. The floor is
	# ONE below the literal population, so a reader that stops existing is
	# caught rather than silently shrinking the population the verdict is read
	# against.
	assert_eq(
		read.size() >= BACKUP_READER_FLOOR,
		true,
		(
			(
				"the backup census found %d read(s) of %s in res://src, below the floor of %d: a "
				% [read.size(), BACKUP_READER, BACKUP_READER_FLOOR]
			)
			+ (
				"shrinking census is a blind guard, and an empty one is indistinguishable from a "
				+ "clean tree. Check the shipped readers, then say which became unnecessary."
			)
		)
	)
	assert_eq(offenders, [], "no shipped caller can obtain backup CONTENT")


## Whether `code` is one of the two admissible shapes, spelled out rather than matched by name.
##
## `file` and `source` are both needed because the private-fallback half is a POSITION
## question — "inside `restore()`" cannot be read off the single line — and answering it
## requires the file's function layout.
func _is_an_admissible_backup_read(file: String, code: String, source: String) -> bool:
	# Shape 1: a probe. It asks whether a file is there and never what is in it, so no caller
	# can obtain an envelope from it however the result is used.
	if code.contains("FileAccess.file_exists("):
		return true
	# Shape 2: the save module's own private recovery. `save/store.gd` is inside the module
	# that OWNS the rotation, so the writer and the recovery reader are the same file by
	# design; what must not exist is a second reader anywhere else.
	if file != SAVE_STORE_PATH:
		return false
	return _function_body(source, "restore").contains(BACKUP_READER)


## The CODE of `func <name>` — instance or `static func` — up to the next top-level `func`,
## with comments already stripped. GDScript has no nested `func`, so a trimmed line beginning
## `func ` is always a top-level declaration and no brace counting is needed.
func _function_body(source: String, func_name: String) -> String:
	var collecting := false
	var out: PackedStringArray = []
	var header := "func %s(" % func_name
	for line in source.split("\n"):
		var code := String(line).strip_edges()
		if code.begins_with("func ") or code.begins_with("static func "):
			collecting = code.contains(header)
		if collecting:
			out.append(String(line))
	return "\n".join(out)


func test_the_facade_exposes_no_backup_slot_constant() -> void:
	# The other half: a caller cannot name the backup because there is no name for it. The only
	# slot the facade publishes is the live one. Read from CODE, since the facade's docstring
	# discusses the backup slot by name.
	var source := _code_only(FileAccess.get_file_as_string("res://src/modules/save/api.gd"))
	assert_eq(source.contains('&"backup"'), false, "the facade names no backup slot")
	assert_eq(String(SaveApi.SLOT), "primary", "the one slot is the live one")


func test_no_facade_verb_takes_a_path_or_a_slot_a_caller_could_name_the_backup_with() -> void:
	# ## Why a census is not sufficient on its own
	#
	# The census above enumerates readers that EXIST today. It cannot see a verb that does not
	# exist yet — and the shape ADR 0128 forbids is exactly that: a facade method
	# `restore(slot)` or `load(path)` would let a caller pass `SavePaths.BACKUP` in a way no
	# reader census can see, because the backup would then be named by the CALLER's argument
	# rather than by a literal inside `res://src`.
	#
	# So this asserts the second half structurally: **no shipped save facade or store method
	# takes a path or slot parameter at all.** `restore()` takes nothing and answers for the
	# live slot; `_read(path)` is the store's own private helper and is the only thing that
	# accepts one. Adding a parameter is a design change to ADR 0128 and this turns it RED.
	#
	# Read from CODE, because every one of these files documents the backup in prose that a
	# raw scan would match.
	for path in [
		"res://src/modules/save/api.gd",
		"res://src/modules/save/save_store.gd",
		"res://src/modules/save/save_paths.gd",
		"res://src/modules/save/save_slot.gd",
		"res://src/modules/save/save_migrate.gd",
		"res://src/modules/save/save_clock.gd",
	]:
		var offenders: Array[String] = []
		var source := _code_only(FileAccess.get_file_as_string(path))
		assert_eq(source.is_empty(), false, "%s is readable" % path)
		for line in source.split("\n"):
			var code := String(line).strip_edges()
			if not code.begins_with("func "):
				continue
			# The ONE sanctioned parameterised read, and it is the store's private helper:
			# `_read(path)` is what `restore()` and the generation probes call, and it is
			# underscore-private, so a caller outside the module cannot reach it.
			# `save_store.gd` by full path, matching [constant SAVE_STORE_PATH] rather than by
			# file name.
			if path == SAVE_STORE_PATH and code.contains("func _read("):
				continue
			for parameter in _slot_naming_parameters(code):
				offenders.append("%s: %s" % [path.get_file(), code])
		assert_eq(
			offenders,
			[],
			(
				(
					"no save facade or store verb takes a %s argument, so no caller can name a "
					% _SLOT_ARGUMENT_NAMES[0]
				)
				+ (
					"slot it did not get from the game (ADR 0128). Found: "
					+ str(offenders)
					+ ". The private store helper `_read(path)` is the sole exception and is "
					+ "underscore-private by name."
				)
			)
		)


## The slot-naming parameters in one `func` signature line, as the declared parameter names.
## Split on top-level commas so a defaulted `slot: StringName = &""` stays one parameter, and
## an untyped `path)` still yields `path`.
func _slot_naming_parameters(code: String) -> Array[String]:
	var open := code.find("(")
	var close := code.rfind(")")
	if open < 0 or close <= open:
		return []
	var found: Array[String] = []
	var depth := 0
	var current := ""
	for index in range(open + 1, close):
		var character := code[index]
		if character == "(" or character == "[" or character == "{":
			depth += 1
		elif character == ")" or character == "]" or character == "}":
			depth -= 1
		if character == "," and depth == 0:
			found.append(current.strip_edges())
			current = ""
			continue
		current += character
	if not current.strip_edges().is_empty():
		found.append(current.strip_edges())
	var out: Array[String] = []
	for parameter in found:
		var name := parameter.split(":")[0].strip_edges()
		var lowered := name.to_lower()
		for candidate in _SLOT_ARGUMENT_NAMES:
			if lowered.contains(candidate):
				out.append(name)
				break
	return out


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
##
## **The suffix is passed EXPLICITLY and that is the whole point of this helper existing.**
## `ContentScan.files_under` defaults its suffix to `.tres` — authored content, the one thing a
## source scan never wants — so a call that omits it walks the `.tres` files, and the `.gd`
## filter below then discards every single one it found. This helper read ZERO of the 487
## GDScript files in `res://src` while reading as a guard over all of them: a mutation probe
## that added a `restore_backup_verb()` caller to `app/item_workbench_app.gd` left the suite at
## 61 passed, 0 failed. The sibling guard in `criterion/test_failure_branches_reachable.gd`
## passes `".gd"` explicitly and is sound; this is that precedent copied.
##
## The suffix therefore may NOT be dropped here, and `test_the_backup_guard_actually_reads_the
## source_tree` is the assertion that makes forgetting it a failure rather than an all-clear.
func _source_files(root: String) -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files_under(root, ".gd"):
		if path.get_file().ends_with(".gd"):
			out.append(path)
	return out


## The population assertion the backup guard needs and did not have.
##
## **A guard that silently inspects nothing is the failure class this repo records as "a guard
## nobody has seen fire is not a guard"** — and that is exactly what `test_no_shipped_caller_can
## _name_the_backup_slot` was. It asserted `offenders == []` over an empty file list, which is
## the same answer a tree with no backup affordance gives, so the mutation probe passed it. This
## turns an empty walk into a FAILURE: the scan must find real GDScript before its "found none"
## verdict means anything.
##
## Two floors rather than one, because they catch different failures: `> 0` catches the walk
## returning nothing at all, and the named floor catches the walk silently covering a fraction of
## the tree — a suffix typo, a depth cap hit early, a root that moved — which is a guard that
## reads as an all-clear for every file it no longer sees.
func test_the_backup_guard_actually_reads_the_source_tree() -> void:
	var found := _source_files("res://src")
	assert_eq(
		found.size() > 0,
		true,
		(
			(
				"the backup guard's walk returned zero .gd files. `ContentScan.files_under` "
				+ "defaults its suffix to `.tres`, so the scan is inspecting authored content and "
				+ "the `.gd` filter discards every file it finds — `test_no_shipped_caller_can_"
			)
			+ (
				"name_the_backup_slot` is reporting all-clear over an empty list, not over the "
				+ "source tree."
			)
		)
	)
	assert_eq(
		found.size() >= SOURCE_FILE_FLOOR,
		true,
		(
			(
				"the backup guard read %d .gd files under res://src, below the floor of %d "
				% [found.size(), SOURCE_FILE_FLOOR]
			)
			+ (
				"measured 2026-10-04 at 487. A guard covering a fraction of the tree cannot "
				+ "report a clean one."
			)
		)
	)
	# And the walk must be reaching the file the audit mutated, so "it read a plausible number"
	# is not satisfied by a walk that stops two directories in.
	assert_eq(
		found.has("res://src/app/item_workbench_app.gd"),
		true,
		"the walk reaches the composition root, which is where the backup caller was injected"
	)


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
