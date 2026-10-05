class_name LadderProgression
extends ProgressionModel

## Advances one realm along the shared ladder (ADR 0005) when accumulated progress
## reaches the threshold. Context keys: "threshold" (float).


func can_advance(state: PathState, context: Dictionary) -> bool:
	var threshold := float(context.get("threshold", 1.0))
	return threshold > 0.0 and state.progress >= threshold


func advance(state: PathState, context: Dictionary) -> void:
	var threshold := float(context.get("threshold", 1.0))
	state.progress = maxf(0.0, state.progress - threshold)
	state.stage += 1
	var next_realm := RealmDefaults.ladder().next(state.rank_id)
	if next_realm != null:
		state.rank_id = next_realm.id
