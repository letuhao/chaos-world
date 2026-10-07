extends TestCase

## Two prices the qi action layer had collapsed into one (ADR 0141, which fixed the
## same collapse on the mind path).
##
## **A burned channel was repaired with the CHANNEL ELIXIR.** `train_channel`
## consumed `training_item` and then repaired, so `recovery_item` — the third role
## every realm authors for exactly this wound (ADR 0031) — was demanded by nothing
## a player could reach. `recover` and the facade's `recover_next` were correct and
## unreachable at a price anybody pays, and no suite noticed, because every fixture
## stocked the wrong item and asserted only that the channel healed.
##
## Driven through the FACADE only. `QiTraining` is the module's internals and the
## defect is one a player reaches through `QiCultivationApi`, so asserting on the
## action layer would prove the wrong surface (ADR 0043).
##
## Every expected value is read from the seed, the inventory, or the actor's own
## state. Nothing is a pasted literal.

const PATH := QiPath.PATH_ID


func _actor_at(realm_id: StringName) -> Actor:
	var actor := Actor.new(
		&"qi_pricing_hero", {Stat.COMPREHENSION: 40.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(PATH, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 64)
	QiTraining.synchronize(actor)
	return actor


func _first_realm() -> StringName:
	return RealmDefaults.ladder().realms()[0].id


func _seed(actor: Actor) -> QiRealmSeed:
	return QiRealmSeed.for_realm(actor.path(PATH).rank_id)


## One unit of a REAL authored item, resolved through the content tree. A fabricated
## stub would prove the consume arithmetic and nothing about the seed's content.
func _stock(actor: Actor, def_id: StringName) -> void:
	var def := Crafting.resolve(def_id)
	assert_ne(def, null, "authored item %s exists" % def_id)
	ItemsApi.inventory(actor).add(def, 1)


func _held(actor: Actor, def_id: StringName) -> int:
	return ItemsApi.inventory(actor).count(def_id)


## A channel this actor's realm has actually unlocked, so the fixture never measures
## a refusal for "no such channel". Derived from the live network, not an id literal.
## Bounded by `MeridianDefaults.all()`, a fixed content list this loop does not grow.
func _channel(actor: Actor) -> StringName:
	for def in MeridianDefaults.all():
		if actor.meridians.get_meridian(def.id) != null:
			return def.id
	return &""


# --- The load-bearing assertion ---------------------------------------------


## A burn is repaired by the realm's RECOVERY elixir, and the channel elixir is not
## touched: two different consumables with two different jobs, and before this the
## wrong one paid for the wound.
##
## Counts, not the return value: `train_channel` returns true only after its consume
## succeeds, so a guard that repaired while spending the wrong item still returned
## true. Only the two counts separate them.
func test_a_burn_is_repaired_by_the_recovery_elixir_and_not_the_channel_elixir() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	assert_ne(
		seed.recovery_item,
		seed.training_item,
		"the two roles are different consumables, so the price is distinguishable"
	)
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	_stock(actor, seed.training_item)
	_stock(actor, seed.recovery_item)
	var elixirs := _held(actor, seed.training_item)
	var recoveries := _held(actor, seed.recovery_item)
	assert_eq(elixirs, 1, "one channel elixir in hand")
	assert_eq(recoveries, 1, "one recovery elixir in hand")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), true, "and the burn is real")
	assert_eq(QiCultivationApi.train_channel(actor, burned), true, "the burn is repaired")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), false, "and it is closed")
	assert_eq(
		_held(actor, seed.recovery_item),
		recoveries - 1,
		"the realm's recovery elixir paid for it (ADR 0031)"
	)
	assert_eq(
		_held(actor, seed.training_item),
		elixirs,
		"and the channel elixir is untouched: a repair is not one training step"
	)


## The negative that names the defect. Holding the WRONG consumable — and nothing
## else — must not repair the burn. Before the fix this press succeeded and spent
## it, which is how a player could close a burned channel without ever touching the
## item the realm authors for that wound.
func test_the_channel_elixir_alone_cannot_repair_a_channel() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	# Exactly the elixir `test_a_burn_is_repaired_by_the_recovery_elixir_...` proves
	# is the wrong one, and no recovery elixir at all.
	_stock(actor, seed.training_item)
	assert_eq(
		QiCultivationApi.train_channel(actor, burned),
		false,
		"a burn refuses without the realm's recovery elixir"
	)
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), true, "so the wound is still open")
	assert_eq(
		_held(actor, seed.training_item),
		1,
		"and the refused press spent nothing: the refusal is before the consume"
	)


## A refusal that closed the wound for free would be worse than the defect, so the
## negative is measured on the wound and not only on the return value.
func test_a_refused_repair_spends_nothing_and_closes_nothing() -> void:
	var actor := _actor_at(_first_realm())
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	assert_eq(QiCultivationApi.train_channel(actor, burned), false, "an empty pack refuses")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), true, "wound still open")
	assert_eq(_held(actor, _seed(actor).training_item), 0, "nothing spent")
	assert_eq(_held(actor, _seed(actor).recovery_item), 0, "nothing spent")


## The other half of the split, so this suite cannot pass by making repairs free: a
## HEALTHY channel still costs the channel elixir, and a healthy press never touches
## the recovery one. Two consumables, two jobs.
func test_a_healthy_channel_is_still_paid_for_with_the_channel_elixir() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var fresh := _channel(actor)
	assert_eq(actor.meridians.get_meridian(fresh).is_injured(), false, "the channel is healthy")
	_stock(actor, seed.training_item)
	_stock(actor, seed.recovery_item)
	var elixirs := _held(actor, seed.training_item)
	var recoveries := _held(actor, seed.recovery_item)
	assert_eq(QiCultivationApi.train_channel(actor, fresh), true, "a healthy press trains")
	assert_eq(_held(actor, seed.training_item), elixirs - 1, "and the channel elixir paid for it")
	assert_eq(
		_held(actor, seed.recovery_item),
		recoveries,
		"while the recovery elixir is for the wound, not the ladder"
	)


## `train_channel` DELEGATES a burn rather than reimplementing the repair, so the two
## routes are one act at one price. A second copy of the consume is exactly how the
## two prices drifted apart the first time; proven by closing the wound through one
## route and finding nothing left for the other to charge for.
func test_the_repair_is_one_act_at_one_price_through_either_route() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	_stock(actor, seed.recovery_item)
	var recoveries := _held(actor, seed.recovery_item)
	assert_eq(QiCultivationApi.train_channel(actor, burned), true, "closed through training")
	assert_eq(
		QiCultivationApi.recover_next(actor),
		false,
		"and the recovery verb finds no second wound to charge for"
	)
	assert_eq(
		_held(actor, seed.recovery_item),
		recoveries - 1,
		"so exactly one elixir paid for the one repair"
	)


## The split is not a first-realm accident: every realm on the ladder authors BOTH
## roles and they are different ids, so the price is distinguishable everywhere a
## deviation can be recovered at. (ADR 0031 makes the second clause load-bearing: a
## realm with no `recovery_item` is unrecoverable after a deviation.)
##
## Bounded by `ladder().realms()`, a fixed content list; the loop appends nothing.
func test_every_realm_distinguishes_the_recovery_elixir_from_the_channel_elixir() -> void:
	var realms := 0
	for def in RealmDefaults.ladder().realms():
		var seed := QiRealmSeed.for_realm(def.id)
		if seed == null:
			continue
		realms += 1
		assert_ne(seed.recovery_item, &"", "recovery elixir authored for %s" % def.id)
		assert_ne(seed.training_item, &"", "channel elixir authored for %s" % def.id)
		assert_ne(
			seed.recovery_item,
			seed.training_item,
			"the two roles differ at %s, or the repair has no price of its own" % def.id
		)
	assert_eq(realms > 1, true, "the ladder really was audited, not one realm")


## The whole point of the price: a deviation is recoverable AT THE SAME REALM by a
## player holding the realm's recovery elixir, through the facade, with no higher
## realm and no module internals. Without it the burn is permanent here, so this is
## also the proof that the wrong price was a soft-lock dressed as a shortcut.
func test_a_burn_is_recoverable_at_the_same_realm_for_the_recovery_elixir_price() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	_stock(actor, seed.recovery_item)
	assert_eq(QiCultivationApi.recover_next(actor), true, "the facade verb closes it")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), false, "wound closed")
	assert_eq(_held(actor, seed.recovery_item), 0, "and the recovery elixir paid for it")


## The qi deviation also scars the dantian, and `recover` is the action that heals
## both. Delegating therefore means a Train press on a burn also undoes the scar —
## neither can lose ground — which is the same consequence ADR 0141 records for the
## mind path's clouded sea.
func test_the_delegated_repair_also_heals_the_scar_the_same_deviation_left() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var dantian := QiTestKit.dantian(actor)
	assert_ne(dantian, null, "the dantian is attached")
	dantian.damage(actor)
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	_stock(actor, seed.recovery_item)
	assert_eq(QiCultivationApi.train_channel(actor, burned), true, "the burn is handed to recover")
	assert_eq(dantian.injured, false, "and the scar went with it, at one price")
	assert_eq(_held(actor, seed.recovery_item), 0, "one elixir, one deviation undone")


## The two prices must not collapse into one number by accident. `recovery_item` and
## `training_item` are separate ids at every realm (above), the repair spends only
## the first and the climb only the second — so a future edit that merges the two
## consumes, or drops one, cannot pass both halves of this suite.
func test_the_repair_and_the_climb_are_paid_for_by_different_elixirs() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var channel_id := _channel(actor)
	_stock(actor, seed.training_item)
	_stock(actor, seed.recovery_item)
	# Burn, repair, then climb: two presses, two consumables, one of each.
	actor.meridians.damage_meridian(channel_id)
	assert_eq(QiCultivationApi.train_channel(actor, channel_id), true, "the repair")
	assert_eq(QiCultivationApi.train_channel(actor, channel_id), true, "then the climb")
	assert_eq(_held(actor, seed.recovery_item), 0, "the recovery elixir paid the repair")
	assert_eq(_held(actor, seed.training_item), 0, "the channel elixir paid the climb")
