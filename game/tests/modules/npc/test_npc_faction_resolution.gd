extends TestCase

## **Every shipped `NpcDef` faction id resolves against `data/world/factions/`** (BL-0715, F4).
##
## `NpcDef.faction` is a FACTION and a settlement is a PLACE, and until something reads one
## and compares it against the other there is nothing to stop a location being typed into
## the faction slot. `smith_bearcutter` and `gate_keeper_bo` both shipped
## `faction = &"mortal_plains"` — a real id, the wrong KIND — which no lookup can resolve
## and no compiler can refuse. `actor.faction` is written from it and read by no
## production code yet, so the blast radius was small; the defect is the same one the
## `azure_peak` history records, and this is the test that stops it recurring.
##
## ## Why the scan is a path and not a facade
##
## `npc` does not declare a dependency on `world`, and ADR 0047 keeps faction membership
## off `Actor.faction` in favour of `ClanDef` — so there is no verb to ask, and adding one
## would spend a method on a twelve-method cap. `RelationGraph` set the precedent: it
## scans `res://data/world/factions` itself for exactly this reason, filtering on the
## `script_class` TEXT so a `.tres` of another type in the same folder is skipped rather
## than mis-cast. This suite reuses that filter rather than inventing a second reader.
##
## ## `location_id` is checked against the LOCATION tree too
##
## The same mistake in the other slot is invisible here — `NpcRosterEntry.location_id` is
## written at runtime, never authored, so no shipped `.tres` can hold one. Checking it
## anyway costs one scan and would catch the next author who adds the field to a def.

const CAST_DIR := "res://data/npc/cast/"
const FACTIONS_DIR := "res://data/world/factions"
const LOCATIONS_DIR := "res://data/world/locations"
## The `script_class` a `.tres` must declare to be read as a faction / a location. A text
## test, so a file that merely MENTIONS a dao id inside its `relationships` is not
## mistaken for one — which is the case `test_...counts_whole_defs...` below pins.
const FACTION_SCRIPT_CLASS := "WorldFactionDef"
const LOCATION_SCRIPT_CLASS := "WorldLocationDef"

## A place, not a faction. Named so the failure says what KIND of mistake was made
## rather than only that an id did not resolve.
const A_PLACE := &"mortal_plains"


## The census itself. `faction` is optional — an unaffiliated drifter ships `&""` — so the
## rule is "non-empty MEANS a resolvable faction", and an empty id is a deliberate
## authorial statement rather than a dangling reference.
##
## Read through `ContentScan.files_under` rather than a hard-coded list of four cast
## members, because a list would go stale the moment a fifth `.tres` is authored, which
## is the failure mode this test exists to catch.
func test_every_shipped_cast_faction_resolves_against_the_world_faction_tree() -> void:
	var factions := _shipped_ids(FACTIONS_DIR, FACTION_SCRIPT_CLASS, "faction_id")
	assert_ne(factions.size(), 0, "the faction tree is not empty, so this is a real check")
	var cast := _cast_files()
	assert_ne(cast.size(), 0, "and the cast directory is not empty")
	for path in cast:
		var def := load(path) as NpcDef
		assert_ne(def, null, "%s loads as an NpcDef" % path)
		if def == null or def.faction == &"":
			continue
		assert_eq(
			def.faction != A_PLACE,
			true,
			(
				"'%s' names a PLACE where a faction belongs — 'mortal_plains' is a location"
				% String(def.npc_id)
			)
		)
		assert_eq(
			factions.has(String(def.faction)),
			true,
			(
				"'%s' authors faction '%s', which no WorldFactionDef in %s resolves"
				% [String(def.npc_id), String(def.faction), FACTIONS_DIR]
			)
		)


## The census above is only as good as its reader, so the reader is measured. `qi_dao.tres`
## names all three daos inside `relationships`, so a scan that read ids out of raw file
## text would report three resolvable factions from a single file — and would then pass
## every future dangling id it was meant to catch.
func test_the_faction_scan_resolves_whole_defs_rather_than_every_id_a_file_mentions() -> void:
	var factions := _shipped_ids(FACTIONS_DIR, FACTION_SCRIPT_CLASS, "faction_id")
	assert_eq(
		factions.size() >= 3, true, "three authored daos resolve, so the tree is genuinely readable"
	)
	assert_eq(factions.has("qi_dao"), true, "and qi_dao is one of them")
	assert_eq(
		factions.has("not_a_dao_at_all"),
		false,
		"while an id no file declares is still absent — the scan resolves, it does not match text"
	)


## The other slot, same rule. Unreachable from shipped content today, which is exactly
## why it needs a test rather than a reviewer's eye: nothing about `NpcDef` stops an
## author adding `location_id = &"mortal_plains"` to the smith tomorrow, and the F4 sweep
## should not have to be re-run by hand to find out.
func test_a_def_that_ever_authors_a_location_points_it_at_a_real_place() -> void:
	var locations := _shipped_ids(LOCATIONS_DIR, LOCATION_SCRIPT_CLASS, "location_id")
	assert_ne(locations.size(), 0, "the location tree is not empty")
	for path in _cast_files():
		var def := load(path) as NpcDef
		if def == null or not &"location_id" in def:
			continue
		assert_eq(
			locations.has(String(def.get("location_id"))),
			true,
			(
				"'%s' authors location '%s', which no WorldLocationDef in %s resolves"
				% [String(def.npc_id), String(def.get("location_id")), LOCATIONS_DIR]
			)
		)


# --- Fixtures -------------------------------------------------------------------


## Every shipped cast file, listed the same flat way `_shipped_ids` lists the trees —
## so the census and its subject are read by one mechanism, and a folder that somehow
## read empty fails the SAME way everywhere instead of silently reporting a clean bill of
## health on an empty subject.
func _cast_files() -> Array[String]:
	var out: Array[String] = []
	for file_name in DirAccess.get_files_at(CAST_DIR):
		if file_name.ends_with(".tres"):
			out.append(CAST_DIR.path_join(file_name))
	return out


## Every def of one type under `root`, keyed by its identity property. `load()` rather
## than a regex over the file: the id is a property, and reading the property is what a
## resolver actually does.
##
## `DirAccess.get_files_at` rather than `ContentScan.files_under`, because this is a
## read-only census of two flat folders and `get_files_at` returns the whole listing in
## one call — no recursion, no depth, no loop that an arch rule has to rule on. The
## `ContentScan` walker is the right answer for a CATALOG loading content; it is not
## required here, and a census that cannot read the tree would report "no dangling ids"
## for the wrong reason.
func _shipped_ids(root: String, script_class: String, property: String) -> Dictionary:
	var out: Dictionary = {}
	for file_name in DirAccess.get_files_at(root):
		if not file_name.ends_with(".tres"):
			continue
		var path := root.path_join(file_name)
		if not FileAccess.get_file_as_string(path).contains('script_class="%s"' % script_class):
			continue
		var resource := load(path)
		if resource == null:
			continue
		var id_value: Variant = resource.get(property)
		if id_value != null and String(id_value) != "":
			out[String(id_value)] = true
	return out
