extends TestCase

## S2c: the elemental door at the REAL firing site. A technique whose element is above
## the attacker's rank AND realm is refused by `FightLoop._strike` with the module's
## own named reason (`element_locked`), and the same swing fires once both halves are
## met. The shipped bare swing is fire (tier 1), so the guard is dormant for it — this
## case fires a lightning technique through the same call to prove the door is live.


func _actor(id: StringName) -> Actor:
	var actor := ActorFactory.build(id, {Stat.PHYSIQUE: 20.0, Stat.SPIRIT: 20.0})
	# The spine reads the mechanism off `MechanismSlot.of` and asserts when nothing is
	# bound, so the landed half below binds through the same composition-root verb
	# production uses — the refusal half never reaches the spine.
	CombatBoot.bind_mechanisms(actor)
	return actor


func _lightning_technique() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.path = PathState.QI
	def.element = ElementStats.LIGHTNING
	def.element_share = 1.0
	def.magnitude = 1.0
	return def


func test_a_locked_element_technique_is_refused_at_the_strike() -> void:
	var hero := _actor(&"door_hero")
	var foe := _actor(&"door_foe")
	var loop := FightLoop.new(hero, foe)
	var refused: Dictionary = loop.call("_strike", hero, foe, 0, _lightning_technique())
	assert_eq(String(refused.get("reason", "")), "element_locked", "the strike names the refusal")
	assert_eq(float(refused.get("amount", -1.0)), 0.0, "and deals nothing")
	assert_eq(bool(refused.get("ok", true)), false, "as a refusal, never a silent swing")
	# The door clears once the rank AND the realm allow the element.
	hero.set_path(PathState.new(ElementMastery.PATH_ID, &"spirit_sea"))
	hero.set_path(PathState.new(PathState.QI, &"spirit_sea"))
	var landed: Dictionary = loop.call("_strike", hero, foe, 0, _lightning_technique())
	assert_ne(
		String(landed.get("reason", "")), "element_locked", "the same swing fires once usable"
	)
