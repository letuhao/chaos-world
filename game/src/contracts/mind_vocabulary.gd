class_name MindVocabulary
extends RefCounted

## The mind-control vocabulary, as a dependency-free value object.
##
## ## WHY THIS IS IN `contracts/` AND NOT IN EITHER MODULE
##
## Two modules need the same ids and neither may name the other:
##
## - `mind_cultivation` PUBLISHES the stats — it owns the mastery tracks and the
##   composure pool, and the ids are its module's derived stats.
## - `status` READS the stats — it owns the contest, the expression damage and the
##   authored mind-status catalogue.
##
## `registry.json` gives `status` the deps `["contracts", "core"]` and
## `mind_cultivation` `["contracts", "core", "destiny", "items", "race"]`, so
## EITHER direction is an undeclared edge. AGENTS.md names the exact answer: "If
## two modules need each other's internals, the boundary is wrong: move the shared
## part to `contracts`/`core`." This is that move.
##
## It is a `RefCounted` and not a `Resource`, because nothing is AUTHORED against
## it — no `.tres` binds it. The authored content is `MindStatusDef`, which lives in
## the `status` module beside the catalogue that loads it. What lives here is the
## *spelling* of the vocabulary, which is what has to be shared.
##
## ## These ids are a PAIR, which is the point of one place for them
##
## Every prefix here has an offence half and a defence half with the SAME suffix,
## so a stat id can be built from one suffix and reach either side:
##
## ```
## MindVocabulary.offence_id(&"voice")   ->  mind_status_mastery_voice
## MindVocabulary.defence_id(&"voice")   ->  mind_composure_voice
## MindVocabulary.composure_pool        ->  mind_composure
## ```
##
## That symmetry is what makes a missing counterpart visible rather than
## plausible: a caller that builds an offence id and looks for no defence id has made
## the yin-yang mistake, and the names sit side by side here so it is a short read.

# --- the three roles -------------------------------------------------------------

const ROLE_CONTROL := &"control"
const ROLE_EXPRESSION := &"expression"
const ROLE_COMPOSURE := &"composure"
const ROLES: Array[StringName] = [ROLE_CONTROL, ROLE_EXPRESSION, ROLE_COMPOSURE]

# --- the four control shapes -----------------------------------------------------

## What a `control` does to the target's ACTIONS. **There is no `lock` in this
## list**, and that omission is the design rather than a gap: a status that removes
## the target's ability to act is an unanswerable disable, which the owner's rule
## refuses and `MindStatusDef.problems()` enforces as a load-time gate.
const SHAPE_SLOW := &"slow"
const SHAPE_COST := &"cost"
const SHAPE_FALSIFY := &"falsify"
const SHAPE_INVERT := &"invert"
const SHAPES: Array[StringName] = [SHAPE_SLOW, SHAPE_COST, SHAPE_FALSIFY, SHAPE_INVERT]

# --- the two expression channels -------------------------------------------------

## `voice` argues and is answered by CONVICTION; `intent` errs the target mid-act
## and is answered by CLARITY UNDER MOTION. Two, not four: each has a defender stat
## the other does not, and that non-symmetry is what makes them a vocabulary rather
## than two numbers.
const CHANNEL_VOICE := &"voice"
const CHANNEL_INTENT := &"intent"
const CHANNELS: Array[StringName] = [CHANNEL_VOICE, CHANNEL_INTENT]

# --- the two mastery tracks ------------------------------------------------------

const TRACK_STATUS := &"status"
const TRACK_EXPRESSION := &"expression"
const TRACKS: Array[StringName] = [TRACK_STATUS, TRACK_EXPRESSION]

# --- the stat id prefixes --------------------------------------------------------

## The ATTACKER's side of every contest: how well this mind imposes or projects.
const OFFENCE_PREFIX := "mind_status_mastery_"

## The DEFENDER's side: how well this mind refuses, or holds. Named in DATA rather
## than through either module's `Stats` class because neither module may name the
## other's types, and a `StringName` built here is a bare id no provider owns by
## accident.
const DEFENCE_PREFIX := "mind_composure_"

## The composure POOL an expression damages. A depleting reserve, and the answer to
## the projection's currency — the yin-yang half that makes a composure stat a
## budget rather than a permanent discount.
const COMPOSURE_POOL := &"mind_composure"

## The component key a `MindMasteryState` ledger lives under on the actor. In the
## vocabulary rather than in the module because BOTH sides need it: `mind_cultivation`
## mints and owns the ledger, and `status` looks one up on an attacker it was
## handed — and `status` may not name `MindMasteryState`, so the KEY is the only
## handle it can be given.
const MIND_STATE_COMPONENT := &"mind_mastery"


## The attacker's stat id for `suffix`, which is any shape or any channel.
static func offence_id(suffix: StringName) -> StringName:
	return StringName(OFFENCE_PREFIX + String(suffix))


## The defender's stat id for the same `suffix`. One suffix reaches either side, so
## a caller cannot spell a pair two ways.
static func defence_id(suffix: StringName) -> StringName:
	return StringName(DEFENCE_PREFIX + String(suffix))


## Whether `suffix` names something the game actually contests — a shape or a
## channel. A stat id built from anything else names a bucket no provider fills, and
## that reads `0.0` silently; this is the check that makes it a refusal.
static func is_contested(suffix: StringName) -> bool:
	return SHAPES.has(suffix) or CHANNELS.has(suffix)


## The suffix an id belongs to, or `&""` when it belongs to neither track. Used by
## the readout, so a screen can label a row without hard-coding six id spellings.
static func suffix_of(stat_id: StringName) -> StringName:
	var text := String(stat_id)
	if text.begins_with(OFFENCE_PREFIX):
		return StringName(text.substr(OFFENCE_PREFIX.length()))
	if text.begins_with(DEFENCE_PREFIX):
		return StringName(text.substr(DEFENCE_PREFIX.length()))
	return &""


## Which side of a contest an id sits on: `&"offence"` or `&"defence"`, or `&""` for
## an id outside the vocabulary. A readout asks this rather than testing two
## prefixes itself, which is how a third prefix would be added and missed.
static func side_of(stat_id: StringName) -> StringName:
	var text := String(stat_id)
	if text.begins_with(OFFENCE_PREFIX):
		return &"offence"
	if text.begins_with(DEFENCE_PREFIX):
		return &"defence"
	return &""
