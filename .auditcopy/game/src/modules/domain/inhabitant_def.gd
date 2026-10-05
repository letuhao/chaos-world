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

## How many of the hero's blows this species survives, at the realm it is authored at
## (ADR 0230). **A COUNT OF BLOWS, never a scale.** `HITS_TO_KILL` is already measured in
## blows and so is `FightLoop.ANCHOR_BLOWS_TO_KILL`, so the corpus and the code speak one
## language: an author writes "this rat takes three" rather than "this rat's vitality is
## 180".
##
## ## Why this is the fix for three pools and one axis
##
## `RealmScaling` already multiplies `MAX_HEALTH` by `RealmDef.power`, so a creature's
## health IS on the realm ladder — but only by whatever its authored `base` happened to
## say. Measured, a default-minted inhabitant pools `50.0 + physique * 10.0` at
## `physique == 0` against a hero who pools ~250, so it died in one press: survivability
## was a function of a base stat, not of the realm both sides stand on. This field is that
## function, in the unit the anchor states it in.
##
## ## `0.0` means UNSIZED, and that is a real answer
##
## Zero is not "one blow". It is "this species authors no survivability", which is what a
## `.tres` written before this field existed says — so the spawner leaves the pool exactly
## as minted rather than inventing a magnitude. A def that authors a value gets a FLAT
## offset on `Stat.MAX_HEALTH`, which COMPOSES with `RealmScaling`'s realm MULT rather
## than replacing it; both sides then scale together up the ladder and the blows-to-survive
## figure stays near what the author wrote at every realm.
@export var blows_to_survive: float = 0.0

## The authored boss turn, or `{}`. **Absent means this species is a mob with a big pool**,
## which is the fail-safe: a `boss` role with no spec here installs no component and
## fights arithmetically like anything else (ADR 0235).
##
## The two numbers, and only the two: `punish_window_blows`, an INTEGER count of blows,
## is the whole mechanical difference between a boss and a mob; `interval` is the boss's
## own blow interval in seconds, left at `0.0` to mean "take the hero's own", so a boss
## telegraphs on the SAME rate gate ADR 0197's anchor is built on rather than on a second
## constant that could be retuned apart from it.
@export var boss_spec: Dictionary = {}


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## Whether this def authors a boss turn, and therefore whether the spawner installs a
## `BossEncounter` on it. A read rather than a `has` on `boss_spec` at every call site,
## because "authors a window" and "authors any spec at all" are different questions and a
## boss with a zero window is a real answer.
func has_boss_spec() -> bool:
	return int(boss_spec.get("punish_window_blows", -1)) >= 0


## The punish window this def authors, in BLOWS, or `0` when it authors none. `0` is
## returned for "no spec" too, because a boss the player can only survive is the `0`
## answer and both mean "the window is zero blows" to the reader that binds it.
func punish_window_blows() -> int:
	return maxi(0, int(boss_spec.get("punish_window_blows", 0)))


## Primitives only, keyed by string, so an authored species round-trips through JSON with no
## bespoke save field. Mirrors `RoomDef.to_dict`.
func to_dict() -> Dictionary:
	var base_out: Dictionary = {}
	for key in base.keys():
		base_out[String(key)] = float(base[key])
	var tags_out: Array = []
	for tag in tags:
		tags_out.append(String(tag))
	var spec_out: Dictionary = {}
	for key in boss_spec.keys():
		spec_out[String(key)] = boss_spec[key]
	return {
		"inhabitant_id": String(inhabitant_id),
		"display_name": display_name,
		"realm_id": String(realm_id),
		"base": base_out,
		"cultivates": cultivates,
		"hostile": hostile,
		"tags": tags_out,
		"blows_to_survive": blows_to_survive,
		"boss_spec": spec_out,
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
	def.blows_to_survive = float(data.get("blows_to_survive", 0.0))
	var spec_data: Dictionary = data.get("boss_spec", {})
	for key in spec_data.keys():
		var value: Variant = spec_data[key]
		# `punish_window_blows` is an INTEGER count of blows (ADR 0235) and `interval` is
		# a float, and a JSON round-trip hands both back as floats — so the two are
		# restored to their own types here rather than letting a `3.0` reach a parameter
		# typed `int`. A key this build does not know is DROPPED, not carried: a save
		# written by a newer build must degrade rather than install a window it cannot
		# mean.
		match String(key):
			"punish_window_blows":
				def.boss_spec["punish_window_blows"] = int(value)
			"interval":
				def.boss_spec["interval"] = float(value)
			_:
				def.boss_spec[String(key)] = value
	return def
