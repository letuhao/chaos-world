extends TestCase

## AUDIT PROBE (MUTATION-a1 / a2). `item_workbench_app.gd:_world_store()` returns
## `SaveStore.new()` on EVERY call, and `_ready` calls it for `install_store("soul")` and
## `install_store("anchor")` while handing `SaveStore.new()` DIRECT instances to
## `SoulApi.set_store` / `AnchorApi.set_store`. The docblock above `_world_store` claims
## "One instance, shared, never one per module".
##
## The economy keys were fixed for exactly this by ADR 0165 (`EconomyBoot._store_for` reads
## `SaveApi.store_for(key)`). The soul and the anchors were not.
##
## Driven through the SHIPPED `SeamHarness`, so this answers the production boot.

var _harness: SeamHarness
var _app: ItemWorkbenchApp


func setup() -> void:
	SaveApi.reset_clock()
	_harness = SeamHarness.mount_new()
	_app = _harness.app as ItemWorkbenchApp


func teardown() -> void:
	if _app != null and _app.actor() != null:
		_app.actor().resources.clear()
	_harness = null
	_app = null
	SaveApi.reset_clock()


## Does the ACTOR payload still carry a soul mirror? If it does, the split is state
## duplication; if it does not, a soul damage is lost outright.
func test_where_does_the_soul_live_in_the_written_envelope() -> void:
	if _app == null or _app.actor() == null:
		return
	var live := _app.actor()
	SoulApi.attach(live)
	AnchorApi.attach(live)
	SoulApi.damage(live, 20, "audit")

	var envelope := SaveStore.restore().get("envelope", {}) as Dictionary
	var world := envelope.get("world", {}) as Dictionary
	var actor_payload := envelope.get("actor", {}) as Dictionary
	var module_data := actor_payload.get("module_data", {}) as Dictionary

	print("MUTATION-a1 world.soul=%s" % str(world.get("soul", {})))
	print("MUTATION-a1 actor.module_data keys=%s" % str(module_data.keys()))
	print("MUTATION-a1 actor soul mirror=%s" % str(module_data.get("soul_state", {})))
	print("MUTATION-a1 actor anchor mirror=%s" % str(module_data.get("anchor_state", {})))

	assert_eq(
		int(SoulApi.soul(live).get("integrity", -1)),
		80,
		"MUTATION-a1 sanity: the module did damage the soul to 80"
	)
	assert_eq(
		int((world.get("soul", {}) as Dictionary).get("integrity", -1)),
		80,
		"MUTATION-a1: envelope.world.soul must carry the module's own integrity"
	)


## THE PLAYER-VISIBLE ONE: damage a soul, let the autosave land, restart the app, and read
## the soul the boot gives back.
func test_a_damaged_soul_survives_a_restart_in_production_boot() -> void:
	if _app == null or _app.actor() == null:
		return
	var live := _app.actor()
	SoulApi.attach(live)
	AnchorApi.attach(live)
	SoulApi.damage(live, 20, "audit")
	SaveApi.persist(live, "standard")

	var before := int(SoulApi.soul(live).get("integrity", -1))

	# Restart: a brand new composition root, exactly as a relaunch does.
	_app = null
	_harness = null
	var second := SeamHarness.mount_new()
	if second == null or second.app == null:
		return
	var reborn := (second.app as ItemWorkbenchApp).actor()
	if reborn == null:
		return
	SoulApi.attach(reborn)
	var after := int(SoulApi.soul(reborn).get("integrity", -1))
	print("MUTATION-a2 soul integrity before save=%s after restart=%s" % [str(before), str(after)])

	assert_eq(before, 80, "sanity: the soul was damaged before the save")
	assert_eq(
		after,
		80,
		"MUTATION-a2: a damaged soul must be the soul the next session reads"
	)