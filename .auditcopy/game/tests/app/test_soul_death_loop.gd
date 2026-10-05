extends TestCase

## ADR 0130: the whole death loop, end to end, through the real verbs.
##
## ## Why this suite exists when the module suites already pass
##
## **`SoulApi`'s own suite proves the arithmetic and never proves the LOOP.** A ledger that
## damages correctly, a gate that answers correctly and a store that survives correctly all
## pass while nothing ever connects a dying body to any of them — which is the exact defect
## DEF-0109 and DEF-0151 record in this repo ("tested, built and unwired"). So the cases here
## drive the same sequence the game drives: health to zero, guardian or not, damage, re-body,
## world advanced, save written.

var _actor: Actor
var _soul_store: SoulWorldLedger
var _anchor_store: AnchorWorldLedger
var _death: SoulDeath
var _deaths: Array[StringName] = []
var _minted: Array = []


func setup() -> void:
	_soul_store = SoulWorldLedger.new()
	_anchor_store = AnchorWorldLedger.new()
	SoulApi.set_store(_soul_store)
	AnchorApi.set_store(_anchor_store)
	_deaths.clear()
	_minted.clear()
	_actor = _hero(&"hero_one")
	DifficultyApi.attach(_actor)
	SoulApi.attach(_actor)
	AnchorApi.attach(_actor)
	_death = SoulDeath.new(_mint, _adopt)


## Every process-wide static this suite installs, released on the way out. Leaving them
## populated lets the next suite read THIS suite's soul, and ObjectDB then reports leaked
## instances at exit with every assertion green. Idempotent, and safe after an early return.
func teardown() -> void:
	# Every actor this suite minted, released so ObjectDB does not report leaked instances at
	# exit with every assertion green. `_born`-style bookkeeping exists for exactly this: the
	# call sites are interleaved, so freeing at each one is skipped by any early return.
	for born in _minted:
		(born as Actor).resources.clear()
	_minted.clear()
	_deaths.clear()
	_actor = null
	SoulApi.set_store(null)
	AnchorApi.set_store(null)


# --- The loop ----------------------------------------------------------------


func test_a_death_with_no_guardian_damages_the_soul_and_re_embodies() -> void:
	# The whole requirement in one case: no consumable guardian, the soul is damaged, the
	# player continues as a NEW actor, and the world does not rewind.
	var before := int(SoulApi.soul(_actor)["integrity"])
	# Captured BEFORE the death: `_adopt` swaps `_actor` for the new body, so reading it after
	# would compare the new body's id against itself and always pass.
	var old_body_id := String(_actor.id)
	var outcome := _die()
	assert_eq(bool(outcome["died"]), true, "the body died")
	assert_eq(String(outcome["guardian"]), "", "no guardian was spent")
	assert_eq(int(outcome["damage"]) > 0, true, "the soul paid something")
	assert_eq(
		int(SoulApi.soul(_actor)["integrity"]),
		before - int(outcome["damage"]),
		"integrity fell by exactly what was reported"
	)
	assert_eq(bool(outcome["incarnated"]), true, "the soul re-embodied")
	assert_ne(String(outcome["body_id"]), old_body_id, "into a different body")
	assert_eq(String(_actor.id), String(outcome["body_id"]), "and the shell now holds it")


func test_the_new_body_carries_the_damaged_soul_and_not_a_fresh_one() -> void:
	# The point of a store-backed soul: the body changes, the soul does not reset. A soul in
	# `module_data` would read as full here and every other suite would still pass.
	_die()
	var reborn := _minted[_minted.size() - 1] as Actor
	assert_eq(
		int(SoulApi.soul(reborn)["integrity"]),
		int(SoulApi.soul(_actor)["integrity"]),
		"the new body reads the SAME damaged soul"
	)


func test_the_incarnation_advances_and_a_life_is_spent() -> void:
	var lives := int(SoulApi.soul(_actor)["lives"])
	_die()
	assert_eq(int(SoulApi.soul(_actor)["incarnation"]), 1, "one incarnation")
	assert_eq(int(SoulApi.soul(_actor)["lives"]), lives - 1, "one life spent")


func test_a_second_death_lands_the_player_in_a_different_arrival() -> void:
	# ADR 0130's "new story path". The gate answers the first UNEARNED arrival, so a second
	# death must not replay the first one.
	_die()
	var first := String(SoulApi.soul(_actor)["arrival"])
	_die()
	var second := String(SoulApi.soul(_actor)["arrival"])
	assert_ne(second, first, "the arrival is not the same one twice")
	assert_ne(second, "", "and it is a real arrival")


func test_the_world_is_not_rewound_by_a_death() -> void:
	# The requirement is that the world takes advantage of the player. An anchor raised BEFORE
	# the death must still stand after it — a rewind would take it with the body.
	_give_hearth_materials()
	AnchorApi.raise_anchor(_actor, &"hearth_of_the_returning", "somewhere")
	assert_eq(AnchorApi.is_raised(_actor, &"hearth_of_the_returning"), true, "raised before")
	_die()
	assert_eq(
		AnchorApi.is_raised(_actor, &"hearth_of_the_returning"),
		true,
		"still standing after the body died"
	)


func test_a_soul_out_of_lives_does_not_rebody_and_says_so() -> void:
	# Exhaust the lives through the real verb, then die again. The refusal must be NAMED, and
	# the damage must still have been paid — a run that ended still happened.
	for _i in range(SoulState.DEFAULT_LIVES):
		_die()
	var integrity := int(SoulApi.soul(_actor)["integrity"])
	var outcome := _die()
	assert_eq(String(outcome["reason"]), "soul_spent", "the refusal is named")
	assert_eq(bool(outcome["incarnated"]), false, "no body was minted")
	assert_eq(
		int(SoulApi.soul(_actor)["integrity"]),
		maxi(0, integrity - int(outcome["damage"])),
		"the soul still paid, because a death still happened"
	)


# --- The guardian -------------------------------------------------------------


func test_a_guardian_is_spent_and_the_soul_is_untouched() -> void:
	# The consumable guardian is the whole of the "if they don't have one" clause: with one, a
	# death costs the ITEM and nothing else.
	_give_guardian()
	var integrity := int(SoulApi.soul(_actor)["integrity"])
	var lives := int(SoulApi.soul(_actor)["lives"])
	var outcome := _die()
	assert_eq(bool(outcome["died"]), false, "the body did not die")
	assert_eq(String(outcome["reason"]), "guardian_spent", "and the reason says why")
	assert_eq(int(outcome["damage"]), 0, "the soul paid nothing")
	assert_eq(int(SoulApi.soul(_actor)["integrity"]), integrity, "integrity is untouched")
	assert_eq(int(SoulApi.soul(_actor)["lives"]), lives, "no life was spent")
	assert_eq(bool(outcome["incarnated"]), false, "no new body")


func test_the_guardian_is_consumed_rather_than_merely_read() -> void:
	_give_guardian()
	_die()
	assert_eq(ItemsApi.has_item(_actor, &"guardian_vigil_ash", 1), false, "the item was spent")


func test_a_healed_body_after_a_guardian_is_alive_again() -> void:
	# The pool must be restored through `change` so its `changed` signal still fires; leaving it
	# at zero would re-fire the death poll on the very next frame.
	_give_guardian()
	_die()
	var pool := _actor.resource(&"health")
	assert_eq(pool.current > 0.0, true, "the body is standing again")
	assert_eq(_death.is_dead(_actor), false, "and is not dead")


# --- Difficulty ----------------------------------------------------------------


func test_difficulty_changes_what_a_death_costs_and_nothing_else() -> void:
	DifficultyApi.select(_actor, &"story")
	var story := _damage_of(&"story")
	DifficultyApi.select(_actor, &"hard")
	var hard := _damage_of(&"hard")
	DifficultyApi.select(_actor, &"standard")
	var standard := _damage_of(&"standard")
	assert_eq(story < standard, true, "story costs less")
	assert_eq(hard > standard, true, "hard costs more")


func test_difficulty_decides_the_share_and_never_the_amount() -> void:
	# ADR 0129's rule, proven through the real path: the row supplies a FRACTION of an
	# authored base cost. A difficulty that supplied the amount would be the second curve.
	var base := int(SoulDeath.BASE_DEATH_COST)
	DifficultyApi.select(_actor, &"standard")
	assert_eq(_damage_of(&"standard"), base, "the neutral row is a no-op on the authored cost")
	DifficultyApi.select(_actor, &"hard")
	assert_eq(_damage_of(&"hard"), int(float(base) * 1.5), "hard is 1.5x that base")


# --- The anchor ------------------------------------------------------------------


func test_a_raised_anchor_repairs_the_soul_over_whole_periods() -> void:
	# The building feature, doing the one thing the soul module cannot do for itself: giving a
	# damaged soul somewhere to be repaired. `periods` is explicit because nothing may own a
	# clock (DEF-0111).
	_die()
	_give_hearth_materials()
	var damaged := int(SoulApi.soul(_actor)["integrity"])
	assert_eq(
		AnchorApi.raise_anchor(_actor, &"hearth_of_the_returning", "here")["ok"], true, "raised"
	)
	var healed := AnchorApi.repair(_actor, 10)
	assert_eq(bool(healed["ok"]), true, "the anchor repaired")
	assert_eq(int(healed["restored"]) > 0, true, "by a real amount")
	assert_eq(int(SoulApi.soul(_actor)["integrity"]) > damaged, true, "the soul is less damaged")


func test_repair_refuses_when_nothing_is_raised_rather_than_doing_nothing_quietly() -> void:
	_die()
	var out := AnchorApi.repair(_actor, 10)
	assert_eq(bool(out["ok"]), false, "no anchor, no repair")
	assert_eq(String(out["reason"]), "not_raised", "and the refusal is named")


func test_repair_refuses_zero_periods_because_there_is_no_tick() -> void:
	_give_hearth_materials()
	AnchorApi.raise_anchor(_actor, &"hearth_of_the_returning", "here")
	var out := AnchorApi.repair(_actor, 0)
	assert_eq(String(out["reason"]), "no_periods", "a repair needs time the caller supplies")


func test_an_anchor_is_a_world_fact_so_a_second_actor_sees_it_standing() -> void:
	# ADR 0101's argument, in the one place where forgetting it would be cheapest to forget.
	# A per-actor ledger would let a rival raise their own on the same ground.
	_give_hearth_materials()
	assert_eq(
		bool(AnchorApi.raise_anchor(_actor, &"hearth_of_the_returning", "here")["ok"]),
		true,
		"the first actor raised it"
	)
	var rival := _hero(&"rival")
	assert_eq(
		AnchorApi.is_raised(rival, &"hearth_of_the_returning"),
		true,
		"a rival sees the anchor standing"
	)
	assert_eq(
		String(AnchorApi.raise_anchor(rival, &"hearth_of_the_returning", "here")["reason"]),
		"already_raised",
		"and cannot raise a second one on the same ground"
	)


func test_an_anchor_above_the_realm_floor_is_refused_by_name() -> void:
	# The stone is authored at `core_formation`, so a mortal cannot raise it. Saying so is the
	# difference between a gate and a silent failure.
	var out := AnchorApi.raise_anchor(_actor, &"stone_of_the_held_name", "here")
	assert_eq(bool(out["ok"]), false, "a mortal cannot reach it")
	assert_eq(String(out["reason"]), "realm_floor", "and the refusal is named")


func test_the_authored_anchors_are_all_usable() -> void:
	# An anchor that repairs nothing and shelters nothing is a building a player can raise for
	# no reason, so it fails the gate rather than shipping as content that does nothing.
	assert_eq(AnchorApi.validate(), [], "every authored anchor does something")


# --- Internals -------------------------------------------------------------------


## Kill the current body and resolve it, exactly as the frame driver does.
func _die() -> Dictionary:
	_kill(_actor)
	return _death.resolve(_actor)


## The integrity a death costs under `difficulty_id`, measured through the real path.
func _damage_of(difficulty_id: StringName) -> int:
	DifficultyApi.select(_actor, difficulty_id)
	var probe := _hero(&"probe_%s" % difficulty_id)
	DifficultyApi.attach(probe)
	DifficultyApi.select(probe, difficulty_id)
	SoulApi.attach(probe)
	var resolver := SoulDeath.new(_mint, _adopt)
	_kill(probe)
	return int(resolver.resolve(probe).get("damage", 0))


## Take the body to zero health, through the pool's own `change` so the signal fires.
func _kill(body: Actor) -> void:
	body.attach_core_resources()
	var pool := body.resource(&"health")
	pool.change(-pool.maximum)


## The composition root's mint callback: a real body, tracked so teardown can release it.
##
## The incarnation is PASSED IN by `SoulDeath`, which reads the ledger before `reincarnate`
## advances it — reading it here would mint the id the previous body already holds.
func _mint(arrival_id: String, incarnation: int) -> Dictionary:
	_deaths.append(StringName(arrival_id))
	var built := CharacterCreationFlow.build_forced(StringName(arrival_id), incarnation)
	if not bool(built.get("ok", false)):
		return {"ok": false, "reason": String(built.get("reason", ""))}
	_minted.append(built["actor"])
	return built


## The composition root's adopt callback: the new body becomes the one every read answers from.
func _adopt(body: Actor) -> void:
	if body != null:
		_actor = body


## An actor with a body plan and core pools, built without the composition root so a test does
## not need a scene tree.
func _hero(actor_id: StringName) -> Actor:
	var body := ActorFactory.build(actor_id)
	RaceApi.attach(body)
	RaceApi.set_race(body, &"stoneborn")
	body.attach_core_resources()
	_minted.append(body)
	return body


## Give the actor what the hearth's authored cost asks for.
##
## The hearth costs two `vial_mending_elixir`, and `raise_anchor` gates on the ITEM cost — the
## coin figure is recorded as the price but charged by `economy`, which this module declares no
## edge to. So a test that wants the hearth standing must actually be holding what it asks for,
## which is the point of the gate.
func _give_hearth_materials() -> void:
	_give_item(&"vial_mending_elixir", 2)


## The consumable that saves a death: spent, and the soul pays nothing.
func _give_guardian() -> void:
	_give_item(&"guardian_vigil_ash", 1)


## Put `def_id` in the bag, attaching an inventory only when there is none.
func _give_item(def_id: StringName, count: int) -> void:
	if ItemsApi.inventory(_actor) == null:
		ItemsApi.attach(_actor)
	var bag := ItemsApi.inventory(_actor)
	var def := Crafting.resolve(def_id)
	if def != null and not bag.has(def_id, count):
		bag.add(def, count)
