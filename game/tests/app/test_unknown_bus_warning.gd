extends TestCase

## ADR 0266, the second half: an unknown events bus WARNS instead of vanishing.
##
## ## The defect
##
## ADR 0242 decision 4 says an unknown bus name "is skipped without crashing". That
## BEHAVIOUR is right and is unchanged here: one bad subscription must not take a boot
## down, and the mod's other subscriptions still load. What was missing is the other half
## of ADR 0184 decision 8 — never skip SILENTLY. `_resolve_events_bus` returned `null`,
## `_wire_subscriptions` hit `continue`, and nothing said so: the mod's handler would
## never run and the author would find out from a missing reward rather than from a line
## in the log. A registrable System whose entire economy is ONE subscription fails
## invisibly under that, which is the whole point of building the bus it subscribes to.
##
## So the skip now NAMES both the bus and the mod that asked for it — `mod_id` is stamped
## onto each row by `ModRuntime.finalize`, the only place that knows which mod a row came
## from — and the pair is recorded on `_unresolved_buses` so the skip is assertable rather
## than only visible in a log.

## Every bus name `_resolve_events_bus` publishes, restated HERE on purpose: the factory
## table is a Dictionary built on each call, so a test that read it back could only prove
## the table agrees with itself. This list is the outside expectation.
const BUS_NAMES: Array[String] = [
	"NpcEvents",
	"AuctionEvents",
	"QuestEvents",
	"ConflictEvents",
	"WorldEvents",
	"DestinyEvents",
	"NationEvents",
	"SectEvents",
	"HoldingsEvents",
]

var _harness: SeamHarness
var _app: ItemWorkbenchApp
var _saved_registrations: Dictionary = {}


func setup() -> void:
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp
	_saved_registrations = ModBoot.active_registrations.duplicate(true)


func teardown() -> void:
	ModBoot.active_registrations = _saved_registrations
	# Free the harness node tree (`free()`, never `queue_free()` — the headless runner
	# drives every test from `SceneTree._initialize()` and a deferred free never runs
	# under `tools test`, which is how a screen subtree leaked per navigation once).
	if _harness != null:
		_harness.teardown()
	_harness = null
	_app = null


# --- The bus resolves ------------------------------------------------------------


## The reason the warning above is worth adding: a mod CAN subscribe to `QuestEvents`,
## and it resolves to the ONE instance `QuestApi` emits through. Asserted against
## `shared()` and not merely against "not null" because a non-null bus that is a
## different object is precisely the dead-subscription defect (ADR 0242 decision 2 hands
## five buses out as a fresh `new()`, which nothing then emits on).
func test_quest_events_resolves_to_the_bus_the_module_emits_on() -> void:
	var bus: RefCounted = _app.call("_resolve_events_bus", "QuestEvents")
	assert_ne(bus, null, "QuestEvents resolves to a bus")
	assert_eq(bus, QuestEvents.shared(), "and it is the shared one QuestApi publishes on")
	assert_eq(
		bus.is_connected(&"quest_completed", Callable()),
		false,
		"so `is_connected` on a fresh callable reads false: a subscriber here is live"
	)


## Every bus the factory table names resolves to SOMETHING. A table entry that silently
## returns null is the whole defect, so this walks the names the table declares rather
## than trusting the table to agree with its own docblock.
func test_every_named_bus_resolves_to_the_class_it_is_named_for() -> void:
	for bus_name in BUS_NAMES as Array[String]:
		var bus: RefCounted = _app.call("_resolve_events_bus", bus_name)
		assert_ne(bus, null, "'%s' resolves to a bus" % bus_name)
		if bus == null:
			continue
		var script := bus.get_script()
		assert_ne(script, null, "'%s' resolves to a scripted object" % bus_name)
		if script == null:
			continue
		# A subscriber that reaches the WRONG object is a dead subscription with no
		# error, and `is_connected` will report it connected forever — so the identity
		# is the claim, not merely "something came back".
		assert_eq(
			String(script.get_global_name()),
			bus_name,
			"'%s' resolves to the contract of that name, not a substitute" % bus_name
		)


# --- The warning -----------------------------------------------------------------


## The claim: an unknown bus is SKIPPED — the boot survives, the mod's other
## subscriptions still load, per ADR 0242 decision 4 — and the skip is RECORDED naming
## both halves, so it is no longer silent.
func test_an_unknown_bus_is_skipped_and_recorded_naming_the_bus_and_the_mod() -> void:
	var good := Callable(self, "_on_anything")
	var registrations := ModBoot.active_registrations.duplicate(true)
	registrations["subscriptions"] = [
		{
			"event_bus": "UnknownBus",
			"event_name": "some_event",
			"callable": good,
			"mod_id": "doctrine",
		},
		{"event_bus": "QuestEvents", "event_name": "quest_completed", "callable": good},
	]
	ModBoot.active_registrations = registrations

	_app.call("_wire_subscriptions", registrations["subscriptions"])

	var unresolved: Array = _app._unresolved_buses
	assert_eq(unresolved.size(), 1, "one unknown bus, one record")
	assert_eq(
		String(unresolved[0]["event_bus"]), "UnknownBus", "naming the bus that resolved to nothing"
	)
	assert_eq(String(unresolved[0]["mod_id"]), "doctrine", "and the mod that asked for it")
	assert_eq(String(unresolved[0]["event_name"]), "some_event", "and the signal it wanted")
	assert_eq(
		QuestEvents.shared().is_connected(&"quest_completed", good),
		true,
		"while the resolvable subscription in the SAME pass still connected"
	)
	if QuestEvents.shared().is_connected(&"quest_completed", good):
		QuestEvents.shared().quest_completed.disconnect(good)


## A row with NO mod id — a mod that wrote its subscription by hand rather than through
## `ModRuntime.finalize` — is still recorded, and the unnamed mod is reported as such
## rather than dropped. The unknown-bus half is the thing under test; the name is a
## detail, and an empty name must not swallow the record.
func test_an_unnamed_mod_is_still_recorded_rather_than_dropped() -> void:
	(
		_app
		. call(
			"_wire_subscriptions",
			[
				{
					"event_bus": "UnknownBus",
					"event_name": "some_event",
					"callable": Callable(self, "_on_anything"),
				}
			]
		)
	)
	var unresolved: Array = _app._unresolved_buses
	assert_eq(unresolved.size(), 1, "recorded with no mod id on the row at all")
	assert_eq(String(unresolved[0]["mod_id"]), "", "and the mod reported as unnamed, not absent")


## The array reflects the MOST RECENT pass, like `_unwired_families` beside it: a second
## boot with a valid subscription only must not leave last boot's unknown bus standing.
func test_the_record_is_cleared_on_each_pass() -> void:
	(
		_app
		. call(
			"_wire_subscriptions",
			[
				{
					"event_bus": "UnknownBus",
					"event_name": "e",
					"callable": Callable(self, "_on_anything"),
					"mod_id": "doctrine",
				}
			]
		)
	)
	assert_eq((_app._unresolved_buses as Array).size(), 1, "the first pass recorded the skip")
	_app.call("_wire_subscriptions", [])
	assert_eq(_app._unresolved_buses.is_empty(), true, "and a clean pass leaves nothing standing")


## A row that is not a subscription at all, or names no bus, is not an unknown BUS and is
## not reported as one. A warning that fires on every malformed row trains the reader to
## ignore it — the whole failure mode a named warning exists to avoid.
func test_a_malformed_row_is_not_reported_as_an_unknown_bus() -> void:
	_app.call("_wire_subscriptions", ["not a dictionary", {}, {"event_bus": ""}])
	assert_eq(
		_app._unresolved_buses.is_empty(),
		true,
		"three malformed rows and no unknown-bus record: this is a bad row, not an unknown bus"
	)


# --- The warning is really emitted ------------------------------------------------


## GDScript cannot intercept `push_warning`, so the STRING is asserted against the
## composition root's own source — read as CODE, comments stripped, the way
## `test_quest_production_completion.gd` reads its install seam. Without the strip the
## docblock above, which names both halves in prose, would satisfy the search by itself.
func test_the_composition_root_warns_naming_the_bus_and_the_mod() -> void:
	var body := _code_of("res://src/app/item_workbench_body.gd")
	var start := body.find("func _wire_subscriptions(")
	assert_ne(start, -1, "the wiring function is still there")
	if start < 0:
		return
	var stop := body.find("\n\n\nfunc ", start)
	var wiring := body.substr(start, stop - start if stop > start else 0)
	assert_ne(wiring.find("push_warning("), -1, "the skip announces itself")
	assert_ne(
		wiring.find("unknown events bus"),
		-1,
		"and the message names the bus as unknown rather than reporting a bare skip"
	)
	assert_ne(
		wiring.find("mod_id"),
		-1,
		"and names the mod that asked for it — an unknown bus with no owner is a defect report"
	)


## The mod id has to REACH the row, or the warning above can only ever print an empty
## name. `ModRuntime.finalize` is the only place that knows which context a subscription
## row came from, so the stamp is asserted there rather than in the app.
func test_finalize_stamps_the_mod_id_onto_every_subscription() -> void:
	var registry := ModuleRegistry.new()
	var a := RegistrationContext.new("mod_a", {}, registry)
	var b := RegistrationContext.new("mod_b", {}, registry)
	var row := {"event_bus": "QuestEvents", "event_name": "quest_completed", "callable": Callable()}
	a.subscribe(row.duplicate())
	b.subscribe(row.duplicate())
	var out := ModRuntime.finalize([a, b], registry)
	var subs: Array = out["subscriptions"]
	assert_eq(subs.size(), 2, "both subscriptions collected")
	assert_eq(String(subs[0]["mod_id"]), "mod_a", "the first names the mod that declared it")
	assert_eq(String(subs[1]["mod_id"]), "mod_b", "and so does the second")
	assert_eq(
		String(subs[0]["event_bus"]),
		"QuestEvents",
		"and the bus the stamp rides on is untouched by the stamping"
	)


## A file's CODE, with comments stripped, so a docblock cannot satisfy a search that is
## supposed to be measuring the function body.
func _code_of(path: String) -> String:
	var out := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := String(raw)
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at := line.find("#")
		if hash_at >= 0:
			line = line.substr(0, hash_at)
		out += line + "\n"
	return out


## Stub handler. These tests assert on what was CONNECTED and RECORDED, never on the
## handler running, so it does nothing.
func _on_anything() -> void:
	pass
