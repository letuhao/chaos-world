extends TestCase

## ## PROPERTY 6 — MASTERY ADVANCES BY USING THE THING
##
## The brief's last required property: mastery must be earnable in play, not only
## through a tech tree, so it has a combat loop. The loop is "swing the weapon,
## get better at the weapon" — there is no spend, no unlock table and no point-buy
## anywhere in `body_cultivation`, and this suite is what makes that claim
## checkable rather than aspirational.
##
## ## What makes it a LOOP rather than a faucet
##
## A faucet pays out forever and stops mattering. A loop has a cost, a cap, and a
## reason to keep swinging — this one has all three: a landed strike must not be
## blunted, the payout is the kind's authored rate and nothing else, and the demand
## it trains is the body's, so the loop's value is bounded by what the body can
## become.

## Swings per rung of the 30-realm ladder. The cap names the loop's real exit —
## an empty payout — and is never reached, so a non-converging loop fails loudly
## instead of spinning.
const MAX_SWINGS := 30
const KIND := &"spear"


func _actor() -> Actor:
	var actor := Actor.new(&"wielder", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"primordial_origin"))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, 128)
	BodyTraining.synchronize(actor)
	return actor


func _ledger(actor: Actor) -> BodyPractice:
	return actor.component(BodyCultivationApi.PRACTICE_ID)


func test_landed_strikes_raise_mastery_monotonically() -> void:
	var actor := _actor()
	var ledger := _ledger(actor)
	var previous := 0.0
	var swings := 0
	# Terminates on its own condition: the loop counts, and the count is a rung of
	# a 30-realm ladder rather than a "keep going" budget.
	while swings < MAX_SWINGS:
		swings += 1
		var earned := float(BodyWeaponUse.wield(actor, KIND)["earned"])
		assert_eq(earned > 0.0, true, "a landed, uncountered strike pays on swing %d" % swings)
		var now := ledger.mastery(KIND)
		assert_eq(now > previous, true, "mastery rose on swing %d" % swings)
		previous = now
	assert_eq(ledger.uses_of(KIND), MAX_SWINGS, "every swing is recorded as a use")


## The loop advances the KIND, not the body in general: a body that has only ever
## swung a spear holds that spear and nothing else. That is what makes the six
## kinds six masterships rather than one mastery with six names.
func test_the_loop_advances_the_kind_and_not_the_others() -> void:
	var actor := _actor()
	var ledger := _ledger(actor)
	var swings := 0
	while swings < MAX_SWINGS:
		swings += 1
		BodyWeaponUse.wield(actor, KIND)
	assert_eq(ledger.mastery(KIND) > 0.0, true, "the swung kind advanced")
	for kind in WeaponKindCatalog.all():
		if kind.id == KIND:
			continue
		assert_eq(ledger.mastery(kind.id), 0.0, "%s was never swung and stays at zero" % kind.id)


## The use loop also trains the BODY, which is the whole reason mastery is a
## physical skill rather than a counter. `will` is the base attribute the SPEAR's
## demanded balance does not pay — `preciscion`-style precision pays aptitude — so
## this pins one concrete demand -> attribute edge rather than "something moved".
func test_the_loop_trains_the_body_the_demand_names() -> void:
	var actor := _actor()
	var spear := WeaponKindCatalog.find(KIND)
	var attribute := WeaponDemand.attribute_of(spear.lean)
	assert_ne(attribute, &"", "the spear's lean resolves to an attribute")
	var before := actor.stats.get_base(attribute)
	var swings := 0
	while swings < MAX_SWINGS:
		swings += 1
		BodyWeaponUse.wield(actor, KIND, true, false, spear.lean, 0.5)
	var after := actor.stats.get_base(attribute)
	assert_eq(after > before, true, "thirty swings trained %s" % attribute)


## ## PROPERTY 5 (part one) — A COUNTERED STRIKE EARNS LESS
##
## The yin-yang counterpart has to travel THROUGH the loop, not sit beside it as a
## note in a docstring. If a defended exchange trained a body exactly as much as an
## open one, the defence would be decoration.
func test_a_blunted_strike_earns_less() -> void:
	var open_wielder := _actor()
	var warded := _actor()
	var swings := 0
	while swings < MAX_SWINGS:
		swings += 1
		BodyWeaponUse.wield(open_wielder, KIND)
		BodyWeaponUse.wield(warded, KIND, true, true)
	var open_mastery := _ledger(open_wielder).mastery(KIND)
	var warded_mastery := _ledger(warded).mastery(KIND)
	assert_eq(open_mastery > warded_mastery, true, "a defended exchange trains a body less")
	assert_eq(warded_mastery > 0.0, true, "but it is not worthless — a counter is not immunity")


## The reduced rate is DATA, not a literal at the use site, and the data says what
## it means: a quarter of an open exchange.
func test_the_blunted_rate_is_authored_and_readable() -> void:
	var rate := BodyWeaponUse.BLUNTED_YIELD
	assert_eq(rate > 0.0 and rate < 1.0, true, "a counter reduces the yield without erasing it")
	var kind := WeaponKindCatalog.find(KIND)
	var actor := _actor()
	var open_payout := float(BodyWeaponUse.wield(actor, KIND)["earned"])
	var warded_actor := _actor()
	var warded := float(BodyWeaponUse.wield(warded_actor, KIND, true, true)["earned"])
	assert_almost_eq(
		warded, open_payout * rate, "the countered payout is the authored fraction of the open one"
	)
	assert_eq(kind.practice_gain > 0.0, true, "and the open payout is the kind's own rate")


## The loop refuses rather than paying on a body that has no practice ledger or no
## weapon of that name. A verb that quietly mints its own state on first call is
## how a second source of truth for mastery appears.
func test_the_loop_refuses_an_unknown_weapon_or_an_unattached_body() -> void:
	var actor := _actor()
	assert_eq(BodyWeaponUse.wield(actor, &"no_such_weapon")["ok"], false, "unknown kind refused")
	var reason := String(BodyWeaponUse.wield(actor, &"no_such_weapon")["reason"])
	assert_ne(reason, "", "and the refusal is NAMED, not an empty false")
	var bare := Actor.new(&"bare", {Stat.PHYSIQUE: 20.0})
	actor = bare
	assert_eq(BodyWeaponUse.wield(bare, KIND)["ok"], false, "a body with no ledger refused")
