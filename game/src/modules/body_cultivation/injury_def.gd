class_name InjuryDef
extends Resource

## Authored shape of ONE destroyed part: what it takes to break it, what rebuilding
## it costs, and the band a rebuilt part lands in.
##
## ## Why a part is DEFINED rather than inferred
##
## The brief is "destroy and recreate", so the unit of state is a PART, not a wound
## severity. `BodyWounds` already owns severity, necrosis and the recoverable
## `MeridianState.injured` flag (ADR 0070), and those all live in
## `combat_engine`. This file is the body path's own vocabulary for the third
## thing that sits on top of them: a part that has been taken apart on purpose and
## is currently WORSE than it was, which is not a thing `injured` can express
## (`injured` halves a bonus and is cleared by one elixir).
##
## ## Every number a balance pass moves lives in `InjuryTuning`, not here
##
## This file is the SHAPE — which part, on which meridian, at which huyệt, and
## which stat it degrades. The magnitudes (how much the stat falls, what a rebuild
## costs, how likely a rebuild beats the original) are one shared curve in
## `injury_tuning.tres`, for the reason AGENTS.md states about every other rate:
## thirty authored copies of one number is thirty chances to desynchronise.
##
## ## Why `meridian_id` AND `point_id`
##
## `BodyDamage` resolves at the MERIDIAN and treats the huyệt as the weak point
## within it (ADR 0070), so a part can be named at either granularity. A part
## bound to a channel moves the channel's aggregate; a part bound to a huyệt moves
## that huyệt's own quality. A part that names neither is refused rather than
## guessed — an injury with no location cannot degrade a stat, and silently
## degrading the whole body would make the number meaningless.

## The loss is a SHARE of what the part contributes: `stat x (1 - loss)`, and a
## destroyed part contributes `stat x broken_multiplier` on top of whatever it
## lost. ONE form, deliberately.
##
## A `flat` alternative was designed in and cut. A flat loss is an absolute point
## count against a stat whose magnitude the definition cannot see — it would have
## to be tuned per part against a figure that changes with the actor's realm, the
## provider stack and every other part on the same stat. That is the "second copy
## of a rate" failure AGENTS.md names, wearing a different hat. A share is bounded
## by construction, scales with the body it is on, and is legible in a balance
## report as one fraction.
##
## So `loss` is always a RATE in `[0, 1]`, clamped on read by `InjuryTuning
## .loss_of`. A part's SIZE is then `loss x loss_scale`, and the shipped table
## decides how hard the whole system bites without sixty files being edited.

## The part this definition destroys. Stable across save/load and never derived
## from the actor's current realm: a part that moved when a body entered a realm
## would re-point every injury the actor was already carrying.
@export var id: StringName = &""
@export var display_name: String = ""
## The channel this part rides, or `&""` for a part with no channel.
@export var meridian_id: StringName = &""
## The huyệt this part rides, or `&""` for a part that is the channel itself.
@export var point_id: StringName = &""
## The stat this part's loss is felt in. A `StringName` because the answer is
## core's and the module's own (`Stat.DEFENSE_PHYSICAL`, `BodyStats.MUSCLE_FIBER`);
## naming one as a field type would put a compile-time edge in this Resource that
## the `.tres` format does not need.
@export var stat_id: StringName = &""
## This part's share of the stat it is felt in, in `[0, 1]`. Always a RATE; see
## the module docblock for why a flat form was cut rather than shipped.
@export var loss: float = 0.0


## The stat id this part degrades, or `&""` when the definition names none — a
## content gap a caller can refuse on rather than a part that silently does
## nothing.
func stat() -> StringName:
	return stat_id


## Whether this part names somewhere on the body. A part with no location cannot
## degrade a stat, so every entry point refuses before anything is paid.
func has_site() -> bool:
	return stat_id != &"" and (meridian_id != &"" or point_id != &"")
