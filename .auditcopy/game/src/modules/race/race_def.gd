class_name RaceDef
extends Resource

## One authored race: a **body plan**, not a stat stick (ADR 0062).
##
## A race replaces `SpeciesDef` and inherits its reproduction fields — `gestation_days`,
## `base_fertility`, `base_potency` and `offspring_variance` are race data now, not a
## separate species concept.
##
## **A race is one value, never a blend.** A child of two different races is born ONE
## race: `dominance` says how strongly this body asserts in a contested conception, and
## `manifestation_threshold` is the share it needs before it appears at all.
##
## **Every race carries a liability as authored data, in this same Resource as its
## advantage.** `closed_paths` (a path this body cannot take), `realm_ceiling` (0 = no
## ceiling) and `lifespan` are structural, not numeric: they cannot be bought off with
## an item, so no race is ever strictly best. A race with none of them authored is a
## content bug — `has_liability()` exists so a test can say so.
##
## Adding a race is authoring a `.tres` under `res://data/races/`, never code.

## `tags` entry marking the catalog's fallback race: the one a conception resolves to
## when no parent's race clears its manifestation threshold. Authored as data so the
## choice is content, not a hardcoded id in code.
const BASELINE_TAG := &"baseline"

@export var id: StringName = &""
@export var display_name: String = ""
## Clinical and mechanical, in the game's own voice. A race here is a body plan and
## inherits the succubus/birth system, so this copy describes structure and never
## anything else (AGENTS.md).
@export var description: String = ""

# --- Reproduction (inherited from SpeciesDef, ADR 0002) --------------------

@export var gestation_days: float = 30.0
@export var base_fertility: float = 0.0
@export var base_potency: float = 0.0
@export var offspring_variance: float = 0.1

# --- Body plan ---------------------------------------------------------------

## How strongly this race asserts in a contested conception. Higher wins more often.
@export var dominance: float = 0.5
## Share of a contested conception this race needs before it manifests at all. A
## parent whose share lands below this contributes nothing.
@export var manifestation_threshold: float = 0.2

# --- Liabilities (mandatory; a race without one is a content bug) -------------

## Cultivation paths this body CANNOT take, as `PathState` ids.
@export var closed_paths: Array[StringName] = []
## Highest realm ordinal this body can reach. 0 means no ceiling.
@export var realm_ceiling: int = 0
## Total authored lifespan in days.
@export var lifespan: float = 36500.0

# --- Grants ------------------------------------------------------------------

## Base attributes this body is born with, applied once through
## `ActorStats.set_base` — a `StatModifier` can only raise a base attribute, never
## lower one, so a race that grants a base attribute cannot be expressed as a
## modifier. See `RaceProjection`.
@export var base_attributes: Dictionary = {}
## Fractions applied to the shared derived-stat pipeline as PERCENT modifiers.
@export var percent_modifiers: Dictionary = {}
## Element affinities this body is born with.
@export var affinities: Dictionary = {}

@export var tags: Array[StringName] = []


## The stat source id this race contributes under. Namespaced, so a re-projection can
## find every race modifier and rebuild it from the ledger.
func source_id() -> StringName:
	return RaceState.source_for(id)


## The modifiers this race contributes. PERCENT only: a flat modifier is how a stat
## stick is built, and this race is not one.
func build_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for key in percent_modifiers.keys():
		out.append(
			StatModifier.new(
				StringName(key), Stat.Op.PERCENT, float(percent_modifiers[key]), source_id()
			)
		)
	return out


## Whether this race grants any stat at all. A body plan may be entirely structural.
func has_modifiers() -> bool:
	return not percent_modifiers.is_empty()


## Whether this race carries at least one structural liability. Exposed so a content
## test can hold the line ADR 0062 draws: a race whose only downside is a number is a
## stat stick with a costume.
func has_liability() -> bool:
	return not closed_paths.is_empty() or realm_ceiling > 0 or lifespan < 36500.0


## Whether this body can cultivate `path_id`.
func allows_path(path_id: StringName) -> bool:
	return not closed_paths.has(path_id)


## Whether this body may attempt `realm_index`. `realm_ceiling` 0 means no ceiling,
## so an unbounded body answers true at any ordinal.
func allows_realm(realm_index: int) -> bool:
	return realm_ceiling <= 0 or realm_index <= realm_ceiling


## Whether `realm_index` is past what this body can reach. An actor who is already
## above the ceiling is still reported as blocked: ascension does not rewrite a race.
func realm_ceiling_exceeded(realm_index: int) -> bool:
	return realm_ceiling > 0 and realm_index > realm_ceiling
