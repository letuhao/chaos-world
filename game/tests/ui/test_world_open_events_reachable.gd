extends TestCase

## A WORLD EVENT IS A THING A PLAYER CAN NAME, NOT A COUNT (BL-0906).
##
## ## What was measured, and what this file refuses to re-prove
##
## `WorldPulse.available_events()` returned real dictionaries and had ZERO callers;
## `WorldPulse.summary()` collapsed the world's open events to `active_events: int` at
## `world_pulse.gd:546-547`; and the panel's own readout said only
## "live now 1, ready 2". A player could see that the world was busy and could not learn
## WHICH event, WHAT stage it was in, HOW LONG it had held, or WHAT it paid — while those
## events' beats silently drove quest steps and destiny counters.
##
## **Nothing here proves the event module computes correct rows.** `EventReadModel
## .open_rows` and its own suites own that, and re-proving it here would prove arithmetic
## while staying green on a build where no player could see any of it — the false green
## this file is written against.
##
## ## What IS claimed, in order of how badly a failure would hurt
##
##  1. **The PRODUCTION bridge publishes the rows.** Case 5 drives the real
##     `ItemWorkbenchApp` through the real `ScreenStack`, navigates to the world route and
##     reads the live screen's summary — the way a player does. It is RED until
##     `ItemWorkbenchApp._world_bridge` fills the `events` slot.
##  2. **The screen can name an open event.** Not "the screen received a count", but the
##     event's own `display_name` and `stage_name` appearing in what a player reads.
##  3. **An empty world says so.** Three distinct wordings for "nothing open", "seam
##     missing" and "open but unnameable", because `[]` is all three at once on the wire.
##  4. **No `ui/` file reads a module.** The rows arrive through the bridge; a screen that
##     named `EventApi` would make this suite's central claim a lie.
##
## Cases 1–4 need no mounted root except case 5, deliberately: mounting the composition
## root is one parse error away from a peer's in-flight split, and a reachability suite
## that can go red for someone else's typo proves nothing about reachability.

const PANEL_SCENE := "res://src/ui/panels/world_pulse_panel.tscn"
const SCREEN_SCENE := "res://src/ui/screens/world_map_screen.tscn"
const BRIDGE_SOURCE := "res://src/ui/screens/world_pulse_bridge.gd"
const ROOT_SOURCE := "res://src/app/item_workbench_app.gd"
const PULSE_SOURCE := "res://src/app/world_pulse.gd"

## How many one-period waits this suite will press before giving up on an event opening.
## A bound, not a hope: an unbounded loop is the shape `test_no_unbounded_wait.gd` exists
## to refuse, and a test that hangs on a quiet world proves nothing either.
const OPEN_ATTEMPTS := 24

## The row shape `EventReadModel.open_rows` publishes, as the fixture holds one. The KEYS
## are the contract under test: a panel that invented a field would be authoring vocabulary
## the event module does not speak, and a panel that dropped one would be hiding something
## a player can otherwise see.
const ROW_KEYS: Array[String] = [
	"event_id",
	"kind",
	"display_name",
	"location_id",
	"stage_id",
	"stage_name",
	"stage_index",
	"stage_count",
	"opened_period",
	"periods_held",
	"duration_periods",
	"standoff_id",
	"territory_id",
	"is_final_stage",
]

var _born: Array[Node] = []
## The rows the fixture's `events` slot answers with, so an assertion about "what a player
## sees" is a statement about the UI PROGRAM's rendering and not about a pulse's clock.
var _rows: Array[Dictionary] = []
var _events_wired: bool = true
## How many times the slot was read. A screen that cached the roster once at bind time
## would render a stale world, so the read count is itself a claim.
var _reads: int = 0


## The runner builds ONE instance and calls every `test_*` body on it, so the recorders
## above are suite-wide state and survive into the next body. Reset per body rather than
## per body-end, because a body that fails an assertion still returns normally and would
## skip a teardown-only clear.
func setup() -> void:
	super.setup()
	_rows = [_row()]
	_events_wired = true
	_reads = 0


# --- 1. The SEAM advertises and answers the rows -------------------------------


## THE FIRST LINK. `ui/` may reach `app/` only through the bridge (`app` is a
## `PRIVATE_UNIT` in `tools/arch/rules.py`), so an event row that is not a slot here
## cannot reach a screen at all — there is no second way in.
func test_the_bridge_advertises_an_events_read_slot() -> void:
	var bridge := _bridge()
	assert_eq(
		bridge.has_events(),
		true,
		(
			"MISSING SEAM: WorldPulseBridge carries state, advance and retreat but no events "
			+ "read slot, so a world event can reach a player as a COUNT and never as a thing"
		)
	)
	assert_eq(bridge.has(&"state"), true, "and the readout it sits beside is still advertised")
	assert_eq(bridge.has(&"advance"), true, "as is the one-period verb")
	assert_eq(bridge.has(&"retreat"), true, "and the season-scale one")


## A read slot that answers nothing is a line the composition root maintains for nothing.
## Asserted through the production read path, so the test exercises the same method the
## screen calls rather than reaching into the callable itself.
func test_the_events_slot_answers_the_rows_the_root_published() -> void:
	var bridge := _bridge()
	var rows := bridge.open_event_rows()
	assert_eq(rows.size(), 1, "the slot answered exactly what the fixture published")
	if rows.is_empty():
		return
	assert_eq(
		String((rows[0] as Dictionary).get("display_name", "")),
		"Fracture at Greenwood",
		"and it is the event's OWN display_name, not a string this suite wrote"
	)
	assert_eq(
		String((rows[0] as Dictionary).get("stage_name", "")),
		"Oath Taking",
		"with the stage the module published"
	)


## **Rows are copied out, not handed out.** A screen that mutated what it was given would
## be writing into a payload the composition root may still be holding, and the second
## repaint would show a world the root never had.
func test_the_events_slot_hands_out_copies_rather_than_the_roots_own_rows() -> void:
	var bridge := _bridge()
	var rows := bridge.open_event_rows()
	assert_eq(rows.is_empty(), false, "the slot answered a row to mutate")
	if rows.is_empty():
		return
	(rows[0] as Dictionary)["display_name"] = "A name this suite invented"
	var again := bridge.open_event_rows()
	assert_eq(again.is_empty(), false, "and the slot still answers on the second read")
	if again.is_empty():
		return
	assert_eq(
		String((again[0] as Dictionary).get("display_name", "")),
		"Fracture at Greenwood",
		"so the root's own row was not mutated through the seam"
	)


## An unwired read slot answers `[]` — never a crash, never a false row. Read as
## `open_event_rows()` because that is the screen's own door.
func test_an_unwired_events_slot_reads_as_empty_rather_than_as_an_error() -> void:
	var bridge := WorldPulseBridge.new()
	assert_eq(bridge.has_events(), false, "a bridge nobody filled publishes no events")
	assert_eq(bridge.open_event_rows().size(), 0, "and reading it is an empty roster, not a crash")


# --- 2. The SCREEN can NAME an open event --------------------------------------


## THE CLAIM THE WHOLE BL IS ABOUT. A player watching the world route must be able to
## read WHICH event is open, WHAT stage it is in, HOW LONG it has held, and WHAT it pays
## — the four things a bare count could never say.
##
## Asserted on the panel's own published LINE, because that is the text a player reads,
## and on the row underneath it, because a line that names the wrong event is worse than
## no line.
func test_the_screen_names_the_open_event_and_its_stage_and_its_payoff() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	var world := _world_of(screen)
	var lines := world.get("open_event_lines", []) as Array
	assert_eq(lines.size(), 1, "exactly one line per open event, and one event is open")
	if lines.is_empty():
		return
	var line := String(lines[0])
	assert_eq(
		line.contains("Fracture at Greenwood"),
		true,
		"a player can read WHICH event is open - it was a bare count before"
	)
	assert_eq(
		line.contains("Oath Taking"),
		true,
		"WHAT stage it has reached - the stage name reaches the screen verbatim"
	)
	assert_eq(
		line.contains("stage 2 of 3"),
		true,
		"and how far through that is, 1-based, because 'stage 0 of 3' reads as a bug"
	)
	assert_eq(
		line.contains("held 12 periods"),
		true,
		"HOW LONG it has held, in the clock's own unit and never in seconds"
	)
	assert_eq(
		line.contains("standoff oath_finale"),
		true,
		"and WHAT it pays, in the event module's own vocabulary"
	)
	assert_eq(
		L.t(String(world.get("events_title", ""))),
		"What is happening in the world",
		"under a heading that says there IS something happening"
	)
	# The tally is still there too, and that matters: removing the count a player could
	# already read would be a DIFFERENT regression, so the rows are an addition and not a
	# replacement. Two numbers on one surface that can disagree is its own defect, which
	# is why the pulse publishes both from ONE `EventApi.summary` call.
	assert_eq(
		int(world.get("active_events", -1)),
		1,
		"and the bare count the player could always see is unchanged beside the new row"
	)
	_free_all()


## The screen passes RAW values and the panel formats them. A screen that built its own
## sentence would put a `%d` in `ui/` a second place to get wrong, and the count the
## reader already forwards (`active_events`) would no longer be the only tally on the
## surface — two numbers that can disagree.
func test_the_screen_forwards_the_rows_raw_and_the_panel_owns_every_format() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	var rows := _world_of(screen).get("open_events", []) as Array
	assert_eq(rows.size(), 1, "the panel is holding the row the root published")
	if rows.is_empty():
		return
	var row := rows[0] as Dictionary
	for key in ROW_KEYS:
		assert_eq(row.has(key), true, "%s reaches the panel from the module's own row" % key)
	assert_eq(
		int(row.get("periods_held", -1)),
		12,
		"and the held count arrives as an INT a panel formats, not as '12 periods'"
	)
	assert_eq(
		bool(_world_of(screen).get("events_wired", false)),
		true,
		"beside the flag that says the seam was published at all"
	)
	_free_all()


## ## The rows are re-READ, never cached
##
## A screen that read the roster once at bind time would render a world frozen at the
## moment the route opened, while the clock beside it kept moving — two panels on one
## surface, one of them lying. Asserted by counting READS, which is the only thing that
## distinguishes a live roster from a snapshot.
func test_the_screen_rereads_the_rows_so_a_moved_world_is_shown_moved() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	var first := _reads
	screen.refresh()
	assert_eq(_reads > first, true, "a repaint asks the seam again rather than replaying a cache")
	_free_all()


## ## The whole row shape, not the four fields this suite happens to assert on
##
## `_assert_primitives` used to recurse and assert only on a violation, so on a clean
## payload it walked everything and made NO assertion — and `run_tests.gd:171` charges a
## body that asserted nothing as a FAILURE. It answers with the count it verified, and the
## test asserts that count is above zero.
func test_the_screen_summary_stays_primitives_only_with_the_rows_in_it() -> void:
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	var summary := screen.summary()
	assert_eq(summary.is_empty(), false, "the screen published a summary at all")
	assert_eq(
		_assert_primitives(summary) > 0,
		true,
		"and every value reachable from it is a primitive, an array, or a dictionary of those"
	)
	_free_all()


# --- 3. The EMPTY STATE, honestly -----------------------------------------------


## A world with nothing open must say so in words. An empty list under a heading is the
## shape a player reads as a bug — the panel failed to load its data — whereas one honest
## sentence is the difference between "the world is quiet" and "this surface is broken".
func test_a_world_with_no_open_event_says_so_rather_than_rendering_an_empty_list() -> void:
	_rows = []
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	var world := _world_of(screen)
	assert_eq(int(world.get("open_event_count", -1)), 0, "there is genuinely nothing open")
	assert_eq(
		L.t(String(world.get("events_title", ""))),
		"Nothing is happening in the world right now",
		"and the heading says the world is quiet, in the plainest words available"
	)
	var lines := world.get("open_event_lines", []) as Array
	assert_eq(lines.size(), 1, "one line stands in for the empty list, not zero lines")
	if lines.is_empty():
		return
	assert_eq(
		L.t(String(lines[0])),
		"No event is open. The world is waiting on its next one.",
		"and it is a sentence, so the section reads as an answer rather than as a failure"
	)
	_free_all()


## ## THE MISSING SEAM, which is NOT the quiet world
##
## These two are the same `[]` on the wire, and the difference between them is the whole
## reason the flag exists. A screen that rendered an unwired seam as "nothing is happening"
## would turn broken wiring into a calm world — the one reading that hides the defect.
func test_an_unwired_events_seam_is_named_rather_than_rendered_as_a_quiet_world() -> void:
	_rows = []
	_events_wired = false
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	var world := _world_of(screen)
	assert_eq(
		bool(world.get("events_wired", true)),
		false,
		"the screen knows the root published no rows, and says so in the flag"
	)
	assert_eq(
		L.t(String(world.get("events_title", ""))),
		"The world's events are not published to this screen",
		"and the heading NAMES THE MISSING SEAM rather than claiming the world is quiet"
	)
	var lines := world.get("open_event_lines", []) as Array
	assert_eq(lines.is_empty(), false, "a missing seam still says something under its heading")
	if lines.is_empty():
		return
	assert_eq(
		String(lines[0]).contains("No world event row reaches this screen"),
		true,
		"and the line explains the seam, which is what a player reads when a world looks idle"
	)
	_free_all()


## A row with no display name is a THIRD state, and the one a hardcoded roster check would
## get wrong: something IS open, and this surface cannot say what. Rendering it as "nothing
## is happening" would be a lie about a live event.
func test_an_open_event_this_screen_cannot_name_says_so_instead_of_claiming_peace() -> void:
	_rows = [_row()]
	(_rows[0] as Dictionary)["display_name"] = ""
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	var world := _world_of(screen)
	assert_eq(int(world.get("open_event_count", -1)), 1, "an event really is open")
	assert_eq(
		L.t(String(world.get("events_title", ""))),
		"Something is open, and this screen cannot name it",
		"which is neither 'quiet' nor 'fine', and the heading says exactly that"
	)
	assert_eq(
		int(world.get("unnamed_event_count", -1)),
		1,
		"and the panel counted the unnamed row rather than hiding it"
	)
	assert_eq(
		String((world.get("open_event_lines", []) as Array)[0]).contains("greenwood_fracture"),
		true,
		"the line falls back to the event's OWN id, which is worse than a name but honest"
	)
	_free_all()


## ## A row the panel cannot render at all is KEPT, not dropped
##
## Dropping an unnamed row would convert "something is open and I cannot name it" into
## "nothing is open" — the false calm this whole seam exists to prevent. So the count and
## the heading are asserted together.
func test_the_panel_never_drops_a_published_row_to_make_its_own_output_look_clean() -> void:
	_rows = [_row(), _row()]
	(_rows[1] as Dictionary)["display_name"] = ""
	(_rows[1] as Dictionary)["event_id"] = ""
	var screen := _screen()
	screen.setup(_actor())
	screen.bind_world(_bridge())
	var world := _world_of(screen)
	assert_eq(
		int(world.get("open_event_count", -1)),
		2,
		"both published rows are held, because dropping one would hide a live event"
	)
	assert_eq(
		(world.get("open_event_lines", []) as Array).size(),
		2,
		"and each is rendered, the nameless one under the wording that admits it"
	)
	_free_all()


# --- 4. The SEAM ITSELF: no module reads, no second row shape -------------------


## `ui/` may reach `app/` only through the bridge, so a screen that could name the event
## module some other way would be a second path and the rule `PRIVATE_UNITS` exists for
## would be decorative. Read with comments stripped, because these files DOCUMENT this
## rule in prose and a guard that fires on its own documentation is a guard nobody trusts.
func test_no_ui_file_names_the_event_module_the_bridge_hides() -> void:
	var files := _ui_files("gd")
	assert_eq(files.is_empty(), false, "the UI walk visited files, so this verdict is real")
	for entry in files:
		var code := _code_only(entry["text"] as String)
		for banned in ["EventApi", "EventReadModel", "res://src/modules/event"]:
			assert_eq(
				code.contains(banned),
				false,
				(
					"%s names %s; the rows arrive through WorldPulseBridge or not at all"
					% [entry["path"], banned]
				)
			)


## ## The rows are PUBLISHED, not re-derived
##
## The event module already computed them and already owns the shape. A pulse that
## rebuilt a row field-by-field would be a second read model, and a panel that invented a
## field would be authoring vocabulary the module does not speak — both the private-copy
## shape ADR 0116 exists to stop.
func test_the_pulse_publishes_the_module_rows_rather_than_rebuilding_them() -> void:
	var pulse := _read(PULSE_SOURCE)
	assert_ne(pulse.is_empty(), true, "%s is readable" % PULSE_SOURCE)
	assert_eq(
		pulse.contains('"open_event_rows"'),
		true,
		"WorldPulse.summary must PUBLISH the row roster, not only the count beside it"
	)
	assert_eq(
		_code_only(pulse).contains("EventReadModel"),
		false,
		"and it must take them from the module's OWN read model rather than rebuilding a row"
	)


## The composition root FILLS the slot, and it is the only place that may. A bridge whose
## `events` is wired to nothing is the original defect with a field added. Read as source
## because mounting the root is one parse error away, and a reachability suite that can go
## red for a peer's in-flight split proves nothing.
func test_the_composition_root_fills_the_events_slot() -> void:
	var root := _read(ROOT_SOURCE)
	assert_ne(root.is_empty(), true, "%s is readable" % ROOT_SOURCE)
	assert_eq(
		root.contains('bridge.events = Callable(self, "_world_open_events")'),
		true,
		(
			"MISSING SEAM: ItemWorkbenchApp builds a world bridge but never fills the events "
			+ "slot, so every open event row the pulse computes stops at the root"
		)
	)
	assert_eq(
		root.contains("func _world_open_events() -> Array[Dictionary]:"),
		true,
		"and the callable it names answers the row roster the pulse owns"
	)


## The bridge file itself must DOCUMENT the slot it cuts, because the cut is the thing a
## reader will want to reinstate. A slot with no stated reason is one a future reader
## removes as an unused seam.
func test_the_bridge_states_why_the_events_slot_exists() -> void:
	var bridge := _read(BRIDGE_SOURCE)
	assert_ne(bridge.is_empty(), true, "%s is readable" % BRIDGE_SOURCE)
	var doc := _doc_of(bridge, "var events: Callable")
	assert_eq(
		doc.contains("BL-0906"),
		true,
		"the slot's own note names the measurement that cut the previous seam"
	)


# --- 5. The PRODUCTION bridge, driven the way a player drives it ----------------


## THE ACCEPTANCE CLAIM. Drives the real `ItemWorkbenchApp` through the real `ScreenStack`,
## navigates to the world route, and reads the live screen's summary — the way a player
## opens the world page.
##
## **RED until `ItemWorkbenchApp._world_bridge` fills the `events` slot.** A suite that
## builds its own bridge proves the UI PROGRAM renders rows; only this one proves the
## composition root PUBLISHES them, which is the half that was missing. Cases 1–4 stay
## green when this line is deleted, so this is not redundant with them.
##
## The assertion is deliberately NOT "a row arrived". On a fresh world the root may
## legitimately have nothing open, so the claim is the one that holds either way: the seam
## is PUBLISHED, which is only knowable from the flag, and the section renders a sentence
## rather than nothing. A world that has an open event names it — asserted separately below
## by pressing the world's own wait verb until one opens, because an event that only
## appears on a lucky seed is not a thing a player can rely on seeing.
func test_the_running_build_publishes_open_event_rows_to_the_world_route() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp boots, or nothing below is proven")
	if harness.boot_error != "":
		return
	var moved := harness.navigate(&"world_map")
	assert_eq(bool(moved["ok"]), true, "the world route is reachable: %s" % moved["note"])
	if not bool(moved["ok"]):
		return
	var live := harness.live_screen()
	assert_ne(live, null, "the world route left a live screen")
	if live == null:
		return
	var world := (live.call(&"summary") as Dictionary).get("world", {}) as Dictionary
	assert_eq(
		bool(world.get("events_wired", false)),
		true,
		(
			"MISSING SEAM: the world route shows a tally no player can expand. The composition "
			+ "root binds a bridge with no events slot, so every open event the pulse computes "
			+ "stops at the root. Fill it in ItemWorkbenchApp._world_bridge()."
		)
	)
	var lines := world.get("open_event_lines", []) as Array
	assert_eq(
		lines.is_empty(),
		false,
		"and the section renders a sentence even with nothing open, rather than an empty list"
	)


## ## THE SAME RUN, once the world has actually opened something
##
## `MAX_OPENS_PER_PULL` is `1` and the pull is one period, so a fresh root may hold
## nothing. Pressing the world's OWN wait button until a row appears proves the two halves
## agree on the same rows: the pulse counts them (`active_events`) and the screen names
## them (`open_event_lines`). **They are read from one `EventApi.summary` call inside
## `WorldPulse.summary`, so a disagreement here is a real defect and not a timing artefact.**
func test_the_running_build_names_an_event_the_whole_world_agrees_is_open() -> void:
	var harness := SeamHarness.mount_new()
	assert_eq(harness.boot_error, "", "the real ItemWorkbenchApp boots")
	if harness.boot_error != "":
		return
	var moved := harness.navigate(&"world_map")
	if not bool(moved["ok"]):
		assert_eq(false, true, "the world route is reachable: %s" % moved["note"])
		return
	var live := harness.live_screen()
	if live == null:
		assert_eq(false, true, "the world route left a live screen")
		return
	var named := ""
	var counted := 0
	for attempt in OPEN_ATTEMPTS:
		var world := (live.call(&"summary") as Dictionary).get("world", {}) as Dictionary
		counted = int(world.get("active_events", 0))
		if counted > 0:
			var lines := world.get("open_event_lines", []) as Array
			named = "" if lines.is_empty() else String(lines[0])
			break
		harness.press(live, "%WaitButton")
		# The press repaints through the screen, which re-reads the seam, so the next
		# iteration reads a fresh roster rather than the one this loop started with.
		live = harness.live_screen()
		if live == null:
			break
	assert_eq(
		counted > 0,
		true,
		(
			(
				"the world opened nothing after %d seasons; this suite cannot prove a player can "
				% OPEN_ATTEMPTS
			)
			+ "see an open event if the world never has one"
		)
	)
	assert_eq(
		named.is_empty(),
		false,
		"the pulse counts an open event and the screen renders a line for it, so the two halves agree"
	)
	assert_eq(
		named.contains("held "),
		true,
		"and the line a player reads says how long it has held, which a count never could"
	)


# --- Fixtures ------------------------------------------------------------------


func _panel() -> WorldPulsePanel:
	var panel := (load(PANEL_SCENE) as PackedScene).instantiate() as WorldPulsePanel
	_born.append(panel)
	return panel


func _screen() -> WorldMapScreen:
	var screen := (load(SCREEN_SCENE) as PackedScene).instantiate() as WorldMapScreen
	_born.append(screen)
	return screen


## An actor the world map can render, as `test_world_pulse.gd`'s own fixture does: the
## screen's other dependency answers for any actor, and the clock arrives by bridge.
func _actor() -> Actor:
	return Actor.new(&"event_hero", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})


## ## A bridge whose clock AND rows are this suite's own
##
## The verb slots answer the same keys `ItemWorkbenchPlay` answers, and the read slot
## answers rows in the exact shape `EventReadModel.open_rows` publishes — so an assertion
## about the panel is a statement about the UI PROGRAM rendering what it was handed.
## `events_wired` is a separate switch rather than inferred from the rows, because an
## unwired slot and an empty world are the same `[]` and only the caller can tell them
## apart; that distinction is what case 3 measures.
func _bridge() -> WorldPulseBridge:
	var bridge := WorldPulseBridge.new()
	bridge.read_state = Callable(self, "_fake_state")
	bridge.advance = Callable(self, "_fake_advance")
	bridge.retreat = Callable(self, "_fake_retreat")
	if _events_wired:
		bridge.events = Callable(self, "_fake_events")
	return bridge


func _fake_state() -> Dictionary:
	return {
		"periods": 12,
		"period_count": 12,
		"period_seconds": 120.0,
		"offered": 36,
		"claimed": 24,
		"opened": 2,
		"active_events": _rows.size(),
		"available_events": 2,
		"ambient_facts": [],
		# The count and the roster are published from ONE `EventApi.summary` call in the
		# real pulse. The fixture mirrors that by deriving both from `_rows`, so a
		# disagreement between them cannot be an artefact of this suite's own bookkeeping.
		"open_event_rows": _rows.duplicate(true),
	}


func _fake_advance() -> Dictionary:
	return {"ok": true, "reason": "", "periods": 13}


func _fake_retreat(periods: int) -> Dictionary:
	return {"ok": true, "reason": "", "declared": periods, "paid": periods, "unpaid": 0}


func _fake_events() -> Array[Dictionary]:
	_reads += 1
	return _rows.duplicate(true)


## One open event row, in the exact shape the event module's read model publishes. Every
## key `ROW_KEYS` names is present even where this suite asserts on none of it, because a
## fixture with only the four interesting keys would let a panel that dropped the other
## ten pass.
func _row() -> Dictionary:
	return {
		"event_id": "greenwood_fracture",
		"kind": "rift",
		"display_name": "Fracture at Greenwood",
		"location_id": "mortal_greenwood",
		"stage_id": "oath",
		"stage_name": "Oath Taking",
		"stage_index": 1,
		"stage_count": 3,
		"opened_period": 7,
		"periods_held": 12,
		"duration_periods": 4,
		"standoff_id": "oath_finale",
		"territory_id": "",
		"is_final_stage": false,
	}


func _world_of(screen: Node) -> Dictionary:
	return (screen.summary() as Dictionary).get("world", {}) as Dictionary


## Every `.gd` under `res://src/ui`, as `{path, text}`. Iterative, not recursive:
## `test_ui_conventions.gd` measured that a recursive `DirAccess` walk silently returns
## nothing under this runner, which would make the guard above pass vacuously.
func _ui_files(extension: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pending: Array[String] = ["res://src/ui"]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var path: String = current.path_join(entry)
			if dir.current_is_dir():
				if not entry.begins_with("."):
					pending.append(path)
			elif path.get_extension() == extension:
				out.append({"path": path, "text": _read(path)})
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["path"] < b["path"])
	return out


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Source with comments stripped, so a file that DOCUMENTS the rule it follows is not
## failed by it.
func _code_only(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		var out := ""
		var quoted := false
		for i in line.length():
			var ch := line[i]
			if ch == '"':
				quoted = not quoted
			elif ch == "#" and not quoted:
				break
			out += ch
		kept.append(out)
	return "\n".join(kept)


## The doc comment block immediately above `marker`: every contiguous `##` line going up
## from it, stopping at the first line that is not one. The bridge's slot notes live
## above their declarations, so this is how a guard reads the REASON rather than the type.
func _doc_of(text: String, marker: String) -> String:
	var lines := text.split("\n")
	var out: Array[String] = []
	for line in lines:
		if line.strip_edges().begins_with(marker):
			break
		if line.strip_edges().begins_with("##"):
			out.append(line)
		elif not line.strip_edges().is_empty():
			out.clear()
	return "\n".join(out)


## Every value reachable from `value` is a primitive, an array, or a dictionary of those.
## Returns how many values were verified, so a caller can assert that the walk happened
## instead of only that it found nothing.
func _assert_primitives(value: Variant) -> int:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return 1
		TYPE_DICTIONARY:
			var seen := 1
			for key in value as Dictionary:
				seen += _assert_primitives(key) + _assert_primitives((value as Dictionary)[key])
			return seen
		TYPE_ARRAY:
			var counted := 1
			for item in value as Array:
				counted += _assert_primitives(item)
			return counted
		_:
			assert_eq(true, false, "non-primitive value in summary(): %s" % typeof(value))
			return 0


## Everything this suite instantiated is freed here rather than at each call site: an
## early return in a test would otherwise skip its own cleanup, and the runner shares one
## process across every suite. Detached before freed, because a node still parented does
## not release, and never `queue_free()` — the runner never processes a frame.
func _free_all() -> void:
	for node in _born:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_born.clear()


func teardown() -> void:
	if SeamHarness.live != null:
		SeamHarness.live.teardown()
	_free_all()
