class_name MeridianDefaults
extends RefCounted

## The 20 meridians: 12 primary + 8 extraordinary (ADR 0017). Append-only;
## adding a meridian is data.

const PRIMARY := &"primary"
const EXTRAORDINARY := &"extraordinary"

static var _defs: Array[MeridianDef] = []


static func all() -> Array[MeridianDef]:
	if _defs.is_empty():
		_defs = _build()
	return _defs


static func _build() -> Array[MeridianDef]:
	var defs: Array[MeridianDef] = []
	# 12 Primary meridians (realms 1-9)
	defs.append(_make(&"lung", "Lung", PRIMARY, 0, 0.05, 0.10, 0.05))
	defs.append(_make(&"large_intestine", "Large Intestine", PRIMARY, 0, 0.05, 0.10, 0.05))
	defs.append(_make(&"stomach", "Stomach", PRIMARY, 0, 0.05, 0.10, 0.05))
	defs.append(_make(&"spleen", "Spleen", PRIMARY, 0, 0.05, 0.10, 0.05))
	defs.append(_make(&"heart", "Heart", PRIMARY, 3, 0.05, 0.10, 0.05))
	defs.append(_make(&"small_intestine", "Small Intestine", PRIMARY, 3, 0.05, 0.10, 0.05))
	defs.append(_make(&"bladder", "Bladder", PRIMARY, 3, 0.05, 0.10, 0.05))
	defs.append(_make(&"kidney", "Kidney", PRIMARY, 3, 0.05, 0.10, 0.05))
	defs.append(_make(&"pericardium", "Pericardium", PRIMARY, 6, 0.05, 0.10, 0.05))
	defs.append(_make(&"triple_burner", "Triple Burner", PRIMARY, 6, 0.05, 0.10, 0.05))
	defs.append(_make(&"gallbladder", "Gallbladder", PRIMARY, 6, 0.05, 0.10, 0.05))
	defs.append(_make(&"liver", "Liver", PRIMARY, 6, 0.05, 0.10, 0.05))
	# 8 Extraordinary meridians (realms 10-18)
	defs.append(_make(&"du_mai", "Du Mai", EXTRAORDINARY, 9, 0.05, 0.10, 0.05))
	defs.append(_make(&"ren_mai", "Ren Mai", EXTRAORDINARY, 9, 0.05, 0.10, 0.05))
	defs.append(_make(&"chong_mai", "Chong Mai", EXTRAORDINARY, 9, 0.05, 0.10, 0.05))
	defs.append(_make(&"dai_mai", "Dai Mai", EXTRAORDINARY, 9, 0.05, 0.10, 0.05))
	defs.append(_make(&"yin_qiao", "Yin Qiao", EXTRAORDINARY, 12, 0.05, 0.10, 0.05))
	defs.append(_make(&"yang_qiao", "Yang Qiao", EXTRAORDINARY, 12, 0.05, 0.10, 0.05))
	defs.append(_make(&"yin_wei", "Yin Wei", EXTRAORDINARY, 15, 0.05, 0.10, 0.05))
	defs.append(_make(&"yang_wei", "Yang Wei", EXTRAORDINARY, 15, 0.05, 0.10, 0.05))
	return defs


static func _make(
	id: StringName,
	display_name: String,
	type: StringName,
	tier: int,
	capacity_bonus: float,
	flow_bonus: float,
	power_bonus: float
) -> MeridianDef:
	var def := MeridianDef.new()
	def.id = id
	def.display_name = display_name
	def.type = type
	def.tier = tier
	def.capacity_bonus = capacity_bonus
	def.flow_bonus = flow_bonus
	def.power_bonus = power_bonus
	return def
