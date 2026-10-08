class_name FateDef
extends Resource

## One authored fate: a permanent consequence of a specific kind of deed.
##
## A fate is data, never code (ADR 0006 pattern). It is earned exactly once,
## applies immediately, and is never removed — there is no equip slot and no
## revoke path anywhere in the module.
##
## `visibility` controls what the player may see before it is earned:
##   &"revealed" — listed with full copy.
##   &"hidden"   — listed but unnamed; `teaser` is the only text shown.
##   &"teaser"   — omitted from the codex entirely.

const REVEALED := &"revealed"
const HIDDEN := &"hidden"
const TEASER := &"teaser"

## ## The CLOSED lineage vocabulary of [member tags]
##
## A tag is a KIND of deed, named so a gate can ask "does this actor carry any
## fate of that kind" without naming the fate. Seven values, declared here rather
## than authored per-fate, because an author may NOT coin a lineage: a tag outside
## this set refuses with `unknown_tag` (ADR 0196, fate tag vocabulary) and is never a plain unmet.
##
## Engine-shaped tokens are EXCLUDED on purpose. `defensive`, `aggressive`,
## `heavy`, `resilient`, `fast_path`, `killcount` and `marked` were all authored on
## shipped fates, and every one restates what `flat_modifiers` / `percent_modifiers`
## already say — a gate on "heavy" is stat language leaking into a gate, and two
## fates whose bonuses were retuned together would silently start agreeing on a
## lineage. `heaven` duplicates [member category]; `first` and `solitary` are
## position words the `counter` verb answers better.
const TAGS: Array[StringName] = [
	&"oath",
	&"blood",
	&"mercy",
	&"severance",
	&"desertion",
	&"rebirth",
	&"duel",
]

@export var id: StringName = &""
@export var display_name: String = ""
## Why this fate exists, in the game's own voice. Never engine vocabulary.
@export var description: String = ""
## Grouping for the codex: &"oath", &"blood", &"heaven", &"rebirth", ...
@export var category: StringName = &""
@export var tier: int = 0
@export var visibility: StringName = REVEALED
## Shown in place of the name when `visibility` is HIDDEN. Never spoils the
## effect.
@export var teaser: String = ""
## Applied on earn, as `StatModifier`s, exactly like an authored trait.
@export var flat_modifiers: Dictionary = {}
@export var percent_modifiers: Dictionary = {}
## Probability modifiers this fate contributes (ADR 0274). Maps a
## probability/rate stat id to a float shift. Unlike flat_modifiers (which
## shift a magnitude), these shift a PROBABILITY — a 0..1 rate. The yin-yang
## rule applies: every positive shift carries a negative counterpart authored
## in the same fate.
@export var probability_modifiers: Dictionary = {}
## Named counters this fate reads through the gate verb `counter`. Declaring
## them here keeps the gate answerable without a hardcoded id list in code.
@export var counters: Array[StringName] = []
## ## The lineages this fate belongs to, read by the `tagged` gate verb
##
## Every entry must be inside [constant TAGS] — a closed vocabulary of KINDS of
## deed, not a free label. An author may not coin one: a gate naming a tag outside
## the set refuses `unknown_tag` and names it, because a tag nothing carries is a
## gate that can never open (ADR 0196, fate tag vocabulary).
##
## **OR across fates.** `{verb: &"tagged", id: &"oath"}` is satisfied by holding
## ANY ONE fate carrying `oath`. That is the only defensible reading: tags are
## unordered with no primary, and a per-fate variant is what `has_fate` already is.
##
## **Empty is legal and means "answers to no lineage question."** Six of the
## seventeen shipped fates carry none, and that is not a defect to fix.
##
## **Never exclusive, never ordered, never consumed.** Carrying a tag earns
## nothing: it grants no stat, opens no reward, and a `tagged` gate only READS this
## list, so no gate can remove the fate (ADR 0065).
##
## **Not [member DestinyDef.group], and never to be unified with it.** A group
## closes its members against each other forever — earn one and the rest are
## forfeit. A tag does the opposite: it is a question several fates may answer.
@export var tags: Array[StringName] = []
## Fates that become available when this fate is held (ADR 0383). A synergy is a
## prerequisite edge, not a grant: holding this fate makes the listed fates earnable,
## but each must still be earned through its own deed path. Must be consistent with
## `requires` on the target fates: `A.unlocks` contains `B` iff `B.requires` contains `A`.
@export var unlocks: Array[StringName] = []
## Fates that must be held before this fate can be earned (ADR 0383). Empty means
## no synergy prerequisite. The synergy graph must be acyclic.
@export var requires: Array[StringName] = []


func is_visible() -> bool:
	return visibility != TEASER


## Whether this fate participates in any synergy relationship.
func has_synergy() -> bool:
	return not unlocks.is_empty() or not requires.is_empty()


## The stat source id this fate contributes under. Namespaced so a re-projection
## can find every fate modifier and rebuild it from the ledger.
func source_id() -> StringName:
	return DestinyState.source_for(id)


## The modifiers this fate contributes. Same construction as an authored trait,
## because fate reuses the single stat-modifier pipeline rather than composing
## its own fold (ADR 0065).
func build_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for key in flat_modifiers.keys():
		out.append(
			StatModifier.new(StringName(key), Stat.Op.FLAT, float(flat_modifiers[key]), source_id())
		)
	for key in percent_modifiers.keys():
		out.append(
			StatModifier.new(
				StringName(key), Stat.Op.PERCENT, float(percent_modifiers[key]), source_id()
			)
		)
	return out


## Whether this fate contributes any stat at all. A pure-narrative fate is
## legitimate: it exists to gate story, and it applies nothing.
func has_modifiers() -> bool:
	return not flat_modifiers.is_empty() or not percent_modifiers.is_empty()


## The probability modifiers this fate contributes (ADR 0274). Same
## construction as build_modifiers(), but for rate/probability stats.
func build_probability_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for key in probability_modifiers.keys():
		out.append(
			StatModifier.new(
				StringName(key), Stat.Op.FLAT, float(probability_modifiers[key]), source_id()
			)
		)
	return out


## Whether this fate contributes any probability modifier at all.
func has_probability_modifiers() -> bool:
	return not probability_modifiers.is_empty()


## The fate ids that can be offered together with this one when its trigger fires
## (ADR 0389). Empty means this fate is never part of a choice group. The choice
## is a UI presentation of implicit eligibility: when multiple fates in this
## list are eligible (their gate conditions are met and the actor does not hold
## them), the UI presents them as a choice. The backend resolves it through
## existing earn logic — the player picks one and `earn_fate` records it.
##
## The group is symmetric: if A lists B, then B lists A. The UI reads this list
## from the fate whose trigger fired and presents all eligible fates in the group.
@export var eligible_choices: Array[StringName] = []


## Whether this fate is part of a choice group (ADR 0389).
func has_eligible_choices() -> bool:
	return not eligible_choices.is_empty()


## The fate ids in `eligible_choices` that the actor does not already hold,
## canonically ordered. A fate the actor holds is not eligible to be offered.
func unheld_choices(ledger: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for fate_id in eligible_choices:
		if not DestinyState.has_fate(ledger, fate_id):
			out.append(fate_id)
	return out


## Dialogue changes when this fate is held (ADR 0398). Maps a dialog_id to a
## text override. When the player holds this fate, the dialog generator
## replaces the base text for that dialog_id with the override. Empty means
## this fate modifies no dialogue.
@export var dialog_modifiers: Dictionary = {}

## The difficulty events this fate triggers when earned (ADR 0404).
##
## Each event is a Dictionary with `event_type` (closed vocabulary), `magnitude`
## (float), and `description` (player-facing text). Three event types:
##   &"enemy_spawn"       — more enemies appear in the world
##   &"social_difficulty" — NPCs harder to persuade, prices increase
##   &"combat_difficulty" — enemies become stronger, new enemy types appear
##
## The yin-yang rule: every fate with positive stat modifiers MUST declare at
## least one difficulty event. A fate with no modifiers needs no event.
const DIFFICULTY_EVENT_TYPES: Array[StringName] = [
	&"enemy_spawn",
	&"social_difficulty",
	&"combat_difficulty",
]

@export var difficulty_events: Array[Dictionary] = []


## Whether this fate triggers any difficulty event at all.
func has_difficulty_events() -> bool:
	return not difficulty_events.is_empty()


## The total difficulty modifier for `event_type` from this fate. 0.0 when
## the fate declares no event of that type.
func difficulty_modifier_for(event_type: StringName) -> float:
	var total := 0.0
	for event in difficulty_events:
		if not (event is Dictionary):
			continue
		if StringName((event as Dictionary).get("event_type", &"")) == event_type:
			total += float((event as Dictionary).get("magnitude", 0.0))
	return total
