extends TestCase

## The quick-use bar: six slots, each bound to one item id, and one verb that spends
## the bound item. Moved here from `app/consumable_system.gd`, which ADR 0056 forbids
## and DEF-0098 recorded as owed.
##
## ## What these cases are worth
##
## The prototype's only consumer was its own test, so a green suite here proves the
## class exists rather than that the game reaches it. That is a real limit and it is
## not papered over: there is no bar in any scene, no input mapping that spends a slot
## and no panel that draws one. What the suite does establish is that the feature is
## now *reachable and correctly shaped* for whoever wires it — behind a facade, with
## ids persisted rather than definitions, and with no second copy of the inventory.
## The second of those is what `test_quick_use_is_not_a_second_inventory.gd` holds.
##
## ## Why there is no `reset()`
##
## The prototype exposed `reset()` "for test isolation", which put a test concern in a
## production surface. The suite object is constructed once and `setup()` runs before
## every case, so building the actor in `setup()` gives each case its own bar and the
## method has no reason to exist.

const PILL := &"health_pill"

var _actor: Actor


func setup() -> void:
	_actor = Actor.new(&"quicker", {Stat.SPIRIT: 20.0, Stat.PHYSIQUE: 20.0})
	_actor.attach_core_resources()
	ItemsApi.attach(_actor)


## An actor carrying `count` of a restoring pill, built the way `items` builds one.
func _with_pills(count: int) -> Actor:
	var def := ItemDef.new()
	def.id = PILL
	def.category = ItemCategory.CONSUMABLE
	def.stackable = true
	def.max_stack = 99
	def.fixed_modifiers = [{"option_id": &"restore_health", "value": 20.0}]
	ItemsApi.inventory(_actor).add(def, count)
	return _actor


# --- The bar ----------------------------------------------------------------


func test_a_fresh_actor_has_six_empty_slots() -> void:
	assert_eq(QuickUseApi.SLOT_COUNT, 6, "the bar is six slots wide")
	var summary: Dictionary = QuickUseApi.summary(_actor)
	assert_eq(int(summary.get("slot_count", 0)), 6, "and the read model says so")
	assert_eq((summary["slots"] as Array).size(), 6, "with one row per slot")
	for row in summary["slots"]:
		assert_eq(String(row["def_id"]), "", "every slot starts empty")


func test_assigning_binds_an_id_and_reading_it_back_gives_that_id() -> void:
	var result: Dictionary = QuickUseApi.assign_slot(_actor, 2, PILL)
	assert_eq(bool(result.get("ok", false)), true, "the assign is accepted")
	assert_eq(int(result.get("slot", -1)), 2, "and names the slot it wrote")
	var rows: Array = QuickUseApi.summary(_actor)["slots"]
	assert_eq(String(rows[2]["def_id"]), String(PILL), "slot 2 reads back as the pill")
	assert_eq(String(rows[0]["def_id"]), "", "and slot 0 is untouched")


func test_an_out_of_range_slot_is_refused_and_writes_nothing() -> void:
	# The refusal vocabulary is load-bearing: a refused write is what keeps a panel
	# iterating a stale count from raising mid-frame.
	for bad in [-1, 99]:
		var result: Dictionary = QuickUseApi.assign_slot(_actor, bad, PILL)
		assert_eq(bool(result.get("ok", false)), false, "slot %d is refused" % bad)
		assert_eq(String(result.get("reason", "")), "invalid_slot", "reason invalid_slot")
	assert_eq(QuickUseApi.summary(_actor)["slots"].size(), 6, "and the bar is still six slots")


func test_an_empty_slot_is_refused_with_its_own_reason() -> void:
	var result: Dictionary = QuickUseApi.use_slot(_actor, 0)
	assert_eq(bool(result.get("ok", false)), false, "an unbound slot cannot be spent")
	assert_eq(String(result.get("reason", "")), "empty_slot", "reason empty_slot")


func test_clearing_a_slot_reports_what_it_held_and_keeps_the_item() -> void:
	_with_pills(3)
	QuickUseApi.assign_slot(_actor, 1, PILL)
	var result: Dictionary = QuickUseApi.clear_slot(_actor, 1)
	assert_eq(bool(result.get("ok", false)), true, "the slot is released")
	assert_eq(String(result.get("prev_def_id", "")), String(PILL), "and it reports the old id")
	assert_eq(
		ItemsApi.has_item(_actor, PILL),
		true,
		"while the pill is untouched in the bag -- a bar is not an inventory"
	)


func test_attach_is_idempotent() -> void:
	QuickUseApi.assign_slot(_actor, 0, PILL)
	QuickUseApi.attach(_actor)
	QuickUseApi.attach(_actor)
	assert_eq(
		String(QuickUseApi.summary(_actor)["slots"][0]["def_id"]),
		String(PILL),
		"re-attaching never replaces an existing bar with an empty one"
	)


# --- Spending ---------------------------------------------------------------


func test_using_a_slot_consumes_exactly_one_through_items() -> void:
	_with_pills(5)
	QuickUseApi.assign_slot(_actor, 0, PILL)
	var result: Dictionary = QuickUseApi.use_slot(_actor, 0)
	assert_eq(bool(result.get("ok", false)), true, "the spend is accepted")
	assert_eq(
		ItemsApi.inventory(_actor).count(PILL),
		4,
		"and `items` is down exactly one -- the bar moved nothing itself"
	)
	assert_eq(
		String(QuickUseApi.summary(_actor)["slots"][0]["def_id"]),
		String(PILL),
		"while the binding survives, because four are still carried"
	)


func test_a_depleted_stack_releases_its_own_slot() -> void:
	# A bar entry pointing at nothing can never fire again, so the last spend empties
	# the slot. Whether the last one is gone is `items`' fact to answer.
	_with_pills(1)
	QuickUseApi.assign_slot(_actor, 3, PILL)
	var result: Dictionary = QuickUseApi.use_slot(_actor, 3)
	assert_eq(bool(result.get("ok", false)), true, "the last pill is spent")
	assert_eq(
		String(QuickUseApi.summary(_actor)["slots"][3]["def_id"]),
		"",
		"and the slot that can no longer fire is released"
	)


func test_a_refused_spend_leaves_the_binding_alone() -> void:
	# `ItemsApi.use_item` is all-or-nothing, so a slot naming a pill the actor does not
	# carry spends nothing -- and must not empty itself either, or a player who picks
	# the pill up later would find the bar silently reset.
	QuickUseApi.assign_slot(_actor, 0, PILL)
	var result: Dictionary = QuickUseApi.use_slot(_actor, 0)
	assert_eq(bool(result.get("ok", false)), false, "nothing is carried, so nothing is spent")
	assert_eq(
		String(QuickUseApi.summary(_actor)["slots"][0]["def_id"]),
		String(PILL),
		"and the binding survives a refused spend"
	)


# --- Persistence ------------------------------------------------------------


func test_a_bar_persists_six_bare_ids_and_nothing_else() -> void:
	# ADR 0056: "persist ids, not definitions." This is the assertion that
	# distinguishes the salvage from the deleted `SkillSystem._save`, which wrote
	# `skill.to_dict()` -- the whole authored definition -- into the payload.
	_with_pills(5)
	QuickUseApi.assign_slot(_actor, 0, PILL)
	var data: Dictionary = _actor.get_module_data(QuickUseApi.STATE_KEY)
	assert_eq(data.keys(), ["slots"], "the payload carries exactly one key")
	var slots: Array = data["slots"]
	assert_eq(slots.size(), 6, "and that key is six rows")
	# Type before value: `String(some_dictionary)` is not a constructor in Godot 4.7,
	# so stringifying a row before checking it is a String RAISES and aborts the test
	# mid-function — which the runner reports as "incomplete", not as a failure. A
	# malformed payload has to fail here, cleanly, to be worth anything.
	for entry in slots:
		assert_eq(entry is String, true, "every row is a String and never a definition")
	assert_eq(String(slots[0]), String(PILL), "the slot persists as a bare id")
	assert_eq(String(slots[1]), "", "an unbound slot persists as empty")


func test_a_restored_actor_adopts_its_own_bar() -> void:
	# The property that makes the id persistence worth anything: a save written by one
	# actor comes back as the same bar on the next one.
	QuickUseApi.assign_slot(_actor, 4, PILL)
	var saved: Dictionary = _actor.get_module_data(QuickUseApi.STATE_KEY).duplicate(true)

	var restored := Actor.new(&"restored", {Stat.SPIRIT: 20.0})
	restored.attach_core_resources()
	ItemsApi.attach(restored)
	restored.set_module_data(QuickUseApi.STATE_KEY, saved)
	QuickUseApi.attach(restored)

	var rows: Array = QuickUseApi.summary(restored)["slots"]
	assert_eq(String(rows[4]["def_id"]), String(PILL), "slot 4 came back bound")
	assert_eq(String(rows[0]["def_id"]), "", "and the unbound slots are still unbound")


func test_a_restored_payload_shorter_than_the_bar_still_yields_six_slots() -> void:
	# A save written when the bar was a different width must restore what it can
	# rather than fail or grow the bar.
	var restored := Actor.new(&"short", {Stat.SPIRIT: 20.0})
	restored.attach_core_resources()
	restored.set_module_data(QuickUseApi.STATE_KEY, {"slots": [String(PILL)]})
	QuickUseApi.attach(restored)
	var rows: Array = QuickUseApi.summary(restored)["slots"]
	assert_eq(rows.size(), 6, "the bar is still six slots wide")
	assert_eq(String(rows[0]["def_id"]), String(PILL), "the one saved slot is restored")
	assert_eq(String(rows[5]["def_id"]), "", "and the rest are empty, not missing")


func test_an_actor_with_no_actor_reads_as_nothing_at_all() -> void:
	assert_eq(QuickUseApi.summary(null), {}, "no actor is an empty payload, not a broken one")
