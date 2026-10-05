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
## ## `element_defense_<e>` deliberately gets NO modifier, STILL
##
## ADR 0069 gave this channel its realm-flatness because it was a RATE: a rate must never
## track a magnitude (ADR 0050), and scaling a defender's authored mitigation by 551.46
## would make deep-realm qi immunity automatic and silently. ADR 0200 replaces that rate
## with an unbounded defense MAGNITUDE — which dissolves the original objection rather than
## confirming it, since a magnitude is exactly what the ladder SHOULD scale.
##
## It is nonetheless still realm-flat, because ADR 0200 lists moving the resistance-like
## halves onto `RealmScaling.SCALED_STATS` as a separate open consequence and the
## mitigation formula that replaces `RESIST_CAP` has not landed. Recorded here as a KNOWN
## STALE RULE rather than left inherited: whoever implements the formula owns this line,
## and `tests/modules/elements/test_element_stat_publication.gd::
## test_element_defense_carries_no_realm_multiplier_while_power_does` pins the present
## behavior so the move cannot happen silently.
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
## The realm half is therefore free to rewrite whenever the ladder moves: after a
## breakthrough call `RealmScaling.apply(actor)` (which clears the source tag wholesale) or
## [method apply_realm_modifiers].
##
## ## `attach` is IDEMPOTENT, and that is what makes it the verb a restore path must use
##
## [method attach] mounts the provider only if the actor has none, then refreshes the realm
## half either way. So "attach" and "refresh" are the same call, which is the only shape a
## SHARED attach list can have: `ItemWorkbenchApp._attach_body_modules` is reached by a fresh
## build, a restore and a body swap, and the first of those already has the provider from
## `ActorFactory.build` while the other two never do.
##
## It was not idempotent until a restore proved why it had to be. `restore_actor` called
## [method apply_realm_modifiers] alone, on the reading that the realm half was all that was
## missing — it was not, because `Actor.from_dict` restores components and **never a
## `StatProvider`**. The omission was invisible in the most misleading way available:
## `ActorStats._recompute` backs every modifier bucket at `0.0`, so the realm MULT still
## published `element_power_<e>` onto `derived_all()` for a provider that was not there, while
## `element_defense_<e>` -- which no modifier ever names -- was simply absent, and
## `derived(element_power_<e>)` read `0.0` whatever affinity the body held. A returning
## player had no elemental power and no elemental resistance at all, on the one channel
## ADR 0069 calls realm-INVARIANT and ADR 0088 makes status potency read.
##
## The guard is the same one [code]FertilityApi.attach[/code] uses, and for the same reason:
## `ActorStats.add_provider` appends unguarded, so a second copy would double every
## contribution. What changed is only that the verb no longer punishes a caller for asking
## twice.
static func attach(actor: Actor, rules: ElementRules = null) -> void:
	if actor == null:
		return
	var resolved := rules if rules != null else default_rules()
	if not _has_provider(actor):
		actor.stats.add_provider(ElementProvider.new(resolved))
	apply_realm_modifiers(actor, resolved)


## Whether this actor already carries an [ElementProvider], read by script identity rather
## than by position: a provider's RULES are its own, so "the first one" is not a fact about
## the module and "an [ElementProvider]" is.
static func _has_provider(actor: Actor) -> bool:
	for entry in actor.stats._providers:
		if entry.get_script() == ElementProvider:
			return true
	return false


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
