extends TestCase

## BL-0287: the meridian network reaches the body provider as CORE state.
##
## `context.component(&"meridians")` returns null on every actor the game builds,
## and ADR 0057 says so: the network is `Actor.meridians`, not a module component.
## It reaches a provider as `StatContext.meridian_network()`, which `Actor._init`
## supplies and the `meridians` setter re-points on every reassignment — so a
## provider that reads the context follows the actor's live field, and one that
## captured the network would keep serving the object `Actor.from_dict` discarded.
##
## This module was the last holdout: `BodyProvider` was CONSTRUCTED with its actor
## because `StatContext` had no accessor to read. That substitute is gone. These
## tests pin the two properties it had and the one hazard ADR 0057 warns about, and
## the guard at the bottom closes the door on the substitute coming back.


func _actor() -> Actor:
	var actor := (
		Actor
		. new(
			&"meridian_reader",
			{
				Stat.PHYSIQUE: 10.0,
				BodyStats.BONE_DENSITY: 10.0,
				BodyStats.MUSCLE_FIBER: 10.0,
				BodyStats.ORGAN_VITALITY: 10.0,
			}
		)
	)
	BodyCultivationApi.attach(actor)
	return actor


func _strengthen_lung(actor: Actor) -> void:
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")


## The network is still not a module component. Registering it under another id
## would be the same second source of truth ADR 0057 removes, so this stays.
func test_the_network_is_still_not_a_module_component() -> void:
	var actor := _actor()
	assert_eq(actor.component(&"meridians"), null, "nobody registers the network")


## The substitute is not "a component under another name": nothing in the bag
## duplicates the network. The provider is the only thing attach() adds, and it is
## the provider itself that already used to be there.
func test_attach_adds_only_the_provider_and_its_own_progress_tracker() -> void:
	var actor := _actor()
	for id in actor.components.keys():
		assert_eq(
			[&"body_cultivation_provider", &"body_progress"].has(id),
			true,
			"attach added %s" % String(id)
		)


## `Actor._init` connects `meridians.changed` to the stats invalidator through the
## `meridians` setter, so a meridian mutation invalidates on its own with no body
## verb in between and no connect of this module's own. `attach` used to add that
## connect itself; it was a second place invalidating on one signal, which is the
## duplication ADR 0057 names, so `Actor` owns it alone.
##
## This is now the proof that CORE alone invalidates: the cache is warmed by the
## first read, so the second read can only exceed 15.0 if something re-dirtied it,
## and `attach` no longer contributes a connect. Were that connect load-bearing,
## deleting it turns this assertion red.
func test_a_meridian_mutation_alone_refreshes_the_body_stat() -> void:
	var actor := _actor()
	# Warm the cache, so a later read has to recompute to be correct.
	actor.mark_stats_dirty()
	assert_almost_eq(actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.0, "no channel")
	_strengthen_lung(actor)
	assert_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER) > 15.0,
		true,
		"the network paid out with no body verb in between"
	)


## The honest ABSENT case, matching the qi and mind providers: a context built
## with no network contributes no bonus and does not crash. Its number equals the
## untrained one, because an owner with no network has nothing to train.
##
## 7.5 and not the 15.0 an attached actor reports: this actor never called
## `attach`, so it carries no integrity reservoir, `integrity_factor` is the 0.5
## floor, and `(10 + 10 + 10) * 0.5 * 0.5` is what a body with no pool behind it is
## worth. The claim under test is the meridian multiplier, so the second assertion
## compares against the same actor's real context — which does carry an untrained
## network — and requires the two to agree.
func test_a_context_with_no_network_answers_the_untrained_number() -> void:
	var actor := (
		Actor
		. new(
			&"bare",
			{
				Stat.PHYSIQUE: 10.0,
				BodyStats.BONE_DENSITY: 10.0,
				BodyStats.MUSCLE_FIBER: 10.0,
				BodyStats.ORGAN_VITALITY: 10.0,
			}
		)
	)
	var context := StatContext.new(
		actor.stats.base_ref(),
		actor.resources,
		actor.traits,
		actor.affinities,
		actor.paths,
		actor.components
	)
	assert_eq(context.meridian_network(), null, "a bare context states the absence")
	var absent := float(BodyProvider.new().contribute(context)[BodyStats.BODY_CULTIVATION_POWER])
	var untrained := float(
		BodyProvider.new().contribute(actor.stats._context)[BodyStats.BODY_CULTIVATION_POWER]
	)
	assert_almost_eq(absent, 7.5, "and contributes no meridian bonus")
	assert_almost_eq(
		absent, untrained, "which is the number an untrained network gives for the same owner"
	)


## The accessor's own contract from the provider's side: what `contribute` reads
## is the network `StatContext` carries, which is the actor's live field. A
## captured or re-boxed network would fail this.
func test_the_provider_reads_the_actors_own_network() -> void:
	var actor := _actor()
	var context: StatContext = actor.stats._context
	assert_eq(context.meridian_network(), actor.meridians, "the context carries the live network")
	assert_ne(context.meridian_network(), null, "and it is not a placeholder")
	# And the provider contributes the same numbers it would through the actor,
	# which is the whole claim: no Actor was needed to reach that network.
	_strengthen_lung(actor)
	var values := BodyProvider.new().contribute(context)
	assert_almost_eq(
		float(values[BodyStats.BODY_CULTIVATION_POWER]),
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER),
		"an actor-less provider reads the same network",
		0.0001
	)


## The guard against the substitute coming back, in the form the qi/mind hazard
## called for: `BodyProvider` must be UNCONSTRUCTABLE from an Actor.
##
## Purely behavioural guards cannot see this — a provider handed an actor and one
## built bare produce identical stats, which is exactly why the substitute passed
## every suite while it was there. So this is a source scan: it asserts the
## provider names no `Actor` at all, which is what "cannot be handed one" means.
## A `BodyProvider.new(actor)` at any call site cannot compile while that holds.
func test_the_provider_cannot_be_handed_an_actor() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/body_cultivation/provider.gd")
	assert_ne(source.is_empty(), true, "the provider source is readable")
	assert_eq(_code_lines_naming(source, "Actor").size(), 0, "no code line names an Actor")
	assert_eq(_code_lines_naming(source, "_init(").size(), 0, "and the provider takes no arguments")
	# A provider really is constructible bare, which is the shape every call site
	# now uses. Assert it so the scan above cannot pass on a provider that merely
	# stopped mentioning Actor while keeping an actor-typed parameter.
	assert_eq(BodyProvider.new() != null, true, "constructible with no arguments")


## Code lines naming `token`, ignoring comments and prose. A line is CODE once its
## leading `#` is stripped, so the documentation of this rule never trips it.
func _code_lines_naming(text: String, token: String) -> Array[String]:
	var out: Array[String] = []
	for raw in text.split("\n"):
		var line: String = (raw as String).strip_edges()
		if line.begins_with("#"):
			continue
		var code := (line as String).split("#")[0]
		if code.contains(token):
			out.append(code)
	return out


## The hazard ADR 0057 names: `Actor.from_dict` REPLACES `actor.meridians`. A
## provider holding the network would keep serving the object it discarded.
##
## Two levels, and the second is the one that is actually load-bearing. Going
## through `from_dict` does NOT distinguish them — it is static and returns a new
## Actor, so the composition root's `attach` builds a fresh provider over the
## restored network either way, and capturing the network passes. Replacing the
## field on an actor that ALREADY has a provider attached is what separates them,
## and that is the shape this asserts.
func test_the_provider_follows_a_restored_network_rather_than_the_discarded_one() -> void:
	var actor := _actor()
	_strengthen_lung(actor)
	var before := actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER)
	assert_eq(before > 15.0, true, "the original network pays")

	var restored := Actor.from_dict(actor.to_dict())
	BodyCultivationApi.attach(restored)
	assert_eq(
		restored.meridians.get_power_bonus(), actor.meridians.get_power_bonus(), "power survived"
	)
	assert_almost_eq(
		restored.stats.derived(BodyStats.BODY_CULTIVATION_POWER),
		before,
		"the restored body reads the RESTORED network"
	)

	# And it is live on the new object: deepen the restored network only.
	assert_eq(restored.meridians.refine_meridian(&"lung", 2), true, "refined")
	assert_eq(
		restored.stats.derived(BodyStats.BODY_CULTIVATION_POWER) > before,
		true,
		"and the restored provider followed it"
	)
	assert_almost_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER),
		before,
		"without touching the original body"
	)


## The network swapped out from under a provider that is already attached. Mark
## the stats dirty by hand: this is about WHICH network the read resolves, not
## about invalidation (the connect in `attach` is bound to the network it saw).
func test_the_provider_never_serves_a_network_the_actor_discarded() -> void:
	var actor := _actor()
	_strengthen_lung(actor)
	var original: MeridianNetwork = actor.meridians
	var paid := original.get_power_bonus()
	assert_eq(paid > 0.0, true, "the first network pays")

	actor.meridians = MeridianNetwork.from_dict(original.to_dict())
	assert_eq(actor.meridians != original, true, "the field was replaced")
	actor.meridians.open_meridian(&"spleen")
	actor.meridians.expand_meridian(&"spleen")
	actor.meridians.strengthen_meridian(&"spleen")
	actor.mark_stats_dirty()
	# lung pays on both objects; spleen pays only on the one the actor holds. So
	# the two bonuses differ, and the exact expected value names which one the
	# provider resolved. Asserting "greater than 15" would pass either way —
	# captured-network mutation M7 caught nothing until this line.
	var captured := original.get_power_bonus()
	var live := actor.meridians.get_power_bonus()
	assert_eq(live > captured, true, "the new network pays more (%f vs %f)" % [live, captured])
	assert_almost_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER),
		15.0 * (1.0 + live),
		"the provider read the network the actor holds now",
		0.0001
	)
	assert_eq(
		is_equal_approx(
			actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER), 15.0 * (1.0 + captured)
		),
		false,
		"and not the one it discarded"
	)


## Resonance is the R19-R30 payoff and rides the same read. It is applied as a
## multiplier on the aggregate, so it must move the stat on its own account.
func test_resonance_ranks_move_the_body_stat_through_the_same_read() -> void:
	var actor := _actor()
	_strengthen_lung(actor)
	var plain := actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER)
	actor.meridians.set_resonance_rank(4)
	assert_almost_eq(actor.meridians.resonance_multiplier(), 1.2, "rank 4 is +20%")
	assert_eq(
		actor.stats.derived(BodyStats.BODY_CULTIVATION_POWER) > plain, true, "resonance paid out"
	)
