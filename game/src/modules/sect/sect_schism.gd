class_name SectSchism
extends RefCounted

## **A schism costs BOTH halves** (BL-0197, ADR 0085).
##
## A free schism is a strictly-positive action, so every crisis would end in a
## split and no institution would ever have to answer for one. That is why this
## exists rather than being folded into `promote` or `leave`: the price is the
## only thing standing between a disagreement and an amputation, and a split that
## charges nothing is a strictly-positive move any actor can make for any reason.
##
## ## What a split does, in exactly three numbers
##
## 1. **The undivided standing is divided.** `half = undivided / 2`, floor. The one
##    point an odd undivided value leaves over is **charged away, never minted**:
##    each half starts at the same `half`, so `kept + seceded <= undivided` is a
##    property of the shape rather than of the content. Two halves that each
##    inherited `ceil(undivided / 2)` would sum back to more than they started
##    with, which is a grant wearing a split's clothes.
## 2. **Each half pays the declared cost**, read from `SectTuning.schism_cost`
##    through `SectCatalog`. A rebalance is a `.tres` edit and a cost nobody can
##    retune is a cost nobody owns (ADR 0067's shape).
## 3. **Each half pays again per territory the declaration leaves unassigned**,
##    read from `SectTuning.schism_cost_per_unassigned`. A split is a split, not a
##    transfer: ground neither half took is nobody's ground, and the price of
##    leaving it that way is charged to BOTH halves rather than to whichever one
##    the caller likes.
##
## ## The price is symmetric BY CONSTRUCTION, not by convention
##
## One `settled` number is computed here and written to both halves. Two callers
## each subtracting their own price would be two places to drift, and the whole
## rule is that neither half is cheaper.
##
## ## This module assigns NO territory
##
## The per-territory charge reads an authored `SectDef.territory_ids` and an
## assignment list the caller passes; it never moves ground and never decides
## who holds what. That is ADR 0085's rule ("a claim on held ground never moves
## ground") plus its territory rule ("territory grants no combat bonus"): a schism
## decides WHO EXISTS and WHAT EACH OWNS IN RECOGNITION, and the spine decides
## everything else.
##
## Nothing here reads a clock, consults an `rng`, or grants a stat. The standing
## a split halves is the number `SectProjection` already projects as the one
## bounded `PERCENT` (ADR 0084); this file moves that number and touches no
## modifier, no base attribute and no other stat surface.

## The word a declared split is recorded under. It is the SECT's word, carried
## verbatim into whatever reads the declaration: a reader decides for itself
## whether `schism` is hostile, and this module never asks anybody to agree.
const VERB := "schism"

## The named reason each refusal uses. Strings rather than an `enum` because every
## one of them crosses the facade as a `String` and is written into a history
## record; an ordinal in either place would be a number whose meaning changes the
## moment somebody reorders this file (ADR 0084).
const R_NO_ACTOR := "no_actor"
const R_NOT_A_MEMBER := SectApi.NOT_A_MEMBER
const R_UNKNOWN_SECT := SectApi.UNKNOWN_SECT
## The seceding half is a sect id this build does not ship. `join` refuses an
## unknown sect for the same reason: an institution nothing defines teaches
## nothing, grants nothing and fills no office.
const R_UNKNOWN_HALF := "unknown_half"
const R_CANNOT_SECEDE_FROM_ITSELF := "cannot_secede_from_itself"
const R_ALREADY_SECEDED := "already_seceded"
## There is no undivided standing to divide: one point, or none. Splitting it
## would produce two halves of zero and charge both of them for the privilege,
## which is the worst possible trade and a refusal rather than a formality.
const R_NOTHING_TO_SPLIT := "nothing_to_split"

## The same six, keyed by the name each refusal is written with, so a caller can
## look a reason up without holding the constant.
const REASONS := {
	R_NO_ACTOR: R_NO_ACTOR,
	R_NOT_A_MEMBER: R_NOT_A_MEMBER,
	R_UNKNOWN_SECT: R_UNKNOWN_SECT,
	R_UNKNOWN_HALF: R_UNKNOWN_HALF,
	R_CANNOT_SECEDE_FROM_ITSELF: R_CANNOT_SECEDE_FROM_ITSELF,
	R_ALREADY_SECEDED: R_ALREADY_SECEDED,
	R_NOTHING_TO_SPLIT: R_NOTHING_TO_SPLIT,
}


## The whole of the arithmetic, as one dictionary, so a caller and a test read the
## same numbers rather than each re-deriving the sum.
##
## `undivided` is the standing before the split; `half` is what each side inherits;
## `odd_charged` is the point an odd undivided value loses; `price` is what each
## side pays; `settled` is what each side is left holding; `shortfall` is how much
## of the price a half could not cover, clamped at zero rather than driven below.
##
## **The clamp is the cost being real.** A half whose price exceeds its inheritance
## settles at zero and publishes the shortfall rather than refusing the split: a
## schism nobody can afford to make is not a game rule, it is a missing verb. The
## shortfall is what lets a panel say "this split will cost you everything you
## have" before it happens.
static func settle(undivided: int, price: int) -> Dictionary:
	var before := maxi(0, undivided)
	var charged := maxi(0, price)
	var half := int(floor(float(before) / 2.0))
	return {
		"undivided": before,
		"half": half,
		"odd_charged": before - half * 2,
		"price": charged,
		"settled": maxi(0, half - charged),
		"shortfall": maxi(0, charged - half),
	}


## What each half pays when `assigned` names places out of the sect's authored
## `territory_ids`: the declared cost plus the per-territory charge, in the one
## place `SectTuning` already keeps it (`SectTuning.schism_price`).
static func price(tuning: SectTuning, unassigned: int) -> int:
	if tuning == null:
		return 0
	return tuning.schism_price(unassigned)


## How many of the sect's authored places the declaration left UNASSIGNED.
##
## Counted against `SectDef.territory_ids` rather than against the argument, so the
## caller cannot shrink the bill by handing in a short list, and a place id the
## sect never claimed is not a place a split can abandon. The loop is bounded by
## the authored content on both sides.
static func unassigned(def: SectDef, assigned: Array[StringName]) -> int:
	if def == null:
		return 0
	var held := def.territory_ids
	var taken := 0
	for place_id in assigned:
		if place_id == &"" or held.has(place_id):
			taken += 1
	return maxi(0, held.size() - taken)
