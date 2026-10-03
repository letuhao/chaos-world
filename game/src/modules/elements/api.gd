class_name ElementsApi
extends RefCounted

## Public facade for the `elements` module (ADR 0004).

static var _default_rules: ElementRules


static func default_rules() -> ElementRules:
	if _default_rules == null:
		_default_rules = ElementRules.new(ElementDefaults.all())
	return _default_rules


## Attach the element provider, and the REALM modifier that keeps `element_power_<e>`
## on the same scale as `Stat.ATTACK_SPIRITUAL` (ADR 0069).
##
## ## Why the modifier exists
##
## `RealmScaling.SCALED_STATS` is seven STATIC ids, and `element_power_<e>` is not one
## of them -- it cannot be, the ids are built from the element id at read time. So it
## would be realm-FLAT while the raw term `m_0 * ATTACK_SPIRITUAL` grows by the
## authored `RealmDef.power`, 1.00 -> 551.46. Measured element fraction of a qi hit at
## `share = 0.8`: **0.7619 at R1, 0.3678 at R11, 0.0058 at R30** -- a silent realm
## degression of the element channel to numerical noise, and worse than useless because
## it looks like a balance curve.
##
## The fix reuses ADR 0026's existing composition rather than adding an authored table:
## one source-tagged `StatModifier(power_id, Op.MULT, realm.power, SOURCE)` per element,
## which is the same shape `RealmScaling.apply` writes and lands on the same
## `mult` bucket, so it composes with an item's modifier exactly once. The element's
## share of a qi hit is then realm-INVARIANT -- the invariant worth a test, because it is
## the difference between "elements matter at every realm" and "elements stopped
## mattering somewhere past Foundation Establishment".
##
## ## `element_resistance_<e>` deliberately gets NO modifier
##
## It is a RATE, and a rate must never track a magnitude (ADR 0050). Scaling a
## defender's authored resistance by 551.46 would make deep-realm qi immunity automatic
## and silently, and a per-point investment a player paid for would become worthless.
## Recorded here rather than inherited by accident: the channel stays realm-flat, and
## the realm multiplier on the ATTACKER's power is what compensates.
##
## ## NOT IDEMPOTENT, and that is the ONE part worth being careful about
##
## `ActorStats.add_provider` appends unguarded, so calling `attach` twice on one actor
## would stack two providers. `add_modifier` is likewise unguarded, and
## `remove_modifiers_from` matches a source tag EXACTLY -- core has no prefix matching
## (see `NpcStageProjection.strip`), so a source shared with `RealmScaling` cannot be
## swept selectively. This module therefore does the repo's strip-then-apply dance
## itself: [method apply_realm_modifiers] removes only the `(RealmScaling.SOURCE,
## element_power_<e>)` pairs and rewrites them. Re-attaching the realm half is free.
##
## The consequence the ADR records honestly: attach once, and after a breakthrough call
## `RealmScaling.apply(actor)` (which clears the source tag wholesale) or
## [method apply_realm_modifiers] -- never `attach` again to "refresh" it.
static func attach(actor: Actor, rules: ElementRules = null) -> void:
	var resolved := rules if rules != null else default_rules()
	actor.stats.add_provider(ElementProvider.new(resolved))
	apply_realm_modifiers(actor, resolved)


## Write (or rewrite) the realm MULT on every `element_power_<e>` this rules set knows.
##
## Separate from [method attach] for two reasons. An actor's element set can change -- a
## cross-training unlock, a new tier's element arriving with a breakthrough -- and the
## elements the rules know are not necessarily the elements the actor has affinity in.
## And it is the cheap, safe way to pick up a new realm after a breakthrough without a
## second `attach`, which is exactly what `RealmScaling.apply` does for the seven static
## ids.
static func apply_realm_modifiers(actor: Actor, rules: ElementRules = null) -> void:
	if actor == null or actor.stats == null:
		return
	var resolved := rules if rules != null else default_rules()
	var realm := RealmScaling.highest_realm(actor)
	if realm == null:
		# No realm on the ladder: `RealmScaling.apply` removes and returns, so a
		# R1-authored 1.0 is NOT written. Matching that is what makes the modifier
		# invisible on an unstatted test actor instead of a `mult` of 1.0 per element.
		return
	strip_realm_modifiers(actor, resolved)
	for element in resolved.ids():
		actor.stats.add_modifier(
			StatModifier.new(
				ElementStats.power_id(element), Stat.Op.MULT, realm.power, RealmScaling.SOURCE
			)
		)


## Take back only this module's element-power realm modifiers, and nothing else.
##
## Walks the stack itself rather than asking core for a prefix match, because core's verb
## is exact-source by design and `RealmScaling.SOURCE` is core's tag -- clearing it
## wholesale would take the seven scaled ids with it, which is a different module's
## business. A `(source, stat)` pair is the only thing removed.
static func strip_realm_modifiers(actor: Actor, rules: ElementRules = null) -> void:
	if actor == null or actor.stats == null:
		return
	var resolved := rules if rules != null else default_rules()
	var owned: Array[StringName] = []
	for element in resolved.ids():
		owned.append(ElementStats.power_id(element))
	var kept: Array[StatModifier] = []
	for modifier in actor.stats._modifiers:
		var ours := modifier.source == RealmScaling.SOURCE and owned.has(modifier.stat)
		if not ours:
			kept.append(modifier)
	if kept.size() != actor.stats._modifiers.size():
		actor.stats._modifiers = kept
		actor.stats.mark_dirty()


static func multiplier(rules: ElementRules, attacker: StringName, defender: StringName) -> float:
	return rules.multiplier(attacker, defender)
