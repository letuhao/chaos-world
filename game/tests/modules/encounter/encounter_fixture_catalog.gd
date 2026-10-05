class_name EncounterFixtureCatalog
extends RefCounted

## A test-local stand-in for `EncounterCatalog`, holding `EncounterDef` /
## `ProphecyDef` built in code. The module reads content through the catalog
## singleton, and the shipped content tree is authored independently of this
## suite, so the logic tests install their own catalog for the duration of a
## test instead of depending on which `.tres` files happen to exist.
##
## `install()` REPLACES the `EncounterCatalog.shared` singleton wholesale:
## the fixture catalog is the only catalog the module can see for the span of
## the test. `teardown()` restores whatever catalog the process held beforehand.


## A simple encounter with no trigger condition and no prophecy.
static func simple_encounter(encounter_id: StringName) -> EncounterDef:
	var def := EncounterDef.new()
	def.id = encounter_id
	def.display_name = String(encounter_id)
	def.description = "A fixture encounter."
	def.trigger_type = EncounterDef.TRIGGER_ALWAYS
	def.weight = 1.0
	def.cooldown = 0
	def.fate_choices = [&"t_fate_a", &"t_fate_b"]
	def.prophecy_id = &""
	def.unique = true
	return def


## An encounter with a prophecy drop.
static func prophecy_encounter(encounter_id: StringName, prophecy_id: StringName) -> EncounterDef:
	var def := EncounterDef.new()
	def.id = encounter_id
	def.display_name = String(encounter_id)
	def.description = "A fixture encounter with a prophecy."
	def.trigger_type = EncounterDef.TRIGGER_ALWAYS
	def.weight = 1.0
	def.cooldown = 0
	def.fate_choices = [&"t_fate_a", &"t_fate_b"]
	def.prophecy_id = prophecy_id
	def.unique = true
	return def


## An encounter with a location trigger.
static func location_encounter(encounter_id: StringName, location_id: StringName) -> EncounterDef:
	var def := EncounterDef.new()
	def.id = encounter_id
	def.display_name = String(encounter_id)
	def.description = "A fixture encounter triggered by location."
	def.trigger_type = EncounterDef.TRIGGER_LOCATION
	def.trigger_value = location_id
	def.weight = 1.0
	def.cooldown = 0
	def.fate_choices = [&"t_fate_a"]
	def.prophecy_id = &""
	def.unique = true
	return def


## An encounter with a cooldown.
static func cooldown_encounter(encounter_id: StringName, cooldown_turns: int) -> EncounterDef:
	var def := EncounterDef.new()
	def.id = encounter_id
	def.display_name = String(encounter_id)
	def.description = "A fixture encounter with a cooldown."
	def.trigger_type = EncounterDef.TRIGGER_ALWAYS
	def.weight = 1.0
	def.cooldown = cooldown_turns
	def.fate_choices = [&"t_fate_a"]
	def.prophecy_id = &""
	def.unique = false
	return def


## A simple prophecy.
static func simple_prophecy(prophecy_id: StringName, hint_fate_id: StringName) -> ProphecyDef:
	var def := ProphecyDef.new()
	def.id = prophecy_id
	def.display_name = String(prophecy_id)
	def.description = "A fixture prophecy."
	def.hint_fate_id = hint_fate_id
	def.hint_text = "Something will happen."
	return def


## Replace the module's catalog singleton with one built from `encounters` and
## `prophecies`, for the duration of one test.
static func install(
	encounters: Array[EncounterDef] = [], prophecies: Array[ProphecyDef] = []
) -> void:
	var catalog := EncounterCatalog.new()
	for def in encounters:
		catalog._encounters[String(def.id)] = def
	for def in prophecies:
		catalog._prophecies[String(def.id)] = def
	catalog._loaded = true
	EncounterCatalog.shared = catalog


## Undo `install`. The real catalog is what the singleton lazily rebuilds when
## `shared` is null, so a restored test that needs real authored content simply
## has none installed.
static func teardown() -> void:
	EncounterCatalog.shared = null
