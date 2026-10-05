extends TestCase

## DEF-0151: a `category = &"technique"` item used through `ItemsApi.use_item`
## produces a `CodexEntry`, and the seam that makes it possible refuses to guess.
##
## This suite drives the REAL item path — `ItemsApi.use_item`, the same call
## `item_workbench.gd:166` and `QuickUseApi.use_slot` make — rather than calling the
## techniques facade directly. A seam that only its own test can reach is the exact
## defect DEF-0151 records, so a test that learned through `TechniquesApi.learn`
## would assert the module still works rather than that a player can use a manual.
##
## ## The three states stay three
##
## Most of this file is about what delivery must NOT do. `ItemUse` DELIVERS,
## `CodexEntry` HOLDS, `TechniqueSlots` BINDS (ADR 0053), and a learned passive
## contributes NOTHING until it is explicitly equipped (ADR 0054). Collapsing any
## two of those means a single mis-click buys a permanent investment AND spends a
## limited slot, so each is asserted separately rather than as one summary.

const MORTAL := &"qi_refining"

## Real technique-legal pool options, so "the passive did not move" is a claim about
## an actual contribution rather than about an empty list (ADR 0054's 36 legal
## options, of which these are two).
const PASSIVE_OPTION := &"cult_qi_control"
const RESOURCE_OPTION := &"core_max_qi"

## `TechniqueCatalog` is process-wide, so a fixture id reused across suites would
## have its second def silently replace the first. A serial keeps them unique.
static var _serial: int = 0

## The delivery seam and the casting resolver are PROCESS-WIDE installs (see
## `technique_delivery.gd`). `run_tests.gd` calls `teardown` after every test
## precisely because a binding left behind leaks into the next suite, so both are
## torn down here and installed per-test by `_wire`.


func teardown() -> void:
	TechniqueDelivery.clear()
	TechniqueCasting.set_resolver(Callable())


func _wire() -> void:
	TechniqueDelivery.install(Callable(TechniqueDelivery, "bind_learner"))


## A hero with items, techniques and a qi path — the attach order `app/` uses, with
## `ItemsApi` FIRST because the delivery seam writes into a codex that
## `TechniquesApi.attach` creates.
func _hero(qi: float = 500.0) -> Actor:
	var actor := Actor.new(&"practitioner", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"qi", qi))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	# ADR 0140: learning charges the technique's OWN path's `progress`, and every
	# technique studied below is a qi one — so the budget lands on `QI` specifically.
	# `PathState.ALL[0]` is BODY, which this fixture never sets, so writing there
	# left the qi path at 0 and every study was refused `insufficient_progress`.
	# The budget is a fixture, not a balance claim; the price itself is asserted in
	# `test_technique_study_cost.gd`.
	actor.path(PathState.QI).progress = 100000.0
	ItemsApi.attach(actor)
	TechniquesApi.attach(actor)
	return actor


## A real `category = &"technique"` ITEM, carrying one real technique-legal option so
## it is genuinely a study manual and not an inert row.
func _manual(technique_id: StringName, option_id: StringName = &"base_comprehension") -> ItemDef:
	var def := ItemDef.new()
	def.id = technique_id
	def.display_name = "A Manual"
	def.category = ItemCategory.TECHNIQUE
	def.stackable = false
	def.rarity = &"magic"
	def.realm = MORTAL
	def.roll_spec = {"count": 1, "contexts": ["base"]}
	def.fixed_modifiers = [{"option_id": option_id, "value": 4.0}]
	return def


## The matching `TechniqueDef`, ungated so the tests exercise delivery rather than the
## realm ladder, and registered with the catalog so `definition(id)` resolves it the
## way a shipped `.tres` would.
##
## `fixture_id` takes the id rather than minting one here, because the ITEM carries
## that same id — it IS the delivery key — and two fixtures minted independently
## would drift apart.
func _technique(
	technique_id: StringName, active: bool = true, upkeep: Dictionary = {}
) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = technique_id
	def.display_name = "A Technique"
	def.grade = ItemGrade.MORTAL
	def.active = active
	def.path = PathState.QI
	def.upkeep = upkeep
	def.upkeep_interval = 60.0
	TechniqueCatalog.instance().register(def)
	return def


## A fixture id unique across every run of this suite. `TechniqueCatalog` is
## process-wide and registration is last-wins, so a reused id would have its second
## def silently replace the first — and because the delivery key IS the id, a
## collision would make one test study another test's technique.
func _fresh_id(label: String) -> StringName:
	_serial += 1
	return StringName("delivery_suite_%s_%d" % [label, _serial])


func _stock(actor: Actor, def: ItemDef) -> void:
	ItemsApi.inventory(actor).add(def, 1)


# --- The gap this file exists to close ---------------------------------------


## The facade's published methods, read from its own script.
##
## `TechniquesApi.new()` is the wrong door: every method on it is `static`, so
## instantiating yields a bare `RefCounted` whose script is NOT the api, and
## `get_script_method_list()` then returns nothing — every cap assertion below
## failed on an EMPTY list rather than on a count. Read the class's own script.
func _published_methods() -> Array[String]:
	var script: Script = load("res://src/modules/techniques/api.gd")
	var out: Array[String] = []
	for method in script.get_script_method_list():
		var method_name := String(method.get("name", ""))
		if method_name.begins_with("_") or out.has(method_name):
			continue
		out.append(method_name)
	return out


func test_using_a_real_technique_item_produces_a_codex_entry() -> void:
	var actor := _hero()
	var technique_id := _fresh_id("learn")
	_technique(technique_id)
	var manual := _manual(technique_id)
	_stock(actor, manual)
	_wire()

	assert_eq(TechniquesApi.codex(actor).count(), 0, "the codex starts empty")
	# The REAL item path, not the facade. This is the call a player's "use" makes.
	var result := ItemsApi.use_item(actor, technique_id)
	assert_eq(bool(result.get("ok")), true, "the manual is studied, not refused")
	# The right id, in the codex, as a `CodexEntry` — the second of three states.
	assert_eq(TechniquesApi.codex(actor).knows(technique_id), true, "the codex knows the technique")
	var entry := TechniquesApi.codex(actor).entry(technique_id)
	assert_ne(entry, null, "and it is a CodexEntry, not just a flag")
	assert_eq(entry.technique_id, technique_id, "carrying the technique's own id")
	assert_eq(entry.mastery_rung, 0, "delivery buys rung 0; mastery is a separate investment")
	# And the item is GONE: the item delivers and is consumed (ADR 0053).
	assert_eq(ItemsApi.inventory(actor).count(technique_id), 0, "the manual is consumed")
	assert_eq(ItemsApi.use_item(actor, technique_id).get("ok"), false, "and cannot be used twice")


func test_the_outcome_names_the_manual_that_delivered_the_technique() -> void:
	var actor := _hero()
	var technique_id := _fresh_id("from")
	_technique(technique_id)
	_stock(actor, _manual(technique_id))
	_wire()
	var result := ItemsApi.use_item(actor, technique_id)
	# So a caller reports "studied X" without re-deriving which manual it held.
	assert_eq(String(result.get("id")), String(technique_id), "the outcome names the technique")
	assert_eq(String(result.get("learned_from")), String(technique_id), "and the manual")


# --- The three states stay three (ADR 0053, ADR 0054) ------------------------


func test_learning_does_not_equip_and_does_not_touch_a_slot() -> void:
	var actor := _hero()
	var technique_id := _fresh_id("no_equip")
	_technique(technique_id)
	_stock(actor, _manual(technique_id))
	_wire()
	var learned_here := ItemsApi.use_item(actor, technique_id)
	assert_eq(
		bool(learned_here.get("ok")),
		true,
		"the manual is studied, not refused: '%s'" % String(learned_here.get("reason", ""))
	)

	# Delivery only HOLDS. The slot table is the third state and nothing here may
	# have touched it: a study that also spent a slot would make a mis-click cost
	# two irreversible things at once.
	assert_eq(TechniquesApi.codex(actor).knows(technique_id), true, "it is known")
	assert_eq(TechniquesApi.slots(actor).is_equipped(technique_id), false, "and NOT equipped")
	assert_eq(TechniquesApi.slots(actor).all().is_empty(), true, "no slot is occupied")
	assert_eq(
		int(TechniquesApi.summary(actor)["equipped_count"]),
		0,
		"and the loadout summary counts nothing bound"
	)


func test_a_learned_passive_applies_nothing_and_contributes_nothing() -> void:
	# ADR 0054: a learned passive must NOT auto-equip. So a manual that learns a
	# passive changes no modifier stack, no derived stat, and nothing else.
	var actor := _hero()
	var technique_id := _fresh_id("passive")
	var def := _technique(technique_id, false)
	def.passive_options = [
		{"option_id": PASSIVE_OPTION, "value": 4.0},
		{"option_id": RESOURCE_OPTION, "value": 25.0},
	]
	var max_qi_before := actor.stats.derived(Stat.MAX_QI)
	var modifiers_before := actor.stats.modifier_count()
	_stock(actor, _manual(technique_id))
	_wire()

	var studied := ItemsApi.use_item(actor, technique_id)
	assert_eq(
		bool(studied.get("ok")),
		true,
		"the manual is studied, not refused: '%s'" % String(studied.get("reason", ""))
	)
	assert_eq(TechniquesApi.codex(actor).knows(technique_id), true, "known")
	# NOTHING applied. Both counts are the load-bearing assertions.
	assert_eq(actor.stats.modifier_count(), modifiers_before, "no modifier was applied")
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_QI), max_qi_before, "and the resource channel did not move"
	)
	assert_eq(
		TechniqueEffects.applied_count(actor, technique_id), 0, "the technique contributes zero"
	)


func test_a_learned_passive_contributes_only_once_it_is_explicitly_equipped() -> void:
	# The other half of ADR 0054: learning is not a dead end. An explicit equip is
	# what makes the same technique contribute, and it contributes exactly once.
	var actor := _hero()
	var technique_id := _fresh_id("equip_later")
	var def := _technique(technique_id, false)
	def.passive_options = [
		{"option_id": PASSIVE_OPTION, "value": 4.0},
		{"option_id": RESOURCE_OPTION, "value": 25.0},
	]
	var max_qi_before := actor.stats.derived(Stat.MAX_QI)
	_stock(actor, _manual(technique_id))
	_wire()
	var studied_here := ItemsApi.use_item(actor, technique_id)
	assert_eq(
		bool(studied_here.get("ok")),
		true,
		(
			"the manual was studied: '%s' -> %s | codex=%s | id=%s"
			% [
				String(studied_here.get("reason", "")),
				str(studied_here),
				str(TechniquesApi.codex(actor).to_dict()),
				technique_id,
			]
		)
	)

	assert_eq(TechniqueEffects.applied_count(actor, technique_id), 0, "nothing yet")
	var equipped := TechniquesApi.equip(actor, technique_id)
	assert_eq(
		bool(equipped.get("ok")),
		true,
		"and it equips when asked: '%s'" % String(equipped.get("reason", ""))
	)
	assert_almost_eq(
		actor.stats.derived(Stat.MAX_QI), max_qi_before + 25.0, "the authored value, applied once"
	)
	assert_eq(TechniqueEffects.applied_count(actor, technique_id), 2, "both channels contribute")
	assert_eq(TechniquesApi.slots(actor).is_equipped(technique_id), true, "and it is bound")


func test_studying_never_grants_the_flat_base_attribute_the_item_used_to() -> void:
	# The old `_apply_learned` wrote `actor.stats.set_base(...)`. ADR 0053 moved
	# that: the manual DELIVERS a technique, and a technique's power is the def's
	# own options while EQUIPPED — never a permanent base-attribute bump on study.
	# Pinned because the old behaviour is the one this seam replaced, and a base
	# attribute is exactly what `ItemRequirement` gates on, so a flat bump would
	# let a manual fund its own gate.
	var actor := _hero()
	var technique_id := _fresh_id("no_base")
	_technique(technique_id)
	var before := actor.stats.get_base(Stat.COMPREHENSION)
	var manual := _manual(technique_id, &"base_comprehension")
	_stock(actor, manual)
	_wire()
	assert_eq(bool(ItemsApi.use_item(actor, technique_id).get("ok")), true, "studied")
	assert_almost_eq(
		actor.stats.get_base(Stat.COMPREHENSION), before, "study writes no base attribute"
	)
	assert_eq(TechniquesApi.codex(actor).knows(technique_id), true, "it learned the technique")


# --- The seam refuses to guess -------------------------------------------------


func test_the_seam_refuses_a_non_technique_item_and_the_codex_is_unchanged() -> void:
	var actor := _hero()
	var codex_before := TechniquesApi.codex(actor).technique_ids()
	# A real `OptionCatalog` technique-legal option, so this row is refused for
	# being the wrong CATEGORY and for nothing else.
	var sword := ItemDef.new()
	sword.id = &"delivery_suite_sword"
	sword.category = ItemCategory.EQUIPMENT
	sword.rarity = &"magic"
	sword.fixed_modifiers = [{"option_id": PASSIVE_OPTION, "value": 9.0}]
	_stock(actor, sword)
	_wire()

	# Forced through the seam directly, because `ItemsApi.use_item` would route an
	# equipment row to the EQUIPPED channel and never arrive here — which is itself
	# the property worth stating: the seam is only reachable for a technique row.
	var refused := TechniqueDelivery.study(actor, sword, null)
	assert_eq(bool(refused.get("ok")), false, "an equipment row is refused")
	assert_eq(String(refused.get("reason")), "not_a_technique", "by name")
	assert_eq(
		TechniquesApi.codex(actor).technique_ids(),
		codex_before,
		"and the codex is byte-for-byte unchanged"
	)
	assert_eq(actor.stats.modifier_count(), 0, "nothing was applied to the actor either")
	assert_eq(ItemsApi.inventory(actor).count(sword.id), 1, "and the item was not consumed")


func test_the_seam_refuses_a_technique_item_no_definition_claims() -> void:
	# An item that IS category=technique but whose id resolves to no `TechniqueDef`.
	# The seam must refuse `unknown_technique` rather than teach something adjacent:
	# silently resolving by display name or shared word would make a player study the
	# wrong technique, which is worse than a refusal.
	var actor := _hero()
	_wire()
	var ghost := _manual(_fresh_id("unauthored"))
	_stock(actor, ghost)
	var refused := ItemsApi.use_item(actor, ghost.id)
	assert_eq(bool(refused.get("ok")), false, "an unauthored manual is refused")
	assert_eq(String(refused.get("reason")), "unknown_technique", "by name")
	assert_eq(TechniquesApi.codex(actor).count(), 0, "and the codex is untouched")
	# All-or-nothing is `ItemsApi.use_item`'s own guarantee, and the refusal must not
	# break it: an unusable item is never consumed.
	assert_eq(ItemsApi.inventory(actor).count(ghost.id), 1, "a refused study consumes nothing")


func test_an_unbound_seam_refuses_by_name_rather_than_silently_doing_nothing() -> void:
	# "This build cannot learn" and "the gate refused" are different messages, so
	# the unbound case is named rather than reported as a bare failure.
	var actor := _hero()
	TechniqueDelivery.clear()
	assert_eq(TechniqueDelivery.is_bound(), false, "nothing installed")
	var technique_id := _fresh_id("unbound")
	_technique(technique_id)
	var refused := TechniqueDelivery.study(actor, _manual(technique_id), null)
	assert_eq(bool(refused.get("ok")), false, "refused")
	assert_eq(String(refused.get("reason")), "no_seam", "named as an unwired build")
	assert_eq(TechniquesApi.codex(actor).count(), 0, "and nothing was learned")


func test_the_gate_still_refuses_through_the_seam_and_names_what_is_unmet() -> void:
	# The seam is a delivery mechanism, not a gate bypass: a technique above the
	# actor's realm tier is still refused, and the gate's own `unmet` list reaches
	# the caller rather than being flattened.
	var actor := _hero()
	var technique_id := _fresh_id("gated")
	var def := _technique(technique_id)
	def.grade = ItemGrade.IMMORTAL
	_stock(actor, _manual(technique_id))
	_wire()
	var refused := ItemsApi.use_item(actor, technique_id)
	assert_eq(bool(refused.get("ok")), false, "an Immortal technique is refused at Mortal")
	assert_eq(String(refused.get("reason")), "realm_unmet", "by the gate, not the seam")
	assert_eq((refused.get("unmet") as Array).is_empty(), false, "and it says what is short")
	assert_eq(TechniquesApi.codex(actor).knows(technique_id), false, "nothing was learned")
	assert_eq(ItemsApi.inventory(actor).count(technique_id), 1, "and the manual survives")


func test_re_studying_a_known_technique_never_lowers_its_rung() -> void:
	# ADR 0053: re-learning never lowers a mastery rung — a duplicate manual is not a
	# mastery loss. The seam reaches `learn`, so this is a property of delivery too.
	var actor := _hero()
	var technique_id := _fresh_id("rerung")
	_technique(technique_id)
	_stock(actor, _manual(technique_id))
	_wire()
	TechniquesApi.codex(actor).learn(technique_id, 3)
	_stock(actor, _manual(technique_id))
	assert_eq(bool(ItemsApi.use_item(actor, technique_id).get("ok")), true, "studied again")
	assert_eq(
		int(TechniquesApi.codex(actor).row(technique_id).get("rung", 0)),
		3,
		"the rung is untouched by a duplicate manual"
	)


# --- The facade cap is not spent ----------------------------------------------


func test_the_delivery_seam_cost_the_facade_nothing() -> void:
	# ADR 0056: the seam is a named CLASS, so the published surface is unchanged.
	# It used to be "a named class plus a CONSTANT"; the `DELIVERY` constant is gone
	# because the value `&"technique_delivery"` was read by nothing in `res://src` and
	# could not be — the seam travels as a `ProjectSettings` Callable under
	# `TechniqueDelivery.SETTING`, never as that string.
	var published := _published_methods()
	# The seam must be absent from the METHOD list, which is what "reached as a
	# named type rather than published on the facade" means.
	assert_eq(published.has("DELIVERY"), false, "the seam is not a facade method")
