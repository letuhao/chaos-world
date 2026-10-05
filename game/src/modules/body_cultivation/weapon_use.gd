class_name BodyWeaponUse
extends RefCounted

## The WEAPON half of the practice loop: land a strike, earn mastery.
##
## ## Mastery advances by USING the thing, never by a tech tree
##
## [method wield] is the only writer of weapon mastery. There is no spend, no
## unlock table and no `points` button: the loop is "swing the maul, get better at
## the maul", and the ledger it writes (`BodyPractice.demand_mastery`) is keyed by
## kind rather than by rank. A tech-tree route would have to invent a currency;
## this one only needs a fight.
##
## ## The loop pays BODY work, so it cannot become a second ladder
##
## Each landed strike pays two things: the demand's base attribute, resolved from
## the demand id, and nothing that reads a realm. So a R30 novice and a R1 veteran
## of the same kind pay and gain identically — the difference between them is
## everything ELSE the realm bought them, which is the separation the whole system
## is for.

## A landed but COUNTERED strike earns this fraction of an uncountered one. A
## rate constant of the practice, in the same spirit as `RealmRate` being a rate:
## it says how much one use counts, never how strong a thing from this realm is.
const BLUNTED_YIELD := 0.25


## One use of `kind_id` by `actor`. Returns `{ok, earned, mastery, uses, landed,
## blunted, reason}` — all primitives, so a read model may publish it whole.
##
## `countered` is the defender's side, supplied by whoever resolved the exchange:
## the combat module's read of whether a `WeaponCounter` defence matched the
## kind's demand. A caller with no opinion passes false and gets the full yield,
## because a loop nobody wired a counter into must still be earnable; the tests
## wire one deliberately, and `test_a_blunted_strike_earns_less` is what stops the
## reduced yield from being decorative.
##
## `demand_paid` names the demand the exchange actually exercised and defaults to
## the KIND's own. A spear answering a shield drill trains BALANCE, not reach —
## which is how a body learns a weapon it has not swung, and why the kind's own
## mastery need not be the one that grew.
static func wield(
	actor: Actor,
	kind_id: StringName,
	landed: bool = true,
	countered: bool = false,
	demand_paid: StringName = &"",
	demand_delta: float = 0.0
) -> Dictionary:
	var kind := WeaponKindCatalog.find(kind_id)
	var refusal := _refusal(actor, kind, kind_id)
	if not refusal.is_empty():
		return refusal
	var practice: BodyPractice = actor.component(BodyCultivationApi.PRACTICE_ID)
	var paid := demand_paid if demand_paid != &"" else kind.demand
	# The BODY WORK a landed strike does, and where it goes. `demand_delta` is the
	# amount and the KIND's own `demand_delta` the DEFAULT, because mastery is earned
	# by using the weapon: a swing nobody calls `wield` for is still a swing, so a
	# caller with no opinion about the exchange still has to leave the body different
	# from a body that never held the thing. Without a default here the only way to
	# train an attribute was to pass a number, and the default call paid nothing.
	var delta := demand_delta if demand_delta > 0.0 else kind.demand_delta
	# The demand STAT the kind trains is named by the kind; the demand the
	# exercise PAID is named by the exchange. Two different facts, and conflating
	# them is how a reskin sneaks in.
	WeaponDemand.credit_demand(actor, kind.demand, kind.practice_gain)
	var earned := practice.apply_use(kind_id, landed, countered, kind.practice_gain, BLUNTED_YIELD)
	if landed:
		# `delta` is the kind's RATE of body work per use, so it scales with what the
		# use was worth. Reading it raw made a greatsword's `demand_delta` and a spear's
		# the only thing separating them while the credit itself ignored practice_gain —
		# two numbers that were authored as different and composed to the same body.
		WeaponDemand.credit_attribute(actor, paid, delta * kind.practice_gain)
		WeaponDemand.credit_demand(actor, paid, earned)
	actor.mark_stats_dirty()
	return {
		"ok": true,
		"earned": earned,
		"mastery": practice.mastery(kind_id),
		"uses": practice.uses_of(kind_id),
		"landed": landed,
		"blunted": countered,
		"demand": String(paid),
		"reason": &"",
	}


## The whole demand train one landed strike pays, as `{stat, demand, attribute,
## amount}`. A caller reporting an exchange asks this rather than inventing a
## number, so the strike's body cost is authored once and two screens cannot
## disagree about what a spear costs the body.
static func demand_payment(
	kind_id: StringName, demand_paid: StringName, demand_delta: float
) -> Dictionary:
	var kind := WeaponKindCatalog.find(kind_id)
	if kind == null:
		return {}
	var paid := demand_paid if demand_paid != &"" else kind.demand
	return {
		"stat": String(WeaponDemand.stat_of(paid)),
		"demand": String(paid),
		"attribute": String(WeaponDemand.attribute_of(paid)),
		"amount": demand_delta,
	}


## Whether `counter_id` answers `kind_id`, read through the one defence table.
## The use loop's caller asks this rather than restating the matchup, which is
## what lets a kind's counter travel into the loop without a second copy.
static func answered_by(kind_id: StringName, counter_id: StringName) -> bool:
	var kind := WeaponKindCatalog.find(kind_id)
	if kind == null:
		return false
	return WeaponCounter.blunts(counter_id).has(kind.demand)


static func _refusal(actor: Actor, kind: WeaponKindDef, _kind_id: StringName) -> Dictionary:
	var out := {
		"ok": false,
		"earned": 0.0,
		"mastery": 0.0,
		"uses": 0,
		"landed": false,
		"blunted": false,
		"demand": &"",
		"reason": &"",
	}
	if actor == null:
		out["reason"] = "no actor"
		return out
	if kind == null:
		out["reason"] = "unknown weapon kind"
		return out
	if actor.component(BodyCultivationApi.PRACTICE_ID) == null:
		out["reason"] = "no practice ledger"
		return out
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		out["reason"] = "no body path"
		return out
	if maxi(0, RealmDefaults.ladder().index_of(state.rank_id)) < kind.min_realm_index:
		out["reason"] = "realm too shallow for this weapon"
		return out
	return {}
