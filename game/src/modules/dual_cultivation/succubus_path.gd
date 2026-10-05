class_name SuccubusPath
extends RefCounted

## The succubus cultivation system. It advances on the shared realm ladder and has
## its own 30-stage display vocabulary (ADR 0005/0006). Its stats live in
## DualCultivationProvider and scale with ladder rank.
##
## It is the path with no realm seeds of its own, which makes it the one in-tree system
## shaped like a MOD's — so it is also where `RealmMapper` is used: the correspondence
## between its stage vocabulary and the shared ladder is STATED by formula rather than
## assumed to be 30 == 30 (ADR 0266).

const PATH_ID := &"succubus"


static func path_def() -> CultivationPathDef:
	var def := CultivationPathDef.new()
	def.id = PATH_ID
	def.display_name = "Succubus"
	def.stage_names = _stage_names()
	return def


## How many stages this path authors. Read off the vocabulary rather than typed beside
## it, because the two are the same fact and a second copy of it would be free to drift.
static func stage_count() -> int:
	return _stage_names().size()


## The shared realm a succubus stage maps onto, BY FORMULA through `RealmMapper`.
##
## This is the only place the path states its correspondence to the ladder. The 30
## stage names below line up with the 30 realms because the map is the identity at
## equal lengths — not because anyone counted, and not because the two arrays are
## edited together. A stage added without a matching realm is now a red assertion in
## `test_succubus_path.gd` rather than a silent off-by-one in every stage name.
static func realm_id_for_stage(stage: int) -> StringName:
	return RealmMapper.standard_realm_id(stage, stage_count())


## The shared rate for a succubus stage. `RealmRate` on the realm the stage maps onto,
## never a curve this module authors — the provider reads `RealmRate.factor` on
## `PathState.rank_id` and lands on the same number through here.
static func stage_factor(stage: int) -> float:
	return RealmMapper.factor_for_ordinal(stage, stage_count())


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
