class_name CombatShield
extends RefCounted

## The S9 binding of the four `CombatStats.SHIELD_*` ids (ADR 0068, ADR 0879): a
## capacity pool the spine drains through `absorb`, with a per-hit cut (`SHIELD_PEN`,
## the ATTACKER's), a removal multiplier (`SHIELD_TOUGHNESS`), and a per-second refill
## (`SHIELD_REGEN`).
##
## ## The contract takes a penetration
##
## `CombatSpine._absorb` calls `absorb(amount, penetration) -> overflow` on whatever
## component sits under `CombatSpine.SHIELD_COMPONENT`, where `penetration` is the
## attacker's `SHIELD_PEN`. The cut is the ATTACKER's number, so it cannot be read
## inside a component that only sees the defender's own state — a one-argument call
## cannot carry it, which is why ADR 0879 made the contract the two-argument one.
##
## ## No actor reference, on purpose
##
## A component that held its owner would be a RefCounted cycle (the actor's
## `module_data` holds the component, the component would hold the actor), and a cycle
## leaks. [method refresh] PULLS the owner's four numbers and stores floats, [method
## tick] takes the delta a caller owns, and nothing here reaches back.
##
## ## The spine never reads regen
##
## `SHIELD_REGEN` belongs to a combat tick, not to one hit's resolution, and a refill
## inside a resolve would reorder the stages it runs between. [method tick] is the only
## reader; a fight with no tick simply never refills.

## The authored ceiling: `SHIELD_CAPACITY` as last refreshed, with its neutral default
## folded in the way every other contest half is read.
var capacity_max: float = 0.0
## What is left. Starts at `capacity_max` when a caller binds through [method attach].
var current: float = 0.0
## Multiplier on the damage the pool is good for, `1.0 + SHIELD_TOUGHNESS` as last
## refreshed. `1.0` is the neutral; a stat channel floors at zero (`ActorStats._put`),
## so this can only be RAISED by authoring — the weakening half of the shield is the
## attacker's `SHIELD_PEN`, never a negative toughness.
var toughness: float = 1.0
## Per-second refill, `SHIELD_REGEN` as last refreshed.
var regen: float = 0.0


## A shield bound FULL, for a caller that has just equipped one. [method refresh] keeps
## `current` across a stat change; this is the one place a shield starts at its ceiling.
static func attach(actor: Actor) -> CombatShield:
	var shield := CombatShield.new()
	shield.refresh(actor)
	shield.current = shield.capacity_max
	return shield


## Bind this owner's shield the moment its BUILD resolves one (ADR 0887), and return it.
##
## The binding rule IS the build: a resolved `shield.capacity` above `0.0` means this body
## has a pool (the aptitude matrix's vigor edges write it), and `0.0` — the default every
## actor carries — means no shield at all, so an unbuilt body never grows a component it
## did not earn. Idempotent, and a component already bound under the key is left
## UNTOUCHED unless it is a real [CombatShield] (which is refreshed), so a test double
## keeps behaving as the double it is.
static func ensure(owner: Actor) -> RefCounted:
	if owner == null or owner.stats == null:
		return null
	var existing: RefCounted = owner.component(CombatSpine.SHIELD_COMPONENT)
	if existing != null:
		if existing is CombatShield:
			(existing as CombatShield).refresh(owner)
		return existing
	var capacity := (
		CombatStats.default_of(CombatStats.SHIELD_CAPACITY)
		+ owner.stats.derived(CombatStats.SHIELD_CAPACITY)
	)
	if not is_finite(capacity) or capacity <= 0.0:
		return null
	var shield := CombatShield.attach(owner)
	owner.set_component(CombatSpine.SHIELD_COMPONENT, shield)
	return shield


## Pull the four authored numbers off `owner` and clamp `current` down to a new ceiling.
## Idempotent, so a caller may refresh on every stat change rather than diffing them.
func refresh(owner: Actor) -> void:
	if owner == null or owner.stats == null:
		return
	capacity_max = maxf(
		0.0,
		(
			CombatStats.default_of(CombatStats.SHIELD_CAPACITY)
			+ owner.stats.derived(CombatStats.SHIELD_CAPACITY)
		)
	)
	toughness = maxf(
		0.0,
		(
			CombatStats.default_of(CombatStats.SHIELD_TOUGHNESS)
			+ owner.stats.derived(CombatStats.SHIELD_TOUGHNESS)
		)
	)
	regen = maxf(
		0.0,
		(
			CombatStats.default_of(CombatStats.SHIELD_REGEN)
			+ owner.stats.derived(CombatStats.SHIELD_REGEN)
		)
	)
	current = minf(current, capacity_max)


## The gate's contract: spend up to `amount` against the pool and return the OVERFLOW
## that got past — `0.0` when the shield took everything, `amount` when it took nothing.
##
## `penetration` is the attacker's cut and it lands BEFORE the blow: it is spent off the
## pool, so a piercing attacker leaves a smaller shield behind rather than a shielded
## hit. Removal is then `min(current * toughness, amount)`: toughness scales how much
## DAMAGE the pool is good for (`1.0` is the classic `min(current, amount)`), the removal
## is never more than the blow itself — a shield removes damage, it does not deal it —
## and the pool is debited only for what it held.
func absorb(amount: float, penetration: float = 0.0) -> float:
	if amount <= 0.0:
		return amount
	current = maxf(0.0, current - minf(current, maxf(0.0, penetration)))
	var removal := minf(current * toughness, amount)
	current = maxf(0.0, current - removal)
	return maxf(0.0, amount - removal)


## The refill `SHIELD_REGEN` owns: `regen` points per second, capped at the authored
## ceiling. The caller owns time (a combat tick, not one hit's resolution — see the
## class doc); a non-positive `delta` is a no-op rather than a rewind.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	current = minf(capacity_max, current + regen * delta)


## Primitives only, so `ui/` can render it without naming this class (ADR 0038).
func summary() -> Dictionary:
	return {
		"capacity_max": capacity_max,
		"current": current,
		"ratio": (current / capacity_max) if capacity_max > 0.0 else 0.0,
		"toughness": toughness,
		"regen": regen,
	}
