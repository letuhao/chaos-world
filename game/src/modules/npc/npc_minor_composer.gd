class_name NpcMinorComposer
extends RefCounted

## COMPOSE AN UNTRACKED NPC, ON INTERACTION, FROM WHAT THE PLACE ALREADY KNOWS
## (ADR 0253).
##
## ## The problem this file exists to solve
##
## A minor npc must arrive **already plausible** — a name, a manner, one opinion consistent
## with the place they are in and their tier — **without a per-npc authored asset and without
## persisting**. The lazy answer is a roll: a global name list, a global manner list,
## `rng.pick` each. That produces a cutout, because a rolled opinion has no relationship to
## the room the person is standing in: the same three rows read identically whether you meet
## them at the gate or at the well.
##
## ## The rule that makes it a person instead: **CONTAINMENT, not a roll**
##
## A value is chosen by which authored rows the PLACE CONTAINS (`NpcPlaceVoice`, one
## `.tres` per location, found BY ITS ID). A voice that authors names, manners and opinions
## owns all three, and a minor standing in that location inherits a belief that is true *of
## that place*. Nothing is rolled from a global list: every value is a deterministic lookup
## keyed by the location, and the ONE thing that varies is the caller's `ordinal`.
##
## **Content cost is per-PLACE, not per-NPC.** One authored voice serves every minor who
## stands in that room, forever, with no asset per face — which is the difference between
## "cheap" and "not worth shipping".
##
## ## **Cost while nobody is looking: exactly zero**
##
## No cache, no table, no registration, no constructor. `compose` does ONE file-existence
## check and returns a value the caller drops. A settlement of 400 unobserved minor npcs
## costs **400 un-loaded `.tres` assets and zero dictionaries** — the whole lazy-principle
## promise, asserted against `NpcAliveness.composes` by a named counter in
## `tests/modules/npc/test_npc_alive.gd`.

## The most authored rows of ANY ONE kind read for a single persona. **This is the loop
## bound**: every table walked below is sliced to this length, so an author who authors
## 40,000 names pays this number and not 40,000. Above any plausible cast and pinned by a
## test, because a bound nothing queries is a number that moves silently.
const MAX_ROWS := 64

## `res://data/npc/personas/` — the authored place voices. Deliberately NOT the cast
## directory: these are per-PLACE rows, and keeping them apart is what lets a guard assert
## that the untracked tiers author no per-npc alive asset at all.
const PERSONA_ROOT := "res://data/npc/personas/"

## The magnitude floor for a composed persona when neither the place nor the def declares
## one. A named constant rather than a literal in a ternary, because a reviewer tuning the
## alive layer should have exactly one number to look at.
const DEFAULT_POWER_SCALE := 20.0

## The manner an unvoiced place gets. A CONSTANT, not a blank: an npc whose place authors
## nothing still has to hold themselves some particular way, or a panel prints nothing.
const DEFAULT_MANNER := "LOC_NPC_C1FBD4DC8B"

## The activity an unvoiced place gets, for the same reason.
const DEFAULT_ACTIVITY := "LOC_NPC_CD66EB8B1D"

## The opinion an unvoiced place gets. **A minor with no opinion is not a defect to paper
## over** — they are somebody who has not lived here long enough to have a view about it,
## which is what a minor npc usually is.
const DEFAULT_OPINION := "LOC_NPC_2D553A2664"

## The body an unvoiced place gets, with its verb and consequence.
const DEFAULT_TELL_VERB := &"nods_once"
const DEFAULT_TELL_BODY := "LOC_NPC_735EBAB8F2"
const DEFAULT_TELL_CONSEQUENCE := &"neutral"

## The name an unvoiced place with no def either gets. `a passer-by` rather than an
## invented human: an anonymous face is the honest shape when the world authors none.
const DEFAULT_NAME := "LOC_NPC_079C179B55"


## ## The composed persona for an untracked npc standing at `location_id`, of `tier`, as
## the `ordinal`-th face met in that room.
##
## `ordinal` is the ONLY thing that varies the name, and it is the caller's counter rather
## than a draw: two minors met in one room get distinct names, and a second read of the same
## room composes the same set. That is what makes a room feel occupied rather than being a
## slot machine.
##
## `def` may be null. **A minor npc needs no `.tres` of its own at all** — the voice supplies
## everything, and `def` contributes only a fallback name and a fallback magnitude scale.
## Passing null is therefore the normal case for a composed minor.
static func compose(
	location_id: StringName, tier: StringName, ordinal: int = 0, def: NpcDef = null
) -> NpcPersona:
	var persona := NpcPersona.new()
	persona.location_id = location_id
	var voice := _voice(location_id)
	persona.display_name = _name(voice, location_id, ordinal, def)
	persona.manner = _manner(voice, ordinal)
	persona.activity = _activity(voice, ordinal)
	persona.power_scale = power_scale(voice, def)
	_opinion(persona, voice, location_id, tier, ordinal)
	_tell(persona, voice, tier, ordinal)
	# The ONE write to the module's compose counter, and the reason it can be asserted
	# rather than believed: this line is the entire cost of a minor npc, and it runs only
	# because somebody interacted. `NpcAliveness.reset()` is the harness seam.
	NpcAliveness.composes += 1
	return persona


## The tuned magnitude a composed persona is built at: the PLACE's scale when it authors
## one, else the def's, else the constant floor. **Two declared sources and one constant,
## resolved in that order** — never a computed curve, because a magnitude the game computes
## is a second ladder (ADR 0050).
static func power_scale(voice: NpcPlaceVoice, def: NpcDef) -> float:
	if voice != null and voice.power_scale > 0.0:
		return voice.power_scale
	if def != null and def.minor_power_scale > 0.0:
		return def.minor_power_scale
	return DEFAULT_POWER_SCALE


## The authored voice for `location_id`, or null when the place authors none. **One
## `FileAccess` existence check, never a scan** — the id is the file name, so an absent
## place is a failed open rather than a directory walk. That is what makes composing a minor
## at an un-authored place O(1) rather than O(personas on disk).
static func _voice(location_id: StringName) -> NpcPlaceVoice:
	if location_id == &"":
		return null
	var path := "%s%s.tres" % [PERSONA_ROOT, String(location_id)]
	if not FileAccess.file_exists(path):
		return null
	var voice := load(path) as NpcPlaceVoice
	if voice == null:
		push_error(
			(
				(
					"NpcMinorComposer: '%s' is not an NpcPlaceVoice; a minor npc standing there "
					+ "composes from the constants instead of from authored content"
				)
				% path
			)
		)
	return voice


## ## The deterministic picks, and the fallback chain behind each
##
## `_pick` is what keeps every pick IN BOUNDS for any non-negative ordinal rather than
## indexing off the end, and a negative ordinal is refused by the `ordinal >= 0` half of
## each guard rather than by a clamp nobody wrote.


static func _name(
	voice: NpcPlaceVoice, location_id: StringName, ordinal: int, def: NpcDef
) -> String:
	if voice != null and voice.has_names() and ordinal >= 0:
		return _pick(voice.names, ordinal)
	if def != null and not def.display_name.is_empty():
		return def.display_name
	# The place's own name is the last authored resort, and it is honest: an unnamed
	# person at the well is "someone at {place}" rather than an invented human.
	if location_id != &"":
		return L.t("LOC_NPC_DB8A06EFCA") % String(location_id)
	return L.t(DEFAULT_NAME)


static func _manner(voice: NpcPlaceVoice, ordinal: int) -> String:
	if voice != null and voice.has_manners() and ordinal >= 0:
		return _pick(voice.manners, ordinal)
	return L.t(DEFAULT_MANNER)


static func _activity(voice: NpcPlaceVoice, ordinal: int) -> String:
	if voice != null and voice.has_activities() and ordinal >= 0:
		return _pick(voice.activities, ordinal)
	return L.t(DEFAULT_ACTIVITY)


## ## (2) ONE OPINION, filtered by TIER — and the tier is CONTENT
##
## The composer asks the voice "which of your opinions is a plausible view for THIS tier"
## and takes the first. **It never writes `if tier == major`.** That is ADR 0067's rule
## respected literally, and it is also the honest shape: only an AUTHOR knows which of a
## place's views belongs to a drifter and which to a gatekeeper, so the answer is authored
## data and the mechanism is a filter over it.
static func _opinion(
	persona: NpcPersona,
	voice: NpcPlaceVoice,
	location_id: StringName,
	tier: StringName,
	ordinal: int
) -> void:
	persona.opinion_stance = NpcOpinionDef.STANCE_INDIFFERENT
	persona.opinion_subject = location_id
	persona.opinion_prose = DEFAULT_OPINION
	if voice == null or ordinal < 0:
		return
	var seen := 0
	for authored in voice.opinions:
		if not authored.valid() or not _plausible_for(authored, tier):
			continue
		if seen == ordinal % maxi(1, voice.opinions.size()):
			persona.opinion_stance = authored.normalized_stance()
			persona.opinion_subject = authored.subject_id
			persona.opinion_prose = authored.prose
			return
		seen += 1


## (3) ONE BODY, chosen by the same containment + tier rule as the opinion.
static func _tell(
	persona: NpcPersona, voice: NpcPlaceVoice, tier: StringName, ordinal: int
) -> void:
	persona.tell_verb = DEFAULT_TELL_VERB
	persona.tell_body = DEFAULT_TELL_BODY
	persona.tell_consequence = DEFAULT_TELL_CONSEQUENCE
	if voice == null or ordinal < 0:
		return
	var seen := 0
	for authored in voice.tells:
		if not authored.valid() or not _plausible_for_tell(authored, tier):
			continue
		if seen == ordinal % maxi(1, voice.tells.size()):
			persona.tell_verb = authored.verb
			persona.tell_body = authored.body
			persona.tell_consequence = authored.consequence
			return
		seen += 1


## The one indexing operation, capped at [constant MAX_ROWS]. Every authored table a
## persona reads goes through here, which is what makes the cap a property of the composer
## rather than a thing each pick has to remember.
static func _pick(rows: Array[String], ordinal: int) -> String:
	var bounded := mini(rows.size(), MAX_ROWS)
	if bounded <= 0:
		return ""
	return rows[ordinal % bounded]


## Whether this authored opinion is a view a `tier` may plausibly hold. A row naming no
## `plausible_tiers` at all is TRUE FOR EVERY TIER — the safe default, because an author
## who authors an opinion plainly means it for the people who live there.
static func _plausible_for(opinion: NpcOpinionDef, tier: StringName) -> bool:
	return _tiers_allow(opinion, tier)


## The same question for a tell, and the same rule: an untiered row is for everybody.
static func _plausible_for_tell(tell: NpcTellDef, tier: StringName) -> bool:
	return _tiers_allow(tell, tier)


static func _tiers_allow(def: Resource, tier: StringName) -> bool:
	var declared: Variant = def.get("plausible_tiers")
	if not (declared is Array) or (declared as Array).is_empty():
		return true
	return (declared as Array).has(String(NpcTier.normalize(tier)))
