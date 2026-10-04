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
##   - `element_resistance_<e>` was NOT, because no modifier ever names it;
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
##   5. `element_resistance_<e>` carries no realm multiplier while power does, which is WHY
##      case 1's power key can survive without the provider and the resistance key cannot.


## A context built directly rather than borrowed from an `Actor`, so "what does the provider
## publish" is answerable without an actor at all. `StatContext`'s constructor is the
## published seam; reaching into `Actor._context` would make this suite depend on core's
## private field layout.
func _context(base: Dictionary = {}) -> StatContext:
	return StatContext.new(base, {}, NameList.new(), AffinityMap.new(), {}, {}, null)


## The published ids for one element, in the order the provider writes them.
func _ids_for(element: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.append(ElementStats.power_id(element))
	out.append(ElementStats.resistance_id(element))
	return out


# --- 1. the provider publishes what the module claims it owns ----------------------


## Every element `ElementRules` names gets BOTH ids. Written over `rules.ids()` rather than
## `ElementStats.BASE_ELEMENTS` on purpose: the advanced tier is where a hand-written loop
## bound would have quietly stopped, and an element nobody measured is exactly the element
## that stops being published.
func test_the_provider_publishes_a_power_and_a_resistance_id_for_every_element_it_knows() -> void:
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
	# MEASURED, not asserted per element: publishing the two ids and nothing else is the
	# contract, so a stray third id per element is a finding rather than a free extra.
	assert_eq(
		published.size(),
		rules.ids().size() * 2,
		"the provider publishes exactly two ids per element and nothing else"
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
## `element_resistance_<e>` is the id to assert on, because it is the one no realm modifier
## ever names — a bare `Actor` has no path, so `element_power_<e>` here rests entirely on
## the provider and a zero-FILTER would hide it too, but the resistance id cannot be
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
		published.has(ElementStats.resistance_id(ElementStats.WATER)),
		true,
		"an untrained body's resistance is published at 0.0, not omitted"
	)
	assert_almost_eq(
		float(published[ElementStats.resistance_id(ElementStats.WATER)]),
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


# --- 5. a rate must never track a magnitude ----------------------------------------


## ADR 0069's own reason for splitting the two channels: `element_power_<e>` is a MAGNITUDE
## and takes the realm multiplier; `element_resistance_<e>` is a RATE and takes none, because
## scaling a defender's authored resistance by the realm power would make deep-realm qi
## immunity automatic and silently.
##
## This is also the diagnostic for the restore defect. A realm multiplier alone is enough to
## put `element_power_<e>` on the surface at `0.0`, which is exactly why the power half of
## that failure looked healthy and the resistance half did not — asserted here so the next
## reader of a half-present element surface knows which half is load-bearing.
func test_element_resistance_carries_no_realm_multiplier_while_power_does() -> void:
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
	var actor := ActorFactory.build(&"rates", {Stat.WILL: 10.0})
	actor.set_affinity(ElementStats.FIRE, 4.0)
	var resistance_before := actor.stats.derived(ElementStats.resistance_id(ElementStats.FIRE))
	var power_before := actor.stats.derived(ElementStats.power_id(ElementStats.FIRE))
	assert_almost_eq(
		power_before, 4.0, "a bare factory actor carries no realm multiplier yet", 1e-9
	)

	ActorFactory.with_qi_cultivation(actor, deepest.id)

	assert_almost_eq(
		actor.stats.derived(ElementStats.power_id(ElementStats.FIRE)),
		power_before * deepest.power,
		"element_power_%s is a magnitude and takes the realm multiplier" % ElementStats.FIRE,
		1e-6
	)
	assert_almost_eq(
		actor.stats.derived(ElementStats.resistance_id(ElementStats.FIRE)),
		resistance_before,
		(
			(
				"element_resistance_%s is a rate and takes none: scaling it by %s would make "
				+ "deep-realm qi immunity automatic"
			)
			% [ElementStats.FIRE, deepest.power]
		),
		1e-9
	)
