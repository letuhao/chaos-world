class_name Acupoint
extends RefCounted

## acupoint — acupoint structure (ADR 0015/0023). Each acupoint owns trained quality
## and recoverable blockage. Body essence is stored in the shared body_integrity
## ResourcePool (ADR 0012), not per-acupoint; fill and drain mutate that pool
## through the owning AcupointSet.

const MINOR := &"minor"
const MAJOR := &"major"
const CELESTIAL := &"celestial"

var id: StringName
var tier: StringName = MINOR
var quality: float = 0.5
var blocked: bool = false


func block() -> void:
	blocked = true


func clear_block() -> void:
	blocked = false


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"tier": String(tier),
		"quality": quality,
		"blocked": blocked,
	}


static func from_dict(data: Dictionary) -> Acupoint:
	var point := Acupoint.new()
	point.id = StringName(data.get("id", ""))
	point.tier = StringName(data.get("tier", MINOR))
	point.quality = float(data.get("quality", 0.5))
	point.blocked = bool(data.get("blocked", false))
	return point
