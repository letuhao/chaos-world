extends RefCounted

## Not a suite: the runner only collects `test_*.gd`, so this helper is named to
## sit outside discovery.
##
## Shared fixtures for the Mind path's reachability audit. Both audit suites ask
## the same two questions of every one of the 29 boundaries — is each demand
## reachable from a source-realm pre-state, and is each demand actually
## discriminating — so they share how to build a bare actor, how to prepare one
## through production actions, and how to read the gate inputs `preview` reports.

## The ladder has 30 realms, so there are 29 boundaries between them.
const BOUNDARY_COUNT := 29


## An actor at `rank_id` with the module and the sea attached and nothing earned.
static func fresh_actor(rank_id: StringName) -> Actor:
	var actor := Actor.new(
		&"reachability_hero",
		{Stat.COMPREHENSION: 0.0, Stat.WILL: 0.0, MindStats.SEA_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	actor.meridians.unlock_for_realm(rank_id)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 500)
	MindTraining.synchronize(actor)
	return actor


## The gate inputs `preview` reports for the realm after `rank_id`, read from the
## module rather than restated from the seeds.
static func gates_at(rank_id: StringName) -> Dictionary:
	var gates: Variant = MindAdvancement.preview(fresh_actor(rank_id)).get("gates", {})
	return gates if gates is Dictionary else {}


## The strongest pre-state a player standing in `rank_id` can hold, reached only
## through the production actions: the source realm's sea and channel milestones
## completed, then the target's progress budget and comprehension floor earned by
## cultivation, then the sea topped up.
static func prepared(rank_id: StringName) -> Actor:
	var actor := fresh_actor(rank_id)
	var state := actor.path(MindPath.PATH_ID)
	var target := RealmDefaults.ladder().next(rank_id)
	var source_seed := MindRealmSeed.for_realm(rank_id)
	var target_seed := MindRealmSeed.for_realm(target.id)
	stock(actor, source_seed.sea_catalyst)
	MindTraining.strengthen_sea(actor)
	stock(actor, source_seed.training_item)
	var wanted: int = MeridianState.STATE_ORDER.get(source_seed.required_channel_state, 0)
	for meridian_id in source_seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			continue
		while MeridianState.STATE_ORDER.get(channel.state, 0) < wanted:
			stock(actor, source_seed.training_item)
			if not MindTraining.train_channel(actor, meridian_id):
				break
			channel = actor.meridians.get_meridian(meridian_id)
	var sea := MindCultivationApi.sea(actor)
	var guard := 0
	while (
		guard < 8192
		and (
			state.progress < target_seed.progress_required
			or actor.stats.get_base(Stat.COMPREHENSION) < target_seed.comprehension_required
		)
	):
		guard += 1
		if sea.is_full(actor):
			sea.drain(actor, sea.current(actor))
		if not MindTraining.cultivate(actor, 500.0):
			break
	while not sea.is_full(actor) and guard < 16384:
		guard += 1
		if not MindTraining.cultivate(actor, 500.0):
			break
	return actor


## Resolve a real authored item and put one in the actor's inventory. Resolving
## through the item tree is what proves the seed's content exists and loads.
static func stock(actor: Actor, def_id: StringName) -> void:
	if def_id.is_empty():
		return
	var def := Crafting.resolve(def_id)
	if def == null:
		return
	var guard := 0
	while not ItemsApi.has_item(actor, def_id) and guard < 64:
		ItemsApi.inventory(actor).add(def, 1)
		guard += 1


## One gate entry out of an actor's own `preview` report. Returned untyped because
## `channels` inside the block is an Array while every other entry is a Dictionary,
## so each caller narrows it itself.
static func gate(actor: Actor, key: String) -> Variant:
	var gates: Dictionary = MindAdvancement.preview(actor).get("gates", {})
	return gates.get(key, {})


## The `value` a gate measured, and the `required` it demands.
static func value_of(actor: Actor, key: String) -> float:
	var entry: Variant = gate(actor, key)
	return number(entry if entry is Dictionary else {}, "value")


static func required_of(actor: Actor, key: String) -> float:
	var entry: Variant = gate(actor, key)
	return number(entry if entry is Dictionary else {}, "required")


static func number(entry: Dictionary, key: String) -> float:
	var value: Variant = entry.get(key, 0.0)
	return float(value) if value is float or value is int else 0.0


## Fight the tribulation bound to `target` to a decided win, through the
## production entry points only (ADR 0041). Finishing the phases is not enough: a
## gate opens only for a decided win, so the fight must be resolved as well. A
## survivor of another realm must not stand in for this one (ADR 0032), so this is
## always fought for the realm it is being checked against.
static func fight(actor: Actor, target: RealmDef) -> void:
	if Breakthrough.tribulation_ok(actor, target.index):
		return
	if Breakthrough.begin_tribulation(actor, target.index) == null:
		return
	var guard := 0
	while Breakthrough.advance_tribulation(actor) and guard < 128:
		guard += 1
	Breakthrough.resolve_tribulation(actor, true)


## One realm's worth of the high tier, the way the real path does it: fight the
## tribulation bound to that realm, advance into it through core's own entry
## point, commit the anchor it creates, then take the resonance milestone that
## strengthens it.
static func walk_high_tier(actor: Actor, target_index: int) -> void:
	var target := realm_at(target_index)
	fight(actor, target)
	Breakthrough.try_advance(actor, MindPath.PATH_ID)
	MindAnchor.commit(actor, target_index)
	strengthen_anchor(actor)


## `MindTraining.strengthen_anchor` is the only production route to an inside
## world's strengthened stage.
static func strengthen_anchor(actor: Actor) -> void:
	var state := actor.path(MindPath.PATH_ID)
	if state == null or actor.inside_world == null:
		return
	var seed := MindRealmSeed.for_realm(state.rank_id)
	if seed == null:
		return
	stock(actor, seed.training_item)
	MindTraining.strengthen_anchor(actor)


static func realm_at(index: int) -> RealmDef:
	return RealmDefaults.ladder().realms()[index]
