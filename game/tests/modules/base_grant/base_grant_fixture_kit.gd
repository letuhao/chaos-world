extends TestCase

## Shared kit for the `base_grant` suites. NOT a suite itself: the runner discovers
## `test_*.gd` only, so this file is never executed on its own. Both suites `extend` it
## rather than importing it, which is the repo's own precedent (`doctrine_fixture_kit.gd`,
## `domain_fixture_kit.gd`) and is why the helpers are STATIC — a subclass would otherwise
## have to reach through an instance to borrow them.
##
## It exists because the hero's base attributes are load-bearing, not decoration: the
## transfer floor is `0.0` and is REACHABLE, so `AGILITY 4.0` is what lets one suite prove
## a floor refuses and another prove the floor itself is grantable. Two copies of that
## number would let both suites pass against their own fixture.
##
## ## Why there is no teardown to write
##
## `Actor` is a `RefCounted`, not a `Node`: it holds no scene-tree reference and releases
## itself when the last reference drops, so a suite here parents nothing and frees nothing.
## `queue_free()` is banned outright in `res://src` and would be wrong here anyway — the
## headless runner drives every test from `SceneTree._initialize()`, which returns before
## the first frame, so a deferred free never runs under `tools test`.


## A hero with deliberate headroom on every attribute the suites move:
## `PHYSIQUE 10 / SPIRIT 8 / AGILITY 4` — asymmetric on purpose, so a suite cannot assume
## symmetry between what it spends and what it has.
static func hero() -> Actor:
	var actor := Actor.new(&"grantee", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0, Stat.AGILITY: 4.0})
	actor.attach_core_resources()
	return actor


## Every base attribute as `{String id: float}`, read ONCE so a caller cannot observe the
## dictionary change between two reads of the same assertion.
static func base_snapshot(actor: Actor) -> Dictionary:
	var source := actor.stats.base_dict()
	var out := {}
	# `keys()` is snapshotted by the `for` and the body writes to `out`, never to `source`,
	# so the walk terminates on the seven core attributes (INC-0002).
	for key in source.keys():
		out[String(key)] = float(source[key])
	return out


## A pool holding `amount`, so the purchase half of the gate can be exercised without
## minting one through a cultivation path.
static func pool(actor: Actor, id: StringName, amount: float) -> ResourcePool:
	var minted := ResourcePool.new(id, amount)
	actor.add_resource(minted)
	return minted


## `press` — `{gains, cost_pool, cost_amount}` — bound to `source_id`.
##
## Returned as a NEW dictionary every call because a shared mutable request is how a suite
## ends up asserting against the previous test's `source`.
static func press_request(press: Dictionary, source_id: String) -> Dictionary:
	var out := press.duplicate()
	out["source"] = source_id
	return out
