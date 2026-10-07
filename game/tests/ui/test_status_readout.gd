extends TestCase

## ADR 0106's second half: the readout. The loot fight screen is where the player is
## losing health, so that is where a status has to be visible — and it is visible only
## if the panel, not the screen, turns the facade's primitives into a sentence.
##
## Two claims are pinned here, and both are the ones a future edit can quietly break:
##
##  1. `StatusApi.summary(actor)` is primitives-only, so a screen and a test read the
##     same shape (AGENTS.md's testable contract). A `Node`, a `StatusDef` or a
##     `StatusEffect` in there would make the readout untestable and would hand `ui/`
##     a module type it may not name.
##  2. The screen CONSUMES it. A panel that can format a dict nobody passes it is a
##     readout that exists and is never reached, which is the same defect ADR 0106
##     found on the tick side, one layer over.

const SCREEN_SCENE := "res://src/ui/screens/loot_encounter.tscn"
const PANEL_SCENE := "res://src/ui/panels/loot_boss_panel.tscn"
const SCREEN_SCRIPT := "res://src/ui/screens/loot_encounter.gd"
const PANEL_SCRIPT := "res://src/ui/panels/loot_boss_panel.gd"
## One frame at the rate the engine runs at. The elapsed time belongs to whoever owns
## the clock, so a headless test passes its own rather than reading `Time` (ADR 0089).
const FRAME := 1.0 / 60.0

## One COMBAT-scope id and one CULTIVATION-scope id, both authored, so the assertion is
## about the SCOPE and not about which ids happen to ship. `fire_immolation` is the one
## the audit names (COMBAT, 16 s); `wood_bloom` is `duration = -1.0` CULTIVATION, the
## permanent blessing ADR 0089's purge rule exists to spare.
const COMBAT_STATUS := &"fire_immolation"
const CULTIVATION_STATUS := &"wood_bloom"

## Every screen this suite instantiated. The runner shares one process across every
## suite, so an unfreed screen stays resident for the rest of the run — and this is
## the heaviest screen in the program. Freed centrally because the call sites are
## interleaved and a test returning early would skip a free at its end.
var _born: Array[Node] = []

## Every `StatusLoop` `_root_loop` handed out. A `Callable` is the only holder the
## screen has, and a Callable whose RefCounted target was freed is INVALID — a
## temporary loop here would make `combat_exit_wired()` read false for a reason the
## screen never saw, which is a test bug wearing a wiring bug's clothes.
var _loops: Array[StatusLoop] = []


## The player and the composition root's own status wire over them — the same pair
## `item_workbench_app.gd` builds, so a purge here is the purge the app performs.
func _rig() -> Dictionary:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor)
	LootApi.attach(actor)
	return {"actor": actor, "loop": StatusLoop.new(actor)}


func _bridge() -> LootBridge:
	var bridge := LootBridge.new()
	bridge.list_domains = Callable(LootApi, "domains")
	bridge.enter_domain = Callable(LootApi, "enter_domain")
	bridge.leave_domain = Callable(LootApi, "abandon")
	bridge.pickup = Callable(LootApi, "pickup")
	bridge.pickup_all = Callable(LootApi, "pickup_all")
	bridge.reclaim = Callable(LootApi, "reclaim")
	bridge.read_state = Callable(LootApi, "summary")
	return bridge


## Free everything `_screen()` handed out. Idempotent, so it is safe after an abort.
func teardown() -> void:
	for node in _born:
		if is_instance_valid(node):
			node.free()
	_born.clear()
	_loops.clear()


func _screen(actor: Actor) -> LootEncounterScreen:
	var scene: PackedScene = load(SCREEN_SCENE)
	assert_ne(scene, null, "the loot screen scene loads")
	var screen := scene.instantiate() as LootEncounterScreen
	_born.append(screen)
	screen.call("_ready")
	screen.call("setup", actor)
	screen.call("bind_bridge", _bridge())
	return screen


## Whether `needle` appears anywhere in the nested view, keys and values alike. Used
## instead of spelling the path out, because the panel nests its report under its own
## key and a future extra level would otherwise fail this test for a good change.
func _holds(view: Variant, needle: String) -> bool:
	if view is Dictionary:
		var entries: Dictionary = view
		for key in entries:
			if String(key) == needle or _holds(entries[key], needle):
				return true
		return false
	if view is Array:
		var items: Array = view
		for entry in items:
			if String(entry) == needle or _holds(entry, needle):
				return true
	return false


# --- 1. the facade summary is primitives-only ---------------------------------


func test_the_status_summary_holds_no_objects_and_reads_empty_without_an_actor() -> void:
	var bare := StatusApi.summary()
	assert_eq(_non_primitives(bare), [], "no actor means a shaped catalogue read, not objects")
	# `active` is the half the screen consumes, and it must be an array a panel can walk
	# without a type check — an empty one rather than null, so "carrying nothing" and
	# "the facade is broken" are not the same value.
	assert_eq((bare["active"] as Array).is_empty(), true, "no actor carries no active status")
	assert_eq((bare["ids"] as Array).is_empty(), false, "the catalogue is still reported")


func test_a_live_status_summarizes_to_primitives_only() -> void:
	var actor := (_rig()["actor"]) as Actor
	var applied := StatusApi.apply(actor, &"fire_immolation", 2.0)
	assert_eq(bool(applied["ok"]), true, "the burn applies")
	var report := StatusApi.summary(actor)
	assert_eq(_non_primitives(report), [], "the whole summary is primitives")
	var active := report["active"] as Array
	assert_eq(active.size(), 1, "one live status is reported")
	var entry := active[0] as Dictionary
	assert_eq(String(entry["id"]), "fire_immolation", "and it is the one that was applied")
	# Every key the panel reads has to be there, with a real value in it: a missing
	# `remaining` would print "0s" and read as a status about to expire.
	for key in ["remaining", "permanent", "magnitude", "ticks_elapsed", "scope", "known"]:
		assert_eq(entry.has(key), true, "the summary carries '%s'" % key)
	assert_eq(bool(entry["known"]), true, "the status module authored this one")
	assert_eq(bool(entry["permanent"]), false, "and it is a timed status")
	assert_eq(float(entry["remaining"]) > 0.0, true, "with time left on it")


# --- 2. the screen and the panel consume it -----------------------------------


func test_the_fight_screen_shows_what_is_on_the_player() -> void:
	var actor := (_rig()["actor"]) as Actor
	var screen := _screen(actor)
	assert_eq(
		String(screen.summary()["status_label"]),
		L.t(LootBossPanel.NO_STATUSES),
		"a fresh player is told they are carrying nothing"
	)
	# Applied the way a hit applies one — through the facade, not by hand — then the
	# screen refreshes exactly as an exchange does.
	StatusApi.apply(actor, &"fire_immolation", 2.0)
	screen.refresh()
	var view := screen.summary()
	var line := String(view["status_label"])
	assert_eq(line.contains("fire immolation"), true, "the readout names the status")
	assert_eq(line.contains("%d"), false, "and is not an unformatted template")
	assert_eq(_holds(view, "fire_immolation"), true, "the id is reported in the view")
	# The panel's own half carries the structured form, which is what makes the line
	# assertable without parsing the sentence itself.
	var boss := view["boss"] as Dictionary
	assert_eq(int(boss["status_count"]), 1, "the panel carries the count")
	assert_eq((boss["status_ids"] as Array).has("fire_immolation"), true, "and the ids")
	# " x" is the `x%.1f` and the trailing "s" the `%ds` — both the panel's, never the
	# screen's. If either half moved into the screen, these are the assertions that
	# would fail, which is the point of checking them here.
	assert_eq(line.contains(" x"), true, "the potency is printed as the panel formats it")
	assert_eq(line.contains("s "), true, "and so is the remaining timer")


func test_the_readout_moves_when_the_clock_spends_a_pulse() -> void:
	# The point of the whole change: ticking is now visible. A burn that spends a pulse
	# has to change the line a player reads, or the readout is decoration again.
	var rig := _rig()
	var actor := rig["actor"] as Actor
	var screen := _screen(actor)
	StatusApi.apply(actor, &"fire_immolation", 2.0)
	screen.refresh()
	var before := String(screen.summary()["status_label"])
	assert_eq(before.contains("pulse"), false, "a fresh burn has spent nothing yet")
	# The interval is the AUTHORED one, so the frames are derived from the def rather
	# than pinned to a number that a content retune would invalidate.
	var def := StatusApi.definition(&"fire_immolation")
	var frames := int(ceil(maxf(0.001, def.tick_interval) / FRAME))
	for _frame in frames:
		(rig["loop"] as StatusLoop).tick(FRAME)
	screen.refresh()
	var after := String(screen.summary()["status_label"])
	assert_ne(after, before, "the readout changed once the clock paid out")
	assert_eq(after.contains("1 pulse"), true, "and it names the pulse the status spent")


func test_a_permanent_status_reads_as_forever_not_a_negative_timer() -> void:
	# `StatusEffect`'s forever sentinel is a negative timer. Printing the raw number
	# would tell a player they have "-1s" of a blessing, so the panel has to say what it
	# means. `wood_bloom` is authored `duration = -1.0`, scope `cultivation`.
	var actor := (_rig()["actor"]) as Actor
	var screen := _screen(actor)
	var applied := StatusApi.apply(actor, &"wood_bloom", 1.0)
	assert_eq(bool(applied["ok"]), true, "the permanent cultivation status applies")
	screen.refresh()
	var line := String(screen.summary()["status_label"])
	assert_eq(line.contains("wood bloom"), true, "the permanent status is listed")
	assert_eq(line.contains("forever"), true, "and its timer reads as forever")
	assert_eq(line.contains("-"), false, "never as the negative sentinel it stores")


func test_the_readout_clears_when_the_status_is_gone() -> void:
	# Stale rows are worse than no readout: a debuff that expired but stayed on screen
	# teaches the player to ignore the line. `exit_combat` is the purge ADR 0089 names,
	# so the panel must follow the same state the actor ends up in.
	var rig := _rig()
	var actor := rig["actor"] as Actor
	var screen := _screen(actor)
	StatusApi.apply(actor, &"metal_sever", 1.0)
	screen.refresh()
	assert_eq(_holds(screen.summary(), "metal_sever"), true, "the debuff is listed while live")
	(rig["loop"] as StatusLoop).exit_combat()
	screen.refresh()
	assert_eq(_holds(screen.summary(), "metal_sever"), false, "and gone once combat purged it")
	assert_eq(
		String(screen.summary()["status_label"]),
		L.t(LootBossPanel.NO_STATUSES),
		"with the line saying so rather than left holding a stale row"
	)


# --- 2b. ADR 0089's PURGE is reached from the shipped game (F-6) ------------------
#
# `StatusLoop.exit_combat` is the ONLY route to `StatusApi.clear_combat_scope`, and it
# measured ZERO callers in `game/src`: a COMBAT-scope debuff — `fire_immolation` is
# authored at 16 s — outlived the fight that inflicted it, so a player walked out of a
# fight still burning for its full duration. ADR 0106 deferred the wiring to "the same
# change that makes the readout visible"; the readout shipped and this did not.
#
# ## Why the caller cannot be a facade call
#
# `exit_combat` is `app/status_loop.gd`, and `app` is a `PRIVATE_UNIT`
# (`tools/arch/rules.py:35`), so `ui/` may name neither the type nor the verb. The
# composition root injects it as a `Callable` (`ItemWorkbenchApp._bind_route_screen`'s
# `ROUTE_LOOT` arm → `LootEncounterScreen.bind_combat_exit`), the same door ADR 0143
# gives the quest screen. These cases drive THAT seam, not `StatusLoop.exit_combat`, so
# deleting the wiring fails here even though every other case in this file stays green.


## The screen plus the composition root's own purge wire over the same actor, which is
## the pair `_bind_route_screen` builds for the loot route.
func _wired_screen(actor: Actor) -> LootEncounterScreen:
	var screen := _screen(actor)
	screen.call("bind_combat_exit", Callable(_root_loop(actor), "exit_combat"))
	return screen


## A `StatusLoop` over `actor`, matching the root's field. Held in `_loops` rather than
## built inline, because the seam is a `Callable` and the loop must stay alive for as
## long as the screen holds it.
func _root_loop(actor: Actor) -> StatusLoop:
	var loop := StatusLoop.new(actor)
	_loops.append(loop)
	return loop


## THE claim: a player who ends a fight stops carrying the debuff that fight inflicted.
##
## Driven through the screen verb a player presses, not through the purge: a suite that
## calls `exit_combat` directly stays green the day the composition root stops injecting
## it, which is the whole shape of F-6.
func test_ending_a_fight_purges_the_debuff_that_fight_inflicted() -> void:
	var rig := _rig()
	var actor := rig["actor"] as Actor
	var screen := _wired_screen(actor)
	# Applied the way a blow applies one — through the facade, not by hand — because the
	# defect is about the status a real fight leaves behind, not about a rigged one.
	StatusApi.apply(actor, COMBAT_STATUS, 2.0)
	assert_eq(actor.has_status(COMBAT_STATUS), true, "the burn is live before the fight ends")
	screen.refresh()
	assert_eq(
		String(screen.summary()["status_label"]).contains("fire immolation"),
		true,
		"and the player can see they are burning"
	)
	# Leaving is refused for a player who never entered (the refusal
	# `test_an_unwired_purge_still_lets_the_player_leave_the_fight` pins), so the fight
	# is entered first — the same order the player takes.
	assert_eq(screen.act_enter(), true, "the player enters the domain")

	assert_eq(screen.act_leave(), true, "the player leaves the domain")

	assert_eq(actor.has_status(COMBAT_STATUS), false, "the burn is gone the moment combat ends")
	assert_eq(
		(screen.summary()["last_cleared"] as Array).has("fire_immolation"),
		true,
		"and the purge NAMES what it removed, so the screen can report it"
	)
	screen.refresh()
	assert_eq(
		String(screen.summary()["status_label"]),
		L.t(LootBossPanel.NO_STATUSES),
		"the readout repaints to match — no stale row the player learns to ignore"
	)


## The half of ADR 0089 that makes the purge a scope purge and not a cleanse: a
## CULTIVATION gift is NEVER touched by combat state. Without this the fix above would
## also silently delete a permanent tribulation blessing every time a player walked out
## of a fight, which is the same defect wearing the other hat.
func test_ending_a_fight_never_touches_a_cultivation_blessing() -> void:
	var rig := _rig()
	var actor := rig["actor"] as Actor
	var screen := _wired_screen(actor)
	var granted := StatusApi.apply_cultivation(actor, CULTIVATION_STATUS, 1.0)
	assert_eq(bool(granted["ok"]), true, "the permanent blessing applies")
	StatusApi.apply(actor, COMBAT_STATUS, 2.0)
	assert_eq(screen.act_enter(), true, "the player enters the domain")
	assert_eq(screen.act_leave(), true, "the player leaves the domain")

	assert_eq(actor.has_status(COMBAT_STATUS), false, "the COMBAT burn was purged")
	assert_eq(actor.has_status(CULTIVATION_STATUS), true, "and the CULTIVATION gift survived it")
	assert_eq(
		(screen.summary()["last_cleared"] as Array).has("wood_bloom"),
		false,
		"and was never named as cleared — the purge is scoped, not a cleanse (ADR 0107)"
	)


## The positive control: the purge is WIRED, so the two cases above are measuring a
## purge that ran rather than one that silently did nothing. Without this, an unwired
## seam and a correctly scoped one are indistinguishable from the assertions above —
## the COMBAT case would fail rather than pass vacuously, so this is belt and braces.
func test_the_screen_reports_whether_its_combat_exit_purge_is_wired() -> void:
	var rig := _rig()
	var actor := rig["actor"] as Actor
	assert_eq(_screen(actor).combat_exit_wired(), false, "a bare screen has no purge seam at all")
	var wired := _wired_screen(actor)
	assert_eq(wired.combat_exit_wired(), true, "the composition root's arm binds it")
	assert_eq(bool(wired.summary()["combat_exit_wired"]), true, "and summary() publishes that")


## An unwired seam must not turn "leave the fight" into a refusal. The screen still
## leaves the domain; what it cannot do is purge, and that is a missing bookkeeping step
## rather than something the player is stopped for.
func test_an_unwired_purge_still_lets_the_player_leave_the_fight() -> void:
	var actor := (_rig()["actor"]) as Actor
	var screen := _screen(actor)
	assert_eq(screen.combat_exit_wired(), false, "no seam was bound")
	assert_eq(screen.act_leave(), false, "leaving a domain nobody entered is still refused")
	# With a fight actually entered, the refusal has to become the action.
	screen.act_enter()
	assert_eq(screen.combat_exit_wired(), false, "still no seam after entering")
	assert_eq(screen.act_leave(), true, "and leaving still works")


func test_a_screen_with_no_actor_reports_nothing_at_all() -> void:
	# The screen contract, unchanged by the readout: `{}` with no actor, so a test never
	# reads a half-initialised screen as a real view.
	var scene: PackedScene = load(SCREEN_SCENE)
	var bare := scene.instantiate() as LootEncounterScreen
	_born.append(bare)
	bare.call("_ready")
	assert_eq(bare.summary(), {}, "no actor means no view — not a readout of nothing")


# --- 3. the rules the readout had to obey --------------------------------------


func test_the_screen_reaches_the_status_module_only_through_its_facade() -> void:
	# `ui/` is held to the facade rule, and `status` is in `rules.UI_MODULES`, so
	# `StatusApi` is a legal door. A `StatusDef`, a `StatusEffect` or a `res://` into
	# the module would be the violation the allowlist exists to catch.
	var script := FileAccess.get_file_as_string(SCREEN_SCRIPT)
	assert_eq(script.contains("StatusApi"), true, "the screen reads the facade by name")
	assert_eq(script.contains("StatusDef"), false, "and no status content type")
	assert_eq(script.contains("StatusEffect"), false, "nor any instance type")
	assert_eq(script.contains("res://src/modules/status"), false, "nor a direct module path")
	assert_eq(script.contains("theme_override"), false, "and no theme override anywhere")
	# The scene must not instance a module file either — the `.tscn` half of the same
	# rule, which `test_ui_conventions` checks for every module.
	assert_eq(
		FileAccess.get_file_as_string(SCREEN_SCENE).contains("res://src/modules/"),
		false,
		"nor does the scene reference a module path"
	)


func test_the_screen_formats_no_status_figure_of_its_own() -> void:
	# AGENTS.md: a screen passes raw values and the panel owns `%d`. The claim is scoped
	# to the STATUS half, because this screen legitimately formats the loot gate and the
	# bonus line — both about a module it owns. What must not exist is code that reads a
	# status field and prints it, and that is what the field scan pins.
	var code := _code_only(SCREEN_SCRIPT)
	for field in ["remaining", "ticks_elapsed", "magnitude", "permanent"]:
		assert_eq(
			code.contains(field), false, "the screen never reads the status field '%s'" % field
		)
	# It hands the panel the facade's own key and nothing else: one `get`, no reading
	# inside the rows it forwards.
	assert_eq(code.contains('.get("active"'), true, "it forwards the facade's own key")
	assert_eq(code.contains('"statuses"'), false, "and formats no status dict of its own")


func test_the_panel_owns_the_status_line_and_resolves_its_node_lazily() -> void:
	# The two UI rules a new panel half could have broken: no `@onready`, and an
	# idempotent `_bind_nodes()`. A headless suite drives this panel before a scene tree
	# exists, so a one-shot binding in `_ready()` would make the readout untestable.
	var source := FileAccess.get_file_as_string(PANEL_SCRIPT)
	assert_eq(_code_only(PANEL_SCRIPT).contains("@onready"), false, "no @onready in ui/")
	assert_eq(source.contains("func _bind_nodes()"), true, "nodes resolve in _bind_nodes()")
	assert_eq(source.contains("theme_override"), false, "style belongs to the one theme")
	# And the node the new half renders is really declared by the scene, not invented by
	# a script that would then render nothing. Checked on the node BLOCK, because a
	# `unique_name_in_owner` on some other node would satisfy a whole-file search.
	var scene := FileAccess.get_file_as_string(PANEL_SCENE)
	assert_eq(
		_node_block(scene, "StatusLabel").contains("unique_name_in_owner = true"),
		true,
		"the scene marks the status label unique, so %StatusLabel resolves"
	)


func test_the_status_label_is_a_container_child_not_an_absolute_position() -> void:
	# Anchors + Containers only. `custom_minimum_size` is a widget's own minimum and
	# carries no position; `position` / `offset_*` / `anchor_*` on the new node would be an
	# absolute layout under a Container, which the UI standard bans.
	var node := _node_block(FileAccess.get_file_as_string(PANEL_SCENE), "StatusLabel")
	assert_ne(node.is_empty(), true, "the status label is declared")
	for banned in ["position = ", "offset_", "anchor_", "grow_horizontal"]:
		assert_eq(node.contains(banned), false, "the status label carries no %s" % banned)
	assert_eq(node.contains("layout_mode = 2"), true, "and is a child of the panel's container")


# --- Plumbing ------------------------------------------------------------------


## The `[node ...]` block for `node_name`, reassembled across lines.
func _node_block(scene: String, node_name: String) -> String:
	var block := ""
	for raw in scene.split("\n"):
		if block.is_empty():
			if raw.begins_with("[node ") and ('"%s"' % node_name) in raw:
				block = raw
			continue
		if raw.begins_with("["):
			break
		block += "\n" + raw
	return block


## `path`'s text with comments removed, so a scan reads code and not prose. The panel
## documents WHY it holds no `@onready`, and a doc comment is not a regression — the
## same reason `test_ui_conventions.gd` strips comments before it scans.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		if raw.strip_edges().begins_with("#"):
			continue
		var hash := raw.find("#")
		out.append(raw.substr(0, hash) if hash >= 0 else raw)
	return "\n".join(out)


## Dotted paths inside a summary whose value is not a primitive, a String, an Array, or
## a dictionary of the same. A `Node`, a `Resource` or an `Object` in a testable surface
## is how a readout quietly stops being testable.
func _non_primitives(value: Variant, path: String = "") -> Array[String]:
	var out: Array[String] = []
	if value is Dictionary:
		var entries: Dictionary = value
		for key in entries:
			var child: Variant = entries[key]
			if child is Dictionary or _is_primitive(child):
				out.append_array(_non_primitives(child, "%s.%s" % [path, key]))
			else:
				out.append("%s.%s" % [path, key])
		return out
	if value is Array:
		var items: Array = value
		for index in items.size():
			out.append_array(_non_primitives(items[index], "%s[%d]" % [path, index]))
	return out


func _is_primitive(value: Variant) -> bool:
	if value == null:
		return true
	var kind := typeof(value)
	return (
		kind == TYPE_BOOL
		or kind == TYPE_INT
		or kind == TYPE_FLOAT
		or kind == TYPE_STRING
		or kind == TYPE_STRING_NAME
		or kind == TYPE_ARRAY
	)
