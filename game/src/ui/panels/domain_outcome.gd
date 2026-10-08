class_name DomainOutcome
extends RefCounted

## The WORDING of what a domain verb just did — one sentence, from the MODULE's own reason
## id and the bridge's own table.
##
## ## Why the wording is not on the screen
##
## Two rules pull this out of `DomainExploreScreen` at once. A refusal must be reported in
## the module's vocabulary and never one this program invented (`DomainBridge.REASON_TEXT`
## words it; the id is what a driver and a test match on) — and a screen that words its own
## refusals is a second, quietly-wrong account of why a verb was refused. The hosting screen
## was also over its thousand-line ceiling, and this is the block that could leave without
## moving a single door: it is pure string composition over two inputs.
##
## ## Why the fixture id leads the sentence
##
## A room can hold three fixtures, so "You are not carrying its key" alone is ambiguous
## against two neighbours on the same row. `<fixture>: <text>` is what makes the line
## answerable, and it is composed in ONE place so the summary line and the message line can
## never name two different fixtures for one press.
##
## ## Why an accepted line carries BOTH the id and the wording
##
## A line with only the id leaves a player reading `claimed`; a line with only the wording
## leaves a driver and a test pattern-matching prose. Each half fails a different consumer,
## so the sentence carries both — and `reason` is empty on a free read, because nothing
## happened and an empty id beside the fixture name is a token no consumer can match.
##
## Contract: pure functions, no Node, no bridge. `reason_text` is handed the bridge's own
## wording rather than the bridge, so `ui/` keeps its facade-only boundary.

## What a fixture verb that SUCCEEDED did, keyed by the module's own reason ids. Each names
## the state it left behind, so an acceptance that changed nothing is visibly different from
## one that paid out.
##
## `telegraphing` and `fired` are named even though no verb on this screen produces them
## (ADR 0211: a trap is telegraphed by `presence`, which the composition root calls). They
## stay because the fixture line still has to word a trap the player triggered elsewhere, and
## a wording invented here would be a second account of the module's.
const OUTCOME_TEXT := {
	"telegraphing": "LOC_UI_PANELS_5846F5E8A0",
	"fired": "fired",
	"advanced": "advanced",
	"wrong_node": "LOC_UI_PANELS_4AAEE427FE",
	"claimed": "claimed",
}

## What a FREE read says it did. Its own sentence rather than an `OUTCOME_TEXT` row,
## because `inspect` answers with an EMPTY reason (`domain_fixtures.gd:533`): nothing
## happened, no state moved, nothing is owed.
const READ_TEXT := "LOC_UI_PANELS_E6033C333B"

## The prefix a refusal carries, so a player can tell a refusal from an acceptance without
## reading the tone colour (which is the theme's, not this program's).
const REJECTED_PREFIX := "LOC_UI_PANELS_E2A3E17593"


## The player-facing sentence for a reason id, as `DomainBridge.REASON_TEXT` words it.
## Falls back to the id itself: a reason this build has no wording for must still be
## REPORTED rather than dropped, because silently shortening a refusal to "Rejected" is how
## a player concludes the actor cannot do the thing at all.
static func reason_text(reason: String, worded: String) -> String:
	return reason if worded.is_empty() else worded


## What a successful verb did, in words.
static func outcome_text(reason: String) -> String:
	var text := String(OUTCOME_TEXT.get(reason, reason))
	return text if not text.is_empty() else "done"


## `<fixture>: <text>`, or `<text>` alone when no fixture is aimed at. The one place a
## fixture outcome is prefixed, so two lines can never name two different fixtures for one
## press.
static func sentence(fixture_id: StringName, text: String) -> String:
	if String(fixture_id).is_empty():
		return text
	return "%s: %s" % [String(fixture_id), text]


## The line for a fixture verb that answered: the reason ID and the wording, both, because
## each half fails a different consumer (see the class docblock).
static func accepted(fixture_id: StringName, reason: String) -> String:
	return sentence(fixture_id, "%s — %s" % [reason, outcome_text(reason)])


## The line for a fixture verb that refused. The reason is the MODULE'S and the sentence is
## the bridge's table — never a wording chosen here.
static func refused(fixture_id: StringName, reason: String, worded: String) -> String:
	return sentence(fixture_id, "%s %s — %s" % [L.t(REJECTED_PREFIX), reason, worded])


## The line for a free read. Composed through [method sentence] like every other fixture
## outcome, so it names the same fixture the rest of the screen is talking about.
static func read(fixture_id: StringName) -> String:
	return sentence(fixture_id, READ_TEXT)
