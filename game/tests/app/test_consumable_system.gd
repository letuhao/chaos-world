extends TestCase

## ADR 0056 / DEF-0098: `ConsumableSystem` is the id-persistence model the rest of
## the repo follows, and it survives the prototype's deletion — the file is the
## salvage, so its behaviour is still pinned here.
##
## This suite replaces `test_input_system.gd`, which tested the whole prototype:
## `SkillSystem`, `InputHandler` and `ConsumableSystem` together. `SkillDef`,
## `SkillSystem` and `InputHandler` are deleted (ADR 0056), so their assertions
## went with them and every case that asserted a bare key sequence or a combo is
## gone with a note on why. What is kept is what still has a surviving
## implementation: the consumable slot table, and the composition root's wiring of
## the techniques module that replaced the slot machine.
##
## The deleted behaviour, and why no assertion survives it:
##   - skill slots / equip / unequip / `use_skill` cost+cooldown+descriptor:
##     superseded by `TechniquesApi` learn/equip/unequip, tested in
##     `tests/modules/techniques/`. Cooldowns are deliberately NOT implemented
##     (DEF-0090 — no damage pipeline), so there is nothing here to pin.
##   - combat state toggling, combat timeout, auto-combat: DEF-0098 says delete
##     the duplicate combat state machines in favour of one CombatApi-owned
##     component. `combat/api.gd` does not expose one yet.
##   - `press_key` / `click` routing, input buffering, key tables: the router is
##     gone; combo identity is a technique field, not a key sequence (DEF-0098).
##   - `COMBO_PATTERNS` and its `multiplier: 1.5`: read by nothing but this
##     suite's own existence. Deleted.

var _actor: Actor
var _consumable_system: ConsumableSystem


func _init() -> void:
	_actor = Actor.new(&"test_player", {Stat.SPIRIT: 20.0, Stat.PHYSIQUE: 20.0})
	_actor.attach_core_resources()
	_consumable_system = ConsumableSystem.new(_actor)


func setup() -> void:
	_consumable_system.reset()


# ── Consumable slots: kept, because ConsumableSystem survives ────────────────


func test_consumable_slots_initialized() -> void:
	assert_eq(_consumable_system.slot_count(), 6, "consumable slot count")


func test_consumable_assign_and_use() -> void:
	ItemsApi.attach(_actor)
	var def := ItemDef.new()
	def.id = &"health_pill"
	def.category = ItemCategory.CONSUMABLE
	def.stackable = true
	def.max_stack = 99
	def.fixed_modifiers = [{"option_id": &"restore_health", "value": 20.0}]
	ItemsApi.inventory(_actor).add(def, 5)
	_consumable_system.assign_consumable(0, &"health_pill", 5)
	var result: Dictionary = _consumable_system.use_consumable(0)
	assert_eq(bool(result.get("ok", false)), true, "consumable use ok")


func test_consumable_empty_slot() -> void:
	var result: Dictionary = _consumable_system.use_consumable(0)
	assert_eq(bool(result.get("ok", false)), false, "empty slot fails")
	assert_eq(result.get("reason", ""), "empty_slot", "reason empty_slot")


func test_consumable_invalid_slot_is_refused() -> void:
	# ADR 0056's id-persistence model is only worth keeping if the boundaries hold:
	# an out-of-range index writes nothing rather than raising.
	var result: Dictionary = _consumable_system.assign_consumable(99, &"health_pill", 1)
	assert_eq(bool(result.get("ok", false)), false, "an out-of-range slot is refused")
	assert_eq(result.get("reason", ""), "invalid_slot", "reason invalid_slot")


func test_consumable_summary() -> void:
	var summary: Dictionary = _consumable_system.summary()
	assert_eq(summary.get("slot_count", 0), 6, "consumable summary slot count")


func test_consumable_persists_ids_not_definitions() -> void:
	# ADR 0056: "persist ids, not definitions." This is the assertion that
	# distinguishes the salvage from the deleted `SkillSystem._save`, which wrote
	# `skill.to_dict()` — the whole authored definition — into the payload.
	_consumable_system.assign_consumable(0, &"health_pill", 5)
	var data: Dictionary = _actor.get_module_data(&"consumable_slots")
	var slots: Array = data.get("slots", [])
	assert_eq(slots.size(), 6, "module data has 6 slots")
	assert_eq(String(slots[0]), "health_pill", "the slot persists as a bare id")
	assert_eq(data is Dictionary, true, "and the payload is a plain dictionary")


# ── Techniques wiring: the module that replaced the slot machine ────────────


func test_a_freshly_wired_actor_carries_the_technique_components() -> void:
	# The load-bearing assertion of this file now: `app/` attaches the techniques
	# module (ADR 0056 says app/ wires it and the module owns it), and a player
	# actor built by the composition root comes out with a codex, a slot table and
	# an upkeep tracker already on it.
	var actor := ActorFactory.build(&"techniqued", {Stat.SPIRIT: 20.0})
	ItemsApi.attach(actor)
	TechniquesApi.attach(actor)
	assert_ne(actor.component(TechniquesApi.CODEX_COMPONENT), null, "the codex is attached")
	assert_ne(actor.component(TechniquesApi.SLOTS_COMPONENT), null, "the slot table is attached")
	assert_ne(
		actor.component(TechniquesApi.UPKEEP_COMPONENT), null, "the upkeep tracker is attached"
	)


func test_attach_is_idempotent() -> void:
	# A restored save adopts its own snapshot, so a second attach must not replace
	# the codex with a fresh empty one.
	var actor := ActorFactory.build(&"twice", {Stat.SPIRIT: 20.0})
	ItemsApi.attach(actor)
	TechniquesApi.attach(actor)
	var first: Variant = actor.component(TechniquesApi.CODEX_COMPONENT)
	TechniquesApi.attach(actor)
	assert_eq(
		actor.component(TechniquesApi.CODEX_COMPONENT).get_instance_id(),
		first.get_instance_id(),
		"a second attach leaves the existing codex in place"
	)


func test_attach_writes_the_technique_state_key() -> void:
	# The module persists its own payload under its own key, so a save carries
	# technique ids and rungs rather than authored definitions.
	var actor := ActorFactory.build(&"persisted", {Stat.SPIRIT: 20.0})
	ItemsApi.attach(actor)
	TechniquesApi.attach(actor)
	assert_eq(
		actor.get_module_data(TechniquesApi.STATE_KEY).has("version"),
		true,
		"the technique state is written under the module's own key"
	)
