class_name SeaProvider
extends StatProvider

## Emits derived stats from Sea of Consciousness state (ADR 0016). Reads the
## sea component attached to the actor. Capacity and fullness come from the
## actor's mind_power pool via the sea.
##
## Capacity is the whole emitted surface, and it is the one number here with two
## writers: this provider publishes it, and `MindTraining.synchronize` is what
## sets it from `MindRealmSeed.sea_capacity`. `MindProvider` must therefore not
## also scale it — see its docblock.
##
## `SEA_CLARITY`, `SEA_TURBULENCE` and `SEA_FULL` were DELETED (BL-0163) rather
## than left emitting into nothing. The first two restated component fields that
## ADR 0071's mind formula reads off `SeaOfConsciousness` directly, so a stat
## copy of them was a second copy of the truth with no reader. `SEA_FULL` was
## worse than unread — it was a THIRD definition of "full", comparing
## `current` against `effective_capacity()` while `SeaOfConsciousness.is_full()`
## compares against the reservoir maximum, so the two disagreed exactly when the
## sea was turbulent. `is_full` is the single definition now;
## `test_mind_stat_surface.gd` pins that disagreement is gone.


func contribute(context: StatContext) -> Dictionary:
	var sea: SeaOfConsciousness = context.component(&"sea_of_consciousness")
	if sea == null:
		return {}
	var pool := context.resource(MindStats.MIND_POWER)
	return {
		MindStats.SEA_CAPACITY: pool.maximum if pool != null else sea.structural_capacity,
	}
