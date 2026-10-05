class_name NpcOpinionDef
extends Resource

## ONE authored opinion, held by one npc, about one subject (ADR 0253).
##
## ## An opinion is a POSITION plus a SUBJECT, and both matter
##
## `subject_id` is **open**: it may be another authored npc, an institution, a place, or
## any other id the world already uses. That openness is the feature — a sect elder and a
## drifter can both hold a position of `elder_wei` and disagree about him on principle,
## and nothing in this module has to be taught what a sect is.
##
## **Two npcs holding different positions about the same subject is the ordinary case,
## not a contradiction** — which is why the closed half is the POSITION and not the
## subject.
##
## ## It carries NO magnitude and is NOT a bond
##
## There is no weight here and `SocialApi.apply_cause` is never called from this path: a
## view is a thing somebody BELIEVES, and making it also move standing would mean the
## player could farm an opinion the way ADR 0091's anti-farm rule exists to stop. The
## bond stays the only writer of a bond.

## Where a subject sits in an npc's regard. A closed authored vocabulary, kept in the
## STANCE_ALL order above the fields because GDScript requires every constant to precede
## every variable (`class-definitions-order`).
const STANCE_ENDORSED := &"endorse"
const STANCE_DISTRUST := &"distrust"
const STANCE_CONTEST := &"contest"
const STANCE_INDIFFERENT := &"indifferent"
const STANCE_ALL: Array[StringName] = [
	STANCE_ENDORSED, STANCE_DISTRUST, STANCE_CONTEST, STANCE_INDIFFERENT
]

## Held against something. Open vocabulary — an npc id, an institution, a place.
@export var subject_id: StringName = &""

@export var stance: StringName = STANCE_INDIFFERENT

## The sentence the npc would use for it. One authored line, rendered verbatim.
@export var prose: String = ""

## An optional deterministic slot: an authored opinion is chosen by CONTAINMENT (the
## subject is at the location) and this breaks the tie, which is why a story elder reads
## the same way twice while a composed minor does not roll at all.
@export var opinion_seed: int = 0

## The tiers this view is a plausible one FOR. **Empty means every tier** — an author who
## does not narrow it means it for the people who live there. Read by `NpcMinorComposer`
## so a composed minor's opinion is consistent with the place AND its tier, which is why
## the tier question lives in CONTENT and the mechanism never writes `if tier == minor`
## (ADR 0067).
@export var plausible_tiers: Array[String] = []


func valid() -> bool:
	return subject_id != &"" and not prose.is_empty()


func normalized_stance() -> StringName:
	return stance if STANCE_ALL.has(stance) else STANCE_INDIFFERENT


func to_dict() -> Dictionary:
	return {
		"subject_id": String(subject_id),
		"stance": String(stance),
		"prose": prose,
		"opinion_seed": opinion_seed,
	}
