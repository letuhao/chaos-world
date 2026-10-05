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
##
## The modifier names an `option_id`, not inline target fields: `ItemDef.effects()`
## resolves every entry through `OptionCatalog.fixed_effect(option_id, value)`, so a
## synthetic `{target_type, op, target_id, value}` dictionary is silently ignored and
## the def resolves to NO effects at all. `base_physique` is the real registered option
## — a FLAT on `physique` with `unit: magnitude`, which is the only shape that means
## anything here.
func _base_stat_def(category: StringName, stat_id: StringName, value: float) -> ItemDef:
	var def := ItemDef.new()
	def.id = &"test_base_stat_channel"
	def.category = category
	def.rarity = &"common"
	def.realm = &"qi_refining"
	def.fixed_modifiers = [{"option_id": StringName("base_%s" % stat_id), "value": value}]
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


func test_a_base_attribute_option_cannot_even_be_attached_to_a_consumable() -> void:
	# The stronger half, measured rather than assumed. `base_physique` declares
	# `categories: ["equipment", "technique"]`, so `activations_for` never yields
	# CONSUMED and `ItemDef.effects()` drops the modifier before any use path sees it.
	# That means `ItemUse._apply_consumed`'s base-gain refusal is unreachable by
	# CONSTRUCTION, not merely untriggered: a consumable cannot carry the content that
	# would trip it. Two independent reasons, either sufficient.
	var catalog := OptionCatalog.instance()
	assert_eq(
		catalog.allows_activation(&"base_physique", ItemActivation.CONSUMED),
		false,
		"a base-attribute option is attachable to a consumable, so the refusal below is the only guard"
	)
	assert_eq(
		catalog.allows_activation(&"base_physique", ItemActivation.LEARNED),
		true,
		"and it IS attachable as learned, which is exactly why the dead branch matters"
	)

	var actor := _hero()
	var before := actor.stats.get_base(Stat.PHYSIQUE)
	var def := _base_stat_def(ItemCategory.CONSUMABLE, Stat.PHYSIQUE, 3.0)
	var result := ItemUse.apply(actor, def, ItemInstance.new(def.id, &"channel_probe"))
	assert_eq(bool(result.get("ok", false)), false, "a consumable carrying nothing applies nothing")
	assert_eq(
		actor.stats.get_base(Stat.PHYSIQUE),
		before,
		"and a base attribute is never persisted through it - it is spent and gone"
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
