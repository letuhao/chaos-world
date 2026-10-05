extends TestCase

## THE CONTRACT BETWEEN THE ROUTE TABLE AND THE SCREENS IT MOUNTS.
##
## `ItemWorkbenchApp._bind_route_screen` binds a mounted screen with
## `screen.call("setup", _actor)`. Nothing in the type system ties that call to the
## screen: a route names a scene by path, the scene names a script by `ext_resource`,
## and if EITHER link is wrong the mount still succeeds. The screen is pushed, it
## becomes the live screen, it reports no error, and it renders nothing — because
## every widget it holds was reading from an actor it was never given. A player sees
## an empty panel; every suite stays green. That is the failure this suite exists to
## make loud, and it is why the guard is structural rather than a `has_method`
## fallback in the app: a fallback silences the error and keeps the blank screen.
##
## Two directions, both needed, neither implying the other:
##
##  1. every route mounts a screen that can TAKE the actor — the scene loads, its
##     root carries a working script, and that script answers `setup` with exactly
##     one required argument, which is what the app's default binding arm passes;
##  2. every screen the app actually MOUNTED, with the app's own actor, reports a
##     non-empty `summary()` — the blank-screen detector, since a screen that
##     renders nothing is exactly `{}`.
##
## (1) reads the shipped route table and the shipped scenes, so it needs no running
## app and stays honest even while the composition root is broken. (2) drives the
## real app the way a player does, so it fails loudly rather than passing vacuously
## when the app cannot boot.
##
## The opposite direction — every shipped screen is routed, so none is reachable
## only by a test — is already guarded elsewhere, and duplicating it here would be a
## second thing that can be wrong: `test_ui_conventions.gd` and
## `tests/app/test_screen_reachability.gd` both assert it. Read those for "unrouted".

const SETUP := &"setup"
const SUMMARY := &"summary"
## What the app's default binding arm passes: `screen.call("setup", _actor)`. Every
## screen the default arm serves must therefore require EXACTLY this many
## arguments. The workbench is not an exception to the count — it is an exception to
## who calls it: `_bind_route_screen` also hands it the persistence callables `ui/`
## is not allowed to own (ADR 0027), and those are defaulted, so it still requires
## exactly one.
const BINDING_ARGS := 1
## Reported when the method is absent, so a label never reads "expected 1, got 0"
## for a screen that simply has no such method.
const NO_SETUP := -1

# --- 1. every route mounts a screen that can take the actor -------------------


func test_every_route_mounts_a_screen_that_takes_the_apps_actor() -> void:
	var routes := ScreenRoutes.all()
	assert_ne(routes.is_empty(), true, "the shipped route table is not empty, so the scan is real")
	for route in routes:
		var route_id := StringName(route.get("id", ""))
		var scene_path := String(route.get("scene", ""))
		assert_ne(String(route_id), "", "every route carries an id, so a failure can name it")
		var packed := load(scene_path) as PackedScene
		assert_ne(packed, null, "route '%s' loads %s" % [route_id, scene_path])
		if packed == null:
			continue
		var screen := packed.instantiate()
		assert_ne(screen, null, "route '%s' instantiates %s" % [route_id, scene_path])
		if screen == null:
			continue
		assert_eq(
			screen is Control,
			true,
			(
				"route '%s' mounts %s, whose root is not a Control, so the stack cannot hold it"
				% [route_id, scene_path.get_file()]
			)
		)
		# `has_method`, not a source read: the app asks the live node, so an inherited
		# `setup` counts. A screen that stops inheriting `UiScreen`, or whose script
		# stops compiling, answers false here and nowhere else complains.
		assert_eq(
			screen.has_method(SETUP),
			true,
			(
				(
					"route '%s' mounts %s, whose script does not answer %s(actor): the screen "
					% [route_id, scene_path.get_file(), SETUP]
				)
				+ "is handed no actor, renders blank, and reports nothing"
			)
		)
		if screen.has_method(SETUP):
			assert_eq(
				_required_args(screen, SETUP),
				BINDING_ARGS,
				(
					(
						"route '%s' mounts %s, whose %s() does not require exactly the actor "
						% [route_id, scene_path.get_file(), SETUP]
					)
					+ "the app passes it, so the binding call cannot be satisfied"
				)
			)
		assert_eq(
			screen.has_method(SUMMARY),
			true,
			(
				(
					"route '%s' mounts %s, which publishes no %s(): it is the screen's whole "
					% [route_id, scene_path.get_file(), SUMMARY]
				)
				+ "testable surface, so nothing can prove what it shows"
			)
		)
		screen.free()


# --- 2. a mounted screen shows something -------------------------------------


func test_every_screen_the_app_mounts_reports_what_it_renders() -> void:
	# `{}` is what a screen with no actor returns, by the documented screen contract
	# (`test_ui_conventions.gd` guards that half). So a MOUNTED screen whose summary
	# is also `{}` is indistinguishable from one that was handed nothing — and that
	# is the whole defect: it renders blank while every other signal says the route
	# works. Asserting non-empty is what turns a blank screen into a failure that
	# names the route and the screen.
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp boots, or nothing below is proven")
	if harness.boot_error != "":
		return
	for route in ScreenRoutes.all():
		var route_id := StringName(route.get("id", ""))
		var scene_path := String(route.get("scene", ""))
		var moved := harness.navigate(route_id)
		assert_eq(
			bool(moved["ok"]),
			true,
			"route '%s' mounts for a player: %s" % [route_id, moved["note"]]
		)
		if not bool(moved["ok"]):
			continue
		var live := harness.live_screen()
		assert_ne(live, null, "route '%s' left a live screen" % route_id)
		if live == null:
			continue
		assert_eq(
			harness.bound_actor(live),
			harness.actor,
			(
				(
					"route '%s' shows %s, which is not bound to the app's actor, so it can only "
					% [route_id, scene_path.get_file()]
				)
				+ "render an empty view"
			)
		)
		if not live.has_method(SUMMARY):
			continue  # already reported, by name, by the structural half
		var view: Variant = live.call(SUMMARY)
		assert_eq(
			view is Dictionary and not (view as Dictionary).is_empty(),
			true,
			(
				(
					"route '%s' mounted %s with the app's actor and it reports nothing, so "
					% [route_id, scene_path.get_file()]
				)
				+ "the player sees an empty screen"
			)
		)


func teardown() -> void:
	# The runner shares one process across every suite, and `SeamHarness` holds a
	# mounted app in a static, so an aborted test would leak it into the next one.
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


# --- Plumbing ---------------------------------------------------------------


## How many arguments `method_name` on `node` REQUIRES: declared parameters minus
## the ones carrying a default. The app calls `setup(actor)`, so only the required
## count decides whether that call can be satisfied.
##
## Read from the live node rather than from the script's own member list, so an
## inherited `setup` counts and a script that failed to compile is reported as absent
## (-1) instead of as zero arguments.
func _required_args(node: Node, method_name: StringName) -> int:
	for method in node.get_method_list():
		if StringName(method.get("name", "")) != method_name:
			continue
		var declared := (method.get("args", []) as Array).size()
		var defaulted := (method.get("default_args", []) as Array).size()
		return declared - defaulted
	return NO_SETUP
