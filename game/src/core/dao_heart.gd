class_name DaoHeart
extends RefCounted

## The actor's dao heart CRACKS and is REBUILT (BL-0932's ruling): a failed
## breakthrough or a heart-demon trial's toll leaves a scar, and the same
## cultivation-recovery content that heals a dantian mends it.
##
## ## Where the scar lives, and why not a modifier
##
## The scar is a NEGATIVE base offset on the dao heart's own id, and
## `actor_stats.gd`'s derivation adds it to `will` (the attribute the stat has always
## derived from). A `StatModifier` is the natural shape for a temporary debuff and it
## is WRONG here: modifiers are not serialized (`ActorStats.to_dict` carries only the
## aptitude cache; the actor's payload carries `base`), so a cracked heart would heal
## itself on the next load and the crack would be a lie. `base` IS serialized, so the
## scar survives a save for free — and `_put` floors the effective value at zero, so no
## scar can leave a hero with a negative heart.
##
## ## It composes upward with every authored grant
##
## The derivation is `(will + scar + flat) * (1 + percent)`, so the gear, set,
## bloodline and consumable grants that were decorative before (BL-0932) still add on
## top of a crack. Rebuilding is therefore TWO legitimate answers — spend the recovery
## elixir to raise the scar, or out-grow it with content — and neither is a second
## stat composer.


## The current scar on `actor`'s dao heart: `0.0` when whole, NEGATIVE when cracked.
static func crack_of(actor: Actor) -> float:
	if actor == null:
		return 0.0
	return minf(0.0, actor.stats.get_base(Stat.DAO_HEART))


## Crack the heart by `amount`, floored so the effective dao heart can never go below
## zero: `will` is the most a crack can eat. Returns the new scar.
static func crack(actor: Actor, amount: float) -> float:
	if actor == null or not is_finite(amount) or amount <= 0.0:
		return crack_of(actor)
	var floor := -maxf(0.0, actor.stats.derived(Stat.WILL))
	actor.stats.set_base(Stat.DAO_HEART, maxf(floor, crack_of(actor) - amount))
	actor.mark_stats_dirty()
	return crack_of(actor)


## Mend the scar by `amount`, never past zero: rebuilding restores a whole heart and
## never grants one. Returns the new scar.
static func rebuild(actor: Actor, amount: float) -> float:
	if actor == null or not is_finite(amount) or amount <= 0.0:
		return crack_of(actor)
	actor.stats.set_base(Stat.DAO_HEART, minf(0.0, crack_of(actor) + amount))
	actor.mark_stats_dirty()
	return crack_of(actor)
