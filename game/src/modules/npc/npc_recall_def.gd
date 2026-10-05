class_name NpcRecallDef
extends Resource

## ONE authored incident, in prose, keyed to the REAL cause id (ADR 0253).
##
## ## Why this exists at all
##
## ADR 0091 made a relationship a ledger of authored causes and made the SUM a derived
## read. That is correct and it is also unreadable: a smith who has met you six times
## reads back as `standing: -6.0`, which is a number and not a thing anybody did. The
## player is told a total when the world actually has an INCIDENT — one named afternoon,
## one cause id, one body.
##
## ## **The cause id is the source of truth and the prose is a RENDERING of it.**
##
## This def authors NO amount. There is no standing here, no weight, no modifier: if the
## ledger says the bond moved because `walked_past_the_gate`, that id is what happened
## and this is only the sentence that says it out loud. Two rules keep them from drifting
## apart, and both are enforced by `NpcAliveness.memory` rather than asserted in a comment:
##
##   1. **A recall with no `cause_id` is refused**, not rendered — prose about an act
##      nothing recorded is exactly the second record this design refuses.
##   2. **`cause_id` is resolved against `SocialCauseCatalog` at read time.** An id no
##      shipped cause carries fails loudly rather than rendering, so a typo is a build
##      error rather than a sentence about something that never happened.
##
## There is deliberately no per-npc counter of how often this has been rendered. The
## ledger's `SocialBond.causes` already counts, and a second count is a second truth.

## The most rows one npc may author. A cast of 300 members at an unbounded number of
## recalled incidents each is a save that grows with content rather than with play, so
## the bound is named and the read refuses past it instead of quietly slicing (ADR
## 0173(b): exceeding a bound FAILS LOUDLY, never truncates).
const MAX_RECALLS := 8

## The authored cause this incident is a rendering of. REQUIRED — see the class note.
@export var cause_id: StringName = &""

## The anchor the sentence is written from, substituted in order. Pure presentation: it
## carries no magnitude, so it can never become a second number on the bond.
@export var anchors: Array[String] = []

## The one sentence. Written in the third person about what YOU did and what they saw,
## so it renders identically whoever is looking at it.
@export var prose: String = ""

## A colder, shorter line for a roster row. May be empty, in which case the long form
## is used — an empty short form is a display choice and not a broken asset.
@export var short_prose: String = ""


func valid() -> bool:
	return cause_id != &"" and not prose.is_empty()


## The short line if the author wrote one, else the long one. A panel never has to know
## which of the two fields it is reading.
func brief() -> String:
	return short_prose if not short_prose.is_empty() else prose


func to_dict() -> Dictionary:
	return {
		"cause_id": String(cause_id),
		"anchors": anchors.duplicate(),
		"prose": prose,
		"short_prose": short_prose,
	}
