extends TestCase

## ## Why this suite exists under `modules/npc/` when the catalog is `modules/event/`
##
## BL-0747 shipped a real fix — `EventCatalog._admit` no longer erases the def already
## holding an id when it refuses one, and it stops handing back an id list in whatever
## order the ids happened to be interned in — and **no test in the repository could
## tell.** The auditor restored the whole original bug: both `_events.erase(key)` /
## `_ids.erase(...)` branches and `_ids = _ids` in place of `_sorted_ids(_ids)` — and
## `--suite test_npc` returned `508 passed, 0 failed`.
##
## Two reasons that suite is green either way, and both are structural rather than
## accidental:
##
##   1. **`reload()` exists for tests only.** `EventCatalog.instance().reload()` is the
##      documented escape hatch for "a suite that authored a def in code". So the erase can
##      only ever manifest *in-process*, and a suite that never calls `register` never sees
##      it.
##   2. **The npc suites never register into the catalog at all.** Grep is decisive: over
##      `game/tests`, `EventCatalog.instance().register` appears in exactly TWO files —
##      `tests/app/test_world_pulse_open_budget.gd` and `tests/modules/event/
##      test_event_content.gd`. Neither is an npc suite. So the destructive path had no
##      npc-side caller to be damaged by, and "the elder's ladder depends on that catalog"
##      was a true statement about the game that no npc test exercised.
##
## This file closes the hole on the npc side without moving the npc module: it drives the
## SAME public surface (`EventCatalog.instance()`), uses no `npc/` private state, and is
## filtered out of every other suite's run, so the assertion the audit wanted cannot be
## satisfied by content that only exists in this file's directory.
##
## ## ## Why the ORDER tests below REGISTER probes, and why the first version of them
## ## could not fail
##
## The obvious order test — "reload twice, the two reads agree, and the result is the
## string order" — **is green against the bug**, and it was green in the first version of
## this file. Two reasons, both measured rather than argued:
##
##   - **Two reads of one tree agree under any implementation.** `_scan` sorts its paths
##     and `reload()` re-walks the same eight files, so admission order is identical on
##     every read within a process. "Two observations agree" is a claim about the
##     harness, not about the code under test.
##   - **The shipped tree cannot show the difference.** The eight `.tres` files are named
##     after their ids, so `_scan`'s path sort admits them in string order already. An
##     unsorted `_ids = _ids` therefore returns the *identical* array, and "the result is
##     the string order" is satisfied by the same array that is the bug.
##
## So the assertion has to be a property of the ORDER ITSELF, computed independently: the
## ids are compared **as strings**, against an `Array[String].sort()` the test performs
## itself, and the admission order is **perturbed on purpose** so the two can disagree.
## `Array[StringName].sort()` is never the expected value here — asserting that `sort()`
## sorted would be asserting the bug (BL-0747 measured it ordering by interned pointer).
##
## That is what makes these tests falsifiable: with `event_catalog.gd:165` set back to
## `_ids = _ids`, the three tests below each go red, and the reported `got` array is
## visibly tail-unsorted.

## A shipped event id, named literally rather than read off the catalog. The failure being
## pinned is SILENT CONTENT LOSS, so the id must not come from `event_ids()[0]`: an
## already-destroyed catalog names nothing and the test would pass by having no target.
const SHIPPED := &"the_stone_that_answering"

## Where the catalog's own source lives, read by the structural pin at the bottom.
const CATALOG_SOURCE := "res://src/modules/event/event_catalog.gd"

## Three well-formed probe ids registered in DELIBERATE reverse-alphabetical order. Two
## properties make them falsifiable against `_ids = _ids`:
##
##   - they sort **after** every shipped id (they all begin `probe_zz_…`, and the shipped
##     ids begin `auction_`, `beast_`, `the_`, `tournament_`, `war_`), so under a removed
##     sort they land as an unsorted TAIL rather than being lost in the middle; and
##   - they are registered out of order, so admission order and string order cannot both
##     be satisfied by the same array.
const REVERSE_ALPHA_PROBES: Array[String] = [
	"zz_probe_third",
	"zz_probe_first",
	"zz_probe_second",
]

## One well-formed probe whose id sorts strictly BETWEEN two shipped ids, so its reported
## POSITION is a falsifiable fact rather than a tautology. `c` < `m` < `t`:
## `beast_tide_…` < `catalog_probe_between` < `the_dawn_descent`. It is admitted LAST, which
## is what makes an append-only catalog wrong about it.
const BETWEEN_PROBE := &"catalog_probe_between"


## ## The dependency the elder's ladder actually has, asserted directly.
##
## `npc_tally` beats are the ONLY way an npc's rung verb arrives (`the_favour_of_elder_wei`
## authors `favours` and `oaths_sworn`; `NpcBoot.install` injects `NpcApi.tally` into
## `EventBeatWriter`), so the whole ladder rests on event defs resolving out of this
## catalog. A refusal that erases one is not a cosmetic bug — it is a dead rung.
func test_the_catalog_still_serves_the_event_the_elders_ladder_reads() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	assert_ne(catalog.has(SHIPPED), false, "the shipped event is in the catalog")
	assert_eq(catalog.problems().size(), 0, "and the shipped tree has no problems")


## ## The mutation the audit restored, reproduced here on purpose.
##
## A malformed probe carrying a SHIPPED id — the branch that used to
## `_events.erase(key)` and `_ids.erase(...)`. Asserted from the npc side so the npc suite
## fails when the catalog's refusal starts destroying content again, whatever reason the
## fix has since been rewritten for.
func test_a_probe_cannot_destroy_a_shipped_event_the_elders_ladder_needs() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	var authored := String(catalog.event_definition(SHIPPED).display_name)

	var probe := EventDef.new()
	probe.id = SHIPPED
	probe.display_name = "A Probe That Should Never Ship"
	probe.kind = &"doomsday"
	assert_eq(catalog.register(probe), false, "a def with an unknown kind is refused")

	assert_eq(catalog.has(SHIPPED), true, "and the shipped event is STILL there afterwards")
	assert_eq(
		String(catalog.event_definition(SHIPPED).display_name),
		authored,
		"still the tree's def, not the probe's"
	)
	assert_eq(
		catalog.event_ids().has(String(SHIPPED)),
		true,
		"and still in the list `available` walks in order"
	)


## ## THE ORDER, as a property of the order: test_the_catalogs_order_is_the_string_order
##
## `EventApi.available` walks `event_ids()` in order and `WorldPulse` opens the FIRST
## eligible one, so the order is a decision, not a presentation detail. The expected value
## is computed **in this test**, as `Array[String].sort()` over the ids read back as
## strings — never by calling the catalog's own sort, which is the call under test.
##
## The admission order is perturbed (three well-formed defs registered in reverse
## alphabetical order, after the shipped tree) because the bare tree cannot express a
## difference: every shipped file is named after its id, so `_scan` admits them in string
## order and an unsorted catalog is indistinguishable from a sorted one. With the sort
## removed this reports `…, "war_of_the_nine_fords", "probe_zz_probe_third",
## "probe_zz_probe_first", "probe_zz_probe_second"]` — a visibly unsorted tail — against an
## expectation ending `…, "probe_zz_probe_second"]`.
func test_the_catalogs_order_is_the_string_order_not_merely_a_stable_order() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	# Touch the shipped tree first, so the probes append AFTER it and the only thing that
	# can make this array unsorted is the missing sort.
	assert_eq(
		catalog.event_ids().size() > 1,
		true,
		"the shipped tree is read before the probes, so an order exists to be wrong"
	)
	_register_reverse_alphabetical_probes()

	var got := _ids_as_strings(catalog.event_ids())
	var want := got.duplicate()
	want.sort()
	assert_eq(
		got,
		want,
		(
			(
				"the catalog's order must be the STRING order regardless of admission order, "
				+ "because `WorldPulse` opens the FIRST entry `EventApi.available` offers: %s"
			)
			% [got]
		)
	)


## ## THE ORDER as a POSITION between two named neighbours, which is what the pulse reads
##
## "The array is sorted" is a claim about the whole list; this is the claim `WorldPulse`
## actually depends on. `EventApi.available` walks `event_ids()` and the pulse opens the
## FIRST eligible entry, so what matters is *where* an id sits relative to the ids around
## it. A probe whose id sorts between `beast_tide_of_the_mortal_plains` and
## `the_dawn_descent` must therefore be reported BETWEEN those two, and not at the end of
## the array where it was registered.
##
## It is deliberately NOT "two reads of one tree agree". That formulation was the first
## version of this guard and it cannot fail: `_scan` sorts its paths and `reload()`
## re-walks the same files, so both reads get an identical admission order under ANY
## implementation. Agreement between two identical inputs is a fact about the harness, not
## a property of the code. What makes two observations comparable here is that the second
## one is pinned against two NAMED neighbours, which is data the catalog cannot reorder.
func test_a_registered_event_lands_at_its_authored_place_and_not_where_it_was_registered() -> void:
	_reload()
	var catalog := EventCatalog.instance()
	# The two shipped ids the probe must fall between. Named literally rather than read at
	# an index: an index would move when the catalog's sort is removed, which is precisely
	# the thing under test.
	var before := &"beast_tide_of_the_mortal_plains"
	var after := &"the_dawn_descent"
	assert_eq(
		catalog.has(before) and catalog.has(after),
		true,
		"the two shipped neighbours the probe is placed between both exist"
	)

	var probe := EventDef.new()
	probe.id = BETWEEN_PROBE
	probe.display_name = "A Probe That Sorts Between Two Shipped Ids"
	probe.kind = EventDef.KIND_DISASTER
	assert_eq(catalog.register(probe), true, "the well-formed probe is admitted")

	var got := _ids_as_strings(catalog.event_ids())
	var probe_at := got.find(String(BETWEEN_PROBE))
	var before_at := got.find(String(before))
	var after_at := got.find(String(after))
	assert_eq(probe_at >= 0, true, "the probe is in the id list the pulse walks")
	if probe_at < 0 or before_at < 0 or after_at < 0:
		return
	assert_eq(
		probe_at > before_at,
		true,
		"'%s' sorts after '%s', so it must be reported after it: %s" % [BETWEEN_PROBE, before, got]
	)
	assert_eq(
		probe_at < after_at,
		true,
		(
			"'%s' sorts before '%s', so it must be reported before it rather than left at the end: %s"
			% [BETWEEN_PROBE, after, got]
		)
	)


## ## The structural pin: the array IS the one `_sorted_ids` produced
##
## The two tests above perturb the CONTENT, which is the stronger claim, and this one pins
## the MECHANISM, so a future rewrite cannot quietly swap in a different call that happens
## to agree on today's eight ids. It reads the catalog's source rather than calling a
## private method: a test that reached into `_sorted_ids` through `call()` would be
## asserting an implementation detail the moment it is renamed, whereas a source read says
## only the two things that matter and cannot drift into overclaiming.
func test_the_catalog_still_sorts_its_ids_through_the_string_comparison() -> void:
	var source := _comment_stripped_source(CATALOG_SOURCE)
	assert_ne(source, "", "the catalog's source is readable at %s" % CATALOG_SOURCE)
	assert_eq(
		source.contains("_ids = _ids"),
		false,
		(
			"the self-assignment `_ids = _ids` is BL-0747's bug: it hands back the admission "
			+ "order, which follows the interned StringName rather than the string"
		)
	)
	assert_eq(
		source.contains("_sorted_ids(_ids)"),
		true,
		"and the ids are re-sorted by string value on every admission"
	)


## ## Fixtures


## Three well-formed defs admitted in DELIBERATE reverse-alphabetical order, each asserting
## it was admitted so a rejected probe cannot quietly make the order test vacuous.
func _register_reverse_alphabetical_probes() -> void:
	for suffix in REVERSE_ALPHA_PROBES:
		var probe := EventDef.new()
		probe.id = &"probe_%s" % suffix
		probe.display_name = "Probe %s" % suffix
		# A real member of `EventDef.KINDS`, a non-empty display_name, and no stages, beats
		# or pay rows — `problems()` returns an empty array for that, so `register` reaches
		# the admission path rather than the refusal path.
		probe.kind = EventDef.KIND_DISASTER
		assert_eq(
			EventCatalog.instance().register(probe),
			true,
			"the well-formed probe 'probe_%s' is admitted" % suffix
		)


## The catalog's ids as plain strings, so the expected value can be an `Array[String]`
## sort rather than the `Array[StringName]` sort that is the bug.
func _ids_as_strings(ids: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for event_id in ids:
		out.append(String(event_id))
	return out


## One source file with every `#` comment removed. Comments are stripped because the
## catalog's own docstring NAMES the bug — the paragraph above `_sorted_ids` says
## `Array[StringName].sort()` is not specified to order by the interned string — so a
## comment-only match would let a sentence satisfy the structural pin.
func _comment_stripped_source(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ""
	var out: Array[String] = []
	for line in text.split("\n"):
		out.append(line.split("#")[0])
	return "\n".join(out)


## Reset asserted, not assumed: `EventCatalog` is a process-wide singleton and the runner
## shares one process across every suite. `teardown` runs after EVERY test, so the probes
## the order tests register cannot leak into whichever suite runs next.
func _reload() -> void:
	EventCatalog.instance().reload()
	assert_eq(
		EventCatalog.instance().has(SHIPPED),
		true,
		"the shipped tree really was re-read before this test's probe"
	)


func teardown() -> void:
	EventCatalog.instance().reload()
