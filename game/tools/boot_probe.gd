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
## The screen's own domain dropdown. Re-entering the same domain replays the same
## table every time, so a probe that only ever presses Enter learns one table's
## contents and then calls the whole corpus un-equippable. Walking this selector
## is what a player does when one place pays nothing worth wearing.
const DOMAIN_OPTION := "%DomainOption"
## The screen's own tier dropdown. A drop's grade scales with the tier it was
## fought at, and the grade gate refuses anything above the hero's own tier, so
## fighting the default tier can hand over gear this hero may not wear. A player
## picks the tier they can equip from; so does the probe.
const TIER_OPTION := "%TierOption"
## The screen's own Leave control. A sweep runs many fights, and entering a new
## domain while the last one is still live is refused, so every attempt after the
## first would fail on the previous attempt's leftovers. Leaving is also what a
## player does between hunts.
const LEAVE_BUTTON := "%LeaveButton"
## The reward list's row control, by node name rather than unique name: the rows are
## instantiated from `loot_drop_row.tscn`, so no single owner holds them all.
const REWARD_LIST := "%RewardList"
const DROP_ACTION := "DropAction"
## Recursion needs a depth cap like any other loop (AGENTS.md): a traversal with no cap
## is an unbounded loop the moment the tree it walks turns out to contain a cycle, and
## the `while`-scanning rules cannot see a recursive call at all. The reward list is
## three levels deep, so this is slack rather than a tuned number.
const MAX_WALK_DEPTH := 12
## How many pickup controls one fight's reward may offer. The loop that presses
## them is driven by a live screen, never by a snapshot, so it needs a fixed cap
## rather than a bound derived from what the screen happens to be showing.
const MAX_DROPS_PER_REWARD := 8
## How many domains the walk may fight before it insists none of them pays
## something the hero can wear. One boss is not a guarantee of gear: a fight may
## pay a consumable, a material, or a drop whose grade is above the hero's tier.
## The tables reference 1339 wearable equipment items and 188 of 1383 tables
## stock some a tier-1 hero can wear, so a handful of fights says more about the
## handful than about the corpus. Each attempt now covers a DIFFERENT domain's
## entry band rather than sliding along a diagonal, which is what let eight
## fights be read as the whole game (BL-0625, retracted). Wide enough to reach a
## table that stocks gear, capped so a corpus that pays nothing cannot spin.
const MAX_EQUIP_HUNTS := 24
## How many DOMAIN CELLS the sweep may visit before it gives up on reaching
## MAX_EQUIP_HUNTS real fights. Most of the corpus is above a starting hero's
## realm and refuses entry correctly, so attempts and fights are different
## budgets: bounding the walk by attempts starved it of actual fights, because
## the refusals consumed the cap. This outer bound is what makes the loop
## terminate at all -- `MAX_EQUIP_HUNTS` alone would not, since a corpus that
## refuses everything would walk it forever.
const MAX_SWEEP_CELLS := 160
## The app's strike deals 25 and the lowest authored boss has 100 vitality, so four
## strikes is the whole fight. A cap, never "until it dies" — see `_strike_until_dead`.
const MAX_STRIKES := 8
## The two routes the equip half walks between, and the controls it drives there.
## The hero screen is the honest observable for "the stats changed": it is what the
## player's own sheet shows, so this cannot pass by reaching past the UI into the actor.
const HOME_ROUTE := &"workbench"
const CHARACTER_ROUTE := &"character"
## Where a boss can be fought. Claiming a drop walks back to the workbench, so a
## second hunt has to come back here before it can press Enter on anything.
const LOOT_ROUTE := &"loot_encounter"
const EQUIP_BUTTON := "%EquipButton"
const ACTION_BAR := "%ActionBar"
const INVENTORY_PANEL := "%InventoryPanel"
const ITEM_LIST := "%ItemList"


## One sweep cell: the domain and tier this attempt chose. A helper rather than
## an inline literal because the loop built the same dictionary twice and gdformat
## reflowed both copies into a parenthesised call.
func _cell(where: Dictionary) -> Dictionary:
	return {"domain": where.get("domain", ""), "tier": where.get("tier", "")}


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
	var rows_at_boot := _bag_rows(app)
	report["rows_at_boot"] = rows_at_boot
	var nav_report: Dictionary = await _press_nav(app)
	report["nav"] = nav_report
	# One boss is not a guarantee of gear: a fight may pay a consumable or a token,
	# and neither can be worn. Keep hunting the way a player would, stopping at the
	# first drop the hero's own Equip control accepts. A fight that paid nothing
	# wearable is a corpus fact, so it is reported as such rather than papered over.
	var hunt_report: Dictionary = {}
	var claim_report: Dictionary = {}
	var equip_report: Dictionary = {}
	var attempts := 0
	var fights := 0
	var refused := 0
	var sweep: Array[Dictionary] = []
	# The verdict is built from the BEST cell, not the last one. A refusal on the
	# final cell used to make the whole probe report "its hunt mints nothing" even
	# when earlier cells fought, claimed and equipped cleanly, which is how a
	# working loop gets reported as a dead one.
	var best: Dictionary = {}
	for attempt in MAX_SWEEP_CELLS:
		attempts = attempt + 1
		if fights >= MAX_EQUIP_HUNTS:
			break
		var where: Dictionary = {}
		hunt_report = await _hunt(app, attempt, where)
		report["hunt"] = hunt_report
		var cell := _cell(where)
		# A domain the hero is not strong enough for is a GATE WORKING, not a
		# defect, and it is not a fight either. Counted apart from the hunt budget
		# so a corpus that is mostly out of reach cannot starve the sweep of real
		# fights before the cap is reached.
		if bool(hunt_report.get("refused", false)):
			refused += 1
			cell["refused"] = hunt_report.get("why", "the domain refused entry")
			sweep.append(cell)
			continue
		if not bool(hunt_report.get("ok", false)):
			cell["hunt"] = hunt_report.get("why", "minted nothing")
			sweep.append(cell)
			continue
		fights += 1
		claim_report = await _claim(app, rows_at_boot)
		report["claim"] = claim_report
		cell["def_ids"] = claim_report.get("def_ids", [])
		if not bool(claim_report.get("ok", false)):
			cell["claim"] = claim_report.get("why", "nothing claimed")
			sweep.append(cell)
			continue
		equip_report = await _equip(app, claim_report.get("def_ids", []))
		report["equip"] = equip_report
		if bool(equip_report.get("ok", false)):
			cell["worn"] = equip_report.get("def_id", "")
			cell["stat"] = equip_report.get("stat", "")
			best = {"hunt": hunt_report, "claim": claim_report, "equip": equip_report}
			sweep.append(cell)
			break
		cell["equip"] = equip_report.get("why", "could not be worn")
		sweep.append(cell)
		if String(equip_report.get("baseline_wearable", "")).is_empty():
			# Nothing at all equips, so the Equip control itself is dead. That is a
			# fault and repeating it would multiply one red.
			#
			# `wearable` is NOT the condition. It is false whenever THIS fight's drops
			# cannot be worn, and measured over the entry band that is the common case:
			# 264 of 331 tables a tier-1 hero can enter stock no mortal gear at all, and
			# the 67 that do carry it at median 4.2% per roll (BL-0625). Breaking on it
			# stopped the sweep after its first fight, which is what made 24 hunts and
			# 160 cells dead code and turned one unlucky roll into a claim about the
			# whole corpus -- the slice mistake that created BL-0625 in the first place.
			# A drop the hero's own control rejects is CONTENT; the control accepting
			# nothing at all is the seam.
			break
	if not best.is_empty():
		hunt_report = best["hunt"] as Dictionary
		claim_report = best["claim"] as Dictionary
		equip_report = best["equip"] as Dictionary
	report["hunts"] = fights
	report["cells"] = attempts
	report["refused"] = refused
	report["sweep"] = sweep
	var broken: Array[String] = []
	if not bool(nav_report.get("ok", false)):
		broken.append(
			"its navigation is dead: %s" % nav_report.get("why", "a nav button did nothing")
		)
	if not bool(hunt_report.get("ok", false)):
		broken.append(
			"its hunt mints nothing: %s" % hunt_report.get("why", "the fight did nothing")
		)
	if not bool(claim_report.get("ok", false)):
		broken.append(
			"its drops cannot be collected: %s" % claim_report.get("why", "nothing was claimed")
		)
	if not bool(equip_report.get("ok", false)):
		broken.append(
			(
				"what it collected changes nothing: %s"
				% equip_report.get("why", "equipping did nothing")
			)
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
## Move the domain selector onto the nth option, the way a player picking from
## the dropdown does, and return the label now showing.
## Walk the domain selector by TIER BAND rather than by attempt number.
##
## The nth attempt used to pick `domain[n]` and `tier[n]` together, so the walk
## travelled a diagonal through a grid of 160 domains by 2 tiers and sampled a
## slice of it. That is how eight fights came to be reported as the whole
## corpus: the slice missed the one table that stocks wearable gear, and a claim
## about the game was made from a sample. Covering the first TIER of every
## domain instead visits each domain's entry band, which is both a fairer sample
## and the band a starting hero can actually fight.
func _choose_domain(screen: Node, band: int) -> String:
	var option := screen.get_node_or_null(DOMAIN_OPTION) as OptionButton
	if option == null or option.item_count <= 0:
		return ""
	var index := band % option.item_count
	option.select(index)
	option.item_selected.emit(index)
	return String(option.get_item_text(index))


## Travel to the loot surface if the walk is not already there, and confirm there
## is a live screen to fight from.
func _ready_to_hunt(app: Node) -> Dictionary:
	var here := String(app.call(&"current_route"))
	if here != String(LOOT_ROUTE):
		var travel := await _goto(app, LOOT_ROUTE)
		if not bool(travel.get("ok", false)):
			var said := String(travel.get("why", ""))
			if said.is_empty():
				said = "travel reported no reason"
			return {"ok": false, "why": "from '%s': %s" % [here, said]}
	var screen := _live_screen(app)
	if screen == null:
		return {"ok": false, "why": "the app has no live screen reporting state to fight from"}
	if bool((screen.call(&"summary") as Dictionary).get("in_domain", false)):
		# Leave before fighting, not after: a sweep runs many fights, and the
		# refusal below fires the moment a boss is still live, so every attempt
		# after the first would fail on the previous attempt's leftovers. This is
		# also what a player does between hunts.
		if not _press(screen, LEAVE_BUTTON):
			return {"ok": false, "why": "a boss is still live and Leave is not a live control"}
		await process_frame
		screen = _live_screen(app)
		if screen == null:
			return {"ok": false, "why": "leaving the domain left no live screen"}
	return {"ok": true, "screen": screen}


## Move the tier selector onto the nth option and return the label now showing.
##
## Both selectors advance with the attempt, so the sweep walks the authored grid
## of (domain, tier) pairs rather than replaying one table. Picking a fixed tier
## would be wrong in the other direction too: a drop's grade scales with the tier
## it was fought at, and the grade gate refuses anything above the hero's tier.
func _choose_tier(screen: Node, _band: int) -> String:
	var option := screen.get_node_or_null(TIER_OPTION) as OptionButton
	if option == null or option.item_count <= 0:
		return ""
	# Always the FIRST band. The entry band is the one a starting hero can fight
	# and win, and holding it fixed is what makes each attempt a different DOMAIN
	# rather than a different cell of the same diagonal.
	option.select(0)
	option.item_selected.emit(0)
	return String(option.get_item_text(0))


## `where` is filled with the domain and tier this attempt chose, and is read by
## the caller whatever the outcome. It is a parameter rather than part of the
## return because `_hunt` is already at the six-return cap, and a failure that
## does not say which domain failed is the least useful kind.
func _hunt(app: Node, nth: int, where: Dictionary) -> Dictionary:
	var ready := await _ready_to_hunt(app)
	if not bool(ready.get("ok", false)):
		return {"ok": false, "why": ready.get("why", "cannot reach the loot surface")}
	var screen := ready.get("screen") as Node
	var domain := _choose_domain(screen, nth)
	var tier := _choose_tier(screen, nth)
	where["domain"] = domain
	where["tier"] = tier
	var before := screen.call(&"summary") as Dictionary
	if bool(before.get("in_domain", false)):
		return {"ok": false, "why": "a boss was already live before the player entered one"}
	if not _press(screen, ENTER_BUTTON):
		return {"ok": false, "why": "Enter domain is not a live control"}
	await process_frame
	if not bool((screen.call(&"summary") as Dictionary).get("in_domain", false)):
		# Enter is offered for ANY selected domain - the screen's `_enabled` never
		# consults the realm gate - so the button being live says nothing about
		# whether the entry was accepted. Most of the corpus is above this hero's
		# realm and is correctly refused, and reporting that as "no boss spawned"
		# would read a working gate as a broken pipeline, which is the exact
		# mistake BL-0625 was. Name what the screen published instead.
		var gate := String((screen.call(&"summary") as Dictionary).get("gate", ""))
		if gate.is_empty():
			gate = "the screen published no reason"
		return {
			"ok": false,
			"refused": true,
			"why": "the domain was refused, not entered: %s" % gate,
		}
	var fight := await _strike_until_dead(screen)
	var why := _why_fight_did_not_pay(screen, fight)
	if why != "":
		return {"ok": false, "why": why}
	var after := screen.call(&"summary") as Dictionary
	return {
		"ok": true,
		"domain": domain,
		"tier": tier,
		"strikes": int(fight.get("strikes", 0)),
		"reward_count": int(after.get("reward_count", 0)),
		"pending_drops": int(after.get("pending_drops", 0)),
	}


## Pick the fight's drop up out of the reward list and confirm it reached the bag.
##
## Minting a reward is not the loop finishing. A reward the player cannot collect is
## a number on a screen, which is the exact shape the objective calls out: the drop has
## to become an item the bag lists. So this presses the row's own "Pick up" control,
## requires the pending count to fall, then walks back to the workbench by nav button
## and requires the bag to be larger than it was at boot.
##
## `rows_at_boot` was captured before the hunt, so this compares against what the
## player actually started with rather than against a hardcoded starter count.
func _claim(app: Node, rows_at_boot: int) -> Dictionary:
	var screen := _live_screen(app)
	if screen == null:
		return {"ok": false, "why": "the fight left no live screen to collect from"}
	var blocked := _why_cannot_claim(screen)
	if blocked != "":
		return {"ok": false, "why": blocked}
	var pending_before := int((screen.call(&"summary") as Dictionary).get("pending_drops", 0))
	# What the fight pays is read as each reward slides into view, not once up
	# front: claiming retires a reward (`LootState._settle` moves it off
	# `state["rewards"]` once its last drop is taken) and the next one only appears
	# afterwards, so a single read saw one reward's rows and silently ignored the
	# gear sitting in the second. `_bag_grew` then navigates back to the workbench,
	# so reading any of it afterwards raised "call on a previously freed instance".
	var def_ids: Array[String] = []
	var collected := await _collect_pending(app, pending_before, def_ids)
	if not bool(collected.get("ok", false)):
		return {"ok": false, "why": collected.get("why", "collecting the drop failed")}
	var pending_after := int(collected.get("pending", 0))
	var stuck := _why_still_pending(pending_after, pending_before)
	if stuck != "":
		# Name what each press was REFUSED for. `pending` alone cannot tell five
		# named refusals apart, so a flat count sends whoever reads this hunting
		# a cause the evidence already carries.
		return {
			"ok": false,
			"why":
			(
				"%s; each press published: %s"
				% [stuck, ", ".join(collected.get("refusals", []) as Array)]
			),
			"refusals": collected.get("refusals", []),
		}
	var arrived := await _bag_grew(app, rows_at_boot)
	if not bool(arrived.get("ok", false)):
		var lost: String = str(arrived.get("why", "unknown"))
		return {"ok": false, "why": "the drop was taken but never reached the bag: %s" % lost}
	return {
		"ok": true,
		"pending_before": pending_before,
		"pending_after": pending_after,
		"rows_at_boot": rows_at_boot,
		"rows_now": int(arrived.get("rows", 0)),
		"def_ids": def_ids,
		"refusals": collected.get("refusals", []),
	}


## Wear one of the drops this fight produced, and report what the player's own hero
## sheet says changed.
##
## The claim half proved the drop became an item. That is not the loop finishing:
## an unequipped item does nothing. This walks to the hero screen, records the stats
## it publishes, walks back, wears the drop through the bag's own row selection and
## the real Equip control, then walks to the hero screen again and requires a stat to
## have RISEN. Comparing published stats rather than the actor's internals is the
## point — this is the observable a player can see, so it cannot pass by reaching past
## the UI the way a test with the actor in hand could.
func _equip(app: Node, def_ids: Array) -> Dictionary:
	if def_ids.is_empty():
		return {"ok": false, "why": "the reward named no item, so there is nothing to wear"}
	var before := await _published_stats(app)
	if before.is_empty():
		return {"ok": false, "why": "the hero screen publishes no stats to compare against"}
	var worn := await _wear_one(app, def_ids)
	if not bool(worn.get("ok", false)):
		# `wearable` must survive the rewrap: it is what tells the hunt loop that
		# another boss is worth fighting, and dropping it here made every failure
		# look like a fault, so the walk stopped after the first fight.
		return {
			"ok": false,
			"wearable": bool(worn.get("wearable", false)),
			"baseline_wearable": String(worn.get("baseline_wearable", "")),
			"why": worn.get("why", "the claimed drop could not be worn"),
		}
	var after := await _published_stats(app)
	var rose := _stat_that_rose(before, after)
	if rose == "":
		return {
			"ok": false,
			"why": "wearing '%s' left every published stat unchanged" % worn.get("def_id", ""),
		}
	return {"ok": true, "def_id": worn.get("def_id", ""), "stat": rose}


## Travel to a route by pressing its own nav button, then report whether it stuck.
func _goto(app: Node, route_id: StringName) -> Dictionary:
	var nav := app.get_node_or_null("%NavBar")
	if nav == null:
		return {"ok": false, "why": "there is no nav bar to travel with"}
	var index := _slot_for(route_id)
	if index < 0:
		return {"ok": false, "why": "the route table declares no '%s'" % String(route_id)}
	var blocked := _why_unpressable(nav, index)
	if blocked != "":
		return {"ok": false, "why": blocked}
	(nav.get_node_or_null(NavBar.slot_unique_name(index)) as Button).pressed.emit()
	await process_frame
	var now := String(app.call(&"current_route"))
	if now != String(route_id):
		return {
			"ok": false, "why": "slot %d opened '%s', not '%s'" % [index, now, String(route_id)]
		}
	return {"ok": true}


## The stats the hero screen publishes right now, or `{}` when it cannot be reached.
func _published_stats(app: Node) -> Dictionary:
	if not bool((await _goto(app, CHARACTER_ROUTE)).get("ok", false)):
		return {}
	var screen := _live_screen(app)
	if screen == null:
		return {}
	var summary := screen.call(&"summary") as Dictionary
	return summary.get("stats", {}) as Dictionary


## Append the def ids the currently shown reward offers, skipping ones already seen.
func _record_offered(screen: Node, def_ids: Array[String]) -> void:
	var reward := (screen.call(&"summary") as Dictionary).get("reward", {}) as Dictionary
	for row in reward.get("rows", []) as Array:
		var def_id := String((row as Dictionary).get("def_id", ""))
		if not def_id.is_empty() and not def_ids.has(def_id):
			def_ids.append(def_id)


## Press the reward list's own pickup control until nothing is pending.
##
## The screen is re-resolved on every pass rather than reused, because claiming a
## drop can repaint or replace it and a stale node is a freed-instance crash
## dressed up as a missing drop. `ok` is false only when the screen went away
## mid-collect; having no pressable control left is a normal stop.
func _collect_pending(app: Node, pending_before: int, def_ids: Array[String]) -> Dictionary:
	var pending := pending_before
	## One entry per press, naming the refusal the screen published for it.
	## `pending_drops` alone cannot separate the ways a pickup fails to move a
	## number: `LootState.pickup` has five named refusals (ERR_CLAIM_SPENT,
	## ERR_UNKNOWN_REWARD, ERR_UNKNOWN_DROP, ERR_DROP_CLAIMED, ERR_DROP_STASHED)
	## plus the inventory-full pair, and a flat `pending` is the same reading for
	## all of them. Bounded by MAX_DROPS_PER_REWARD like the walk above, so a
	## screen that refuses every press still terminates.
	var refusals: Array[String] = []
	for _drop in MAX_DROPS_PER_REWARD:
		if pending <= 0:
			return {"ok": true, "pending": pending, "refusals": refusals}
		var live := _live_screen(app)
		if live == null:
			return {"ok": false, "why": "collecting a drop left no live screen to read"}
		_record_offered(live, def_ids)
		var action := _first_drop_action(live)
		if action == null:
			break
		action.pressed.emit()
		await process_frame
		var again := _live_screen(app)
		if again == null:
			return {"ok": false, "why": "collecting a drop left no live screen to read"}
		var shown := again.call(&"summary") as Dictionary
		pending = int(shown.get("pending_drops", 0))
		refusals.append(_refusal_of(shown))
	return {"ok": true, "pending": pending, "refusals": refusals}


## What the screen published about the pickup it just handled, in one short token.
##
## Reads `reward.message` and `reward.tone`, the fields the reward list ACTUALLY
## publishes (loot_reward_list.gd:171-172) after `act_pickup` calls
## `report_outcome(drop_id, reason, tone)` on every press (loot_encounter.gd:164).
##
## Deliberately NOT a default of success: a probe that invents a pass reads green on a
## screen that refused every press, which is the one answer this exists to rule out. An
## outcome nobody published reads as `no_outcome_reported`, so an absence is visible as
## an absence instead of passing as a pass.
func _refusal_of(shown: Dictionary) -> String:
	var reward := shown.get("reward", {}) as Dictionary
	var said := String(reward.get("message", "")).strip_edges()
	var tone := String(reward.get("tone", "")).strip_edges()
	if said.is_empty() and tone.is_empty():
		return "no_outcome_reported"
	return said if tone.is_empty() else "%s (%s)" % [said, tone]


## The claimed drops the bag is actually holding, in the order the reward offered.
func _bagged_candidates(screen: Node, def_ids: Array) -> Array[String]:
	var panel := screen.get_node_or_null(INVENTORY_PANEL)
	if panel == null:
		return []
	var held := (panel.call(&"summary") as Dictionary).get("row_def_ids", []) as Array
	var bagged: Array[String] = []
	for candidate in def_ids:
		var def_id := String(candidate)
		if held.has(def_id) and not bagged.has(def_id):
			bagged.append(def_id)
	return bagged


## Select one bag row the way a player clicking it does. False when the bag's row
## list cannot address that def at all.
func _select_row(screen: Node, def_id: String) -> bool:
	var panel := screen.get_node_or_null(INVENTORY_PANEL)
	if panel == null:
		return false
	var ids := (panel.call(&"summary") as Dictionary).get("row_def_ids", []) as Array
	var list := panel.get_node_or_null(ITEM_LIST) as ItemList
	var index := ids.find(def_id)
	if list == null or index < 0 or index >= list.item_count:
		return false
	list.select(index)
	list.item_selected.emit(index)
	return true


## The first bag row the hero's own Equip control accepts, or "" when none is.
##
## Diagnostic only, and never a substitute for the real assertion: the gate still
## demands the DROPPED item be worn. This exists so "the drop cannot be worn" can
## be told apart from "this probe's Equip lookup is simply wrong" -- a probe that
## reports an unwearable drop because it pressed a control it never found looks
## exactly like a content gap. "" is itself the answer that the seam is dead.
func _baseline_wearable(screen: Node, bar: Node) -> String:
	var panel := screen.get_node_or_null(INVENTORY_PANEL)
	if panel == null:
		return ""
	var ids := (panel.call(&"summary") as Dictionary).get("row_def_ids", []) as Array
	for candidate in ids:
		var def_id := String(candidate)
		if not _select_row(screen, def_id):
			continue
		await process_frame
		# `_offered`, not `_press`: this asks whether the control is live and stops
		# there. Pressing would equip the row, which then reads as "nothing is
		# wearable" on every later attempt -- the diagnostic would destroy the very
		# evidence it exists to collect.
		if _offered(bar, EQUIP_BUTTON):
			return def_id
	return ""


## Wear one of the claimed drops, trying each until the hero's own Equip control
## accepts it.
##
## The Equip button being live is the oracle, not a lookup of the item's category
## in the probe. A button the production action bar disabled is the real answer to
## "can this be worn", so asking it keeps the probe honest about the shipped
## wiring instead of duplicating the rule that wiring enforces.
func _wear_one(app: Node, def_ids: Array) -> Dictionary:
	if not bool((await _goto(app, HOME_ROUTE)).get("ok", false)):
		return {"ok": false, "why": "could not return to the bag"}
	var screen := _live_screen(app)
	if screen == null:
		return {"ok": false, "why": "the workbench is not the live screen"}
	var bar := screen.get_node_or_null(ACTION_BAR)
	if bar == null:
		return {"ok": false, "why": "the workbench composes no action bar to equip through"}
	var bagged := _bagged_candidates(screen, def_ids)
	if bagged.is_empty():
		return {"ok": false, "why": "no claimed drop is in the bag to wear"}
	return await _try_each_drop(screen, bar, bagged)


## Try each bagged drop until the hero's own Equip control accepts one. Split out
## of `_wear_one` so neither half sits at gdlint's six-return ceiling, which is
## what forced the two together in the first place.
func _try_each_drop(screen: Node, bar: Node, bagged: Array[String]) -> Dictionary:
	for candidate in bagged:
		if not _select_row(screen, candidate):
			return {"ok": false, "why": "the bag's row list cannot select '%s'" % candidate}
		# One frame between selecting and pressing: the detail panel must repaint
		# for the newly selected row before the action bar can judge it wearable.
		await process_frame
		if _press(bar, EQUIP_BUTTON):
			return {"ok": true, "def_id": candidate}
	var baseline := await _baseline_wearable(screen, bar)
	# The message carries `baseline_wearable` because that ONE fact separates two
	# defects that look identical from here: if a starter item already equips, the
	# Equip control works and these drops are simply unwearable CONTENT; if nothing
	# equips, the control itself is dead and every drop is a red herring. Collecting
	# the fact without printing it is how "can be worn" stayed a guess.
	#
	# It also names the ids. "Can be worn" is a claim about CONTENT, and a claim about
	# content is only checkable against the content: naming them lets whoever reads
	# this ask whether those ids are in the tables that stock wearable gear, instead
	# of re-deriving the sweep. Without them the message says the drop is unwearable
	# and never says WHICH drop.
	return {
		"ok": false,
		"wearable": false,
		"baseline_wearable": baseline,
		"unwearable_def_ids": bagged,
		"why":
		(
			"none of the %d drop(s) this fight paid can be worn (%s); a starter equips: %s"
			% [bagged.size(), ", ".join(bagged), baseline]
		),
	}


## The first stat key that went UP, or "" when nothing rose. Sorted so the reported
## name is stable across runs rather than whichever key the dictionary yielded first.
func _stat_that_rose(before: Dictionary, after: Dictionary) -> String:
	var keys := after.keys()
	keys.sort()
	for key in keys:
		if float(after[key]) > float(before.get(key, 0.0)):
			return String(key)
	return ""


## The nav slot bound to a route id, or -1. The bar binds slot N to route N.
func _slot_for(route_id: StringName) -> int:
	var slots := ScreenRoutes.all()
	for index in slots.size():
		if StringName(slots[index].get("id", "")) == route_id:
			return index
	return -1


## Why the reward cannot be collected from. Empty means the player could take a drop.
func _why_cannot_claim(screen: Node) -> String:
	if int((screen.call(&"summary") as Dictionary).get("pending_drops", 0)) < 1:
		return "there was nothing pending to collect"
	var action := _first_drop_action(screen)
	if action == null:
		return "the reward lists drops but offers no control to take one"
	if action.disabled:
		return "the drop's Pick up control is disabled, so it cannot be taken"
	return ""


## Why pressing Pick up did not reduce what is owed. Empty is a pass.
func _why_still_pending(after: int, before: int) -> String:
	if after >= before:
		return "taking a drop left %d of %d pending; nothing was collected" % [after, before]
	return ""


## Walk back to the workbench by its own nav button and report the bag it shows.
func _bag_grew(app: Node, rows_at_boot: int) -> Dictionary:
	var nav := app.get_node_or_null("%NavBar")
	if nav == null:
		return {"ok": false, "why": "there is no nav bar to walk back with"}
	var home := _home_slot()
	if home < 0:
		return {"ok": false, "why": "the route table declares no home slot to walk back to"}
	var button := nav.get_node_or_null(NavBar.slot_unique_name(home)) as Button
	if button == null or button.disabled or not button.visible:
		return {"ok": false, "why": "the nav bar's home button is not pressable"}
	button.pressed.emit()
	await process_frame
	var rows := _bag_rows(app)
	if rows <= rows_at_boot:
		return {
			"ok": false,
			"why":
			"the workbench lists %d rows, no more than the %d at boot" % [rows, rows_at_boot],
		}
	return {"ok": true, "rows": rows}


## The slot index of the home route, or -1.
func _home_slot() -> int:
	var slots := ScreenRoutes.all()
	for index in slots.size():
		if bool(slots[index].get("root", false)):
			return index
	return -1


## How many rows the live screen's bag lists, or -1 when it is not a bag view.
func _bag_rows(app: Node) -> int:
	var screen := _live_screen(app)
	if screen == null:
		return -1
	var summary: Variant = screen.call(&"summary")
	if not (summary is Dictionary):
		return -1
	return int((summary as Dictionary).get("row_count", -1))


## The reward list's first row control, or null when the reward has no rows.
func _first_drop_action(screen: Node) -> Button:
	var list := screen.get_node_or_null(REWARD_LIST)
	if list == null:
		return null
	return _first_named(list, DROP_ACTION) as Button


## Depth-first search for a node by name, with a depth cap. See MAX_WALK_DEPTH.
func _first_named(node: Node, node_name: String, depth: int = 0) -> Node:
	if depth > MAX_WALK_DEPTH:
		return null
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found := _first_named(child, node_name, depth + 1)
		if found != null:
			return found
	return null


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
		# Name the boss. Every authored tier carries a non-empty `boss_tables`, so
		# a boss that dies paying nothing is not missing data -- it is a boss the
		# tier's table list does not cover, and the id is what makes that checkable.
		return (
			"the boss '%s' died and minted no reward at all"
			% String(after.get("boss_id", "<unnamed>"))
		)
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
