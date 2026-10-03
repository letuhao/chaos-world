extends SceneTree

## Boot probe: does the shipped main scene actually COME UP, or merely not crash?
##
## `tools boot` already proves the engine survives N frames. That is not the same
## thing, and the difference is exactly where a shell hides: `ItemWorkbenchApp._ready`
## bails out quietly when it cannot find `%ScreenStack`, when the root route scene
## will not load, or when any module attach fails. Every one of those still exits
## 0 with a blank window, so a player gets nothing and the gate is green.
##
## So this mounts the REAL scene as a child of root, lets the engine deliver
## `_ready` and a few frames, and then asks the app to describe itself. It fails
## on the three things a player would notice first: no route, no actor, no screen
## on the stack.
##
## Runs under `--headless -s res://tools/boot_probe.gd`. The main scene is read
## from `application/run/main_scene`, never hardcoded, so this cannot drift onto a
## different scene than the one a player launches.
##
## Output is one `BOOTJSON <json>` line on stdout. Exit 0 means the shell came up.

const EXIT_OK := 0
const EXIT_FAIL := 1
## Frames to let the first layout, the workbench's own `_ready` and a `_process`
## tick settle before asking. Three is what "booted" means here.
const FRAMES := 3


func _initialize() -> void:
	# Deferred on purpose: the engine only delivers `_ready` once this returns and
	# the tree is inside itself. Calling straight from `_initialize` would mount
	# the app into a root that is not yet live, which is precisely the trap
	# `tests/ui/seam_harness.gd` works around by hand.
	_run.call_deferred()


func _run() -> void:
	var path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if path.is_empty():
		_emit({"ok": false, "why": "application/run/main_scene is not set"})
		quit(EXIT_FAIL)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_emit({"ok": false, "why": "could not load %s" % path})
		quit(EXIT_FAIL)
		return
	var app := packed.instantiate()
	if app == null:
		_emit({"ok": false, "why": "%s did not instantiate" % path})
		quit(EXIT_FAIL)
		return
	root.add_child(app)
	for _frame in FRAMES:
		await process_frame
	var report := _inspect(path, app)
	# Detach before freeing: the engine holds the parent pointer, and this probe
	# shares the process with nothing else, so leaving the subtree parented would
	# only leak it (AGENTS.md, the free-not-queue_free rule).
	root.remove_child(app)
	app.free()
	_emit(report)
	quit(EXIT_OK if bool(report.get("ok", false)) else EXIT_FAIL)


## Ask the app what it managed to build, then judge it. Every failure below is a
## way the shell comes up empty-handed, named so the message says which one.
func _inspect(path: String, app: Node) -> Dictionary:
	var scene_name := String(app.name)
	if not app.has_method(&"summary"):
		return {
			"ok": false,
			"why": "%s has no summary(); it cannot report what it mounted" % path,
			"scene": scene_name,
		}
	var summary: Dictionary = app.call(&"summary")
	var route := String(summary.get("route", ""))
	var actor_id := String(summary.get("actor_id", ""))
	var stack: Dictionary = summary.get("stack", {})
	var depth := int(stack.get("depth", 0))
	var screen: Dictionary = summary.get("screen", {})
	var report := {
		"ok": false,
		"scene": scene_name,
		"route": route,
		"actor_id": actor_id,
		"depth": depth,
	}
	if route.is_empty():
		report["why"] = (
			"no route is live: the shell mounted nothing at all"
			+ " (main scene %s; its root route scene will not load)" % path
		)
		return report
	if actor_id.is_empty():
		report["why"] = "route '%s' is live but no actor is bound" % route
		return report
	if depth < 1:
		report["why"] = "route '%s' is live but the screen stack is empty" % route
		return report
	if screen.is_empty():
		report["why"] = "route '%s' is live but its screen reports nothing" % route
		return report
	report["ok"] = true
	return report


func _emit(report: Dictionary) -> void:
	print("BOOTJSON %s" % JSON.stringify(report))
