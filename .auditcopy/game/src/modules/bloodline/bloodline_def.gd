class_name BloodlineDef
extends Resource

## One authored lineage: a **diluted, unlock-gated inheritance**, not an ability
## score (ADR 0063).
##
## A bloodline answers exactly two questions — *how concentrated is this in you*, and
## *has it unlocked yet*. It is not a level, it never grows inside a life, and it is
## not spendable: purity is inherited at conception and diluted by every mixed pairing
## after it.
##
## **Purity gates; it does not scale.** `awaken_threshold` is the concentration a
## lineage needs before it does anything at all, and once awake it contributes a
## bounded `PERCENT` modifier rather than a flat one. Scaling by purity would make the
## threshold meaningless and hand a deep-realm actor a compounding advantage; a flat
## value is dominated by the stat pool early and is noise by roughly realm 12, which
## kills the system on a 30-realm ladder. A bounded percent rides the actor's own
## growth and therefore means the same thing at R5 as at R30.
##
## `race_id` records the body plan this lineage conventionally runs in. It is authored
## flavour for a lineage screen, NOT a restriction: a lineage may cross races, and
## `&""` means exactly that.
##
## Adding a lineage is authoring a `.tres` under `game/data/bloodlines/`, never code.

@export var id: StringName = &""
@export var display_name: String = ""
## Clinical and mechanical, in the game's own voice. A lineage here feeds the
## succubus/birth system, so this copy describes structure and inheritance and nothing
## else (AGENTS.md).
@export var description: String = ""

## Concentration in `[0, 1]` at which this lineage's power unlocks. Equal to the
## purity means awake: a gate that reads as "at least this pure" is the only reading
## that does not strand a player one decimal below the bar.
@export var awaken_threshold: float = 0.42

## Fractions applied to the shared derived-stat pipeline as PERCENT modifiers, and
## ONLY while the lineage is awake. Bounded on purpose — see the class note.
@export var percent_modifiers: Dictionary = {}

## Traits this lineage grants while it is held. Projected alongside the
## `bloodline:<id>` mirror and recorded in the ledger so a strip can take back exactly
## what was added.
@export var traits: Array[StringName] = []
@export var tags: Array[StringName] = []
## The race this lineage conventionally runs in, or `&""` when it crosses races.
@export var race_id: StringName = &""


## Whether this lineage has unlocked at `purity`. The boundary is inclusive: a gate
## that read strictly above would make a threshold unreachable by exactly the number
## the content author wrote down.
func is_awake(purity: float) -> bool:
	return purity >= awaken_threshold


## The stat source id this lineage contributes under. Namespaced, so a re-projection
## can strip and rebuild the whole contribution from the ledger.
func source_id() -> StringName:
	return BloodlineState.source_for(id)


## The modifiers this lineage contributes. PERCENT only, and tagged with this
## lineage's own source so a rebuild is exact. Called only while awake.
func build_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for key in percent_modifiers.keys():
		out.append(
			StatModifier.new(
				StringName(key), Stat.Op.PERCENT, float(percent_modifiers[key]), source_id()
			)
		)
	return out


## Whether this lineage grants any stat at all. A lineage can be purely a gate: it
## carries a trait and nothing else.
func has_modifiers() -> bool:
	return not percent_modifiers.is_empty()
