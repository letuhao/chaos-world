extends RefCounted

## Not a suite: the runner only collects `test_*.gd`, so this helper is named to
## sit outside discovery.
##
## Shared fixtures for the Mind path's reachability audit. Both audit suites ask
## the same two questions of every one of the 29 boundaries — is each demand
## reachable from a source-realm pre-state, and is each demand actually
## discriminating — so they share how to build a bare actor, how to prepare one
## through the production actions, and how to read the gate inputs `preview`
## reports.
##
## It is also where every WAIT in the Mind tests lives. A `while` on game state
## with no bound is what wrote a 1 GB/s Godot log onto the user's disk: the
## condition it waits on was unreachable, so the loop spun forever. Each wait
## below therefore names the condition it is waiting on, bounds it at a small
## count, and returns whether the condition was met, so a gate that cannot be
## satisfied fails an assertion instead of hanging.
## `test_mind_deviation_recovery.gd` fails the build if an unbounded `while`
## comes back into this directory.

## The ladder has 30 realms, so there are 29 boundaries between them.
const BOUNDARY_COUNT := 29

# --- Bounds, and the condition each one names --------------------------------

## A reservoir holds at most R30's authored 825, so a full sea is reached in a
## couple of sittings whatever work a sitting is sized to. The bound is a canary
## for "the fill stopped converging", not a budget to spend.
const FILL_BOUND := 4

## Same for the progress budget and the comprehension floor: one sitting sized
## to the whole gate clears both, so this is that sitting plus slack.
const GATE_BOUND := 4

## `meditate` steps by the facade's own 0.1 and a deviation clouds the sea by
## 0.5, so a clouded sea needs five presses. The bound is that plus slack.
const CALM_BOUND := 8

## A channel climbs the four-state ladder one state per elixir, so a channel at
## the bottom needs three. The bound is that plus the one that confirms it.
const CLIMB_BOUND := 4

## At most nine waves (Tribulation.WAVES_BY_TIER) plus the warning and aftermath
## phases. The bound names a wave that would stop advancing.
const TRIBULATION_BOUND := 16

## Authored item defs resolved once. `Crafting.resolve` falls through to a
## recursive scan of the whole item content tree whenever the id does not sit in
## the category its prefix implies, so an uncached resolve per stocking call turns
## a 30-realm audit into minutes of directory walking.
static var _defs: Dictionary = {}


## The work one `cultivate` call must do to earn a realm's whole entry gate: its
## progress budget, or the insight that budget's comprehension floor needs.
##
## Insight is `INSIGHT_RATE` per unit of work TIMES core's `Stat.INSIGHT_GAIN`
## (BL-0165), and `INSIGHT_GAIN` is `1.0 + comprehension * 0.01` — so the real
## rate rises as the floor is approached. This deliberately prices the insight
## side with the FLOOR term alone, which is `INSIGHT_GAIN == 1.0`: an UPPER bound
## on the work the floor needs. Over-earning is safe for a fixture (the gate is
## met sooner than the estimate says) whereas under-earning is what produced an
## unreachable-gate report, so the bound is taken in the one direction that cannot
## hide a stall. It is also what makes BL-0153 measurable rather than asserted: the
## two terms are compared in the same units here, and
## `test_mind_gate_binding.gd` re-measures the crossover through the production
## action instead of trusting this estimate.
static func gate_work(target_seed: MindRealmSeed) -> float:
	# Both sides of the gate are denominated in REALM RATE, not in the work one
	# `cultivate` call is handed: `gain = amount * RealmRate.factor(rank)`.
	# A sitting sized to the raw budget therefore under- or over-ears by the rate,
	# which is how this fixture ended up reporting a progress shortfall on a gate
	# that is in fact reachable — the standing guard treats that as unreachable.
	# `NEUTRAL` is the documented 1.0 for a realm off the ladder, so this never
	# divides by zero and never invents a rate the module does not publish.
	var rate := RealmRate.factor(target_seed.id)
	return maxf(
		target_seed.progress_required / rate,
		target_seed.comprehension_required / (MindTraining.INSIGHT_RATE * rate)
	)


# --- Actors -----------------------------------------------------------------


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


## The strongest pre-state a player standing in `rank_id` can hold, reached only
## through the production actions: the source realm's sea and channel milestones
## completed, then the target's progress budget and comprehension floor earned by
## cultivation, then the sea topped up.
##
## Nothing here reaches past the facade to drain the sea or hand-write progress.
## It used to, and that is exactly how a stalled path stayed green: the fixtures
## were doing the player's job, so a gate no player could satisfy still measured
## as satisfied.
##
## The waits report whether they converged, but this returns the actor either
## way: the audit suites assert the resulting gate values themselves, so a
## prepare that could not finish surfaces there as "the progress budget for X is
## earned while in Y" rather than as a null dereference.
static func prepared(rank_id: StringName) -> Actor:
	var actor := fresh_actor(rank_id)
	var target := RealmDefaults.ladder().next(rank_id)
	var source_seed := MindRealmSeed.for_realm(rank_id)
	stock(actor, source_seed.sea_catalyst)
	MindCultivationApi.strengthen_sea(actor)
	train_channels(actor, source_seed)
	sharpen_sea(actor)
	earn_gate(actor, MindRealmSeed.for_realm(target.id))
	fill_sea(actor)
	return actor


# --- Bounded waits ----------------------------------------------------------


## Cultivate until the reservoir is full. `is_full` is the condition, and the
## bound is a canary for it.
static func fill_sea(actor: Actor) -> bool:
	var sea := MindCultivationApi.sea(actor)
	if sea == null:
		return false
	var waited := 0
	while not sea.is_full(actor) and waited < FILL_BOUND:
		waited += 1
		if not MindTraining.cultivate(actor, work_for(actor)):
			return false
	return sea.is_full(actor)


## Cultivate until the target realm's progress budget AND comprehension floor are
## both met — the two gates only cultivation moves. Sized so one sitting covers
## both, because a test is not a UI pressing a fixed step thousands of times.
static func earn_gate(actor: Actor, target_seed: MindRealmSeed) -> bool:
	var state := actor.path(MindPath.PATH_ID)
	if state == null or target_seed == null:
		return false
	var work := gate_work(target_seed)
	var waited := 0
	while (
		waited < GATE_BOUND
		and (
			state.progress < target_seed.progress_required
			or actor.stats.get_base(Stat.COMPREHENSION) < target_seed.comprehension_required
		)
	):
		waited += 1
		if not MindTraining.cultivate(actor, work):
			return false
	return (
		state.progress >= target_seed.progress_required
		and actor.stats.get_base(Stat.COMPREHENSION) >= target_seed.comprehension_required
	)


## Meditate until the sea is calm again. `turbulence` is the condition.
static func calm_sea(actor: Actor) -> bool:
	var sea := MindCultivationApi.sea(actor)
	if sea == null:
		return false
	var waited := 0
	while sea.turbulence > 0.0 and waited < CALM_BOUND:
		waited += 1
		if not MindCultivationApi.meditate(actor):
			return false
	return sea.turbulence <= 0.0


## Train every channel the source realm demands to its demanded state. A burned
## channel is REPAIRED, not trained, and the repair is priced by the realm's
## `recovery_item` rather than its `training_item`: `MindTraining.train_channel`
## hands a burn to `recover` because that is what the seed authors it for
## (ADR 0031). `meets` fails on the injury flag alone, so the repair is a step of
## its own and it is a step the fixture has to PAY for — stocking the channel
## elixir here left the repair unreachable and the whole audit reporting a gate as
## unmet for a reason that was the fixture's own. `required_channel_state` is the
## condition.
static func train_channels(actor: Actor, source_seed: MindRealmSeed) -> bool:
	var state := actor.path(MindPath.PATH_ID)
	if state == null or source_seed == null:
		return false
	actor.meridians.unlock_for_realm(state.rank_id)
	var target: int = MeridianState.STATE_ORDER.get(source_seed.required_channel_state, 0)
	for meridian_id in source_seed.required_meridians:
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			return false
		if channel.is_injured():
			stock(actor, source_seed.recovery_item)
			if not MindCultivationApi.train_channel(actor, meridian_id):
				return false
			channel = actor.meridians.get_meridian(meridian_id)
		for _climb in CLIMB_BOUND:
			if channel.state_rank() >= target:
				break
			stock(actor, source_seed.training_item)
			if not MindCultivationApi.train_channel(actor, meridian_id):
				return false
			channel = actor.meridians.get_meridian(meridian_id)
		if not channel.meets(source_seed.required_channel_state):
			return false
	return true


## Cultivate until clarity and purity have both reached the realm the actor is
## standing in's own milestones — the two a deviation degrades and the sea's entry
## gate reads. A deviation halves clarity; cultivation is the one action that
## lifts it back, and that is what makes a deviation recoverable without a higher
## realm.
static func sharpen_sea(actor: Actor) -> bool:
	var sea := MindCultivationApi.sea(actor)
	var state := actor.path(MindPath.PATH_ID)
	if sea == null or state == null:
		return false
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	if source_seed == null:
		return false
	var work := work_for(actor)
	var waited := 0
	while (
		waited < GATE_BOUND
		and (sea.clarity < source_seed.clarity_required or sea.purity < source_seed.purity_required)
	):
		waited += 1
		if not MindTraining.cultivate(actor, work):
			return false
	return sea.clarity >= source_seed.clarity_required and sea.purity >= source_seed.purity_required


## The work for one sitting against the gate the actor currently stands before:
## the next realm's whole budget, or this realm's own when there is no next.
static func work_for(actor: Actor) -> float:
	var state := actor.path(MindPath.PATH_ID)
	if state == null:
		return 0.0
	var ladder := RealmDefaults.ladder()
	var target := ladder.next(state.rank_id)
	if target != null:
		return gate_work(MindRealmSeed.for_realm(target.id))
	var source_seed := MindRealmSeed.for_realm(state.rank_id)
	return 0.0 if source_seed == null else source_seed.progress_required


# --- Reading the gates ------------------------------------------------------


## The gate inputs `preview` reports for the realm after `rank_id`, read from the
## module rather than restated from the seeds.
static func gates_at(rank_id: StringName) -> Dictionary:
	var gates: Variant = MindAdvancement.preview(fresh_actor(rank_id)).get("gates", {})
	return gates if gates is Dictionary else {}


## Resolve a real authored item and put one in the actor's inventory. Resolving
## through the item tree is what proves the seed's content exists and loads.
##
## Cached, and the cache is load-bearing rather than tidy: `Crafting.resolve`
## falls through to a recursive scan of the whole item content tree whenever the
## id does not sit in the category its prefix implies, so an uncached resolve per
## stocking call turns a 30-realm audit into minutes of directory walking.
static func stock(actor: Actor, def_id: StringName) -> void:
	if def_id.is_empty():
		return
	var def := _def(def_id)
	if def == null:
		return
	for _unit in 64:
		if ItemsApi.has_item(actor, def_id):
			return
		ItemsApi.inventory(actor).add(def, 1)


static func _def(def_id: StringName) -> ItemDef:
	if _defs.has(def_id):
		return _defs[def_id]
	var resolved := Crafting.resolve(def_id)
	_defs[def_id] = resolved
	return resolved


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


# --- High tier --------------------------------------------------------------


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
	for _wave in TRIBULATION_BOUND:
		if not Breakthrough.advance_tribulation(actor):
			break
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
	MindCultivationApi.strengthen_anchor(actor)


static func realm_at(index: int) -> RealmDef:
	return RealmDefaults.ladder().realms()[index]


# --- Reading the module's own source -----------------------------------------


## One module file's CODE, with every whole-line `#` comment removed.
##
## The guards that read source look for a declaration or an emitted id, and a
## docblock explaining WHY an id was deleted necessarily spells that id out. A raw
## `contains()` is then failed by the very comment documenting the fix, which is
## how a guard gets deleted instead of the code. Stripping comment lines keeps the
## guard pointed at code, which is what it is for. Comment TAILS on a code line
## are left alone: they can hide a re-planted id, and none of this module's own
## code carries one.
static func module_code(relative_path: String) -> String:
	var source := FileAccess.get_file_as_string(
		"res://src/modules/mind_cultivation/%s" % relative_path
	)
	var kept: Array[String] = []
	for line in source.split("\n"):
		if not String(line).strip_edges().begins_with("#"):
			kept.append(String(line))
	return "\n".join(kept)


## The whole module's CODE, every `.gd` file concatenated with comments stripped.
## Per-directory rather than per-file so a deleted id cannot be re-planted in a new
## file beside the one it was removed from.
static func module_code_all() -> String:
	var joined := ""
	var dir := DirAccess.open("res://src/modules/mind_cultivation")
	if dir == null:
		return joined
	for file_name in dir.get_files():
		var file := String(file_name)
		if file.ends_with(".gd"):
			joined += module_code(file)
	return joined
