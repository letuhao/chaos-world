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


## The parts for one case at a chosen elemental share and a chosen number of points of
## authored elemental RESISTANCE.
##
## `resistance_points` is resistance in the ATTACKER's element, because that is where
## `QiDamage._resistance_of` reads it: `clampf(element_resistance_<attacker_element> /
## resist_divisor - penetration, 0, resist_cap)`. `defender_element` is a SEPARATE axis and
## is carried explicitly on `DEFENDER_ELEMENT_KEY` rather than left to the dominance walk,
## because the two answers were previously conflated into one affinity slot and every
## resistance case in this subsystem was silently measuring a defender who resisted
## nothing.
func _parts(
	element: StringName, defender_element: StringName, share: float, resistance_points: float
) -> Dictionary:
	var attacker := _attacker(element)
	var target := _defender(element, resistance_points)
	return QiDamage.new().breakdown(
		_context(attacker, target, element, share, 100.0, defender_element)
	)


## An attacker whose numbers are pinned so the arithmetic is legible: spirit 10.0 and
## aptitude 10.0 give `ATTACK_SPIRITUAL = 25.0`, and an affinity of 10.0 in `element` with
## no mastery gives `element_power_<element> = 10.0`.
##
## The affinity is in the element UNDER TEST, so every case carries the same elemental
## power and the matchup is the only thing that varies between two rows of the table.
##
## The base dictionary is a single named constant rather than an inline literal so
## gdformat has one dict to wrap instead of one per call site, and so the pinned numbers
## have exactly one definition across these suites.
func _attacker(element: StringName = ElementStats.FIRE) -> Actor:
	var actor := Actor.new(&"attacker", ATTACKER_BASE)
	actor.add_resource(ResourcePool.new(&"health", 1000.0))
	if element != &"":
		actor.set_affinity(element, _affinity())
	ElementsApi.attach(actor, _rules)
	return actor


## A defender whose resistance is authored in `resisted_element`, and `will` is left at
## 0.0 so `element_resistance_<resisted_element>` is exactly `affinity * 0.5` with no
## `will` term to account for. `resistance_points` is the RESISTANCE, so the affinity is
## twice it.
##
## `ElementsApi.attach` is REQUIRED, not decoration: `element_resistance_<e>` is
## contributed by `ElementProvider` and reads `0.0` on an actor nobody attached one to.
## Without it every resistance assertion in both qi suites was measuring "no contest".
func _defender(resisted_element: StringName, resistance_points: float) -> Actor:
	var actor := Actor.new(&"defender", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 10.0})
	actor.add_resource(ResourcePool.new(&"health", 5000.0))
	if resisted_element != &"":
		actor.set_affinity(resisted_element, resistance_points * 2.0)
	ElementsApi.attach(actor, _rules)
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
##
## `with_rules = false` is the only way to reach the "nothing injected anywhere"
## degradation case: this helper injects the rules unconditionally, so the case that
## asserts `rules_bound == false` was asserting against a context that had them.
func _context(
	attacker: Actor,
	target: Actor,
	element: Variant,
	share: float,
	magnitude: float = 100.0,
	defender_element: StringName = &"",
	with_rules: bool = true
) -> AttackContext:
	var ctx := AttackContext.new(attacker, target, null, _tuning, magnitude)
	if with_rules:
		ctx.set_data(QiDamage.ELEMENT_RULES_KEY, _rules)
	# The blend a caller might hand over is an `Array`, never an element id, so both
	# branches below are the same write: the shape is rejected downstream, not here.
	ctx.set_data(QiDamage.ELEMENT_KEY, element)
	ctx.set_data(QiDamage.ELEMENT_SHARE_KEY, share)
	if defender_element != &"":
		ctx.set_data(QiDamage.DEFENDER_ELEMENT_KEY, defender_element)
	return ctx


## The affinity every fixture actor is built with, in whatever element is under test.
func _affinity() -> float:
	return 10.0


## The pinned single spelling of the fixture's affinity, for the assertions that quote it.
func _fire_affinity() -> float:
	return 10.0


func _raw_attack_of(realm_id: StringName) -> float:
	return 25.0 * _power_of(realm_id)


func _power_of(realm_id: StringName) -> float:
	return RealmDefaults.ladder().realm(realm_id).power
