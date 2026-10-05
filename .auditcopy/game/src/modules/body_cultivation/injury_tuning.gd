class_name InjuryTuning
extends Resource

## Every balance number the destroy-and-recreate path reads, in DATA
## (BRIEF 1.7, and the same rule `CombatTuning` states for the body damage path).
##
## `body_cultivation/injury_tuning.tres` is the shipped instance; a rule reading a
## literal out of its own `.gd` is the defect this file exists to prevent, exactly
## as `combat_engine/combat_damage.tres` is for ADR 0070's seven numbers.
##
## ## Why ONE table and not one per part
##
## The brief's reward loop is "recreation can exceed the original", and the cost
## curve has to be the same SHAPE at R1 and R30 or the mechanic is dead at one end
## of the ladder and oppressive at the other. A per-`InjuryDef` copy of these
## numbers would be sixty authored chances to desynchronise that shape — the
## failure mode AGENTS.md names for every second copy of a rate. So a part declares
## WHICH stat it is and HOW BIG its own loss is (`InjuryDef.loss`), and everything
## about the PRICE OF REBUILDING IT is one shared curve read here.
##
## ## The defaults are the SCHEMA's neutral state, not a shipped balance
##
## A bare `InjuryTuning.new()` is deliberately degenerate in the same direction
## `CombatTuning.new()` is: a rebuilding that always fails, a loss that always
## zeroes, a cost that always refuses. A caller who forgets the `.tres` gets an
## obviously broken system rather than a plausible one.

## The share of a rebuilt part's stat it lands BELOW its original. The rebuild is
## a floor, not a refund: `rebuilt = original - original * rebuild_shortfall`,
## with the shortfall drawn from the `[shortfall_min, shortfall_max]` band below.
## Clamped into `[0, 1]` on read — a share above one would hand a rebuild MORE than
## it destroyed, which turns the whole loop into a free multiplier.
@export var rebuild_shortfall_min: float = 1.0
## The ceiling of the shortfall band. `rebuild_shortfall_min == rebuild_shortfall_max`
## makes every rebuild land at the same place, which is the deterministic form a
## suite pins and the balance a designer retunes away from.
@export var rebuild_shortfall_max: float = 1.0
## How much of the rebuilt part's original figure the shared reservoir is charged
## for the rebuild, as a share of the realm's own `integrity_maximum`. Clamped into
## `[0, 1]` on read: above one the "cost" is a heal, and a rebuild that PAYS the
## cultivator is not a gate.
@export var rebuild_cost_ratio: float = 0.0
## The channel the rebuild is carved from, or `&""` for no channel sacrifice. A
## `StringName` read out of DATA rather than a `MeridianDefaults` lookup in code:
## which channel a part costs is a design decision, and thirty-odd `.tres` files
## would each be able to name a channel without a `.gd` growing the second answer.
## Empty means a rebuild costs essence and nothing else.
@export var rebuild_cost_meridian: StringName = &""
## Whether `rebuild_cost_meridian` may equal the part's own channel. False is the
## shipped value: a part rebuilt out of its own channel would erase the very
## improvement the rebuild just made, which is a cost with no possible net.
@export var rebuild_cost_allows_source: bool = false

## The floor the rebuild band may not go below, as a share of the destroyed part's
## own figure. This is what keeps "permanent until deliberately recreated" honest
## even when `rebuild_shortfall_min` is authored at zero: an author's optimistic
## number cannot author a body that gets stronger from nothing.
@export var rebuilt_floor_ratio: float = 0.0
## The ceiling, as a share of the destroyed part's own figure. THIS is the brief's
## "recreation can exceed the original", and it is a NUMBER IN DATA rather than a
## branch in code: above `1.0` a good rebuild may genuinely beat what was
## destroyed, and that is the reward loop. Clamped into `[0, ...]` on read, never
## below the floor, so the band can never invert.
@export var rebuilt_ceiling_ratio: float = 1.0
## The chance a rebuild lands inside the band at all, against the chance it is
## REFUSED as a ruin and leaves the part destroyed where it was. Clamped into
## `[0, 1]`: at `0.0` no part can ever be recreated, which is a soft-lock rather
## than a difficulty setting. The ruin branch is what makes a rebuild a TRIAL.
@export var rebuild_chance: float = 0.0
## How far above the band a ruin falls, as a share of the part's original figure.
## Only ever a LOSS: a ruin must not be able to beat the ceiling above.
@export var ruin_drop_ratio: float = 0.0
## The stat multiplier a destroyed part contributes, relative to what it
## contributed before. This is the ONE number that makes property 2 measurable: a
## destroyed part applies `original x broken_multiplier` and nothing else, so the
## stat a body can use TODAY is lower the moment a part is taken apart.
## Clamped into `[0, 1]` on read — above one a destruction would be an upgrade.
@export var broken_multiplier: float = 0.0
## The share of `InjuryDef.loss` a destruction actually spends, `[0, 1]`. Lets a
## designer author one loss magnitude per part and have the shipped table decide
## how hard the whole system bites, without a balance pass editing sixty files.
@export var loss_scale: float = 0.0
## The first ladder index whose TRAINED channels are gated on a rebuild. Below it
## the gate is off and the ladder behaves exactly as it did before this system
## existed — which is the point: a gate on every channel from R1 is a wall across
## the whole ladder rather than a decision the player makes, and the early realms
## have no budget to pay for a rebuild. This is the one number a designer moves to
## open or close the system, and it is why the gate is scoped rather than absolute.
@export var gate_realm_index: int = 0
## Whether the gate is armed at all. False ships the system fully built — destroy,
## degrade, recreate, exceed — with the ADVANCEMENT gate left off, so the mechanic
## is complete and playable without being able to soft-lock a ladder that was
## authored before it existed. Flipping this one boolean is what makes the gate
## mandatory; it is data precisely because that decision is the owner's.
@export var gate_enabled: bool = false


## A shipped, sane instance. `duplicate(true)` for the reason `CombatTuning.shipped`
## gives: `load()` returns the RESOURCE CACHE's instance, so a caller that wrote to
## what it got would retune every later reader in the process.
static func shipped() -> InjuryTuning:
	var cached := load("res://data/body_cultivation/injury_tuning.tres") as InjuryTuning
	return cached.duplicate(true) as InjuryTuning if cached != null else null


## This part's share of the stat it is felt in, scaled by the table below. Always
## a RATE, and bounded into `[0, 1]` here rather than at every read site: a
## hand-edited `.tres` with `loss` of `-4.0` or `7.0` must not be able to invert a
## stat or zero it outright without the caller knowing.
func loss_of(def: InjuryDef) -> float:
	if def == null:
		return 0.0
	return clampf(_finite(def.loss) * _finite(loss_scale), 0.0, 1.0)


## The band a rebuilt part's shortfall is drawn from, `[min, max]` as shares of
## what was destroyed. Ordered on read, so a `.tres` whose two numbers were
## transposed gives a band rather than an empty one — and an empty band would be a
## rebuild that can only ever fail.
func shortfall_band() -> Vector2:
	var low := clampf(_finite(rebuild_shortfall_min), 0.0, 1.0)
	var high := clampf(_finite(rebuild_shortfall_max), 0.0, 1.0)
	return Vector2(minf(low, high), maxf(low, high))


## The band a rebuilt part's stat lands in, `[floor, ceiling]` as shares of what
## was destroyed. Always ordered, and always a floor at or below the ceiling, so a
## retune cannot produce a band that is empty — which would be a rebuild that can
## only ever fail. The ceiling is NOT clamped to `1.0`: exceeding the original is
## the brief's reward loop, and a table that forbade it would forbid the mechanic.
func rebuild_band() -> Vector2:
	var floor_ratio := maxf(0.0, _finite(rebuilt_floor_ratio))
	var ceiling_ratio := maxf(floor_ratio, _finite(rebuilt_ceiling_ratio))
	return Vector2(floor_ratio, ceiling_ratio)


## The essence a rebuild spends, as a share of the realm's `integrity_maximum`.
## Clamped into `[0, 1]`: the cost must never pay the cultivator back.
func cost_ratio() -> float:
	return clampf(_finite(rebuild_cost_ratio), 0.0, 1.0)


## The multiplier a destroyed part contributes. Clamped into `[0, 1]`: above one a
## destruction is a promotion, which inverts the whole brief.
func broken_share() -> float:
	return clampf(_finite(broken_multiplier), 0.0, 1.0)


## The chance a rebuild succeeds, read through the same clamp so a `.tres` cannot
## author `1.0` where the schema means a real trial.
func chance() -> float:
	return clampf(_finite(rebuild_chance), 0.0, 1.0)


## How far a ruined rebuild falls below the band's floor. Non-negative by
## construction: a ruin must be strictly a loss.
func ruin_drop() -> float:
	return clampf(_finite(ruin_drop_ratio), 0.0, 1.0)


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0
