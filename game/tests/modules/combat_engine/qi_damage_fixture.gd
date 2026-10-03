extends TestCase

## Shared fixture for the qi-damage suites. Not a suite itself: the runner
## discovers `test_*.gd` only, so this file is never executed on its own.
##
## It exists so `test_qi_damage.gd` (the mechanism contract) and
## `test_qi_damage_realm.gd` (ADR 0069's realm invariance) share ONE copy of the
## pinned actor arithmetic. A second copy would drift, and a drift here is
## invisible: both suites would still be green against their own copy.

## spirit 10.0 and aptitude 10.0 give `ATTACK_SPIRITUAL = spirit*2 + aptitude*0.5 =
## 25.0`. physique and comprehension are the two the spine's own derived stats need to
## be non-degenerate; neither moves this fixture's arithmetic.
const ATTACKER_BASE := {
	Stat.SPIRIT: 10.0,
	Stat.APTITUDE: 10.0,
	Stat.PHYSIQUE: 10.0,
	Stat.COMPREHENSION: 10.0,
}

var _tuning: CombatTuning
var _rules: ElementRules


func setup() -> void:
	_tuning = CombatTuning.shipped()
	_rules = ElementsApi.default_rules()


## The parts for a real STRONG/NEUTRAL/whatever pair at a chosen share and a chosen
## number of points of authored elemental resistance on the defender.
func _parts(
	element: StringName, defender_element: StringName, share: float, resistance_points: float
) -> Dictionary:
	var attacker := _attacker()
	var target := _defender(defender_element, resistance_points)
	return QiDamage.new().breakdown(_context(attacker, target, element, share))


## An attacker whose numbers are pinned so the arithmetic is legible: spirit 10.0 and
## aptitude 10.0 give `ATTACK_SPIRITUAL = 25.0`, and fire affinity 10.0 with no mastery
## gives `element_power_fire = 10.0`.
##
## The base dictionary is a single named constant rather than an inline literal so
## gdformat has one dict to wrap instead of one per call site, and so the pinned numbers
## have exactly one definition across these suites.
func _attacker() -> Actor:
	var actor := Actor.new(&"attacker", ATTACKER_BASE)
	actor.add_resource(ResourcePool.new(&"health", 1000.0))
	actor.set_affinity(ElementStats.FIRE, _fire_affinity())
	ElementsApi.attach(actor, _rules)
	return actor


## A defender with a health pool, an affinity in `element`, and `will` 0.0 so its
## `element_resistance_<element>` is exactly `affinity * 0.5` -- no `will` term to
## account for. `resistance_points` is the RESISTANCE, so the affinity is twice it.
func _defender(element: StringName, resistance_points: float) -> Actor:
	var actor := Actor.new(&"defender", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 10.0})
	actor.add_resource(ResourcePool.new(&"health", 5000.0))
	if element != &"":
		actor.set_affinity(element, resistance_points * 2.0)
	return actor


func _technique(element: StringName, share: float) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = &"qi_test"
	def.element = element
	def.element_share = share
	def.magnitude = 100.0
	return def


## A context shaped exactly as `CombatSpine._context` shapes one, minus the spine's own
## stage writes the mechanism does not read.
func _context(
	attacker: Actor, target: Actor, element: Variant, share: float, magnitude: float = 100.0
) -> AttackContext:
	var ctx := AttackContext.new(attacker, target, null, _tuning, magnitude)
	ctx.set_data(QiDamage.ELEMENT_RULES_KEY, _rules)
	if element is Array:
		# The blend a caller might hand over: an `Array`, never an element id.
		ctx.set_data(QiDamage.ELEMENT_KEY, element)
	else:
		ctx.set_data(QiDamage.ELEMENT_KEY, element)
	ctx.set_data(QiDamage.ELEMENT_SHARE_KEY, share)
	return ctx


func _fire_affinity() -> float:
	return 10.0


func _raw_attack_of(realm_id: StringName) -> float:
	return 25.0 * _power_of(realm_id)


func _power_of(realm_id: StringName) -> float:
	return RealmDefaults.ladder().realm(realm_id).power
