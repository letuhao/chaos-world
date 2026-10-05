class_name BodyPractice
extends RefCounted

## Weapon mastery and material-art mastery as ONE ledger of practice, held as an
## actor component.
##
## ## Mastery is not realm rank, and this is where that is structural rather
## ## than merely intended
##
## Two independent facts make it so:
##
## 1. **Nothing in this file reads a realm, a ladder index, `RealmRate`,
##    `RealmScaling`, or `RealmDef.power`.** Mastery is keyed by WEAPON KIND and
##    by MATERIAL ART — ids with no ordinal at all. There is no place for a realm
##    to leak in, so there is nothing to keep two curves apart.
## 2. **Mastery is paid in body work, not in a number that multiplies the
##    ladder.** [method apply_use] pays the kind's demand's base attribute and
##    the kind's own demand stat. A body at the top of the ladder that has never
##    held a maul holds a maul at zero, and a body at the bottom that has swung
##    one ten thousand times holds it as high as its own arms allow.
##
## `test_mastery_is_independent_of_realm` pins the first half by construction
## (two actors at different realms, identical ledger, identical mastery) and the
## second by measurement (the ladder cannot move mastery because nothing reads it).

## One landed, uncountered use, before the kind's own `practice_gain`. A rate of
## the PRACTICE, NOT a magnitude of the weapon and NOT of the realm.
const USE_YIELD := 1.0

## The module's own stat ids for weapon demands, keyed by demand. Held here rather
## than on the kind so a kind authors a demand and never a number.
var demand_mastery: Dictionary = {}
## Material art id -> the mastery earned practising it.
var art_mastery: Dictionary = {}
## Weapon kind id -> `{"uses": int, "landed": int, "blunted": int}`, the use record
## the use loop earns mastery from.
var record: Dictionary = {}
## Part id -> `BodyPart`, the parts this body actually HAS.
var parts: Dictionary = {}


## Mastery of one weapon kind. 0.0 for a kind this body has never held, which is
## the answer a high-realm novice gets and the whole reason this system exists.
func mastery(kind_id: StringName) -> float:
	return float(demand_mastery.get(String(kind_id), 0.0))


## Mastery of one material art, 0.0 when unpractised.
func art_level(art_id: StringName) -> float:
	return float(art_mastery.get(String(art_id), 0.0))


func uses_of(kind_id: StringName) -> int:
	return int(_row(kind_id).get("uses", 0))


func landed_of(kind_id: StringName) -> int:
	return int(_row(kind_id).get("landed", 0))


## Whether this body holds `part_id` — the question a material art is asked.
## Absent reads as false, which is what makes "grow one" meaningful: the answer
## before the art is false, not a zero.
func has_part(part_id: StringName) -> bool:
	return parts.has(String(part_id))


func part(part_id: StringName) -> BodyPart:
	return parts.get(String(part_id), null)


## Record one use of `kind_id` and commit what it earned.
##
## `blunted_yield` is the fraction a COUNTERED exchange still trains, supplied by
## the caller so this ledger owns no rate: the counterpart's size is a balance
## number and belongs beside the use loop that applies it. A strike that missed
## earns nothing at all and a countered one earns the reduced rate — which is the
## yin-yang counterpart travelling through the loop rather than sitting beside
## it: a body that trains a kind its enemy already answers is measurably worse at
## it, and the test proves the gap rather than trusting it.
##
## Returns the mastery the use earned, in absolute units.
func apply_use(
	kind_id: StringName, landed: bool, blunted: bool, gain: float, blunted_yield: float
) -> float:
	var row := _row(kind_id)
	row["uses"] = int(row.get("uses", 0)) + 1
	if not landed:
		return 0.0
	row["landed"] = int(row.get("landed", 0)) + 1
	var earned := 0.0
	if blunted:
		row["blunted"] = int(row.get("blunted", 0)) + 1
		earned = USE_YIELD * gain * maxf(0.0, blunted_yield)
	else:
		earned = USE_YIELD * gain
	demand_mastery[String(kind_id)] = mastery(kind_id) + earned
	return earned


## Put a part on this body. Returns the part so a caller can report its state,
## and replaces rather than duplicates: two parts for one limb would be two
## sources of truth for the same missing arm.
func add_part(part: BodyPart) -> BodyPart:
	if part == null:
		return null
	parts[String(part.id)] = part
	return part


func _row(kind_id: StringName) -> Dictionary:
	var key := String(kind_id)
	if not record.has(key):
		record[key] = {"uses": 0, "landed": 0, "blunted": 0}
	return record[key]


## Primitives only, because this payload rides `Actor.module_data` and is read by
## a `summary()` and by a save (ADR 0038).
func to_dict() -> Dictionary:
	var part_rows := {}
	for key in parts.keys():
		part_rows[String(key)] = (parts[key] as BodyPart).to_dict()
	return {
		"demand_mastery": demand_mastery.duplicate(),
		"art_mastery": art_mastery.duplicate(),
		"record": record.duplicate(true),
		"parts": part_rows,
	}


static func from_dict(data: Dictionary) -> BodyPractice:
	var practice := BodyPractice.new()
	for key in data.get("demand_mastery", {}).keys():
		practice.demand_mastery[String(key)] = float((data["demand_mastery"] as Dictionary)[key])
	for key in data.get("art_mastery", {}).keys():
		practice.art_mastery[String(key)] = float((data["art_mastery"] as Dictionary)[key])
	for key in data.get("record", {}).keys():
		var row: Dictionary = (data["record"] as Dictionary)[key]
		practice.record[String(key)] = {
			"uses": int(row.get("uses", 0)),
			"landed": int(row.get("landed", 0)),
			"blunted": int(row.get("blunted", 0)),
		}
	for key in data.get("parts", {}).keys():
		practice.parts[String(key)] = BodyPart.from_dict((data["parts"] as Dictionary)[key])
	return practice
