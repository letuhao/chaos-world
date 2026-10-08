class_name VfxType
extends RefCounted

## Open enum for action technique VFX types.
##
## This is an OPEN vocabulary: new types are added by appending to the lists
## below, never by renaming or removing existing ones. A technique authored
## against `projectile` must keep working when `chain_lightning` is added.
##
## Each type belongs to exactly one category, and each category maps to one
## action slot type:
##
##   - Offensive  → Assault
##   - Defensive  → Barrier
##   - Movement   → Evasion
##   - Control    → Suppression
##   - Summon     → Transcendence
##
## Restoration has no VFX category because its visual is always a heal or
## buff on the caster or target — there is no distinct "restoration VFX"
## family. A restoration technique's VFX is `heal` or `buff`, both of which
## live in Defensive.
##
## The enum is keyed by snake_case name so a `.tres` can carry the string
## directly and a lookup is a dictionary hit, not a parse.

const OFFENSIVE := &"offensive"
const DEFENSIVE := &"defensive"
const MOVEMENT := &"movement"
const CONTROL := &"control"
const SUMMON := &"summon"

## Every VFX type, grouped by category. Order within a category is
## presentation order, not power order — a `beam` is not stronger than a
## `projectile`, it is a different shape.
const PROJECTILE := &"projectile"
const BEAM := &"beam"
const AOE := &"aoe"
const NOVA := &"nova"
const CHAIN := &"chain"
const EXPLOSION := &"explosion"
const METEOR := &"meteor"
const PULL := &"pull"
const PUSH := &"push"

const SHIELD := &"shield"
const BARRIER := &"barrier"
const HEAL := &"heal"
const BUFF := &"buff"

const DASH := &"dash"
const TELEPORT := &"teleport"
const BLINK := &"blink"

const TRAP := &"trap"
const ZONE := &"zone"
const STUN := &"stun"
const SLOW := &"slow"

const SUMMON := &"summon"
const TRANSFORM := &"transform"

## All types, canonically ordered. Used by the diversity validator and by a
## picker that offers the full vocabulary.
const ALL := [
	PROJECTILE,
	BEAM,
	AOE,
	NOVA,
	CHAIN,
	EXPLOSION,
	METEOR,
	PULL,
	PUSH,
	SHIELD,
	BARRIER,
	HEAL,
	BUFF,
	DASH,
	TELEPORT,
	BLINK,
	TRAP,
	ZONE,
	STUN,
	SLOW,
	SUMMON,
	TRANSFORM,
]

## Category lookup: VFX type -> category name.
const CATEGORY := {
	PROJECTILE: OFFENSIVE,
	BEAM: OFFENSIVE,
	AOE: OFFENSIVE,
	NOVA: OFFENSIVE,
	CHAIN: OFFENSIVE,
	EXPLOSION: OFFENSIVE,
	METEOR: OFFENSIVE,
	PULL: OFFENSIVE,
	PUSH: OFFENSIVE,
	SHIELD: DEFENSIVE,
	BARRIER: DEFENSIVE,
	HEAL: DEFENSIVE,
	BUFF: DEFENSIVE,
	DASH: MOVEMENT,
	TELEPORT: MOVEMENT,
	BLINK: MOVEMENT,
	TRAP: CONTROL,
	ZONE: CONTROL,
	STUN: CONTROL,
	SLOW: CONTROL,
	SUMMON: SUMMON,
	TRANSFORM: SUMMON,
}

## Action slot type -> VFX categories it may draw from.
##
## Restoration is absent because its VFX is always `heal` or `buff`, both of
## which are Defensive. A restoration technique's VFX is chosen from the
## Defensive category directly.
const SLOT_CATEGORIES := {
	&"assault": [OFFENSIVE],
	&"barrier": [DEFENSIVE],
	&"suppression": [CONTROL],
	&"restoration": [DEFENSIVE],
	&"evasion": [MOVEMENT],
	&"transcendence": [SUMMON, OFFENSIVE],
}


static func is_valid(vfx_type: StringName) -> bool:
	return CATEGORY.has(vfx_type)


static func category_of(vfx_type: StringName) -> StringName:
	return CATEGORY.get(vfx_type, &"")


static func for_slot(slot_type: StringName) -> Array:
	var categories: Array = SLOT_CATEGORIES.get(slot_type, [])
	var out: Array = []
	for vfx_type in ALL:
		if categories.has(category_of(vfx_type)):
			out.append(vfx_type)
	return out
