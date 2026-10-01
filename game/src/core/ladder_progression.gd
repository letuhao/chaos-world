class_name LadderProgression
extends ProgressionModel

## Advances one rank when accumulated progress reaches a threshold.
## Context keys: "threshold" (float), "next_rank" (StringName).


func can_advance(state: PathState, context: Dictionary) -> bool:
	var threshold := float(context.get("threshold", 1.0))
	return threshold > 0.0 and state.progress >= threshold


func advance(state: PathState, context: Dictionary) -> void:
	var threshold := float(context.get("threshold", 1.0))
	var next_rank: StringName = context.get("next_rank", &"")
	state.progress = maxf(0.0, state.progress - threshold)
	state.stage += 1
	if next_rank != &"":
		state.rank_id = next_rank
