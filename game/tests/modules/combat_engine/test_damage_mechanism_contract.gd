extends TestCase

## The seam's generic contract, asserted once for every mechanism (ADR 0067).
##
## These are NOT qi tests. Purity, non-mutation, `mitigate` returning a fresh object
## rather than editing the one it was handed, and `breakdown()` being primitives-only
## are properties of the SEAM — a body or mind mechanism that broke any of them would
## be equally wrong, and qi was simply the first implementation to need them proved.
## Keeping them here means the next mechanism inherits the assertions for free, and it
## is why this suite exists under `tests/contracts/` in spirit and not in name: there is
## no `game/tests/contracts/` home for it yet, and inventing one directory for four
## files when `combat_engine` already holds the mechanism is ceremony.
##
## When a second mechanism lands, add its case to `_cases()` and it is checked against
## every property below automatically — that is the whole point.


## One entry per mechanism: a factory that returns a bound instance.
func _cases() -> Dictionary:
	var qi := QiDamage.new()
	qi.rules = ElementRules.new(ElementDefaults.all())
	qi.tuning = CombatTestKit.shipped()
	# Mind is checked against the SAME properties as qi. `SeaOfConsciousness` is named
	# here, not in `mind_damage.gd`: the mechanism reaches the sea as INJECTED state so
	# `combat_engine` keeps its `["contracts", "core"]` deps, and this suite is the one
	# place that legitimately holds the `mind_cultivation` edge in order to hand the
	# mechanism a real sea. Binding `sea` (rather than relying on an actor's component
	# bag) also means `mitigate` is measured with a sea in hand, so a mind regression in
	# purity or in `mitigate`-freshness is caught generically here rather than only in
	# `test_mind_damage.gd`.
	var mind := MindDamage.new()
	mind.tuning = CombatTestKit.shipped()
	mind.sea = SeaOfConsciousness.new()
	return {&"qi": qi, &"mind": mind}


## A context carrying enough for a mechanism to compute something real. The mechanism
## is not read here — it arrives already bound by the caller — so the parameter is
## underscore-prefixed to say so rather than tripping the unused-argument rule.
func _context(_mechanism: DamageMechanism) -> AttackContext:
	var attacker := CombatTestKit.actor(&"attacker")
	var defender := CombatTestKit.actor(&"defender")
	MechanismSlot.bind(attacker, CombatTestKit.FixedMechanism.new())
	return AttackContext.new(attacker, defender, null, null, 100.0, null, &"qi_refining")


## `resolve` called twice on the same context returns the same proposal, and neither
## call wrote to the context. A mechanism that caches, accumulates or stamps the
## context is a mechanism whose second hit differs from its first, and the whole
## determinism the spine is built on (ADR 0067's injected RNG) rests on this.
func test_resolve_is_pure_and_the_context_is_unmutated() -> void:
	for name in _cases():
		var mechanism: DamageMechanism = _cases()[name]
		var ctx := _context(mechanism)
		var before := ctx.data.duplicate(true)
		var first := mechanism.resolve(ctx)
		var second := mechanism.resolve(ctx)
		assert_eq(first.amount, second.amount, "%s: the same amount twice" % String(name))
		assert_eq(first.effects, second.effects, "%s: and the same effects" % String(name))
		assert_eq(ctx.data, before, "%s: the context was not written to" % String(name))


## `mitigate` returns a FRESH proposal rather than editing the one it was handed. The
## spine hands the same proposal to later stages and keeps its own reference, so an
## in-place `mitigate` would silently rewrite what the caller is still holding.
func test_mitigate_returns_a_fresh_object_and_leaves_the_input_alone() -> void:
	for name in _cases():
		var mechanism: DamageMechanism = _cases()[name]
		var ctx := _context(mechanism)
		var input := DamageProposal.new(123.0)
		var output := mechanism.mitigate(ctx, input)
		assert_eq(input.amount, 123.0, "%s: the caller's proposal is untouched" % String(name))
		assert_ne(output, input, "%s: a different object is returned" % String(name))


## A null context is a supported state, not a crash. The spine's own docblock admits
## `resolve` may answer "I decline this hit", and a mechanism that throws on a null
## takes the whole spine down with it.
func test_a_null_context_declines_rather_than_crashing() -> void:
	for name in _cases():
		var mechanism: DamageMechanism = _cases()[name]
		var proposal := mechanism.resolve(null)
		assert_ne(proposal, null, "%s: answered something" % String(name))
		assert_eq(
			is_finite(proposal.amount), true, "%s: and the amount is a finite number" % String(name)
		)


## `breakdown()` is primitives only. The repo's UI standard (ADR 0038) is that a
## `summary()` payload carries no module type and no engine object, and `breakdown()`
## is the method a readout panel will read.
func test_breakdown_is_primitives_only() -> void:
	for name in _cases():
		var mechanism = _cases()[name]
		if not mechanism.has_method(&"breakdown"):
			continue
		var parts: Variant = mechanism.call(&"breakdown", _context(mechanism))
		assert_eq(parts is Dictionary, true, "%s: breakdown is a dictionary" % String(name))
		for key in (parts as Dictionary).keys():
			var value: Variant = (parts as Dictionary)[key]
			var primitive := (
				value is float
				or value is int
				or value is bool
				or value is String
				or value is StringName
			)
			assert_eq(
				primitive, true, "%s: key %s carries a primitive" % [String(name), String(key)]
			)


## Every effect a proposal carries passes the proposal's own primitive gate. This is
## what lets an effect cross the seam and reach a save or a UI payload unchanged.
func test_every_effect_passes_the_primitive_gate() -> void:
	for name in _cases():
		var mechanism: DamageMechanism = _cases()[name]
		var proposal := mechanism.resolve(_context(mechanism))
		for effect in proposal.effects:
			assert_eq(
				DamageProposal.is_primitive_effect(effect),
				true,
				"%s: effect %s is primitive" % [String(name), str(effect)]
			)
