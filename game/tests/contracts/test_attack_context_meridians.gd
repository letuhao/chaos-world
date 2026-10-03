extends TestCase

## ADR 0057 at the combat seam. `AttackContext._as_context` duck-types an object
## that exposes `Actor`'s public collections, and its own docstring has always
## listed `meridians` among them — but the build passed only six arguments, so
## every context the spine produced answered `meridian_network() == null`.
##
## The failure is silent and total: a mechanism reading `ctx.attacker.meridian_network()`
## got null, the read fell to 0.0, and a trained meridian network bought nothing.
## Nothing anywhere today reads it, which is why it stayed invisible.


## A source that is deliberately NOT an `Actor`: it carries the five collections
## `_as_context` needs and no `meridians` property at all. This is the honest
## absent case, and it must stay null rather than be invented.
class NetworklessSource:
	extends RefCounted

	var traits: NameList
	var affinities: AffinityMap
	var paths: Dictionary = {}
	var components: Dictionary = {}
	var resources: Dictionary = {}

	func _init() -> void:
		traits = NameList.new()
		affinities = AffinityMap.new()


func _actor() -> Actor:
	var actor := Actor.new(&"attacker", {Stat.APTITUDE: 10.0})
	actor.meridians.unlock_for_realm(&"qi_refining")
	actor.meridians.open_meridian(&"lung")
	actor.meridians.expand_meridian(&"lung")
	actor.meridians.strengthen_meridian(&"lung")
	return actor


## The runtime assertion. Not "the accessor exists" — the accessor existed before
## this fix and the seam still answered null. The assertion is that the context the
## spine builds carries the attacker's ACTUAL, TRAINED network.
func test_a_duck_typed_source_carries_its_own_network() -> void:
	var actor := _actor()
	var ctx := AttackContext.new(actor, actor)
	assert_ne(ctx.attacker, null, "the attacker side was built")
	var carried: Variant = ctx.attacker.meridian_network()
	assert_eq(carried, actor.meridians, "and carries the live network")
	# Bound to a Variant first: calling through a null would abort the whole test
	# mid-function and report nothing, which is how a broken seam can look like a
	# passing one that simply stopped.
	if carried != null:
		assert_ne(carried.get_power_bonus(), 0.0, "and it is the trained one, not a stub")
	else:
		assert_eq(true, false, "and it is the trained one, not a stub")


func test_both_sides_get_their_own_network() -> void:
	var attacker := _actor()
	var target := Actor.new(&"target", {Stat.APTITUDE: 10.0})
	target.meridians.unlock_for_realm(&"qi_refining")
	target.meridians.open_meridian(&"lung")
	var ctx := AttackContext.new(attacker, target)
	assert_eq(ctx.attacker.meridian_network(), attacker.meridians, "attacker side")
	assert_eq(ctx.target.meridian_network(), target.meridians, "target side")
	assert_ne(
		ctx.attacker.meridian_network(),
		ctx.target.meridian_network(),
		"and the two sides are not the same object"
	)


## It is passed through LIVE, not reconstructed from the component bag. The bag
## is the lookup ADR 0057 forbids, and it is empty for every actor the game
## builds — so a copy taken from it would be null even now.
func test_the_network_is_not_reconstructed_from_the_component_bag() -> void:
	var actor := _actor()
	assert_eq(actor.component(&"meridians"), null, "the bag has no meridians entry")
	var ctx := AttackContext.new(actor, actor)
	assert_ne(ctx.attacker.meridian_network(), null, "so the bag is not where it came from")


## The absent case, stated rather than papered over. A source with no `meridians`
## property yields a context that says so, and the caller is the only place that
## can tell it apart from a network nobody trained.
func test_a_source_without_a_network_yields_the_honest_null() -> void:
	var source := NetworklessSource.new()
	var ctx := AttackContext.new(source, null)
	assert_ne(ctx.attacker, null, "the collections were enough to build a context")
	assert_eq(ctx.attacker.meridian_network(), null, "and it states the absence")


## A `StatContext` handed in directly is returned as-is: the seam never
## overwrites a context the caller already owns, meridians field included.
func test_a_direct_stat_context_is_passed_through_untouched() -> void:
	var actor := _actor()
	var supplied := StatContext.new(
		actor.stats.base_ref(),
		actor.resources,
		actor.traits,
		actor.affinities,
		actor.paths,
		actor.components
	)
	var ctx := AttackContext.new(supplied, null)
	assert_eq(ctx.attacker, supplied, "the same object comes back")
	assert_eq(ctx.attacker.meridian_network(), null, "and its own null is not overwritten")


## The seam hands mechanisms `ctx.attacker`, and that is the read a mechanism is
## meant to make. It must be reachable through the same accessor a provider uses,
## so there is exactly one way to get a network out of a stat read.
func test_a_mechanism_reads_the_network_through_the_one_accessor() -> void:
	var actor := _actor()
	var ctx := AttackContext.new(actor, actor)
	var seen: Variant = ctx.attacker.meridian_network()
	assert_eq(seen, actor.meridians, "one accessor, one answer, on both sides of the seam")
