extends TestCase

## DEF-0183 as CODE: a committed arrival is a body standing in a PLACE, and the place is what
## the event module is told about.
##
## ## Why this file exists and cannot heal itself
##
## The audit's chain was one dead link and every other symptom was downstream of it:
##
##   `item_workbench_app.gd:198` installs `WorldStage.set_location_publisher` --
##   but NOTHING in `res://src` ever constructed a `WorldStage`, so the publisher was
##   never FIRED. `event/api.gd:87` then read `ledger["location_id"]` == `EventApi.NOWHERE`
##   (`""`), and `event/api.gd:93` filtered out every one of the eight authored events,
##   each of which carries a non-empty `location_id`. Event opens never reached, stages
##   never advanced, prizes were never paid -- three vacuous ladders, one missing line.
##
## ## The anti-pattern this suite is built to avoid
##
## `tests/ui/test_quest_screen.gd:271-278` constructs its OWN `QuestProgram` and binds the
## seam itself. That suite stays green if the composition root's entire quest contribution is
## deleted, because it re-creates the very thing under test. So:
##
##   - The program is read OUT of the mounted root, out of the commit callable the live
##     arrival screen was bound with. Never `CharacterCreationProgram.new()`.
##   - The commit is driven through the screen's own `act_commit`, which is what the row
##     button a player presses calls.
##   - `EventApi.set_location` is NEVER called from here. If the composition root did not
##     publish, nothing publishes, and the second assertion below goes red. That is the
##     whole design: the only thing between the mount and a non-empty `available()` is
##     production wiring.
##
## `EventApi.available` is still genuinely empty for a body that has never moved a period,
## because every authored trigger also waits on a world fact. So this suite advances the
## world's OWN clock — `advance_world`, the production verb behind the world-map button's
## "wait a season" -- to let `WorldAmbient` say what the world reached. It does not record a
## fact itself: a test that writes `storm_front_sighted` proves nothing about the world.

const FIRST_ORIGIN := &"the_one_who_stayed"
## Bounded, not a loop. Four periods is `WorldAmbient.ROSTER`'s last row (`sect_war_called`
## at period 4), and `advance_periods` clamps to its own `MAX_PERIODS_PER_PULL`, so this
## cannot run away.
const PERIODS := 4

var _harness: SeamHarness
var _app: ItemWorkbenchApp


func setup() -> void:
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp


func teardown() -> void:
	# `WorldStage`'s mounted stage and body are PROCESS-WIDE statics, so a mount this suite
	# made and did not leave would publish a freed `PlayerAdapter` to every suite after it.
	if WorldStage.instance() != null:
		WorldStage.instance().leave()
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null


# --- The preconditions --------------------------------------------------------


func test_the_harness_mounted_a_booted_app() -> void:
	assert_eq(String(_harness.boot_error), "", "the shell booted")
	assert_ne(_app, null, "there is a composition root")


func test_the_root_installed_the_location_publisher_the_mount_has_to_fire() -> void:
	# Half the chain, asserted on its own so a RED below names WHICH end broke. This is the
	# line `item_workbench_app.gd:198` owns, and it was installed-but-unfired.
	assert_eq(WorldStage.has_location_publisher(), true, "the event module has a publisher")


func test_a_boot_without_a_commitment_mounts_no_body() -> void:
	# The control: a player who never answered is not standing anywhere, and that is the
	# state the defect shipped in. Without this, "non-empty available()" could be read as
	# something the BOOT does rather than something the ARRIVAL does.
	assert_eq(WorldStage.instance(), null, "nothing is mounted before the player commits")
	assert_eq(WorldStage.player(), null, "and there is no body for the event module to place")


# --- The link ----------------------------------------------------------------


func test_a_committed_arrival_stands_the_player_in_a_real_place() -> void:
	# The link itself, through the production path: the screen's own `act_commit`, which is
	# what the row button a player presses calls.
	var live := _harness.live_screen()
	assert_ne(live, null, "the arrival screen is live")
	if live == null:
		return
	var outcome: Dictionary = live.call("act_commit", FIRST_ORIGIN)
	assert_eq(
		bool(outcome.get("ok", false)),
		true,
		"the arrival committed: %s" % outcome.get("reason", "")
	)
	# The body exists...
	var body := WorldStage.player()
	assert_ne(body, null, "a PlayerAdapter exists after the commit")
	if body == null:
		return
	# ...it wraps the hero the ROOT plays, not a second body nobody is playing...
	assert_eq(
		String(body.actor().id),
		String(_app.actor().id),
		"and it is the hero the composition root adopted"
	)
	# ...and it stands in an authored location, not in `EventApi.NOWHERE`.
	var here := WorldSpawnApi.current(_app.actor())
	assert_ne(bool(here.get("located", false)), false, "the hero's durable ledger names a place")
	assert_ne(String(here.get("location_id", "")), "", "and that place is not nowhere")


func test_the_mount_told_the_event_module_where_the_player_is() -> void:
	_commit()
	var stage := WorldStage.instance()
	assert_ne(stage, null, "a stage is mounted")
	if stage == null:
		return
	var report := stage.summary()
	assert_eq(
		bool(report.get("world_told", false)),
		true,
		"the world was told: %s" % report.get("world_told_reason", "")
	)
	# The publish is the ONLY writer of this key, and it travels through the installed seam.
	assert_ne(
		String(EventApi.state(_app.actor()).get("location_id", "")),
		"",
		"and the event ledger itself carries the place, not a default"
	)


func test_the_programs_own_summary_reports_the_place() -> void:
	# Read through the composition root's published verb, not a private field: `has_hero()`
	# and `hero()` are the program's opinion of itself and cannot see a mount that never
	# happened (that is the shape of proof that let DEF-0183 ship).
	var summary := _app.creation_summary()
	assert_eq(bool(summary.get("in_the_world", false)), true, "the program reports a mounted body")
	assert_ne(String(summary.get("location_id", "")), "", "and names the place it stands in")


## CREATION IS UNCHANGED BY THE RESTORE FIX (ADR 0192). A committed arrival still stands in
## the place the CREATION program DREW, on the creation program's OWN stage — not on a
## restore stage reading a save it never had. This is the one assertion that goes red if
## someone "unifies" the two paths and hands a new hero the read-the-save behaviour: a
## freshly created actor carries no `world_spawn_state`, so a read-first mount would refuse
## it `not_located` and the arrival would report itself unmounted.
func test_the_creation_path_still_stands_the_hero_on_its_own_drawn_stage() -> void:
	_commit()
	var stage := WorldStage.instance()
	assert_ne(stage, null, "the commit mounted a stage")
	if stage == null:
		return
	var summary := _app.creation_summary()
	assert_eq(
		String(stage.summary().get("location_id", "")),
		String(summary.get("location_id", "")),
		"the mounted stage IS the creation program's own, still holding its drawn place"
	)
	assert_eq(
		String(WorldSpawnApi.current(_app.actor()).get("source", "")),
		WorldSpawnApi.SOURCE_RANDOM,
		"and creation still DRAWS: a new hero is placed, not resumed from a save"
	)


# --- The event half. THIS is the assertion that proves the chain came alive -----


func test_events_available_at_the_mounted_location_are_not_empty() -> void:
	_commit()
	# Let the WORLD say what it reached, through its own clock. No fact is written here: the
	# authored triggers wait on `storm_front_sighted` and friends, and `WorldAmbient` is the
	# production owner of those. A test that recorded them itself would prove nothing.
	_app.advance_world(PERIODS)
	var hero := _app.actor()
	var located := String(WorldSpawnApi.current(hero).get("location_id", ""))
	assert_ne(
		located, "", "the hero is somewhere real, so the location filter has a value to compare"
	)
	# The authored catalog itself, so a RED below says WHICH end broke rather than only that
	# something did: the location the draw landed in, and every place an event is authored for.
	var where: Array[String] = []
	for event_id in EventApi.catalog().get("events", {}) as Dictionary:
		var row := EventApi.catalog()["events"][event_id] as Dictionary
		var at := String(row.get("location_id", ""))
		if not at.is_empty() and not where.has(at):
			where.append(at)
	assert_eq(
		where.has(located),
		true,
		"an authored event names the place this hero was drawn into: %s of %s" % [located, where]
	)
	var here := EventApi.available(hero, located)
	assert_ne(here.size(), 0, "EventApi.available is NON-EMPTY at %s: %s" % [located, _ids(here)])
	# And at that same place, every row really is an event authored FOR it -- not a widened
	# filter returning something the location rule should have excluded.
	for row in here:
		assert_eq(
			String(row.get("location_id", "")),
			located,
			"an available event is authored for the place the player stands in"
		)


func test_the_same_read_at_a_place_nobody_stands_in_is_empty() -> void:
	# The other half of the proof: the assertion above is only meaningful because the
	# location filter is real. Asked for a location no authored event names, the same module
	# on the same hero answers empty -- so a non-empty answer above is the MOUNT talking and
	# not the gate being permissive.
	_commit()
	var elsewhere := EventApi.available(_app.actor(), &"a_location_no_tres_defines")
	assert_eq(elsewhere.size(), 0, "an unknown place offers nothing, so the filter is doing work")


# --- Internals ----------------------------------------------------------------


## Commit through the mounted screen. Never a program this suite constructed: that is the
## self-healing mistake this file is written against.
func _commit() -> Dictionary:
	var live := _harness.live_screen()
	if live == null:
		return {"ok": false, "reason": "no_screen"}
	return live.call("act_commit", FIRST_ORIGIN) as Dictionary


func _ids(rows: Array[Dictionary]) -> String:
	var out: Array[String] = []
	for row in rows:
		out.append(String(row.get("event_id", "")))
	return ", ".join(out)
