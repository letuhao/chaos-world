extends TestCase

## Technique set bonuses: when N techniques from the same set are equipped,
## a bonus triggers. Works for both passive and active techniques.
##
## Set state is derived from equipped techniques (TechniqueSlots), NOT from
## the codex — learning a technique without equipping it does not count.

const MORTAL := &"qi_refining"

## `cult_qi_control` is one of the 36 technique-legal pool options (ADR 0054).
const STAT_OPTION := &"cult_qi_control"
## `core_max_qi` is a resource-capacity target.
const RESOURCE_OPTION := &"core_max_qi"

static var _serial: int = 0


## A resolver that counts its own calls, so a test can assert the set bonus
## adds no phantom activation.
class _SetResolver:
	extends RefCounted

	var calls: int = 0

	func resolve(attacker: Actor, target: Actor, def: TechniqueDef) -> Dictionary:
		calls += 1
		return {"amount": 10.0}


func _actor(qi: float = 500.0) -> Actor:
	var actor := Actor.new(&"practitioner", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", qi))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	TechniquesApi.attach(actor)
	return actor


## A technique def registered with the catalog so the facade can resolve it.
## Passive options are NOT added by default — a test that needs a technique to
## contribute its own stats passes them explicitly, so the set bonus is the
## only variable under test.
func _technique(
	active: bool = false, path: StringName = PathState.QI, passive_options: Array[Dictionary] = []
) -> TechniqueDef:
	_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("set_suite_tech_%d" % _serial)
	def.display_name = "Technique"
	def.grade = ItemGrade.MORTAL
	def.active = active
	def.path = path
	if not active and not passive_options.is_empty():
		def.passive_options = passive_options
	TechniqueCatalog.instance().register(def)
	return def


## A technique set def registered with the catalog.
func _make_set(
	members: Array[StringName], tiers: Array[Dictionary], active: bool = false
) -> TechniqueSet:
	_serial += 1
	var set_def := TechniqueSet.new()
	set_def.id = StringName("set_suite_set_%d" % _serial)
	set_def.display_name = "Test Set"
	set_def.members = members
	set_def.tiers = tiers
	set_def.active = active
	TechniqueSetCatalog.instance().register(set_def)
	return set_def


## Learn and equip a technique in one step.
func _equip(actor: Actor, def: TechniqueDef) -> void:
	TechniquesApi.codex(actor).learn(def.id)
	TechniquesApi.equip(actor, def)


# --- Set bonus triggers at threshold -----------------------------------------


func test_set_bonus_triggers_when_n_techniques_are_equipped() -> void:
	var actor := _actor()
	var first := _technique()
	var second := _technique()
	var members: Array[StringName] = [first.id, second.id]
	var tiers: Array[Dictionary] = [
		{"count": 2, "label": "Two-piece", "options": [{"option_id": STAT_OPTION, "value": 10.0}]}
	]
	_make_set(members, tiers)

	# Equip only one member: threshold not reached.
	_equip(actor, first)
	var qi_control := actor.stats.derived(StringName("qi_control"))
	assert_almost_eq(qi_control, 0.0, "no set bonus with one member equipped")

	# Equip the second member: threshold reached.
	_equip(actor, second)
	var with_bonus := actor.stats.derived(StringName("qi_control"))
	assert_almost_eq(with_bonus, 10.0, "set bonus applies at threshold")


func test_set_bonus_does_not_trigger_below_threshold() -> void:
	var actor := _actor()
	var first := _technique()
	var second := _technique()
	var third := _technique()
	var members: Array[StringName] = [first.id, second.id, third.id]
	var tiers: Array[Dictionary] = [
		{"count": 3, "label": "Three-piece", "options": [{"option_id": STAT_OPTION, "value": 15.0}]}
	]
	_make_set(members, tiers)

	_equip(actor, first)
	_equip(actor, second)
	var qi_control := actor.stats.derived(StringName("qi_control"))
	assert_almost_eq(qi_control, 0.0, "no set bonus with two of three members")


func test_set_bonus_drops_when_a_member_is_unequipped() -> void:
	var actor := _actor()
	var first := _technique()
	var second := _technique()
	var members: Array[StringName] = [first.id, second.id]
	var tiers: Array[Dictionary] = [
		{"count": 2, "label": "Two-piece", "options": [{"option_id": STAT_OPTION, "value": 10.0}]}
	]
	_make_set(members, tiers)

	_equip(actor, first)
	_equip(actor, second)
	assert_almost_eq(actor.stats.derived(StringName("qi_control")), 10.0, "bonus active")

	TechniquesApi.unequip(actor, first)
	assert_almost_eq(
		actor.stats.derived(StringName("qi_control")), 0.0, "bonus drops below threshold"
	)


# --- Passive set bonus contributes to stats ----------------------------------


func test_passive_set_bonus_contributes_to_stats() -> void:
	var actor := _actor()
	var first := _technique(false)
	var second := _technique(false)
	var members: Array[StringName] = [first.id, second.id]
	var tiers: Array[Dictionary] = [
		{
			"count": 2,
			"label": "Two-piece",
			"options":
			[
				{"option_id": STAT_OPTION, "value": 5.0},
				{"option_id": RESOURCE_OPTION, "value": 50.0},
			],
		}
	]
	_make_set(members, tiers, false)

	_equip(actor, first)
	_equip(actor, second)

	# The set bonus contributes both a stat and a resource-capacity modifier.
	assert_almost_eq(actor.stats.derived(StringName("qi_control")), 5.0, "stat bonus applied")
	assert_almost_eq(actor.stats.derived(Stat.MAX_QI), 130.0, "resource bonus applied (80 + 50)")


# --- Active set bonus ---------------------------------------------------------


func test_active_set_bonus_is_applied_as_stat_contribution() -> void:
	# An active technique's benefit IS the cast, so a set bonus on an active set
	# is applied as a passive stat contribution that modifies the cast's
	# effectiveness — never as a separate action that fires nothing.
	var actor := _actor()
	var first := _technique(true)
	var second := _technique(true)
	var members: Array[StringName] = [first.id, second.id]
	var tiers: Array[Dictionary] = [
		{"count": 2, "label": "Two-piece", "options": [{"option_id": STAT_OPTION, "value": 8.0}]}
	]
	_make_set(members, tiers, true)

	_equip(actor, first)
	_equip(actor, second)

	# The bonus is a stat contribution, not a cast action.
	assert_almost_eq(
		actor.stats.derived(StringName("qi_control")), 8.0, "active set bonus applied as stat"
	)


func test_active_set_bonus_does_not_fire_as_separate_cast() -> void:
	# The set bonus must not create a phantom cast. It is a stat contribution
	# only — `activate` on a member technique fires exactly one resolver call.
	var actor := _actor()
	var first := _technique(true)
	var second := _technique(true)
	var members: Array[StringName] = [first.id, second.id]
	var tiers: Array[Dictionary] = [
		{"count": 2, "label": "Two-piece", "options": [{"option_id": STAT_OPTION, "value": 8.0}]}
	]
	_make_set(members, tiers, true)

	_equip(actor, first)
	_equip(actor, second)

	var target := Actor.new(&"target")
	var casting := actor.component(TechniquesApi.CASTING_COMPONENT) as TechniqueCasting
	var resolver := _SetResolver.new()
	var fired := casting.activate(actor, first, target, resolver.resolve)
	assert_eq(bool(fired["ok"]), true, "the active technique fires")
	assert_eq(resolver.calls, 1, "exactly one cast — the set bonus adds no phantom activation")


# --- Set state is derived from equipped techniques, not the codex -------------


func test_set_state_is_derived_from_equipped_techniques_not_codex() -> void:
	var actor := _actor()
	var first := _technique()
	var second := _technique()
	var members: Array[StringName] = [first.id, second.id]
	var tiers: Array[Dictionary] = [
		{"count": 2, "label": "Two-piece", "options": [{"option_id": STAT_OPTION, "value": 10.0}]}
	]
	_make_set(members, tiers)

	# Learn both techniques but equip only one.
	TechniquesApi.codex(actor).learn(first.id)
	TechniquesApi.codex(actor).learn(second.id)
	_equip(actor, first)

	assert_almost_eq(
		actor.stats.derived(StringName("qi_control")),
		0.0,
		"no bonus — second technique not equipped"
	)
	assert_eq(TechniquesApi.codex(actor).knows(second.id), true, "but it is known")


func test_set_state_reflects_techniques_learned_but_not_equipped() -> void:
	# Learning a technique without equipping it must not count toward a set
	# threshold. The codex is the acquisition state; the slot table is the
	# equip state. Set bonuses derive from the latter.
	var actor := _actor()
	var first := _technique()
	var second := _technique()
	var members: Array[StringName] = [first.id, second.id]
	var tiers: Array[Dictionary] = [
		{"count": 2, "label": "Two-piece", "options": [{"option_id": STAT_OPTION, "value": 10.0}]}
	]
	_make_set(members, tiers)

	# Learn both, equip neither.
	TechniquesApi.codex(actor).learn(first.id)
	TechniquesApi.codex(actor).learn(second.id)
	TechniquesApi.rebuild(actor)
	assert_almost_eq(
		actor.stats.derived(StringName("qi_control")), 0.0, "no bonus with nothing equipped"
	)


# --- Multiple tiers -----------------------------------------------------------


func test_multiple_tiers_trigger_at_their_respective_thresholds() -> void:
	var actor := _actor()
	var first := _technique()
	var second := _technique()
	var third := _technique()
	var members: Array[StringName] = [first.id, second.id, third.id]
	var tiers: Array[Dictionary] = [
		{"count": 2, "label": "Two-piece", "options": [{"option_id": STAT_OPTION, "value": 5.0}]},
		{
			"count": 3,
			"label": "Three-piece",
			"options": [{"option_id": STAT_OPTION, "value": 12.0}]
		},
	]
	_make_set(members, tiers)

	_equip(actor, first)
	_equip(actor, second)
	# Tier 0 (count=2) is active: +5.0
	assert_almost_eq(actor.stats.derived(StringName("qi_control")), 5.0, "two-piece bonus")

	_equip(actor, third)
	# Both tiers are active: +5.0 + 12.0 = 17.0
	assert_almost_eq(actor.stats.derived(StringName("qi_control")), 17.0, "both tiers stack")


# --- Set state persistence ----------------------------------------------------


func test_set_state_survives_a_rebuild() -> void:
	var actor := _actor()
	var first := _technique()
	var second := _technique()
	var members: Array[StringName] = [first.id, second.id]
	var tiers: Array[Dictionary] = [
		{"count": 2, "label": "Two-piece", "options": [{"option_id": STAT_OPTION, "value": 10.0}]}
	]
	_make_set(members, tiers)

	_equip(actor, first)
	_equip(actor, second)
	assert_almost_eq(actor.stats.derived(StringName("qi_control")), 10.0, "bonus active")

	# Rebuild must not drift or accumulate.
	TechniquesApi.rebuild(actor)
	assert_almost_eq(
		actor.stats.derived(StringName("qi_control")), 10.0, "bonus stable after rebuild"
	)
	TechniquesApi.rebuild(actor)
	assert_almost_eq(actor.stats.derived(StringName("qi_control")), 10.0, "still stable")


# --- Suspended techniques don't count toward thresholds ----------------------


func test_suspended_technique_does_not_count_toward_threshold() -> void:
	var actor := _actor(10.0)
	var first := _technique()
	var second := _technique()
	# Make the second technique expensive so it suspends.
	second.upkeep = {&"qi": 50.0}
	second.upkeep_interval = 60.0

	var members: Array[StringName] = [first.id, second.id]
	var tiers: Array[Dictionary] = [
		{"count": 2, "label": "Two-piece", "options": [{"option_id": STAT_OPTION, "value": 10.0}]}
	]
	_make_set(members, tiers)

	_equip(actor, first)
	_equip(actor, second)
	# Settle upkeep: the second technique cannot pay, so it suspends.
	TechniquesApi.settle_upkeep(actor)

	# The suspended technique does not count toward the threshold.
	assert_almost_eq(
		actor.stats.derived(StringName("qi_control")), 0.0, "suspended member does not count"
	)
	assert_eq(TechniquesApi.slots(actor).is_equipped(second.id), true, "but it is still equipped")
