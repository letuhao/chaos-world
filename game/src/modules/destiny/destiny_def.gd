class_name DestinyDef
extends Resource

## One authored destiny branch: the story identity a player accrues toward
## without ever choosing it (ADR 0065).
##
## A destiny is earned the same way a fate is — by deeds, never by selection.
## Unlike a fate it is a *narrative* concept: it changes what content the
## player can reach, not what their numbers are. Destinies are mutually
## exclusive within a `group`, and earning one refuses the others in that group
## for good.
##
## This is the Chosen One / Revenger shape. There is no branch tree and no
## branch selection UI, because the player cannot pick and the system must not
## offer them a picker (ADR 0065).

const REVEALED := &"revealed"
const HIDDEN := &"hidden"
const TEASER := &"teaser"

## The exclusivity set. Two destinies in the same group can never both be held.
@export var group: StringName = &""
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## One line a player sees when they hold this destiny. Replaces the generic
## "you are bound to X" phrasing with authored voice.
@export var bearing: String = ""
@export var tier: int = 0
@export var visibility: StringName = REVEALED
@export var teaser: String = ""
## Fates granted at the moment this destiny is earned, in authored order.
## A fate granted this way is as permanent as any other.
@export var grants_fates: Array[StringName] = []
## Destinies that must all be held before this one can be earned. Named rather
## than embedded so the prerequisite graph can be cycle-checked at load.
@export var requires_destinies: Array[StringName] = []
## Fates that must be held before this one can be earned.
@export var requires_fates: Array[StringName] = []
## Pure-narrative gate target: authored IDs that may test `has_destiny` against
## this destiny. Lets story content be authored before the destiny exists.
@export var gate_aliases: Array[StringName] = []
## Probability modifiers this destiny contributes while held (ADR 0274).
## Same shape and rules as FateDef.probability_modifiers: maps a
## probability/rate stat id to a float shift, yin-yang paired.
@export var probability_modifiers: Dictionary = {}


func is_visible() -> bool:
	return visibility != TEASER


## Destinies this one excludes, resolved through the catalog: every other member
## of `group`. Never derived from position in an array, so inserting a destiny
## into the content tree cannot silently shift exclusivity.
func conflicts_with(other: DestinyDef) -> bool:
	return group != &"" and other != null and other.group == group and other.id != id
