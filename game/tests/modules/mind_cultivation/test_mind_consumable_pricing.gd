extends TestCase

## Two prices the Mind action layer had collapsed into one (ADR 0141/0142).
##
## **A burned channel was repaired with the CHANNEL ELIXIR.** `train_channel`
## consumed `training_item` and then repaired, so `recovery_item` — the fourth role
## every realm authors for exactly this wound (ADR 0031) — was demanded by nothing
## a player could reach. `recover` and the facade's `recover_next` were correct and
## unreachable at a price anybody pays, and no suite noticed because every fixture
## stocked the wrong item and asserted only that the channel healed.
##
## **The resonance milestone could be pressed forever.** `strengthen_anchor` had no
## guard, so presses 2..N each spent an elixir for an `improve_stability(0.1)` that
## no gate can fail on: `is_stable` reads `>= 0.5`, a committed anchor is created at
## exactly 0.5, and the next commit REPLACES the world and discards the stability
## with it. ADR 0115 had already made the reinforcement flag the milestone itself, so
## "already done" was defined — nothing read it.
##
## Every expected value is read from the seed, the inventory, or the code under
## test's own state. Nothing is a pasted literal, and no assertion calls the helper
## whose behaviour it is checking.

## The ladder index that commits the first anchor, and the realm standing in it when
## the milestone becomes payable: `strengthen_anchor` refuses below
## `Breakthrough.IMMORTAL_REALM_THRESHOLD`, so a fixture standing in a mortal realm
## would be measuring its own refusal (the mistake ADR 0115's cost section records).
const COMMIT := MindAnchor.COMMIT_SEED

## Presses a player holding spare elixirs would make. The defect is not one extra
## press, it is that the press keeps succeeding, so the bound has to exceed one.
const REPEAT_PRESSES := 5


func _actor_at(realm_id: StringName) -> Actor:
	var actor := Actor.new(
		&"pricing_hero", {Stat.COMPREHENSION: 40.0, MindStats.SEA_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, realm_id))
	actor.meridians.unlock_for_realm(realm_id)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 64)
	MindTraining.synchronize(actor)
	return actor


## An actor in the realm that COMMITS an anchor, standing in it, with the anchor
## committed and trialled but unpaid for — the pre-state a player legally holds one
## realm after the commit. Derived from the policy rather than a hard-coded index.
func _committed(realm_index: int = COMMIT) -> Actor:
	var actor := _actor_at(_realm_at(realm_index).id)
	MindAnchor.commit(actor, realm_index)
	assert_eq(actor.inside_world.anchor_created, true, "the commit really did create it")
	return actor


func _realm_at(index: int) -> RealmDef:
	return RealmDefaults.ladder().realms()[index]


func _seed(actor: Actor) -> MindRealmSeed:
	return MindRealmSeed.for_realm(actor.path(MindPath.PATH_ID).rank_id)


## One unit of a REAL authored item, resolved through the content tree. A fabricated
## stub would prove the consume arithmetic and nothing about the seed's content.
func _stock(actor: Actor, def_id: StringName) -> void:
	var def := Crafting.resolve(def_id)
	assert_ne(def, null, "authored item %s exists" % def_id)
	ItemsApi.inventory(actor).add(def, 1)


func _held(actor: Actor, def_id: StringName) -> int:
	return ItemsApi.inventory(actor).count(def_id)


# --- Defect 1: the price of a repair ----------------------------------------


## The load-bearing assertion. A burn is repaired by the realm's RECOVERY elixir,
## and the channel elixir is not touched: the two are different consumables with
## different jobs, and before this the wrong one paid for the wound.
##
## Counts, not the return value: `train_channel` returns true only after its consume
## succeeds, so a guard that repaired while spending the wrong item still returns
## true. Only the two counts separate them.
func test_a_burn_is_repaired_by_the_recovery_elixir_and_not_the_channel_elixir() -> void:
	var actor := _actor_at(_realm_at(0).id)
	var seed := _seed(actor)
	assert_ne(
		seed.recovery_item,
		seed.training_item,
		"the two roles are different consumables, so the price is distinguishable"
	)
	actor.meridians.damage_meridian(_channel(actor))
	_stock(actor, seed.training_item)
	_stock(actor, seed.recovery_item)
	var elixirs := _held(actor, seed.training_item)
	var recoveries := _held(actor, seed.recovery_item)
	assert_eq(elixirs, 1, "one channel elixir in hand")
	assert_eq(recoveries, 1, "one recovery elixir in hand")
	var burned := _channel(actor)
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), true, "and the burn is real")
	assert_eq(MindTraining.train_channel(actor, burned), true, "the burn is repaired")
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
## it, which is how a player could fix a burned channel without ever touching the
## item the realm authors for that wound.
func test_the_channel_elixir_alone_cannot_repair_a_channel() -> void:
	var actor := _actor_at(_realm_at(0).id)
	var seed := _seed(actor)
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	# Exactly the elixir `test_a_burn_is_repaired_by_the_recovery_elixir_...` proves
	# is the wrong one, and no recovery elixir at all.
	_stock(actor, seed.training_item)
	assert_eq(
		MindTraining.train_channel(actor, burned),
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
	var actor := _actor_at(_realm_at(0).id)
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	assert_eq(MindTraining.train_channel(actor, burned), false, "an empty pack refuses")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), true, "wound still open")
	assert_eq(_held(actor, _seed(actor).training_item), 0, "nothing spent")
	assert_eq(_held(actor, _seed(actor).recovery_item), 0, "nothing spent")


## The other half of the split, so this suite cannot pass by making repairs free: a
## HEALTHY channel still costs the channel elixir, and a healthy press never touches
## the recovery one. Two consumables, two jobs.
func test_a_healthy_channel_is_still_paid_for_with_the_channel_elixir() -> void:
	var actor := _actor_at(_realm_at(0).id)
	var seed := _seed(actor)
	var fresh := _channel(actor)
	assert_eq(actor.meridians.get_meridian(fresh).is_injured(), false, "the channel is healthy")
	_stock(actor, seed.training_item)
	_stock(actor, seed.recovery_item)
	var elixirs := _held(actor, seed.training_item)
	var recoveries := _held(actor, seed.recovery_item)
	assert_eq(MindTraining.train_channel(actor, fresh), true, "a healthy press trains")
	assert_eq(_held(actor, seed.training_item), elixirs - 1, "and the channel elixir paid for it")
	assert_eq(
		_held(actor, seed.recovery_item),
		recoveries,
		"while the recovery elixir is for the wound, not the ladder"
	)


## `train_channel` DELEGATES a burn rather than reimplementing the repair, so the two
## routes are one act at one price. If the delegation were replaced by a second copy
## of the consume, the two prices could drift apart again with nothing to catch it —
## which is how they drifted the first time. Proven by closing the wound through one
## route and finding nothing left for the other to charge for.
func test_the_repair_is_one_act_at_one_price_through_either_route() -> void:
	var actor := _actor_at(_realm_at(0).id)
	var seed := _seed(actor)
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	_stock(actor, seed.recovery_item)
	var recoveries := _held(actor, seed.recovery_item)
	assert_eq(MindCultivationApi.train_channel(actor, burned), true, "closed through training")
	assert_eq(
		MindCultivationApi.recover_next(actor),
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
func test_every_realm_distinguishes_the_recovery_elixir_from_the_channel_elixir() -> void:
	var realms := 0
	for def in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(def.id)
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
## realm and no module internals. Without the recovery elixir the burn is permanent
## here, so this is also the proof that the wrong price was a soft-lock dressed as a
## shortcut.
func test_a_burn_is_recoverable_at_the_same_realm_for_the_recovery_elixir_price() -> void:
	var actor := _actor_at(_realm_at(0).id)
	var seed := _seed(actor)
	var burned := _channel(actor)
	actor.meridians.damage_meridian(burned)
	assert_eq(MindCultivationApi.preview(actor).get("ready"), false, "and the gate is shut")
	_stock(actor, seed.recovery_item)
	assert_eq(MindCultivationApi.recover_next(actor), true, "the facade verb closes it")
	assert_eq(actor.meridians.get_meridian(burned).is_injured(), false, "wound closed")
	assert_eq(_held(actor, seed.recovery_item), 0, "and the recovery elixir paid for it")


## A channel this actor's realm has actually unlocked, so the fixture never measures
## a refusal for "no such channel". Derived from the live network, not an id literal.
func _channel(actor: Actor) -> StringName:
	for def in MeridianDefaults.all():
		if actor.meridians.get_meridian(def.id) != null:
			return def.id
	return &""


# --- Defect 2: the milestone is paid once -----------------------------------


## What the milestone is actually worth, derived rather than asserted: the commit
## already leaves the world stable, so the stability a press adds cannot be what a
## gate reads. `is_stable` is core's own predicate and a committed anchor's stability
## is core's own constructor default — neither is a number this suite wrote down.
func test_a_committed_anchor_is_already_stable_before_the_milestone_is_paid() -> void:
	var actor := _committed()
	var world := actor.inside_world
	assert_eq(world.is_stable(), true, "the commit's world already passes `is_stable`")
	assert_almost_eq(
		world.stability,
		InsideWorld.new(world.tier).stability,
		"at core's own default for a fresh world, so the commit raises nothing"
	)
	assert_eq(
		world.anchor_strengthened,
		false,
		"so the clause the milestone unlocks is the paid flag, not the stability"
	)


## The first press pays: the elixir is spent, the flag is set, and the anchor gate
## the facade already publishes reads met with nothing outstanding. That gate is the
## answer the player can act on — a screen needs no new surface to explain a
## refusal, because the refusal and a paid milestone say the same thing.
func test_the_first_press_pays_and_opens_the_gate_the_facade_publishes() -> void:
	var actor := _committed()
	var seed := _seed(actor)
	var stage := MindAnchor.required_stage(_realm_at(COMMIT + 1).index)
	assert_eq(MindAnchor.stage_met(actor, stage), false, "the gate starts shut")
	assert_ne(
		String(MindAnchor.outstanding(actor, stage)),
		"",
		"and the shortfall is named, so the press is not a mystery"
	)
	_stock(actor, seed.training_item)
	var elixirs := _held(actor, seed.training_item)
	assert_eq(MindTraining.strengthen_anchor(actor), true, "the milestone is paid")
	assert_eq(
		_held(actor, seed.training_item),
		elixirs - 1,
		"and it cost the realm's channel elixir, which is the whole clause (ADR 0115)"
	)
	assert_eq(MindTraining.anchor_reinforced(actor), true, "the flag is set")
	assert_eq(MindAnchor.stage_met(actor, stage), true, "which is what opens the gate")
	assert_eq(MindAnchor.outstanding(actor, stage), "", "and leaves nothing outstanding")


## THE regression assertion for the ratchet. Before the guard, presses 2..N each
## returned true and each spent an elixir. Now the milestone is paid once, so the
## whole sequence costs exactly one elixir — and, separately, moves the stability
## exactly once. Both halves: a guard that stopped charging but kept inflating
## stability would pass the count alone.
##
## The pack holds an elixir PER PRESS, deliberately. With only one, presses 2..N
## refuse for want of a consumable and the assertions would pass with the guard
## deleted — which is exactly what the first mutation of this suite proved: 178/0
## with the guard removed. A refusal and a charge are different answers, so the
## fixture has to make the charge the only one it can give.
func test_pressing_the_milestone_again_costs_nothing_and_moves_nothing() -> void:
	var actor := _committed()
	var seed := _seed(actor)
	for _elixir in REPEAT_PRESSES:
		_stock(actor, seed.training_item)
	var elixirs := _held(actor, seed.training_item)
	assert_eq(elixirs, REPEAT_PRESSES, "one elixir per press is in hand")
	assert_eq(MindTraining.strengthen_anchor(actor), true, "the first press pays")
	var stability := actor.inside_world.stability
	for press in range(REPEAT_PRESSES - 1):
		assert_eq(
			MindTraining.strengthen_anchor(actor),
			false,
			"press %d of %d: the milestone is already paid" % [press + 2, REPEAT_PRESSES]
		)
	assert_eq(
		_held(actor, seed.training_item),
		elixirs - 1,
		"%d presses cost ONE elixir, not %d" % [REPEAT_PRESSES, REPEAT_PRESSES]
	)
	assert_eq(
		actor.inside_world.stability,
		stability,
		"and the stability the first press added is not a ratchet"
	)


## The stability the FIRST press adds is measured, not assumed, and it is the whole
## argument for refusing the rest: a tenth of a percent that the next commit
## discards. Read from the world's own before/after rather than written down.
func test_the_stability_the_first_press_adds_is_discarded_by_the_next_commit() -> void:
	var actor := _committed()
	var committed_stability := actor.inside_world.stability
	_stock(actor, _seed(actor).training_item)
	assert_eq(MindTraining.strengthen_anchor(actor), true, "paid")
	var gained := actor.inside_world.stability - committed_stability
	assert_eq(gained > 0.0, true, "so the press does move stability (%s)" % gained)
	# The next tier's commit replaces the world outright, so nothing carries over.
	MindAnchor.commit(actor, MindAnchor.COMMIT_POCKET)
	assert_eq(
		actor.inside_world.stability,
		InsideWorld.new(InsideWorld.POCKET).stability,
		"which starts from core's own default again, not from what was paid"
	)


## The guard is per ANCHOR, not a latch: the next tier commits a new anchor and the
## milestone is payable again. Without this the fix would have made the ladder
## unwalkable past R19 while every gate still demanded a fresh reinforcement — the
## soft-lock this suite exists to prevent, in the other direction.
func test_a_new_committed_anchor_is_payable_again() -> void:
	var actor := _committed()
	_stock(actor, _seed(actor).training_item)
	assert_eq(MindTraining.strengthen_anchor(actor), true, "the first anchor is paid")
	assert_eq(MindTraining.anchor_reinforced(actor), true, "and reported paid")
	MindAnchor.commit(actor, MindAnchor.COMMIT_POCKET)
	assert_eq(
		MindTraining.anchor_reinforced(actor),
		false,
		"the next tier's anchor is a different one and is unpaid"
	)
	# Standing in the realm that commits it, which is where the milestone is payable.
	actor.set_path(PathState.new(MindPath.PATH_ID, _realm_at(MindAnchor.COMMIT_POCKET).id))
	MindTraining.synchronize(actor)
	_stock(actor, _seed(actor).training_item)
	var elixirs := _held(actor, _seed(actor).training_item)
	assert_eq(MindTraining.strengthen_anchor(actor), true, "and payable again")
	assert_eq(
		_held(actor, _seed(actor).training_item),
		elixirs - 1,
		"so a second anchor is a second real payment, not a free repeat"
	)


## `anchor_reinforced` is the milestone's own "already done", published so a caller
## does not restate `inside_world.anchor_strengthened` and drift from the guard. It
## must agree with the flag at both ends of the press and be false for an actor
## holding no anchor at all — a query that answered true for "no anchor" would let a
## caller suppress a milestone that is genuinely owed.
func test_the_published_predicate_agrees_with_the_flag_it_guards() -> void:
	var bare := _actor_at(_realm_at(0).id)
	assert_eq(MindTraining.anchor_reinforced(bare), false, "no anchor is never paid")
	var actor := _committed()
	assert_eq(
		MindTraining.anchor_reinforced(actor),
		actor.inside_world.anchor_strengthened,
		"unpaid after the commit"
	)
	_stock(actor, _seed(actor).training_item)
	assert_eq(MindTraining.strengthen_anchor(actor), true, "paid")
	assert_eq(
		MindTraining.anchor_reinforced(actor),
		actor.inside_world.anchor_strengthened,
		"paid after the press, so the two can never disagree"
	)
	assert_eq(MindTraining.anchor_reinforced(actor), true, "and it reads true")


## The refusal the player meets before the milestone is owed at all: below the
## Immortal tier, or with no anchor committed. Unchanged by this fix and pinned
## anyway, because it is the same pre-consume validation a second copy of it would
## skip — and a milestone that spends an elixir where there is nothing to reinforce
## is the same defect as one that spends a second elixir on the same anchor.
func test_the_milestone_refuses_before_it_is_owed_and_spends_nothing() -> void:
	var mortal := _actor_at(_realm_at(Breakthrough.IMMORTAL_REALM_THRESHOLD - 1).id)
	_stock(mortal, _seed(mortal).training_item)
	assert_eq(MindTraining.strengthen_anchor(mortal), false, "no anchor below the tier")
	assert_eq(
		_held(mortal, _seed(mortal).training_item),
		1,
		"and the realm's channel elixir survives the refusal"
	)
	var uncommitted := _actor_at(_realm_at(COMMIT).id)
	_stock(uncommitted, _seed(uncommitted).training_item)
	assert_eq(MindTraining.strengthen_anchor(uncommitted), false, "no anchor committed yet")
	assert_eq(
		_held(uncommitted, _seed(uncommitted).training_item),
		1,
		"and its channel elixir survives too (R19 is a legitimate no-op)"
	)


## The two prices must not collapse into one number by accident. `recovery_item` and
## `training_item` are separate ids at every realm (above), the repair spends only
## the first and the climb only the second — so a future edit that merges the two
## consumes, or drops one, cannot pass both halves of this suite.
func test_the_repair_and_the_climb_are_paid_for_by_different_elixirs() -> void:
	var actor := _actor_at(_realm_at(0).id)
	var seed := _seed(actor)
	var channel_id := _channel(actor)
	_stock(actor, seed.training_item)
	_stock(actor, seed.recovery_item)
	# Burn, repair, then climb: two presses, two consumables, one of each.
	actor.meridians.damage_meridian(channel_id)
	assert_eq(MindTraining.train_channel(actor, channel_id), true, "the repair")
	assert_eq(MindTraining.train_channel(actor, channel_id), true, "then the climb")
	assert_eq(_held(actor, seed.recovery_item), 0, "the recovery elixir paid the repair")
	assert_eq(_held(actor, seed.training_item), 0, "the channel elixir paid the climb")
