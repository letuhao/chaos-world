extends TestCase

## BL-0839's proof, at the seam the GAME wires: a fixture reward reaches a real
## inventory as a REALIZED instance, or the fixture is a lie that reads as sealed.
##
## The suite installs exactly what the composition root installs —
## `DomainBoot.install()` puts `key_reach_of` + `grant_item` behind
## `DomainFixtures.set_minter` — and then solves real formations and opens a real
## treasure inside a run the shipped generator produced. Nothing here mints a stub
## granter, because a stub granter is what the other fixture suites already use and
## it is exactly why the broken seam could hide: both ends answered their own copy
## of the question while the SHIPPED pair minted a bare definition with no instance.
##
## Three claims, and each is a state, never a signal:
##   1. an opened treasure's reward is a realized instance IN the bag;
##   2. a solved formation increases the bag by its authored reward and records
##      the lore row (ADR 0216's five currencies, two of them);
##   3. the same fixture seed mints the same relic — the roll belongs to the
##      fixture, so a replay is a replay and not a reroll.

## The first authored template, the same one `test_domain_run_chain` drives.
const TEMPLATE := &"ember_grotto"

## Fixed seeds, tried in order: a run that does not ship the room under test answers
## `{}` from `DomainApi.room`, and the next seed is tried. Three constants, then the
## case fails naming what no run shipped — bounded, never a search.
const SEEDS: Array[int] = [7, 8, 9]

const OFFERING := &"ash_camp_offering"
const OFFERING_REWARD := &"ash_camp_pilgrims_ration"
const PUZZLE := &"ash_arena_formation"
const PUZZLE_REWARD := &"ash_arena_formation_key"

## The direct realization witness: an EQUIPMENT def (`stackable = false`), so the
## minted piece is an instance a save would carry, not a merged stack row.
const RELIC := &"tide_vault_hoard_of_shells"

var _heroes: Array[Actor] = []


func setup() -> void:
	DomainBoot.install()
	_heroes.clear()


func teardown() -> void:
	# `set_minter` is process-wide state and the runner calls this after EVERY test.
	DomainFixtures.set_minter(Callable(), Callable())
	DomainBoot.reset()
	_heroes.clear()


func _hero() -> Actor:
	var hero := ActorFactory.build(&"fixture_proof_actor", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})
	hero.attach_core_resources()
	ItemsApi.attach(hero)
	_heroes.append(hero)
	return hero


## The first fixed seed whose run ships `fixture_id`, as `{room_id, fixture}`, or `{}`.
## Rooms are matched by their FIXTURES rather than by a bare room id: a generated run
## suffixes a repeated def (`ash_camp#2` — the same spelling `DomainFight._door_id`
## re-derives), and the honest question is "does some room in this map hold the
## fixture", not "is the def's bare id present".
func _enter_with_fixture(hero: Actor, fixture_id: StringName) -> Dictionary:
	for seed in SEEDS:
		var entered := DomainBoot.enter_domain(hero, TEMPLATE, seed)
		if not bool(entered.get("ok", false)):
			continue
		for room in DomainApi.rooms(hero):
			var row := room as Dictionary
			for entry in row.get("fixtures", []) as Array:
				var fixture := entry as Dictionary
				if String(fixture.get("fixture_id", "")) == String(fixture_id):
					return {
						"room_id": StringName(String(row.get("room_id", ""))), "fixture": fixture
					}
	return {}


## The bag's instance for `def_id`, or null. The count is read separately by callers
## that tolerate a stack row; this is the realized-object half.
func _instance_in(hero: Actor, def_id: StringName) -> ItemInstance:
	var inventory := ItemsApi.inventory(hero)
	if inventory == null:
		return null
	for instance in inventory.instances():
		if String(instance.def_id) == String(def_id):
			return instance
	return null


## Whether the bag holds `def_id` at all — instance rows and stack rows together.
func _held(hero: Actor, def_id: StringName) -> bool:
	var inventory := ItemsApi.inventory(hero)
	if inventory == null:
		return false
	if inventory.count(def_id) > 0:
		return true
	return _instance_in(hero, def_id) != null


# --- 1. the treasure --------------------------------------------------------------


func test_an_opened_treasure_lands_a_realized_instance_in_the_bag() -> void:
	var hero := _hero()
	var found := _enter_with_fixture(hero, OFFERING)
	assert_eq(found.is_empty(), false, "a run ships the fixture under test")
	var room_id := found.get("room_id", &"") as StringName
	var opened := DomainFixtures.claim(hero, room_id, OFFERING)
	assert_eq(bool(opened.get("ok", false)), true, "the offering opens: %s" % str(opened))
	assert_eq(
		String(opened.get("pays", "")),
		DomainFixtures.PAY_EQUIPMENT,
		"paying the object currency (ADR 0216)"
	)
	assert_ne(
		String(opened.get("instance_id", "")),
		"",
		"the answer carries a REALIZED instance id, not a bare definition"
	)
	assert_eq(_held(hero, OFFERING_REWARD), true, "and the reward is in the bag")
	var again := DomainFixtures.claim(hero, room_id, OFFERING)
	assert_eq(
		String(again.get("reason", "")),
		DomainFixtures.ERR_ALREADY_CLAIMED,
		"a second claim pays nothing"
	)


# --- 2. the formation -------------------------------------------------------------


func test_a_solved_puzzle_increases_a_real_inventory() -> void:
	var hero := _hero()
	var found := _enter_with_fixture(hero, PUZZLE)
	assert_eq(found.is_empty(), false, "a run ships the fixture under test")
	var room_id := found.get("room_id", &"") as StringName
	var fixture: Dictionary = found.get("fixture", {}) as Dictionary
	var sequence: Array = fixture.get("sequence", [])
	assert_eq(sequence.is_empty(), false, "the formation authors its sequence")

	var before := int(ItemsApi.inventory(hero).used_slots())
	var smiled := false
	for node in sequence:
		var step := DomainFixtures.attempt(hero, room_id, PUZZLE, StringName(node))
		assert_eq(
			bool(step.get("ok", false)), true, "every authored node is accepted: %s" % str(step)
		)
		if String(step.get("reason", "")) == DomainFixtures.OK_CLAIMED:
			smiled = true
	assert_eq(smiled, true, "the last node completes the formation")
	assert_eq(_held(hero, PUZZLE_REWARD), true, "the authored reward is a real possession")
	assert_eq(
		int(ItemsApi.inventory(hero).used_slots()) > before,
		true,
		"and a solved puzzle INCREASES a real inventory (BL-0839's own wording)"
	)
	var state := DomainFixtures.state_of(hero, room_id, PUZZLE)
	assert_eq(
		int(state.get("insight", 0)),
		DomainFixtures.LORE_INSIGHT,
		"with the lore row recorded (ADR 0216's thinnest currency)"
	)


# --- 3. the seed, and the refusal --------------------------------------------------


func test_the_fixture_seed_mints_the_same_relic_for_two_pockets() -> void:
	var first := _hero()
	var second := _hero()
	var seed := 424242
	var a := DomainBoot.grant_item(first, RELIC, seed)
	var b := DomainBoot.grant_item(second, RELIC, seed)
	assert_eq(int(a.get("leftover", 1)), 0, "the first delivery lands")
	assert_eq(int(b.get("leftover", 1)), 0, "and so does the second")
	var one := _instance_in(first, RELIC)
	var two := _instance_in(second, RELIC)
	assert_ne(one, null, "the first pocket carries the relic as an INSTANCE")
	assert_ne(two, null, "and so does the second")
	var left := one.to_dict()
	var right := two.to_dict()
	left.erase("instance_id")
	right.erase("instance_id")
	assert_eq(left, right, "the same fixture seed rolls the same relic — never a reroll")


func test_an_unresolvable_reward_is_refused_by_name_and_pays_nothing() -> void:
	var hero := _hero()
	var answer := DomainBoot.grant_item(hero, &"no_such_reward_item", 1)
	assert_eq(int(answer.get("leftover", 0)), 1, "nothing is handed over")
	assert_eq(String(answer.get("reason", "")), "unknown_item", "and the content defect is NAMED")
	assert_eq(ItemsApi.inventory(hero).used_slots(), 0, "with the bag untouched")
