extends TestCase

## BL-0747: **a refused `register` never destroys a registered def, and two loads of
## one tree agree on the order.**
##
## ## Why this file exists, given the file beside it
##
## `test_event_catalog_invariants.gd` already asserts the destruction invariant from the
## *outside* — after a probe, `has(SHIPPED)` and the authored `display_name` are intact.
## That is the right assertion and it is still here. What it does not do is **prove the
## catalogue is the only thing the probe damaged**, and it never varies the ORDER the
## catalogue hands ids back in. Two gaps, and both are reachable:
##
##   - `EventCatalog.instance()` is process-wide and `reload()` exists *only* for tests,
##     so the erase can only manifest in-process. A suite that never calls `register` never
##     sees it, and `--suite test_npc` — the suites that depend on the elder's ladder
##     reading `the_favour_of_elder_wei` — is not where the event suites run. A green
##     `--suite test_npc` was therefore compatible with the whole fix being reverted.
##   - The determinism claim (`world_pulse.gd:422`: "the order `available` gives them…
##     that order is the catalog's STRING order") had **no test at all**. It is the claim
##     a player notices — two runs opening two different events — and nothing held it.
##
## So this file pins both halves as INTERNAL invariants, plus the whole-tree form of the
## first, and `tests/modules/npc/test_npc_event_catalog_dependency.gd` pins the elder's
## own dependency so the npc suite carries it too.

## ## What "the order is deterministic" is asserted AGAINST
##
## Against nothing weaker than the STRING order. `_ids.sort()` is the alternative and it
## is not a comparison at all: `Array[StringName].sort()` is unspecified as to the interned
## string, so it orders by pointer, and the ids are interned — measured, the same eight
## shipped `.tres` files came back in a different order from two loads of one tree. So the
## test compares the ids **as strings**, against `Array[String].sort()`. Asserting that
## `sort()` sorted would be asserting the bug.

## The elder's own event. Named rather than picked from `event_ids()[0]` because the
## failure being pinned is *silent content loss*: if the id is derived from whatever the
## catalog currently holds, an already-empty catalog names nothing and the test passes.
const ELDER_EVENT := &"the_favour_of_elder_wei"

## A shipped id that no authored beat is tied to, used so the whole-tree sweep below has
## a target that is not the one the elder's ladder reads.
const UNCLAIMED := &"the_stone_that_answering"

## A kind outside `EventDef.KINDS`, which is what makes a probe MALFORMED. The malformed
## branch is the one that used to erase; a well-formed duplicate takes a different line.
const BAD_KIND := &"doomsday"


## ## 1. The malformed branch, asserted on the catalogue's OWN bookkeeping
##
## `has()` and `display_name` are what a caller reads. The erase also touched `_ids` — the
## list `EventApi.available` walks and the pulse opens in order — so a def could survive
## in `_events` while being gone from the order, and `has()` would call it present. Both
## halves are asserted, and `problems()` is asserted too: that is the whole-tree health
## check, and it walks `_ids`.
func test_a_malformed_probe_never_removes_a_shipped_def_from_the_catalog_or_its_order() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	var authored := catalog.event_definition(ELDER_EVENT)
	assert_ne(authored, null, "the shipped tree has the elder's event")
	var authored_name := String(authored.display_name)
	assert_eq(
		catalog.event_ids().has(String(ELDER_EVENT)),
		true,
		"and the id starts in the order `available` walks"
	)

	var probe := _def(ELDER_EVENT, "A Malformed Probe", BAD_KIND)
	assert_eq(catalog.register(probe), false, "a def naming a kind nobody reads is refused")

	assert_eq(catalog.has(ELDER_EVENT), true, "the shipped def is still in `_events`")
	assert_eq(
		String(catalog.event_definition(ELDER_EVENT).display_name),
		authored_name,
		"and it is still the one the TREE authored, not the object the probe handed it"
	)
	assert_eq(
		catalog.event_ids().has(String(ELDER_EVENT)),
		true,
		"and the id is still in `_ids`, so `available` can still offer it"
	)
	assert_eq(
		_ordering_problem(),
		"",
		"and `problems()` — which walks `_ids` — sees a healthy tree: %s" % str(catalog.problems())
	)


## ## 2. The duplicate branch, pinned separately
##
## Two separate lines of code, so a fix to one proves nothing about the other. It is also
## the branch a reader is most tempted to read as "replace", which is why this one asserts
## BOTH: the claim is refused, AND the first def is the one that survives.
func test_a_second_well_formed_claim_on_a_shipped_id_is_refused_and_the_first_def_survives(
) -> void:
	_reload()
	var catalog := EventCatalog.instance()
	var authored_name := String(catalog.event_definition(UNCLAIMED).display_name)

	var probe := _def(UNCLAIMED, "A Second Claim On A Shipped Id", EventDef.KIND_DISASTER)
	assert_eq(catalog.register(probe), false, "a duplicate id is refused")
	assert_eq(catalog.has(UNCLAIMED), true, "the first def is still registered")
	assert_eq(
		String(catalog.event_definition(UNCLAIMED).display_name),
		authored_name,
		"the FIRST def wins the id; a later claim never replaces shipped content"
	)
	assert_eq(catalog.event_ids().has(String(UNCLAIMED)), true, "and the order is untouched too")


## ## 3. The whole tree, not one hand-picked id
##
## One id is a sample; a defect that fires on any id is only bounded by the tree. Every
## shipped id gets a malformed probe carrying that id, and afterwards every one of them
## must still resolve. This is the form that says "no id in this build is destroyable by
## `register`", which is the actual invariant — and it cannot be satisfied by a fix that
## special-cases the one id a previous test happened to use.
func test_no_shipped_id_is_destroyable_by_a_probe_that_reuses_it() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	var ids := catalog.event_ids()
	var names := {}
	for event_id in ids:
		names[String(event_id)] = String(catalog.event_definition(event_id).display_name)
	assert_eq(ids.size() > 1, true, "the tree ships more than one event, so there is a set")

	for event_id in ids:
		catalog.register(_def(event_id, "A Probe", BAD_KIND))

	for event_id in ids:
		var key := String(event_id)
		var def := catalog.event_definition(event_id)
		assert_ne(def, null, "%s survived a probe claiming its id" % key)
		if def != null:
			assert_eq(
				String(def.display_name),
				names[key],
				"%s is still the tree's def, not the probe's" % key
			)
	assert_eq(catalog.event_ids(), ids, "and the id list came through the sweep unchanged")


## ## 4. The ORDER: string order, not admission order
##
## The eight shipped ids happen to be admitted in string order (the walk sorts by path and
## every file is named after its id), so asserting against the SHIPPED tree alone passes
## under `_ids = _ids` — the bug is invisible on today's content and appears the first
## time an author names a file `z_first_night.tres`. So the order is perturbed here on
## purpose: three well-formed defs registered in DELIBERATE reverse-alphabetical order, and
## the catalogue is required to hand them back alphabetically.
##
## This is the assertion that turns "deterministic" into a checkable claim. `_ids.sort()`
## sorts interned pointers and would keep insertion order here; `_sorted_ids` compares
## strings and would not.
func test_the_order_is_the_string_order_not_the_order_defs_were_admitted_in() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	var shipped := catalog.event_ids()
	assert_eq(shipped.size() > 1, true, "the shipped tree has more than one event")

	# Reverse alphabetical, and each id sorts LATE so it has to move rather than merely
	# land after the shipped eight.
	for suffix in ["zz_probe_third", "zz_probe_first", "zz_probe_second"]:
		var def := _def(&"probe_%s" % suffix, "Probe %s" % suffix, EventDef.KIND_DISASTER)
		assert_eq(catalog.register(def), true, "a well-formed novel def is admitted: %s" % suffix)

	var got: Array[String] = []
	for event_id in catalog.event_ids():
		got.append(String(event_id))
	var want := got.duplicate()
	want.sort()
	assert_eq(
		got,
		want,
		(
			(
				"the catalog's order must be the STRING order regardless of admission order, "
				+ "because `WorldPulse._open_available` opens the FIRST entry `available` "
				+ "offers: %s"
			)
			% got
		)
	)


## ## 5. DETERMINISM, as the task states it: two independent `reload()`s over one tree.
##
## Same process, same files, cache dropped twice. `reload()` clears `_events`, `_ids`,
## `_rejected` and `_loaded`, so the second read is a genuine re-walk rather than a replay
## of the first — which is exactly what makes the two orders comparable. Asserted against
## the STRING order as well as against each other, because two equal orders that are both
## in load order would satisfy "the same" and still be the bug.
##
## **The perturbation is load-bearing, and this is the measured reason for it.** The eight
## shipped ids happen to be ADMITTED in string order — `_scan` sorts by path and every file
## is named after its id — so on the bare tree an unsorted `_ids = _ids` returns the
## *identical* list twice and this test passes green against the bug it exists to catch. The
## fix is the same reverse-alphabetical triple test 4 registers, made here as well so the
## second read differs in ADMISSION order: same tree, same files, two different admission
## sequences, and the catalog must still hand back one string order.
func test_two_independent_reloads_of_one_tree_return_the_same_ids_in_the_same_order() -> void:
	var first := _order_of_a_fresh_reload()
	var second := _order_of_a_fresh_reload()
	assert_eq(first.size() > 1, true, "the tree ships more than one event, so an order exists")
	assert_eq(
		first,
		second,
		"two reads of ONE tree must agree on the order, or a run opens a different event"
	)
	var want := first.duplicate()
	want.sort()
	assert_eq(
		first,
		want,
		"and both are the STRING order, not an order that happened to repeat: %s" % first
	)


## The same two reads with a well-formed def registered in between, admitted in
## reverse-alphabetical order on the FIRST read and not on the second. Under `_ids = _ids`
## the first read ends `... , probe_zz_probe_third, probe_zz_probe_first,
## probe_zz_probe_second` and the second omits them, so the two orders DISAGREE as well as
## being unsorted — which is the "one run opens a different event" symptom, reproduced
## from a single tree rather than across two machines.
func test_a_reload_with_a_probe_between_reads_still_returns_the_same_order() -> void:
	var first := _order_of_a_reload_with_probes()
	var second := _order_of_a_fresh_reload()
	assert_eq(first.size() > 1, true, "the tree ships more than one event, so an order exists")
	assert_eq(
		first,
		second,
		(
			"a def registered between two reads of ONE tree must not change the order the "
			+ "catalog reports for the shipped tree: %s vs %s" % [first, second]
		)
	)


## ## Fixtures


## The ids one full re-walk of the shipped tree returns, as strings.
func _order_of_a_fresh_reload() -> Array[String]:
	var catalog := EventCatalog.instance()
	catalog.reload()
	var out: Array[String] = []
	for event_id in catalog.event_ids():
		out.append(String(event_id))
	return out


## One re-walk preceded by three well-formed defs admitted in DELIBERATE reverse order.
func _order_of_a_reload_with_probes() -> Array[String]:
	var catalog := EventCatalog.instance()
	catalog.reload()
	# Touch the shipped tree first, so the probes are appended AFTER it and any drift is
	# the probes' own admission order rather than a differently-sorted shipped tree.
	assert_eq(catalog.event_ids().size() > 1, true, "the shipped tree is read before the probes")
	for suffix in ["zz_probe_third", "zz_probe_first", "zz_probe_second"]:
		var def := _def(&"probe_%s" % suffix, "Probe %s" % suffix, EventDef.KIND_DISASTER)
		assert_eq(catalog.register(def), true, "the well-formed probe '%s' is admitted" % suffix)
	var out: Array[String] = []
	for event_id in catalog.event_ids():
		out.append(String(event_id))
	return out


## A well-formed-enough `EventDef` carrying `id`, as far as it can be: a valid kind, a
## display name, no stages and no beats — `problems()` on this returns an empty array, so
## `register` reaches the DUPLICATE branch rather than the malformed one.
func _def(id: StringName, display_name: String, kind: StringName) -> EventDef:
	var def := EventDef.new()
	def.id = id
	def.display_name = display_name
	def.kind = kind
	return def


## The first line of `problems()`, or `""` for a healthy tree. Asserted rather than
## inlined because a line about one id and a whole-tree answer are different claims.
func _ordering_problem() -> String:
	var problems := EventCatalog.instance().problems()
	return String(problems[0]) if not problems.is_empty() else ""


## Drop the cache and re-walk the tree, and ASSERT the reset worked. `EventCatalog` is a
## process-wide singleton and the runner shares one process across every suite, so a suite
## that ran first and left a probe registered would otherwise make every assertion below
## describe THAT rather than the shipped tree.
##
## `expect_assertions(2)` is declared, and it is not cosmetic. The `!= null` guard is what
## lets the tests below report the DESTROYED EVENT BY NAME and the exact id list that came
## back. Without it a restored `_admit` erase aborts the body on the next line's
## `display_name` access, the framework charges ONE failure for the whole body, and the
## report names an aborted line instead of the content that vanished.
func _reload() -> void:
	expect_assertions(2)
	EventCatalog.instance().reload()
	assert_eq(
		EventCatalog.instance().event_definition(ELDER_EVENT) != null,
		true,
		"the shipped tree really was re-read before this test's probe"
	)
	assert_eq(
		EventCatalog.instance().event_ids().size() > 1,
		true,
		"and it holds more than one event, so an order and a set exist to lose"
	)


## The probes in this file are the only things that dirty a process-wide cache, and the
## next suite reads the same tree. `teardown` runs after EVERY test (see
## `tests/framework.gd`), so the tree is handed back the way it was found.
func teardown() -> void:
	EventCatalog.instance().reload()
