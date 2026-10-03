class_name DestinyFixtureCatalog
extends RefCounted

## A test-local stand-in for `FateCatalog`, holding `FateDef` / `DestinyDef` built
## in code. The module reads content through the catalog singleton, and the
## shipped content tree is authored independently of this suite, so the logic
## tests install their own catalog for the duration of a test instead of
## depending on which `.tres` files happen to exist.
##
## The fixtures use a reserved `t_` id prefix so they can never collide with a
## real authored fate or destiny, and `teardown()` restores whatever catalog the
## process held beforehand — including the case where it held none.
##
## Nothing here is a production path: `FateCatalog.shared` is swapped only for the
## span of one test, and a test that forgets to restore cannot affect its
## siblings because they install their own.


## A fate that grants a flat stat bonus under a real `Stat` id.
static func flat_fate(fate_id: StringName, stat_id: StringName, value: float) -> FateDef:
	var def := FateDef.new()
	def.id = fate_id
	def.display_name = String(fate_id)
	def.description = "A fixture fate."
	def.category = &"fixture"
	def.tier = 1
	def.visibility = FateDef.REVEALED
	def.flat_modifiers = {stat_id: value}
	def.percent_modifiers = {stat_id: value / 10.0}
	def.tags = [&"fixture"]
	return def


## A fate with no modifiers at all: pure narrative, a gate target only.
static func story_fate(fate_id: StringName) -> FateDef:
	var def := FateDef.new()
	def.id = fate_id
	def.display_name = String(fate_id)
	def.description = "A fixture fate that grants nothing."
	def.category = &"fixture"
	def.tier = 1
	def.visibility = FateDef.HIDDEN
	def.teaser = "Something happened once."
	def.tags = [&"fixture"]
	return def


## A destiny with no prerequisites and no exclusivity.
static func plain_destiny(destiny_id: StringName) -> DestinyDef:
	var def := DestinyDef.new()
	def.id = destiny_id
	def.display_name = String(destiny_id)
	def.description = "A fixture destiny."
	def.bearing = "You are bound to %s." % destiny_id
	def.tier = 1
	def.visibility = FateDef.REVEALED
	return def


## A destiny with no prerequisites, `no_group`, and `grants_fates` in the order
## given — authored order is what the earn path is required to preserve.
static func granting_destiny(
	destiny_id: StringName, no_group: bool = false, granted: Array[StringName] = []
) -> DestinyDef:
	var def := DestinyDef.new()
	def.id = destiny_id
	def.display_name = String(destiny_id)
	def.description = "A fixture destiny that carries its consequence with it."
	def.bearing = "You are bound to %s." % destiny_id
	def.tier = 1
	def.visibility = FateDef.REVEALED
	if not no_group:
		def.group = &"fixture_branch"
	def.grants_fates = granted
	return def


## A destiny gated on other destinies and on fates.
static func gated_destiny(
	destiny_id: StringName,
	required_fates: Array[StringName] = [],
	required_destinies: Array[StringName] = []
) -> DestinyDef:
	var def := DestinyDef.new()
	def.id = destiny_id
	def.display_name = String(destiny_id)
	def.description = "A fixture destiny with prerequisites."
	def.bearing = "You are bound to %s." % destiny_id
	def.tier = 2
	def.visibility = FateDef.REVEALED
	def.group = &""
	def.requires_fates = required_fates
	def.requires_destinies = required_destinies
	return def


## A destiny that carries a pure-narrative gate target, so alias handling has
## something real to resolve.
static func aliased_destiny(destiny_id: StringName, aliases: Array[StringName]) -> DestinyDef:
	var def := DestinyDef.new()
	def.id = destiny_id
	def.display_name = String(destiny_id)
	def.description = "A fixture destiny story gates may be authored against."
	def.bearing = "You are bound to %s." % destiny_id
	def.tier = 1
	def.visibility = FateDef.REVEALED
	def.gate_aliases = aliases
	return def


## Replace the module's catalog singleton with one built from `fates` and
## `destinies`, for the duration of one test.
static func install(fates: Array[FateDef] = [], destinies: Array[DestinyDef] = []) -> void:
	var catalog := FateCatalog.new()
	for def in fates:
		catalog._fates[String(def.id)] = def
	for def in destinies:
		catalog._destinies[String(def.id)] = def
	catalog._loaded = true
	FateCatalog.shared = catalog


## Undo `install`. The real catalog is what the singleton lazily rebuilds when
## `shared` is null, so a restored test that needs real authored content simply
## has none installed.
static func teardown() -> void:
	FateCatalog.shared = null
