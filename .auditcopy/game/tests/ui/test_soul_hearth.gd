extends TestCase

## THE SOUL AND HEARTH PAGE IS REACHABLE AND WIRED (ADR 0127 / 0129 / 0146 / 0128).
##
## `soul`, `difficulty`, `anchor` and `save` each shipped a facade, authored content
## and a green suite, and nothing in the shipped program ever RENDERED any of them.
## A number in an injected store, a row in a table, a set of headless verbs and a
## `summary()` with no reader are the four shapes that failure takes.
##
## ## What every assertion here is made through
##
## The mounted app. `SeamHarness.mount_new()` parents the real
## `ItemWorkbenchApp.tscn`, the route table mounts the screen, the composition root's
## `_bind_route_screen` arm binds its seams, and every claim is read back off the
## MOUNTED screen's own `summary()`. Nothing in this file calls `DifficultyApi.select`
## or `AnchorApi.raise_anchor` in place of a button press; the module is asked only
## afterwards whether the world moved, which is what makes the press the thing under
## test rather than the module.

const SCREEN := "res://src/ui/screens/soul_hearth_screen.tscn"
const ROUTE := &"soul_hearth"
## The hearth the shipped content authors, and what it costs. Read as ids here rather
## than restated: the price lives on the def, and a suite that retyped it would pass
## against a def someone had retuned.
const HEARTH := &"hearth_of_the_returning"
const PRESET_OFFER := &"hard"
## An id the difficulty table does not define, so the refusal half can be driven
## without inventing content.
const PRESET_UNKNOWN := &"a_name_no_table_carries"
## The anchor authored at a realm floor a boot hero is below, so the page has a
## refusal to render that is not "already raised".
const STONE := &"stone_of_the_held_name"
## Depth ceiling for the row walk: the rows sit four levels below the screen.
const MAX_TREE_WALK := 12

var _harness: SeamHarness = null


func setup() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	_harness = null


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	_harness = null


# --- The four seams the page is made of --------------------------------------


## Piece one: the route. A screen the route table does not name cannot be reached by
## anything, and `test_screen_reachability` names it as unreachable.
func test_the_route_table_names_the_page_with_its_own_key() -> void:
	var ids: Array = []
	for row in ScreenRoutes.summary():
		ids.append(String(row.get("id", "")))
	assert_eq(ids.has(String(ROUTE)), true, "the soul page is a named route")
	assert_eq(
		String(ScreenRoutes.key_of(ROUTE)), "s", "and its key is s, which the action below is"
	)


## Piece two: the input action. A route reachable only by a button is a route a
## keyboard player cannot reach.
func test_the_pages_input_action_is_bound_to_its_key() -> void:
	var action := ScreenRoutes.action_of(ROUTE)
	assert_eq(String(action), "nav_route_s", "the route names its own action")
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action resolves back to this route, not to another screen's"
	)


## Piece three: the boundary. `ui/` may name `difficulty` and `anchor` and nothing
## else out of these four: `soul` is absent from `rules.UI_MODULES` and `save` must
## stay absent forever (ADR 0128), so both arrive as injected Callables.
func test_the_screen_reaches_two_modules_by_facade_and_two_by_bridge() -> void:
	var script := _code(FileAccess.get_file_as_string("res://src/ui/screens/soul_hearth_screen.gd"))
	assert_eq(script.contains("DifficultyApi"), true, "the difficulty facade is named")
	assert_eq(script.contains("AnchorApi"), true, "and so is the anchor facade")
	# The two that must NOT be named. Read from CODE, so the page's own docblock
	# explaining why it does not name them cannot fail the guard.
	assert_eq(script.contains("SoulApi"), false, "the soul is never named (not in UI_MODULES)")
	assert_eq(script.contains("SaveApi"), false, "and neither is the save (ADR 0128)")
	assert_eq(script.contains("res://src/modules/"), false, "nor any direct module path")
	assert_eq(script.contains("theme_override"), false, "and no theme override anywhere")
	assert_eq(script.contains("@onready"), false, "and every node resolved lazily")


## The other two halves of the standard, as source facts rather than as a review:
## an empty-summary path of its own, and no widget built in `_ready()`.
func test_the_page_keeps_the_screen_contract_in_source() -> void:
	var script := _code(FileAccess.get_file_as_string("res://src/ui/screens/soul_hearth_screen.gd"))
	assert_eq(script.contains("return {}"), true, "it has an explicit empty-summary path")
	assert_eq(script.contains("func _ready("), false, "and builds no widget in _ready()")
	for hook in ["focus_initial", "on_screen_shown", "on_screen_hidden", "on_stack_input"]:
		var inherited := script.contains("func %s(" % hook) or _ui_screen_declares(hook)
		assert_eq(inherited, true, "the %s hook exists on the page or on UiScreen" % hook)


## Whether `UiScreen` itself declares the hook, so the claim above is about the
## page's own contract rather than about a name this file happens to spell.
func _ui_screen_declares(hook: String) -> bool:
	var source := FileAccess.get_file_as_string("res://src/ui/screens/ui_screen.gd")
	return source.contains("func %s(" % hook)


# --- The read model ----------------------------------------------------------


## THE REACHABILITY PROOF. The real app boots, the route table mounts this screen,
## the composition root binds it, and the mounted screen reports the app's own hero.
func test_the_page_mounts_for_a_player_and_reports_their_own_soul() -> void:
	var harness := _boot()
	if harness == null:
		return
	var moved := harness.navigate(ROUTE)
	assert_eq(bool(moved["ok"]), true, "the soul route is reachable: %s" % moved["note"])
	if not bool(moved["ok"]):
		return
	var live := harness.live_screen()
	assert_ne(live, null, "the route left a live screen")
	assert_eq(
		live.scene_file_path,
		SCREEN,
		"and it is THIS screen, not merely something the route table named"
	)
	assert_eq(
		harness.app.is_ancestor_of(live),
		true,
		"mounted under the running app, not instantiated here"
	)
	assert_eq(harness.bound_actor(live), harness.actor, "and bound to the app's own actor")

	var view := live.summary() as Dictionary
	assert_eq(view.is_empty(), false, "a bound hero renders a real view, not {}")
	assert_eq(String(view.get("actor", "")), String(harness.actor.id), "for the app's own hero")
	# The soul half is the read the whole page exists for, and it arrived through the
	# root's bridge rather than through a facade the UI may not name.
	assert_eq(bool(view.get("soul_seam", false)), true, "the soul seam is bound by the root")
	assert_eq(
		(view.get("soul", {}) as Dictionary).get("integrity_max", 0) > 0,
		true,
		"and the soul it reads has an authored ceiling"
	)
	assert_eq(bool(view.get("save_seam", false)), true, "the save seam is bound by the root too")


## The documented contract: primitives only, each child's own summary nested under
## the child's own key, and nothing a Node or a Resource snuck into the tree.
func test_the_summary_is_primitives_only_with_every_child_nested() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	var view := live.summary() as Dictionary
	for key in [
		"soul",
		"difficulty_id",
		"scalars",
		"ledger",
		"portrait",
		"presets",
		"anchors",
		"save",
	]:
		assert_eq(view.has(key), true, "%s is published" % key)
	for key in ["ledger", "portrait"]:
		var child: Dictionary = view[key]
		assert_eq(child.is_empty(), false, "%s nests its own summary" % key)
	assert_eq(_non_primitives(view).is_empty(), true, "and nothing in it is a Node or a Resource")


## The soul the page publishes is the SOUL, key for key with `SoulApi.soul` — not the
## root's envelope wrapped around it.
##
## The bridge hands over `{"soul": ..., "last_death": ...}`, so a screen that passed
## that envelope where a soul was expected made every figure read zero while the page
## looked healthy: the panel printed "Integrity is not measured." beside a standing
## soul, and `"soul"` nested a soul under `"soul"`. This is the assertion that would
## have caught it.
func test_the_published_soul_is_the_soul_and_not_the_bridge_envelope() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	var view := live.summary() as Dictionary
	var soul: Dictionary = view.get("soul", {})
	assert_eq(soul.is_empty(), false, "the page publishes a soul at all")
	assert_eq(soul.has("soul"), false, "and it is not the bridge envelope wrapped in a soul")
	assert_eq(int(soul.get("integrity_max", 0)) > 0, true, "with an authored integrity ceiling")
	assert_eq(int(soul.get("lives_max", 0)) > 0, true, "and an authored lives ceiling")
	# Compared against the facade's OWN shape, so a retune of the published key set is
	# a visible diff rather than a silent one.
	var expected := SoulApi.soul(harness.actor)
	for key in expected.keys():
		assert_eq(soul.has(key), true, "the published soul carries the facade's '%s'" % key)
	# And the panel that renders those figures is showing the same numbers, which is
	# what proves the fix reached the surface rather than only the summary.
	var ledger: Dictionary = view.get("ledger", {})
	assert_eq(
		int(ledger.get("integrity_max", -1)),
		int(soul.get("integrity_max", -2)),
		"and the panel renders that same ceiling, not a zero"
	)


## `{}` with no actor, so a test never reads a half-initialised screen as a real
## view — and `test_ui_conventions.gd` walks every shipped screen for the same rule,
## so this case is the one that proves the guard can still see this screen.
func test_the_page_reports_nothing_before_an_actor_is_bound() -> void:
	var screen := (load(SCREEN) as PackedScene).instantiate()
	assert_ne(screen, null, "soul_hearth_screen.tscn roots a screen")
	if screen == null:
		return
	assert_eq(screen.summary(), {}, "no actor, no view")
	screen.free()


## Every panel on the page answers for itself, and every panel's own summary is what
## the screen nests. A panel that reported `{}` while its row showed data would make
## the screen's nested summary a lie.
func test_every_panel_reports_what_it_is_showing() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	var view := live.summary() as Dictionary
	var ledger: Dictionary = view["ledger"]
	# One format specifier for one value, and the literal `%d/%d` escaped as `%%`.
	# The label as it stood spelled `%d/%d: %s` against a single STRING, so evaluating
	# it raised `String formatting error: a number is required` and threw BEFORE the
	# assertion it describes — taking the two assertions after it down as well.
	var integrity_line := String(ledger.get("integrity_line", ""))
	assert_eq(
		integrity_line.contains("/"), true, "the panel owns its own %%d/%%d: %s" % integrity_line
	)
	assert_eq(ledger.get("restore_verbs", []) as Array, [], "and publishes no restore verb at all")
	var portrait: Dictionary = view["portrait"]
	assert_eq(bool(portrait.get("resolved", false)), true, "the portrait panel resolved a face")
	assert_ne(String(portrait.get("portrait_id", "")), "", "and it is an authored id, never empty")


# --- The difficulty dial -----------------------------------------------------


## THE LOAD-BEARING CASE. One mounted page, ONE PRESSED PRESET BUTTON, and the
## module's own answer asked afterwards. Nothing in this body calls
## `DifficultyApi.select` in place of the press.
func test_pressing_a_preset_button_changes_what_the_page_reports() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	var hero := harness.actor
	var before := live.summary() as Dictionary
	assert_eq(
		String(before.get("difficulty_id", "")),
		String(DifficultyApi.current_id(hero)),
		"the page reports the module's own current id before anything is pressed"
	)
	var share_before := float(
		(before.get("scalars", {}) as Dictionary).get("soul_damage_share", 0.0)
	)

	# THE PRESS. The row's real Button, its real signal, the screen's real handler,
	# the root's real door, and the facade's own write.
	assert_eq(_press_preset(live, String(PRESET_OFFER)), true, "the preset row is a live control")

	# What the MODULE says, asked independently of the screen.
	assert_eq(
		String(DifficultyApi.current_id(hero)),
		String(PRESET_OFFER),
		"and the module now answers the preset that was pressed"
	)
	var after := live.summary() as Dictionary
	assert_eq(
		String(after.get("difficulty_id", "")),
		String(PRESET_OFFER),
		"so the page reports it too, rather than its own memory of the id it asked for"
	)
	# Compared as a NUMBER, not as text: `String(1.5)` is not a valid constructor call
	# in GDScript and aborts the function right here, so a suite that spelled this as
	# a string comparison never reached the four assertions below it.
	assert_ne(
		float((after.get("scalars", {}) as Dictionary).get("soul_damage_share", 0.0)),
		share_before,
		"and the scalars it prints moved, so the surface is wired to real state"
	)
	# The row marked live is the module's answer, not the screen's: exactly one row
	# is `selected`, and it is the one that was pressed.
	var selected := after.get("selected_preset_ids", []) as Array
	assert_eq(selected.size(), 1, "exactly one preset row is marked live")
	assert_eq(selected[0], String(PRESET_OFFER), "and it is the one that was pressed")
	# The live preset is not selectable again: its own button is disabled, because a
	# control that re-selects what is already selected does nothing behind itself.
	var live_row := _preset_row(live, String(PRESET_OFFER))
	assert_eq(
		bool(live_row.get("can_select", true)), false, "the pressed preset is no longer selectable"
	)


## A refused selection is a RENDERED reason, not a silent no-op and not a greyed-out
## button. The player is told `unknown_difficulty` by pressing, which is the only way
## to learn a name that is authored.
func test_an_unknown_preset_is_refused_by_name_and_the_row_shows_it() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	# Committed through the page's own verb rather than a press, because a row only
	# exists for an AUTHORED preset and this id is deliberately not one.
	var out := live.act_select_difficulty(PRESET_UNKNOWN)
	assert_eq(bool(out.get("ok", false)), false, "an unauthored preset is refused")
	assert_eq(
		String(out.get("reason", "")), "unknown_difficulty", "and the module's own name is carried"
	)
	var view := live.summary() as Dictionary
	assert_eq(
		String(view.get("last_select_reason", "")), "unknown_difficulty", "the page reports it"
	)
	assert_eq(bool(view.get("last_select_ok", true)), false, "and agrees it was not ok")
	assert_eq(
		String(view.get("difficulty_id", "")),
		String(DifficultyApi.current_id(harness.actor)),
		"and the run is still under whatever it was under: a refusal writes nothing"
	)


## ADR 0129's neutral row: selecting the shipped default is arithmetically a no-op,
## so choosing the middle option cannot silently retune the run.
func test_the_neutral_preset_is_reported_as_a_no_op() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	assert_eq(_press_preset(live, "hard"), true, "the hard preset can be pressed")
	var hard := live.summary() as Dictionary
	assert_eq(_press_preset(live, "standard"), true, "and the standard preset can be pressed back")
	var standard := live.summary() as Dictionary
	assert_eq(
		String(standard.get("difficulty_id", "")), "standard", "the run is back on the default"
	)
	assert_eq(
		float((hard.get("scalars", {}) as Dictionary).get("soul_damage_share", 0.0)),
		1.5,
		"the hard row scaled a death above the baseline"
	)
	assert_eq(
		float((standard.get("scalars", {}) as Dictionary).get("soul_damage_share", 0.0)),
		1.0,
		"and the standard row is exactly 1.00 on every scalar, so it moves nothing"
	)


# --- The construction works --------------------------------------------------


## THE SECOND LOAD-BEARING CASE. One mounted page, ONE PRESSED RAISE BUTTON, and the
## module's own ledger asked afterwards.
func test_pressing_a_raise_button_changes_what_the_page_reports() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	var hero := harness.actor
	# The hearth asks for two mending elixirs, which a boot hero does not hold, so the
	# first press is a refusal and the SECOND press is the raise. Both halves are the
	# point: a page that only ever showed a success would not be proving the wiring.
	var row := _anchor_row(live, String(HEARTH))
	assert_eq(row.is_empty(), false, "the page lists the authored hearth")
	assert_eq(int(row.get("cost_coins", 0)) > 0, true, "with its authored coin price on it")
	assert_eq(bool(row.get("can_raise", false)), true, "and its raise button is live")

	var refused := live.act_raise_anchor(HEARTH)
	assert_eq(bool(refused.get("ok", false)), false, "a hero short of the elixirs is refused")
	assert_eq(
		String(refused.get("reason", "")), "cannot_afford", "and the module's own name is carried"
	)
	assert_eq(
		(_non_primitives(refused)).is_empty(),
		true,
		"the refusal names what is missing as primitives, so the row can print it"
	)
	var after_refusal := live.summary() as Dictionary
	assert_eq(
		String(after_refusal.get("last_raise_reason", "")), "cannot_afford", "the page reports it"
	)
	assert_eq(
		(after_refusal.get("raised_anchor_ids", []) as Array).has(String(HEARTH)),
		false,
		"and nothing stands raised, so the refusal was not half-applied"
	)

	# PAY THE PRICE. Granted through the inventory the module gates on, so the raise
	# below is the real verb with a real cost rather than a bypass.
	var missing := refused.get("missing", {}) as Dictionary
	assert_eq(missing.is_empty(), false, "and the refusal names what it was short of")
	for def_id in missing.keys():
		_grant(harness.actor, StringName(def_id), int(missing[def_id]))
	assert_eq(
		_press_raise(live, String(HEARTH)), true, "the raise button is still live after a refusal"
	)

	# What the MODULE says, asked independently of the screen.
	assert_eq(
		AnchorApi.is_raised(hero, HEARTH),
		true,
		"and the module now reports the anchor standing where this hero stands"
	)
	var after := live.summary() as Dictionary
	assert_eq(
		(after.get("raised_anchor_ids", []) as Array).has(String(HEARTH)),
		true,
		"so the page shows it raised too"
	)
	var raised_row := _anchor_row(live, String(HEARTH))
	assert_eq(bool(raised_row.get("raised", false)), true, "and its own row says so")


## A second press on a raised anchor is refused BY NAME, and the page renders it
## rather than hiding the control — a player who is told `already_raised` learns what
## to do, and a greyed-out button teaches nothing.
func test_a_second_raise_is_refused_by_name_and_the_row_shows_it() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	_grant_cost(live, String(HEARTH))
	assert_eq(_press_raise(live, String(HEARTH)), true, "the first press raises it")
	var again := live.act_raise_anchor(HEARTH)
	assert_eq(bool(again.get("ok", false)), false, "the second is refused")
	assert_eq(String(again.get("reason", "")), "already_raised", "and the module names why")
	var row := _anchor_row(live, String(HEARTH))
	# Asserted on the PRESSED row specifically, not on "some row somewhere". The module
	# refuses with `"anchor_id": ""`, so a screen that read the id back off its own
	# verdict painted the refusal on NO row and this one went on reading "Ready to
	# raise where you stand." while the message line carried the refusal.
	assert_eq(
		String(row.get("last_reason", "")),
		"already_raised",
		"and the row the player pressed carries the module's own name"
	)
	# The rendered line is compared against the ROW's OWN authored wording, not against
	# a sentence retyped here. The panel is the only thing that owns player-facing
	# prose (AGENTS.md, UI standard), so a suite that restated it would fail on a
	# reword that changed no behaviour — and a reword that DID change the meaning
	# would pass. Same rule as `test_status_readout.gd` and `LootBossPanel.NO_STATUSES`.
	var refusal_line := String(row.get("refusal_line", ""))
	assert_ne(refusal_line.is_empty(), true, "and the row rendered a line rather than nothing")
	assert_eq(
		refusal_line,
		String(AnchorConstructionRow.REFUSAL_TEXT.get("already_raised", "")),
		"and that line is the row's own wording for the module's name"
	)
	# Still the REFUSAL and not the ready line: the two differ, so the comparison above
	# is a real one rather than true of whatever the row happened to paint.
	assert_ne(
		refusal_line,
		String(AnchorConstructionRow.REFUSAL_TEXT.get("", "")),
		"and it is the refusal, not the ready-to-raise line"
	)


## The authored realm floor is shown, not hidden. A player below it is told the floor
## rather than watching nothing happen, which is what ADR 0146 §Consequences asks.
func test_the_realm_floor_is_reported_rather_than_hidden() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	var row := _anchor_row(live, String(STONE))
	assert_eq(row.is_empty(), false, "the page lists the floor-authored stone")
	assert_eq(String(row.get("realm_floor", "")), "core_formation", "with its authored floor on it")
	var out := live.act_raise_anchor(STONE)
	assert_eq(bool(out.get("ok", false)), false, "a boot hero below the floor cannot raise it")
	assert_eq(String(out.get("reason", "")), "realm_floor", "and the refusal is named, not silent")


## Every price on the page is the authored one. A panel that retyped a cost would
## agree with itself and disagree with the module, which is the only thing that can
## charge for it.
func test_every_price_on_the_page_is_the_module_own_figure() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	var anchors := (live.summary() as Dictionary)["anchors"] as Array
	assert_eq(anchors.is_empty(), false, "the page lists at least one authored anchor")
	for entry in anchors:
		var row: Dictionary = entry
		var authored := AnchorApi.cost_of(StringName(String(row.get("id", ""))))
		assert_eq(
			int(row.get("cost_coins", -1)),
			int(authored.get("coins", -2)),
			"%s is shown at the coins cost_of publishes" % row.get("id", "")
		)


## Every refusal this page raises ITSELF is an authored constant on the screen, so a
## missing seam or an unbound actor is named rather than failing quietly. The module's
## own refusals (`cannot_afford`, `already_raised`, `realm_floor`,
## `unknown_difficulty`) are NOT here on purpose: this suite reads those off a module
## verdict rather than off a screen constant, so the page cannot invent its own.
func test_the_screen_publishes_a_name_for_each_of_its_own_refusals() -> void:
	var script := _code(FileAccess.get_file_as_string("res://src/ui/screens/soul_hearth_screen.gd"))
	for reason in [
		SoulHearthScreen.NO_SOUL_SEAM,
		SoulHearthScreen.NO_SAVE_SEAM,
		SoulHearthScreen.NO_ANCHOR_SEAM,
		SoulHearthScreen.NO_DIFFICULTY_SEAM,
		SoulHearthScreen.NO_ACTOR,
	]:
		assert_eq(
			script.contains('"%s"' % reason),
			true,
			"the screen names '%s' rather than failing quietly" % reason
		)


# --- The save ----------------------------------------------------------------


## ADR 0128: the player SEES the save's condition and is given no way to load it.
## The first half is asserted; the second is asserted as a structural fact — this
## surface publishes no verb that could reach the backup slot at all.
func test_the_save_is_reported_as_a_condition_and_offers_no_restore() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	var view := live.summary() as Dictionary
	var save: Dictionary = view["save"]
	assert_eq(save.is_empty(), false, "the page reports the save's condition")
	assert_eq(bool(save.get("primary_present", false)), true, "the live slot is there")
	assert_eq(save.has("backup_present"), true, "and whether a spare generation exists is reported")
	# No verb. Named as a list so a caller can assert the emptiness rather than trust
	# it, and so a future button has somewhere obvious to appear.
	assert_eq(
		(save.get("restore_verbs", []) as Array).is_empty(), true, "the save half restores nothing"
	)
	assert_eq(
		(view["ledger"] as Dictionary).get("restore_verbs", []) as Array,
		[],
		"and the panel that renders it publishes no verb either"
	)


## Writing a generation and then looking again moves the reported generation, so the
## save half is read from the module's own status rather than painted with a literal.
func test_the_reported_save_generation_follows_a_real_write() -> void:
	var harness := _boot()
	if harness == null:
		return
	var live := _open(harness)
	if live == null:
		return
	var before := int((live.summary() as Dictionary)["save"].get("generation", 0))
	SaveApi.persist(harness.actor, String(DifficultyApi.current_id(harness.actor)))
	var after := int((live.summary() as Dictionary)["save"].get("generation", 0))
	assert_eq(
		after > before,
		true,
		"the page's generation moved with the save: %d -> %d" % [before, after]
	)
	assert_eq(
		int(after),
		int(SaveApi.summary().get("generation", -1)),
		"and it agrees with the module's own status line"
	)


# --- Plumbing ----------------------------------------------------------------


func _boot() -> SeamHarness:
	if _harness != null and _harness.app != null:
		return _harness
	_harness = SeamHarness.mount_new()
	assert_eq(_harness.boot_error, "", "the real ItemWorkbenchApp scene boots")
	if _harness.boot_error != "":
		return null
	return _harness


## The page as a player reaches it: the route mounts it and the root binds it.
func _open(harness: SeamHarness) -> SoulHearthScreen:
	var moved := harness.navigate(ROUTE)
	if not bool(moved["ok"]):
		assert_eq(false, true, "the soul route mounts: %s" % moved["note"])
		return null
	return harness.live_screen() as SoulHearthScreen


## Grant whatever the raise of `anchor_id` is short of, so a refusal and a raise can
## both be driven from one page without authoring a fixture. Paid through the items
## facade the module's own gate reads, so the raise below is the real verb with a
## real cost rather than a bypass around one.
func _grant_cost(screen: SoulHearthScreen, anchor_id: String) -> void:
	var refused := screen.act_raise_anchor(StringName(anchor_id))
	var missing := refused.get("missing", {}) as Dictionary
	for def_id in missing.keys():
		_grant(screen.actor(), StringName(def_id), int(missing[def_id]))


## One stack of an authored def, through the items facade. Resolved through
## `Crafting.resolve` — the single catalog resolver `app/` itself uses — rather than
## by path, so a def that moved does not turn this into a null add.
func _grant(actor: Actor, def_id: StringName, quantity: int) -> void:
	if actor == null or quantity <= 0:
		return
	var def := Crafting.resolve(def_id)
	if def == null:
		return
	ItemsApi.inventory(actor).add(def, quantity)


## Press a preset row's real Button. Returns false when there is no such row or the
## control is disabled, so a dead control can never read as a successful selection.
func _press_preset(screen: Node, difficulty_id: String) -> bool:
	return _press_row(screen, "Preset", difficulty_id, "%SelectButton", "difficulty_id")


## Press an anchor row's real Button, under the same refusal-to-count rule.
func _press_raise(screen: Node, anchor_id: String) -> bool:
	return _press_row(screen, "Anchor", anchor_id, "%RaiseButton", "id")


func _press_row(screen: Node, node_name: String, id: String, control: String, key: String) -> bool:
	for node in _all_named(screen, node_name, 0):
		var summary: Dictionary = node.call(&"summary")
		if String(summary.get(key, "")) != id:
			continue
		var button := _find_unique(node, control) as Button
		if button == null or button.disabled:
			return false
		button.pressed.emit()
		return true
	return false


## The row rendering `anchor_id`, as its own summary. `{}` when there is none, so a
## missing row is an empty dictionary rather than an absent method call.
func _anchor_row(screen: Node, anchor_id: String) -> Dictionary:
	for node in _all_named(screen, "Anchor", 0):
		var row: Dictionary = node.call(&"summary")
		if String(row.get("id", "")) == anchor_id:
			return row
	return {}


func _preset_row(screen: Node, difficulty_id: String) -> Dictionary:
	for node in _all_named(screen, "Preset", 0):
		var row: Dictionary = node.call(&"summary")
		if String(row.get("difficulty_id", "")) == difficulty_id:
			return row
	return {}


## Every descendant named `node_name` that is a ROW, bounded by `MAX_TREE_WALK`. The
## bound is what `tests/arch_rules/test_no_unbounded_wait.gd` requires of a recursive
## walk: a junction pointing at an ancestor never returns.
##
## ## Why the prefix match is narrowed to `node.has_method(&"summary")`
##
## The page's own `Presets` / `Anchors` boxes are named with the same prefix as the
## rows they hold, so a bare `begins_with` walk collects the CONTAINER first and
## `summary()` on a `VBoxContainer` is `Nonexistent function` — which ABORTS the
## calling function mid-assertion. The test then reports whatever it happened to have
## asserted before the abort, which is how a suite that never exercised the row at all
## produced twenty-one distinct-looking failures off one cause. A row is a node that
## publishes `summary()`; a container is not one.
func _all_named(node: Node, node_name: String, depth: int) -> Array[Node]:
	var found: Array[Node] = []
	if node == null or depth > MAX_TREE_WALK:
		return found
	for child in node.get_children():
		if String(child.name).begins_with(node_name) and child.has_method(&"summary"):
			found.append(child)
		found.append_array(_all_named(child, node_name, depth + 1))
	return found


func _find_unique(node: Node, unique_name: String) -> Node:
	if node == null:
		return null
	var direct := node.get_node_or_null(unique_name)
	if direct != null:
		return direct
	for child in node.get_children():
		var found := _find_unique(child, unique_name)
		if found != null:
			return found
	return null


## Dotted paths in `value` holding something that is not a primitive, a String, an
## Array, or a Dictionary of the same. A returned node is how a testable surface
## quietly stops being testable.
func _non_primitives(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Dictionary:
		for key in value as Dictionary:
			var child: Variant = (value as Dictionary)[key]
			if child is Dictionary or child is Array or _is_primitive(child):
				out.append_array(_non_primitives(child))
			else:
				out.append(String(key))
		return out
	if value is Array:
		for entry in value as Array:
			out.append_array(_non_primitives(entry))
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
	)


## Source with its comments stripped. Every file in this program documents the rule
## it follows by naming the token the rule forbids, so a raw `contains` over source
## text flags the prose — which is exactly the punishment that teaches the next author
## to delete the explanation instead of keeping the convention.
func _code(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		kept.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(kept)
