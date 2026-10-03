extends TestCase

## ADR 0106's definition of done: the COMPOSITION ROOT ticks the status clock.
##
## ## Why this file exists at all
##
## Measured 2026-10-03, `Actor.tick_statuses` and `StatusApi.tick_statuses` had no
## production caller in `game/src` — ADR 0089 recorded that and ADR 0056's deletion of
## `InputHandler` took the last one with it. `StatusLoop` existed, fully tested, and
## nothing in the shipped game ever called it. A status system nobody can tick is
## decoration: no burn spent a pulse, nothing expired.
##
## ## What this suite therefore does NOT do
##
## It never calls `StatusLoop.tick` or `StatusApi.tick_statuses` directly. That is
## precisely the shape that hid the original defect for five waves — a suite that
## drives the loop itself stays green the day the production caller is deleted. Here
## the ONLY clock is `_process` on the mounted `ItemWorkbenchApp`, driven through
## `SeamHarness`, which parents the real `ItemWorkbenchApp.tscn` under the tree root
## the way a game boot does. Delete `_process` from `item_workbench_app.gd` and every
## case below fails.

## One quarter-second frame, at the same 60 Hz the engine runs at. A headless test
## passes its OWN delta rather than reading a clock (ADR 0089): `Time.get_ticks_*` is
## forbidden in this repo, and the point of the rule is that the elapsed time comes
## from whoever owns time.
const FRAME := 1.0 / 60.0

var _harness: SeamHarness = null


func setup() -> void:
	_harness = null
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	_harness = null


## The mounted app, or a recorded failure and null. A `_boot` that returned a harness
## with a boot error would let every case below compare against a null actor.
func _boot() -> SeamHarness:
	var harness := SeamHarness.mount_new()
	_harness = harness
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	return harness if harness.boot_error == "" else null


## Drive the composition root's OWN frame callback, `frames` times. This is the whole
## point of the file: the entry under test is `ItemWorkbenchApp._process`, never
## `StatusLoop.tick`, so a green run is evidence about production wiring rather than
## about a wire's own unit test.
func _frames(app: Node, frames: int) -> void:
	assert_eq(app.has_method(&"_process"), true, "the composition root declares _process")
	if not app.has_method(&"_process"):
		return
	for frame in frames:
		app.call("_process", FRAME)


func test_the_mounted_root_drives_the_status_clock() -> void:
	var harness := _boot()
	if harness == null:
		return
	assert_eq(harness.app.has_method(&"_process"), true, "the root owns a per-frame callback")
	# A burn the player can see is the load-bearing claim: it is applied to the APP's
	# own actor — the one `SeamHarness` read off the mounted root, not one a test
	# built — and it is spent by frames the root received.
	var applied := StatusApi.apply(harness.actor, &"fire_immolation", 3.0)
	assert_eq(bool(applied["ok"]), true, "the burn applies to the app's own actor")
	var before := harness.actor.resource(&"health").current
	_frames(harness.app, 240)
	assert_eq(harness.actor.has_status(&"fire_immolation"), true, "the status is still live")
	assert_eq(
		before - harness.actor.resource(&"health").current > 0.0,
		true,
		"and four seconds of mounted frames spent its pulse — through _process"
	)


func test_the_root_ages_a_status_to_expiry_across_frames() -> void:
	# Expiry is the other half of "nobody can tick": without a caller nothing ever
	# reaches `remaining <= 0`. `metal_sunder` is authored at a 10.0s duration, so
	# 720 quarter-second frames are well past it.
	#
	# The modifier count is asserted RELATIVE, not as zero. The app's hero carries the
	# sect and clan ledgers plus whatever the mount attached, so an exact zero would be
	# a claim about the composition root's attach order rather than about the status
	# clock. What the status module must not do is leave its OWN modifiers behind, and
	# releasing them is what `_prune` does on the way out.
	var harness := _boot()
	if harness == null:
		return
	var before := harness.actor.stats.modifier_count()
	var applied := StatusApi.apply(harness.actor, &"metal_sunder", 1.0)
	assert_eq(bool(applied["ok"]), true, "the debuff applies")
	assert_eq(
		harness.actor.stats.modifier_count() > before,
		true,
		"and it holds the authored modifiers while it is live"
	)
	_frames(harness.app, 720)
	assert_eq(harness.actor.has_status(&"metal_sunder"), false, "expired through app/ wiring")
	assert_eq(
		harness.actor.stats.modifier_count(),
		before,
		"and its modifiers were released back to what the actor carried"
	)


func test_the_frames_the_root_drives_are_the_ones_the_actor_sees() -> void:
	# The claim that separates "the root ticks" from "the root happens to call something".
	# One interval's worth of elapsed time must produce the module's pulse count and no
	# more: a root that multiplied `delta`, or a loop that ran its own clock, would
	# either double-spend or drift, and the drift only shows up against a figure read
	# off the same authored def the module spends from.
	var harness := _boot()
	if harness == null:
		return
	StatusApi.apply(harness.actor, &"fire_immolation", 3.0)
	var def := StatusApi.definition(&"fire_immolation")
	var share := float(def.payload.get("share_per_pulse", 0.0))
	var interval := maxf(0.001, def.tick_interval)
	var frames := int(ceil(interval / FRAME))
	_frames(harness.app, frames)
	var report := StatusApi.summary(harness.actor)
	var active := report.get("active", []) as Array
	var pulses := 0
	for entry in active:
		pulses += int((entry as Dictionary).get("ticks_elapsed", 0))
	# One interval came due in one interval of frames: the counter is the module's, read
	# through the facade, and it is exactly one.
	assert_eq(float(active.is_empty()), 0.0, "the burn is still on the actor")
	assert_eq(pulses, 1, "exactly one pulse came due in one authored interval")
	var spent := (
		harness.actor.resource(&"health").maximum - harness.actor.resource(&"health").current
	)
	# The first pulse pays the un-escalated share: `ticks_elapsed` is incremented
	# BEFORE `_pulse` runs, so pulse 1 is the index-0 term of the escalation curve.
	assert_eq(spent >= 3.0 * share, true, "the pulse spent the authored share of the potency")
	assert_eq(
		spent < 3.0 * share * 2.0,
		true,
		"and not a second one, so the root is not over-ticking the frame it was given"
	)


func test_a_frame_with_no_elapsed_time_changes_nothing() -> void:
	# The `delta <= 0.0` guard. A paused or first frame must not age a status, and must
	# not be the thing that makes the root crash either.
	var harness := _boot()
	if harness == null:
		return
	StatusApi.apply(harness.actor, &"fire_immolation", 2.0)
	var before := harness.actor.resource(&"health").current
	var remaining := float(StatusApi.summary(harness.actor)["active"][0]["remaining"])
	harness.app.call("_process", 0.0)
	assert_eq(harness.actor.resource(&"health").current, before, "a zero delta spends no pulse")
	assert_eq(
		float(StatusApi.summary(harness.actor)["active"][0]["remaining"]),
		remaining,
		"and ages nothing"
	)


func test_the_root_never_reads_a_wall_clock() -> void:
	# ADR 0089's rule, stated where the clock now lives. `delta` is a parameter here; a
	# `Time.get_ticks_*` in this file would make a status age differently under a test,
	# a replay and a frame that hitched — and it is a read no assertion can see.
	#
	# Comments are stripped first, for the same reason `test_ui_conventions` does it:
	# the file explains WHY the wall clock is absent, and a doc comment is not a
	# violation.
	var code := _code_only("res://src/app/item_workbench_app.gd")
	assert_ne(code.is_empty(), true, "the composition root's source is readable")
	assert_eq(code.contains("Time.get_ticks"), false, "no wall-clock tick read")
	assert_eq(code.contains("Time.get_datetime"), false, "and no wall-clock date read")


func test_the_status_tick_has_exactly_one_caller_in_the_shipped_program() -> void:
	# ADR 0106's named failure is a SECOND clock: `ui/` grows a `_process`, or a module
	# invents one, and a status ages at two different rates depending on which screen is
	# mounted. Scanned over `game/src` — not over `item_workbench_app.gd` alone —
	# because a scan of one file cannot catch the duplication that is the whole risk.
	#
	# `player_adapter.gd` carries a real `_physics_process` (ADR 0106 records it) but is
	# mounted by NO `.tscn`, so it is not a second clock in the running game. It is
	# named here rather than ignored, because a driver some future scene mounts would
	# then be a second clock this allowlist had already blessed.
	var callers: Array[String] = []
	for path in _gdscript_files("res://src"):
		# `status_loop.gd` is the wire the root holds, so the reference it makes is
		# the CALL this scan is looking for, not a second clock. Excluded by name, and
		# asserted below to be the only such exemption.
		if path == "res://src/app/status_loop.gd":
			continue
		var code := _code_only(path)
		if code.contains("StatusApi.tick_statuses(") or code.contains("StatusLoop.new("):
			callers.append(path.trim_prefix("res://"))
	callers.sort()
	assert_eq(
		callers,
		["src/app/item_workbench_app.gd"],
		"the composition root is the only thing that builds a status loop or ticks one"
	)
	# And the other way round: a frame driver is a clock whoever owns it. These are the
	# three the tree ships today — the root (ADR 0106), the headless nav probe that reads
	# one snapshot per frame, and the unmounted `PlayerAdapter` body. Any NEW one is a
	# second clock and belongs in that list deliberately, with a reason.
	var drivers: Array[String] = []
	for path in _gdscript_files("res://src"):
		var code := _code_only(path)
		if code.contains("func _process(") or code.contains("func _physics_process("):
			drivers.append(path.trim_prefix("res://"))
	drivers.sort()
	# Spelled with the `src/` prefix the scan actually produces, so a path change shows
	# up as a failure naming the file rather than as a silent `has()` miss.
	assert_eq(
		drivers,
		[
			"src/app/item_workbench_app.gd",
			"src/app/nav_probe.gd",
			"src/app/player_adapter.gd",
		],
		"exactly the frame drivers the tree ships, no more"
	)


func test_the_status_clock_leaves_the_save_payload_alone() -> void:
	# ADR 0089's persistence rule, restated for the change that gives the clock a
	# caller. Ticking is a SESSION concern: nothing this file does — building the loop,
	# passing the engine's `delta`, advancing the runtime table — may reach the save
	# payload. `SCHEMA_VERSION` is the whole contract for that: a `delta` that changed
	# the schema would make a designer retune silently rewrite every old save.
	#
	# `to_dict()` is NOT asserted to be status-free, because that half is
	# `core/actor.gd`'s to decide and not this file's: the payload is whatever the actor
	# serializes, and a status that reached it would be a `core/` finding under a
	# different owner. What IS pinned here is the part this change could have broken —
	# the payload does not move between a ticked actor and an untouched one, in any key
	# the status module could have reached.
	var harness := _boot()
	if harness == null:
		return
	var before := harness.actor.to_dict()
	# An empty payload means `to_dict()` never ran, which would make every assertion
	# below pass vacuously — so the guard is on the SHAPE, not on emptiness.
	assert_eq(before.has("version"), true, "the app's actor serialises a real payload")
	assert_eq(before.has("id"), true, "with the identity a save needs")
	StatusApi.apply(harness.actor, &"fire_immolation", 2.0)
	_frames(harness.app, 90)
	assert_eq(harness.actor.has_status(&"fire_immolation"), true, "the burn is live while ticking")
	var ticked := harness.actor.to_dict()
	assert_eq(int(ticked["version"]), 4, "schema version is unchanged at 4")
	assert_eq(String(ticked["id"]), String(harness.actor.id), "and the actor reserializes itself")
	# The keys a status runtime could have spilled into are all absent. Nothing this
	# change added reaches the payload: the runtime table is a `WeakRef` map inside the
	# status module, never module data, so a frame cannot move a byte of a save.
	for key in ["status_runtime", "status_runtimes", "status_state", "status_tick"]:
		assert_eq(ticked.has(key), false, "the payload gained no '%s' key" % key)
	assert_eq(
		ticked.keys().size(),
		before.keys().size(),
		"and ticking added no slot to the payload at all"
	)


## `path`'s text with comments and string literals removed, so a scan reads code and not
## prose. The composition root explains WHY it holds no wall clock, and a doc comment
## must not be the thing that fails its own rule — the same reason
## `tests/ui/test_ui_conventions.gd` strips comments before it scans.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var hash := raw.find("#")
		var line := raw.substr(0, hash) if hash >= 0 else raw
		out.append(line)
	return "\n".join(out)


## Every `.gd` under `root`, recursively, excluding the editor's own `addons/`.
func _gdscript_files(root: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				if entry != "addons":
					found.append_array(_gdscript_files(path))
			elif entry.ends_with(".gd"):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
