class_name SuccubusPath
extends RefCounted

## The succubus cultivation system. It advances on the shared realm ladder and has
## its own 30-stage display vocabulary (ADR 0005/0006). Its stats live in
## DualCultivationProvider and scale with ladder rank.

const PATH_ID := &"succubus"


static func path_def() -> CultivationPathDef:
	var def := CultivationPathDef.new()
	def.id = PATH_ID
	def.display_name = "Succubus"
	def.stage_names = _stage_names()
	return def


static func _stage_names() -> Array[String]:
	return [
		"Flicker",
		"Allure",
		"Enticement",
		"Bewitchment",
		"Enchantment",
		"Seduction",
		"Rapture",
		"Obsession",
		"Enchantress",
		"Heart Thief",
		"Dreamweaver",
		"Temptress",
		"Succubus",
		"Lady of Desire",
		"Queen of Desire",
		"Empress of Desire",
		"Sovereign of Desire",
		"Overlord of Desire",
		"Domain of Desire",
		"Law of Desire",
		"Edict of Desire",
		"Authority of Desire",
		"Hegemony of Desire",
		"Origin of Desire",
		"Primordial Desire",
		"Dao of Desire",
		"Ascendant of Desire",
		"Transcendent Desire",
		"Desire Dao Ancestor",
		"Primordial Desire Origin",
	]
