class_name Injury
extends RefCounted

## DESTROY AND RECREATE: the body path's third overlay, and the one that is not a
## debuff.
##
## ## The three existing states, and the fourth this adds
##
## The body already carries two damage vocabularies and this is neither of them:
##   - `MeridianState.injured` (ADR 0017) — a RECOVERABLE flag. One elixir clears
##     it, it halves a bonus while set, and it never records what it cost.
##   - `BodyWounds` (ADR 0070) — accumulating SEVERITY, with NECROSIS that floors
##     at a threshold and a jam that one recovery item closes.
## A part that has been taken apart on purpose is neither: it is WORSE than it was
## in a way the body cannot walk back on its own, and the only way past it is to
## pay to build it again. So this file's unit of state is the PART, not a number
## that decays.
##
## ## THE STATE MACHINE
##
## ```
##   absent ──destroy──> broken ──recreate(succeeds)──> rebuilt ──destroy──> broken
##                        │                                  │
##                        └──recreate(ruins)──> broken      └──absorbed──> absent
##                                                            (the excess is kept)
## ```
##
## `broken` is PERMANENT. There is no tick, no decay, no timeout anywhere in this
## file: a part that is broken stays broken until [method recreate] succeeds, and
## the stat it degrades is lower the entire time. That is property 1 of the brief,
## and it is enforced by the ABSENCE of a decay path rather than by a flag that
## says "permanent".
##
## `rebuilt` is not an endpoint but a RANK. A rebuild may land BELOW the original
## (the usual case), or ABOVE it (the brief's reward loop) — and when it lands
## above, the excess is folded into the part's own `surplus` so the next rebuild
## starts from the stronger figure rather than from the number the actor started
## the realm with. That is what stops "recreation can exceed the original" from
## being a one-shot curiosity.
##
## ## WHY THE LEDGER IS ITS OWN COMPONENT
##
## A part's contribution is removed by a `StatModifier` tagged with a source id
## derived from the part, so `remove_modifiers_from` is exactly one call and cannot
## remove a modifier belonging to anything else. That modifier has to be
## REBUILDABLE after a save, and `Actor` serializes components as raw data, so
## this ledger stores the arithmetic and not the object. [method restore] re-derives
## the modifier from a reloaded payload; nothing here needs a live `StatModifier`
## to survive.
##
## ## NO TIMER, NO `Time`, NO LOOP
##
## An injury is not a `StatusEffect` and never becomes one. A decay would make
## waiting a recovery route, which is precisely what ADR 0070 forbids for wounds
## and what would turn the brief's "permanent until deliberately recreated" back
## into the timed debuff it replaced.

## One destroyed part. The ledger holds one of these per broken part.
##
## `origin` is the figure the part contributed BEFORE it was destroyed, and it is
## the number every later comparison is made against: the rebuild band is a share
## of it, `surplus` is added on top of it, and a broken part contributes
## `origin x broken_multiplier` regardless of how strong the body has since
## become.
var part_id: StringName = &""
## Whether this part was destroyed, as opposed to absent.
var broken: bool = false
## Whether the current state was reached by a successful rebuild rather than by
## the original destruction. Used by the read model only — the arithmetic reads
## `broken` and `origin`.
var rebuilt: bool = false
## The figure this part contributed before it was destroyed. Never recomputed from
## the actor's live stat: by the time a part is destroyed the body has already
## trained around it, and re-reading would make the recorded original drift.
var origin: float = 0.0
## What a previous rebuild earned ABOVE its origin, carried forward so a second
## rebuild is measured from the stronger figure. Zero on a never-rebuilt part.
var surplus: float = 0.0
## The stat this part is felt in, copied off the definition at destruction time so
## a definition edited between two saves cannot re-point a live wound.
var stat_id: StringName = &""
## The channel this part rides, or `&""`. Same reason as `stat_id`.
var meridian_id: StringName = &""
## The huyệt this part rides, or `&""`.
var point_id: StringName = &""


func _init(p_part_id: StringName = &"", p_stat_id: StringName = &"") -> void:
	part_id = p_part_id
	stat_id = p_stat_id


## The modifier source tag for this part. Derived from the part id and nothing
## else, so restoring a modifier after a save cannot collide with another part's,
## and `remove_modifiers_from` with this tag removes exactly this part's.
static func modifier_source(part_id: StringName) -> StringName:
	return StringName("body_injury_%s" % String(part_id))


## Whether this part is contributing at all. An absent part and a broken one are
## both "not whole", but only a broken one is still on the ledger.
func is_broken() -> bool:
	return broken


## THE SIGNED NUMBER THIS PART ADDS TO ITS STAT — and the single place that number
## exists.
##
## Broken: `-origin x loss`, read through `InjuryTuning.loss_of` so a hand-edited
## `.tres` cannot author a negative cost or one above the whole stat. A destroyed
## part is pure subtraction, so the stat a body can use TODAY is lower the instant a
## part is taken apart. That is property 2 of the brief, and it is one negative
## FLAT on the actor's own modifier stack rather than a flag every stat formula in
## the game would have to remember to consult.
##
## Rebuilt: `surplus`, which is `origin x rebuilt_share - origin`. A rebuild that
## landed BELOW its origin therefore removes whatever is left of the original cost,
## and a rebuild that landed ABOVE it becomes a POSITIVE modifier — a stat the part
## now contributes more of than it ever did. **The brief's "recreation can exceed
## the original" is not a branch anywhere in this module**: it is exactly what a
## positive `surplus` means, reached through the same subtraction a destruction
## uses, which is why the two halves cannot disagree about the arithmetic.
##
## Absent: `0.0`, because there is nothing to contribute.
func contribution(tuning: InjuryTuning) -> float:
	if not broken:
		return surplus
	var def := InjuryCatalog.definition_of(part_id)
	return -clampf(tuning.loss_of(def) * maxf(0.0, origin), 0.0, maxf(0.0, origin))


## The share of its original a part was last rebuilt at, or `-1.0` for one that has
## never been rebuilt. A NEGATIVE sentinel rather than `0.0` because `0.0` is a
## legal rebuilt share (a total ruin) and the read model has to tell "rebuilt to
## nothing" from "never rebuilt".
func rebuilt_share() -> float:
	if not rebuilt:
		return -1.0
	var total := origin + surplus
	return total / origin if origin > 0.0 else 1.0


## Raw data. `Actor` serializes module components as plain dictionaries, so this
## is the only shape a save ever sees and `InjuryLedger.load_from` is the only way
## back.
func to_dict() -> Dictionary:
	return {
		"part_id": String(part_id),
		"broken": broken,
		"rebuilt": rebuilt,
		"origin": origin,
		"surplus": surplus,
		"stat_id": String(stat_id),
		"meridian_id": String(meridian_id),
		"point_id": String(point_id),
	}


## Rebuild from raw data. `origin` and `surplus` are finite-checked because they are
## MULTIPLIED by the tuning's band and then become a `StatModifier` value: an
## untrusted save carrying `NaN` would produce `NaN` here, and `maxf(NaN, x) == NaN`
## survives every clamp in the stat pipeline (the same hole
## `BodyDamage`'s module docblock closes at its point 5).
static func from_dict(data: Dictionary) -> Injury:
	var part := Injury.new(StringName(data.get("part_id", "")), StringName(data.get("stat_id", "")))
	part.broken = bool(data.get("broken", false))
	part.rebuilt = bool(data.get("rebuilt", false))
	part.origin = maxf(0.0, _finite(float(data.get("origin", 0.0))))
	part.surplus = _finite(float(data.get("surplus", 0.0)))
	part.meridian_id = StringName(data.get("meridian_id", ""))
	part.point_id = StringName(data.get("point_id", ""))
	return part


static func _finite(value: float) -> float:
	return value if is_finite(value) else 0.0
