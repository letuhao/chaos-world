extends TestCase

## Two prices the body action layer had collapsed into one (ADR 0141, which fixed
## the same collapse on the mind path).
##
## **A torn channel was repaired with the CHANNEL ELIXIR.** `strengthen` consumed
## `strengthening_item` and then repaired, so `recovery_item` — the third role every
## realm authors for exactly this wound, and the item whose crafting recipe every
## realm ships (ADR 0031) — was demanded by nothing a player could reach.
## `recover` and the facade's `recover_next` were correct and unreachable at a price
## anybody pays.
##
## Delegating rather than reimplementing is what keeps one repair at one price. The
## body half of that delegation buys something the old injury branch never did: the
## acupoint jammed on the torn channel by the same deviation is freed too, because
## `recover` is (ADR 0031) the only action that clears a blockage.
##
## Driven through the FACADE only — `BodyTraining` is the module's internals, and
## this is a defect a player reaches through `BodyCultivationApi` (ADR 0043).
##
## Every expected value is read from the seed, the inventory, or the actor's own
## state. Nothing is a pasted literal.

const PATH := BodyPath.PATH_ID


func _actor_at(realm_id: StringName) -> Actor:
	var actor := Actor.new(&"body_pricing_hero", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(PATH, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, 64)
	BodyTraining.synchronize(actor)
	return actor


func _first_realm() -> StringName:
	return RealmDefaults.ladder().realms()[0].id


func _seed(actor: Actor) -> BodyRealmSeed:
	return BodyRealmSeed.for_realm(actor.path(PATH).rank_id)


## One unit of a REAL authored item, resolved through the content tree. A fabricated
## stub would prove the consume arithmetic and nothing about the seed's content.
func _stock(actor: Actor, def_id: StringName) -> void:
	var def := Crafting.resolve(def_id)
	assert_ne(def, null, "authored item %s exists" % def_id)
	ItemsApi.inventory(actor).add(def, 1)


func _held(actor: Actor, def_id: StringName) -> int:
	return ItemsApi.inventory(actor).count(def_id)


## The FIRST channel `strengthen_next` will offer, read from the seed's own candidate
## list, so the fixture and the verb agree on which channel is being repaired. Bounded
## by that fixed list; the loop appends nothing.
func _first_candidate(actor: Actor) -> StringName:
	var seed := _seed(actor)
	if seed == null:
		return &""
	if not seed.channel_training.is_empty():
		return seed.channel_training[0]
	return seed.required_meridians[0] if not seed.required_meridians.is_empty() else &""


## Every channel `strengthen_next` could offer, torn. The facade publishes no
## per-channel verb on this path — `strengthen_next` walks its own candidate list and
## returns on the first success — so tearing ONE channel proves nothing: the walk
## simply moves to the next healthy one and succeeds with the channel elixir. The
## negatives have to take the whole candidate list down.
##
## Bounded by the actor's own network, a fixed list this loop does not grow.
func _tear_every_candidate(actor: Actor) -> void:
	for channel in actor.meridians.get_all_meridians():
		actor.meridians.damage_meridian(channel.id)


func _jam_first_huyet(actor: Actor, meridian_id: StringName) -> StringName:
	for point in BodyCultivationApi.acupoints(actor):
		if AcupointDefaults.meridian_of(point.id) == meridian_id:
			point.block()
			return point.id
	return &""


# --- The load-bearing assertion ---------------------------------------------


## A tear is repaired by the realm's RECOVERY elixir, and the channel elixir is not
## touched: two different consumables with two different jobs, and before this the
## wrong one paid for the wound.
##
## Counts, not the return value: `strengthen_next` returns true only after its consume
## succeeds, so a guard that repaired while spending the wrong item still returned
## true. Only the two counts separate them.
func test_a_tear_is_repaired_by_the_recovery_elixir_and_not_the_channel_elixir() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	assert_ne(
		seed.recovery_item,
		seed.strengthening_item,
		"the two roles are different consumables, so the price is distinguishable"
	)
	var torn := _first_candidate(actor)
	actor.meridians.damage_meridian(torn)
	_stock(actor, seed.strengthening_item)
	_stock(actor, seed.recovery_item)
	var elixirs := _held(actor, seed.strengthening_item)
	var recoveries := _held(actor, seed.recovery_item)
	assert_eq(elixirs, 1, "one channel elixir in hand")
	assert_eq(recoveries, 1, "one recovery elixir in hand")
	assert_eq(actor.meridians.get_meridian(torn).is_injured(), true, "and the tear is real")
	assert_eq(BodyCultivationApi.strengthen_next(actor), true, "the tear is repaired")
	assert_eq(actor.meridians.get_meridian(torn).is_injured(), false, "and it is closed")
	assert_eq(
		_held(actor, seed.recovery_item),
		recoveries - 1,
		"the realm's recovery elixir paid for it (ADR 0031)"
	)
	assert_eq(
		_held(actor, seed.strengthening_item),
		elixirs,
		"and the channel elixir is untouched: a repair is not one training step"
	)


## The negative that names the defect. Holding the WRONG consumable — and nothing
## else — must not repair a tear. Before the fix this press succeeded and spent it,
## which is how a player could close a torn channel without ever touching the item the
## realm authors for that wound.
##
## EVERY candidate is torn, not one: `strengthen_next` walks past a torn channel to the
## next healthy one, so a single tear would have been repaired by the channel elixir on
## the following candidate and this would have measured nothing.
func test_the_channel_elixir_alone_cannot_repair_a_channel() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var torn := _first_candidate(actor)
	_tear_every_candidate(actor)
	_stock(actor, seed.strengthening_item)
	assert_eq(
		BodyCultivationApi.strengthen_next(actor),
		false,
		"a tear refuses without the realm's recovery elixir"
	)
	assert_eq(actor.meridians.get_meridian(torn).is_injured(), true, "so the wound is still open")
	assert_eq(
		_held(actor, seed.strengthening_item),
		1,
		"and the refused press spent nothing: the refusal is before the consume"
	)


## A refusal that closed the wound for free would be worse than the defect, so the
## negative is measured on the wound and not only on the return value.
func test_a_refused_repair_spends_nothing_and_closes_nothing() -> void:
	var actor := _actor_at(_first_realm())
	var torn := _first_candidate(actor)
	_tear_every_candidate(actor)
	assert_eq(BodyCultivationApi.strengthen_next(actor), false, "an empty pack refuses")
	assert_eq(actor.meridians.get_meridian(torn).is_injured(), true, "wound still open")
	assert_eq(_held(actor, _seed(actor).strengthening_item), 0, "nothing spent")
	assert_eq(_held(actor, _seed(actor).recovery_item), 0, "nothing spent")


## The other half of the split, so this suite cannot pass by making repairs free: a
## HEALTHY channel still costs the channel elixir, and a healthy press never touches
## the recovery one. Two consumables, two jobs.
func test_a_healthy_channel_is_still_paid_for_with_the_channel_elixir() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var fresh := _first_candidate(actor)
	assert_eq(actor.meridians.get_meridian(fresh).is_injured(), false, "the channel is healthy")
	_stock(actor, seed.strengthening_item)
	_stock(actor, seed.recovery_item)
	var elixirs := _held(actor, seed.strengthening_item)
	var recoveries := _held(actor, seed.recovery_item)
	assert_eq(BodyCultivationApi.strengthen_next(actor), true, "a healthy press trains")
	assert_eq(
		_held(actor, seed.strengthening_item), elixirs - 1, "and the channel elixir paid for it"
	)
	assert_eq(
		_held(actor, seed.recovery_item),
		recoveries,
		"while the recovery elixir is for the wound, not the ladder"
	)


## `strengthen` DELEGATES a tear rather than reimplementing the repair, so the two
## routes are one act at one price. A second copy of the consume is exactly how the
## two prices drifted apart the first time; proven by closing the wound through one
## route and finding nothing left for the other to charge for.
func test_the_repair_is_one_act_at_one_price_through_either_route() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var torn := _first_candidate(actor)
	actor.meridians.damage_meridian(torn)
	_stock(actor, seed.recovery_item)
	var recoveries := _held(actor, seed.recovery_item)
	assert_eq(BodyCultivationApi.strengthen_next(actor), true, "closed through training")
	assert_eq(
		BodyCultivationApi.recover_next(actor),
		false,
		"and the recovery verb finds no second wound to charge for"
	)
	assert_eq(
		_held(actor, seed.recovery_item),
		recoveries - 1,
		"so exactly one elixir paid for the one repair"
	)


## What delegation BUYS on this path, and the old injury branch never had: the acupoint
## the same deviation jammed on the torn channel is freed by the same press. ADR 0031
## makes `recover` the ONLY action that clears a blockage, so a repair priced
## separately but implemented inline would have left the jam standing behind a wound
## the player had just paid to close.
func test_the_delegated_repair_also_frees_the_huyet_the_deviation_jammed() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var torn := _first_candidate(actor)
	var point_id := _jam_first_huyet(actor, torn)
	assert_ne(point_id, &"", "a acupoint on this meridian exists")
	actor.meridians.damage_meridian(torn)
	_stock(actor, seed.recovery_item)
	assert_eq(BodyCultivationApi.strengthen_next(actor), true, "the press is accepted")
	assert_eq(actor.meridians.get_meridian(torn).is_injured(), false, "the tear is closed")
	var freed := false
	for point in BodyCultivationApi.acupoints(actor):
		if point.id == point_id:
			freed = not point.blocked
	assert_eq(freed, true, "and the jam on the same meridian went with it, at one price")
	assert_eq(_held(actor, seed.recovery_item), 0, "one elixir, one deviation undone")


## The split is not a first-realm accident: every realm on the ladder authors BOTH
## roles and they are different ids, so the price is distinguishable everywhere a
## deviation can be recovered at. (ADR 0031 makes the second clause load-bearing: a
## realm with no `recovery_item` is unrecoverable after a deviation.)
##
## Bounded by `ladder().realms()`, a fixed content list; the loop appends nothing.
func test_every_realm_distinguishes_the_recovery_elixir_from_the_channel_elixir() -> void:
	var realms := 0
	for def in RealmDefaults.ladder().realms():
		var seed := BodyRealmSeed.for_realm(def.id)
		if seed == null:
			continue
		realms += 1
		assert_ne(seed.recovery_item, &"", "recovery elixir authored for %s" % def.id)
		assert_ne(seed.strengthening_item, &"", "channel elixir authored for %s" % def.id)
		assert_ne(
			seed.recovery_item,
			seed.strengthening_item,
			"the two roles differ at %s, or the repair has no price of its own" % def.id
		)
	assert_eq(realms > 1, true, "the ladder really was audited, not one realm")


## The whole point of the price: a deviation is recoverable AT THE SAME REALM by a
## player holding the realm's recovery elixir, through the facade, with no higher
## realm and no module internals. Without it the tear is permanent here, so this is
## also the proof that the wrong price was a soft-lock dressed as a shortcut.
func test_a_tear_is_recoverable_at_the_same_realm_for_the_recovery_elixir_price() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var torn := _first_candidate(actor)
	actor.meridians.damage_meridian(torn)
	# The tear blocks the gate and the gate says so by name, so the player knows the
	# item is the thing they are missing (ADR 0034: a gate and its preview are the
	# same wording).
	var unmet: Array = BodyAdvancement.preview(actor).get("unmet", [])
	var named := false
	for message in unmet:
		if String(message).contains("Damaged channels"):
			named = true
	assert_eq(named, true, "the wound is named on the gate: %s" % ", ".join(unmet))
	_stock(actor, seed.recovery_item)
	assert_eq(BodyCultivationApi.recover_next(actor), true, "the facade verb closes it")
	assert_eq(actor.meridians.get_meridian(torn).is_injured(), false, "wound closed")
	assert_eq(_held(actor, seed.recovery_item), 0, "and the recovery elixir paid for it")


## The two prices must not collapse into one number by accident. `recovery_item` and
## `strengthening_item` are separate ids at every realm (above), the repair spends
## only the first and the climb only the second — so a future edit that merges the two
## consumes, or drops one, cannot pass both halves of this suite.
func test_the_repair_and_the_climb_are_paid_for_by_different_elixirs() -> void:
	var actor := _actor_at(_first_realm())
	var seed := _seed(actor)
	var channel_id := _first_candidate(actor)
	_stock(actor, seed.strengthening_item)
	_stock(actor, seed.recovery_item)
	# Tear, repair, then climb: two presses, two consumables, one of each.
	actor.meridians.damage_meridian(channel_id)
	assert_eq(BodyCultivationApi.strengthen_next(actor), true, "the repair")
	assert_eq(BodyCultivationApi.strengthen_next(actor), true, "then the climb")
	assert_eq(_held(actor, seed.recovery_item), 0, "the recovery elixir paid the repair")
	assert_eq(_held(actor, seed.strengthening_item), 0, "the channel elixir paid the climb")
