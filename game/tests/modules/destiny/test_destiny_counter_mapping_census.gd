extends TestCase

## The second half of the pair that `test_destiny_counter_production_wiring.gd`
## used to be, split out on the seam its own section marker already drew: **the
## mapping census**. That file's first half drives real production writers and asks
## "given a live bridge, does the writer the game actually uses move its counter";
## this file asks the question on the OTHER side of the table — "is every row in
## `DestinyProjection.COUNTER_FACTS` something the shipped tree can really record,
## and is every counter a shipped `FateDef` actually names one the table can move".
##
## ## Why the seam is here and not at the gate section
##
## The gate section (`# --- The gate opens on it ---`) reads counters off an actor
## the writer cases moved. The census reads the CONTENT TREE and the mapping TABLE:
## `FateCatalog`, `QuestCatalog`, `EventCatalog`, raw `.tres` text under `res://data`,
## and lines of source under `res://src`. That is a different subject with a
## different set of dependencies and — the reason that decided it — a different
## failure mode. A broken writer fails in section one; a `.tres` that names a counter
## nothing moves fails in section two, and until now both lived in one file behind one
## install. Splitting here leaves the half that must never be fudged —
## `CombatApi.hit`, `CombatApi.spare`, `ClanHeir.register`, `SectApi.promote`,
## `SectDuty.serve`, `event/EventBeatWriter` through the world's own tick, and
## `app/CharacterCreationFlow` — in the file whose header explains why those writers
## are not negotiable.
##
## ## Nothing below constructs a beat or records a fact by hand
##
## The only "fact" this file ever mentions is a fact id READ out of
## `COUNTER_FACTS`, and the only writers it touches are module-owned `const`s. It
## asserts over catalogs, over shipped `.tres` text, and over lines of source; it
## never calls a writer and never moves a counter. That is precisely why this half is
## safe to split off: the two earlier versions of the sibling file went green on a
## broken build because they asked a CONSTRUCTED beat to move a counter, and nothing
## here can be green for that reason, because nothing here asks for a movement.
##
## ## The bridge is installed per-test here too, and the census does not need it
##
## Installed anyway, deliberately, and for the same reason the sibling does it: this
## process is SHARED. `WorldFact._subscribers` is a `static var`, so the only thing
## that makes a subscriber left behind observable is a suite that asserts the DELTA.
## Every case here reads no counter at all, so a leak out of this suite would be
## invisible in its OWN output and would surface as some unrelated suite's counter
## moving by one. Leaving the install in means `teardown()` can catch that leak in
## the suite that made it, under its own name.
##
## **And it is a DELTA, never `0`.** See the note on the sibling's `_baseline_subscribers`:
## the same reasoning binds both halves of the pair, and either one asserting an
## absolute count would be asserting that no other suite exists.

const Support := preload("res://tests/modules/destiny/destiny_counter_wiring_support.gd")

## **A constant rather than `Support.UNPRODUCED`.** `Support` is a preloaded script
## constant, and GDScript resolves a `const` initialiser against the class's own
## members — which the runner attaches one property at a time — so reading through it
## during initialisation answers `null` and the failure reads like a missing row in
## the table instead of a constant that could not be resolved in time. One copy, here,
## with the same three names in the same order, and the assertion below is what
## holds the two in agreement.
const UNPRODUCED := [&"bound_name_called", &"mountain_circled_once", &"vigil_broken"]

## The baseline this suite's own `teardown()` is measured against, read HERE rather
## than asserted to be zero. See the header.
var _baseline_subscribers: int = 0

## **Assigned here, never at the declaration.** Two reasons, and both of them about
## the runner rather than about this suite. First, `Support` does not resolve while
## the object is still being constructed — the runner attaches one property at a time,
## so a script constant initialiser that dereferences it answers `null`. Second, the
## runner then COPIES the properties of an already-built instance onto a second
## instance, and a `Callable` is bound to the instance it was created from, so a
## forwarding `var f := func(): ...` declared on the template would rebind to the
## TEMPLATE when it is copied, and every census read would come back from the
## half-built object this suite is constructing. Assigning inside `setup()` — which
## the runner calls on the live instance, after construction — binds the forwarding
## methods to the instance that is actually going to read them.
##
## They exist at all because the shared helpers have no `class_name` and are reached
## only through this `const`, and a bare `Support._declared_counters()` is a
## property access that GDScript parses as a member of THIS script rather than a call
## on the support object. Forwarding once, here, is the narrow door that lets the
## census read the same answer as its sibling.
var _declared_counters: Callable
var _wired_ids: Callable
var _authored_fact_ids: Callable
var _module_owned_facts: Callable
var _unproduced_facts: Callable
var _authored_counter_gate_ids: Callable
var _names_in_code: Callable


## Install the bridge for ONE test, exactly as the sibling suite does.
##
## The census asserts nothing this bridge feeds, so it is here to be a well-behaved
## neighbour rather than to make any assertion true — see the header.
func setup() -> void:
	# Bound BEFORE the bridge goes in, so a reader that cannot be bound fails this
	# case by name instead of surfacing as a `null` answer in a census three lines on.
	_bind_support()
	_baseline_subscribers = WorldFact.subscriber_count()
	DestinyProjection.subscribe_to_fact_ledger()
	assert_eq(
		WorldFact.has_subscriber(Callable(DestinyProjection, "on_fact_recorded")),
		true,
		(
			"the fact->counter bridge is LIVE for this test, even though no case here reads "
			+ "a counter: this suite shares a process, and a suite that installed nothing "
			+ "could not detect a leak it made"
		)
	)


## Leave the process exactly as this suite found it — a DELTA back to the count
## `setup()` recorded, never `0`, because a sibling suite may legitimately hold a
## subscriber of its own. Only the bridge THIS suite installed is removed, by
## identity — never `WorldFact.clear_subscribers()`, which is process-wide and would
## trade this suite's leak for whatever suite ran next.
func teardown() -> void:
	DestinyProjection.unsubscribe_from_fact_ledger()
	assert_eq(
		WorldFact.subscriber_count(),
		_baseline_subscribers,
		(
			"the bridge is REMOVED again and the slot is back to the count this test found: "
			+ "the runner shares one process, and a subscriber left behind moves counters "
			+ "for every later suite"
		)
	)


## Bind one forwarding [Callable] per shared reader, against the LIVE instance.
##
## Not a loop and not a dictionary: the forwarders are named members because a
## reader that is never bound should fail as a `null` call at the one case that uses
## it, and a table keyed by name would hide that behind a lookup that fails somewhere
## else. Seven assignments, each of which fails loudly and locally.
func _bind_support() -> void:
	_declared_counters = Support._declared_counters
	_wired_ids = Support._wired_ids
	_authored_fact_ids = Support._authored_fact_ids
	_module_owned_facts = Support._module_owned_facts
	_unproduced_facts = Support._unproduced_facts
	_authored_counter_gate_ids = Support._authored_counter_gate_ids
	_names_in_code = Support._names_in_code


# --- The mapping is authored, auditable, and matches the real tree -----------


## The table is an EXPLICIT map, never a fuzzy name match. Every row is checked
## against the real shipped `FateDef` that reads it, over the real catalog rather
## than a copy, so deleting a row here cannot quietly retire a fate.
##
## **This asserts the coverage that is TRUE, not coverage that is hoped for.** No
## shipped `.tres` uses the `counter` gate verb, so zero counters need a writer
## today — the census, not a silent pass and not a failing assertion. The moment
## somebody authors `{verb: &"counter", ...}`, this goes RED naming the ids with no
## writer, which is the check the gap needed all along: a fate's `counters` entry
## cannot quietly become a promise nothing keeps.
##
## Widened to assert total coverage once every authored counter has a producer.
func test_every_wired_counter_is_declared_by_a_shipped_fate() -> void:
	var declared := _declared_counters.call()
	assert_eq(
		declared.is_empty(),
		false,
		"the shipped fate tree declares counters; this suite must read it, not assume"
	)
	var unwired: Array[String] = []
	for counter_id in declared.keys():
		# `counter_for_fact` answers FACT -> counter, so asking it with a COUNTER id
		# is a category error that happens to be truthy for `duels_won` alone (the one
		# id that is spelled the same on both sides). Read the table directly instead,
		# so an id is "wired" only because a row really moves it.
		if not _wired_ids.call().has(String(counter_id)):
			unwired.append(String(counter_id))
	unwired.sort()
	var wired := _wired_ids.call()
	var gates := _authored_counter_gate_ids.call()
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


## Every fact on the left is a fact the shipped tree can actually record: an authored
## event beat, a fact a quest's own demand names, a composition-root beat, or one of
## the five module-owned producers ADR 0137 added.
##
## ## What this claims about the three dead rows
##
## It claims the HONEST thing, which is a census rather than a flat pass: the shipped
## content tree authors no beat for `vigil_broken`, `bound_name_called` or
## `mountain_circled_once`, and nothing in `game/src` produces them either. Those
## three stay dead and this suite says so BY NAME, because a test that went green
## while they were dead — and listed them as expected — is the inverted proof the
## pair of files was written to delete.
##
## Inventing a producer for them is NOT this file's work and would be wrong: the
## quests that ask for them are other modules' content, and an authored counter only
## a test could reach is the exact shape DEF-0105/DEF-0106 record.
func test_every_wired_fact_is_authored_content_or_a_named_module_producer() -> void:
	var reachable := _authored_fact_ids.call()
	for entry in _module_owned_facts.call():
		reachable[String((entry as Dictionary).get("fact", ""))] = true

	var orphans: Array[String] = []
	for row in DestinyProjection.COUNTER_FACTS:
		var fact := String((row as Dictionary).get("fact", ""))
		if not reachable.has(fact):
			orphans.append(fact)
	orphans.sort()
	assert_eq(
		orphans,
		[],
		(
			(
				"these rows name facts nothing in the shipped tree can record: %s. Authoring "
				% str(orphans)
			)
			+ "their producers is other modules' work (DEF-0105/DEF-0106) and a test must not "
			+ "stand in for it — add the producer and this goes green by itself."
		)
	)


## The dead rows are named HERE, exactly, so the census above cannot quietly grow a
## fourth while still passing. If this list ever shrinks, the assertion that shrank it
## says why; if it is deleted wholesale, the next author inherits a suite that claims
## full coverage and does not have it.
func test_the_unproduced_rows_are_named_so_the_census_cannot_grow_quietly() -> void:
	var unreachable := _unproduced_facts.call()
	unreachable.sort()

	assert_eq(
		unreachable,
		[
			String(UNPRODUCED[0]),
			String(UNPRODUCED[1]),
			String(UNPRODUCED[2]),
		],
		(
			(
				"exactly three authored rows have no producer in `game/src` and no authored "
				+ (
					"beat: %s. They read 0 forever and stay that way until the owning module "
					% str(unreachable)
				)
			)
			+ "writes them (DEF-0105/DEF-0106). When one lands, delete it from UNPRODUCED in "
			+ "the same change that adds the producer — this suite is a census, not a wish."
		)
	)


## Every id this suite treats as module-owned really is named in the shipped module
## that claims to produce it, in a line of CODE. Read from the files rather than
## restated, because the two have already drifted once — `what_the_rotation_cost.tres`
## once watched `vigil_broken` and now watches `sect_post_held`, and a suite that
## believed the docstring rather than the tree would still have been green.
func test_the_module_owned_producer_list_is_read_from_the_modules_that_claim_it() -> void:
	var expected := {
		"res://src/modules/combat/combat_facts.gd":
		[String(CombatFacts.FACT_DUELS_WON), String(CombatFacts.FACT_THIRD_MAN_SPARED)],
		"res://src/modules/clan/clan_facts.gd": [String(ClanFacts.FACT_HEIR_REGISTERED)],
		"res://src/modules/sect/sect_facts.gd":
		[String(SectFacts.FACT_POST_HELD), String(SectFacts.FACT_OATHS_DISCHARGED)],
		"res://src/app/character_creation_flow.gd": [String(CharacterCreationFlow.FACT_ID)]
	}
	var listed: Array[String] = []
	for entry in _module_owned_facts.call():
		listed.append(String((entry as Dictionary).get("writer", "")))
	listed.sort()

	for path in expected.keys():
		var body := FileAccess.get_file_as_string(path)
		assert_ne(body, "", "%s ships, so this is not a silent skip" % path)
		for fact in expected[path] as Array:
			assert_eq(
				_names_in_code.call(body, String(fact)),
				true,
				(
					"%s names '%s' in a line of code, so the census is reading a real producer"
					% [path, String(fact)]
				)
			)
	assert_eq(
		listed,
		[
			"app/CharacterCreationFlow",
			"clan/ClanFacts",
			"combat/CombatFacts",
			"combat/CombatFacts",
			"sect/SectFacts",
			"sect/SectFacts"
		],
		"and every module-owned producer is listed here, so a new one cannot be invisible"
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


## Every counter a shipped `FateDef` names is one the bridge can move. The converse
## census is `test_every_wired_counter_is_declared_by_a_shipped_fate`; this direction
## is the one that catches a typo in the TABLE, which would otherwise move a number
## nothing gates on.
func test_every_wired_counter_is_one_the_shipped_tree_declares() -> void:
	var declared := _declared_counters.call()
	var unknown: Array[String] = []
	for counter_id in _wired_ids.call():
		if not declared.has(counter_id):
			unknown.append(counter_id)
	assert_eq(unknown, [], "no row moves a counter no fate reads")
