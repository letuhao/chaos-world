class_name W8FixtureModuleApi
extends RefCounted

## Minimal fixture module facade proving module registration through the mods
## system (ADR 0184). A test double: it registers, it does not play.


static func module_id() -> String:
	return "w8_fixture_module"


static func summary() -> Dictionary:
	return {"fixture": true}
