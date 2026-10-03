class_name ElementDefaults
extends RefCounted

## The default element set (ADR 0004): tier 1 五行 + tier 2 advanced. New elements
## can be appended here or authored as ElementDef `.tres` resources.


static func base() -> Array[ElementDef]:
	# The 相克 cycle is 金克木 · 木克土 · 土克水 · 水克火 · 火克金, and each entry's
	# `overcomes` list names the element it BEATS: metal>wood, wood>earth, earth>water,
	# water>fire, fire>metal. Measured over the 25 tier-1 pairs this row means exactly
	# 0.950 with a 0.5..1.5 spread, which is the balanced value ADR 0069 pins.
	#
	# ⚠️ DEF-0140 was filed against this table on the claim that it is TRANSPOSED (that
	# `fire > wood` should be STRONG). It is not: `fire > metal` reading 1.5 and
	# `fire > wood` reading 1.0 is the correct cycle, and 0.950 is the mean the shipped
	# balance wants. The defect is in the TEST that asserted `fire > wood`, not here —
	# so this table is left as authored.
	return [
		_make(ElementStats.METAL, "Metal", 1, [ElementStats.WATER], [ElementStats.WOOD]),
		_make(ElementStats.WOOD, "Wood", 1, [ElementStats.FIRE], [ElementStats.EARTH]),
		_make(ElementStats.WATER, "Water", 1, [ElementStats.WOOD], [ElementStats.FIRE]),
		_make(ElementStats.FIRE, "Fire", 1, [ElementStats.EARTH], [ElementStats.METAL]),
		_make(ElementStats.EARTH, "Earth", 1, [ElementStats.METAL], [ElementStats.WATER]),
	]


static func advanced() -> Array[ElementDef]:
	return [
		_make(ElementStats.LIGHTNING, "Lightning", 2, [], [ElementStats.WATER, ElementStats.WIND]),
		_make(ElementStats.ICE, "Ice", 2, [], [ElementStats.WOOD, ElementStats.WATER]),
		_make(ElementStats.WIND, "Wind", 2, [], [ElementStats.EARTH, ElementStats.FIRE]),
		_make(ElementStats.LIGHT, "Light", 2, [], [ElementStats.DARK]),
		_make(ElementStats.DARK, "Dark", 2, [], [ElementStats.LIGHT]),
	]


static func all() -> Array[ElementDef]:
	var out := base()
	out.append_array(advanced())
	return out


static func _make(
	id: StringName, display_name: String, tier: int, generates: Array, overcomes: Array
) -> ElementDef:
	var entry := ElementDef.new()
	entry.id = id
	entry.display_name = display_name
	entry.tier = tier
	entry.generates = _names(generates)
	entry.overcomes = _names(overcomes)
	return entry


static func _names(values: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for value in values:
		out.append(value)
	return out
