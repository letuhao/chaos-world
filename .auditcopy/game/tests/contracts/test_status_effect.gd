extends TestCase

## ADR 0086: the shared status contract, extended in place.
##
## The load-bearing assertions here are the ones a widening could silently break:
## the constructor stays `(id, remaining = -1.0)` because two live call sites use
## it, `is_permanent()`/`is_expired()` keep their exact meaning, and every new field
## is DEFAULTED so `StatusEffect.new(&"x")` is still a complete status. A subclass
## (`PregnancyStatus`) must keep working through all of it, which is why the
## subclass's own behaviour is asserted here and not only in its module.


## A status that publishes at least one lever, which is what an authored hazard
## must do (ADR 0075). Used so a test asserting something else about magnitude or
## duration is not also asserting that it published nothing.
func _levered(id: StringName, remaining: float = -1.0) -> StatusEffect:
	var status := StatusEffect.new(id, remaining)
	status.mitigation_tags.append(&"gear")
	return status


func test_a_bare_status_constructs_and_is_permanent() -> void:
	# The two live call sites' shapes, pinned: `StatusEffect.new(&"x")` is a
	# permanent status, `StatusEffect.new(&"x", 60.0)` a timed one.
	var bare := StatusEffect.new(&"x")
	assert_eq(bare.id, &"x", "id carried")
	assert_almost_eq(bare.remaining, -1.0, "default remaining")
	assert_eq(bare.is_permanent(), true, "bare status is permanent")
	assert_eq(bare.is_expired(), false, "a permanent status never expires")
	var timed := StatusEffect.new(&"x", 60.0)
	assert_eq(timed.is_permanent(), false, "timed status is not permanent")
	assert_eq(timed.is_expired(), false, "a fresh timed status has not expired")
	timed.tick(60.0)
	assert_eq(timed.is_expired(), true, "a drained status expired")


func test_every_new_field_is_defaulted() -> void:
	# A default is not a "nice to have" here: `StatusEffect.new(&"x")` is the
	# shape `StatusApply._status` builds while the contract may still be narrow,
	# so an undefaulted field would be a null read rather than a sensible one.
	var status := StatusEffect.new(&"x")
	assert_eq(status.element, &"", "no element by default")
	assert_eq(status.kind, StatusEffect.Kind.STAT_MODIFIER, "default kind")
	assert_eq(status.scope, StatusEffect.Scope.COMBAT, "default scope")
	assert_eq(status.stacking, StatusEffect.Stacking.REFRESH, "default stacking")
	assert_almost_eq(status.magnitude, 0.0, "default magnitude")
	assert_almost_eq(status.magnitude_cap, 0.0, "default cap")
	assert_eq(status.stacks, 1, "a fresh status is one stack")
	assert_almost_eq(status.tick_interval, 0.0, "no interval by default")
	assert_almost_eq(status.tick_elapsed, 0.0, "no elapsed time by default")
	assert_eq(status.source, &"", "no source by default")
	assert_eq(status.mitigation_tags.size(), 0, "no levers by default")
	assert_eq(status.payload.is_empty(), true, "no payload by default")


func test_tick_only_ages_the_timer() -> void:
	# `tick` is the ORIGINAL four-line method and is unchanged: the interval
	# counters belong to whoever drives the tick, not to the timer.
	var status := StatusEffect.new(&"blessing", 10.0)
	status.tick(4.0)
	assert_almost_eq(status.remaining, 6.0, "aged by delta")
	status.tick(99.0)
	assert_almost_eq(status.remaining, 0.0, "clamped at zero, never negative")
	assert_eq(status.is_expired(), true, "a clamped status is expired")


func test_an_empty_mitigation_is_detectable() -> void:
	# ADR 0075/0086: `mitigation_tags` is required, so "no lever" must be a
	# QUESTION with an answer rather than an absent array that reads as empty by
	# accident. `StatusDef.problems()` is the audit that enforces it.
	var bare := StatusEffect.new(&"hazard")
	assert_eq(bare.has_mitigation(), false, "an empty lever list is detectable")
	bare.mitigation_tags.append(&"pill")
	assert_eq(bare.has_mitigation(), true, "a published lever is detectable")
	# And the two lists do not alias, so one status's levers never leak into the
	# next one created from the same default.
	var other := StatusEffect.new(&"other_hazard")
	assert_eq(other.has_mitigation(), false, "defaults are not shared between instances")


func test_the_op_enum_is_reused_and_mult_is_refused() -> void:
	# ADR 0086: `Op` is NOT duplicated, and `MULT` is banned because N instances
	# would compound to 1024x and make a status's strength a function of how often
	# it was applied.
	assert_eq(StatusEffect.ALLOWED_OPS.has(Stat.Op.FLAT), true, "FLAT allowed")
	assert_eq(StatusEffect.ALLOWED_OPS.has(Stat.Op.PERCENT), true, "PERCENT allowed")
	assert_eq(StatusEffect.ALLOWED_OPS.has(Stat.Op.MULT), false, "MULT banned")
	var status := _levered(&"sunder")
	assert_eq(status.allows_op(Stat.Op.FLAT), true, "FLAT accepted")
	assert_eq(status.allows_op(Stat.Op.MULT), false, "MULT refused by the contract")


func test_only_a_combat_scope_is_resisted() -> void:
	# "a blessing the game pays out must not tax the player for receiving it".
	var combat := _levered(&"sunder")
	var blessing := _levered(&"heavenly_blessing")
	blessing.scope = StatusEffect.Scope.CULTIVATION
	assert_eq(combat.is_resisted_by(0.5), true, "combat status meets resistance")
	assert_eq(blessing.is_resisted_by(0.5), false, "cultivation status ignores it")
	assert_eq(combat.is_resisted_by(0.0), false, "no resistance, nothing to resist")


func test_the_element_is_a_tag_and_not_a_type() -> void:
	# ADR 0086: `contracts/` may depend on nothing, so an element is a StringName
	# here and a module owns the vocabulary behind it.
	var status := _levered(&"immolation")
	status.element = &"fire"
	assert_eq(status.element, &"fire", "element is a StringName tag")
	assert_eq(StatusEffect.new(&"x").element, &"", "empty means not element-bound")


func test_a_subclass_overrides_nothing_and_still_works() -> void:
	# The subclass precedent ADR 0086 keeps legal: a real state machine extends
	# this class, overrides no constructor and adds fields of its own. If the
	# constructor or `is_expired` moved, this is the assertion that fails first.
	var status := PregnancyStatus.new(&"pregnancy")
	assert_eq(status.id, &"pregnancy", "id assigned by the owner")
	assert_eq(status.stage, PregnancyStatus.Stage.CONCEIVED, "first stage")
	assert_eq(status.is_gestating(), false, "not gestating yet")
	assert_eq(status.is_permanent(), true, "no expiry authored")
	assert_eq(status.has_mitigation(), false, "a state machine is not a hazard")
	# It inherits the widened vocabulary too, which is the point of extending in
	# place rather than subclassing per status.
	status.scope = StatusEffect.Scope.CULTIVATION
	status.mitigation_tags.append(&"affinity")
	assert_eq(status.has_mitigation(), true, "inherits the widened contract")
