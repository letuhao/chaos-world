class_name BloodlineFixtureCatalog
extends RefCounted

## A test-local stand-in for `BloodlineCatalog`, holding `BloodlineDef` built in code.
## The module reads content through the catalog singleton, and the shipped content tree
## is authored independently of this suite, so the logic tests install their own
## catalog for the duration of a test instead of depending on which `.tres` files happen
## to exist.
##
## The fixtures use a reserved `t_` id prefix so they can never collide with a real
## authored lineage, and `teardown()` restores whatever catalog the process held
## beforehand. One test (`test_bloodline_content.gd`) deliberately reads the SHIPPED
## tree, which is the only way to hold authored content to ADR 0063's reachability rule.
##
## `install()` reaches into the catalog's private `_bloodlines` / `_loaded` members,
## exactly as `RaceFixtureCatalog` does — the catalog has no public way to register
## content, and adding one would widen the module's surface for a test's benefit only.


## A lineage on the common bar, with the grants the attach tests project.
static func common(lineage_id: StringName) -> BloodlineDef:
	var def := _base(lineage_id)
	def.awaken_threshold = BloodlineApi.TIER_COMMON
	def.percent_modifiers = {"max_health": 0.1}
	return def


## A lineage on the rare bar.
static func rare(lineage_id: StringName) -> BloodlineDef:
	var def := _base(lineage_id)
	def.awaken_threshold = BloodlineApi.TIER_RARE
	def.percent_modifiers = {"qi_regen": 0.05}
	return def


## A lineage on the founding bar — one generation of pure inheritance and no more.
static func founding(lineage_id: StringName) -> BloodlineDef:
	var def := _base(lineage_id)
	def.awaken_threshold = BloodlineApi.TIER_FOUNDING
	def.percent_modifiers = {"qi_absorption": 0.15}
	return def


## A lineage with no stat grant at all, so the projection has to mirror it without
## touching the modifier stack.
static func inert(lineage_id: StringName) -> BloodlineDef:
	var def := _base(lineage_id)
	def.percent_modifiers = {}
	def.traits = [&"t_fixture_grant"]
	return def


static func _base(lineage_id: StringName) -> BloodlineDef:
	var def := BloodlineDef.new()
	def.id = lineage_id
	def.display_name = String(lineage_id)
	def.description = "A fixture lineage."
	def.awaken_threshold = 0.42
	def.percent_modifiers = {}
	def.traits = []
	def.tags = []
	def.race_id = &""
	return def


## Replace the module's catalog singleton with one built from `defs`, for the duration
## of one test.
static func install(defs: Array[BloodlineDef]) -> void:
	var catalog := BloodlineCatalog.new()
	for def in defs:
		catalog._bloodlines[String(def.id)] = def
	catalog._loaded = true
	BloodlineCatalog.shared = catalog


## Undo `install`. The real catalog is what the singleton lazily rebuilds when `shared`
## is null.
static func teardown() -> void:
	BloodlineCatalog.shared = null
