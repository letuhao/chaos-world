extends TestCase

## Why the doctrine program still owes a base-stat verb: NO item channel grants
## one, and this file is the proof rather than the claim.
##
## It asserts behaviour that belongs to `items`, and it lives here on purpose: the
## finding's whole point is that a doctrine board has no verb to call when a row
## says "+1 physique". It belongs in `game/tests/modules/items/` beside the code it
## reads, and it is here only because session `bg-elixir` holds that directory.
## Move it when that path frees.
##
## The claim being pinned, DEF-0321, was WRONG when first written. It said a
## permanent base-attribute grant is a *learned* item delivered by
## `ItemUse._apply_learned`. That function does read base gains and call `set_base`
## (`items/item_use.gd:179-186`) — but the only category whose activation is
## `LEARNED` is `TECHNIQUE` (`ItemActivation.BY_CATEGORY`), and `_apply_learned`
## sends `TECHNIQUE` to `_study_technique` on its FIRST line
## (`items/item_use.gd:177`). `_study_technique` calls an injected `Callable` and
## writes no stat. So the `set_base` branch is unreachable: dead code that reads
## exactly like the missing feature.
##
## The other candidate refuses on purpose. `items/item_use.gd:136-140`: a consumable
## whose only content is a base attribute "restores nothing and applies nothing"
## (ADR 0001) — its gains ride along in the payload and it returns
## `REASON_NO_EFFECT`. That is correct for a consumable, which is spent and gone; it
## just means a consumable cannot be the delivery for a permanent grant either.
##
## So the two halves of the finding: a permanent base-attribute grant has NO shipped
## path, and a transient one goes through `Actor.add_status` as always. The first is
## why a sanctioned base-stat verb is owed rather than already present.


## A def whose only content is a FLAT gain on a real base attribute.
func _base_stat_def(category: StringName, stat_id: StringName, value: float) -> ItemDef:
	var def := ItemDef.new()
	def.id = &"test_base_stat_channel"
	def.category = category
	def.rarity = &"common"
	def.realm = &"qi_refining"
	def.fixed_modifiers = [
		{
			"target_type": OptionTarget.STAT,
			"op": &"FLAT",
			"target_id": stat_id,
			"value": value,
		}
	]
	return def


func _hero() -> Actor:
	var actor := Actor.new(&"channel_reader", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	return actor


func test_technique_is_the_only_category_that_activates_as_learned() -> void:
	# The premise the dead branch rests on. If this ever stops being true, the
	# `set_base` branch in `_apply_learned` becomes reachable and the finding below
	# is wrong — so this fails first and says why.
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


func test_a_learned_item_with_a_base_stat_goes_to_the_technique_seam_and_writes_nothing() -> void:
	var actor := _hero()
	var before := actor.stats.get_base(Stat.PHYSIQUE)
	var def := _base_stat_def(ItemCategory.TECHNIQUE, Stat.PHYSIQUE, 3.0)
	# No delivery seam is installed, so the technique channel refuses with `no_seam`.
	# That refusal IS the point: the base gain is never applied on the way past.
	var result := ItemUse.apply(actor, def, ItemInstance.new(def.id, &"channel_probe"))
	assert_eq(bool(result.get("ok", false)), false, "an uninstalled technique seam refuses")
	assert_eq(
		actor.stats.get_base(Stat.PHYSIQUE),
		before,
		"a learned item wrote a base attribute, so _apply_learned's set_base branch is NOT dead"
	)


func test_a_consumable_whose_only_content_is_a_base_attribute_refuses_and_still_reports() -> void:
	var actor := _hero()
	var before := actor.stats.get_base(Stat.PHYSIQUE)
	var def := _base_stat_def(ItemCategory.CONSUMABLE, Stat.PHYSIQUE, 3.0)
	var result := ItemUse.apply(actor, def, ItemInstance.new(def.id, &"channel_probe"))
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
	assert_eq(
		float((result.get("stat_gains", {}) as Dictionary).get(String(Stat.PHYSIQUE), 0.0)),
		3.0,
		"and the refused gain is still reported in the payload"
	)


func test_neither_item_channel_moves_a_base_attribute() -> void:
	# The finding in one assertion, over every category that reaches an apply path.
	# EQUIPPED and CRAFTED are refused by `apply` outright, so the only two channels
	# that could deliver are covered above; this names the conclusion so a future
	# channel added without thought trips here.
	for raw in [ItemCategory.CONSUMABLE, ItemCategory.TECHNIQUE]:
		var category := StringName(raw)
		var actor := _hero()
		var before := actor.stats.get_base(Stat.PHYSIQUE)
		var def := _base_stat_def(category, Stat.PHYSIQUE, 3.0)
		ItemUse.apply(actor, def, ItemInstance.new(def.id, &"channel_probe"))
		assert_eq(
			actor.stats.get_base(Stat.PHYSIQUE),
			before,
			(
				"%s delivered a permanent base attribute, so a sanctioned verb is now redundant"
				% category
			)
		)
