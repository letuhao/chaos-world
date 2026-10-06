extends TestCase

## ADR 0880: S3 reads the per-element crit pair the `elements` module generates and
## publishes (ADR 0215) — `element_crit_<e>` / `element_crit_resist_<e>` for a technique
## that names an element, the omni pair for an elementless one — on top of the core
## `Stat.CRIT_CHANCE` / `Stat.CRIT_RESIST` contest. Before this the channels were
## generated, realm-scaled, provider-emitted and read by nothing.
##
## Every draw is `0.0` and every attacker is quiet, so `outcome.crit` answers exactly the
## question "is the net half strictly above zero", which is the ADR 0877 rule.

var _tuning: CombatTuning


func setup() -> void:
	_tuning = CombatTestKit.shipped()


func test_a_techniques_own_element_can_win_the_crit() -> void:
	assert_eq(_resolve(&"fire", {&"element_crit_fire": 1.0}).crit, true, "the fire half crits")


func test_the_same_investment_does_not_leak_to_another_element() -> void:
	var outcome := _resolve(&"water", {&"element_crit_fire": 1.0})
	assert_eq(outcome.crit, false, "a water technique never read the fire channel")


func test_the_matching_resist_half_cancels_to_zero() -> void:
	var outcome := _resolve(
		&"fire", {&"element_crit_fire": 1.0}, {&"element_crit_resist_fire": 1.0}
	)
	assert_eq(outcome.crit, false, "equal halves read exactly zero, and a tie whiffs")


func test_an_unelemental_technique_reads_the_omni_channel() -> void:
	assert_eq(_resolve(&"", {&"element_crit_": 1.0}).crit, true, "the omni half carries it")
	assert_eq(_resolve(&"", {}).crit, false, "and an uninvested elementless blow does not crit")


func test_an_unknown_element_reads_as_untrained_rather_than_crashing() -> void:
	var outcome := _resolve(&"no_such_element", {&"element_crit_fire": 1.0})
	assert_eq(outcome.crit, false, "no channel resolves, so no crit and no error")


func test_the_read_is_gated_on_the_authored_prefix() -> void:
	_tuning.element_crit_prefix = ""
	assert_eq(_resolve(&"fire", {&"element_crit_fire": 1.0}).crit, false, "cleared prefix, no read")


# --- internals ---------------------------------------------------------------------


## One clean blow with a technique carrying `element`, from a QUIET attacker (core crit
## zeroed, ADR 0022) carrying `attacker_ids` as flat modifiers, against a plain target
## carrying `target_ids` the same way.
func _resolve(
	element: StringName, attacker_ids: Dictionary = {}, target_ids: Dictionary = {}
) -> CombatOutcome:
	var attacker := CombatTestKit.quiet_actor(&"attacker")
	for id in attacker_ids:
		attacker.stats.add_modifier(
			CombatStats.rate_modifier(StringName(id), float(attacker_ids[id]), &"test")
		)
	var target := CombatTestKit.actor(&"target")
	for id in target_ids:
		target.stats.add_modifier(
			CombatStats.rate_modifier(StringName(id), float(target_ids[id]), &"test")
		)
	var technique := CombatTestKit.technique(100.0)
	technique.element = element
	var mechanism := CombatTestKit.FixedMechanism.new()
	mechanism.amount = 1.0
	MechanismSlot.bind(attacker, mechanism)
	return CombatSpine.resolve_hit(
		attacker, target, technique, _tuning, CombatTestKit.CountingGenerator.new([0.0])
	)
