class_name BodyPath
extends RefCounted

## The body cultivation path. Advances on the shared realm ladder with its own
## 30-stage display vocabulary (ADR 0005/0006/0012).

const PATH_ID := &"body_cultivation"


static func path_def() -> CultivationPathDef:
	var def := CultivationPathDef.new()
	def.id = PATH_ID
	def.display_name = "Body Cultivation"
	def.stage_names = _stage_names()
	def.resource_ids = [BodyStats.BODY_INTEGRITY]
	return def


static func _stage_names() -> Array[String]:
	return [
		"Skin Tempering",
		"Muscle Forging",
		"Bone Refining",
		"Marrow Cleansing",
		"Tendon Strengthening",
		"Organ Tempering",
		"Blood Refining",
		"Iron Body",
		"Copper Body",
		"Silver Body",
		"Gold Body",
		"Jade Body",
		"Diamond Body",
		"Adamant Body",
		"Body of Laws",
		"Body of Dao",
		"Body of Void",
		"Body of Chaos",
		"Body of Creation",
		"Body of Destruction",
		"Body of Eternity",
		"Body of Immortality",
		"Body of Transcendence",
		"Body of Unity",
		"Body of Origin",
		"Body of Heaven",
		"Body of Earth",
		"Body of Humanity",
		"Body of Divinity",
		"Body of the Dao",
	]
