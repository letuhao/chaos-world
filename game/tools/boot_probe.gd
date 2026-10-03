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
## The loot screen's own controls, by unique name. Named here because they are the
## production seam being driven, not because the probe should know the screen's guts.
const ENTER_BUTTON := "%EnterButton"
const STRIKE_BUTTON := "%StrikeButton"
## The app's strike deals 25 and the lowest authored boss has 100 vitality, so four
## strikes is the whole fight. A cap, never "until it dies" — see `_strike_until_dead`.
const MAX_STRIKES := 8


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
	var nav_report: Dictionary = await _press_nav(app)
	report["nav"] = nav_report
	var hunt_report: Dictionary = await _hunt(app)
	report["hunt"] = hunt_report
	var broken: Array[String] = []
	if not bool(nav_report.get("ok", false)):
		broken.append(
			"its navigation is dead: %s" % nav_report.get("why", "a nav button did nothing")
		)
	if not bool(hunt_report.get("ok", false)):
		broken.append(
			"its hunt mints nothing: %s" % hunt_report.get("why", "the fight did nothing")
		)
	if bool(report.get("ok", false)) and not broken.is_empty():
		# Came up, but you cannot go anywhere or fight anything. That is the same
		# failure a player sees as a window with nothing in it, so it must not read as
		# a pass. Each half is named separately because they are separate faults.
		report["ok"] = false
		report["why"] = "the shell came up but " + "; and ".join(broken)
	# Detach before freeing: the engine holds the parent pointer, and this probe
	# shares the process with nothing else, so leaving the subtree parented would
	# only leak it (AGENTS.md, the free-not-queue_free rule).
	root.remove_child(app)
	app.free()
	_emit(report)
	quit(EXIT_OK if bool(report.get("ok", false)) else EXIT_FAIL)


## Press a REAL nav bar button in a REAL boot and report where it took the game.
##
## This is the half the headless suite structurally cannot prove. `SeamHarness`
## mounts the app into a root that is not yet inside the tree, so the engine never
## delivers `_ready` to the bar and the suite has to call the app's `_ready` by hand;
## anything the bar does in its own `_ready` is therefore never exercised there. A
## gate that only ever runs the harness is blind to exactly the wiring a player uses
## to move. Here the tree is live, `_ready` ran on its own, and the button is the one
## the composition root authored.
func _press_nav(app: Node) -> Dictionary:
	var nav := app.get_node_or_null("%NavBar")
	if nav == null:
		return {"ok": false, "why": "the app composes no %NavBar, so it offers no destinations"}
	var before := String(app.call(&"current_route"))
	var slots := ScreenRoutes.all()
	var index := _first_other_route(slots, before)
	if index < 0:
		return {
			"ok": false, "why": "the route table declares no destination other than '%s'" % before
		}
	var blocked := _why_unpressable(nav, index)
	if blocked != "":
		return {"ok": false, "why": blocked}
	var target := String(slots[index].get("scene", ""))
	(nav.get_node_or_null(NavBar.slot_unique_name(index)) as Button).pressed.emit()
	await process_frame
	var after := String(app.call(&"current_route"))
	var wrong := _why_wrong_landing(app, index, before, after, slots)
	if wrong != "":
		return {"ok": false, "why": wrong}
	return {"ok": true, "slot": index, "from": before, "to": after, "scene": target}


## The first slot that is not where the game already is. Pressing the route you are
## on proves nothing, so the probe needs a destination it is not already at.
func _first_other_route(slots: Array, before: String) -> int:
	for candidate in slots.size():
		if StringName(slots[candidate].get("id", "")) != StringName(before):
			return candidate
	return -1


## Why no player could press this slot. Empty means the control is genuinely live, so
## a failure after the press is the navigation's fault rather than the button's.
func _why_unpressable(nav: Node, index: int) -> String:
	var button := nav.get_node_or_null(NavBar.slot_unique_name(index)) as Button
	if button == null:
		return "the nav bar authors no button for slot %d" % index
	if button.disabled:
		return "slot %d is disabled, so no player can press it" % index
	if not button.visible:
		return "slot %d is hidden, so no player can press it" % index
	return ""


## Why the press did not land on the route the slot advertises. Empty is a pass.
func _why_wrong_landing(
	app: Node, index: int, before: String, after: String, slots: Array
) -> String:
	if after == before:
		return "pressing slot %d left the game on '%s'" % [index, before]
	var advertised := String(slots[index].get("id", ""))
	if StringName(after) != StringName(advertised):
		return "slot %d advertises '%s' but opened '%s'" % [index, advertised, after]
	if (app.call(&"summary") as Dictionary).get("screen", {}).is_empty():
		return "slot %d navigated to '%s' but mounted no screen" % [index, after]
	return ""


## Fight a boss to death in the RUNNING app and report what it minted.
##
## This is the objective's primary loop, walked by pressing the loot screen's own
## buttons: enter the domain, strike until the authored vitality pool is gone, and
## confirm a reward payload was minted with drops still pending. Nothing here grants
## an item or calls a facade directly, so a pass means the shipped controls produced
## the acquisition rather than that a test handed one over.
##
## Runs after `_press_nav`, which leaves the game on the loot route.
func _hunt(app: Node) -> Dictionary:
	var screen := _live_screen(app)
	if screen == null:
		return {"ok": false, "why": "the app has no live screen reporting state to fight from"}
	var before := screen.call(&"summary") as Dictionary
	if bool(before.get("in_domain", false)):
		return {"ok": false, "why": "a boss was already live before the player entered one"}
	if not _press(screen, ENTER_BUTTON):
		return {"ok": false, "why": "Enter domain is not a live control"}
	await process_frame
	if not bool((screen.call(&"summary") as Dictionary).get("in_domain", false)):
		return {
			"ok": false, "why": "entering the domain left no boss live, so nothing can be fought"
		}
	var fight := await _strike_until_dead(screen)
	var why := _why_fight_did_not_pay(screen, fight)
	if why != "":
		return {"ok": false, "why": why}
	var after := screen.call(&"summary") as Dictionary
	return {
		"ok": true,
		"strikes": int(fight.get("strikes", 0)),
		"reward_count": int(after.get("reward_count", 0)),
		"pending_drops": int(after.get("pending_drops", 0)),
	}


## The live screen, or null when the shell has nothing reporting state.
func _live_screen(app: Node) -> Node:
	var stack := app.get_node_or_null("%ScreenStack")
	if stack == null:
		return null
	var screen := stack.call(&"current") as Node
	if screen == null or not screen.has_method(&"summary"):
		return null
	return screen


## Why a fight that ran to completion did not mint an acquisition. Empty is a pass.
##
## Each branch is a different fault, so each is named separately: a vitality pool
## nothing spends, a boss nothing can kill, a kill that pays nothing, or a reward with
## nothing left to claim.
func _why_fight_did_not_pay(screen: Node, fight: Dictionary) -> String:
	var stopped := String(fight.get("why", ""))
	if stopped != "":
		return stopped
	var strikes := int(fight.get("strikes", 0))
	var after := screen.call(&"summary") as Dictionary
	if bool(after.get("in_domain", false)):
		return "%d strikes landed and the boss is still alive" % strikes
	if int(after.get("reward_count", 0)) < 1:
		return "the boss died and minted no reward at all"
	if int(after.get("pending_drops", 0)) < 1:
		return "the reward lists drops but none are pending to claim"
	return ""


## Press Strike while it is offered, and report how many it took. Bounded by
## MAX_STRIKES rather than "until it dies": the app's strike deals 25 and the lowest
## authored boss has 100 vitality, so four strikes is the whole fight. A boss that
## outlasts that is a content bug and must fail loudly instead of spinning
## (AGENTS.md, the runaway rule). Returns -1 when the cap was hit.
func _strike_until_dead(screen: Node) -> Dictionary:
	var strikes := 0
	while _strike_offered(screen):
		if strikes >= MAX_STRIKES:
			return {
				"strikes": strikes,
				"why":
				(
					"the boss outlived %d strikes; the authored vitality pool is not spent"
					% MAX_STRIKES
				),
			}
		if not _press(screen, STRIKE_BUTTON):
			return {
				"strikes": strikes,
				"why": "the screen offers a strike but its Strike control is not pressable",
			}
		strikes += 1
		await process_frame
	return {"strikes": strikes, "why": ""}


## Whether the screen itself says a strike is available.
##
## Read from the screen's published `enabled` rather than from the Button's own
## disabled flag. `enabled` is what the screen declares a player may do, and the
## button is only a view of it — looping on the view instead asks the control to
## decide the rules, and a button that stays enabled after the boss dies then keeps
## the fight alive forever.
func _strike_offered(screen: Node) -> bool:
	var enabled := (screen.call(&"summary") as Dictionary).get("enabled", {}) as Dictionary
	return bool(enabled.get("strike", false))


func _offered(screen: Node, unique_name: String) -> bool:
	var button := screen.get_node_or_null(unique_name) as Button
	return button != null and not button.disabled and button.visible


func _press(screen: Node, unique_name: String) -> bool:
	var button := screen.get_node_or_null(unique_name) as Button
	if not _offered(screen, unique_name):
		return false
	button.pressed.emit()
	return true


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
