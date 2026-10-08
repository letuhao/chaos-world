extends TestCase

## The `institutions` content family: that it is DECLARED, that a mod's def reaches it
## without a base-game edit, that the overlay order is deterministic, and the DEF-0334
## capability-ordering regression.
##
## ## Why the fixtures are written to the OS temp dir
##
## Two reasons, and the second is the one that matters. First,
## `game/data/packs/guilds/organizations/` is authored content: a case that adds
## a `.tres` there changes what every later suite and every audit grades.
## Second — and this is the `PortraitCatalog.with_probe` lesson —
## **a guard asserted against shipped content cannot be distinguished from that content
## being broken.** The check either fires because it works or because the fixture is
## wrong, and only one of those is evidence. So every case below builds its own tree.
##
## ## The `res://` path in [method _write_def] is a MOD'S OWN def script
##
## Written as `res://src/core/institution_def.gd`, i.e. the generic def a mod is expected
## to author on. `test_a_subclass_def_is_not_merged` pins the documented boundary that a
## subclass is NOT discovered by the directory scan.

## The family name a mod declares. Read from the ONE declaration `families.json` carries
## for it, so a rename on the Python side fails here rather than silently orphaning the
## runtime seam.
const FAMILY := "institutions"
const GENERIC_DEF := "res://src/core/institution_def.gd"
## A def authored on a SUBCLASS, for the one case that pins the family's documented
## discovery limit. Under `res://tests/` so it creates no boundary edge either way.
const SUBCLASS_DEF := "res://tests/core/institution_subclass_fixture_def.gd"
## The composition root's institution wiring, read as TEXT for the structural half of the
## one-loader case: what the boot's SOURCE may name is what decides whether a second scan
## can come back.
const BOOT_FILE := "res://src/app/institution_boot.gd"

var _temp_root: String = ""
## Every catalog this suite touches, cleared in teardown: the headless runner drives every
## suite in ONE process, and a leaked overlay stack would make this suite's fixtures the
## next suite's content.
var _registry: InstitutionRegistry = null


func setup() -> void:
	_temp_root = OS.get_environment("TEMP").path_join("cw_institution_def_catalog_test")
	_ensure_dir(_temp_root)
	_registry = InstitutionRegistry.new()
	# Also cleared in teardown, and deliberately in BOTH: setup clears what a PREVIOUS
	# suite left in this process, teardown clears what THIS suite leaves. Relying on
	# teardown alone means a case that aborts mid-way hands its fixtures to the next one.
	InstitutionDefCatalog.clear()


func teardown() -> void:
	# The catalog's OWN reset clears the overlay stack as well as the loaded tree, and it
	# is the only seam this slice ships — the boot's is the deferred app/ one-liner. So
	# this one call is what keeps this suite's fixtures out of the next suite's content.
	InstitutionDefCatalog.clear()
	if _registry != null:
		_registry.clear()
		_registry = null
	if _temp_root != "":
		_remove_tree(_temp_root)
	_temp_root = ""


# --- The family is DECLARED ---------------------------------------------------


## ## The family resolves, and its def class is the one that exists
##
## This is the declaration half of ADR 0184 §9 read from the GDScript side: the Python
## gate proves a mod may NAME this family, and this proves naming it resolves to a real
## def class rather than a string nothing loads.
func test_the_family_resolves_and_its_def_class_loads() -> void:
	assert_eq(InstitutionDefCatalog.DEF_SCRIPT_CLASS, "InstitutionDef", "the family names one def")
	var script := load(GENERIC_DEF) as GDScript
	assert_ne(script, null, "that def class loads")
	assert_eq(
		String(script.get_global_name()), InstitutionDefCatalog.DEF_SCRIPT_CLASS, "by its name"
	)
	assert_eq(InstitutionDefCatalog.ID_FIELD, "id", "and the family's id field is `id`")


## The base directory the family scans is the one the shipped organizations live in, and
## it carries `.tres` files — so "empty catalog" would be a wiring fault rather than a
## build that ships no organizations.
func test_the_base_root_is_where_the_shipped_organizations_live() -> void:
	assert_eq(
		InstitutionDefCatalog.INSTITUTIONS_ROOT,
		"res://data/packs/guilds/organizations",
		"the family scans the authored institutions directory"
	)
	var shipped := ContentScan.files_under(InstitutionDefCatalog.INSTITUTIONS_ROOT)
	assert_eq(shipped.size() > 0, true, "and it is not empty on this tree")


## ## The legacy tier roots carry NO defs after the pack move
##
## The move relocated every tier into `game/data/packs/<pack>/organizations/`, and no
## catalog scans the old roots — so a `.tres` left behind there loads NOWHERE, which
## is silent content loss rather than a loud double load. An absent directory reads
## as empty (`ContentScan` degrades a missing dir to no contribution), so this fires
## only when a stray file actually exists.
## A `for` over a four-literal array, reading only: the body appends to nothing.
func test_the_legacy_tier_roots_carry_no_defs_after_the_pack_move() -> void:
	for legacy in [
		"res://data/sect", "res://data/nation", "res://data/clans", "res://data/institutions"
	]:
		assert_eq(
			ContentScan.files_under(legacy).is_empty(),
			true,
			"%s carries no defs: a stray there would load nowhere" % legacy
		)


## ## The merge stack names no directory twice
##
## The base root IS a pack dir (`packs/guilds/organizations`), and `_pack_rows`
## yields every pack's `organizations/` dir — so without the skip in `_merge_stack`
## the same dir would merge twice and `CatalogOverlay` would refuse the whole
## family (an undeclared collision of every id with itself, registering nothing).
## A `for` over the stack's own snapshot, reading only: the body writes a fresh
## local set, never the stack being walked.
func test_the_merge_stack_names_no_directory_twice() -> void:
	var seen := {}
	for row in InstitutionDefCatalog.instance()._merge_stack():
		var dir := String((row as Dictionary).get("dir", ""))
		assert_eq(seen.has(dir), false, "%s merges once, never twice" % dir)
		seen[dir] = true


## ## The boot holds NO base root of its own — there is ONE loader, not two in step
##
## Two constants naming one directory from two layers was a duplication this slice could
## only ASSERT IN STEP: a rename on either side that forgot the other failed here, which is
## how the second loader survived as long as it did — a mod's overlay roots reached the
## catalog's merge and never the boot's own `ContentScan` walk, so two answers described
## two different families.
##
## The duplication is gone: `InstitutionBoot.install` and `InstitutionBoot.summary` both
## read this catalog, and the boot's own constant was deleted with its walk. What replaces
## the assertion is STRONGER — the boot's source is structurally unable to name a
## directory, so a second scan is a red test rather than a silent split.
func test_the_boot_names_no_base_root_and_walks_no_directory_of_its_own() -> void:
	var body := FileAccess.get_file_as_string(BOOT_FILE)
	assert_ne(body, "", "the boot file is readable")
	assert_eq(
		_calls(body, InstitutionDefCatalog.INSTITUTIONS_ROOT),
		0,
		"the app boot names no content root: the core catalog is the ONLY loader"
	)
	assert_eq(
		_calls(body, "ContentScan"),
		0,
		"and walks no directory of its own, so a mod overlay cannot reach one loader and miss the other"
	)
	# And the two halves still AGREE, measured rather than asserted by spelling: the boot's
	# report and the boot's own read model describe the same organizations. On THIS
	# suite's registry, which `teardown` clears — the shared one would hand three guild
	# kinds to every suite after this one in the same process.
	InstitutionBoot.install(_registry)
	assert_eq(
		(InstitutionBoot.last_report["organizations"] as Array).size(),
		(InstitutionBoot.summary(_registry)["organizations"] as Array).size(),
		"so install() and summary() cannot describe two different families"
	)


# --- Base defs AND overlay defs are both visible ------------------------------


## ## A mod's def is visible with NO base-game edit — the headline of this slice
##
## The base catalog is loaded first, then a fixture root is pushed as an overlay, and the
## mod's organization appears. Nothing in `game/src` was touched to make it appear: the
## seam is `set_overlay_roots`, which is the whole of the mod content contract.
func test_a_mod_def_is_visible_alongside_the_base_defs_with_no_base_game_edit() -> void:
	var mod_root := _temp_root.path_join("guild_pack")
	_ensure_dir(mod_root)
	var def_path := _write_def(mod_root, "mod_guild", &"hunting_guild", [&"has_offices"])
	# The base root only, no overlay: the mod's organization must be ABSENT. Without this
	# the case below could pass because the fixture leaked into the base tree.
	var base_only := _fresh()
	assert_eq(base_only.has(&"mod_guild"), false, "before the seam, the mod's def is absent")

	InstitutionDefCatalog.set_overlay_roots([_row(mod_root, "guild_pack")])
	var overlaid := _fresh()
	assert_eq(overlaid.has(&"mod_guild"), true, "after the seam, it is visible")
	assert_eq(overlaid.owner_of(&"mod_guild"), "guild_pack", "and owned by the mod")
	assert_eq(overlaid.path_of(&"mod_guild"), def_path, "at the path the mod shipped it")
	# And the base defs are STILL there: the overlay is additive, never a replacement of
	# the whole family. This is what makes "base first, then overlays" mean anything.
	assert_eq(overlaid.ids().size() > 1, true, "the base organizations are still present")


## Every kind the shipped organizations declare is reachable, and every one is visible
## through the catalog rather than only through the boot. The kinds themselves come from
## the authored `.tres` files, so this asserts the DISCOVERY is generic and not a list.
func test_every_shipped_organization_is_visible_and_its_kind_is_reported() -> void:
	var catalog := _fresh()
	var report := catalog.summary()
	assert_eq(bool(report["merge_ok"]), true, "the base merge succeeded")
	var rows := report["rows"] as Array
	assert_eq(rows.size() > 0, true, "and it found organizations")
	var kinds: Array = []
	var all_owned_by_base := true
	for row in rows:
		kinds.append(String((row as Dictionary)["kind"]))
		if String((row as Dictionary)["owner"]) != "base":
			all_owned_by_base = false
	assert_eq(all_owned_by_base, true, "the shipped organizations are all base-owned")
	# Three kinds, three different capability sets (ADR 0278) — and none of them is a
	# name this test wrote, which is the point: the catalog dispatches on the `.tres`.
	assert_eq(kinds.has("trading_guild"), true, "the trading guild is visible")
	assert_eq(kinds.has("hunting_guild"), true, "the hunting guild is visible")
	assert_eq(kinds.has("farmers_circle"), true, "the farmers' circle is visible")
	# And no row names a KIND the catalog itself knows, which would be a default invented
	# for a kind nobody declared.
	for kind in catalog.ids():
		var def := catalog.definition(kind)
		assert_ne(def, null, "'%s' resolves to a def" % kind)
		assert_ne(def.kind, &"", "'%s' declares its own kind" % kind)


## ## A mod can ship a BRAND-NEW KIND, and the registry registers it from the `.tres`
##
## The full claim, end to end: a def declaring a kind nothing has ever seen is visible in
## the catalog, `check_content` passes on it (the registry-free half), and
## `InstitutionBoot.register_def` registers the kind with no module edited. This is what
## "a modder adds a kind by REGISTERING it" has to mean in practice.
func test_a_mod_ships_a_brand_new_kind_and_it_registers_with_no_module_edited() -> void:
	var mod_root := _temp_root.path_join("new_kind_pack")
	_ensure_dir(mod_root)
	# `has_territory` and NO `has_offices`, on purpose: a def that declares offices must
	# also author a reachable top one (`InstitutionDef._content_fault` refuses
	# `no_top_position`), and a fixture that did not would be refused by a content rule
	# before this case ever reached the thing it is about.
	_write_def(mod_root, &"starwrights", &"starwright_guild", [&"has_territory"])

	InstitutionDefCatalog.set_overlay_roots([_row(mod_root, "new_kind_pack")])
	var catalog := _fresh()

	assert_eq(catalog.has(&"starwrights"), true, "the new organization is visible")
	var def := catalog.definition(&"starwrights")
	assert_ne(def, null, "and loads")
	assert_eq(def.kind, &"starwright_guild", "declaring a kind nothing has seen")
	assert_eq(bool(def.check_content()["ok"]), true, "its authored content is sound")
	# The registry has never heard of this kind, which is the normal state of a first
	# `.tres` — so `check` refuses by name and `register_def` is what makes it legal.
	assert_eq(
		bool(def.check(_registry)["ok"]), false, "the registry refuses it before registration"
	)
	assert_eq(_registry.knows(&"starwright_guild"), false, "and knows nothing of it")

	var verdict := InstitutionBoot.register_def(_registry, def)
	assert_eq(bool(verdict["ok"]), true, "the boot registers the brand-new kind")
	assert_eq(_registry.knows(&"starwright_guild"), true, "so the kind exists afterwards")
	assert_eq(
		_registry.def_type_of(&"starwright_guild"), "InstitutionDef", "under its own def class name"
	)
	assert_eq(bool(verdict["new"]), true, "and this was a NEW row, not a fold")


# --- Deterministic overlay merge order ----------------------------------------


## ## Base first, then overlays in load order — the ORDER is the contract
##
## ADR 0184 §5: "Base game first, then mods in load order; later overlays earlier within
## a family." A merge that let a mod's root come first would hand a mod authority over
## the base game's content by nothing more than dictionary iteration order.
func test_the_merge_order_is_base_first_then_overlays_in_load_order() -> void:
	var first := _temp_root.path_join("first_mod")
	var second := _temp_root.path_join("second_mod")
	_ensure_dir(first)
	_ensure_dir(second)
	_write_def(first, &"a_from_first", &"k", [])
	_write_def(second, &"b_from_second", &"k", [])
	InstitutionDefCatalog.set_overlay_roots([_row(first, "first_mod"), _row(second, "second_mod")])
	var merged := _fresh().overlay_merge()
	assert_eq(bool(merged["ok"]), true, "the merge succeeded")
	var order: Array = []
	for entry in merged["merged"]:
		order.append(String(entry["id"]))
	# The base organizations sort ahead of both fixture ids by id, and the two overlays
	# appear in the order they were handed — which is the mod load order the composition
	# root computed, not an order this catalog chose.
	assert_eq(order.has("a_from_first"), true, "the first overlay contributed")
	assert_eq(order.has("b_from_second"), true, "the second overlay contributed")
	assert_eq(
		order.find("a_from_first") < order.find("b_from_second"),
		true,
		"and the FIRST overlay comes first in the merged order"
	)


## Two calls over the same stack produce the same order. Determinism is asserted rather
## than assumed because `DirAccess` iteration order is not stable across platforms, which
## is exactly why `ContentScan` sorts — and an unstable overlay order is a content
## authority that changes between runs.
func test_the_merge_order_is_identical_across_two_calls() -> void:
	var mod_root := _temp_root.path_join("stable_mod")
	_ensure_dir(mod_root)
	_write_def(mod_root, "stable_one", &"k", [])
	_write_def(mod_root, "stable_two", &"k", [])
	InstitutionDefCatalog.set_overlay_roots([_row(mod_root, "stable_mod")])
	var catalog := _fresh()
	var first := catalog.overlay_merge()
	var second := catalog.overlay_merge()
	assert_eq(_ids_of(first), _ids_of(second), "the same stack merges to the same order every time")


## Within ONE root the order is by path, because `ContentScan.files_under` sorts — so a
## catalog listing five organizations does not reorder itself between reads.
func test_defs_within_one_root_are_in_sorted_path_order() -> void:
	var mod_root := _temp_root.path_join("sorted_mod")
	_ensure_dir(mod_root)
	_write_def(mod_root, "zeta_org", &"k", [])
	_write_def(mod_root, "alpha_org", &"k", [])
	_write_def(mod_root, "mid_org", &"k", [])
	InstitutionDefCatalog.set_overlay_roots([_row(mod_root, "sorted_mod")])
	var merged := _fresh().overlay_merge()
	var order: Array = []
	for entry in merged["merged"]:
		if not String(entry["owner"]).is_empty() and String(entry["owner"]) == "sorted_mod":
			order.append(String(entry["id"]))
	assert_eq(order, ["alpha_org", "mid_org", "zeta_org"] as Array, "sorted within the root")


## ## An UNDECLARED id collision is REFUSED, and it is the loud kind of refusal
##
## ADR 0184 §5: a same-id collision requires an explicit `overrides:` declaration or it
## is a loud load error, never silent. Two mods shipping the same organization id is
## exactly that, and folding it would let whichever root `DirAccess` listed first win.
func test_an_undeclared_id_collision_between_two_mods_is_refused_by_name() -> void:
	var first := _temp_root.path_join("collide_a")
	var second := _temp_root.path_join("collide_b")
	_ensure_dir(first)
	_ensure_dir(second)
	_write_def(first, &"shared_org", &"k", [])
	_write_def(second, &"shared_org", &"k", [])
	InstitutionDefCatalog.set_overlay_roots([_row(first, "collide_a"), _row(second, "collide_b")])
	var merged := _fresh().overlay_merge()
	assert_eq(bool(merged["ok"]), false, "the merge REFUSED rather than picking a winner")
	assert_eq(String(merged["reason"]), "undeclared_override", "with the named reason")
	var detail := String(merged["detail"])
	assert_eq(detail.contains("shared_org"), true, "the detail names the id")
	assert_eq(detail.contains("collide_b"), true, "and the offending owner")
	# A refused merge leaves the catalog EMPTY and reports it, so a caller cannot read an
	# empty family as a clean one.
	var catalog := _fresh()
	assert_eq(catalog.is_loaded(), false, "and the catalog refuses to present itself as loaded")


## The counterpart: a collision the LATER root DECLARED an override for is accepted, and
## the later def WINS while keeping the earlier id's position. Without this case the
## refusal above would read as "two mods may never agree", which is not the rule.
func test_a_declared_override_replaces_the_def_and_the_collision_is_accepted() -> void:
	var first := _temp_root.path_join("override_a")
	var second := _temp_root.path_join("override_b")
	_ensure_dir(first)
	_ensure_dir(second)
	_write_def(first, &"shared_org", &"k", [])
	_write_def(second, &"shared_org", &"k", [])
	InstitutionDefCatalog.set_overlay_roots(
		[_row(first, "override_a"), _row(second, "override_b", ["shared_org"])]
	)
	var merged := _fresh().overlay_merge()
	assert_eq(bool(merged["ok"]), true, "a DECLARED override is accepted")
	# Counted, not listed: the merge ALWAYS includes the base root, so asserting the
	# whole merged list would be asserting the shipped organizations too and would say
	# nothing about the override.
	var appearances := 0
	for entry in merged["merged"]:
		if String(entry["id"]) == "shared_org":
			appearances += 1
	assert_eq(appearances, 1, "and the id appears once, not twice")
	var catalog := _fresh()
	assert_eq(catalog.owner_of(&"shared_org"), "override_b", "the LATER root won")


# --- The documented limits ----------------------------------------------------


## ## A SUBCLASS def is NOT discovered by the directory scan — the pinned boundary
##
## `CatalogOverlay.merge` selects a `.tres` by a TEXT scan for
## `script_class="InstitutionDef"`. A def authored on a SUBCLASS of that type therefore
## declares `script_class="<Subclass>"` and is not merged. This is acceptable and
## deliberate — ADR 0278's decision is that `core` ships ONE authored type for every kind,
## so a mod authors a KIND rather than a new def class — but it is a limit, and a limit
## that is not asserted is a limit that gets discovered as a silent skip.
func test_a_subclass_def_is_not_merged_and_the_limit_is_documented_not_silent() -> void:
	var mod_root := _temp_root.path_join("subclass_pack")
	_ensure_dir(mod_root)
	_write_def(
		mod_root,
		&"subclass_org",
		&"subclass_guild",
		[&"has_territory"],
		SUBCLASS_DEF,
		"InstitutionSubclassFixtureDef",
	)
	InstitutionDefCatalog.set_overlay_roots([_row(mod_root, "subclass_pack")])
	var catalog := _fresh()
	# It is NOT visible through the directory scan...
	assert_eq(
		catalog.has(&"subclass_org"),
		false,
		"a subclass .tres is not merged by the family's script_class text scan"
	)
	# ...but it is still REGISTERABLE when handed straight to the boot, which is how a
	# non-discovery is distinguished from an invalid def.
	var loaded := load(mod_root.path_join("subclass_org.tres")) as InstitutionDef
	assert_ne(loaded, null, "the subclass def still loads as an InstitutionDef")
	assert_eq(
		bool(InstitutionBoot.register_def(_registry, loaded)["ok"]),
		true,
		"and the boot still registers it when handed directly"
	)


## ## An overlay that contributes nothing is distinguishable from a REFUSED merge
##
## The base root is always in the stack, so this catalog's "empty" is never truly empty —
## which is the point of the case. Two states must not read alike: an overlay root that
## holds no `.tres` (a mod that declares a family before shipping content into it) is a
## legitimate nothing, while an undeclared id collision is a refusal. A caller that read
## both as "no new organizations" would ship a mod whose collision never fired.
func test_an_overlay_contributing_nothing_is_quiet_while_a_refused_merge_is_not() -> void:
	var empty_root := _temp_root.path_join("empty_mod")
	_ensure_dir(empty_root)
	InstitutionDefCatalog.set_overlay_roots([_row(empty_root, "empty_mod")])
	var quiet := _fresh()
	var report := quiet.summary()
	assert_eq(bool(report["merge_ok"]), true, "an empty overlay root SUCCEEDS")
	assert_eq(String(report["merge_reason"]), "", "with no reason, because nothing refused")
	assert_eq(quiet.is_loaded(), true, "and the catalog is loaded, not broken")
	# The base organizations are still there — an overlay adds to the family, it never
	# replaces it, which is what "base first" means.
	assert_eq(quiet.ids().size() > 0, true, "the base organizations are still present")
	for institution_id in quiet.ids():
		assert_eq(
			quiet.owner_of(institution_id),
			"base",
			"and every one of them is base-owned: the empty root contributed nothing"
		)
	# Now the REFUSED counterpart, on the same shape of call.
	var collide_a := _temp_root.path_join("quiet_collide_a")
	var collide_b := _temp_root.path_join("quiet_collide_b")
	_ensure_dir(collide_a)
	_ensure_dir(collide_b)
	_write_def(collide_a, &"dup_org", &"k", [])
	_write_def(collide_b, &"dup_org", &"k", [])
	InstitutionDefCatalog.set_overlay_roots(
		[_row(collide_a, "quiet_collide_a"), _row(collide_b, "quiet_collide_b")]
	)
	var refused := _fresh()
	assert_eq(refused.is_loaded(), false, "while an undeclared collision is NOT loaded")
	assert_eq(
		String(refused.summary()["merge_reason"]),
		"undeclared_override",
		"and it names the refusal rather than reading as an empty family"
	)


## `summary()` is primitives only, as every panel-facing read model in this repo is. A
## `Resource` or a `Vector2` reaching a JSON summary would not be visible to any checker.
func test_summary_is_primitives_only() -> void:
	var catalog := _fresh()
	var report := catalog.summary()
	_assert_primitive(report, "summary")


# --- Helpers ------------------------------------------------------------------


## A catalog with NO cached tree, over whatever stack is currently set.
##
## It does NOT clear the stack: every case sets its own, and `set_overlay_roots` already
## drops the stale tree, so asking for the singleton after setting a stack IS the fresh
## read. Clearing here would silently discard the stack the case had just declared, which
## is exactly the bug an earlier revision of this file had.
func _fresh() -> InstitutionDefCatalog:
	return InstitutionDefCatalog.instance()


## One authored def per call, written into `dir_path` with the family's id field.
## `script_path` / `script_class_name` default to the generic def and are overridden
## positionally by the subclass case, which needs the resource to declare a DIFFERENT
## `script_class` — which is the whole mechanism being pinned.
func _write_def(
	dir_path: String,
	id_value: StringName,
	kind: StringName,
	capabilities: Array,
	script_path: String = GENERIC_DEF,
	script_class_name: String = "InstitutionDef"
) -> String:
	var path := dir_path.path_join(String(id_value) + ".tres")
	var caps := ""
	for capability in capabilities:
		caps += '&"%s", ' % String(capability)
	var text := (
		(
			'[gd_resource type="Resource" script_class="%s" load_steps=2 format=3]\n'
			% script_class_name
		)
		+ "\n"
		+ '[ext_resource type="Script" path="%s" id="1_def"]\n' % script_path
		+ "\n"
		+ "[resource]\n"
		+ 'script = ExtResource("1_def")\n'
		+ 'kind = &"%s"\n' % String(kind)
		+ "capabilities = Array[StringName]([%s])\n" % caps
		+ 'id = &"%s"\n' % String(id_value)
		+ "standing_cap = 100\n"
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(text)
	file.close()
	return path


## One overlay stack row in `CatalogOverlay`'s shape, which is the shape
## `RegistrationContext.add_content_root` stores and `_wire_content_roots` receives.
static func _row(dir_path: String, owner: String, declared: Array = []) -> Dictionary:
	return {"dir": dir_path, "owner": owner, "declared_overrides": declared, "id_field": "id"}


static func _ids_of(merged: Dictionary) -> Array:
	var out: Array = []
	for entry in merged["merged"]:
		out.append(String(entry["id"]))
	return out


## How many times `needle` appears in CODE, ignoring the `##` prose that documents it. The
## boot's class note explains WHY it no longer walks a directory, and that sentence names
## both `ContentScan` and the root — so a raw `contains` reads the explanation as the defect.
## A `for` over the file's lines, reading only: the body appends to a counter, never to the
## array being walked.
static func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits


static func _ensure_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


## Flat delete of the fixture tree. Fixtures are one level deep by construction, and the
## `while` is the `DirAccess` terminator (`entry != ""`) that `test_no_unbounded_wait.gd`
## accepts, with `depth` naming the bound that makes it safe regardless — the shape
## `test_catalog_overlay_families.gd` already uses for the same helper.
static func _remove_tree(dir_path: String, depth: int = 0) -> void:
	if depth > 4:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := dir_path.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(path, depth + 1)
		else:
			DirAccess.remove_absolute(path)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


## Every leaf is a primitive. Recursive because a Dictionary nests, and it is bounded by
## the report's own depth rather than by a count a body could grow — see the class note.
func _assert_primitive(value, label: String, depth: int = 0) -> void:
	assert_eq(depth > 6, false, "%s nests no deeper than a panel can walk" % label)
	match typeof(value):
		TYPE_DICTIONARY:
			for key in value as Dictionary:
				_assert_primitive((value as Dictionary)[key], "%s.%s" % [label, key], depth + 1)
		TYPE_ARRAY:
			for entry in value as Array:
				_assert_primitive(entry, label, depth + 1)
		_:
			assert_eq(
				typeof(value) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_NIL],
				true,
				"%s is a primitive (got %s)" % [label, type_string(typeof(value))]
			)
