extends TestCase

## WHAT THE ELEMENT PROVIDER PUBLISHES, AND WHERE THAT PUBLICATION IS ALLOWED TO END UP.
##
## The unit under test is the SEAM, not the arithmetic. `test_element_provider.gd` already
## pins what one element's resistance is worth, and `test_element_wiring.gd` already pins
## that a factory actor derives non-zero power — so a provider that computed perfectly
## while contributing nothing to a stat surface was green in both.
##
## ## The defect this suite exists for
##
## `ItemWorkbenchApp.restore_actor` re-mounted every module that CONTRIBUTES to a restored
## hero except the element provider: it called `ElementsApi.apply_realm_modifiers`, which
## writes the realm `MULT` onto `element_power_<e>` and touches nothing else. Core never
## serializes a `StatProvider`, so `Actor.from_dict` handed back a body with no provider at
## all. The surface then looked half-alive:
##
##   - `element_power_<e>` WAS on `derived_all()`, because `ActorStats._recompute` backs
##     every modifier bucket at `0.0` — a multiplier on nothing still publishes a key;
##   - `element_defense_<e>` was NOT, because no modifier ever names it;
##   - `derived(element_power_<e>)` read `0.0` whatever affinity the body held.
##
## Five of the seven red assertions in `tests/app/test_body_cultivation_reachability.gd`
## were the missing resistance keys and the sixth was the dead power value. So the cases
## below each pin one way that class of hole can come back:
##
##   1. the provider publishes a power AND a resistance id for every element it knows;
##   2. every id it publishes reaches `ActorStats.derived_all()`;
##   3. a stat worth `0.0` is PUBLISHED, not dropped -- an untrained hero is the case where
##      every one of these ids is zero, and a surface that filtered zeros would hide the
##      whole provider rather than report a body that has not trained;
##   4. `attach` twice is one provider and one contribution while still rewriting the realm
##      half, which is the contract that lets ONE attach list serve a fresh build, a restore
##      and a body swap (the list the restore defect lived in);
##   5. BOTH `element_power_<e>` and `element_defense_<e>` carry the same realm
##      multiplier — which is what makes ADR 0200's `D/(K+D)` realm-invariant, and what
##      stops a realm-flat defense half from leaving the elemental share of a qi hit
##      drifting down the ladder while the offense half rides it.


## A context built directly rather than borrowed from an `Actor`, so "what does the provider
## publish" is answerable without an actor at all. `StatContext`'s constructor is the
## published seam; reaching into `Actor._context` would make this suite depend on core's
## private field layout.
func _context(base: Dictionary = {}) -> StatContext:
	return StatContext.new(base, {}, NameList.new(), AffinityMap.new(), {}, {}, null)


## The published ids for one element, in the order the provider writes them: the
## power/defense pair. Deliberately NOT the ADR 0215 crit pair — the zero-reading case
## below asserts every id here reads `0.0` on an untrained body, and the crit pair has
## a non-zero BASE by design (`CRIT_BASE`).
func _ids_for(element: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.append(ElementStats.power_id(element))
	out.append(ElementStats.defense_id(element))
	return out


# --- 1. the provider publishes what the module claims it owns ----------------------


## Every element `ElementRules` names gets BOTH ids. Written over `rules.ids()` rather than
## `ElementStats.BASE_ELEMENTS` on purpose: the advanced tier is where a hand-written loop
## bound would have quietly stopped, and an element nobody measured is exactly the element
## that stops being published.
func test_the_provider_publishes_a_power_and_a_defense_id_for_every_element_it_knows() -> void:
	var rules := ElementsApi.default_rules()
	var published := ElementProvider.new(rules).contribute(_context())
	for element in rules.ids():
		for id in _ids_for(element):
			assert_eq(
				published.has(id),
				true,
				(
					"the provider publishes '%s' for %s; it published %s"
					% [id, element, str(published.keys())]
				)
			)
	# MEASURED, not asserted per element: the four ids above and nothing else is the
	# contract, plus the OMNI pairs, which the provider publishes on the same rule
	# (`ElementStats.all_ids()` carries OMNI) rather than as a special case: the crit
	# pair (ADR 0215) and the power/defense pair (ADR 0004's pure-qi channel). A stray
	# fifth id per element is a finding rather than a free extra.
	assert_eq(
		published.size(),
		rules.ids().size() * 4 + 4,
		"the provider publishes four ids per element plus the omni power/defense and crit pairs"
	)


# --- 2. what is published is what the surface carries ------------------------------


## THE SEAM. A provider's return value is the only way a module gets a stat onto an actor,
## so an id the provider published and `derived_all()` does not carry is a stat that does
## not exist — with no error anywhere. This is the case that was red.
func test_every_id_the_provider_publishes_reaches_the_stat_surface() -> void:
	var rules := ElementsApi.default_rules()
	var published := ElementProvider.new(rules).contribute(_context({Stat.WILL: 10.0}))
	var actor := Actor.new(&"published", {Stat.WILL: 10.0})
	ElementsApi.attach(actor, rules)
	var surface := actor.stats.derived_all()
	for id in published.keys():
		assert_eq(
			surface.has(id),
			true,
			(
				"the provider published '%s' and the stat surface does not carry it; it carries %s"
				% [id, str(surface.keys())]
			)
		)
	# Non-vacuous: the surface really does carry provider keys, or the loop above would
	# pass on an empty `published` map.
	assert_eq(published.size() > 0, true, "the provider published something for this map to check")


## The same claim through the COMPOSITION ROOT rather than a hand-attached actor, because the
## restore defect was invisible to `Actor.new`: the factory mounts the provider, and only
## `restore_actor` skipped it. A suite that only ever mints through the factory would still
## have been green.
func test_a_factory_built_hero_carries_every_published_element_id() -> void:
	var actor := ActorFactory.build(&"publication")
	var surface := actor.stats.derived_all()
	for element in ElementsApi.default_rules().ids():
		for id in _ids_for(element):
			assert_eq(
				surface.has(id),
				true,
				"a factory-built hero carries '%s', which the factory mounts for everyone" % id
			)


# --- 3. a zero is a value, not an absence ------------------------------------------


## An untrained hero is the case where EVERY one of these ids is `0.0`, and it is the case
## a surface that filtered zeros would turn into a silently provider-less actor. The key must
## be present AND read `0.0`: present-at-zero is "this body has not trained", absent is "this
## module is not mounted", and only one of those is true here.
##
## `element_defense_<e>` is the id to assert on, because it is the one no realm modifier
## ever names — a bare `Actor` has no path, so `element_power_<e>` here rests entirely on
## the provider and a zero-FILTER would hide it too, but the defense id cannot be
## reproduced by the modifier-bucket backing at all.
func test_a_zero_valued_element_stat_is_published_rather_than_dropped() -> void:
	var rules := ElementsApi.default_rules()
	var actor := Actor.new(&"untrained")
	ElementsApi.attach(actor, rules)
	var surface := actor.stats.derived_all()
	for element in rules.ids():
		for id in _ids_for(element):
			assert_eq(
				surface.has(id),
				true,
				"'%s' is 0.0 on an untrained body and is still published, not dropped" % id
			)
			assert_almost_eq(
				actor.stats.derived(id),
				0.0,
				"and it reads 0.0 rather than a borrowed number",
				1e-12
			)


## The same, from the provider's own return value: a `0.0` contribution is a KEY, not a
## missing entry. `contribute` is free to omit an id — that is how an unattrained element
## would look to a caller — so the guarantee is asserted where it is actually made.
func test_the_provider_publishes_a_zero_valued_contribution_as_a_key() -> void:
	var rules := ElementsApi.default_rules()
	var published := ElementProvider.new(rules).contribute(_context())
	assert_eq(
		published.has(ElementStats.defense_id(ElementStats.WATER)),
		true,
		"an untrained body's defense is published at 0.0, not omitted"
	)
	assert_almost_eq(
		float(published[ElementStats.defense_id(ElementStats.WATER)]),
		0.0,
		"and the published value really is the zero",
		1e-12
	)


# --- 4. the verb a shared attach list can use ---------------------------------------


## `attach` twice must be ONE provider and ONE contribution. This is the guard on the
## contract that lets one attach list serve a fresh build (which already has the provider
## from `ActorFactory.build`), a restore and a body swap: without it the only safe shape was
## two different verbs, and the restore used the wrong one.
##
## Counted AND compared, and the count is the load-bearing half: a second provider
## OVERWRITES the same id with the same value rather than adding to it, so the stat reads
## identically either way and only the count can see the duplicate.
func test_attaching_twice_is_one_provider_and_one_contribution() -> void:
	var actor := Actor.new(&"twice")
	actor.set_affinity(ElementStats.FIRE, 5.0)
	ElementsApi.attach(actor)
	var once := actor.stats.provider_count()
	var power_once := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	ElementsApi.attach(actor)
	assert_eq(
		actor.stats.provider_count(),
		once,
		"a second attach mounts no second provider; `add_provider` appends unguarded, so it must"
	)
	# Asserted because it is the reason the count above is necessary: this number is the same
	# with one provider and with two, so a suite that only read the stat would be green on a
	# doubled stack and would double every landed blow's elemental share (ADR 0088).
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		power_once,
		"and the stat is unchanged by the repeat, which is exactly why the count matters",
		1e-9
	)


## The other half of the same contract: the realm half IS rewritten by a repeated attach, or
## a body that has broken through since would keep answering with the realm it left. The
## multiplier's VALUE is authored per-realm data, so this asserts the RELATIONSHIP against
## the realm the body is actually on, never a pinned figure.
func test_a_repeated_attach_still_rewrites_the_realm_multiplier() -> void:
	var actor := ActorFactory.build(&"refreshed")
	actor.set_affinity(ElementStats.FIRE, 2.0)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		2.0,
		"a bare factory actor has no path, so no realm multiplier is written yet",
		1e-9
	)
	var ladder := RealmDefaults.ladder()
	var realms := ladder.realms()
	var deepest := realms[realms.size() - 1] as RealmDef
	ActorFactory.with_qi_cultivation(actor, deepest.id)
	var after_enrolment := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_almost_eq(
		after_enrolment,
		2.0 * deepest.power,
		"enrolment wrote the authored multiplier for the realm the body is on",
		1e-6
	)
	# A second attach on a body that has already broken through must not be a no-op for the
	# realm half -- that is what made one verb able to be both "mount" and "refresh".
	ElementsApi.attach(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		after_enrolment,
		"re-attaching rewrites the realm half to the same realm rather than stacking it",
		1e-9
	)


# --- 5. both element halves are realm-scaled magnitudes -------------------------


## ADR 0200's stated open consequence, LANDED. Before it, `element_resistance_<e>` was a
## RATE and took no realm multiplier, because ADR 0069's reason was that a rate must never
## track a magnitude (ADR 0050) and scaling a defender's authored mitigation by 551.46
## would make deep-realm qi immunity automatic. ADR 0200 replaced that capped percent with
## `element_defense_<e>`, an unbounded MAGNITUDE, which dissolves the objection: a
## magnitude is exactly what the ladder SHOULD scale.
##
## This assertion was deliberately INVERTED rather than relaxed, because the old one was a
## barrier marking a known defect: it pinned `element_defense_<e>` as realm-FLAT and said
## in prose that whoever put it on the ladder "has to come here and say so, rather than
## finding a test that already agreed". This is that coming here. The defect it was holding
## the door shut on is measured in
## `tests/modules/combat_engine/test_cross_mechanism_balance.gd`: with only the offense half
## on the ladder the elemental fraction of a qi hit read `0.665043 / 0.694266 / 0.704604 /
## 0.705803` over R1 / R10 / R20 / R30 — a spread of `0.04076025` against a claimed
## invariance of `0.000001`, and the suite's own printed verdict was
## `NOT CONSTANT -- FINDING`. `K = defense_divisor_k * element_power_<e>` grew 551.46x while
## `D = element_defense_<e> / resist_divisor` stood still, so `D/(K+D)` fell toward `0.26`
## and a deep-realm defender's authored mitigation became numerical noise.
##
## The property now asserted is the PAIR, not either half alone: both scale, and by the
## SAME authored `realm.power`, because a half-scaled pair is exactly the asymmetry.
func test_both_element_halves_take_the_realm_multiplier() -> void:
	var ladder := RealmDefaults.ladder()
	var realms := ladder.realms()
	assert_eq(realms.is_empty(), false, "the ladder publishes realms to enrol on")
	var deepest := realms[realms.size() - 1] as RealmDef
	# Measured, so the case cannot pass vacuously on a ladder whose last realm is 1.0.
	assert_eq(
		deepest.power > 1.0,
		true,
		"the deepest realm must scale something, or this case proves nothing (%s)" % deepest.id
	)
	var actor := ActorFactory.build(&"magnitudes", {Stat.WILL: 10.0})
	actor.set_affinity(ElementStats.FIRE, 4.0)
	var defense_before := actor.stats.derived(ElementStats.defense_id(ElementStats.FIRE))
	var power_before := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_almost_eq(
		power_before, 4.0, "a bare factory actor carries no realm multiplier yet", 1e-9
	)
	# Non-vacuous on the DEFENSE half specifically. `ElementProvider` contributes
	# `affinity * 0.5 + will * 0.2`, so a `will` of 10.0 alone would put `2.0` here and a
	# zero-multiplier assertion would pass on the provider term. This measures the real
	# published figure and divides the ratio by it rather than assuming a magnitude.
	assert_eq(
		defense_before > 0.0,
		true,
		(
			"element_defense_%s is a non-zero magnitude on this actor, or the ratio below is vacuous"
			% ElementStats.FIRE
		)
	)

	ActorFactory.with_qi_cultivation(actor, deepest.id)

	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		power_before * deepest.power,
		"element_power_%s is a magnitude and takes the realm multiplier" % ElementStats.FIRE,
		1e-6
	)
	assert_almost_eq(
		actor.stats.derived(ElementStats.defense_id(ElementStats.FIRE)),
		defense_before * deepest.power,
		(
			(
				"element_defense_%s is a magnitude too and takes the SAME multiplier: "
				+ "K = defense_divisor_k * element_power and D = element_defense / resist_divisor "
				+ "only cancel while both ride the ladder (realm power %s)"
			)
			% [ElementStats.FIRE, deepest.power]
		),
		1e-6
	)
	# The PAIR is the claim, so assert the pair and not the two halves. If the defense half
	# were ever quietly moved off the ladder again this is the line that says so, and it
	# says so as a ratio of the two published magnitudes rather than as a pinned product.
	var power_ratio := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)) / power_before
	var defense_ratio := (
		actor.stats.derived(ElementStats.defense_id(ElementStats.FIRE)) / defense_before
	)
	assert_almost_eq(
		defense_ratio,
		power_ratio,
		"the two halves move by ONE factor, which is what makes D/(K+D) realm-invariant",
		1e-9
	)


## ADR 0004's pure-qi channel is a MAGNITUDE pair too, so it rides the same ladder — and
## by the SAME factor, or a pure-qi blow's mitigated fraction drifts with the realm
## exactly as the per-element pair's would. The omni ids are not in `rules.ids()`, so
## this is the case that catches a ladder write that forgot them.
func test_the_omni_pair_takes_the_same_realm_multiplier() -> void:
	var realms := RealmDefaults.ladder().realms()
	var deepest := realms[realms.size() - 1] as RealmDef
	var actor := ActorFactory.build(&"omni_magnitudes")
	actor.set_affinity(ElementStats.FIRE, 4.0)
	actor.set_affinity(ElementStats.WATER, 2.0)
	var power_before := actor.stats.derived(ElementStats.power_id(ElementStats.OMNI))
	var defense_before := actor.stats.derived(ElementStats.defense_id(ElementStats.OMNI))
	assert_eq(power_before > 0.0, true, "the summed affinity publishes a non-zero omni power")
	assert_eq(defense_before > 0.0, true, "and a non-zero omni defense")
	ActorFactory.with_qi_cultivation(actor, deepest.id)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.OMNI)),
		power_before * deepest.power,
		"the omni power rides the ladder",
		1e-6
	)
	assert_almost_eq(
		actor.stats.derived(ElementStats.defense_id(ElementStats.OMNI)),
		defense_before * deepest.power,
		"and so does the omni defense, by the same factor",
		1e-6
	)
	# The strip half: `RealmScaling.apply` clears the source tag wholesale, so the omni
	# pair must be on the owned list or a breakthrough leaves a stale multiplier behind.
	RealmScaling.apply(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.OMNI)),
		power_before,
		"the breakthrough clears the omni power's multiplier",
		1e-9
	)


## The reset half of the same contract, and the one a breakthrough exercises: `RealmScaling`
## clears the shared `realm` source tag WHOLESALE, so a body that breaks through without
## re-running `apply_realm_modifiers` would keep answering with the realm it left on BOTH
## halves. Asserted through the exact call order
## `test_cross_mechanism_balance.gd::_stand_at` documents, because the danger is not the
## multiplier — it is a stale one surviving on the defense half alone.
func test_both_element_halves_are_rewritten_after_realm_scaling_clears_the_source() -> void:
	var realms := RealmDefaults.ladder().realms()
	var shallow := realms[0] as RealmDef
	var deepest := realms[realms.size() - 1] as RealmDef
	# The BARE magnitudes, read before any realm is enrolled: a bare factory actor has no
	# path, so `apply_realm_modifiers` writes nothing and these are the provider's own
	# figures. Non-vacuous for the same reason as the case above.
	var bare := ActorFactory.build(&"bare", {Stat.WILL: 10.0})
	bare.set_affinity(ElementStats.FIRE, 4.0)
	var power_bare := bare.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	var defense_bare := bare.stats.derived(ElementStats.defense_id(ElementStats.FIRE))
	assert_eq(defense_bare > 0.0, true, "the bare defense magnitude is non-zero to divide by")

	var actor := ActorFactory.build(&"wiped", {Stat.WILL: 10.0})
	actor.set_affinity(ElementStats.FIRE, 4.0)
	actor.set_path(PathState.new(PathState.QI, shallow.id))
	RealmScaling.apply(actor)
	ElementsApi.apply_realm_modifiers(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.defense_id(ElementStats.FIRE)),
		defense_bare * shallow.power,
		"the defense half carries the shallow realm's multiplier",
		1e-6
	)

	# The breakthrough: `RealmScaling.apply` sweeps `realm`-sourced modifiers off BOTH
	# halves, then the element module re-writes its own. Anything left behind here would be
	# a stale MULT the defense half kept and the power half lost.
	actor.set_path(PathState.new(PathState.QI, deepest.id))
	RealmScaling.apply(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		power_bare,
		"RealmScaling cleared the power half's multiplier rather than rewriting it",
		1e-9
	)
	assert_almost_eq(
		actor.stats.derived(ElementStats.defense_id(ElementStats.FIRE)),
		defense_bare,
		"and it cleared the DEFENSE half's multiplier too, which is what a single source tag means",
		1e-9
	)
	ElementsApi.apply_realm_modifiers(actor)
	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		power_bare * deepest.power,
		"and the re-write restores the deepest realm on the power half",
		1e-6
	)
	assert_almost_eq(
		actor.stats.derived(ElementStats.defense_id(ElementStats.FIRE)),
		defense_bare * deepest.power,
		"and on the defense half too — neither is left holding a stale multiplier",
		1e-6
	)
