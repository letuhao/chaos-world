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


func is_visible() -> bool:
	return visibility != TEASER


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
