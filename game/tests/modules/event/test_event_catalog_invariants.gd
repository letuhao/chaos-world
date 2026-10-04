extends TestCase

## BL-0747: **a shared catalog does not destroy a registered def, and its order does
## not depend on what loaded first.**
##
## ## Why this file exists, and what it is NOT
##
## Three tests in `tests/modules/npc/test_npc_tally_production_path.gd` went red only
## in company, on failures that named nothing about the roster. The first diagnosis
## offered for them was the obvious one and it was WRONG: that `EventCatalog._admit`
## erased a shipped def when a duplicate id was registered, so `the_favour_of_elder_wei`
## was missing from the catalog for the rest of the process. **It was not missing.**
## Measured directly (`event_definition` after `setup()` and again after a full
## `WorldPulse.pull`): present before, present after, both times. A suite header that
## asserts a cause it did not measure is the same defect as a test that cannot fail.
##
## What was actually true is below, and it is two real bugs. Both are in a process-wide
## cache that every reader in the game shares, which is why a defect in either is
## invisible in a suite that runs first and wrong in a suite that runs late.
##
## ## 1. `_admit` REFUSED BY ERASING (this file's first test)
##
## `register` is the documented escape hatch for "a caller that composes an event in
## code (a test)". Both of its refusal branches used to `_events.erase(key)` and
## `_ids.erase(...)` — so a malformed probe reusing a SHIPPED id removed that shipped
## def for every reader in the process. `_reject` also reported the refusal under
## `key`, which by then was a lie in the other direction: the entry said "rejected"
## about an id that was serving perfectly good content. Refusing a def is a decision
## about that def; erasing a different one is not a decision at all.
##
## ## 2. `event_ids()` WAS NOT IN STRING ORDER (this file's second test)
##
## `_ids.sort()` sorts an `Array[StringName]`, which Godot does not specify to order
## by the interned string. Measured on the shipped eight: two loads of the SAME tree
## returned two different orders. That is not cosmetic — `EventApi.available` walks
## the list in order and the pulse opens the first entry, so which event a pull opens
## was decided by resource load order. `EventState.active_ids` had already solved this
## and said why; the catalog had not.
##
## ## What these tests deliberately do NOT do
##
## Neither test names `the_favour_of_elder_wei`, and neither drives a pulse. The
## observable that was actually broken is in `WorldPulse._open_available` and is owned
## by that file; asserting it here would be a test in the wrong place that reads as
## coverage of the catalog when it is coverage of the composition root.

## A SHIPPED id, deliberately. `the_stone_that_answering` is the only one-stage event
## the tree ships and the only one with no trigger, so the assertions below can never
## be satisfied by a surviving def that merely happens to look registered — a refusal
## that left it registered but emptied would read the same way through `has`.
const SHIPPED := &"the_stone_that_answering"

## A second shipped id, used only to prove the def the catalog serves afterwards is
## the ONE THE TREE AUTHORED rather than the object the probe handed it. Comparing
## display names is the observable: the probe renames it, so a catalog that swapped
## them would be caught even though `has()` would still be true.
const ALSO_SHIPPED := &"the_riven_peak_disaster"


## **The data-destruction invariant, as one assertion.** A hand-built def offered
## under an id the tree already ships is REFUSED, and the shipped def is still there
## afterwards — same object, still answering with the authored display name.
##
## The probe is MALFORMED on purpose (`kind: "doomsday"` is not one of
## `EventDef.KINDS`), because that is the branch that used to erase. A well-formed
## duplicate takes the `duplicate id` branch, which never touched `_events`; pinning
## only that one would leave the destructive half of the bug unpinned and green.
func test_a_malformed_def_registered_under_a_shipped_id_does_not_erase_that_shipped_def() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	var before := catalog.event_definition(SHIPPED)
	assert_ne(before, null, "the shipped tree has the event this probes")
	var authored_name := String(before.display_name)

	var probe := EventDef.new()
	probe.id = SHIPPED
	probe.display_name = "A Probe That Should Never Ship"
	probe.kind = &"doomsday"
	assert_eq(catalog.register(probe), false, "a def with an unknown kind is refused")

	var after := catalog.event_definition(SHIPPED)
	assert_ne(after, null, "and the shipped def is STILL in the catalog afterwards")
	assert_eq(
		String(after.display_name),
		authored_name,
		"still the one the tree authored, not the object the probe handed it"
	)
	assert_eq(
		catalog.event_ids().has(String(SHIPPED)),
		true,
		"and the id is still in the list `available` walks"
	)


## The same claim on the WELL-FORMED duplicate branch, because the two refusal
## branches are separate lines of code and a fix to one of them proves nothing about
## the other.
##
## This is the branch the erasure was reported on, and it is also the one a reader is
## most tempted to treat as "replacing" — so it asserts BOTH halves: the probe is
## refused, AND the first def is the one that survives.
func test_a_second_def_for_a_shipped_id_is_refused_and_the_first_one_survives() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	var before := catalog.event_definition(ALSO_SHIPPED)
	assert_ne(before, null, "the shipped tree has the second probe target")
	var authored_name := String(before.display_name)

	var probe := EventDef.new()
	probe.id = ALSO_SHIPPED
	probe.display_name = "A Second Claim On A Shipped Id"
	probe.kind = EventDef.KIND_DISASTER
	assert_eq(catalog.register(probe), false, "a duplicate id is refused")

	var after := catalog.event_definition(ALSO_SHIPPED)
	assert_ne(after, null, "and the first def is still registered")
	assert_eq(
		String(after.display_name),
		authored_name,
		"the FIRST def wins the id; a later claim never replaces shipped content"
	)


## **A refusal is reported, and reporting it does not lie.** The `rejected` list is the
## only way an author learns a def was refused, so it has to describe the ref. It is
## asserted here because the erased branch left it claiming `SHIPPED` was rejected
## while that same id was serving a perfectly good `.tres` to every other caller.
func test_a_refused_duplicate_is_reported_without_claiming_the_shipped_def_was_rejected() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	var probe := EventDef.new()
	probe.id = SHIPPED
	probe.display_name = "A Third Claim"
	probe.kind = EventDef.KIND_RARE_TREASURE
	assert_eq(catalog.register(probe), false, "the duplicate is refused")

	var reasons := ""
	for entry in catalog.rejected():
		if String(entry["id"]) == String(SHIPPED):
			reasons = String(entry["reason"])
	assert_ne(reasons, "", "the refusal is reported: %s" % str(catalog.rejected()))
	assert_eq(
		reasons.begins_with("duplicate id"),
		true,
		"as a DUPLICATE rather than as the shipped def being rejected: %s" % reasons
	)


## **`event_ids()` is in STRING order, not in load order.**
##
## The comparison is spelled out rather than done through `Array[StringName].sort()`,
## because that call is exactly the thing under test: it does not order by the
## interned string, so asserting that `sort()` sorted would be asserting the bug.
## `EventState.active_ids` carries the same comparison and the same reason, which is
## what makes this a catalog that was missed rather than a rule invented here.
func test_event_ids_are_ordered_by_string_value_and_not_by_load_order() -> void:
	_reload()
	var ids := EventCatalog.instance().event_ids()
	assert_ne(ids.size() > 1, true, "the tree has more than one event, so an order exists")

	var as_strings: Array[String] = []
	for event_id in ids:
		as_strings.append(String(event_id))
	var by_string := as_strings.duplicate()
	by_string.sort()
	assert_eq(
		as_strings,
		by_string,
		(
			(
				"the catalog's order must be the STRING order, because `available` walks "
				+ "it and the pulse opens the first entry: %s"
			)
			% as_strings
		)
	)


## ## Fixtures


## Drop the cache and re-walk the tree, so a suite that ran before this one cannot
## leave a hand-built def registered under a shipped id and make every assertion below
## describe THAT instead of the shipped tree. `EventCatalog` is a process-wide
## singleton and the runner shares one process across every suite, so this is the
## honest reset — and it is asserted to have worked rather than assumed.
func _reload() -> void:
	EventCatalog.instance().reload()
	assert_eq(
		EventCatalog.instance().event_definition(SHIPPED) != null,
		true,
		"the shipped tree really was re-read before this test's probe"
	)
