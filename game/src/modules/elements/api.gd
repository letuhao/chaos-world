class_name ElementsApi
extends RefCounted

## Public facade for the `elements` module (ADR 0004).


static func default_rules() -> ElementRules:
	# The module's ONE rules cache lives on `ElementDefaults`, so the path and training
	# files reach it without naming this facade.
	return ElementDefaults.rules()


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
## ## `element_defense_<e>` now rides the ladder TOO, and that is ADR 0200 landing
##
## ADR 0069 gave this channel its realm-flatness because it was a RATE: a rate must never
## track a magnitude (ADR 0050), and scaling a defender's authored mitigation by 551.46
## would make deep-realm qi immunity automatic and silently. ADR 0200 replaces that rate
## with an unbounded defense MAGNITUDE — which dissolves the original objection rather than
## confirming it, since a magnitude is exactly what the ladder SHOULD scale.
##
## It was left realm-flat anyway, as a KNOWN STALE RULE, because the mitigation formula
## that replaces `RESIST_CAP` had not landed yet. It has. And leaving this half off the
## ladder while the offense half rides it is the exact asymmetry ADR 0200 exists to
## remove: `element_power_<e>` grew `1.00 -> 551.46` and `element_defense_<e>` did not,
## so `D/(K+D)` fell toward `0.26` and the elemental fraction of a qi hit DRIFTED with the
## realm. `test_cross_mechanism_balance.gd` measured it — `0.665043 -> 0.694266 ->
## 0.704604 -> 0.705803`, a spread of `0.04076025` against a claimed invariance of
## `0.000001`, and a `FINDING` verdict printed by the suite itself. Both halves now ride
## the same `realm.power`, the ratio is a ratio of two realm-scaled magnitudes, and the
## fraction is invariant to float precision.
##
## `RealmScaling.SCALED_STATS` is seven STATIC ids and these ids are built from the
## element id at read time, so both halves stay out of that list for the reason
## `element_power_<e>` always was — see [method apply_realm_modifiers].
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


## Write (or rewrite) the realm MULT on every `element_power_<e>` AND every
## `element_defense_<e>` this rules set knows.
##
## Separate from [method attach] for two reasons. An actor's element set can change -- a
## cross-training unlock, a new tier's element arriving with a breakthrough -- and the
## elements the rules know are not necessarily the elements the actor has affinity in.
## And it is the cheap, safe way to pick up a new realm after a breakthrough without a
## second `attach`, which is exactly what `RealmScaling.apply` does for the seven static
## ids.
##
## BOTH halves are written from ONE `realm.power`, which is the whole point: ADR 0200's
## ratio is `m = mitigation_ceiling * D / (K + D)` with `K = defense_divisor_k *
## element_power_<e>` riding the ATTACKER and `D = element_defense_<e> / resist_divisor`
## riding the DEFENDER. Both terms have to move together or the mitigated FRACTION moves
## with the realm, which is what `test_cross_mechanism_balance.gd` was measuring.
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
		actor.stats.add_modifier(
			StatModifier.new(
				ElementStats.defense_id(element), Stat.Op.MULT, realm.power, RealmScaling.SOURCE
			)
		)
	# ADR 0215. The per-element CRIT pair rides the SAME ladder as the power/defense
	# pair, for the same reason and because a contest is a ratio of two numbers that must
	# be the same KIND of number. Scaling only the offence half would make a deep-realm
	# attacker certain to crit — which is exactly the saturation the ADR exists to
	# remove, arrived at from the other direction.
	for element in _owned_crit_elements(resolved):
		actor.stats.add_modifier(
			StatModifier.new(
				ElementStats.crit_id(element), Stat.Op.MULT, realm.power, RealmScaling.SOURCE
			)
		)
		actor.stats.add_modifier(
			StatModifier.new(
				ElementStats.crit_resist_id(element), Stat.Op.MULT, realm.power, RealmScaling.SOURCE
			)
		)


## Every element id a crit channel is published for, plus the omni one when the rules
## know it. The omni channel is not in `_rules.ids()`, so writing a modifier for it is
## what stops a ladder step from leaving one actor's `element_crit` unscaled while every
## other crit channel moved — the halves of ONE contest disagreeing by a factor of 551.
static func _owned_crit_elements(resolved: ElementRules) -> Array[StringName]:
	var out: Array[StringName] = []
	for element in resolved.ids():
		out.append(element)
	if not out.has(ElementStats.OMNI):
		out.append(ElementStats.OMNI)
	return out


## Take back only this module's element-power and element-defense realm modifiers, and
## nothing else.
##
## Walks the stack itself rather than asking core for a prefix match, because core's verb
## is exact-source by design and `RealmScaling.SOURCE` is core's tag -- clearing it
## wholesale would take the seven scaled ids with it, which is a different module's
## business. A `(source, stat)` pair is the only thing removed.
##
## Both per-element ids are on the owned list, because ADR 0200 put them on the same
## ladder. Leaving the defense half out would leave a stale `MULT` behind on every
## breakthrough and the two halves would drift apart again by exactly one realm step.
static func strip_realm_modifiers(actor: Actor, rules: ElementRules = null) -> void:
	if actor == null or actor.stats == null:
		return
	var resolved := rules if rules != null else default_rules()
	var owned: Array[StringName] = []
	for element in resolved.ids():
		owned.append(ElementStats.power_id(element))
		owned.append(ElementStats.defense_id(element))
	# ADR 0215: the crit pair is on the owned list for the same reason the other two
	# halves are — leaving it out would leave a stale `MULT` behind on every breakthrough
	# and the halves of the crit contest would drift apart again by one realm step.
	for element in _owned_crit_elements(resolved):
		owned.append(ElementStats.crit_id(element))
		owned.append(ElementStats.crit_resist_id(element))
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


## ## The mastery loop's doors (ADR 0004's second half)
##
## The practice STEP is owned here, the way `QiCultivationApi` owns its
## `CULTIVATE_STEP`: a caller passes a time unit and the module prices it, so no
## screen carries a balance number of its own.
const PRACTICE_STEP := 25.0


static func can_practise(actor: Actor, element_id: StringName) -> bool:
	return ElementTraining.can_practise(actor, element_id)


static func practise(actor: Actor, element_id: StringName, amount: float = PRACTICE_STEP) -> bool:
	return ElementTraining.practise(actor, element_id, amount)


static func mastery_of(actor: Actor, element_id: StringName) -> float:
	return ElementMastery.mastery_of(actor, element_id)


## Open an element the body was not born with: a rare resource raises the AFFINITY
## itself, and the practice gate follows.
static func awaken(actor: Actor, element_id: StringName, amount: float) -> bool:
	return ElementTraining.awaken(actor, element_id, amount)


## ## The elemental path's doors (ADR 0004): enroll, read, advance
##
## The Awaken action is the ENROLLMENT (explicit, never implicit), and the threshold
## the next rung costs is the authored labour curve for that realm — INJECTED by the
## composition root (`set_progress_source`), because this module may not read another
## path's seeds. An uninstalled source refuses advancement with a named reason instead
## of inventing a number.
static func set_progress_source(source: Callable) -> void:
	ElementMastery.set_progress_source(source)


static func begin(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if ElementMastery.enrolled(actor):
		return {"ok": false, "reason": "already_enrolled"}
	var first := RealmDefaults.ladder().realms()[0]
	actor.set_path(PathState.new(ElementMastery.PATH_ID, first.id))
	attach(actor)
	return {"ok": true, "rank": String(first.id)}


static func preview(actor: Actor) -> Dictionary:
	return ElementMastery.preview(actor)


static func advance(actor: Actor) -> Dictionary:
	return ElementMastery.advance(actor)


## Whether `actor` may USE `element_id` right now: the elemental rank must reach the
## element's tier AND the actor's realm must allow it (both, deliberately).
static func can_use(actor: Actor, element_id: StringName) -> bool:
	return ElementMastery.usable(actor, element_id)


## The NAMED refusal a firing site reports when `element_id` is out of reach, or `&""`
## when the element is usable — or empty, which is unelemental and needs no gate. One
## place words the refusal, so every site refuses with the same reason (ADR 0034's rule
## that a gate and its preview share the wording).
static func locked(actor: Actor, element_id: StringName) -> StringName:
	if element_id == &"":
		return &""
	if can_use(actor, element_id):
		return &""
	return &"element_locked"
