class_name ElementDefaults
extends RefCounted

## The default element set (ADR 0004): tier 1 五行 + tier 2 advanced. New elements
## can be appended here or authored as ElementDef `.tres` resources.


static func base() -> Array[ElementDef]:
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
