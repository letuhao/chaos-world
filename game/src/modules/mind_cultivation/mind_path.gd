class_name MindPath
extends RefCounted

## The mind cultivation system. It advances on the shared realm ladder and has
## its own 30-stage display vocabulary (ADR 0005/0006/0013). Its stats live in
## MindProvider and scale with ladder rank.

const PATH_ID := &"mind_cultivation"


static func path_def() -> CultivationPathDef:
	var def := CultivationPathDef.new()
	def.id = PATH_ID
	def.display_name = "Mind Cultivation"
	def.stage_names = _stage_names()
	return def


static func _stage_names() -> Array[String]:
	return [
		"Mind Awakening",
		"Focus",
		"Clarity",
		"Insight",
		"Enlightenment",
		"Perception",
		"Awareness",
		"Concentration",
		"Meditation",
		"Contemplation",
		"Introspection",
		"Discernment",
		"Comprehension",
		"Understanding",
		"Wisdom",
		"Knowledge",
		"Thought",
		"Reasoning",
		"Logic",
		"Intuition",
		"Inspiration",
		"Revelation",
		"Awakening",
		"Ascension",
		"Transcendence",
		"Dao of Mind",
		"Ascendant of Mind",
		"Transcendent Mind",
		"Mind Dao Ancestor",
		"Primordial Mind Origin",
	]
