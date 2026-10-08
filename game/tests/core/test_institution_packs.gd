extends TestCase

## The organization pack: a pack IS a mod (D6), and the three proofs are here.
##
## 1. A temp pack shipping a brand-new kind is DISCOVERED through the overlay
##    seam with no base-game edit — never by editing shipped content.
## 2. A pack whose org fails its claimed contract suite is REFUSED BY NAME:
##    the `contract_failed` reason travels out of `InstitutionContract.register`
##    itself, which the pack path calls rather than reimplements (D3).
## 3. The shipped tiers still load as before (base root, base-owned): the pack
##    rows are additive, and today there are no shipped packs, so zero pack
##    rows is the honest answer rather than a missing directory.
##
## ## Every loop in this file is a `for`
##
## The walks are over a materialised file list, a fixed probe row, or a
## directory listing drained by the `DirAccess` terminator in `_remove_tree`
## (copied from `test_institution_def_catalog.gd`, depth-capped at 4). No body
## appends to the container it walks, so no bound can grow in lockstep with
## its own body and `test_no_unbounded_wait.gd` has nothing to reject.

## A module facade that exists, so `register` never refuses on the api path.
const REAL_API := "res://src/modules/mods/api.gd"
## The generic def a pack authors on — the same script a mod is expected to use.
const GENERIC_DEF := "res://src/core/institution_def.gd"

var _temp_root: String = ""


## A capability that passes its own suite: the base verbs answer cleanly and
## nothing mutates, so `contract_findings()` is empty and the kind registers.
class _SoundPackCapability:
	extends InstitutionCapability

	func capability_id() -> StringName:
		return &"sound_pack_probe"


## A capability that fails its own suite with a planted finding, so the pack
## path must refuse the kind as `contract_failed` — D3's whole mechanism.
class _BrokenPackCapability:
	extends InstitutionCapability

	func capability_id() -> StringName:
		return &"broken_pack_probe"

	func contract_findings() -> Array[String]:
		return ["probe: planted pack finding"]


func setup() -> void:
	_temp_root = OS.get_environment("TEMP").path_join("cw_institution_packs_test")
	_ensure_dir(_temp_root)
	# Cleared in BOTH setup and teardown: setup clears what a previous suite
	# left in this process, teardown clears what this suite leaves.
	InstitutionDefCatalog.clear()


func teardown() -> void:
	InstitutionDefCatalog.clear()
	if _temp_root != "":
		_remove_tree(_temp_root)
	_temp_root = ""


# --- The provides vocabulary -------------------------------------------------


## A temp pack with two sound orgs registers under `provides:
## ["organization_pack"] — the registry half of "a pack IS a mod".
func test_pack_provides_registers_with_valid_orgs() -> void:
	var org_dir := _pack_dir("sound_pack")
	_write_def(org_dir, &"sound_one", &"sound_probe_guild", [&"has_territory"])
	_write_def(org_dir, &"sound_two", &"sound_probe_guild", [&"has_territory"])
	var reg := ModuleRegistry.new()
	var out := reg.register(
		"sound_pack_module", REAL_API, PackedStringArray(), ["organization_pack"], org_dir
	)
	assert_eq(out["ok"], true, "a sound pack registers: %s" % str(out.get("detail", "")))
	assert_eq(out["reason"], "", "no refusal reason")


## A module that does NOT declare the pack is not validated as one, so it
## registers even with an empty dir — the same escape hatch the cultivation
## path ships, in the same shape.
func test_pack_without_provides_skips_validation() -> void:
	var org_dir := _pack_dir("empty_no_provides")
	_ensure_dir(org_dir)
	var reg := ModuleRegistry.new()
	var out := reg.register("plain_module", REAL_API, PackedStringArray(), [], org_dir)
	assert_eq(out["ok"], true, "a module without provides registers without validation")


## A pack that declares the vocabulary but ships no orgs is refused with a
## named cause — never a silent skip.
func test_pack_with_no_orgs_is_refused() -> void:
	var org_dir := _pack_dir("hollow_pack")
	_ensure_dir(org_dir)
	var reg := ModuleRegistry.new()
	var out := reg.register(
		"hollow_pack_module", REAL_API, PackedStringArray(), ["organization_pack"], org_dir
	)
	assert_eq(out["ok"], false, "a pack with no orgs is refused")
	assert_eq(out["reason"], "invalid_organization_pack", "with the named cause")
	assert_eq(String(out["detail"]).contains("no organizations found"), true, "naming the gap")


## A `.tres` no `InstitutionDef` load reaches is refused, naming the file —
## the pack dir holds orgs, and a stranger in it is a content bug, not content.
func test_pack_with_a_foreign_def_is_refused() -> void:
	var org_dir := _pack_dir("foreign_pack")
	_ensure_dir(org_dir)
	_write_foreign(org_dir, "foreign_thing")
	var reg := ModuleRegistry.new()
	var out := reg.register(
		"foreign_pack_module", REAL_API, PackedStringArray(), ["organization_pack"], org_dir
	)
	assert_eq(out["ok"], false, "a pack with a foreign def is refused")
	assert_eq(out["reason"], "invalid_organization_pack", "with the named cause")
	assert_eq(String(out["detail"]).contains("failed to load"), true, "naming the fault")


## An org whose authored content fails is refused BY the content reason: an
## invented capability name fails where it was written.
func test_pack_with_broken_content_is_refused_by_name() -> void:
	var org_dir := _pack_dir("broken_content_pack")
	_write_def(org_dir, &"broken_org", &"broken_probe_guild", [&"not_a_capability"])
	var reg := ModuleRegistry.new()
	var out := reg.register(
		"broken_content_module", REAL_API, PackedStringArray(), ["organization_pack"], org_dir
	)
	assert_eq(out["ok"], false, "a pack with broken content is refused")
	assert_eq(out["reason"], "invalid_organization_pack", "with the named cause")
	assert_eq(
		String(out["detail"]).contains("unknown_capability"),
		true,
		"carrying the content refusal by name"
	)


# --- D3: the contract suite runs at registration ------------------------------


## A pack whose kind brings a broken implementation is refused, and the inner
## reason is `InstitutionContract`'s own `contract_failed` — wired to, never
## reimplemented.
func test_pack_failing_its_contract_is_refused_by_name() -> void:
	var org_dir := _pack_dir("broken_contract_pack")
	_write_def(org_dir, &"doomed_org", &"doomed_probe_guild", [&"has_territory"])
	var reg := ModuleRegistry.new()
	var out := reg.register(
		"broken_contract_module",
		REAL_API,
		PackedStringArray(),
		["organization_pack"],
		org_dir,
		{"doomed_probe_guild": [_BrokenPackCapability.new()]}
	)
	assert_eq(out["ok"], false, "a pack failing its contract is refused")
	assert_eq(out["reason"], "invalid_organization_pack", "with the named cause")
	assert_eq(
		String(out["detail"]).contains(InstitutionContract.R_CONTRACT_FAILED),
		true,
		"refused BY NAME: the dispatcher's own contract_failed travels out"
	)


## The discriminating counterpart: a sound implementation passes the same
## gate, so the refusal above proves the suite runs rather than rejects all.
func test_pack_with_a_sound_capability_registers() -> void:
	var org_dir := _pack_dir("sound_contract_pack")
	_write_def(org_dir, &"sound_org", &"sound_caps_guild", [&"has_territory"])
	var reg := ModuleRegistry.new()
	var out := reg.register(
		"sound_contract_module",
		REAL_API,
		PackedStringArray(),
		["organization_pack"],
		org_dir,
		{"sound_caps_guild": [_SoundPackCapability.new()]}
	)
	assert_eq(out["ok"], true, "a pack passing its contract registers: %s" % str(out))
	# The dispatcher the validation graded through was a throwaway: nothing
	# leaked into the shared one behind this suite's back.
	assert_eq(
		InstitutionContract.instance().knows(&"sound_caps_guild"),
		false,
		"validation leaves no registration behind"
	)


# --- Discovery without a base-game edit --------------------------------------


## A temp pack shipping a brand-new kind is visible through the overlay seam —
## the mod contract — with the base tiers still present beside it.
func test_temp_pack_is_discovered_through_the_overlay_seam() -> void:
	var org_dir := _pack_dir("discovery_pack")
	var def_path := _write_def(org_dir, &"wayfarer_circle", &"wayfarer_guild", [&"has_territory"])
	var base_only := InstitutionDefCatalog.instance()
	assert_eq(base_only.has(&"wayfarer_circle"), false, "before the seam, the pack org is absent")

	InstitutionDefCatalog.set_overlay_roots([_row(org_dir, "discovery_pack")])
	var overlaid := InstitutionDefCatalog.instance()
	assert_eq(overlaid.has(&"wayfarer_circle"), true, "after the seam, it is visible")
	assert_eq(overlaid.owner_of(&"wayfarer_circle"), "discovery_pack", "and owned by the pack")
	assert_eq(overlaid.path_of(&"wayfarer_circle"), def_path, "at the path the pack shipped it")
	var def := overlaid.definition(&"wayfarer_circle")
	assert_ne(def, null, "and the def loads")
	assert_eq(def.kind, &"wayfarer_guild", "declaring a kind nothing has seen")
	assert_eq(bool(def.check_content()["ok"]), true, "whose authored content is sound")
	assert_eq(overlaid.has(&"lantern_exchange"), true, "the base tiers are still present")


## The shipped pack rows are base-owned and empty today; the three tiers load
## from the base root as before. This pins the seam the tier moves will land
## on: when packs ship, their rows layer here, base-owned, in sorted order.
func test_shipped_pack_rows_are_empty_and_the_tiers_still_load() -> void:
	var catalog := InstitutionDefCatalog.instance()
	var merged := catalog.overlay_merge()
	assert_eq(bool(merged["ok"]), true, "the base merge succeeded")
	var pack_seen := false
	for entry in merged["merged"]:
		if String(entry["path"]).contains("data/packs"):
			pack_seen = true
	assert_eq(pack_seen, false, "no shipped packs yet, so no pack row contributes")
	assert_eq(catalog.has(&"lantern_exchange"), true, "the trading guild loads")
	assert_eq(catalog.has(&"grey_horizon_hunt"), true, "the hunting guild loads")
	assert_eq(catalog.has(&"torrent_field_circle"), true, "the farmers' circle loads")
	assert_eq(String(catalog.owner_of(&"lantern_exchange")), "base", "base-owned")
	assert_eq(catalog.is_loaded(), true, "and the family presents itself as loaded")


# --- Helpers ------------------------------------------------------------------


## One temp pack organizations dir, created fresh per case so no two cases
## share content through the resource cache or the singleton.
func _pack_dir(pack_id: String) -> String:
	var dir_path := _temp_root.path_join(pack_id).path_join("organizations")
	_ensure_dir(dir_path)
	return dir_path


## One authored org def per call, in the shape a pack ships: the generic
## `InstitutionDef`, a kind, capabilities from the registry vocabulary, an id.
func _write_def(
	dir_path: String, id_value: StringName, kind: StringName, capabilities: Array
) -> String:
	var path := dir_path.path_join(String(id_value) + ".tres")
	var caps := ""
	for capability in capabilities:
		caps += '&"%s", ' % String(capability)
	var text := (
		'[gd_resource type="Resource" script_class="InstitutionDef" load_steps=2 format=3]\n'
		+ "\n"
		+ '[ext_resource type="Script" path="%s" id="1_def"]\n' % GENERIC_DEF
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


## One `.tres` that is deliberately NOT an organization: no def script, so the
## pack validator cannot read it as one and must refuse the pack naming it.
func _write_foreign(dir_path: String, id_value: String) -> String:
	var path := dir_path.path_join(id_value + ".tres")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string('[gd_resource type="Resource" format=3]\n\n[resource]\n')
	file.close()
	return path


## One overlay stack row in `CatalogOverlay`'s shape, which is the shape
## `RegistrationContext.add_content_root` stores.
static func _row(dir_path: String, owner: String, declared: Array = []) -> Dictionary:
	return {"dir": dir_path, "owner": owner, "declared_overrides": declared, "id_field": "id"}


static func _ensure_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


## Flat delete of the fixture tree. Fixtures are two levels deep by
## construction, and the `while` is the `DirAccess` terminator
## (`entry != ""`) with `depth` naming the bound that makes it safe
## regardless — the shape `test_institution_def_catalog.gd` uses.
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
