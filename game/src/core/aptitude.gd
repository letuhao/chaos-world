class_name Aptitude
extends RefCounted

## The TWELVE aptitudes (ADR 0881), ported verbatim from Keepverse's `AptitudeCatalog`
## (`gk-core/src/FusionRpg.Core/Stats/Aptitudes/Aptitude.cs`): three postures of four.
##
## An aptitude is a SOURCE, never a stat channel: a resolved value lives on an actor as
## POINTS, and `AptitudeMatrix` turns shares of those points into flat contributions on
## real channels. No aptitude id is ever a `derived()` id, and no channel id is named
## here.
##
## ## The roster is STRUCTURAL
##
## Three postures of four is the shape, not a balance number: changing either redefines
## which aptitudes exist, which is a reviewed vocabulary change. `all_ids()` is derived
## from the three lists, so the count is 3 x 4 BY CONSTRUCTION and a thirteenth aptitude
## cannot be added by editing a number.
##
## ## Nothing is user-picked
##
## Keepverse carries an allocation UI, presets and respec; this port does not. Aptitude
## POINTS are resolved from what an actor has BUILT (the three majors — qi, body, mind —
## and the techniques it has learned), and re-resolved at breakthrough and on learning a
## technique. There is no spend verb to call, by design.
##
## ## The one shared spelling, stated rather than avoided
##
## `&"agility"` is both `Stat.AGILITY` (a stored attribute) and an aptitude id here. The
## two are DIFFERENT LAYERS — an attribute is a value a derivation reads, an aptitude is
## a share the matrix resolves — and the overlap is deliberate, exactly one id wide, and
## pinned by `tests/core/test_aptitude.gd`. Every other aptitude id is disjoint from
## `Stat`'s vocabulary.

## The postures group the twelve for display and for reading a build's identity; a
## posture is READ (see `DominantPosture`'s Keepverse rule), never stored and never
## resolved against.
const POSTURE_FORCE := &"force"
const POSTURE_FINESSE := &"finesse"
const POSTURE_BASTION := &"bastion"

const POSTURES := [POSTURE_FORCE, POSTURE_FINESSE, POSTURE_BASTION]
const PER_POSTURE := 4

## The roster's order is APPEND-ONLY, Keepverse's own rule: an existing aptitude's
## ordinal never changes and a retired one's is never reused, because the ordinal is
## what tooling and tests pin the roster with.
const FORCE := [
	&"might",  # universal offence — power
	&"fortitude",  # mitigation — defense, absorption, reduction
	&"vigor",  # shield — capacity, regen, toughness
	&"onslaught",  # breaks guard, reflect
]
const FINESSE := [
	&"agility",  # dodge
	&"composure",  # crit denial
	&"pierce",  # breaks mitigation and shield
	&"focus",  # utility — qi, efficiency, cooldowns
]
const BASTION := [
	&"bulwark",  # guard — parry and block rate and strength
	&"retribution",  # reflect
	&"precision",  # breaks dodge — accuracy
	&"ferocity",  # breaks crit denial — crit rate and damage
]


## All twelve, in append-only ordinal order (Keepverse's 0..11).
static func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(FORCE)
	out.append_array(FINESSE)
	out.append_array(BASTION)
	return out


## The four ids of one posture, or an empty array for a name that is not a posture.
static func in_posture(posture: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	match posture:
		POSTURE_FORCE:
			out.assign(FORCE)
		POSTURE_FINESSE:
			out.assign(FINESSE)
		POSTURE_BASTION:
			out.assign(BASTION)
	return out


static func is_id(id: StringName) -> bool:
	return FORCE.has(id) or FINESSE.has(id) or BASTION.has(id)


## The posture an aptitude belongs to, or `&""` for an id outside the roster.
static func posture_of(id: StringName) -> StringName:
	if FORCE.has(id):
		return POSTURE_FORCE
	if FINESSE.has(id):
		return POSTURE_FINESSE
	if BASTION.has(id):
		return POSTURE_BASTION
	return &""


## The append-only position in [method all_ids], 0..11 — Keepverse's ordinal, kept so
## tests and tooling can pin the roster. `-1` for an id outside it.
static func ordinal_of(id: StringName) -> int:
	return all_ids().find(id)
