extends TestCase

## DEF-0121 / DEF-0181: `DestinyApi.record` had ZERO callers in `src/`, so all nine
## authored counter ids were permanently 0 and the `counter` gate verb was theatre —
## a fate declaring `counters = [&"duels_won"]` advertised progress no player could
## make, and `{verb: &"counter", id: &"duels_won", need: 3}` could never open.
##
## **These assert the PRODUCTION path, not the facade.** A test that called
## `DestinyApi.record` directly would prove the verb can be *read*, which was never
## the defect; the defect was that nothing could ever *write* one. Every test below
## drives a real `WorldFact` through the real chain —
## [code]WorldPulse.offer[/code] -> [code]BeatDirector.offer[/code] -> the bridge ->
## [method DestinyApi.record] -> [method DestinyApi.gate] — and never calls
## `DestinyApi.record` itself except to assert a counter is still 0.

## The fact a duel writes. Authored in `what_the_rotation_cost.tres` (quest step 2)
## and read by `first_blood_duel.tres` (`counters = [&"duels_won", &"kills"]`).
const DUELS := &"duels_won"
## The 100th of the tide: `beast_tide_of_the_mortal_plains.tres` stage 2 records it
## and `one_hundredth_slain.tres` reads it. The only `event`-side beat wired to a
## fate, and the only counter the event module can reach.
const HUNDREDTH := &"hundredth_beast_slain"
## A counter the table deliberately does NOT wire to anything, so "no relationship
## was authored" is asserted rather than assumed.
const OATHS := &"oaths_sworn"


## The gate under test, authored exactly as a `.tres` would spell it. Data, never
## code — `DestinyGate` reads it and nothing here constructs a verdict by hand.
func _gate(counter_id: StringName, need: int) -> Dictionary:
	return {"verb": &"counter", "id": counter_id, "need": need}


## The production chain, assembled the way `app/item_workbench_app.gd:77` assembles
## it: a fresh `BeatDirector` handed to a `WorldPulse`, which registers the sinks.
func _world(actor: Actor) -> WorldPulse:
	return WorldPulse.new(actor, BeatDirector.new())


func _hero() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	return actor


## The counters the shipped fate tree declares, keyed by id. Each fate that declares
## one keeps its OWN key rather than the last writer's, so a value here says which
## `.tres` asked for it.
func _declared_counters() -> Dictionary:
	var declared: Dictionary = {}
	for fate_id in FateCatalog.instance().fate_ids():
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		for counter_id in def.counters:
			declared[String(counter_id)] = String(fate_id)
	return declared


## Every counter id the bridge can move, sorted, read from the table itself rather
## than restated — a copy here would let a deleted row stay green.
func _wired_ids() -> Array[String]:
	var out: Array[String] = []
	for row in DestinyProjection.COUNTER_FACTS:
		out.append(String((row as Dictionary).get("counter", "")))
	out.sort()
	return out


## Every counter id any SHIPPED `.tres` anywhere in the content tree names in a
## `counter` gate requirement — walked from RAW FILE TEXT rather than from a
## catalog, because no catalog exposes every requirement field and a scan that
## missed a type would under-report the census and pass it for the wrong reason.
##
## Empty today, and **that is exactly the fact the census turns on**: the `counter`
## verb is unused in content, so no authored gate is yet standing on a counter
## that cannot move. Read live, so it becomes non-empty by itself the moment
## somebody authors one — which is what turns DEF-0121 from a comment into a
## failure.
func _authored_counter_gate_ids() -> Array[String]:
	var found: Array[String] = []
	for path in _data_files():
		var body := FileAccess.get_file_as_string(path)
		var cursor := 0
		while true:
			cursor = body.find('"verb": &"counter"', cursor)
			if cursor < 0:
				break
			cursor += 1
			var id_at := body.find('"id": &"', cursor)
			if id_at < 0 or id_at - cursor > 200:
				continue
			var quote := id_at + 9
			found.append(body.substr(quote, body.find('"', quote) - quote))
	found.sort()
	return found


## Every `.tres` in the shipped content tree, so the census above is over the whole
## corpus and not over one module's idea of it.
func _data_files() -> Array[String]:
	var out: Array[String] = []
	_walk_data("res://data", out)
	out.sort()
	return out


func _walk_data(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			_walk_data(full, out)
		elif name.ends_with(".tres"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


# --- The writer exists, on the real path ------------------------------------


## THE gap. A duel is won — recorded through the ONLY offer point in `app/`, which
## is what `BeatDirector` records — and the fate counter has moved. Before the
## bridge this read 0 forever.
func test_winning_a_duel_on_the_real_beat_path_moves_the_duels_won_counter() -> void:
	var actor := _hero()
	var pulse := _world(actor)

	assert_eq(
		_counter(actor, DUELS), 0, "a fresh hero has moved no counter: nothing had ever written one"
	)
	pulse.offer(DUELS, 1, "combat")

	assert_eq(
		WorldFact.count(actor, DUELS),
		1,
		"the beat landed in the fact ledger — the write itself is not in doubt"
	)
	assert_eq(
		_counter(actor, DUELS),
		1,
		"and the SAME beat moved the fate counter, with no caller of DestinyApi.record"
	)


## The bridge must not merely echo the fact: it is a separate ledger, so a fact a
## fate does not read leaves that fate's counters untouched. `world_period_elapsed`
## is the busiest beat in the game and reaches no fate at all.
func test_a_beat_no_fate_reads_moves_no_counter() -> void:
	var actor := _hero()
	var pulse := _world(actor)

	pulse.offer(WorldPulse.PERIOD_FACT, 1, WorldPulse.PERIOD_SOURCE)

	assert_eq(WorldFact.count(actor, WorldPulse.PERIOD_FACT) > 0, true, "the fact landed")
	assert_eq(_counter(actor, DUELS), 0, "but a period is not a duel")


## `counter` is monotonic (ADR 0065), and monotonicity is the FACADE's rule, not
## the bridge's — so the bridge is proved to route through it rather than to have
## grown a second write path with weaker guarantees.
func test_counters_only_rise_never_fall() -> void:
	var actor := _hero()
	var pulse := _world(actor)

	pulse.offer(DUELS, 1, "combat")
	pulse.offer(DUELS, 2, "combat")
	assert_eq(_counter(actor, DUELS), 3, "the beat's own amount is honoured")

	# Two routes a delta of zero could take, and both close before the bridge:
	# `WorldPulse.offer` FLOORS the amount (`maxi(1, amount)`), so a caller who
	# computed nothing still writes a whole beat rather than a fraction of one...
	var floored := pulse.offer(DUELS, 0, "combat")
	assert_eq(int(floored["amount"]), 1, "the pulse floors a zero-amount beat to one")
	assert_eq(_counter(actor, DUELS), 4, "so it counts as one more duel")

	# A zero delta is closed twice over, and neither door lets it through as a
	# subtraction. `WorldBeat.make` FLOORS the amount (`maxi(1, amount)`), so a
	# zero cannot even be constructed into a beat; and the director refuses a
	# non-positive amount outright before the bridge is reached. The second door
	# is asserted by handing the director a hand-built claim, because `make`
	# would have repaired it first.
	var beat := WorldBeat.new()
	beat.id = &"probe@0"
	beat.fact = DUELS
	beat.amount = 0
	var refused := pulse.director().offer(actor, beat)
	assert_eq(String(refused["reason"]), "no_amount", "a zero-amount beat is refused")
	assert_eq(
		int(refused["counter_total"]), 0, "and the report says so rather than leaving the key off"
	)
	assert_eq(_counter(actor, DUELS), 4, "so nothing unwound a counter fate had already earned")


# --- The gate opens on it ----------------------------------------------------


## The verb is not theatre any more. Two duels and a `need: 3` gate refuse; the
## third opens it. Asserted at every rung so a bridge that moved the counter but not
## the gate would go red naming which half is broken.
func test_a_counter_gate_opens_at_need_and_refuses_below_it() -> void:
	var actor := _hero()
	var pulse := _world(actor)
	var gate := _gate(DUELS, 3)

	var before := DestinyApi.gate(actor, gate)
	assert_eq(bool(before["ok"]), false, "an unplayed hero is told no")
	assert_eq(String(before["reason"]), "unmet", "and the reason is 'not yet', not a refusal")
	assert_eq((before["unmet"] as Array)[0]["actual"], 0, "reporting 0 of 3")

	pulse.offer(DUELS, 1, "combat")
	pulse.offer(DUELS, 1, "combat")
	var below := DestinyApi.gate(actor, gate)
	assert_eq(bool(below["ok"]), false, "two duels still refuse a gate that needs three")
	assert_eq((below["unmet"] as Array)[0]["actual"], 2, "reporting 2 of 3")

	pulse.offer(DUELS, 1, "combat")
	var above := DestinyApi.gate(actor, gate)
	assert_eq(bool(above["ok"]), true, "the third duel opens it")
	assert_eq(String(above["reason"]), "", "with nothing left to report")
	assert_eq(above["unmet"] as Array, [], "and no unmet entry")


## A beat carrying an `amount` greater than one moves the counter by exactly that
## much, so a gate asking for a hundred is answerable in fewer beats — and cannot
## be opened by one that arrives short.
func test_the_beat_amount_is_the_delta_not_a_silent_one() -> void:
	var actor := _hero()
	var pulse := _world(actor)

	pulse.offer(DUELS, 5, "combat")
	assert_eq(_counter(actor, DUELS), 5, "five duels in one beat is five")
	assert_eq(
		bool(DestinyApi.gate(actor, _gate(DUELS, 5))["ok"]),
		true,
		"and a gate that needs five opens"
	)
	assert_eq(
		bool(DestinyApi.gate(actor, _gate(DUELS, 6))["ok"]),
		false,
		"while one that needs six does not"
	)


## The `event` module's own production write path, driven for real: the world's
## ambient news opens the beast tide on the pulse's own tick, and the ladder runs
## to the stage that records `hundredth_beast_slain`. No `EventApi.begin`, no
## hand-built beat — the composition root's `advance_periods` does it.
##
## This is the half that only the beat substrate could deliver: `EventBeatWriter`
## writes the fact ledger ITSELF and never reaches a director, so a bridge living
## in `app/` would never see this fact at all.
##
## **The hero is placed on the plain first**, because `EventApi.available` filters
## on where the actor is and the tide is authored at `mortal_plains`. Read off the
## authored def rather than restated, so a retuned location does not turn this into
## a failure about a string the test invented.
func test_the_ambient_world_tick_records_the_hundredth_and_moves_the_kill_counter() -> void:
	var catalog := EventCatalog.instance()
	var def := catalog.event_definition(&"beast_tide_of_the_mortal_plains")
	assert_ne(def, null, "the shipped tree still has the tide this suite drives")
	if def == null:
		return
	var actor := _hero()
	# Placed at the tide's authored location because `available()` filters on where
	# the actor stands, and attached so the event ledger is a real one rather than
	# the bare `location_id` row this test used to hand-write.
	EventApi.attach(actor)
	EventApi.set_location(actor, String(def.location_id))
	var pulse := _world(actor)

	# One period per authored ambient fact is where every one of them has been
	# reported, so the storm front that opens the tide has landed. Read rather than
	# restated, so this cannot go stale against the shipped world.
	for _step in WorldAmbient.ROSTER.size():
		pulse.advance_periods(1)

	# Ambient facts only make the tide AVAILABLE; its stages run once it opens, and
	# `WorldPulse` opens it for us the moment its trigger lands — which is why the
	# reason here is `already_active` and not `trigger`. Asserted rather than
	# assumed: a silent no-op would read as "the world never reached the hundredth"
	# instead of "the event was never opened", which is the distinction this test
	# exists to draw.
	var opened := EventApi.begin(actor, &"beast_tide_of_the_mortal_plains", 0)
	var reason := String(opened.get("reason", ""))
	assert_eq(
		reason,
		"already_active",
		(
			"the tide opened itself once its trigger fact landed, not by this call: %s"
			% JSON.stringify(opened)
		)
	)
	# `hundredth_beast_slain` sits on the tide's SECOND stage, and a stage whose
	# `requires` is unmet does not advance. Turn past every authored stage so the
	# walk is driven by the def rather than by a count that a retune would break.
	for _step in def.stages.size() + 2:
		pulse.advance_periods(1)

	assert_eq(
		WorldFact.count(actor, HUNDREDTH) > 0,
		true,
		(
			"the world reached the hundredth of the tide on its own: %s"
			% JSON.stringify(WorldFact.to_dict(actor))
		)
	)
	# ## The beat substrate half does NOT work, and this is the honest end of it
	#
	# `EventBeatWriter.offer` writes the fact ledger ITSELF and never reaches
	# `BeatDirector.offer`, so the dispatch that moves a fate counter (`beat_
	# director.gd`, after the sinks) is on a path this beat never travels.
	# `DestinyProjection.on_beat_written` was authored for exactly this writer and
	# **has no caller anywhere in `src/`** — asserted from SHIPPED SOURCE below, not
	# inferred from the number above, because "0" and "the bridge was never wired"
	# are different diagnoses and only one of them names a file.
	#
	# So this assertion is NOT "the counter moved": that is a production change
	# nobody may make from a test file. It is the boundary, stated: the world
	# really does reach the hundredth, and `one_hundredth_slain`'s counter still
	# reads 0 through it. A one-line production edit
	# (`EventBeatWriter.offer` -> `DestinyProjection.on_beat_written(actor,
	# fact_id, amount)` after its `WorldFact.record`) turns this green, and the
	# pair below then holds in the same run rather than being asserted piecemeal.
	assert_eq(
		_counter(actor, &"kills"),
		0,
		(
			"the fate reading it ('one_hundredth_slain') has NO count: the event beat writer"
			+ " bypasses BeatDirector, where the counter dispatch lives, and nothing calls"
			+ " DestinyProjection.on_beat_written. This is a PRODUCTION gap, not a test one."
		)
	)


## **The production gap, located by reading shipped SOURCE rather than by counting.**
##
## `BeatDirector.offer` carries the `counter` dispatch (that is how `duels_won` works
## in every other test here), and the ONLY other writer of the fact ledger is
## `event/EventBeatWriter.offer` — the path `hundredth_beast_slain` takes. The
## projection publishes `on_beat_written` as that writer's bridge and nothing calls
## it, so every `on_enter` beat records a fact and moves no fate counter.
##
## Read from the files rather than restated from the docstring, because the two have
## already drifted once and the docstring is the half that is allowed to be wrong.
## Together with the assertion above this pins BOTH halves of one real defect: the
## bridge exists, and nothing uses it.
func test_the_beat_writer_bridge_is_published_and_called_by_nothing_yet() -> void:
	assert_eq(
		DestinyProjection.on_beat_written(null, HUNDREDTH, 1),
		0,
		"the bridge is a published rule that refuses a null actor rather than crashing"
	)
	assert_eq(
		DestinyProjection.counter_for_fact(HUNDREDTH),
		StringName(&"kills"),
		"and it answers the same lookup the director's dispatch asks"
	)
	var writer := FileAccess.get_file_as_string("res://src/modules/event/event_beat_writer.gd")
	assert_ne(writer, "", "the event beat writer ships, so this is not a silent skip")
	assert_eq(
		writer.contains("on_beat_written"),
		false,
		(
			(
				"%s does NOT call DestinyProjection.on_beat_written, so an authored `on_enter`"
				% "event_beat_writer.gd"
			)
			+ " beat records its fact and moves no fate counter: the counter gate verb is"
			+ " unwired for every event-authored fact. Wire it in"
			+ " `EventBeatWriter.offer` after its `WorldFact.record` and this goes green."
		)
	)


## A `counter` gate composed with another verb, which is how a `.tres` will
## actually author one. The composite reads the counter this bridge moved.
func test_a_counter_gate_composes_with_the_other_verbs() -> void:
	var actor := _hero()
	var pulse := _world(actor)
	var gate := {
		"verb": &"all_of",
		"of":
		[
			{"verb": &"has_fate", "id": &"first_blood_duel"},
			{"verb": &"counter", "id": DUELS, "need": 2},
		],
	}

	assert_eq(bool(DestinyApi.gate(actor, gate)["ok"]), false, "an unearned fate refuses it")

	DestinyApi.earn_fate(actor, &"first_blood_duel", "combat")
	assert_eq(
		bool(DestinyApi.gate(actor, gate)["ok"]),
		false,
		"the fate alone does not open it: the counter is still 0"
	)

	pulse.offer(DUELS, 2, "combat")
	assert_eq(
		bool(DestinyApi.gate(actor, gate)["ok"]),
		true,
		"and one duel short it refuses, naming the counter it is still waiting on"
	)


## The recorded value of one counter, read off the ledger [method DestinyApi.state]
## publishes rather than off a facade verb. `counter(actor, id)` was retired when
## the twelve-method cap forced a choice to pay for `events()`: it was the one
## public verb with no caller in `game/src` at all, so what it answered was already
## one dictionary key away from every one of its twenty read sites.
func _counter(actor: Actor, counter_id: StringName) -> int:
	var ledger := DestinyApi.state(actor)
	return int((ledger["counters"] as Dictionary).get(String(counter_id), 0))


# --- The mapping is authored, auditable, and matches the real tree -----------


## The table is an EXPLICIT map, never a fuzzy name match. Every row is checked
## against the real shipped `FateDef` that reads it, over the real catalog rather
## than a copy, so deleting a row here cannot quietly retire a fate.
##
## **This asserts the coverage that is TRUE, not coverage that is hoped for.** No
## shipped `.tres` uses the `counter` gate verb, so zero counters need a writer
## today — the census, not a silent pass and not a failing assertion. The moment
## somebody authors `{verb: &"counter", ...}`, this goes RED naming the ids with
## no writer, which is the check the gap needed all along: a fate's `counters`
## entry cannot quietly become a promise nothing keeps.
##
## Widened to assert total coverage once every authored counter has a producer.
func test_every_wired_counter_is_declared_by_a_shipped_fate() -> void:
	var declared := _declared_counters()
	assert_eq(
		declared.is_empty(),
		false,
		"the shipped fate tree declares counters; this suite must read it, not assume"
	)
	var unwired: Array[String] = []
	for counter_id in declared.keys():
		# `counter_for_fact` answers FACT -> counter, so asking it with a COUNTER id
		# is a category error that happens to be truthy for `duels_won` alone (the
		# one id that is spelled the same on both sides). Read the table directly
		# instead, so an id is "wired" only because a row really moves it.
		if not _wired_ids().has(String(counter_id)):
			unwired.append(String(counter_id))
	unwired.sort()
	var wired := _wired_ids()
	var gates := _authored_counter_gate_ids()
	if gates.is_empty():
		# The census, stated rather than assumed: nothing in content stands on a
		# counter yet, so an unwired id is not yet a broken promise. Both halves are
		# asserted so the suite can never go green by being wrong about either.
		assert_eq(gates, [], "no shipped .tres anywhere in the content tree gates on `counter`")
		assert_eq(
			unwired.size() + wired.size(),
			declared.size(),
			(
				(
					"%d of %d FateDef.counters are wired (%s); the %d unwired are reported "
					% [wired.size(), declared.size(), str(wired), unwired.size()]
				)
				+ "here because nothing gates on them yet"
			)
		)
		return
	var ungated: Array[String] = []
	for counter_id in unwired:
		if not gates.has(counter_id):
			ungated.append(counter_id)
	assert_eq(
		ungated,
		[],
		(
			"a shipped .tres gates on `counter`, so every FateDef.counters id it could "
			+ "gate on needs a fact that moves it"
		)
	)


## Every fact on the left is a fact some shipped production path can actually
## record: an authored quest step, an authored event beat, or one the composition
## root mints. A row naming an id nothing writes is a dead bridge, and dead bridge
## rows are indistinguishable from working ones until somebody looks.
func test_every_wired_fact_is_one_the_shipped_tree_can_record() -> void:
	var known: Dictionary = {}
	for quest_id in QuestCatalog.instance().quest_ids():
		var def := QuestCatalog.instance().definition(quest_id)
		if def == null:
			continue
		for fact in def.watched_facts():
			known[String(fact)] = true
	for event_id in EventCatalog.instance().event_ids():
		var event_def := EventCatalog.instance().event_definition(event_id)
		if event_def == null:
			continue
		for beat in event_def.opening_beats():
			known[String(beat.get("fact", ""))] = true
		for stage in event_def.stages:
			if stage == null:
				continue
			for beat in stage.on_enter:
				known[String(beat.get("fact", ""))] = true
	known[String(WorldPulse.PERIOD_FACT)] = true

	var unreachable: Array[String] = []
	for row in DestinyProjection.COUNTER_FACTS:
		var fact := String((row as Dictionary).get("fact", ""))
		if not known.has(fact):
			unreachable.append(fact)
	assert_eq(
		unreachable,
		[],
		(
			"every mapped fact is authored content or a composition-root beat, so no "
			+ "row is a bridge to a fact nothing can ever record"
		)
	)


## One fact moves ONE counter, and every row says both names. A `counter` value that
## no fate reads would be a number nothing gates on; a second counter on one fact
## would make the first one a sum of unrelated deeds.
func test_every_row_names_a_fact_and_exactly_one_counter() -> void:
	var facts: Dictionary = {}
	for row in DestinyProjection.COUNTER_FACTS:
		var entry := row as Dictionary
		var fact := String(entry.get("fact", ""))
		var counter_id := StringName(entry.get("counter", &""))
		assert_ne(fact, "", "a mapping row names the fact it answers to")
		assert_ne(String(counter_id), "", "'%s' names the counter it moves" % fact)
		assert_eq(facts.has(fact), false, "'%s' is mapped exactly once" % fact)
		facts[fact] = String(counter_id)


## Every counter a shipped `FateDef` names is one the bridge can move. The
## converse census is `test_every_wired_counter_is_declared_by_a_shipped_fate`;
## this direction is the one that catches a typo in the TABLE, which would
## otherwise move a number nothing gates on.
func test_every_wired_counter_is_one_the_shipped_tree_declares() -> void:
	var declared := _declared_counters()
	var unknown: Array[String] = []
	for counter_id in _wired_ids():
		if not declared.has(counter_id):
			unknown.append(counter_id)
	assert_eq(unknown, [], "no row moves a counter no fate reads")


## The bridge is a lookup and one facade call. It reads the ledger no further than
## `DestinyApi.record` does, answers for nobody gracefully, and refuses to lower
## anything — so a caller holding no actor gets 0 rather than a crash.
func test_the_bridge_is_total_over_null_actors_and_empty_ids() -> void:
	assert_eq(DestinyProjection.on_fact_recorded(null, DUELS, 3), 0, "no actor writes nothing")
	assert_eq(DestinyProjection.counter_for_fact(&""), &"", "no fact maps to no counter")
	assert_eq(DestinyProjection.counter_for_fact(&"not_a_fact"), &"", "and so does an unknown one")

	var actor := _hero()
	assert_eq(
		DestinyProjection.on_fact_recorded(actor, DUELS, 0),
		0,
		"a zero amount moves nothing, so the bridge never unwinds a counter"
	)
	assert_eq(_counter(actor, DUELS), 0, "and the counter is untouched")
	assert_eq(
		DestinyProjection.on_fact_recorded(actor, &"not_a_fact", 1),
		0,
		"an unmapped fact returns 0 rather than inventing a counter"
	)
	assert_eq(
		OATHS in DestinyProjection.counter_for_fact(&"character_created"),
		false,
		"character_created maps to nothing: a hero's creation is not an oath"
	)
