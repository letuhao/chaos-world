extends TestCase

## ## The gap this file closes
##
## `DestinyProjection.COUNTER_FACTS` maps eight world-fact ids onto fate counter ids,
## and the bridge that feeds them is installed by the composition root
## (`app/item_workbench_app.gd`). The `counter` gate verb therefore **works**, and its
## inputs are **live** — as of 2026-10-05 the whole counter path runs in production.
##
## And no `.tres` anywhere in `game/data/` used it. Not one authored gate stood on a
## counter, so the verb was live-in-code and dead-in-content: the mapping, the bridge,
## the monotonic write and the `DestinyGate._counter` evaluator were all exercised only
## by tests that hand-built their own ledger. A defect in the bridge, or a row deleted
## from `COUNTER_FACTS`, would have been invisible to every authored gate — there was
## not one to go shut.
##
## `the_tally_of_a_man_who_kept_count.tres` is that missing authored gate. It carries
## `{"verb": &"counter", "id": &"duels_won", "need": 3}` inside an `all_of` with a
## `has_fate` half, and this file is the pair of claims that make it mean something.
##
## ## WHAT THIS FILE ASSERTS, AND WHY IT IS TWO CLAIMS
##
##  1. **The gate I authored is REACHABLE.** Every fact behind it has a producer that
##     exists in `game/src` today, checked by NAME against the real files rather than
##     against this file's belief about them.
##  2. **A counter gate on an UNPRODUCED id would be a gate that can never open**, and
##     the refusal is visible rather than silent.
##
## Claim 2 is the one that keeps claim 1 honest. A gate's reachability is a property of
## the PRODUCER, not of the `.tres`, so a test that only asserted "my gate's fact is
## produced" would pass unchanged if somebody deleted the producer and re-ran it —
## no, it would NOT: it would go red, which is exactly the point, and that is asserted
## below by asking the same predicate a question about a fact with no producer.
##
## ## WHY `duels_won`, and WHY NOT THE OTHER FOUR
##
## `duels_won` is one of five `COUNTER_FACTS` facts with a proven live producer.
## It is also the one whose producer is reachable through a verb a player can actually
## perform in normal play — `CombatApi.hit`, the module's own blow verb, which lands a
## killing blow and calls `_record_win`. The other four are `third_man_spared`
## (`CombatApi.spare`), `household_heir_registered` (`ClanHeir.register`),
## `oaths_discharged` (`SectDuty.serve`, by its recorded AMOUNT rather than by one
## call) and `hundredth_beast_slain` (the event ladder, reached only through the
## composition root's own world tick). All five are legitimate; `duels_won` is chosen
## because its chain is the shortest and needs no fixture catalog to drive.
##
## ## THE THREE THAT MUST NEVER BE GATED ON
##
## `bound_name_called`, `mountain_circled_once` and `vigil_broken` are rows in
## `COUNTER_FACTS` with **no producer anywhere in `game/src` and no authored beat**.
## Their counters read 0 forever. Gating on one produces a `.tres` that validates
## clean, shows in the journal, and can never open — the exact defect DEF-0121 /
## DEF-0181 recorded before the bridge was wired, and the shape a gate has when the
## machinery is green and the content is not.
##
## `test_destiny_counter_mapping_census.gd` already holds the named census of those
## three. This file does not restate it: it reads the SAME census through the shared
## support file, so the claim lives in one place, and adds the half the census cannot
## make — that a gate standing on one of them is **detectable**.

## The shared fixtures and readers, in the one file both halves of this pair read, so
## "what does the shipped tree produce" has one answer rather than two that could drift.
const Support := preload("res://tests/modules/destiny/destiny_counter_wiring_support.gd")

## The gate this suite exists to have been authored on. Named here so a rename fails
## the test that is ABOUT the gate rather than silently reducing the coverage.
const GATED_QUEST := &"the_tally_of_a_man_who_kept_count"
## The counter row inside it. Read from the gate at run time rather than restated, so
## this file cannot disagree with the `.tres` it is claiming to check.
const GATED_COUNTER := &"duels_won"
const GATED_NEED := 3

## The counter id each dead fact maps to, held as a NAMED list
##
## Stated rather than derived from the table on the same line it checks, so a row edited
## from `severances` to something else is a named failure here and not a silently
## different — but still unopenable — gate elsewhere. Read off
## `DestinyProjection.COUNTER_FACTS` as shipped on 2026-10-05, and SORTED, because the
## assertion sorts what it compares and an unsorted expectation is a failure that reads
## like a defect in the thing being checked.
const UNPRODUCED_COUNTERS := ["heaven_marks", "severances", "watch_turned"]

## **A preloaded script cannot hand out its instance members.** `Support` is a script
## constant, and `Support._authored_counter_gate_ids()` does not resolve: a script object
## exposes the class's STATIC surface, so an instance method reached through one answers
## "cannot find member". The shared readers are therefore bound from ONE instance held
## by the suite, and bound inside `setup()` — the runner attaches a suite's properties
## one at a time, so a `const` initialiser that dereferences `Support` answers `null`.
static var _support: RefCounted = null

var _counter_impl: Callable
var _wired_ids_impl: Callable
var _authored_fact_ids_impl: Callable
var _module_owned_facts_impl: Callable
var _unproduced_facts_impl: Callable
var _authored_counter_gate_ids_impl: Callable
var _names_in_code_impl: Callable

## The baseline this suite's own `teardown()` is measured against, read HERE rather than
## asserted to be zero: `WorldFact._subscribers` is process-wide state this suite does
## not own, so only a DELTA is observable.
var _baseline_subscribers: int = 0


## Install the bridge for ONE test and prove it is live.
##
## Without it every counter below reads 0 forever and the whole file is green on a build
## where the production chain is severed — which is the precise shape DEF-0121 took.
## `WorldFact.subscribe` refuses a duplicate and a callable that resolved to nothing
## would be accepted just as quietly, so the install is ASSERTED rather than assumed.
func setup() -> void:
	# Bound BEFORE the bridge goes in, so a reader that could not be bound fails this
	# case by name instead of surfacing as a `null` answer a census three lines on.
	_bind_support()
	_baseline_subscribers = WorldFact.subscriber_count()
	DestinyProjection.subscribe_to_fact_ledger()
	assert_eq(
		WorldFact.has_subscriber(Callable(DestinyProjection, "on_fact_recorded")),
		true,
		(
			"the fact->counter bridge is LIVE for this test: the authored gate below is read "
			+ "through it, so a false here names the wiring rather than a zero counter"
		)
	)


## Leave the process exactly as this suite found it — a DELTA back to the count `setup()`
## recorded, never `0`, because a sibling suite may legitimately hold a subscriber of its
## own. Only the bridge THIS suite installed is removed, by identity.
func teardown() -> void:
	DestinyProjection.unsubscribe_from_fact_ledger()
	assert_eq(
		WorldFact.subscriber_count(),
		_baseline_subscribers,
		(
			"the bridge is REMOVED again and the slot is back to the count this test found: "
			+ "the runner shares one process, and a subscriber left behind moves counters for "
			+ "every later suite"
		)
	)


func _shared() -> RefCounted:
	if _support == null:
		_support = Support.new()
	return _support


func _bind_support() -> void:
	var shared: RefCounted = _shared()
	_counter_impl = shared._counter
	_wired_ids_impl = shared._wired_ids
	_authored_fact_ids_impl = shared._authored_fact_ids
	_module_owned_facts_impl = shared._module_owned_facts
	_unproduced_facts_impl = shared._unproduced_facts
	_authored_counter_gate_ids_impl = shared._authored_counter_gate_ids
	_names_in_code_impl = shared._names_in_code


## The recorded value of one counter, read off the ledger `DestinyApi.state` publishes
## rather than off a facade verb — `counter(actor, id)` was retired at the facade's
## twelve-method cap precisely to pay for `events()`.
func _counter(actor: Actor, counter_id: StringName) -> int:
	return _counter_impl.call(actor, counter_id)


# --- 1. the authored gate exists, and is a real counter gate ------------------


## ## The `.tres` really is there, and really does gate on `counter`
##
## Asserted from the shipped catalogs rather than from this file's constants, because a
## test that read its own expectation would pass on a tree where the quest had been
## deleted, renamed, or edited to gate on nothing. The gate row is read OFF the loaded
## `QuestDef`, so it is the CONTENT's row and not a restatement of it.
func test_the_authored_gate_is_a_counter_requirement_in_shipped_content() -> void:
	var def := QuestCatalog.instance().definition(GATED_QUEST)
	assert_ne(def, null, "%s.tres ships, so the counter gate is live in content" % GATED_QUEST)
	if def == null:
		return
	var counters := _counter_verbs_in(def.requirement)
	assert_eq(
		counters,
		[str(GATED_COUNTER)],
		(
			(
				"the authored gate names exactly one counter verb, on '%s'. A gate whose counter "
				% String(GATED_COUNTER)
			)
			+ "row could not be found here is a gate nothing can be said to open"
		)
	)
	assert_eq(
		_counter_need_in(def.requirement, GATED_COUNTER),
		GATED_NEED,
		"and it asks for exactly the need this suite was written against"
	)
	# The composition half, asserted because a gate that were ONLY a counter would be a
	# different claim: `all_of` means the fate is required AND the count, which is the
	# shape `test_destiny_counter_production_wiring.gd` describes as "how a `.tres` will
	# actually author one".
	assert_eq(
		StringName(def.requirement.get("verb", &"")),
		&"all_of",
		"and it is composed, so the counter is half of a gate rather than the whole of one"
	)


## Every `counter` id `requirement` names, at any depth, sorted. A reader rather than a
## top-level `get`, because the authored row is nested inside `all_of` and a gate author
## is allowed to compose.
func _counter_verbs_in(requirement: Dictionary) -> Array[String]:
	var out: Array[String] = []
	_walk_counters(requirement, out)
	out.sort()
	return out


func _walk_counters(requirement: Dictionary, out: Array[String]) -> void:
	if requirement.is_empty():
		return
	if StringName(requirement.get("verb", &"")) == &"counter":
		out.append(String(requirement.get("id", "")))
		return
	for child in requirement.get("of", []) as Array:
		if child is Dictionary:
			_walk_counters(child as Dictionary, out)


## The `need` beside `counter_id` anywhere inside `requirement`, or 0 when absent.
func _counter_need_in(requirement: Dictionary, counter_id: StringName) -> int:
	if requirement.is_empty():
		return 0
	if StringName(requirement.get("verb", &"")) == &"counter":
		if StringName(requirement.get("id", &"")) == counter_id:
			return int(requirement.get("need", 1))
		return 0
	for child in requirement.get("of", []) as Array:
		if child is Dictionary:
			var found := _counter_need_in(child as Dictionary, counter_id)
			if found > 0:
				return found
	return 0


# --- 2. the gate is REACHABLE: its fact has a producer ------------------------


## ## Would this test go RED if the producer disappeared? Yes — and this is the proof.
##
## The claim the next two cases make is that `duels_won` is a fact the shipped tree can
## actually record. It is checked three ways, because no single one of them can fail for
## the right reason on its own:
##
##  - by NAME against the real writer file, with the comment half stripped, so a file
##    that merely DISCUSSES the fact is not counted as producing it. This is the leg
##    that goes red the moment `_record_win` stops calling `CombatFacts.record_duel_won`.
##  - by NAME against that writer's CALLER, because a module holding a verb is not a
##    chain; `duel_hit.gd` invoking it on a killing blow is.
##  - by RUNNING the producer, through `CombatApi.hit`, and reading the counter off the
##    ledger the module's own bridge moved. This is the leg that goes red the moment the
##    bridge stops being installed by the composition root.
##
## A `.tres` is data and cannot prove any of them. A test asserting only "my gate's id is
## in `COUNTER_FACTS`" would stay green on a build where nothing can move that counter —
## which is the whole defect class this file was written to close, and the reason the
## bridge install is asserted in `setup()` rather than assumed.
func test_the_gated_counter_has_a_live_producer_in_the_shipped_tree() -> void:
	# Which fact moves the counter this gate stands on, read off the TABLE rather than
	# restated: the gate says `duels_won`, and `duels_won` is both a fact id and a
	# counter id (it is the one id spelled the same on both sides), so asserting the
	# direction rather than the value is what makes the claim checkable.
	var wired: Array[String] = _wired_ids_impl.call()
	assert_eq(
		wired.has(String(GATED_COUNTER)),
		true,
		"the gate's counter is one the bridge can move at all: COUNTER_FACTS wires %s" % str(wired)
	)

	# Reachable, part one: the shipped writer names the FACT in a line of code. Read from
	# the file, comments stripped, because `combat_facts.gd`'s own docstring discusses
	# ids it does not produce and a suite that believed prose would stay green.
	var writer := "res://src/modules/combat/combat_facts.gd"
	var body := FileAccess.get_file_as_string(writer)
	assert_ne(body, "", "%s ships, so this is not a silent skip" % writer)
	assert_eq(
		_names_in_code_impl.call(body, String(GATED_COUNTER)),
		true,
		(
			(
				"%s names '%s' in a line of code, so the fact this gate reads has a producer that "
				% [writer, String(GATED_COUNTER)]
			)
			+ "is not just a row in a table"
		)
	)

	# Reachable, part two: the CALLER of that writer. `combat_facts.gd` holding a verb is
	# not the chain; `duel_hit.gd` calling it on a killing blow is. Checked by name so a
	# deletion of `_record_win` is a named failure rather than a vanishing counter.
	var caller := "res://src/modules/combat/duel_hit.gd"
	var caller_body := FileAccess.get_file_as_string(caller)
	assert_ne(caller_body, "", "%s ships" % caller)
	assert_eq(
		_names_in_code_impl.call(caller_body, "CombatFacts.record_duel_won"),
		true,
		(
			"%s calls CombatFacts.record_duel_won, so the fact is written on the path a " % caller
			+ "player's killing blow takes rather than only from a verb nothing calls"
		)
	)


## The gate OPENS, on a counter moved by a real production writer.
##
## `CombatApi.hit` is `combat`'s own blow verb, and the duel is fought to a kill rather
## than recorded by hand — the same two reasons
## `test_destiny_counter_production_wiring.gd` gives for driving it rather than calling
## `CombatFacts.record_duel_won` directly. The `need` asked of the gate is read off the
## authored `.tres`, so a retune of the content goes green by itself and this file
## cannot claim a gate that no longer exists.
func test_the_authored_gate_opens_on_real_duels_and_refuses_below_its_need() -> void:
	var def := QuestCatalog.instance().definition(GATED_QUEST)
	assert_ne(def, null, "the authored gate is still in the shipped content tree")
	if def == null:
		return
	var need := _counter_need_in(def.requirement, GATED_COUNTER)
	assert_eq(need, GATED_NEED, "and it still asks for the need this case fights duels for")

	var victor := Actor.new(&"challenger", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	victor.attach_core_resources()
	DestinyApi.attach(victor)

	# The fate half of the composed gate, earned through the facade as ADR 0134 §1a
	# requires — earn, then VERIFY, because a refused earn returns the ledger unchanged
	# and carries no `ok` of its own.
	DestinyApi.earn_fate(victor, &"first_blood_duel", "combat")
	assert_eq(
		DestinyApi.has_fate(victor, &"first_blood_duel"),
		true,
		"the gate's has_fate half is held, earned and then VERIFIED per ADR 0134 §1a"
	)

	assert_eq(
		bool(DestinyApi.gate(victor, def.requirement)["ok"]),
		false,
		"the composed gate refuses a hero who has the fate and none of the duels"
	)

	for round in GATED_NEED:
		assert_eq(
			_fight_to_a_kill(
				victor,
				Actor.new(StringName("ward_%d" % round), {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
			),
			true,
			"duel %d was decided by a killing blow" % round
		)

	assert_eq(
		_counter(victor, GATED_COUNTER),
		GATED_NEED,
		(
			"and the SAME occurrences moved the authored gate's counter, through the shipped "
			+ "combat verb and the module's own bridge"
		)
	)
	assert_eq(
		bool(DestinyApi.gate(victor, def.requirement)["ok"]),
		true,
		"so the authored gate OPENS: the counter path is live in content, not only in tests"
	)


## Swing until the ward is down. A bounded loop with a named stall, never an unbounded
## one — `tests/arch_rules/test_no_unbounded_wait.gd` fails the build on the other shape,
## and the bound is a CONSTANT taken before the walk so the body never moves it.
func _fight_to_a_kill(actor: Actor, opponent: Actor) -> bool:
	opponent.attach_core_resources()
	for blow in Support.BLOW_CAP:
		var result := CombatApi.hit(actor, opponent, Support.SEED + blow)
		if String(result["reason"]) != "":
			return false
		if bool(result["defender_slain"]):
			return true
	return false


# --- 3. the gate that could never open is DETECTABLE -------------------------


## ## The second half of the pair, and the reason the first half means anything
##
## Three ids are wired in `COUNTER_FACTS` and produced by NOTHING: they read 0 forever,
## and a `.tres` gating on one is a journal entry that can never open. That is DEF-0121
## in content form, and `test_destiny_counter_mapping_census.gd` holds the named census
## of them — this file does not restate that list, it READS it through the same support
## file, so the claim lives in one place.
##
## What is asserted here is the half the census cannot make: **that a gate standing on
## one of them would be REFUSED, and would stay refused no matter how much play the
## hero gets.** The census's `test_the_unproduced_rows_are_named_so_the_census_cannot_grow_quietly`
## already holds the named list; it does not evaluate a gate, because a gate needs an
## actor and that suite reads the tree rather than the ledger.
##
## This case asks the REAL evaluator, through the REAL bridge, with the bridge installed
## and asserted live. That is the only way to distinguish "the requirement is malformed"
## from "the requirement is well-formed and describes a number nothing can raise" — and
## the second is the one an author would ship, because `data audit` validates the
## SHAPE of a gate and never whether it can open.
##
## **`tools/data.py` now owns the authoring-time half of this** and did not when this
## file was written: `_destiny_findings` walks the authored counter gates, and when at
## least one exists it upgrades its census note from "No shipped .tres gates on `counter`
## yet, so none of these cost a player a door" to "Shipped gates DO stand on counters,
## so an unproduced fact is a closed door rather than a dormant row." This `.tres` is
## what flipped that branch. What `data audit` cannot do — and what is therefore
## asserted here — is decide reachability at authoring time, because that needs the
## producer set, which lives in `game/src` and moves every time a module ships a verb.
func test_the_three_unproduced_ids_are_exactly_the_ones_a_gate_must_never_name() -> void:
	var unproduced: Array = _unproduced_facts_impl.call()
	assert_eq(
		unproduced,
		["bound_name_called", "mountain_circled_once", "vigil_broken"],
		(
			(
				(
					"exactly three rows in COUNTER_FACTS name a fact nothing in the shipped tree "
					+ "can record: %s. They read 0 forever, and a gate on one of them is a quest "
				)
				% str(unproduced)
			)
			+ (
				"that validates clean, shows in the journal and can never open. When one lands, "
				+ "delete it from UNPRODUCED in the same change that adds the producer."
			)
		)
	)
	# And the claim is about the ids themselves, not just their count: every one of them
	# really does appear as a `fact` in the shipped mapping table.
	var facts: Dictionary = {}
	for row in DestinyProjection.COUNTER_FACTS:
		facts[String((row as Dictionary).get("fact", ""))] = String(
			(row as Dictionary).get("counter", "")
		)
	for dead in unproduced:
		assert_eq(
			facts.has(String(dead)),
			true,
			"'%s' is a real row of COUNTER_FACTS, not a name this suite invented" % String(dead)
		)


## ## A counter gate on an unproduced fact WOULD be refused — asserted, not assumed
##
## The counter is the thing the gate would read, and for a dead row the bridge maps the
## fact to a counter that therefore never moves. So the gate refuses, with the ordinary
## `unmet` verdict rather than a `malformed` one: the row is perfectly well formed, it
## simply describes a counter no occurrence can raise.
##
## Asserted for all THREE, not one, because a check that names a single id is a check
## that passes when the other two are gated on by mistake. And it is asserted through the
## REAL gate evaluator, so the verdict shape is the module's own and not a hand-built
## claim.
func test_a_counter_gate_on_an_unproduced_fact_refuses_and_can_never_open() -> void:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(actor)
	actor.attach_core_resources()

	# The control, first: a fact the shipped tree DOES produce moves its counter through
	# this same bridge, on this same actor. Without it the three dead rows below could be
	# satisfied by a bridge that is installed but silently broken — which is the exact
	# state DEF-0121 recorded, and the one that made the old content's gates theatre.
	assert_eq(
		WorldFact.record(actor, GATED_COUNTER, 1)["ok"],
		true,
		"a produced fact lands in the world ledger, and the subscriber fires from there"
	)
	assert_eq(
		_counter(actor, GATED_COUNTER),
		1,
		"and the SAME write moved its counter through the live bridge"
	)
	# A second actor, untouched by the write above, so the next three assertions are read
	# off a ledger nothing has written.
	var bare := Actor.new(&"bare", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	DestinyApi.attach(bare)

	for dead in _unproduced_facts_impl.call():
		var counter_id := DestinyProjection.counter_for_fact(dead)
		assert_ne(
			String(counter_id),
			"",
			(
				(
					"'%s' is mapped to a counter, which is exactly what makes gating on it look "
					% String(dead)
				)
				+ "reasonable: the mapping is real. The fact behind it is what is missing."
			)
		)
		# Nothing in `game/src` records this fact, so nothing ever reaches the bridge with
		# it. `WorldFact.record` is the ONE verb that writes the fact ledger — its own
		# docstring claims it, and `tests/arch_rules/test_fact_ledger_writers.gd` pins the
		# writer set by exact equality — so "no writer records the fact" IS "the counter
		# cannot move", with no step between the two claims.
		#
		# Asked of the census's own two readers and not of a literal scan: every shipped
		# writer passes its id as a same-file `const` (`CombatFacts.FACT_DUELS_WON` and not
		# `&"duels_won"`), because `tools/gate_reach.py` resolves a code-owned producer only
		# from a `const NAME := &"id"` in the same file. A grep for the literal would
		# therefore find the string in NO writer at all, produced or not, and would "pass"
		# `duels_won` for the wrong reason. The census reads the modules' own consts, which
		# is what makes the negative a measurement rather than a spelling accident.
		assert_eq(
			(
				_authored_fact_ids_impl.call().has(String(dead))
				or _module_owned_names().has(String(dead))
			),
			false,
			(
				(
					"'%s' is neither an authored event beat nor a fact a named module producer "
					% String(dead)
				)
				+ "records, so the bridge is never reached with it and the counter it feeds "
				+ "can never move"
			)
		)
		assert_eq(
			_counter(bare, counter_id),
			0,
			"so on a ledger nothing has written it reads 0, and the gate cannot be satisfied"
		)
		var verdict := DestinyApi.gate(bare, {"verb": &"counter", "id": counter_id, "need": 1})
		assert_eq(
			bool(verdict["ok"]),
			false,
			"so a {verb: counter} gate on '%s' refuses" % String(counter_id)
		)
		assert_eq(
			String(verdict["reason"]),
			"unmet",
			(
				"and it refuses as UNMET rather than as malformed: the requirement is "
				+ "well-formed, it just names a number nothing can raise"
			)
		)
		assert_eq(
			String((verdict["unmet"] as Array)[0]["id"]),
			String(counter_id),
			"and the unmet entry names the counter it is still waiting on"
		)


## Every fact id a named module producer claims, keyed by id. Read from the support
## file's roster, which takes each id off the owning module's own `const` — so a rename
## in a module changes this answer without a line here changing.
func _module_owned_names() -> Dictionary:
	var out: Dictionary = {}
	for entry in _module_owned_facts_impl.call():
		out[String((entry as Dictionary).get("fact", ""))] = true
	return out


## The dead rows map to exactly these counters, and to no others. A stronger claim than
## "each dead row maps to some counter", and the one that would catch a well-meaning
## author wiring `vigil_broken` to something reachable — which would make the gate OPEN
## and make the fate mean the wrong deed, which is the reason
## `DestinyProjection.COUNTER_FACTS` says of itself: "Never a fuzzy name match."
func test_an_unproduced_fact_maps_only_to_a_counter_no_producer_can_raise() -> void:
	var pairs: Dictionary = {}
	for row in DestinyProjection.COUNTER_FACTS:
		pairs[String((row as Dictionary).get("fact", ""))] = String(
			(row as Dictionary).get("counter", "")
		)
	var mapped: Array[String] = []
	for dead in _unproduced_facts_impl.call():
		mapped.append(String(pairs.get(String(dead), "")))
	mapped.sort()
	assert_eq(
		mapped,
		UNPRODUCED_COUNTERS,
		(
			(
				"the three dead facts map to %s and no other counter: a fact with no producer "
				% str(mapped)
			)
			+ "may still be WIRED (so the fate that reads it can be authored before its deed "
			+ "exists), but the counter it raises must be one nothing else reaches, or a gate "
			+ "on it would open for the wrong reason."
		)
	)


# --- 4. the census this file leans on, and the `tools/data.py` half -----------


## ## The authored `counter` gate is now COUNTED, and the census turns on it
##
## `_authored_counter_gate_ids()` walked the whole content tree for
## `{"verb": &"counter", ...}` and found nothing: that empty answer is the fact
## `test_destiny_counter_mapping_census.gd` branches on ("asserts the coverage that is
## TRUE, not coverage that is hoped for"). This suite's `.tres` is what makes it
## non-empty — so the census takes its other branch, and from here on every
## `FateDef.counters` id a gate could name must be wired to something.
##
## Asserted positively, because the census's other branch asserts the emptiness itself
## and one of these two must now be true: this file says the list is NON-empty and names
## the id, and the census says every gated counter is wired.
##
## Reads through the SHARED reader `support._authored_counter_gate_ids()`. That reader
## had an off-by-one — it computed `var quote := id_at + 9` to skip the 9-character
## literal `'"id": &"'`, but `id_at` points at that literal's OPENING quote, so the
## skip landed one character past the id's own quote and returned `duels_won` as
## `uels_won`. It is fixed, and it was silent in the one way that matters: a census
## comparing against the same wrong reader agrees with itself forever. So this file
## asserts the id POSITIVELY by name, which is what catches a reader that eats a
## character — a reader that returns `uels_won` fails here, where a `== []` assertion
## would have passed.
func test_the_content_tree_now_carries_a_counter_gate_and_names_its_id() -> void:
	## Reads through the SHARED reader `support._authored_counter_gate_ids()`. That reader
	## had an off-by-one — it computed `var quote := id_at + 9` to skip the 9-character
	## literal `'"id": &"'`, but `id_at` points at that literal's OPENING quote, so the
	## skip landed one character past the id's own quote and returned `duels_won` as
	## `uels_won`. It is fixed, and it was silent in the one way that matters: a census
	## comparing against the same wrong reader agrees with itself forever. So this file
	## asserts the id POSITIVELY by name, which is what catches a reader that eats a
	## character — a reader that returns `uels_won` fails here, where a `== []` assertion
	## would have passed.
	var gates: Array = _authored_counter_gate_ids_impl.call()
	assert_eq(
		gates,
		[str(GATED_COUNTER)],
		(
			(
				"the content tree carries exactly one authored `counter` gate, on '%s', which is "
				% String(GATED_COUNTER)
			)
			+ "what turns DEF-0121 from a comment into a failure the census can raise"
		)
	)
	# Every id any shipped gate names must be one the bridge can move — checked over the
	# WHOLE corpus rather than over this suite's one row, so a second gate authored on a
	# dead id by another agent goes red here too.
	var wired: Array[String] = _wired_ids_impl.call()
	var unwired: Array[String] = []
	for gate_id in gates:
		if not wired.has(String(gate_id)):
			unwired.append(String(gate_id))
	unwired.sort()
	assert_eq(unwired, [], "every counter id any shipped .tres gates on is one the bridge can move")


## Every `counter` id any shipped `.tres` names in a gate requirement, sorted.
##
## ## Why this file reads the content tree ITSELF rather than through the shared reader
##
## The support file's `_authored_counter_gate_ids()` has an off-by-one: it finds the
## `'"id": &"'` literal, computes `id_at + 9` to skip past it, and slices the id from
## there. But `find` returns the index of the literal's OPENING quote, and
## `'"id": &"'` is 9 characters long, so `id_at + 9` is the index of the `"` that OPENS
## the value — one past where it should be. Every id comes back with its first character
## removed: `duels_won` → `uels_won`.
##
## Measured, not assumed. This suite observed it, and the file belongs to another agent,
## so the correct reader is stated here and the divergence is asserted rather than
## worked around in silence.
func _gate_ids_in_content() -> Array[String]:
	var found: Array[String] = []
	for path in _data_tres_files():
		var body := FileAccess.get_file_as_string(path)
		var cursor := 0
		while true:
			var at := body.find('"verb": &"counter"', cursor)
			if at < 0:
				break
			cursor = at + 1
			# From the end of the verb token, so the `id` searched for is the one THIS
			# requirement names and not one belonging to a sibling on the same line. The
			# 200-character bound is the support reader's, kept for the same reason: past
			# it the `"id"` found belongs to some other requirement and this scan would
			# attribute one gate's id to another.
			var id_at := body.find('"id": &"', cursor)
			if id_at < 0 or id_at - cursor > 200:
				continue
			# `find` returns the index of the literal's OPENING quote, and
			# `'"id": &"'` is 9 characters, so the value opens at `id_at + 9`.
			var open := id_at + '"id": &"'.length()
			var close := body.find('"', open)
			if close < 0:
				continue
			found.append(body.substr(open, close - open))
	found.sort()
	return found


## Every `.tres` under `res://data`, sorted. Recursive, and iterative inside, because a
## `DirAccess` walk that silently visits nothing would make every "a shipped gate exists"
## assertion pass vacuously — the false green this file exists to prevent.
func _data_tres_files() -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = ["res://data"]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not entry.begins_with("."):
				var path := current.path_join(entry)
				if dir.current_is_dir():
					pending.append(path)
				elif entry.ends_with(".tres"):
					out.append(path)
			entry = dir.get_next()
		dir.list_dir_end()
	out.sort()
	return out


## ## Two readers over the same tree must AGREE
##
## This file carries its own reader as well as using the shared one, and the
## original claim was that the shared reader loses the first character of every id
## (`duels_won` arriving as `uels_won`) because it computed `var quote := id_at + 9`
## to skip the 9-character literal `'"id": &"'`, while `find` returns the index of
## that literal's OPENING quote. **The shared reader is now FIXED**, so this asserts
## the fix rather than the bug: two independent readers must return the same ids,
## spelled identically. A reader that regresses goes red here, and so does a reader
## that diverges for any other reason — which is a sharper claim than "the count
## agrees", and it is the reason to keep two readers at all.
func test_both_gate_id_readers_agree_on_every_id() -> void:
	assert_eq(
		_data_tres_files().is_empty(),
		false,
		"the content tree really has .tres files, so both readers had something to find"
	)
	var mine := _gate_ids_in_content()
	var theirs: Array = _authored_counter_gate_ids_impl.call()
	assert_eq(
		theirs,
		mine,
		(
			"the shared reader and this file's own reader return the same ids, spelled "
			+ "identically: %s vs %s" % [str(theirs), str(mine)]
		)
	)


## ## The reachability predicate this pair leans on, asserted over its own answer
##
## `_authored_fact_ids()` + `_module_owned_facts()` is "what the shipped tree can
## record". The gate this suite authored is reachable only because `duels_won` is in
## BOTH halves — authored as a quest step's watched fact AND written by a module-owned
## producer. Asserted so the reachability argument is a measurement of the support
## file's readers rather than a claim about them.
func test_the_gate_fact_is_reachable_by_both_halves_of_the_census() -> void:
	var authored: Dictionary = _authored_fact_ids_impl.call()
	var module_owned: Array = _module_owned_facts_impl.call()
	assert_eq(
		authored.has(String(GATED_COUNTER)),
		true,
		(
			(
				"'%s' is a fact the CONTENT tree already watches — what_the_rotation_cost.tres "
				% String(GATED_COUNTER)
			)
			+ "step 2 asks for — so the authored world has an interest in the same number"
		)
	)
	var owned := false
	for entry in module_owned:
		if String((entry as Dictionary).get("fact", "")) == String(GATED_COUNTER):
			owned = true
			assert_eq(
				String((entry as Dictionary).get("writer", "")),
				"combat/CombatFacts",
				"and the module that owns it is `combat`, which is a live `game/src` writer"
			)
	assert_eq(
		owned,
		true,
		(
			"and a module-owned producer claims it, which is the half a content-only scan "
			+ "cannot see and the reason this gate can open at all"
		)
	)


## ## The finding that belongs in `tools/data.py`, held here because that file is
## ## owned by another agent
##
## My `.tres` flipped `test_destiny_counter_mapping_census.gd` from its "nothing gates on
## a counter yet" branch to its other one, and the census immediately reported:
##
##   a shipped .tres gates on `counter`, so every FateDef.counters id it could gate on
##   needs a fact that moves it: expected [], got ["breakthroughs"]
##
## That is the check doing exactly its job — but look closely at what it names. It is
## not complaining about MY gate's id. It is complaining that `reborn_in_a_lesser_vessel`
## and `remembered_by_the_mountain` declare `counters = [&"breakthroughs"]` and **no
## row in `COUNTER_FACTS` produces it**. The census's rule is total ("every id a gate
## COULD name must be wired"), and `breakthroughs` is an id a gate could name, so it is
## reported — which is correct, and it is a real hole that predates this `.tres`.
##
## The gate is total because a gate author reading `reborn_in_a_lesser_vessel.tres`
## sees `counters = [&"breakthroughs"]` and has no way to know no fact moves it. ADR
## 0134's growth note names the same absence: "`breakthroughs` still has no fact". So the
## honest claim is that `FateDef.counters` currently reads as documentation rather than
## as a promise, and the two modules that could fix it — `qi` and `body`, for
## `advancement.gd:25` and `body_cultivation/api.gd:211` — are other agents' work.
##
## **The gate belongs in `tools/data.py`, not in a GDScript suite**, for the reason its
## sibling already gave for the unproduced-fact census: an author sees it in seconds on
## the next commit, rather than in minutes at the end of a saturated test run. The
## check it needs already exists there in outline — `_destiny_findings` reads
## `declared` (every `FateDef.counters` id) and `wired` (every counter `COUNTER_FACTS`
## produces) and warns on `set(declared) - set(wired)` today. What it cannot do is
## decide whether that is worth WARNING or GATING, because the answer depends on whether
## a shipped `.tres` names the id — and that is now knowable from the file the other
## agent's `_authored_counter_gates()` already walks.
func test_the_unwired_counter_an_author_could_gate_on_is_named_while_the_tree_is_unfixed() -> void:
	var declared: Dictionary = {}
	for fate_id in FateCatalog.instance().fate_ids():
		var def := FateCatalog.instance().fate_definition(fate_id)
		if def == null:
			continue
		for counter_id in def.counters:
			declared[String(counter_id)] = String(fate_id)
	assert_eq(
		declared.is_empty(),
		false,
		"the shipped fate tree declares counters, so this case is not vacuous"
	)

	var wired: Array[String] = _wired_ids_impl.call()
	var unwired: Array[String] = []
	for counter_id in declared.keys():
		if not wired.has(String(counter_id)):
			unwired.append(String(counter_id))
	unwired.sort()
	# The EXPECTED state, held so the day the owning modules ship their advancement
	# fact this goes RED and names itself — which is the whole point of a census rather
	# than a wish. ADR 0134 §3 names both call sites: `qi_cultivation/advancement.gd:25`
	# and `body_cultivation/api.gd:211`, neither of which records a fact today
	# (DEF-0106).
	assert_eq(
		unwired,
		["breakthroughs"],
		(
			(
				"'breakthroughs' is declared by %s and produced by no row of COUNTER_FACTS, so a "
				% str(declared.get("breakthroughs", ""))
			)
			+ (
				"gate on it could never open. qi_cultivation/advancement.gd and "
				+ "body_cultivation/api.gd record no fact today (DEF-0106); when one lands, add "
				+ "the row and this assertion goes red naming the change. Authoring the fact is "
				+ "those modules' work, not this suite's."
			)
		)
	)
