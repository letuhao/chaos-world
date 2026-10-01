class_name QiPath
extends RefCounted

## The Qi Cultivation path. Advances on the shared realm ladder with its own
## 30-stage display vocabulary (ADR 0011). Stats live in QiProvider and scale
## with ladder rank.

const PATH_ID := &"qi_cultivation"


static func path_def() -> CultivationPathDef:
	var def := CultivationPathDef.new()
	def.id = PATH_ID
	def.display_name = "Qi Cultivation"
	def.stage_names = _stage_names()
	def.resource_ids = [QiStats.QI, QiStats.QI_PURITY]
	return def


static func _stage_names() -> Array[String]:
	return [
		"Qi Refining",
		"Foundation Establishment",
		"Core Formation",
		"Nascent Soul",
		"Spirit Transformation",
		"Void Refinement",
		"Body Integration",
		"Great Ascension",
		"Tribulation Crossing",
		"Spirit Condensation",
		"Spirit Sea",
		"Spirit Palace",
		"Spirit Manifestation",
		"Spirit Severing",
		"Spirit Unity",
		"Spirit Domain",
		"Spirit Sovereign",
		"Spirit Ascension",
		"Earth Immortal",
		"Heaven Immortal",
		"Golden Immortal",
		"Mystic Immortal",
		"True Immortal",
		"Primordial Immortal",
		"Great Luo Immortal",
		"Dao Fruit",
		"Immortal Sovereign",
		"Transcendent",
		"Dao Ancestor",
		"Primordial Origin",
	]
