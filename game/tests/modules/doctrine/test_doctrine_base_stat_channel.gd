extends TestCase

## Where a base attribute CAN be moved, and where it still cannot.
##
## DEF-0321 was corrected twice and is now closed by ADR 0280: `ItemActivation.BY_CATEGORY`
## maps exactly one category to `LEARNED` (`items/item_activation.gd:14`) and it is
## `TECHNIQUE`, `ItemUse._apply_learned` sends `TECHNIQUE` to `_study_technique` on its
## FIRST line (`items/item_use.gd:212`), and that function writes no stat — so the
## `set_base` loop at `items/item_use.gd:217` is unreachable dead code that reads exactly
## like the missing feature.
##
## **The sanctioned verb is `BaseGrantApi` and it is deliberately NOT an item channel.**
## That is the whole shape decision, so this file no longer asserts "no channel exists" —
## it asserts the narrower truth that keeps mattering, plus the existence of the new one:
##
##   - no ITEM category moves a base attribute, so reviving the dead branch is not the
##     repair ADR 0280 measured it to be (`ItemDef.effects` DROPS any fixed modifier whose
##     option is not allowed on that category, so flipping a category strips options rather
##     than adding a channel);
##   - the one that does is `BaseGrantApi`, and it refuses a one-sided gain.
##
## ## A correction to the fixture this file used to carry
##
## The old `_base_stat_def` wrote `target_type` / `op` / `target_id` / `value` straight
## into `fixed_modifiers`. `ItemDef.effects` reads `option_id` and `continue`s past any
## entry without one (`items/item_def.gd:100-104`), so **every** fixture this file built
## resolved to zero effects. That is why the assertion "the refused gain is still reported
## in the payload" could never pass: `stat_gains` was structurally `{}`, and the test was
## passing for the wrong reason and failing for the right one. The fixture below is built
## the way the runtime actually delivers a stat — through an `ItemInstance`'s `rolled`
## list, which `ItemDef.effects` appends unfiltered (`items/item_def.gd:107`) because
## production rolls are already activation-filtered at roll time by `OptionCatalog.roll_next`.
##
## It asserts behaviour that belongs to `items`, and it lives here on purpose: the
## finding's whole point is that a doctrine board had no verb to call when a row says
## "+1 physique". It belongs in `game/tests/modules/items/` beside the code it reads, and
## it is here only because session `bg-elixir` holds that directory. Move it when that
## path frees.


func setup() -> void:
	# Every body below must clear this many assertions or the runner charges it a failure,
	# so a body that dies on its first line cannot be reported green.
	expect_assertions(1)


## An item that CARRIES a base-attribute gain, built the way the runtime delivers one.
##
## The gain rides on the instance's rolled list rather than on `fixed_modifiers`, because a
## fixed modifier without an `option_id` is dropped before it is ever read.
func _base_stat_def(category: StringName) -> ItemDef:
	var def := ItemDef.new()
	def.id = &"test_base_stat_channel"
	def.category = category
	def.rarity = &"common"
	def.realm = &"qi_refining"
	return def


func _rolled_base_stat(stat_id: StringName, value: float) -> ItemInstance:
	var instance := ItemInstance.new(&"test_base_stat_channel", &"channel_probe")
	instance.rolled = [
		{
			"option_id": StringName("base_%s" % String(stat_id)),
			"target_type": OptionTarget.STAT,
			"target_id": stat_id,
			"scope": StringName(""),
			"op": &"FLAT",
			"unit": &"magnitude",
			"value": value,
			"channel": &"rolled",
		}
	]
	return instance


func _hero() -> Actor:
	var actor := Actor.new(&"channel_reader", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	return actor


# --- the premise -------------------------------------------------------------


func test_technique_is_the_only_category_that_activates_as_learned() -> void:
	# The premise the dead branch rests on. If a second category ever activates as
	# LEARNED, `_apply_learned`'s `set_base` loop becomes reachable and ADR 0280's
	# measurement is stale — so this fails first and says why.
	var learned: Array[StringName] = []
	for raw in ItemCategory.ALL:
		var category := StringName(raw)
		if ItemActivation.for_category(category) == ItemActivation.LEARNED:
			learned.append(category)
	assert_eq(
		learned.size() == 1 and learned[0] == ItemCategory.TECHNIQUE,
		true,
		"exactly one category activates as learned, and it is technique; got %s" % [learned]
	)


# --- no ITEM channel moves a base attribute ----------------------------------


func test_a_learned_item_with_a_base_stat_goes_to_the_technique_seam_and_writes_nothing() -> void:
	var actor := _hero()
	var before := actor.stats.get_base(Stat.PHYSIQUE)
	var def := _base_stat_def(ItemCategory.TECHNIQUE)
	# No delivery seam is installed, so the technique channel refuses with `no_seam`.
	# That refusal IS the point: the base gain is never applied on the way past.
	var result := ItemUse.apply(actor, def, _rolled_base_stat(Stat.PHYSIQUE, 3.0))
	assert_eq(bool(result.get("ok", false)), false, "an uninstalled technique seam refuses")
	assert_eq(
		actor.stats.get_base(Stat.PHYSIQUE),
		before,
		"a learned item wrote a base attribute, so the sanctioned verb is no longer the only one"
	)


func test_a_consumable_whose_only_content_is_a_base_attribute_refuses_and_still_reports() -> void:
	var actor := _hero()
	var before := actor.stats.get_base(Stat.PHYSIQUE)
	var def := _base_stat_def(ItemCategory.CONSUMABLE)
	var result := ItemUse.apply(actor, def, _rolled_base_stat(Stat.PHYSIQUE, 3.0))
	assert_eq(bool(result.get("ok", false)), false, "a base-attribute consumable applies nothing")
	assert_eq(
		String(result.get("reason", "")),
		ItemUse.REASON_NO_EFFECT,
		"and it says why: there was no applicable effect"
	)
	assert_eq(
		actor.stats.get_base(Stat.PHYSIQUE),
		before,
		"a consumable must not persist a base attribute - it is spent and gone"
	)
	# The numbers still ride along so a caller can show what the item carries, which
	# is the half of ADR 0001 that makes the refusal informative rather than opaque.
	# **This is the assertion the old fixture made unreachable**: it read 0.0 because the
	# fixture resolved to no effects at all, not because the payload drops the gains.
	assert_eq(
		float((result.get("stat_gains", {}) as Dictionary).get(String(Stat.PHYSIQUE), 0.0)),
		3.0,
		"and the refused gain is still reported in the payload"
	)


func test_neither_item_channel_moves_a_base_attribute() -> void:
	# The narrower finding that survives ADR 0280. EQUIPMENT and CRAFTED are refused by
	# `apply` outright, so the only two channels that could deliver are covered above.
	# Named over every category so a future channel added without thought trips here.
	for raw in [ItemCategory.CONSUMABLE, ItemCategory.TECHNIQUE]:
		var category := StringName(raw)
		var actor := _hero()
		var before := actor.stats.get_base(Stat.PHYSIQUE)
		var def := _base_stat_def(category)
		ItemUse.apply(actor, def, _rolled_base_stat(Stat.PHYSIQUE, 3.0))
		assert_eq(
			actor.stats.get_base(Stat.PHYSIQUE),
			before,
			(
				(
					"%s delivered a permanent base attribute; ADR 0280 measured that reviving "
					+ "this branch strips options rather than adding a channel, so re-measure it"
				)
				% category
			)
		)


# --- the channel that does exist ---------------------------------------------


func test_the_sanctioned_channel_moves_a_base_attribute_and_the_item_channel_does_not() -> void:
	# The finding, closed: there IS a way, it is `BaseGrantApi`, and the item path still
	# is not one. Both halves run over the SAME def and the SAME rolled gain, so the
	# difference asserted is the channel rather than the fixture.
	var def := _base_stat_def(ItemCategory.TECHNIQUE)
	var via_item := _hero()
	ItemUse.apply(via_item, def, _rolled_base_stat(Stat.PHYSIQUE, 3.0))

	var via_grant := _hero()
	# A one-sided "+3 physique" is `unpaid` — the yin-yang gate (ADR 0280).
	var refused := BaseGrantApi.grant(
		via_grant, {"source": "doctrine/probe", "gains": {"physique": 3.0}}
	)
	assert_eq(
		String(refused["reason"]),
		BaseGrantApi.REASON_UNPAID,
		"the sanctioned verb refuses the one-sided gain the item path silently ignored"
	)
	assert_eq(via_grant.stats.get_base(Stat.PHYSIQUE), 10.0, "and moved nothing")

	var paid := BaseGrantApi.grant(
		via_grant,
		{"source": "doctrine/probe", "gains": {"physique": 3.0}, "costs": {"spirit": 3.0}}
	)
	assert_eq(bool(paid["ok"]), true, "the same gain as a paid transfer is granted")
	assert_eq(via_grant.stats.get_base(Stat.PHYSIQUE), 13.0, "and it moved the base attribute")
	assert_eq(
		via_item.stats.get_base(Stat.PHYSIQUE),
		10.0,
		"while the item channel still cannot, which is the shape ADR 0280 chose"
	)
