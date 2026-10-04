extends TestCase

## BL-0054: **the authored event tree, audited.**
##
## Split out of `test_event.gd`, which asserts what the DIRECTOR does and passed the
## 1000-line lint cap once this section moved here. The split is by responsibility,
## not by convenience: every test here reads `res://data/event/events/` and asserts
## about content, where `test_event.gd` builds actors and drives the world. The two
## never share a fixture, which is why this file needs no helper but `_verb_texts`.
##
## ## Why the tree gets its own suite at all
##
## ADR 0077's standing warning is that an ADR can describe a spine with not one of
## its named symbols present. BL-0054 names seven kinds and a content tree; a
## director that ships neither is shipped. So these tests hold the line between them:
## every named kind has an event, every authored verb is one the gate reads, every
## location and every prize names content the build actually ships, and a def that
## cannot open is REPORTED rather than silently absent.
##
## **An empty `problems()` list is the audited state.** Every assertion below fails
## loudly on one authored `.tres` rather than on a player failing to open an event
## that was locked by a typo.

const WAR := &"war_of_the_nine_fords"
const TREASURE := &"the_stone_that_answering"

## BL-0054's named list. A tree that ships none of these has not closed BL-0054.
const NAMED_KINDS: Array[StringName] = [
	EventDef.KIND_SECT_WAR,
	EventDef.KIND_TOURNAMENT,
	EventDef.KIND_BEAST_TIDE,
	EventDef.KIND_AUCTION,
	EventDef.KIND_DISASTER,
	EventDef.KIND_DEMONIC_INVASION,
	EventDef.KIND_RARE_TREASURE,
]


func test_the_catalog_ships_one_event_for_every_kind_bl_0054_names() -> void:
	var report := EventApi.catalog()
	for kind in NAMED_KINDS:
		assert_eq(
			int((report["by_kind"] as Dictionary).get(String(kind), 0)) >= 1,
			true,
			"BL-0054 names %s and the tree ships none" % kind
		)
	assert_eq(int(report["count"]) >= 6, true, "at least six authored events")
	assert_eq(
		(report["problems"] as Array).size(),
		0,
		"and no content defect: %s" % str(report["problems"])
	)
	assert_eq((report["rejected"] as Array).size(), 0, "and nothing rejected")


func test_no_authored_trigger_names_a_verb_this_module_cannot_read() -> void:
	# The tool-facing half of `catalog()`: a typo in a `.tres` is caught here rather
	# than by a player failing to open the event it locked.
	var unknown := EventApi.catalog()["unknown_verbs"] as Array
	assert_eq(
		unknown.size(),
		0,
		"every authored requirement names a known verb: %s" % ", ".join(_verb_texts(unknown))
	)


func test_every_authored_event_is_tied_to_a_location_the_world_module_ships() -> void:
	# ADR 0113: the playfield is a `WorldLocationDef` reference. An event pointing at a
	# place that does not exist is an event nobody can open.
	var shipped: Array[String] = []
	for row in WorldApi.locations(null):
		shipped.append(String(row["location_id"]))
	assert_eq(shipped.size() >= 4, true, "the world module ships locations to check against")
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		assert_eq(
			shipped.has(String(def.location_id)),
			true,
			(
				"%s is tied to location '%s', which the world module does not ship"
				% [String(event_id), String(def.location_id)]
			)
		)


func test_every_authored_prize_names_content_the_build_actually_ships() -> void:
	# The authored tree may only name ids that exist, or the gate and the prize refuse
	# forever — which is exactly what DEF-0105/0106/0107 recorded about unreachable
	# gates. A fate the destiny catalog does not define would silently pay nothing.
	var report := EventApi.catalog()
	var war: Dictionary = (report["events"] as Dictionary)[String(WAR)]
	assert_eq(bool(war["is_conflict"]), true, "the sect war is authored as a conflict")
	for event_id in EventCatalog.instance().event_ids():
		var def := EventCatalog.instance().event_definition(event_id)
		for row in def.pay:
			var kind := StringName(row.get("kind", ""))
			var id := StringName(row.get("id", ""))
			if kind == EventDef.PAY_FATE or kind == EventDef.PAY_DESTINY:
				var catalog := FateCatalog.instance()
				var known := (
					catalog.fate_definition(id) != null
					if kind == EventDef.PAY_FATE
					else catalog.destiny_definition(id) != null
				)
				assert_eq(
					known,
					true,
					(
						"%s pays %s '%s', which the destiny catalog does not ship"
						% [String(event_id), String(kind), String(id)]
					)
				)
			if kind == EventDef.PAY_NATION_STANDING:
				assert_ne(
					String(id),
					"",
					(
						"%s pays nation standing but names no polity to read the declaration from"
						% String(event_id)
					)
				)


func test_an_event_def_walk_is_not_vacuous() -> void:
	# A structural test that reads no files proves nothing. Prove the catalog is
	# actually loaded before every assertion above is believed.
	var ids := EventCatalog.instance().event_ids()
	assert_eq(ids.size() >= 6, true, "the catalog loaded: %d events" % ids.size())
	assert_eq(EventCatalog.instance().has(WAR), true, "the war is in it")
	assert_eq(EventCatalog.instance().has(TREASURE), true, "and the treasure")


func test_a_malformed_def_is_rejected_and_reported_rather_than_silently_absent() -> void:
	# An event that loads and can never open is the shape ADR 0077 named. A refusal
	# that is REPORTED is a content bug the author finds.
	var bad := EventDef.new()
	bad.id = &"an_event_with_a_kind_nobody_reads"
	bad.display_name = "Bad"
	bad.kind = &"doomsday"
	var accepted := EventCatalog.instance().register(bad)
	assert_eq(accepted, false, "a def with an unknown kind is refused")
	var reported: Array[Dictionary] = EventCatalog.instance().rejected()
	var named := false
	for entry in reported:
		if String(entry["id"]) == "an_event_with_a_kind_nobody_reads":
			named = true
	assert_eq(named, true, "and it is reported with its reason: %s" % reported)


## Hand the process-wide cache back the way this file found it.
##
## This test's probe is refused, and a refusal is CUMULATIVE: the entry
## `the_favour_of_elder_wei: rejected (... names kind 'doomsday' ... <registered>)`
## lands in `_rejected` and `problems()` walks `_rejected`, so it describes every later
## read of the shipped tree — in this file and in any file that runs after it. The line
## names the SHIPPED id because the probe was registered under a shipped id, which is
## what makes it read like a content defect in a tree that is clean.
##
## This used to be restored inline at the end of the test body, on the grounds that
## "only this test dirties it". That was the wrong axis: the dirt is harmless until a
## LATER file reads the tree, and an inline restore cannot run if the body aborts. The
## runner calls `teardown` after EVERY test whether or not the body finished
## (`tests/run_tests.gd:126`), so that is where the reset belongs, and it is why the
## probe itself is kept.
func teardown() -> void:
	EventCatalog.instance().reload()


# --- Plumbing ---------------------------------------------------------------


## One readable line per unknown verb, so a failing assertion names the event, the
## half of the tree it was found in and the verb — rather than printing an array of
## dictionaries whose keys the reader has to guess.
func _verb_texts(unknown: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in unknown:
		out.append(
			(
				"%s(%s) names '%s'"
				% [
					String((entry as Dictionary)["event_id"]),
					String((entry as Dictionary)["where"]),
					String((entry as Dictionary)["verb"])
				]
			)
		)
	return out
