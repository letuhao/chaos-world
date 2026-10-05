extends TestCase

## ## Fate earned is announced; this suite proves the codex now answers.
##
## `DestinyEvents` declares four signals and `DestinyProjection.events()` holds the
## one instance they fire on. Until `DestinyScreen` connected, nothing in
## `game/src` did: a fate earned while the codex was open changed a stat and
## nothing else, and the page kept showing a snapshot taken before it happened.
##
## So the surface under test is **the reaction**, and the reaction is narrow on
## purpose (ADR 0065):
##
##   - `fate_earned` / `destiny_earned` re-read the facade and repaint;
##   - the announcement is reported on the screen's own message line and as raw
##     ids under `summary()`;
##   - a hero that is NOT the one this codex is bound to never paints;
##   - nothing here can be pressed, chosen, equipped or given up.
##
## The read-only half is asserted over the SHIPPED SOURCE, not just over
## behaviour: a picker is a control, and a control is not something a behavioural
## test can see. A control this surface grew would be invisible to every
## assertion below, which is exactly why the structural guard is here.

const SCREEN_SCENE := "res://src/ui/screens/destiny_screen.tscn"
const SCREEN_SOURCE := "res://src/ui/screens/destiny_screen.gd"
const BRANCH_SCENE := "res://src/ui/panels/destiny_branch_row.tscn"
const FATE_SCENE := "res://src/ui/panels/fate_row.tscn"
const UI_ROOT := "res://src/ui"

## REAL authored ids, exactly as the contract suite names them — one hero, one
## fate tree, so an earn here and an earn there are the same deed.
const OATH_BREAKER := &"oath_breaker"
const VIGIL := &"vigil_broken_by_hand"
const STAYED := &"the_one_who_stayed"

## The shipped `grants_fates` of `the_one_who_stayed`, read rather than restated.
## `grant_origin` is a convenient way to earn an arrival, but the three arrivals
## are EXCLUSIVE: earning one first is exactly what makes a grant on the hero
## being tested impossible, so this earns a REAL authored branch outright instead.
const STAYED_GRANTS: Array[StringName] = [&"oath_of_the_empty_hand", &"oath_kept_under_witness"]

## A real fate that is `hidden` while unearned, so "the row is listed but
## unnamed" is a rule this suite can observe rather than a comment.
##
## Chosen over `vigil_broken_by_hand`, which the old version of this test named:
## that fate ships `visibility = &"revealed"`, so its name was ALWAYS on the page
## and `the hidden fate starts unnamed` was asking it to hide a name it does not
## have. A hidden fate is the only thing that can answer the question.
const HIDDEN := &"the_third_man_spared"

## The three verbs that would make this surface actionable. Substrings, so a
## RENAMED control (`equip`, `equip_fate`, `EquipButton`) is caught as well as a
## literally named one.
const ACTIONABLE := ["Button", "OptionButton", "pressed.", "gui_input", "toggle_mode"]

## The leaf types a codex snapshot may publish. Named once so the walk at the
## foot of this file reads as a rule rather than a type list.
const PRIMITIVE_TYPES: Array[int] = [
	TYPE_BOOL,
	TYPE_INT,
	TYPE_FLOAT,
	TYPE_STRING,
	TYPE_STRING_NAME,
]

## Screens this suite instantiated, freed in `teardown()`.
##
## A screen connects to a PROCESS-WIDE bus in `_bind_nodes()`. Freeing the node
## does NOT disconnect a GDScript signal connection, so a leaked screen from this
## suite would still be called by the next suite's earns — and would call
## `refresh()` on a freed node. Every screen made here is tracked and freed.
var _instantiated: Array = []


func setup() -> void:
	_instantiated.clear()


func teardown() -> void:
	for node in _instantiated:
		if is_instance_valid(node):
			node.free()
	_instantiated.clear()


func _screen() -> DestinyScreen:
	var scene := load(SCREEN_SCENE) as PackedScene
	var screen := scene.instantiate() as DestinyScreen
	_instantiated.append(screen)
	return screen


func _hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	return actor


# --- The codex reacts ---------------------------------------------------------


## The whole point of the change: an earn while the codex is open moves the page
## without the player navigating anywhere. Asserted on the codex's own reporting
## surface, because that is what a test — and a screenshot — can read.
func test_earning_a_fate_updates_an_open_codex_without_navigation() -> void:
	var actor := _hero()
	var screen := _screen()
	screen.setup(actor)
	var before := screen.summary()
	assert_eq(_held_fates(before), [], "nothing is earned yet, so the codex says so")
	assert_eq(int(before["earned_notice_count"]), 0, "and nothing has been announced to it")

	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")

	var after := screen.summary()
	assert_eq(_held_fates(after), [String(OATH_BREAKER)], "the new fate is on the page")
	assert_eq(int(after["fate_count"]), 1, "and the count followed it")
	# The notice names the fate rather than claiming something happened, so a
	# reader (or a test) can tell WHICH one without re-reading the ledger.
	var notices := after["earned_notices"] as Array
	assert_eq(notices.size(), 1, "one earn, one notice")
	assert_eq(String(notices[0]["id"]), String(OATH_BREAKER), "naming the fate")
	assert_eq(String(notices[0]["kind"]), "fate", "and its kind")
	assert_eq(String(notices[0]["actor"]), String(actor.id), "and the hero it belongs to")
	# The message line is the "you have earned X" half: a report, not a control.
	assert_ne(String(after["message"]), "", "and the screen says something")
	assert_eq(String(after["tone"]), String(UiScreen.TONE_OK), "in the ok tone")


## A hidden fate is UNNAMED until it is earned — and the earn is the only thing
## that reveals it. So a codex that cached a pre-earn snapshot could not spoil
## one, and the repaint is what makes it appear. This is the case a stale page
## would get wrong in the direction that matters.
##
## On `HIDDEN`, a fate authored `visibility = &"hidden"` (asserted from the real
## catalog, so a retune that promoted it would be named rather than silently
## weakening the test). Naming it `the_third_man_spared` rather than the fate the
## first draft used is the whole fix: that one ships `revealed`, and a revealed
## fate is NAMED on the page before it is earned, which is correct behaviour that
## the assertion was reading as a bug.
func test_earning_a_hidden_fate_is_what_names_it_on_an_open_codex() -> void:
	var actor := _hero()
	var screen := _screen()
	screen.setup(actor)
	var def := FateCatalog.instance().fate_definition(HIDDEN)
	assert_ne(def, null, "the shipped fate tree still defines '%s'" % HIDDEN)
	if def == null:
		return
	assert_eq(
		String(def.visibility),
		"hidden",
		"and it is still authored hidden, the only visibility that starts unnamed"
	)
	var before := screen.summary()
	assert_eq(_held_fates(before), [], "nothing is earned yet, so no row may claim to hold it")
	assert_eq(_fate_named(before, HIDDEN), false, "and the hidden fate starts unnamed")
	DestinyApi.earn_fate(actor, HIDDEN, "combat")
	assert_eq(
		_fate_named(screen.summary(), HIDDEN),
		true,
		"and the earn is what revealed it, without a re-navigation"
	)


## A destiny is announced on its own signal, and it carries its `grants_fates`
## with it — so one earn brings a branch AND the fates it carries. Both have to
## reach the page: a branch whose consequences are swallowed by the announcement is
## how a consumer loses them.
##
## **The old version asserted only `notices.size() > 1`, and that was wrong
## rather than fragile.** `DestinyApi._persist` is called once, for the destiny,
## and announces that; each granted fate appends to the ledger and records history
## but announces nothing — so a correct screen reports exactly ONE notice, and the
## assertion was asking for a second one that no correct implementation produces.
## The guarantee worth having is APPEND-vs-REPLACE and the fates-on-the-page, and
## both are asserted here instead: this hero earns the branch, then earns a second
## fate, and both announcements must still be present, oldest first.
func test_earning_a_destiny_reports_the_branch_and_the_fates_it_carried() -> void:
	var actor := _hero()
	var screen := _screen()
	screen.setup(actor)
	var def := FateCatalog.instance().destiny_definition(STAYED)
	assert_ne(def, null, "the shipped tree defines '%s'" % STAYED)
	if def == null:
		return
	assert_eq(
		def.grants_fates,
		STAYED_GRANTS,
		"and it still grants the fates this suite reads, read off the shipped def"
	)
	DestinyApi.earn_destiny(actor, STAYED, "story")

	var view := screen.summary()
	var notices := view["earned_notices"] as Array
	assert_eq(
		notices.size(),
		1,
		"one earn, one announcement — the branch is announced once, not once per carried fate"
	)
	var entry: Dictionary = notices[0]
	assert_eq(String(entry["kind"]), "destiny", "announced as the destiny it was")
	assert_eq(String(entry["id"]), String(STAYED), "by its own id")
	# Whatever the branch carried is on the page too, not swallowed by the notice.
	var carried := DestinyApi.fates(actor)
	assert_eq(_sorted_ids(carried), _sorted_ids(STAYED_GRANTS), "the branch carried its fates")
	for fate_id in carried:
		assert_eq(
			_held_fates(view).has(String(fate_id)),
			true,
			"the carried fate '%s' reached the codex" % fate_id
		)
	assert_eq(_held_destinies(view), [String(STAYED)], "and the branch is held on the page")
	# The append half: a second, separate earn must not REPLACE the branch notice.
	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")
	var after := screen.summary()["earned_notices"] as Array
	assert_eq(
		after.size(), 2, "a second earn appends rather than replacing the branch announcement"
	)
	assert_eq(String((after[0] as Dictionary)["id"]), String(STAYED), "oldest first: the branch")
	assert_eq(
		String((after[1] as Dictionary)["id"]),
		String(OATH_BREAKER),
		"then the fate, so nothing an earlier earn reported is lost"
	)


## Exactly-once is the earn-only invariant, and it reaches the UI: a replayed
## earn must not produce a second notice, or a quest that pays a fate twice
## would tell the player the story twice.
func test_a_replayed_earn_announces_once_on_the_codex_too() -> void:
	var actor := _hero()
	var screen := _screen()
	screen.setup(actor)
	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")
	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")
	DestinyApi.earn_fate(actor, OATH_BREAKER, "quest:test")
	assert_eq(
		(screen.summary()["earned_notices"] as Array).size(),
		1,
		"three earns of the same fate produce one notice"
	)
	assert_eq(_held_fates(screen.summary()).size(), 1, "and one row")


## The bus carries an `actor_id` STRING, not an `Actor` (ADR 0136). A second
## hero earning a fate while this page is open is a real production possibility,
## and painting it would show the wrong ledger's row on this hero's page.
func test_an_earn_for_another_hero_is_never_painted_on_this_codex() -> void:
	var mine := _hero(&"mine")
	var other := _hero(&"other")
	var screen := _screen()
	screen.setup(mine)
	DestinyApi.earn_fate(other, OATH_BREAKER, "combat")
	assert_eq(
		(screen.summary()["earned_notices"] as Array).is_empty(),
		true,
		"another hero's earn says nothing here"
	)
	assert_eq(_held_fates(screen.summary()), [], "and painted no row")
	# Counted rather than silently dropped, so a screen that filtered too much
	# is as visible as one that filtered too little.
	assert_eq(int(screen.summary()["foreign_earns"]), 1, "it is counted instead")
	# And the bound hero's own earn still works, so the filter is not a mute.
	DestinyApi.earn_fate(mine, VIGIL, "combat")
	assert_eq(_held_fates(screen.summary()), [String(VIGIL)], "its own earn still paints")


# --- Read-only, and the degradation -------------------------------------------


## ADR 0065: fate is earned and never choosable, so the screen may REPORT an
## earn and never act on one. `read_only` is the screen's own claim; this is the
## independent check that the page it renders holds no actionable control.
func test_the_codex_reports_read_only_and_holds_no_actionable_control() -> void:
	var actor := _hero()
	var screen := _screen()
	screen.setup(actor)
	DestinyApi.earn_fate(actor, OATH_BREAKER, "combat")
	var view := screen.summary()
	assert_eq(bool(view["read_only"]), true, "the screen says it is read-only")
	# Structural: not one of the rows this screen fills can be pressed.
	for row in _rows_of(screen):
		var summary: Dictionary = row.call(&"summary")
		for key in summary.keys():
			var value: Variant = summary[key]
			if value is String or value is StringName:
				assert_eq(
					(
						String(value).contains("Button")
						or String(value).contains("Option")
						or String(value).contains("Equip")
						or String(value).contains("Choose")
						or String(value).contains("Select")
					),
					false,
					"row '%s' publishes no control name" % key
				)
	# And the screen consumes no input at all, so nothing here is reachable by a
	# press in the first place.
	assert_eq(
		screen.on_stack_input(null),
		false,
		"the codex consumes nothing, so `ui_cancel` still pops it"
	)


## Today's real state: a hero who has earned nothing opens the codex. It has to
## render, report zero, and — because the bus fires for everyone — survive an
## earn landing while it is open with no actor bound to announce it to.
func test_the_codex_degrades_cleanly_when_no_fate_was_ever_earned() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "no actor, no view at all")
	assert_eq(screen.earned_notices(), [], "and no notices")
	# An earn while nothing is bound: there is no ledger to paint, so it is
	# counted and dropped rather than crashing on a null actor.
	DestinyApi.earn_fate(_hero(&"elsewhere"), OATH_BREAKER, "combat")
	assert_eq(screen.summary(), {}, "still no view")
	assert_eq(screen.foreign_earns(), 1, "and the unbroadcastable earn is counted")
	# The real state, with an actor: a bound hero who has earned nothing renders
	# a complete codex whose earned section is empty and whose locked section is
	# full — which is a report, not a failure.
	var actor := _hero()
	screen.setup(actor)
	var view := screen.summary()
	assert_ne(view, {}, "a bound hero gives a view even with nothing earned")
	assert_eq(_held_fates(view), [], "no fate is held")
	assert_eq(int(view["fate_count"]), 0, "and the count is zero")
	assert_eq(
		(view["locked_fates"] as Array).is_empty(),
		false,
		"while the locked list is still shown, because the codex is a codex"
	)
	assert_eq(_primitives_only(view), true, "and the whole thing is primitives")


# --- The structural guard: read-only over the shipped source ------------------


## **The load-bearing assertion in this suite.**
##
## A picker is a CONTROL, and a control is not something the behavioural
## assertions above can see: `on_stack_input` returns false, the rows report
## dictionaries, and a `Button` added to the scene would change none of them. So
## the invariant is asserted over the shipped SOURCE of the screen and both of
## the rows it fills — comments stripped, because these files DOCSTRING the verbs
## they never call, and searching raw text fails a file for explaining itself.
##
## This is the same shape as `test_character_creation.gd`'s codex guard, extended
## to the new listener: the earn handler is the newest code on this screen, and
## it is the place a future agent would plausibly reach for a "confirm" button.
func test_the_codex_source_contains_no_actionable_control_at_all() -> void:
	for path in [SCREEN_SOURCE, BRANCH_SCENE, FATE_SCENE]:
		var code := _code_only(path)
		assert_eq(code.is_empty(), false, "%s has readable source" % path)
		for verb in ACTIONABLE:
			assert_eq(
				code.contains(verb),
				false,
				(
					(
						"%s uses '%s'; fate is earned and never choosable (ADR 0065), and a"
						% [path, verb]
					)
					+ " control here would offer a choice the module forbids"
				)
			)
	# The earn verbs themselves: a screen that rendered one could grant a fate.
	#
	# **This is where the read-only verdict actually comes from, and it is GREEN.**
	# `destiny_screen.gd` names no `equip`, `select_fate`, `act_commit`,
	# `earn_fate` or `earn_destiny` anywhere in its code — its only "equip" is the
	# English word inside a footer STRING that tells the player nothing is
	# equipped, and `_code_only` cannot tell prose from a symbol.
	for verb in ["earn_fate", "earn_destiny", "act_commit", "select_fate"]:
		assert_eq(
			_executable_code(SCREEN_SOURCE).contains(verb),
			false,
			"the codex has no %s: it is read-only by design" % verb
		)
	assert_eq(
		_executable_code(SCREEN_SOURCE).contains("equip"),
		false,
		(
			"the codex has no equip: it is read-only by design. `equip` survives only inside"
			+ " a footer STRING literal, which `_executable_code` strips, so the screen"
			+ " really is read-only."
		)
	)


## The UI standard, asserted over the files this change touched rather than
## restated from `AGENTS.md`: nodes resolve lazily through `_bind_nodes()`, and
## styling is by `theme_type_variation` only. Both are also caught by
## `test_ui_conventions.gd`, and that redundancy is deliberate — a guard that
## lives only in another file is a guard that can be deleted silently.
func test_the_codex_binds_lazily_and_styles_by_variation_only() -> void:
	for path in [SCREEN_SOURCE, BRANCH_SCENE, FATE_SCENE]:
		var code := _code_only(path)
		assert_eq(code.contains("@onready"), false, "%s binds no node in @onready" % path)
		assert_eq(
			code.contains("theme_override"),
			false,
			"%s styles itself; style belongs to the one theme" % path
		)
		if code.contains("get_node_or_null("):
			assert_eq(
				code.contains("func _bind_nodes()"),
				true,
				"%s resolves nodes, so it must do it in an idempotent _bind_nodes()" % path
			)


## Every `.connect()` on this screen is guarded by `is_connected()`. The bus is a
## process-wide singleton, so an unguarded connect is one handler per earn for
## the lifetime of the process — the duplicate would not fail any behavioural
## assertion above unless the test happened to bind twice.
func test_every_connect_on_the_codex_is_guarded() -> void:
	var code := _code_only(SCREEN_SOURCE)
	var connects := code.count(".connect(")
	assert_eq(connects > 0, true, "the codex really is subscribed to something")
	var guards := code.count(".is_connected(")
	assert_eq(
		guards >= connects,
		true,
		"every connect (%d) has an is_connected guard (%d)" % [connects, guards]
	)


# --- Helpers ------------------------------------------------------------------


## Every row control this screen filled, as nodes, so their own summaries can be
## walked without re-deriving the pool.
func _rows_of(screen: DestinyScreen) -> Array:
	var out: Array = []
	for path in ["Layout/Scroll/Codex/Destinies", "Layout/Scroll/Codex/Fates"]:
		var box := screen.get_node_or_null(path)
		if box == null:
			continue
		for child in box.get_children():
			if child.has_method(&"summary"):
				out.append(child)
	return out


## An id list as sorted STRINGS, so two lists compare as values rather than as an
## `Array[StringName]` against a differently-typed one. Order is not the subject
## here — set membership is — so both sides are normalised before they meet.
func _sorted_ids(source: Array) -> Array:
	var out: Array = []
	for entry in source:
		out.append(String(entry))
	out.sort()
	return out


## The fate ids the codex is showing as HELD. Read from the screen's own summary
## rather than the facade, so a repaint that failed shows up here as a missing
## row instead of being masked by a fresh facade read.
func _held_fates(view: Dictionary) -> Array:
	var out: Array = []
	for entry in view["fates"] as Array:
		var row: Dictionary = entry
		if bool(row.get("held", false)):
			out.append(String(row.get("id", "")))
	out.sort()
	return out


func _held_destinies(view: Dictionary) -> Array:
	var out: Array = []
	for entry in view["destinies"] as Array:
		var row: Dictionary = entry
		if bool(row.get("held", false)):
			out.append(String(row.get("id", "")))
	out.sort()
	return out


## Whether the codex is willing to show this fate's NAME. A hidden fate is
## `false` until it is earned, which is the whole point of asserting here.
func _fate_named(view: Dictionary, fate_id: StringName) -> bool:
	for entry in view["fates"] as Array:
		var row: Dictionary = entry
		if String(row.get("id", "")) == String(fate_id):
			return bool(row.get("named", false))
	return false


## The CODE of a GDScript file, with every comment line removed — see
## `test_ui_conventions.gd` for why a convention guard must read code and not
## prose.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash := line.find("#")
		if hash >= 0:
			line = line.substr(0, hash)
		out.append(line)
	return "\n".join(out)


## `_code_only`, then with every DOUBLE-QUOTED string literal removed as well —
## i.e. what actually EXECUTES, with prose and data out of it.
##
## **This is the helper the read-only verdict needs and `_code_only` is not.**
## `_code_only` strips comment lines, which is right for `Button`/`OptionButton`
## (Godot node type names only ever appear as symbols) but wrong for a VERB: the
## one occurrence of `equip` in `destiny_screen.gd` is the word inside
## `_footer.text = "Read-only: nothing here is chosen, equipped or given up."` —
## a STRING on a non-comment line, so `_code_only` reported it as a code hit and
## `test_the_codex_source_contains_no_actionable_control_at_all` went red claiming
## an equip affordance that does not exist. The screen is read-only.
##
## The screen's own English is part of the contract it publishes, so it is removed
## only for the verb scan and kept for the structural scan above, which must still
## see a `Button` that a future author might mount. Quote-aware rather than a regex
## over the whole file: a `"` inside another literal, or an escaped `\"`, would
## otherwise desynchronise the scan and quietly truncate it.
##
## Multi-line strings and docstrings are covered by the comment strip in
## `_code_only`, and GDScript has no raw-string form, so a single pass is complete.
func _executable_code(path: String) -> String:
	var out: Array[String] = []
	var in_string := false
	for raw in _code_only(path).split("\n"):
		var line := ""
		var escaped := false
		for index in raw.length():
			var ch := raw[index]
			if in_string:
				# Keep scanning to the closing quote, but emit nothing: the literal
				# is data the screen shows, never a verb it can call.
				if escaped:
					escaped = false
				elif ch == "\\":
					escaped = true
				elif ch == '"':
					in_string = false
				continue
			if ch == '"':
				in_string = true
				line += " "
				continue
			if ch == "#":
				break
			line += ch
		out.append(line)
	return "\n".join(out)


## Whether every leaf of `value` is a primitive. Recursive with a depth cap,
## because the arch rule requires one of any walk that could meet a cycle.
##
## **Keys are deliberately NOT checked, and this helper is the correct shape for
## that.** The sibling helper in `test_destiny_hub_contract.gd` checked keys and
## required them to be `String`, so `DestinyApi.summary()` failed it on
## `StringName` keys — `StringName` is a built-in Variant scalar, and the view a
## panel renders is unaffected by whether a key is `&"fate"` or `"fate"`. Here the
## question is narrower and stated honestly: every VALUE the codex publishes is a
## primitive, which is the part a consumer cannot adapt around. Keys are checked
## for being a key by virtue of being in a Dictionary's `keys()`.
##
## The cap is 5 because a section row contributes `summary -> fates[]` and a fate
## row contributes its own `summary` one level deeper, so a realistic codex is
## already two levels past the view. Raising it past a value that would really nest
## that far would be widening the budget for nothing.
func _primitives_only(value: Variant, depth: int = 0) -> bool:
	# One return rather than one per `match` arm — the repo's linter counts
	# returns, and a seven-return helper for a five-type question is noise. Same
	# walk: a leaf is a primitive, a container is only as good as its contents,
	# and a deep nest is a refusal rather than a stack overflow.
	if depth > 5:
		return false
	var kind := typeof(value)
	if kind in PRIMITIVE_TYPES:
		return true
	var children: Array = []
	if kind == TYPE_DICTIONARY:
		for key in (value as Dictionary).keys():
			if not (key is String or key is StringName):
				return false
			children.append((value as Dictionary)[key])
	elif kind == TYPE_ARRAY:
		children.assign(value as Array)
	else:
		return false
	for child in children:
		if not _primitives_only(child, depth + 1):
			return false
	return true
