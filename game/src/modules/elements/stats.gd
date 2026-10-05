class_name ElementStats
extends RefCounted

## Element ids and per-element derived-stat id helpers (ADR 0004).

# Tier 1 — 五行
const METAL := &"metal"
const WOOD := &"wood"
const WATER := &"water"
const FIRE := &"fire"
const EARTH := &"earth"

# Tier 2 — advanced
const LIGHTNING := &"lightning"
const ICE := &"ice"
const WIND := &"wind"
const LIGHT := &"light"
const DARK := &"dark"

const BASE_ELEMENTS := [METAL, WOOD, WATER, FIRE, EARTH]
const ADVANCED_ELEMENTS := [LIGHTNING, ICE, WIND, LIGHT, DARK]

const MASTERY_PREFIX := "element_mastery_"
const POWER_PREFIX := "element_power_"
## ADR 0200: a defender's mitigation is a MAGNITUDE fed to a ratio, not a capped
## percent, so this is the `D` in `m = mitigation_ceiling * D / (K + D)` rather than a
## fraction of the fight. The old `element_resistance_` prefix named a percent whose
## ceiling is what stopped mattering as offense rode the realm ladder.
const DEFENSE_PREFIX := "element_defense_"

## ADR 0215. The per-element CRIT pair, by PREFIX and never by hand.
##
## ```
## element_crit_<e>           the attacker's chance to crit with <e>, as a MAGNITUDE
## element_crit_resist_<e>    the defender's answer to it
## ```
##
## ## Why a prefix and not a list, stated as the defect it prevents
##
## A hand-written list of ten `element_crit_<e>` ids is a list a new element silently
## leaves out of: add an eleventh element and it has no crit channel and no resist
## channel, every content option aimed at it validates clean, and nothing anywhere says
## so. `ElementStats.crit_ids()` derives the family from `all_ids()` instead, so the
## count is `2 x (elements + 1)` BY CONSTRUCTION and a new element joins by existing.
##
## The `+ 1` is [constant OMNI], the one channel that is not an element: a build cannot
## pick ten separate crit investments and have a blade that crits nothing at all, so the
## bare `element_crit` / `element_crit_resist` pair answers "every element at once". It is
## generated on the same rule as its siblings rather than special-cased, because a
## special case is the first thing a fourth prefix would be written next to.
const CRIT_PREFIX := "element_crit_"
const CRIT_RESIST_PREFIX := "element_crit_resist_"
## The element-less channel. The suffix `""` is what makes the generator above produce
## the bare ids without a special case.
const OMNI := ""


## Every element id the per-element stat families are generated over: the five base
## elements, the five advanced ones, and [constant OMNI]. Derived from the two tier lists
## rather than restated, so an element added to either list joins every family here.
static func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for element in BASE_ELEMENTS:
		out.append(element)
	for element in ADVANCED_ELEMENTS:
		out.append(element)
	out.append(OMNI)
	return out


static func mastery_id(element: StringName) -> StringName:
	return StringName(MASTERY_PREFIX + String(element))


static func power_id(element: StringName) -> StringName:
	return StringName(POWER_PREFIX + String(element))


static func defense_id(element: StringName) -> StringName:
	return StringName(DEFENSE_PREFIX + String(element))


static func crit_id(element: StringName) -> StringName:
	return StringName(CRIT_PREFIX + String(element))


static func crit_resist_id(element: StringName) -> StringName:
	return StringName(CRIT_RESIST_PREFIX + String(element))


## ## The generation rule, quoted, because it is the whole ADR consequence
##
## "Per-element crit is a **suffixed** variant of the same pair
## (`element_crit_<e>` / `element_crit_resist_<e>`), generated from the element table by
## prefix, never hand-listed -- a hand list is how a new element silently loses its crit
## channels."
##
## ## Why TWO functions and not one taking a prefix
##
## `CRIT_PREFIX` is `element_crit_` and `CRIT_RESIST_PREFIX` is `element_crit_resist_`, so
## one of them CONTAINS the other and a reader matching on prefix alone cannot tell which
## family an id belongs to. Naming both separately is what stops `element_crit_resist_fire`
## being read as a `fire` resist half of the offence family.
##
## ## Why `has_crit_id` is a THIRD function rather than a `has` on the others
##
## A caller asking "does this id name a crit channel" needs to answer for an id it was
## handed, not for an element it chose, and the omni pair (`element_crit`,
## `element_crit_resist`) has no suffix to match on. Deriving the answer by asking
## whether the id is IN the generated set is the one definition; a `starts_with` would be
## a second and would disagree on `element_crit_resist_fire`.
static func has_crit_id(stat_id: StringName) -> bool:
	return crit_ids().has(stat_id)


## Every crit id — offence and defence, every element and omni — as ONE flat set.
## `families x (elements + omni)` by construction, which is the number
## `tests/modules/elements/test_element_crit_channels.gd` pins as `2 * all_ids().size()`.
static func crit_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for element in all_ids():
		out.append(crit_id(element))
		out.append(crit_resist_id(element))
	return out


## Every per-element STAT id this module publishes, in one flat set. The element
## families and the ADR 0215 crit families together, derived the same way, so a caller
## that needs "what does this module put on an actor" never hand-lists it either.
static func published_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for element in all_ids():
		out.append(mastery_id(element))
		out.append(power_id(element))
		out.append(defense_id(element))
	out.append_array(crit_ids())
	return out
