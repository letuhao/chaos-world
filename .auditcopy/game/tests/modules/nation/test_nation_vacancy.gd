extends TestCase

## ADR 0083's three-state vocabulary, on the tier whose whole point is a vacancy.
##
##   - `{}` — **this does not exist.** A spare row in a pool. Hidden.
##   - `"vacant": true` — **this EXISTS and its value is absent.** An authored seat
##     nobody holds. **Visible**, `is_filled() == true`, its own tone.
##   - `{"ok": false, "reason": R}` — **this action exists and is refused.**
##
## A vacancy is never `0`, never `"-"`, never a hidden row. These cases assert each
## state SEPARATELY and then assert that the second and the first cannot be confused
## with one another, because a board that renders an unfilled office as a spare row
## has destroyed the succession design.

## Loaded once: two `load()` calls for one scene is a second source of truth about
## which scene this suite drives.
const NATION_SCREEN := preload("res://src/ui/screens/nation_screen.tscn")

const MARCH := &"march_of_the_nine_provinces"


func _actor() -> Actor:
	var actor := Actor.new(&"polity_a", {Stat.PHYSIQUE: 10.0})
	NationApi.attach(actor)
	NationApi.found(actor, MARCH, "polity_a")
	return actor


func _row() -> NationOfficeRow:
	var packed := load("res://src/ui/panels/nation_office_row.tscn") as PackedScene
	return packed.instantiate() as NationOfficeRow


func test_a_polity_authors_at_least_one_vacant_seat_and_it_stays_vacant() -> void:
	var actor := _actor()
	var summary := NationApi.summary(actor)
	var offices: Dictionary = summary["offices"]
	assert_eq(int(summary["vacant_offices"]) >= 1, true, "the board authors a vacancy")
	var vacant := 0
	for office_id in offices.keys():
		var office: Dictionary = offices[office_id]
		if bool(office.get("vacant", false)):
			vacant += 1
			assert_eq(String(office.get("holder_id", "")), "", "%s holds nobody" % office_id)
	assert_eq(vacant, int(summary["vacant_offices"]), "the count matches the rows")


func test_a_vacant_office_is_a_row_with_vacant_true_not_a_zero_or_a_dash() -> void:
	var offices: Dictionary = NationApi.summary(_actor())["offices"]
	var found := false
	for office_id in offices.keys():
		var office: Dictionary = offices[office_id]
		if not bool(office.get("vacant", false)):
			continue
		found = true
		assert_eq(office.has("vacant"), true, "%s states its own existence" % office_id)
		assert_eq(bool(office["vacant"]), true, "%s is vacant" % office_id)
		assert_eq(String(office["holder_id"]), "", "and its holder is absent, not 0 or '-'")
		# The refusal shape is a THIRD state and must not appear on a row.
		assert_eq(office.has("ok"), false, "a row is not a refusal")
		assert_eq(office.has("reason"), false, "and carries no reason: nothing was refused")
	assert_eq(found, true, "at least one vacant seat exists to assert on")


func test_every_authored_office_is_present_whether_filled_or_not() -> void:
	# A board that dropped a seat nobody holds would read as a polity with fewer
	# offices than it authors — the exact failure the vacancy exists to prevent.
	var actor := _actor()
	var authored := NationCatalog.instance().nation_definition(MARCH).office_ids()
	var offices: Dictionary = NationApi.summary(actor)["offices"]
	assert_eq(offices.size(), authored.size(), "one row per authored seat")
	for office_id in authored:
		assert_eq(
			offices.has(String(office_id)), true, "%s is a row whatever its state" % office_id
		)


func test_a_vacant_office_renders_visible_and_a_spare_row_renders_nothing() -> void:
	# THE distinction the succession design depends on, asserted on the panel rather
	# than on pixels. Same widget, two inputs, two visibly different outcomes.
	var row := _row()
	(
		row
		. show_office(
			{
				"office_id": "seat_of_the_star",
				"display_name": "Seat of the Star",
				"succession_method": "trial",
				"capacity": 1,
				"vacant": true,
				"holder_id": "",
				"powers": ["levy"],
			}
		)
	)
	assert_eq(row.is_filled(), true, "a vacant seat EXISTS, so the row is filled")
	assert_eq(row.is_vacant(), true, "and is explicitly vacant")
	assert_eq(row.visible, true, "a vacancy is a VISIBLE row, never hidden")
	var view := row.summary()
	assert_ne(view, {}, "a vacant seat has a summary: it exists")
	assert_eq(bool(view["vacant"]), true, "the summary states the vacancy")
	assert_eq(String(view["holder_line"]), "Vacant", "and says so in words, not a dash")
	assert_ne(String(view["card_tone"]), "", "and it carries its own card tone")

	# The same row, given `{}` — the first state. It must render nothing at all.
	row.show_office({})
	assert_eq(row.is_filled(), false, "a spare pool row does not exist")
	assert_eq(row.is_vacant(), false, "and is not a vacancy")
	assert_eq(row.summary(), {}, "so it reports nothing, not a shaped row with blanks")
	assert_eq(row.visible, false, "and it takes no space")


func test_a_vacant_seat_and_a_spare_row_cannot_be_told_apart_by_accident() -> void:
	# The negative form, because the failure this guards against is the two states
	# COLLAPSING. If they ever shared a card tone, a summary shape or a visibility
	# rule, this fails even though both individual cases above would still pass.
	var row := _row()
	row.show_office({"office_id": "seat", "display_name": "Seat", "vacant": true, "holder_id": ""})
	var vacant_summary: Dictionary = row.summary()
	var vacant_card := String(vacant_summary["card_tone"])
	var vacant_visible := row.visible
	row.show_office({})
	var spare_summary: Dictionary = row.summary()
	assert_ne(vacant_summary, spare_summary, "the two states report different things")
	assert_ne(vacant_card, "StanceCard", "a vacancy never falls back to a neutral card")
	assert_eq(row.visible, false, "and the spare row is hidden while the vacancy was not")
	assert_eq(vacant_visible, true, "the vacancy was visible")


func test_a_filled_office_is_a_third_shape_distinct_from_both() -> void:
	var row := _row()
	(
		row
		. show_office(
			{
				"office_id": "seat",
				"display_name": "Seat",
				"succession_method": "heir",
				"capacity": 1,
				"vacant": false,
				"holder_id": "marshal_jo",
				"powers": [],
			}
		)
	)
	var filled := row.summary()
	assert_eq(bool(filled["vacant"]), false, "a filled seat is not vacant")
	assert_eq(bool(filled["held"]), true, "and is held")
	assert_eq(String(filled["holder_line"]), "Held by marshal_jo", "naming its holder")
	assert_ne(
		String(filled["card_tone"]),
		"VacantSeatCard",
		"a filled seat never paints itself with the vacancy card"
	)


func test_the_screen_renders_every_vacant_seat_rather_than_omitting_it() -> void:
	# The screen is where the distinction has to survive, because that is where a
	# player looks. `offices` counts seats, vacancies included, and the vacant ones
	# are listed by id so a caller can name them without counting.
	var screen := (NATION_SCREEN as PackedScene).instantiate()
	screen.setup(_actor())
	var view: Dictionary = screen.summary()
	var offices: Array = view["offices"]
	var vacant_ids: Array = view["vacant_office_ids"]
	assert_eq(int(view["vacant_offices"]) >= 1, true, "the screen counts a vacancy")
	assert_eq(vacant_ids.size(), int(view["vacant_offices"]), "and names each one")
	assert_eq(int(view["office_count"]), offices.size(), "offices counts seats, not rows")
	for office in offices:
		assert_eq((office as Dictionary).has("vacant"), true, "each row states its own state")
	assert_eq(int(view["filled_offices"]) >= 1, true, "and some seats are filled")
	screen.free()


func test_the_screen_summary_is_empty_without_an_actor() -> void:
	# ADR 0083's vocabulary needs a `{}` to be reachable, and a screen that reports
	# keys with no actor would make `{}` unreadable as a state at all.
	var screen := (NATION_SCREEN as PackedScene).instantiate()
	assert_eq(screen.summary(), {}, "empty with no actor, not partial")
	screen.free()


func test_the_ledger_survives_a_json_round_trip() -> void:
	# ADR 0083's disclosed gap: `Actor.to_dict` converts only the OUTER
	# `module_data` key, so a StringName key or a Resource anywhere inside the ledger
	# reaches the save untouched and silently breaks every save.
	var actor := _actor()
	NationApi.set_stance(actor, &"court_of_the_star", &"allied")
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(actor.to_dict()))
	assert_ne(round_tripped, null, "the payload is JSON-safe and round-trips")
	var restored: Dictionary = (round_tripped as Dictionary)["module_data"][String(
		NationState.MODULE_KEY
	)]
	assert_eq(
		restored["stances"].size(),
		1,
		"the stance survived with a String key rather than a StringName one"
	)
	var reread := Actor.from_dict(round_tripped as Dictionary)
	NationApi.attach(reread)
	assert_eq(
		(NationApi.state(reread)["stances"] as Dictionary).size(),
		1,
		"and the restored ledger still reads as one row"
	)
