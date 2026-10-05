class_name ItemGrade
extends RefCounted

## Item grades and the realm tier required to use them (ADR 0007).

const MORTAL := &"mortal"
const SPIRIT := &"spirit"
const EARTH := &"earth"
const HEAVEN := &"heaven"
const IMMORTAL := &"immortal"
const DIVINE := &"divine"

const ALL := [MORTAL, SPIRIT, EARTH, HEAVEN, IMMORTAL, DIVINE]

const TIER_BY_GRADE := {
	MORTAL: 1,
	SPIRIT: 2,
	EARTH: 2,
	HEAVEN: 3,
	IMMORTAL: 3,
	DIVINE: 4,
}


static func required_tier(grade: StringName) -> int:
	return int(TIER_BY_GRADE.get(grade, 1))
