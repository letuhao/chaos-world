extends TestCase

## The rapid key in a live fight (BL-0933): the loop fires the equipped rapid
## technique at the TECHNIQUE's own cast interval, clamped at 5 hits/s, while the heavy
## blow's own gate is untouched.
##
## The `_hero`/`_minted` fixtures mirror `test_fight_anchor_and_tone.gd`'s on purpose:
## the two files measure the same loop, so a fixture drift would fail both rather than
## let one suite measure a fight the other never runs.

const REALM := &"qi_refining"


func setup() -> void:
	# The damage seam the composition root installs (`item_workbench_body.gd`): the
	# test runner never boots the app, so the suite installs the same Callable.
	TechniqueCasting.set_resolver(
		func(attacker: Actor, target: Actor, def: TechniqueDef) -> Variant:
			return CombatEngineApi.resolve_hit(attacker, target, def, CombatEngineApi.tuning())
	)


func _hero() -> Actor:
	var actor := ActorFactory.build(&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})
	ActorFactory.with_body_cultivation(actor, REALM)
	ActorFactory.with_qi_cultivation(actor, REALM)
	ActorFactory.with_mind_cultivation(actor, REALM)
	actor.meridians.unlock_for_realm(REALM)
	CombatBoot.install(actor)
	return actor


## A rapid technique with a chosen authored interval.
func _rapid(suffix: String, cooldown: float) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = StringName("rapid_%s" % suffix)
	def.display_name = "Rapid Art"
	def.grade = ItemGrade.MORTAL
	def.path = PathState.QI
	def.active = true
	def.rapid = true
	def.cooldown = cooldown
	def.magnitude = 0.4
	def.element = ElementStats.FIRE
	TechniqueCatalog.instance().register(def)
	return def


func _equip_rapid(hero: Actor, def: TechniqueDef) -> void:
	TechniquesApi.codex(hero).learn(def.id)
	assert_eq(bool(TechniquesApi.equip(hero, def)["ok"]), true, "the rapid art equips onto the key")


## A loop with the hero adopted and a fight open against a minted opponent.
func _fighting_loop(hero: Actor) -> FightLoop:
	var loop := FightLoop.new(hero)
	loop.adopt_hero(hero)
	assert_eq(bool(loop.start_fight(&"rapid_opponent", REALM)["ok"]), true, "the fight opens")
	return loop


func _health_of(loop: FightLoop, key: String) -> float:
	return float(loop.summary().get(key, 0.0))


# --- The cast lands, pays and gates -------------------------------------------


func test_a_rapid_cast_lands_and_starts_the_techniques_own_interval() -> void:
	var hero := _hero()
	var def := _rapid("own_interval", 0.5)
	_equip_rapid(hero, def)
	var loop := _fighting_loop(hero)
	var before := _health_of(loop, "opponent_health")
	var fired := loop.cast_rapid(11)
	assert_eq(bool(fired.get("ok", false)), true, "the cast fires: %s" % str(fired))
	assert_eq(_health_of(loop, "opponent_health") < before, true, "and the technique lands damage")
	assert_almost_eq(
		_health_of(loop, "rapid_remaining"),
		0.5,
		"the authored interval gates the next cast",
		0.0001
	)
	# The gate is REAL: an immediate second cast is refused by name, and one interval of
	# elapsed time opens it again.
	var early := loop.cast_rapid(12)
	assert_eq(String(early.get("reason", "")), FightLoop.R_NOT_READY, "too early refuses")
	loop.age(0.5)
	assert_eq(bool(loop.cast_rapid(13).get("ok", false)), true, "the interval reopens the key")


## The clamp is the LOOP's, not the content's: an art authored at zero still fires no
## faster than 5 hits/s, and `MIN_RAPID_INTERVAL` is that number.
func test_the_clamp_bounds_an_unauthored_interval_at_five_per_second() -> void:
	assert_almost_eq(
		FightLoop.MIN_RAPID_INTERVAL, 0.2, "the clamp is 5 hits/s, restated as a pin", 0.0001
	)
	var hero := _hero()
	_equip_rapid(hero, _rapid("zero_interval", 0.0))
	var loop := _fighting_loop(hero)
	assert_eq(bool(loop.cast_rapid(21).get("ok", false)), true, "fires")
	assert_almost_eq(
		_health_of(loop, "rapid_remaining"),
		FightLoop.MIN_RAPID_INTERVAL,
		"and the clamp, not the authored zero, gates it",
		0.0001
	)


## The heavy blow's gate is a different action's: a cast never preempts it, and only
## elapsed time opens either.
func test_the_heavy_gate_is_untouched_by_a_cast() -> void:
	var hero := _hero()
	_equip_rapid(hero, _rapid("heavy_untouched", 0.2))
	var loop := _fighting_loop(hero)
	var heavy_before := _health_of(loop, "blows_remaining")
	assert_eq(heavy_before > 0.0, true, "the heavy blow starts on its own gate")
	loop.cast_rapid(31)
	loop.age(0.2)
	loop.cast_rapid(32)
	assert_almost_eq(
		_health_of(loop, "blows_remaining"),
		heavy_before - 0.2,
		"only the elapsed time moved the heavy gate",
		0.0001
	)


## The sixty-second band, in the rate arithmetic the census asserts: the clamp's rate
## is >= the rapid class's 300 hits a fight, and the heavy anchor stays ~25 blows.
func test_the_bands_rate_arithmetic_holds() -> void:
	assert_eq(
		60.0 / FightLoop.MIN_RAPID_INTERVAL >= 300.0, true, "the rapid class clears 300 in sixty"
	)
	var heavy := 60.0 * FightLoop.BASE_BLOWS_PER_SECOND
	assert_eq(heavy >= 24.0 and heavy <= 26.0, true, "and the heavy anchor stays ~25 blows")


# --- Every refusal is named ---------------------------------------------------


func test_an_empty_rapid_key_refuses_by_name() -> void:
	var hero := _hero()
	var loop := _fighting_loop(hero)
	var fired := loop.cast_rapid(41)
	assert_eq(bool(fired.get("ok", false)), false, "nothing to cast")
	assert_eq(
		String(fired.get("reason", "")), FightLoop.R_NO_RAPID, "and the refusal names the key"
	)


func test_a_cast_outside_a_fight_refuses_like_an_exchange() -> void:
	var hero := _hero()
	_equip_rapid(hero, _rapid("no_fight", 0.2))
	var loop := FightLoop.new(hero)
	loop.adopt_hero(hero)
	var fired := loop.cast_rapid(51)
	# The same guard order an exchange reads: the missing OPPONENT is named before the
	# missing fight, because that is the check a caller can act on first.
	assert_eq(String(fired.get("reason", "")), FightLoop.R_NO_OPPONENT, "no opponent, no cast")
