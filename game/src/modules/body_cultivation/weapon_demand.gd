class_name WeaponDemand
extends RefCounted

## The six body demands a weapon kind can ask for, and the one-to-one map from a
## demand to the BASE ATTRIBUTE that pays for it.
##
## ## This is the mechanism that makes kinds different, and it is a lookup
##
## A kind does not store a multiplier. It stores a demand id, and the demand
## resolves here to exactly one base attribute. So a maul trains a body that
## already has mass to move, and a needle trains a body that already has the
## steadiness to place a point — and neither can be reached by the other's
## training, because the entries below are different attributes rather than two
## sizes of the same one. A seventh kind that reused `MASS` would be a reskin, and
## `test_weapon_kinds_demand_different_bodies` names it.
##
## ## Why the attribute is the whole of the difference
##
## Nothing in the use loop compares one kind's number against another's to decide
## which is better. It pays the demand's attribute. That is the whole
## differentiation: a high-mastery maul is a strong body, a high-mastery needle is
## a precise body, and no amount of the first turns a body into the second.

const MASS := &"mass"
const LEVERAGE := &"leverage"
const SPEED := &"speed"
const BALANCE := &"balance"
const BRACE := &"brace"
const PRECISION := &"precision"

## Demand id -> the base attribute its practice pays. Six entries over four
## attributes: two demands share an attribute on purpose (MASS and LEVERAGE are
## both "physique to move something"), and what separates them is which weapon
## asks and which counter blunts — never how big the number is. A demand is a
## BODY PROBLEM, not a magnitude.
const PAYING_ATTRIBUTE := {
	MASS: Stat.PHYSIQUE,
	LEVERAGE: Stat.PHYSIQUE,
	SPEED: Stat.AGILITY,
	BALANCE: Stat.AGILITY,
	BRACE: Stat.WILL,
	PRECISION: Stat.APTITUDE,
}

## Every demand, in the order a screen renders them. Fixed and small so a read
## model can publish the full axis rather than only the kinds a body holds.
const ALL: Array[StringName] = [MASS, LEVERAGE, SPEED, BALANCE, BRACE, PRECISION]

## The module's own stat ids for the demands. Named here rather than in
## `contracts/stat.gd`: no module may add to another module's constant, and a
## module-owned stat needs exactly one owner.
const DEMAND_STATS := {
	MASS: &"body_demand_mass",
	LEVERAGE: &"body_demand_leverage",
	SPEED: &"body_demand_speed",
	BALANCE: &"body_demand_balance",
	BRACE: &"body_demand_brace",
	PRECISION: &"body_demand_precision",
}


## The published stat id for one demand, or `&""` when the demand is unknown —
## which is what a hand-edited `.tres` earns, and it reads as "no demand trained"
## rather than as a crash.
static func stat_of(demand: StringName) -> StringName:
	return DEMAND_STATS.get(demand, &"")


## The base attribute one demand's practice pays. Empty for an unknown demand.
static func attribute_of(demand: StringName) -> StringName:
	return PAYING_ATTRIBUTE.get(demand, &"")


## A body's trained level in one demand, read off the module's own stat id.
static func trained(actor: Actor, demand: StringName) -> float:
	var id := stat_of(demand)
	return 0.0 if id == &"" or actor == null else actor.stats.get_base(id)


## Add `amount` to a demand's own trained stat. A non-positive amount writes
## nothing, so a missed strike can never train a body downwards.
static func credit_demand(actor: Actor, demand: StringName, amount: float) -> void:
	var id := stat_of(demand)
	if id == &"" or actor == null or amount <= 0.0 or not is_finite(amount):
		return
	actor.stats.set_base(id, actor.stats.get_base(id) + amount)


## Add `amount` to the base attribute a demand pays. Same guard as the demand
## stat: the attribute is a body, and a body is not trained by a negative press.
static func credit_attribute(actor: Actor, demand: StringName, amount: float) -> void:
	var attribute := attribute_of(demand)
	if attribute == &"" or actor == null or amount <= 0.0 or not is_finite(amount):
		return
	actor.stats.set_base(attribute, actor.stats.get_base(attribute) + amount)
