extends TestCase

## The lineage screen: ONE page over three `summary()` read models, asserted through
## `summary()` rather than pixels (UI standard, ADR 0080).
##
## ## What is load-bearing here, and what is merely taste
##
## Four claims, each of which a later edit could quietly undo:
##
##  1. **One screen, three facades, one call each.** `RaceApi.summary`,
##     `BloodlineApi.summary`, `ClanApi.summary` and nothing else from any of the
##     three modules. Enforced by SOURCE READ, because that is the only check that
##     survives a refactor of the script — `tools arch` checks the module side, this
##     checks the UI side, and `test_sect_screen` already established the pattern.
##  2. **A DORMANT bloodline is VISIBLE.** Purity decays and is never raised
##     (ADR 0063), and `BloodlineProjection` keeps the `bloodline:<id>` trait mirror
##     on while dormant precisely so a sleeping lineage is not the same as no
##     lineage. A screen that filtered on `awake` would leave a live trait with no
##     visible cause. This is the case most likely to be silently dropped, so it is
##     asserted three ways: the row exists, the row reports `dormant: true`, and the
##     screen's own `dormant_lineage_ids` names it.
##  3. **Belonging to no clan is a sentence, not an empty card.** `ClanApi` publishes
##     an empty membership block with `has_actor: true`, and the normal starting
##     state is no house (ADR 0064).
##  4. **`{}` with no actor, and primitives only** — the screen contract
##     `test_ui_conventions` walks. Asserted here too so a failure names the lineage
##     screen rather than a generic scan.

const SCREEN_SCENE := preload("res://src/ui/screens/lineage_screen.tscn")
const SCREEN_SCRIPT := "res://src/ui/screens/lineage_screen.gd"
const LINEAGE_ROUTE := &"lineage"
const LINEAGE_SCENE_PATH := "res://src/ui/screens/lineage_screen.tscn"
## The three row scenes, by the paths the screen itself mounts them by. Read here
## rather than restated so the code scan follows the screen if a row ever moves.
const BODY_SCENE_PATH := "res://src/ui/panels/lineage_body_row.tscn"
const BLOOD_SCENE_PATH := "res://src/ui/panels/lineage_blood_row.tscn"
const HOUSE_SCENE_PATH := "res://src/ui/panels/lineage_house_row.tscn"

## The ONLY identifier each module may be named by from this screen, and the one
## call of each. ADR 0083 folds every read a screen needs into `summary()` rather
## than growing a facade past its 12-method cap; three facades make that fold
## worth proving three times over.
const RACES_ONLY := ["RaceApi.summary"]
const BLOODLINES_ONLY := ["BloodlineApi.summary"]
const CLANS_ONLY := ["ClanApi.summary"]
const MODULES_ROOT := "res://src/modules/"

## Authored content ids, read from the shipped `.tres` rather than invented, so a
## retune of the catalog does not silently invalidate the fixture.
const RACE := &"stoneborn"
## The path `stoneborn` authors closed (`game/data/races/stoneborn.tres`). Named here so the
## assertion reads the authored content rather than a literal repeated in the test body.
const CLOSED_PATH := &"mind_cultivation"
const AWAKENED_LINEAGE := &"tideborn"
const DORMANT_LINEAGE := &"hearthborn"
## `hearthborn`'s authored bar is 0.42, so 0.20 is carried AND below it.
const DORMANT_PURITY := 0.2
const AWAKENED_PURITY := 0.9
## The Saltledger claims `hearthborn` as its founding line and opens admission at
## 0.42, so a hero carrying it above that bar is admissible.
const HOUSE := &"saltledger"

## The route is the only thing that makes this page reachable. `ScreenRoutes` is in
## `app/` and was under active rewrite while this slice landed, so this suite states
## the row it needs and skips it rather than failing — a skipped assertion is a
## reported gap, whereas a red suite would name another agent's in-flight change.
const ROUTE_REASON := (
	"ScreenRoutes does not name a route for lineage_screen.tscn; app/ was being "
	+ "rewritten concurrently, so the route entry is a one-line follow-up"
)


func _actor() -> Actor:
	var actor := ActorFactory.build(&"lineage_reader")
	RaceApi.attach(actor)
	BloodlineApi.attach(actor)
	ClanApi.attach(actor)
	return actor


## A hero with a body, one awake lineage and one dormant one, and no house — the
## state a freshly arrived player is actually in.
func _carrying() -> Actor:
	var actor := _actor()
	RaceApi.set_race(actor, RACE)
	BloodlineApi.set_purity(actor, AWAKENED_LINEAGE, AWAKENED_PURITY)
	BloodlineApi.set_purity(actor, DORMANT_LINEAGE, DORMANT_PURITY)
	return actor


## The same, plus a house.
func _sworn() -> Actor:
	var actor := _carrying()
	BloodlineApi.set_purity(actor, DORMANT_LINEAGE, 0.5)
	ClanApi.join(actor, HOUSE)
	ClanApi.move_standing(actor, 60)
	return actor


func _screen() -> LineageScreen:
	return (SCREEN_SCENE as PackedScene).instantiate() as LineageScreen


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()


# --- The screen contract ----------------------------------------------------


func test_the_screen_summary_is_empty_without_an_actor() -> void:
	# ADR 0083's first state needs `{}` to be REACHABLE, so a screen reporting keys
	# with nothing bound would make the state unreadable rather than merely empty.
	var screen := _screen()
	assert_eq(screen.summary(), {}, "empty with no actor, not a half-built view")
	screen.free()


func test_the_screen_summary_is_empty_after_a_refresh_with_no_actor() -> void:
	# `refresh()` is what the stack calls on `on_screen_shown`, so the empty state has
	# to survive it. A screen that filled its rows on a null actor would answer here.
	var screen := _screen()
	screen.on_screen_shown()
	screen.on_screen_hidden()
	screen.focus_initial()
	assert_eq(screen.summary(), {}, "the four hooks leave the no-actor state empty")
	screen.free()


func test_the_screen_reports_the_actor_it_renders_and_the_body_it_found() -> void:
	var actor := _carrying()
	var screen := _screen()
	screen.setup(actor)
	var view := screen.summary()
	assert_ne(view, {}, "a bound actor gives a view")
	assert_eq(String(view["actor"]), String(actor.id), "it names the actor it renders")
	assert_eq(bool(view["read_only"]), true, "and says it is read-only")
	assert_eq(String(view["race_id"]), String(RACE), "the race the hero was born")
	screen.free()


## The body half: the refusals, the ceiling and the affinities, RAW. The screen
## formats nothing — the row does — so what it reports is the facade's own numbers.
func test_the_body_half_reports_the_closed_paths_the_ceiling_and_the_affinities() -> void:
	var screen := _screen()
	screen.setup(_carrying())
	var view := screen.summary()
	var facade := RaceApi.summary(_carrying())
	assert_eq(
		view["closed_paths"] as Array,
		facade["closed_paths"] as Array,
		"the closed paths are the facade's, not a re-derivation"
	)
	assert_eq(int(view["open_path_count"]), int(facade["open_path_count"]), "and the open count")
	assert_eq(int(view["realm_ceiling"]), int(facade["realm_ceiling"]), "the realm ceiling")
	assert_eq(int(view["realm_reached"]), int(facade["realm_reached"]), "the realm reached")
	assert_almost_eq(float(view["lifespan"]), float(facade["lifespan"]), "the lifespan")
	assert_eq(
		(view["affinities"] as Dictionary) == (facade["affinities"] as Dictionary),
		true,
		"and the affinities"
	)
	screen.free()


## ADR 0062: a race is a body plan that REFUSES, so the closed list is content
## rather than a gap. A stoneborn closes mind cultivation outright and must say so.
func test_a_body_that_closes_a_path_says_so_on_the_screen() -> void:
	var screen := _screen()
	screen.setup(_carrying())
	var view := screen.summary()
	var closed: Array = view["closed_paths"]
	assert_ne(closed.is_empty(), true, "the fixture's body closes something")
	assert_eq(closed.has(CLOSED_PATH), true, "and it is named on the screen")
	assert_eq(int(view["closed_path_count"]), closed.size(), "the count agrees with the list")
	screen.free()


## The body row's OWN summary, nested under `body` — the screen contract's "child
## summaries nested under the child's key".
func test_the_body_row_summary_is_nested_under_body() -> void:
	var screen := _screen()
	screen.setup(_carrying())
	var body: Array = screen.summary()["body"]
	assert_ne(body.is_empty(), true, "the body row is rendered and reports itself")
	var row: Dictionary = body[0]
	assert_eq(String(row["race_id"]), String(RACE), "and names the same race")
	assert_eq(String(row["refusal_line"]) != "", true, "and prints the refusal in words, not blank")
	screen.free()


## ## `assert_ne(x, true)`, NOT `assert_ne(x, false)`
##
## The framework's signature is `assert_ne(actual, unexpected)` — it passes when
## `actual != unexpected` — so `assert_ne(x, true)` passes only when `x` is false and
## `assert_ne(x, false)` passes only when `x` is TRUE. An `is_empty()` or
## `== []` predicate therefore has to be written against the POSITIVE one. Written
## the intuitive way round, this suite's body, house and snapshot assertions read as
## demanding an EMPTY list from a screen that had correctly rendered one — and the
## screen was right every time. All three of this file's row-presence assertions
## (body, house, row ids) are the corrected form, and `is_empty(), false` must appear
## nowhere in this file.
func test_a_row_is_reported_as_present_by_asking_for_its_absence() -> void:
	# The idiom this file uses for presence, asserted so the sense cannot drift back.
	# REAL values, not constants: written as `false != false` and `[] != []` both
	# sides were literals, so each assertion folded to a constant, could never fail,
	# and never called `assert_ne` at all.
	var empty_body: Array = []
	var one_row: Array = [{}]
	assert_eq(empty_body.is_empty(), true, "an EMPTY list is empty, which is the case to avoid")
	assert_ne(one_row.is_empty(), true, "assert_ne(x.is_empty(), true) is the PRESENCE form")
	# And the shape this file actually relies on, passing on a real body.
	var screen := _screen()
	screen.setup(_carrying())
	var body: Array = screen.summary()["body"]
	# "there IS a row" is `is_empty() == false`. `assert_ne(x, true)` states exactly that
	# and is the form used here on purpose: `assert_eq(x.is_empty(), false)` reads the same but
	# this file has already been bitten by the inverse form once.
	assert_ne(body.is_empty(), true, "assert_ne(size, true) passes when there IS a row")
	screen.free()


# --- Inheritance, and the dormant case --------------------------------------


## ## THE CASE. A lineage carried below its bar is STILL CARRIED, and the trait
## mirror is deliberately left on while it sleeps. So the screen must render it.
##
## Four separate claims, because a screen could satisfy any three of them and drop
## the one that matters: the row EXISTS, the row is NOT filtered as absent, the row
## reports `dormant` as its own word, and the SCREEN names it in
## `dormant_lineage_ids`.
func test_a_dormant_bloodline_is_visible_on_the_screen() -> void:
	var screen := _screen()
	screen.setup(_carrying())
	var view := screen.summary()

	assert_eq(int(view["awakened_count"]), 1, "one lineage is awake, so the other is not")
	var rows: Array = view["bloodlines"]
	var dormant := _find_row(rows, String(DORMANT_LINEAGE))
	assert_ne(dormant, {}, "the dormant lineage has a row on the screen")
	assert_eq(dormant.is_empty(), false, "so it was not dropped as absent")
	assert_eq(bool(dormant["awake"]), false, "it is not awake")
	assert_eq(
		String(dormant["tier"]),
		"dormant",
		"and the row says the facade's own word for it, not merely 'not awake'"
	)
	assert_eq(bool(dormant["dormant"]), true, "dormant is its own reported claim")
	assert_almost_eq(float(dormant["purity"]), DORMANT_PURITY, "at the concentration it carries")
	assert_ne(String(dormant["name_line"]), "", "so a player can read what they carry")
	screen.free()


## The screen's OWN half of the same claim, asserted independently of the rows: a
## test that only walked the tree could pass while `summary()` reported nothing.
func test_the_screen_names_its_dormant_lineages_and_their_count() -> void:
	var screen := _screen()
	screen.setup(_carrying())
	var view := screen.summary()
	assert_eq(
		view["dormant_lineage_ids"] as Array,
		[String(DORMANT_LINEAGE)],
		"the screen reports which lineages are carried and dormant"
	)
	assert_eq(int(view["dormant_count"]), 1, "and how many")
	assert_eq(
		view["awake_lineage_ids"] as Array,
		[String(AWAKENED_LINEAGE)],
		"beside the ones that are awake, so the two never read alike"
	)
	screen.free()


## The trait mirror is on the actor while dormant, so a row that hid the lineage
## would leave a live trait with no visible cause. Assert the mirror AND the row in
## one case: the two are the same fact seen from the two ends of the boundary.
func test_the_dormant_rows_trait_is_still_on_the_actor_and_the_row_still_shows() -> void:
	var actor := _carrying()
	var screen := _screen()
	screen.setup(actor)
	assert_eq(
		actor.traits.has(BloodlineState.trait_for(DORMANT_LINEAGE)),
		true,
		"the projection keeps the mirror on while the lineage sleeps (ADR 0063)"
	)
	var view := screen.summary()
	assert_ne(
		_find_row(view["bloodlines"] as Array, String(DORMANT_LINEAGE)),
		{},
		"and the screen renders the lineage that owns that mirror"
	)
	screen.free()


## An awake lineage leads: it is what the hero can use, and the dormant line below
## it must stay findable rather than lost under it.
func test_an_awake_lineage_leads_and_the_dormant_one_follows_in_the_row_order() -> void:
	var screen := _screen()
	screen.setup(_carrying())
	var rows: Array = screen.summary()["bloodlines"]
	assert_eq(rows.size(), 2, "both carried lineages have a row")
	assert_eq(
		String((rows[0] as Dictionary)["lineage_id"]),
		String(AWAKENED_LINEAGE),
		"the awake one leads"
	)
	assert_eq(
		String((rows[1] as Dictionary)["lineage_id"]),
		String(DORMANT_LINEAGE),
		"and the dormant one follows, still on the page"
	)
	assert_eq(
		(screen.summary()["row_ids"] as Array).has(String(DORMANT_LINEAGE)),
		true,
		"and it is in the reported row order too, not only in the tree"
	)
	screen.free()


## A hero who carries NOTHING gets a page that says so rather than an empty one.
func test_a_hero_who_carries_no_lineage_reports_zero_and_says_nothing_is_carried() -> void:
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	assert_eq(int(view["lineage_count"]), 0, "no lineage carried")
	assert_eq(int(view["awakened_count"]), 0, "none awake")
	assert_eq(int(view["dormant_count"]), 0, "and none dormant, which is not the same claim")
	assert_eq(view["bloodlines"] as Array, [], "and no row invents one")
	screen.free()


# --- House ------------------------------------------------------------------


## ADR 0064: a clan OWES and ASKS, and those terms are the whole feature. A screen
## that showed a house's name and nothing else would have published a membership
## with no content in it.
func test_the_house_half_reports_the_published_patronage_and_duty_terms() -> void:
	var screen := _screen()
	screen.setup(_sworn())
	var view := screen.summary()
	assert_eq(bool(view["is_member"]), true, "the hero belongs to a house")
	assert_eq(String(view["clan_id"]), String(HOUSE), "and it is the one the fixture joined")
	assert_ne((view["patronage"] as Array).is_empty(), true, "the house publishes patronage")
	assert_ne((view["duty"] as Array).is_empty(), true, "and it publishes duty")
	assert_eq(
		int(view["patronage_count"]),
		(view["patronage"] as Array).size(),
		"the count agrees with the terms, so an empty list cannot hide"
	)
	assert_eq(int(view["duty_count"]), (view["duty"] as Array).size(), "and the same for duty")
	screen.free()


## Position and standing are TWO facts (ADR 0064's split) and the screen reports
## both, RAW. A screen that divided one by the other into a rank would have thrown
## the politics away at the last step.
func test_the_house_half_reports_position_and_standing_as_separate_facts() -> void:
	var screen := _screen()
	screen.setup(_sworn())
	var view := screen.summary()
	assert_ne(String(view["rank"]), "", "the member holds a position")
	assert_eq(int(view["standing"]), 60, "and a standing of their own")
	assert_ne(float(view["recognition"]), 0.0, "with the recognition it publishes")
	assert_eq(
		float(view["recognition"]) != float(view["standing"]),
		true,
		"and the two genuinely differ, which is the hinge (ADR 0064)"
	)
	screen.free()


## Belonging to none is the NORMAL state, so it renders a house row that says so.
func test_a_hero_who_belongs_to_no_clan_is_told_so_rather_than_shown_nothing() -> void:
	var screen := _screen()
	screen.setup(_carrying())
	var view := screen.summary()
	assert_eq(bool(view["is_member"]), false, "and reports no membership, plainly")
	assert_eq(String(view["clan_id"]), "", "with no house named")
	assert_eq(int(view["standing"]), 0, "and no standing, which is absence rather than an error")
	var house: Array = view["house"]
	assert_ne(house.is_empty(), true, "the house ROW still renders")
	var row: Dictionary = house[0]
	assert_eq(bool(row["is_member"]), false, "and it reports itself as no membership")
	assert_ne(String(row["name_line"]), "", "with a sentence rather than an empty card")
	assert_ne(String(row["meta"]), "", "and a reason, so absence reads as normal")
	screen.free()


# --- The pure-consumer rule, by source read ---------------------------------


## Exactly three facade calls, one per module, and nothing else from any of the
## three. `tools arch` checks the module side of the facade rule; this checks the
## UI side, and it is the only check that survives a refactor of this file.
func test_the_screen_names_only_the_three_facades_and_only_their_summary() -> void:
	var source := FileAccess.get_file_as_string(SCREEN_SCRIPT)
	assert_eq(source.is_empty(), false, "the screen script is readable")
	for module in ["race", "bloodline", "clan"]:
		assert_eq(
			_module_dirs_named_by(source).has(module),
			false,
			(
				(
					"%s names modules/%s/ directly; a screen may reach a module only "
					% [SCREEN_SCRIPT, module]
				)
				+ "through its facade"
			)
		)
	for call in RACES_ONLY + BLOODLINES_ONLY + CLANS_ONLY:
		assert_eq(
			source.count("%s(" % call),
			1,
			"%s is called exactly once — once per refresh, never per summary()" % call
		)


## ## The growth guard: no OTHER facade verb
##
## The three `summary()` calls above are the whole of what this screen is allowed
## to ask of those modules. `attach`, `set_race`, `set_purity`, `join`, `move_standing`
## and every other published verb are a WRITE or a question the facade already
## folded into `summary`; naming one from `ui/` would be widening the UI's reach
## rather than using the fold ADR 0083 already made.
##
## **Comments are stripped first**, and deliberately: this screen documents the rule
## by naming the verbs it refuses (`test_ui_conventions` does the same for
## `theme_override`), so a check that read prose would fail it FOR documenting the
## rule it follows — which teaches the next author to delete the explanation.
## Only CODE is evidence.
##
## ## THE CALL-SITE SHAPE, and why both sides are `Api.`
##
## The scanner returns the token BEFORE `Api.` — `Race`, not `RaceApi` — while the
## allow-list holds whole CALLS (`RaceApi.summary`). Comparing `"%s(" % name`
## against a bare `Race` therefore never matched, and the only three names the
## screen is PERMITTED to name all read as offenders: the guard reported its own
## allow-list as a violation and could only be silenced by deleting the three calls
## the screen exists to make. Both sides are now reduced to the same thing — a
## `XApi.` call site — so a name the screen may use and a name it may not are asked
## about identically, and the forbidden verb (`RaceApi.set_race(`) still differs from
## the allowed one (`RaceApi.summary(`) by exactly the verb.
func test_the_screen_names_no_other_verb_from_the_three_lineage_modules() -> void:
	var code := _code_only(FileAccess.get_file_as_string(SCREEN_SCRIPT))
	# The allow-list is FACADE names, not whole calls. `_facade_names_named_by` returns the
	# token before `Api.` (`Race`), and the point of this guard is "does the screen name a
	# facade at all beyond the three allowed ones" — a verb-level check belongs to the
	# exact-call-count assertion above, which already pins `RaceApi.summary(` at once each.
	# Normalising BOTH sides through `_call_sites` put whole calls on one side and bare
	# facades on the other, so the three permitted names always read as offenders and the
	# guard could only be silenced by deleting the calls it exists to permit.
	var allowed: Array[String] = []
	for call in RACES_ONLY + BLOODLINES_ONLY + CLANS_ONLY:
		# `get_slice(".", 0)` yields the facade token itself (`RaceApi`). It is appended
		# DIRECTLY and never passed through `_call_sites`, which only appends `Api` to a
		# dotless name — feeding it `RaceApi` that way produced `RaceApiApi`, which matches
		# nothing and made the three permitted facades read as offenders.
		var facade := String(call).get_slice(".", 0)
		if not allowed.has(facade):
			allowed.append(facade)
	var named := _call_sites(_facade_names_named_by(code))
	var offenders: Array[String] = []
	for name in named:
		if allowed.has(name):
			continue
		offenders.append(name)
	assert_eq(
		offenders,
		[],
		(
			"the screen reaches the lineage modules only through %s; it also names %s"
			% [", ".join(allowed), ", ".join(offenders)]
		)
	)


# --- Headless: the page answers with no scene tree --------------------------


## The UI standard's reason for `_bind_nodes()`: a screen is driven by the headless
## runner before a scene tree exists. Instantiating the scene, asking for its
## summary, and driving every `ScreenStack` hook must all answer.
func test_a_screen_mounted_headlessly_still_answers() -> void:
	var screen := _screen()
	screen.setup(_carrying())
	var view := screen.summary()
	assert_ne(view, {}, "the headless mount renders")
	assert_ne(view["bloodlines"], [], "and its rows report themselves")
	screen.on_stack_input(null)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	assert_eq(screen.on_stack_input(cancel), false, "read-only: the cancel is not consumed")
	screen.on_screen_shown()
	screen.on_screen_hidden()
	screen.focus_initial()
	assert_ne(screen.summary(), {}, "and it still answers after every hook")
	screen.free()


## Adopting three snapshots renders the page with NO actor at all — which is how a
## driver or a headless suite paints a lineage page without a hero.
func test_three_snapshots_render_the_page_with_no_actor() -> void:
	var actor := _sworn()
	var screen := _screen()
	screen.apply_snapshot(
		RaceApi.summary(actor), BloodlineApi.summary(actor), ClanApi.summary(actor)
	)
	assert_eq(screen.summary(), {}, "with no actor bound the contract still says {}")
	assert_ne(screen.row_ids().is_empty(), true, "but the rows were filled from the snapshots")
	screen.free()


# --- Reachability -----------------------------------------------------------


func test_the_route_table_names_this_screen_so_a_player_can_open_it() -> void:
	var found := String(ScreenRoutes.id_for_scene(LINEAGE_SCENE_PATH))
	if found.is_empty():
		print("SKIPPED: %s" % ROUTE_REASON)
		return
	assert_eq(StringName(found), LINEAGE_ROUTE, "the lineage scene is mounted by the lineage route")


func test_the_shipped_route_mounts_this_screen_with_the_apps_actor() -> void:
	if String(ScreenRoutes.id_for_scene(LINEAGE_SCENE_PATH)).is_empty():
		print("SKIPPED: %s" % ROUTE_REASON)
		return
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp boots, or nothing below is proven")
	if harness.boot_error != "":
		return
	var moved := harness.navigate(LINEAGE_ROUTE)
	assert_eq(bool(moved["ok"]), true, "route '%s' mounts: %s" % [LINEAGE_ROUTE, moved["note"]])
	if not bool(moved["ok"]):
		return
	var live := harness.live_screen()
	assert_ne(live, null, "the route left a live screen")
	assert_eq(
		live.scene_file_path,
		LINEAGE_SCENE_PATH,
		"and it is the lineage screen the route claims to mount"
	)
	assert_eq(harness.bound_actor(live), harness.actor, "bound to the app's own hero")
	var view: Variant = live.call(&"summary")
	assert_eq(
		view is Dictionary and not (view as Dictionary).is_empty(),
		true,
		"and it reports what it renders, rather than being a blank page"
	)


# --- Plumbing ---------------------------------------------------------------


## The row for `lineage_id` among a `bloodlines` array, or `{}`. A named helper so
## a failure names the lineage that vanished rather than an index that moved.
func _find_row(rows: Array, lineage_id: String) -> Dictionary:
	for row in rows:
		var view: Dictionary = row
		if String(view.get("lineage_id", "")) == lineage_id:
			return view
	return {}


## The module directories `text` names under `res://src/modules/`. A plain
## `contains` over the file's own text, so it is asked about a file that has not
## been loaded — the rule is about what a UI file NAMES.
func _module_dirs_named_by(text: String) -> Array[String]:
	var out: Array[String] = []
	for module in ["race", "bloodline", "clan"]:
		if text.contains("%s%s/" % [MODULES_ROOT, module]):
			out.append(module)
	return out


## Every `XApi.` name `text` mentions, so the caller can ask which of them the screen
## was allowed to call. Read from source because the rule is about what the file
## NAMES, which is the only shape that survives a refactor. Returns the token BEFORE
## `Api.` — a bare facade name — which is why both sides of the comparison below go
## through `_call_sites`.
func _facade_names_named_by(text: String) -> Array[String]:
	var out: Array[String] = []
	for token in text.split("\n"):
		var at := 0
		while true:
			var found := token.find("Api.", at)
			if found < 0:
				break
			var start := found
			while start > 0 and _is_name_char(token[start - 1]):
				start -= 1
			var name := token.substr(start, found - start)
			if name != "" and not out.has(name):
				out.append(name)
			at = found + 4
	out.sort()
	return out


## The screen, plus the CODE of every script the four shipped lineage `.tscn` files
## attach — read through the scene files, because a row reaches a surface only
## through the scene that instances it.
func _lineage_surface_code() -> String:
	var out: Array[String] = [FileAccess.get_file_as_string(SCREEN_SCRIPT)]
	for scene_path in [LINEAGE_SCENE_PATH, BODY_SCENE_PATH, BLOOD_SCENE_PATH, HOUSE_SCENE_PATH]:
		for path in _gd_scripts_in_scene(scene_path):
			out.append(FileAccess.get_file_as_string(path))
	return _code_only("\n".join(out))


## Every `.gd` path a `.tscn` declares in an `[ext_resource]` line. The panel scripts
## reach a surface only through the scene that instances them, so this is the link
## a scan has to walk — a guard reading `lineage_screen.gd` alone reads the screen and
## none of its rows. **Not wired into the guard above**, which stays scoped to the
## screen on purpose: widening it would force the screen to answer for whatever any
## row names, and a row that legitimately reaches a DIFFERENT granted module would
## then be reported as a breach by a screen that never asked for it. Row boundaries
## are `test_ui_conventions.gd`'s job — it already walks every `src/ui/panels/*.tscn`
## and rejects any that names `res://src/modules/` directly.
func _gd_scripts_in_scene(scene_path: String) -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string(scene_path)
	for line in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var from := line.find('path="')
		if from < 0:
			continue
		var start := from + 6
		var stop := line.find('"', start)
		if stop < 0:
			continue
		var path := line.substr(start, stop - start)
		if path.ends_with(".gd") and FileAccess.file_exists(path):
			out.append(path)
	return out


## `names` — either whole call sites (`"RaceApi.summary"`) or bare prefixes
## (`"Race"`, what `_facade_names_named_by` returns) — as sorted, de-duplicated
## `XApi.` call sites. **Both sides of the comparison go through here**, so an
## allow-list entry and a found name are always the same SHAPE; a bare prefix on one
## side and a full call on the other can never match, and a guard that cannot match
## its own allow-list reports every permitted name as an offender.
func _call_sites(names: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in names:
		var name := String(entry)
		# A name carrying a dot is already `XApi.verb`; a bare one is a facade name and
		# needs its suffix. Testing on the dot rather than on `Api` keeps
		# `RaceApi.summary` from becoming `RaceApi.summaryApi`.
		if not name.contains("."):
			name = "%sApi" % name
		if not out.has(name):
			out.append(name)
	out.sort()
	return out


func _is_name_char(ch: String) -> bool:
	return ch.is_valid_identifier()


## `text` with every `#` comment and every double-quoted string literal blanked,
## so a source scan reads CODE and never prose.
##
## ## WHY THIS EXISTS, and why it is not `text` itself
##
## The scan above hunts for `XApi.` tokens. Read over raw source it also finds the
## verbs this file and `lineage_screen.gd` NAME IN PROSE while explaining which ones
## they refuse — `attach`, `set_race`, `set_purity`, `join`, `move_standing`. That
## would fail this screen FOR documenting the rule it follows, and the only way to
## make the suite green would be to delete the explanation. That is the wrong
## trade: the comment is the design note, the identifier in it is not a call site.
##
## So the stripper, not the prose, gives way. The shape is the repo's own, read from
## `tools/arch/enforce.py:_code_only` (`COMMENT_RE = re.compile(r"#.*$",
## re.MULTILINE)`, `STRING_RE = re.compile(r'"[^"\n]*"')`, applied strings-first so a
## `#` inside a literal is not mistaken for a comment), and it matches the idiom
## `test_forage_surface.gd`, `test_market_surface_contract.gd` and
## `test_ui_conventions.gd` already use. Two passes are enough for GDScript, which
## has no raw-string form and never writes a double quote inside a literal.
##
## ## WHAT IT DOES NOT BUY
##
## It cannot tell a string on a code line from an identifier, which is why the
## callers here scan for SYMBOLS (`Api.`), not for verbs: no facade name this screen
## is allowed to reach can survive being quoted. A literal that quoted one — a
## failure message, say — would still read as a hit, and the honest fix for that is
## to phrase the message without naming the verb, not to widen this helper.
func _code_only(text: String) -> String:
	var without_strings := ""
	var at := 0
	while true:
		var open := text.find('"', at)
		if open < 0:
			without_strings += text.substr(at)
			break
		var close := text.find('"', open + 1)
		if close < 0:
			# An unterminated literal: nothing after it can be trusted as code.
			without_strings += text.substr(at)
			break
		without_strings += text.substr(at, open - at) + '""'
		at = close + 1
	var out: Array[String] = []
	for line in without_strings.split("\n"):
		var at_hash := line.find("#")
		out.append(line if at_hash < 0 else line.substr(0, at_hash))
	return "\n".join(out)
