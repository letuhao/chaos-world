class_name InhabitantDef
extends Resource

## An authored creature SPECIES that stands inside a domain (ADR 0074).
##
## **A species is not a class.** `NpcDef` (ADR 0077) is an authored INDIVIDUAL — Bearcutter
## Lao, who owes a debt; this is the bear. Neither is a script: both resolve into an `Actor`,
## and what separates a mob from a mini-boss from a boss is a realm, a number, and a tag on
## `Actor.tags`. There is deliberately no `MiniBossDef` subclass to inherit from.
##
## **The realm is the field that makes a rival a rival.** A `rival_cultivator` built from this
## def gets a real `PathState` at `realm_id` with the player's own providers, so it is a rival
## *cultivator* rather than a mob with a name.
##
## **Magnitude is authored, never branched on.** A mini-boss is this def with a bigger `base`
## and a higher `realm_id`. If a mechanism ever wants `if role == "boss"` to change a number, the
## number belongs in this def instead.

## Stable identity across saves and across every map that places this species. A map's spawn
## ref names this, never a display name.
@export var inhabitant_id: StringName = &""

@export var display_name: String = ""

## The realm this species starts at, before any breakthrough. Empty means the species carries no
## realm at all, which is only legal for a def whose role does not cultivate.
@export var realm_id: StringName = &""

## Base attributes before realm scaling. This is where a mini-boss is bigger than a mob.
@export var base: Dictionary = {}

## Whether this species is a CULTIVATOR, and therefore enrolled on a cultivation path at
## `realm_id` with the same providers the player gets. `DomainRoles.cultivates(role)` reports
## only what the role PERMITS; this field decides. An npc is not automatically a cultivator.
@export var cultivates: bool = false

## Whether this species is hostile on sight. `DomainRoles.is_hostile(role)` is the necessary
## condition; this field is the authored opt-in, so a role that cannot be hostile never is.
@export var hostile: bool = false

## Authored tags, copied onto the spawned `Actor`. The role itself is stamped separately by
## `DomainSpawner` and is not authored here.
@export var tags: Array[StringName] = []


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## Primitives only, keyed by string, so an authored species round-trips through JSON with no
## bespoke save field. Mirrors `RoomDef.to_dict`.
func to_dict() -> Dictionary:
	var base_out: Dictionary = {}
	for key in base.keys():
		base_out[String(key)] = float(base[key])
	var tags_out: Array = []
	for tag in tags:
		tags_out.append(String(tag))
	return {
		"inhabitant_id": String(inhabitant_id),
		"display_name": display_name,
		"realm_id": String(realm_id),
		"base": base_out,
		"cultivates": cultivates,
		"hostile": hostile,
		"tags": tags_out,
	}


static func from_dict(data: Dictionary) -> InhabitantDef:
	var def := InhabitantDef.new()
	def.inhabitant_id = StringName(data.get("inhabitant_id", ""))
	def.display_name = String(data.get("display_name", ""))
	def.realm_id = StringName(data.get("realm_id", ""))
	var base_data: Dictionary = data.get("base", {})
	for key in base_data.keys():
		# `Stat` ids are `StringName`; JSON hands them back as `String`, and the stat
		# context is keyed by `StringName` throughout.
		def.base[StringName(key)] = float(base_data[key])
	def.cultivates = bool(data.get("cultivates", false))
	def.hostile = bool(data.get("hostile", false))
	for tag in data.get("tags", []):
		def.tags.append(StringName(tag))
	return def
