extends TestCase

## `third_man_spared` is reachable from PRODUCTION — the gap BL-0803 filed.
##
## `CombatApi.spare` shipped with zero production callers, so the fact it writes was watched
## by `the_tally_of_a_man_who_kept_count` (need **2**), `what_the_rotation_cost`, and an
## AUTHORED fate literally named `the_third_man_spared` in `game/data/destiny/fates/` — and
## nothing in the shipped game could ever clear it.
##
## ## The moment, taken from the fate's own description
##
## That fate says, verbatim: *"Stood at killing distance with the advantage held and did not
## close. The sect files this as an incomplete hunt, not as mercy."* So the moment is not a
## surrender (no surrender system exists) and not a duel resolution (ADR 0076 makes an
## encounter a stat-resolved exchange in which **either side can win**). It is the player
## holding the advantage and choosing to stop.
##
## ## Where that choice lives
##
## `PlayerAdapter` is the shipped player's body, and `attack` is already the ONE place it
## lands a blow. Its `interact` press is the other action on the same target — and it was
## emitting `interacted(name)` into a handler that, for a combatant, could only ever file the
## press as a look at a thing. So `interact` while `State.COMBAT` now means *show mercy*:
## it resolves nothing, spends no health, and hands the decision to `CombatBoot`, the combat
## composition root and the only layer allowed to name `CombatApi.spare`.
##
## ## The OWNER writes (ADR 0113); nothing polls
##
## There is no timer, no sweep, no `has anyone shown mercy yet` pass anywhere on this path.
## `CombatBoot.mercy` refuses before it delegates, and the module records the mercy state and
## the fact itself.
##
## ## These cases drive the PRODUCTION path
##
## The load-bearing assertions go through `PlayerAdapter.interact` and `CombatBoot`, never
## through `CombatApi.spare` by hand. A test that called the verb itself would stay green if
## the whole wiring were deleted — which is how this gap survived an audit.

const SEED := 424242


func teardown() -> void:
	CombatMercy.install(Callable())


func _fighter(actor_id: StringName) -> Actor:
	return ActorFactory.build(actor_id, {Stat.PHYSIQUE: 12.0, Stat.AGILITY: 8.0, Stat.WILL: 6.0})


## A `PlayerAdapter` fighting `ward`, with the full combat stack installed. The opponent's
## node is returned too, because a case that stages a SECOND opponent needs to take the
## first one off the registry — `interact` presses the NEAREST interactable, so two nodes at
## the same distance make the second press land on the one already spared.
func _in_a_fight(hero: Actor, ward_node: Node2D) -> PlayerAdapter:
	CombatBoot.install(hero)
	var adapter := PlayerAdapter.new(hero)
	adapter.set_state(PlayerAdapter.State.COMBAT)
	adapter.global_position = Vector2.ZERO
	adapter.add_interactable(ward_node)
	return adapter


## The node an opponent stands as. Carries its `Actor` under the `&"actor"` meta the
## adapter already reads (`_defender_of`), so no subclass and no spawner is needed.
func _opponent_node(ward: Actor) -> Node2D:
	var target := Node2D.new()
	target.name = String(ward.id)
	target.global_position = Vector2(PlayerAdapter.INTERACTION_RANGE * 0.5, 0.0)
	target.set_meta(&"actor", ward)
	return target


# --- the wiring, which is the whole point --------------------------------------


## The one production path: pressing E on the opponent you are holding spares them.
func test_pressing_interact_on_an_opponent_while_fighting_spares_them() -> void:
	var hero := _fighter(&"challenger")
	var ward := _fighter(&"ward")
	var adapter := _in_a_fight(hero, _opponent_node(ward))
	# The press is the ONLY caller exercised here — `CombatApi.spare` is never named.
	adapter.interact()

	assert_eq(
		WorldFact.count(hero, CombatFacts.FACT_THIRD_MAN_SPARED),
		1,
		"the press recorded the fact on the ONE WHO SHOWED MERCY"
	)
	assert_eq(
		WorldFact.count(ward, CombatFacts.FACT_THIRD_MAN_SPARED),
		0,
		"and not on the opponent — this is a fact about the mercy, not about the fight"
	)


## The gate is non-trivial: a bare actor who has never fought does not already pass it, and
## an EXPLORATION press on the very same opponent does not clear it either.
func test_the_fact_is_not_already_true_and_an_exploration_press_does_not_clear_it() -> void:
	var hero := _fighter(&"challenger")
	var ward := _fighter(&"ward")
	assert_eq(WorldFact.count(hero, CombatFacts.FACT_THIRD_MAN_SPARED), 0, "not already true")

	# Not fighting: the same press on the same target means "look at this", as it always did.
	CombatBoot.install(hero)
	var adapter := PlayerAdapter.new(hero)
	var target := Node2D.new()
	target.name = "ward"
	target.global_position = Vector2(PlayerAdapter.INTERACTION_RANGE * 0.5, 0.0)
	target.set_meta(&"actor", ward)
	adapter.add_interactable(target)
	adapter.interact()

	assert_eq(
		WorldFact.count(hero, CombatFacts.FACT_THIRD_MAN_SPARED),
		0,
		"an exploration press is not a mercy, so the gate stays shut"
	)


## Half (a) of the gate-soundness rule: satisfiable from a legal prior state. Two presses
## on two living opponents is the shortest legal route to the need 2 of
## `the_tally_of_a_man_who_kept_count`.
func test_two_mercies_clears_the_need_two_step() -> void:
	var hero := _fighter(&"challenger")
	var first := _fighter(&"ward_one")
	var first_node := _opponent_node(first)
	var adapter := _in_a_fight(hero, first_node)
	adapter.interact()

	var second := _fighter(&"ward_two")
	# `interact` presses the NEAREST interactable, so the first opponent is taken OFF the
	# registry first: two nodes at the same distance would make this press land on the one
	# already spared, which is refused `already_spared` and records nothing.
	adapter.remove_interactable(first_node)
	adapter.add_interactable(_opponent_node(second))
	adapter.interact()

	assert_eq(
		WorldFact.count(hero, CombatFacts.FACT_THIRD_MAN_SPARED),
		2,
		"two opponents let walk, which is exactly what the authored step asks for"
	)


## The mercy is a TERMINAL state, not a tally: the next swing on that opponent is refused
## against it, so a mercy cannot be a note somebody quietly cancels with the next blow.
func test_a_spared_opponent_cannot_then_be_killed_by_the_next_swing() -> void:
	var hero := _fighter(&"challenger")
	var ward := _fighter(&"ward")
	var adapter := _in_a_fight(hero, _opponent_node(ward))
	adapter.interact()

	var landed: Variant = CombatBoot.strike(hero, ward, SEED)
	var answer: Dictionary = landed if landed is Dictionary else {}
	var blow: Dictionary = answer.get("result", {}) as Dictionary

	assert_eq(String(blow.get("reason", "")), "defender_spared", "the duel is over with them")
	assert_eq(
		WorldFact.count(hero, CombatFacts.FACT_DUELS_WON),
		0,
		"and a duel that ended in mercy is not a duel WON"
	)


## A corpse cannot be shown mercy, and a spared opponent cannot be spared twice: both are
## refusals that write nothing, so the monotone ledger stays monotone.
func test_the_press_is_refused_on_a_corpse_and_on_an_already_spared_opponent() -> void:
	var hero := _fighter(&"challenger")
	var ward := _fighter(&"ward")
	var adapter := _in_a_fight(hero, _opponent_node(ward))
	adapter.interact()

	# A second press on the same opponent: the mercy already happened.
	adapter.interact()
	assert_eq(
		WorldFact.count(hero, CombatFacts.FACT_THIRD_MAN_SPARED),
		1,
		"the same mercy written twice is still one mercy"
	)

	var corpse := _fighter(&"corpse")
	# STAGE the body already down. A body falls in some earlier fight; it is not produced
	# HERE, because the one swing this path can land is a bare one priced at `2.0` against
	# a `170.0` pool (`CombatBoot.BARE_SWING_MAGNITUDE`), and a test that relied on one
	# swing killing would be asserting a number this suite does not own. The press under
	# test — a mercy on a corpse — then runs on the staged state and must write nothing.
	var corpse_pool := corpse.resource(&"health") as ResourcePool
	corpse_pool.change(-corpse_pool.maximum)
	assert_almost_eq(corpse_pool.current, 0.0, "the corpse is staged at zero health")
	var corpse_adapter := _in_a_fight(hero, _opponent_node(corpse))
	corpse_adapter.interact()

	assert_eq(
		WorldFact.count(hero, CombatFacts.FACT_THIRD_MAN_SPARED),
		1,
		"a body already down is not somebody to be merciful towards"
	)


## An unbound seam is a NAMED refusal, never a silent no-op — the same posture `attack`
## already takes, so a boot order that never reached `CombatBoot.install` is diagnosable.
func test_an_unbound_mercy_seam_refuses_by_name_and_records_nothing() -> void:
	var hero := _fighter(&"challenger")
	var ward := _fighter(&"ward")
	CombatMercy.install(Callable())
	assert_eq(CombatMercy.installed(), false, "nothing is installed")

	var refused := CombatMercy.commit(hero, ward)

	assert_eq(bool(refused["ok"]), false, "the seam is not installed")
	assert_eq(String(refused["reason"]), "no_resolver", "so it says so by name")
	assert_eq(
		WorldFact.count(hero, CombatFacts.FACT_THIRD_MAN_SPARED),
		0,
		"and a mercy that did not happen is not a mercy"
	)
