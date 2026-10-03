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
## Named counters this fate reads through the gate verb `counter`. Declaring
## them here keeps the gate answerable without a hardcoded id list in code.
@export var counters: Array[StringName] = []
## Tags a gate may test with `has_fate` when a fate should answer to several
## conceptual questions without duplicating definitions.
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
