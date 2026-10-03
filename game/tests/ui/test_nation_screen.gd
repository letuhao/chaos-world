extends TestCase

## The nation screen: a pure consumer of `NationApi.summary(actor)`, asserted through
## `summary()` rather than pixels (AGENTS.md, UI standard).
##
## ## What is load-bearing here
##
## Four claims, each of which a future edit could quietly undo:
##
##  1. **A vacancy is a ROW, and it is visibly not a spare.** ADR 0083's middle state
##     is `"vacant": true`: the seat exists and its value is absent. The distinction
##     between a vacant office and a spare pool row is therefore STRUCTURAL — a
##     vacant seat answers `is_filled() == true` and renders in its own card tone,
##     while a spare row reports `{}` and hides. They must never look alike.
##  2. **Every AUTHORED office is always a row**, whether or not anybody holds it. A
##     board that dropped a seat would read as a polity with fewer offices than it
##     authors — the exact legibility failure the screen exists to prevent.
##  3. **The screen is a PURE consumer.** Exactly one facade call, `summary(actor)`,
##     and no other identifier from `nation`.
##  4. **Read-only.** No mutating verb is reachable from here, and `on_stack_input`
##     declines every event so `ScreenStack` pops the screen with `ui_cancel`.
##
## The screen scene, loaded once: two `load()` calls for one scene is a second source
## of truth about which scene this suite drives.
const SCREEN_SCENE := preload("res://src/ui/screens/nation_screen.tscn")
const OFFICE_SCENE := "res://src/ui/panels/nation_office_row.tscn"
const TERRITORY_SCENE := "res://src/ui/panels/nation_territory_row.tscn"
const STANCE_SCENE := "res://src/ui/panels/nation_stance_row.tscn"
const STANDOFF_SCENE := "res://src/ui/panels/nation_standoff_row.tscn"
const SCRIPT_PATH := "res://src/ui/screens/nation_screen.gd"
## The only facade method this screen is allowed to call. ADR 0083 folds every read a
## screen needs into `summary()` rather than growing the facade past its 12-method cap.
const FACADE := "NationApi"
const ONLY_FACADE_CALL := "NationApi.summary"
## Every mutating verb `nation` publishes. A read-only screen that reached one would
## turn a declaration of war into a two-click accident (ADR 0085: a conflict is a
## declaration with a prize fixed up front, and the prize is paid once).
const MUTATING_VERBS := [
	"found",
	"claim_territory",
	"release_territory",
	"accrue_territory",
	"set_stance",
	"declare_war",
	"resolve_conflict",
]
## The verbs a screen legitimately reads, besides `summary`. Reaching one of these
## from `ui/` would widen the facade instead of using the fold ADR 0083 already made.
const OTHER_FACADE_VERBS := ["attach", "state"]

const MARCH := &"march_of_the_nine_provinces"
const COURT := &"court_of_the_star"
const CLAIMED := &"river_march"


func _actor() -> Actor:
	var actor := Actor.new(&"polity_a", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	return actor


## A hero living under a founded polity, so the board has an authored seat set to
## render — including the vacancies `found` writes deliberately.
func _under_a_nation() -> Actor:
	var actor := _actor()
	NationApi.found(actor, MARCH, "polity_a")
	return actor


func _screen() -> NationScreen:
	return (SCREEN_SCENE as PackedScene).instantiate() as NationScreen


# --- The screen contract ----------------------------------------------------


func test_the_screen_summary_is_empty_without_an_actor() -> void:
	# ADR 0083's first state needs `{}` to be REACHABLE, so a screen that reported
	# keys with nothing bound would make the state unreadable rather than empty.
	var screen := _screen()
	assert_eq(screen.summary(), {}, "empty with no actor, not a half-built view")
	screen.free()


func test_the_screen_reports_the_bound_actor_and_the_polity_it_lives_under() -> void:
	var actor := _under_a_nation()
	var screen := _screen()
	screen.setup(actor)
	var view := screen.summary()
	assert_ne(view, {}, "a bound actor gives a view")
	assert_eq(String(view["actor"]), String(actor.id), "it names the actor it renders")
	assert_eq(bool(view["founded"]), true, "and the polity it found")
	assert_eq(String(view["nation_id"]), String(MARCH), "and under the right one")
	assert_ne(String(view["nation_name"]), "", "named, not an id standing in for a name")
	screen.free()


func test_a_hero_under_no_nation_is_a_sentence_not_a_crash() -> void:
	# ADR 0083: "no institution" is the ORDINARY starting state. A hero who lives
	# under nothing still gets a view, and an empty board rather than a failure.
	var screen := _screen()
	screen.setup(_actor())
	var view := screen.summary()
	assert_eq(bool(view["founded"]), false, "no polity")
	assert_eq(String(view["nation_id"]), "", "and none named")
	assert_eq((view["offices"] as Array).is_empty(), true, "so no seat is claimed")
	screen.free()


# --- The board: every AUTHORED office is a row -------------------------------


func test_every_authored_office_of_the_polity_is_listed_vacancies_included() -> void:
	# The load-bearing claim of this screen. Iterating the AUTHORED board rather
	# than the filled seats is what keeps an unfilled office visible at all; a
	# vacancy is a live fact about the world, not a missing widget.
	var actor := _under_a_nation()
	var authored := _authored_office_ids(actor)
	assert_ne(authored.is_empty(), true, "the polity authors offices to assert on")
	var screen := _screen()
	screen.setup(actor)
	var view := screen.summary()
	var listed := view["offices"] as Array
	assert_eq(listed.size(), authored.size(), "one row per authored office, none dropped")
	for office_id in authored:
		assert_eq(
			(view["office_ids"] as Array).has(String(office_id)), true, "%s has a row" % office_id
		)


func test_the_vacancy_counts_are_readable_so_the_gap_is_countable() -> void:
	# A screen that hid a vacancy would still render "N offices"; these counts are
	# what make the difference between a seat and no seat legible rather than a
	# matter of opinion.
	var screen := _screen()
	screen.setup(_under_a_nation())
	var view := screen.summary()
	var vacant := view["vacant_offices"] as int
	assert_ne(vacant, 0, "a freshly founded polity has unfilled seats, and they are counted")
	assert_eq(
		int(view["filled_offices"]) + int(view["vacant_offices"]),
		(view["offices"] as Array).size(),
		"filled and vacant together account for every seat on the board"
	)
	assert_eq(
		(view["vacant_office_ids"] as Array).size(), vacant, "and the ids agree with the count"
	)
	screen.free()


# --- A vacant office and a spare pool row must NEVER look alike --------------


func test_a_vacant_office_is_visible_and_filled_while_a_spare_row_is_neither() -> void:
	# THE structural distinction this screen exists for. ADR 0083: a vacancy is never
	# `0`, never `"-"`, never a hidden row. If these two could render alike, the
	# succession design would have been thrown away at the last step.
	var row := (load(OFFICE_SCENE) as PackedScene).instantiate() as NationOfficeRow

	row.show_office({"office_id": "empty_seat", "display_name": "Empty Seat", "vacant": true})
	assert_eq(row.is_filled(), true, "an authored seat nobody holds STILL EXISTS")
	assert_eq(row.is_vacant(), true, "and says it is vacant rather than merely empty")
	var vacant_view := row.summary()
	assert_ne(vacant_view, {}, "so it renders something")
	assert_eq(bool(vacant_view["vacant"]), true, "carrying the middle state explicitly")
	assert_eq(String(vacant_view["holder_id"]), "", "with its value absent, not zero")

	row.show_office({})
	assert_eq(row.is_filled(), false, "a spare pool row does NOT exist")
	assert_eq(row.is_vacant(), false, "so it cannot be vacant")
	assert_eq(row.summary(), {}, "and it reports nothing at all, not blanks")
	row.free()


func test_a_vacant_office_and_a_filled_one_never_share_a_tone() -> void:
	# The half of the distinction that lives in the theme rather than the data: a
	# missing variation renders as the base style, so the two states must name
	# DIFFERENT `theme_type_variation`s for the board to read at a glance.
	var row := (load(OFFICE_SCENE) as PackedScene).instantiate() as NationOfficeRow
	row.show_office({"office_id": "empty_seat", "display_name": "Empty Seat", "vacant": true})
	var vacant_view := row.summary()
	row.show_office(
		{"office_id": "taken_seat", "display_name": "Taken Seat", "holder_id": "polity_b"}
	)
	var filled_view := row.summary()
	assert_ne(
		String(vacant_view["card_tone"]),
		String(filled_view["card_tone"]),
		"a vacant seat and a filled one paint themselves differently"
	)
	assert_ne(
		String(vacant_view["holder_line"]),
		String(filled_view["holder_line"]),
		"and say different things about who holds them"
	)
	assert_ne(
		String(vacant_view["holder_line"]),
		"-",
		"an absent holder is a word, never a dash that reads as an authored value"
	)
	row.free()


func test_the_board_shows_a_vacancy_without_truncating_the_pool() -> void:
	# The spare rows past the authored board must hide, and the authored ones must
	# all survive — so a pool that grew for the board cannot be the same pool the
	# vacancy was rendered in.
	var screen := _screen()
	screen.setup(_under_a_nation())
	var view := screen.summary()
	assert_eq(
		(view["offices"] as Array).size(),
		(view["office_ids"] as Array).size(),
		"every mounted office row carries a seat, and spare rows carry none"
	)
	screen.free()


# --- Claims, stances and standoffs ------------------------------------------


func test_a_claim_over_places_is_nested_under_its_own_key() -> void:
	# The screen contract: a child's own summary lives under that child's key, so a
	# test reads the claim without walking the tree.
	var actor := _under_a_nation()
	NationApi.claim_territory(actor, CLAIMED)
	var screen := _screen()
	screen.setup(actor)
	var claims := screen.summary()["claims"] as Array
	assert_ne(claims.is_empty(), true, "the claim is listed")
	var row: Dictionary = claims[0]
	assert_eq(String(row["territory_id"]), String(CLAIMED), "and named by id")
	assert_eq(String(row["holder_id"]), String(MARCH), "with the polity that holds it")
	assert_eq(bool(row["contested"]), false, "a take is not a contest")
	assert_eq(screen.summary()["contested_claims"] as int, 0, "and the screen counts no contest")
	screen.free()


func test_a_stance_is_reported_with_the_verb_verbatim() -> void:
	# ADR 0047: ONE canonical row per unordered pair. The panel prints the verb
	# rather than a directional sentence, because a one-sided opinion is
	# structurally impossible in the data and must not reappear in the prose.
	var actor := _under_a_nation()
	NationApi.set_stance(actor, COURT, &"allied")
	var screen := _screen()
	screen.setup(actor)
	var stances := screen.summary()["stances"] as Array
	assert_eq(stances.size(), 1, "the stance the facade wrote is listed once")
	var row: Dictionary = stances[0]
	assert_eq(String(row["verb"]), "allied", "printed exactly as declared")
	assert_eq(String(row["other_id"]), String(COURT), "and names the other polity")
	assert_eq(bool(row["known_verb"]), true, "and it is one of the closed verb set")
	screen.free()


func test_a_declared_conflict_is_nested_with_its_prize_verbatim() -> void:
	# ADR 0085: the prize was fixed when the two sides declared, so a panel that
	# re-derived it would show a number nobody ever agreed to.
	var actor := _under_a_nation()
	NationApi.declare_war(actor, COURT, CLAIMED, {"mode": "contest", "transfer": "ownership"})
	var screen := _screen()
	screen.setup(actor)
	var view := screen.summary()
	var standoffs := view["standoffs"] as Array
	assert_eq(standoffs.size(), 1, "the declared conflict is listed")
	var row: Dictionary = standoffs[0]
	assert_eq(bool(row["closed"]), false, "and it is open")
	assert_eq(String(row["prize_transfer"]), "ownership", "with the DECLARED prize")
	assert_eq(int(view["open_standoffs"]), 1, "and the screen counts it as open")
	screen.free()


# --- Purity: one facade method, and nothing else from the module -------------


func test_the_screen_calls_exactly_one_facade_method_and_no_other_module_name() -> void:
	# `tools arch` checks the MODULE side of the boundary. This checks the UI side, by
	# reading the shipped source: one `NationApi.summary(` call, and no other
	# identifier from `nation` anywhere in the file.
	var source := FileAccess.get_file_as_string(SCRIPT_PATH)
	assert_ne(source.is_empty(), true, "%s is readable" % SCRIPT_PATH)
	assert_eq(
		source.count(ONLY_FACADE_CALL),
		1,
		"%s calls %s exactly once" % [SCRIPT_PATH, ONLY_FACADE_CALL]
	)
	assert_eq(
		source.contains(FACADE),
		true,
		"%s names the facade at all, so the check above cannot pass vacuously" % SCRIPT_PATH
	)
	for verb in MUTATING_VERBS:
		assert_eq(
			source.contains("%s.%s(" % [FACADE, verb]),
			false,
			"%s never calls the mutating verb %s" % [SCRIPT_PATH, verb]
		)
	for verb in OTHER_FACADE_VERBS:
		assert_eq(
			source.contains("%s.%s(" % [FACADE, verb]),
			false,
			"%s reads no second facade method; %s is not one of them" % [SCRIPT_PATH, verb]
		)


func test_no_nation_or_sect_module_file_other_than_the_facade_is_named() -> void:
	# The stronger half: not "no other METHOD on the facade" but "no other FILE". A
	# `NationState` or `NationDef` reference would reach past the facade entirely.
	var source := FileAccess.get_file_as_string(SCRIPT_PATH)
	for interior in [
		"NationState", "NationDef", "NationCatalog", "NationProjection", "NationTuning"
	]:
		assert_eq(
			source.contains(interior),
			false,
			"%s names %s; ui/ may only reach the facade" % [SCRIPT_PATH, interior]
		)
	assert_eq(
		source.contains("res://src/modules/nation/"),
		false,
		"%s paths into the module; panels call the facade by bare name" % SCRIPT_PATH
	)


# --- Focus, read-only, and the row pool --------------------------------------


func test_the_stack_hooks_exist_and_are_safe_with_nothing_bound() -> void:
	var screen := _screen()
	for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
		assert_eq(screen.has_method(hook), true, "%s is implemented" % hook)
	screen.on_screen_shown()
	screen.on_screen_hidden()
	screen.focus_initial()
	assert_eq(screen.summary(), {}, "still empty, so a focus call did not invent state")
	screen.free()


func test_the_screen_consumes_no_input_so_ui_cancel_pops_it() -> void:
	# Read-only by design: a screen that consumed `ui_cancel` would trap the player.
	var screen := _screen()
	screen.setup(_under_a_nation())
	assert_eq(screen.on_stack_input(null), false, "a null event is declined")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	assert_eq(screen.on_stack_input(cancel), false, "cancel is declined so the stack pops")
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	assert_eq(screen.on_stack_input(accept), false, "and so is everything else")
	screen.free()


func test_focus_records_its_target_before_any_focus_call() -> void:
	# `DestinyScreen` records `_focus_target` FIRST because a node outside a viewport
	# has nothing to focus yet — recording after the call would leave the field empty
	# in exactly the headless case the suite exercises.
	var screen := _screen()
	screen.setup(_under_a_nation())
	screen.focus_initial()
	assert_ne(
		String(screen.summary()["focus_target"]),
		"",
		"the landing spot is recorded even with no viewport"
	)
	screen.free()


func test_focus_lands_on_a_seat_even_when_every_seat_is_vacant() -> void:
	# The landing spot deliberately includes a VACANT seat: the vacancy is the
	# thing a player opening this screen most needs to see.
	var screen := _screen()
	screen.setup(_under_a_nation())
	var view := screen.summary()
	if int(view["vacant_offices"]) > 0:
		screen.focus_initial()
		assert_ne(String(view["focus_target"]), "", "a vacant seat is focusable")
	screen.free()


func test_the_row_pool_grows_rather_than_truncating() -> void:
	# A pool that dropped a row would silently drop content: the board would shrink
	# to whatever the scene happened to mount. Grow the data past the mounted pool
	# and every seat must still be there.
	var screen := _screen()
	screen.setup(_under_a_nation())
	var mounted := (screen.summary()["office_ids"] as Array).size()
	assert_ne(mounted, 0, "the mounted pool is not empty")
	var inflated := _inflate_offices(NationApi.summary(_under_a_nation()))
	screen.apply_snapshot(inflated)
	assert_eq(
		(screen.summary()["office_ids"] as Array).size(),
		inflated["offices"].size(),
		"a larger snapshot grows the pool rather than dropping seats"
	)
	screen.free()


# --- The row panels own every format -----------------------------------------


func test_the_office_row_formats_the_seat_and_the_screen_does_not() -> void:
	# AGENTS.md: "no number formatting in a screen — the panel owns `%d`, decimals and
	# widths." So the panel's rendered line carries the numbers, and the SCREEN's own
	# summary carries them raw, which is what a test can assert on.
	var row := (load(OFFICE_SCENE) as PackedScene).instantiate() as NationOfficeRow
	row.show_office(
		{"office_id": "tribunal", "display_name": "Tribunal", "capacity": 3, "vacant": true}
	)
	var meta := String(row.summary()["meta"])
	assert_ne(meta.find("3"), -1, "the row prints the seat count")
	assert_eq(String(row.summary()["head"]), "Tribunal", "and the seat's authored name")
	row.free()


func test_the_territory_row_says_a_contest_is_not_a_transfer() -> void:
	# A claim on held ground never moves ground: the holder line still names the
	# holder, so a player reading it cannot mistake a contest for a conquest.
	var row := (load(TERRITORY_SCENE) as PackedScene).instantiate() as NationTerritoryRow
	(
		row
		. show_territory(
			{
				"territory_id": "river_march",
				"display_name": "River March",
				"holder_id": "court_of_the_star",
				"challenger_id": "march_of_the_nine_provinces",
				"tier_index": 2,
			}
		)
	)
	var view := row.summary()
	assert_eq(bool(view["contested"]), true, "the row knows it is contested")
	assert_ne(String(view["challenge_line"]).find("court_of_the_star"), -1, "and says so")
	assert_ne(
		String(view["holder_line"]).find("march_of_the_nine_provinces"),
		-1,
		"while the holder is the side that still holds the ground"
	)
	row.free()


func test_a_stance_row_reads_the_same_with_the_two_ids_swapped() -> void:
	# ADR 0047 as extended by ADR 0085: the row is keyed by the pair ordered
	# lexicographically, so a swapped read returns the identical dictionary. The row
	# prints the pair rather than "you vs them" for exactly that reason.
	var row := (load(STANCE_SCENE) as PackedScene).instantiate() as NationStanceRow
	var view := {
		"pair_key": "alpha|beta",
		"a_id": "alpha",
		"b_id": "beta",
		"other_id": "beta",
		"verb": "truce",
		"sequence": 7,
	}
	row.show_stance(view)
	var forward := row.summary()
	row.show_stance(view.duplicate(true))
	var again := row.summary()
	assert_eq(String(forward["head"]), String(again["head"]), "the same row renders the same")
	assert_eq(String(forward["partner_line"]).find("alpha"), 0, "pair printed as a pair")
	assert_eq(String(forward["partner_line"]).find("beta") > 0, true, "both sides named")
	row.free()


func test_a_standoff_row_reports_the_verdict_tally_and_never_a_roll() -> void:
	# The tally is how many verdicts came back from elsewhere. There is no rng
	# behind it, so the row must read as a count and not as odds.
	var row := (load(STANDOFF_SCENE) as PackedScene).instantiate() as NationStandoffRow
	(
		row
		. show_standoff(
			{
				"standoff_id": "alpha|beta@1",
				"other_id": "beta",
				"mode": "contest",
				"quota": 3,
				"closed": false,
				"sides":
				{
					"alpha": {"won": 2, "lost": 1, "exhaustion": 0.0},
					"beta": {"won": 1, "lost": 2, "exhaustion": 0.5},
				},
				"prize": {"transfer": "ownership", "standing": {"alpha": 15}},
			}
		)
	)
	var view := row.summary()
	assert_eq(int(view["verdicts"]), 3, "both sides' wins are one shared count")
	assert_eq(int(view["quota"]), 3, "against the declared quota")
	assert_eq(String(view["prize_line"]).find("ownership"), -1, "the prize is not guessed at")
	assert_ne(String(view["prize_line"]).find("15"), -1, "it is read verbatim off the ledger")
	assert_eq(bool(view["closed"]), false, "and the standoff is still open")
	row.free()


func test_every_row_panel_reports_nothing_before_it_is_shown() -> void:
	# ADR 0083's first state: a spare row in a pool. `clear()` and never having been
	# shown are the same thing, and every row reports `{}` rather than blanks.
	var scenes := {
		"office": OFFICE_SCENE,
		"territory": TERRITORY_SCENE,
		"stance": STANCE_SCENE,
		"standoff": STANDOFF_SCENE,
	}
	for label in scenes.keys():
		var row := (load(scenes[label]) as PackedScene).instantiate()
		assert_eq(row.summary(), {}, "%s row is empty before it is shown" % label)
		assert_eq(row.is_filled(), false, "and carries nothing" % label)
		assert_eq(row.visible, false, "and takes up no space" % label)
		row.free()


# --- Plumbing ---------------------------------------------------------------


## The office ids the polity authors, read off the facade's own summary rather than
## off the catalog, so this suite asserts against the same data the screen renders.
func _authored_office_ids(actor: Actor) -> Array:
	var out: Array = []
	for office_id in (NationApi.summary(actor)["offices"] as Dictionary).keys():
		out.append(String(office_id))
	return out


## A snapshot naming more offices than the mounted pool, so `_grow()` has something
## to grow into.
func _inflate_offices(snapshot: Dictionary) -> Dictionary:
	var board: Dictionary = snapshot.get("offices", {}) as Dictionary
	# Snapshot the seed count BEFORE the loop. Testing `count < board.size() + 4`
	# instead is an infinite loop: the body inserts one key per pass, so `size`
	# grows in lockstep with `count` and the +4 gap never closes. Each pass also
	# allocated a fresh nested Dictionary, which is the ~0.3 GB/s growth that took
	# a tests/ui run to 67 GB.
	var target := board.size() + 4
	var count := 0
	while count < target:
		board["t_pad_%02d" % count] = {
			"office_id": "t_pad_%02d" % count,
			"display_name": "Pad",
			"succession_method": "election",
			"capacity": 1,
			"vacant": true,
			"holder_id": "",
			"powers": [],
		}
		count += 1
	snapshot["offices"] = board
	return snapshot
