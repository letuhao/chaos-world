extends TestCase

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

## ADR 0165, ruling Q2: `cultivate` stays FREE, and this suite is the ruling made
## executable.
##
## The finding (DEF-0214) was real and the re-measurement confirmed it: `QiTraining.
## cultivate` (`training.gd:31-59`) spends no qi, no clock and no item. It computes
## `gain`, calls `dantian.fill`, refines quality and adds to progress. The comment at
## `training.gd:44-48` argues about a DEADLOCK from refusing the action, never about
## its price — which is the tell that it was never priced on purpose.
##
## Two coherent answers existed. Price the sitting, or say the gate is the price.
## The corpus settled it, and the answer is the second one:
##
## - **`dantian_fill_required` is 1.0 on all 30 seeds.** The gate demands a FULL
##   reservoir at every single realm. `cultivate` is the only verb that fills one, so
##   the free verb IS the thing the gate is priced in — the player pays in sittings
##   and the ladder's own `progress_required` ladder (100 -> 2900) is the meter.
## - **The priced verbs are the ladder's other two halves, and both are reachable.**
##   `train_channel` walks the channel gate spending `training_item` (30 authored
##   elixirs, `76348490` made the walk selectable), and `attempt_breakthrough`
##   spends `breakthrough_item`. `qi_gate_ladder_findings` grades all three roles
##   resolve in content, so the price is not theoretical.
## - **Pricing the sitting would break the deadlock the comment documents.** A
##   `cultivate` that spent qi would need the reservoir drawn down to charge for it,
##   and the entry gate wants that same reservoir FULL. The two demands cancel and
##   the path deadlocks — the exact failure the comment records having already
##   happened once.
##
## So: the free verb is the DESIGN, the gate is the price, and this suite asserts
## both halves so neither can be quietly broken. The rejected alternative was a
## qi-denominated cost; it is recorded here because it is the obvious "fix" a future
## agent will reach for, and it is the one that deadlocks.


## The finding itself, asserted so a future change to it is deliberate: `cultivate`
## spends nothing. An inventory snapshot and a pool reading either side of a sitting.
func test_cultivate_spends_no_item_and_no_qi() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	assert_ne(seed, null, "the standing realm has a seed")
	var state := actor.path(QiPath.PATH_ID)
	var pool := actor.resource(QiStats.QI)
	# `attach` mounts the reservoir FULL (`api.gd:_ensure_resources`), and `fill`
	# clamps at capacity, so a sitting on a full core would be a no-op on the pool
	# and the assertion below would be vacuous. Drain it first — the interesting
	# claim is that a sitting ADDS qi and spends none.
	pool.current = 0.0
	var inventory := ItemsApi.inventory(actor)
	var items_before := _item_fingerprint(inventory)
	var qi_before := pool.current
	var progress_before := state.progress

	assert_eq(QiCultivationApi.cultivate(actor, 50.0), true, "a sitting is accepted")

	assert_eq(
		_item_fingerprint(ItemsApi.inventory(actor)),
		items_before,
		"cultivate consumes no item: the ladder's price is the elixir and the pill"
	)
	assert_eq(
		pool.current > qi_before,
		true,
		"and it does not spend qi either — it FILLS the reservoir the gate demands full"
	)
	assert_eq(state.progress > progress_before, true, "progress is the meter it pays in")


## The gate is the price, and this is the half that makes it true: every one of the
## 30 realms demands a full reservoir, so the free verb cannot be skipped.
func test_every_realm_demands_a_full_reservoir() -> void:
	var ladder := RealmDefaults.ladder()
	var checked := 0
	for realm in ladder.realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(
			seed.dantian_fill_required,
			1.0,
			(
				"%s does not demand a full dantian; a free sitting would stop being the price"
				% realm.id
			)
		)
		checked += 1
	assert_eq(checked, 30, "and it graded the whole ladder")


## The other two halves of the price exist and are authored, so "the gate is the
## price" is not resting on the fill term alone.
func test_the_ladder_still_carries_its_two_priced_verbs() -> void:
	var ladder := RealmDefaults.ladder()
	var checked := 0
	for realm in ladder.realms():
		var seed := QiRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		for role in [&"breakthrough_item", &"training_item", &"recovery_item"]:
			var item_id: StringName = seed.get(role)
			assert_ne(
				item_id,
				&"",
				(
					"%s authors no %s, so one of the priced verbs has nothing to spend"
					% [realm.id, role]
				)
			)
			assert_eq(
				ResourceLoader.exists("res://data/items/consumable/%s.tres" % item_id),
				true,
				"%s resolves in content" % item_id
			)
		checked += 1
	assert_eq(checked, 30, "and it graded the whole ladder")


## The rejected alternative, recorded as an executable warning. This is the shape a
## future agent reaches for when it reads DEF-0214 and decides to "fix" the free
## verb, and it is the shape that deadlocks: the gate wants the reservoir FULL while
## the verb would be charging out of it.
##
## What is asserted is the conflict, not a re-implementation: an empty reservoir
## fails the fill gate, so a verb that had drained the actor could never have
## satisfied the gate it was being paid for.
func test_a_qi_denominated_cost_would_deadlock_against_the_fill_gate() -> void:
	var actor := Probe.fresh_actor(&"qi_refining")
	var seed := QiRealmSeed.for_realm(&"qi_refining")
	var dantian := QiAccess.dantian(actor)
	var pool := actor.resource(QiStats.QI)
	# Start drained, which is the state a qi-priced `cultivate` would leave behind.
	pool.current = 0.0
	assert_eq(dantian.ratio(actor) < seed.dantian_fill_required, true, "a drained core")
	# Sitting then fills it — the only way to reach the gate — which is exactly why
	# the price cannot be paid out of the same reservoir.
	assert_eq(QiCultivationApi.cultivate(actor, 500.0), true, "a sitting refills it")
	assert_eq(dantian.ratio(actor) >= seed.dantian_fill_required, true, "and meets the gate")


## Bounded snapshot: the inventory's own stacks, walked once. Returns a comparable
## string so the assertion above is about CONTENT, not object identity.
##
## `stacks()` is the inventory's own fixed-length accessor, so the count is
## snapshotted BEFORE the loop and no body appends to the container it walks
## (INC-0002).
func _item_fingerprint(inventory: Inventory) -> String:
	var parts: Array[String] = []
	var stacks := inventory.stacks()
	for stack in stacks:
		parts.append("%s:%d" % [stack.def_id, stack.quantity])
	return ",".join(parts)
