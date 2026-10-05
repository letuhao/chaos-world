extends "res://tests/modules/event/event_director_fixture.gd"

## ## THE PROBE FILE — BL-0896 / BL-0897
##
## Two authored events that are dead content, and the two tests that drive the
## PRODUCTION surface rather than constructing the seam they test.
##
## ## Why a PRODUCTION surface and not a fixture
##
## An earlier audit proved here that a suite which wires up what it tests cannot
## fail when the wiring is absent. So neither test below calls `EventGate` directly,
## installs a resolver, or hands `EventApi` a def: both drive the shipped `.tres`
## through the shipped catalog, and the war probe READS `res://src` the way the
## repository's own `tools arch` reachability pass does.
##
## ## What each one is for
##
## - `the_stone_that_answering`: opens and runs its ladder through `EventApi` with
##   NO test-only gate relaxation — no pre-recorded fact, no relaxed trigger, not a
##   hand-built def. Whatever the ledger happens to hold is what the world offers.
## - `war_of_the_nine_fords`: the declared standoff must have a reachable caller.
##   A war whose declaration is wired and whose settlement is not is the defect
##   ADR 0085 exists to keep visible.

const STONE := &"the_stone_that_answering"

## The war id, named LOCALLY rather than taken from the fixture. The fixture already
## declares `WAR`, and a subclass that redeclares a parent's constant is a PARSE
## ERROR ("the member already exists in parent class"), not a shadow — so this file
## extends the fixture for its actor plumbing and names its own ids here.
const CONFLICT := &"war_of_the_nine_fords"

## The production tree, which is the whole scope of a reachability claim: `res://src`
## only. `res://tests` is deliberately NOT walked, because a suite that only calls
## itself is not reachability — `tools/arch/facade_constants.py:365` says so in
## those words and this file obeys it.
const PRODUCTION_ROOT := "res://src"


## Every `.gd` under `root`, found iteratively and sorted.
##
## Iterative, for the reason `event_director_fixture.gd:_module_files` already
## documents: a recursive `DirAccess` returned an empty list under this runner once,
## and an empty scan makes every assertion pass vacuously — which is the exact
## failure this probe exists to catch. `assert_gt(scanned, 0)` below is what keeps
## that from happening here.
func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
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
			elif path.ends_with(".gd"):
				out.append(path)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


## Every production file that CALLS `EventApi.resolve`, with its line number.
##
## The definition itself is excluded by construction: this looks for the call shape
## `EventApi.resolve(`, and `event/api.gd` declares `static func resolve(`. A probe
## that counted the declaration would report the module reaching itself and read as
## coverage of a gap it never tested.
func _production_callers_of_resolve() -> Array[String]:
	var hits: Array[String] = []
	for path in _gd_files(PRODUCTION_ROOT):
		var text := FileAccess.get_file_as_string(path)
		var from := 0
		while true:
			var at := text.find("EventApi.resolve(", from)
			if at < 0:
				break
			var line := text.substr(0, at).split("\n").size()
			hits.append("%s:%d" % [path.get_file(), line])
			from = at + 1
	return hits


# --- GAP 1: the stone event ---------------------------------------------------


## A hero who has done NOTHING. No pre-recorded fact, no relaxed trigger, no
## hand-built def: the shipped catalog, the shipped gate, the shipped ledger.
##
## Founded in the March because the prize pays a `nation_standing` row, and
## standing in the transcendent realm because that is where the stone is.
func _stone_actor() -> Actor:
	var actor := Actor.new(&"stone_probe_actor", {Stat.PHYSIQUE: 10.0})
	DestinyApi.attach(actor)
	NationApi.attach(actor)
	EventApi.attach(actor)
	NationApi.found(actor, &"march_of_the_nine_provinces", String(actor.id))
	EventApi.set_location(actor, &"transcendent_realm")
	return actor


## THE PROBE. The event must appear in `available` and then OPEN, with no help.
##
## This is the whole test. `EventApi.available` reads the authored trigger and
## `EventApi.begin` re-checks it, so a trigger a legal prior state cannot satisfy
## makes this fail at `ok == false` with `trigger_unmet` — which is precisely the
## BL-0896 defect, and it fails HERE rather than in a fixture that had already
## recorded the fact it was waiting for.
func test_the_stone_event_is_offered_and_opens_with_no_gate_relaxation() -> void:
	var actor := _stone_actor()

	var offered := EventApi.available(actor)
	var ids: Array[String] = []
	for row in offered:
		ids.append(String((row as Dictionary)["event_id"]))

	assert_eq(
		ids.has(String(STONE)),
		true,
		(
			("`available` never offers the stone on a hero who has done nothing. " + "offered=%s")
			% str(ids)
		)
	)

	var opened := EventApi.begin(actor, STONE)
	assert_eq(
		bool(opened.get("ok", false)),
		true,
		"the stone event opens through the production verb, unrelaxed: %s" % opened
	)
	assert_eq(_stage_id(actor, STONE), "read", "and it opens on the stage it authors")


## THE LADDER RUNS. An opened event that never reaches its prize is a different dead
## content from one that never opens, and `advance` is the only pull-based verb that
## moves it (ADR 0085: no clock in the module).
##
## The loop is bounded by the def's own stage count rather than by a magic number, so
## it cannot pass by advancing forever: a ladder that refuses to move would return
## the same stage every pull and the final assertion would fail.
func test_the_stone_event_runs_its_ladder_and_pays_through_the_pull_based_advance() -> void:
	var actor := _stone_actor()
	var opened := EventApi.begin(actor, STONE)
	assert_eq(bool(opened.get("ok", false)), true, "it opens first: %s" % opened)

	var def := EventCatalog.instance().event_definition(STONE)
	assert_ne(def, null, "the catalog serves the shipped def")
	var pulls: int = int(def.stage_count()) + 4
	var resolutions := 0
	for index in range(pulls):
		var pulled := EventApi.advance(actor, 1)
		resolutions += (pulled["resolved"] as Array).size()

	assert_eq(
		resolutions,
		1,
		(
			(
				"the ladder resolved exactly once across %d pulls; a one-stage event that "
				+ "never resolves is dead content a second way"
			)
			% pulls
		)
	)
	assert_eq(
		int(EventApi.summary(actor)["paid_count"]),
		1,
		"and the prize was paid, marked paid, exactly once (ADR 0061)"
	)
	assert_eq(
		int(EventApi.summary(actor)["active_count"]),
		0,
		"so nothing is left open: the event closed rather than stalling"
	)


## Every fact the shipped def's own opening and stages WRITE, as primitives.
##
## `EventDef.opening_beats` is the def's own folding of its first stage's `on_enter`
## in beside its own, so one read covers both writers. Read off the SHIPPED catalog,
## not off a def this file builds.
func _facts_this_event_produces(def: EventDef) -> Array[StringName]:
	var out: Array[StringName] = []
	for beat in def.opening_beats():
		var fact := StringName((beat as Dictionary).get("fact", ""))
		if fact != &"" and not out.has(fact):
			out.append(fact)
	for stage in def.stages:
		for beat in stage.on_enter:
			var fact := StringName((beat as Dictionary).get("fact", ""))
			if fact != &"" and not out.has(fact):
				out.append(fact)
	return out


## Every `fact` id the authored trigger READS, composites included.
##
## `EventGate.verbs_in` only answers "which VERBS", so this is its own walk over the
## trigger dictionary. `none_of` is walked exactly like `all_of` — the tree used to
## hide this defect behind a soft tier precisely because a guard that stopped at
## `none_of` never looked inside it.
func _facts_the_trigger_demands(trigger: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if trigger.is_empty():
		return out
	var verb := StringName(trigger.get("verb", ""))
	if verb == EventFacts.VERB_FACT:
		var fact := StringName(trigger.get("id", ""))
		if fact != &"" and not out.has(fact):
			out.append(fact)
		return out
	if not EventGate.COMPOSITE_VERBS.has(verb):
		return out
	var children = trigger.get("of", [])
	if not (children is Array):
		return out
	for child in children as Array:
		if not (child is Dictionary):
			continue
		for nested in _facts_the_trigger_demands(child as Dictionary):
			if not out.has(nested):
				out.append(nested)
	return out


## **THE RED PROOF FOR GAP 1.** The shipped def, read off the production catalog.
##
## The gate this event used to author was
## `none_of(fact treasure_stone_read)`, and `treasure_stone_read` is written by this
## event's OWN stage 0 and by nothing else in the tree. That is BL-0896 exactly: the
## demand sits behind the door that would satisfy it.
##
## **`none_of` is why the assertion is about the AUTHORED DEMAND, not the verdict.**
## A prohibition needs no producer — it is OPEN on any hero who has never read the
## stone — so a runtime verdict test passes ON the defect and the dead content ships.
## ADR 0217's SATISFIABLE test is about the DEMAND: a legal prior state must produce
## the fact it asks for, and here the only producer is the event itself. Demand and
## producers are read off the same shipped def, so this goes red on a trigger this
## ladder satisfies by itself and green on one that asks the world for something.
func test_no_shipped_event_demands_a_fact_only_its_own_ladder_produces() -> void:
	var def := EventCatalog.instance().event_definition(STONE)
	assert_ne(def, null, "the catalog serves the shipped stone def")

	var demands := _facts_the_trigger_demands(def.trigger)
	var produces := _facts_this_event_produces(def)

	# The walk is not vacuous: the def really does write facts, or a def that wrote
	# none would pass this for the wrong reason.
	assert_eq(
		produces.size() > 0,
		true,
		(
			"the def writes %d facts, so the comparison below is against a real producer set"
			% produces.size()
		)
	)

	var circular: Array[String] = []
	for fact in demands:
		if produces.has(fact):
			circular.append(String(fact))

	assert_eq(
		circular.size(),
		0,
		(
			(
				"the authored trigger of '%s' demands %s, and that fact is written ONLY by "
				+ "this event's own opening/stages. The gate is satisfied only by its own "
				+ "opening (ADR 0217 SATISFIABLE), so the event can never open on a legal "
				+ "prior state. demands=%s produces=%s"
			)
			% [String(STONE), str(circular), str(demands), str(produces)]
		)
	)


# --- GAP 2: the war's standoff ------------------------------------------------


## THE PROBE. A war whose DECLARATION is wired and whose SETTLEMENT is not is the
## ADR 0085 shape with half a wire on it: `WorldEventBus.conflict_triggered`
## announces escalating conflict, the standoff row is written, and no player action
## can ever close it.
##
## `EventApi.resolve` is the ONE place `NationApi.resolve_conflict` is called from
## (`event/api.gd:432`), so if nothing in production calls `resolve`, the whole
## program's one political conflict is unresolvable. This asserts the call site
## EXISTS — it is a reachability probe over `res://src`, not a test of `resolve`
## itself.
func test_the_declared_war_has_a_production_caller_that_can_settle_it() -> void:
	# `assert_eq`, never `assert_gt`: this runner's `TestCase` has no `assert_gt`,
	# and a name the base class does not own is a PARSE ERROR, not a missing
	# assertion. `size > 0` as an equality is the same claim either way.
	var scanned := _gd_files(PRODUCTION_ROOT).size()
	assert_eq(
		scanned > 0,
		true,
		(
			(
				"the production walk read %d files. A probe that scanned nothing passes "
				+ "vacuously, which is the defect this file exists to catch"
			)
			% scanned
		)
	)

	var callers := _production_callers_of_resolve()
	assert_eq(
		callers.size() > 0,
		true,
		(
			"NO production file calls `EventApi.resolve`. It is the only caller of "
			+ "`NationApi.resolve_conflict` (event/api.gd:432), so the standoff that "
			+ "`war_of_the_nine_fords` DECLARES (transfer: ownership, territory_id: "
			+ "river_march) can never be settled: the river march never changes hands "
			+ "and the standoff row is never closed. ADR 0085 forbids inventing a "
			+ "verdict source inside the political layer, so the missing moment is a "
			+ "content and app-layer build - see docs/deferred.jsonl DEF-0315."
		)
	)


## The declaration half is ALREADY wired, and this pins it so the settlement half
## cannot be "fixed" by deleting the war. `begin` calls `NationApi.declare_war`
## through `_declare` (`api.gd:697`), so a reachable declaration with an unreachable
## settlement is the honest state to measure against.
func test_the_war_still_declares_its_standoff_and_the_territory_is_still_its_prize() -> void:
	var def := EventCatalog.instance().event_definition(CONFLICT)
	assert_ne(def, null, "the catalog serves the shipped war")
	assert_eq(String(def.kind), "sect_war", "and it is the conflict kind")

	var declaration := EventApi._war_declaration(def.trigger)
	assert_eq(String(declaration.get("other_id", "")), "court_of_the_star", "its sides")
	assert_eq(
		String(declaration.get("territory_id", "")),
		"river_march",
		"and the ground at stake, which is what makes this a war about ownership"
	)
	assert_eq(
		String(declaration.get("transfer", "")),
		"ownership",
		"the declared prize transfers ownership, and it is declared UP FRONT (ADR 0085)"
	)
