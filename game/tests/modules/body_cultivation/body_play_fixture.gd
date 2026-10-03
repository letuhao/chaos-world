class_name BodyPlayFixture
extends RefCounted

## Play-only harness for the body-cultivation suite.
##
## It builds an actor and brings it to the brink of the next realm through the
## same public actions a screen calls: `cultivate`, `meditate`, `strengthen`,
## `recover`, and the breakthrough itself. It never writes a stat, a channel
## state, a refinement depth, a huyệt quality, or a progress value directly —
## hand-written preparation is what let every gate in
## `BodyBreakthroughCondition` go untested, because a prepared actor satisfies
## a gate by construction and no gate is ever seen refusing.
##
## It deliberately asserts NOTHING. An `assert_eq` inside a `while` turns a
## non-converging preparation into hundreds of identical failures; here a loop
## that cannot converge simply stops, and the calling suite's own assertion on
## the resulting gate is the single, located failure.

## Every loop below is bounded and the cap names the condition that failed to
## converge. None of these is "large enough that it will probably get there".
const MAX_CHANNEL_STEPS := 256  # one channel to the realm cap, plus its huyệt
const MAX_CULTIVATE_STEPS := 2048  # work budget at the shallowest authored rate
const MAX_MEDITATE_STEPS := 8192  # deepest authored insight floor at the slowest gain
const MAX_RECOVERY_STEPS := 64  # one wound per channel, per meridian
const MAX_TRIBULATION_WAVES := 64  # waves the authored tribulation can spend
const MAX_ATTEMPTS := 96  # rolls at the authored floor chance before giving up

## Bodies share one inventory, and a full 30-realm run keeps a pill plus an
## elixir stack per realm, so the default slot count runs dry mid-ladder.
const INVENTORY_SLOTS := 128

var _defs: Dictionary = {}


## A body cultivator with the module, its huyệt set, and an inventory attached,
## at `at_realm`. The starting physique is the only authored number here: it is
## the actor's base stat, not a gate outcome.
func actor(at_realm: StringName = &"qi_refining", physique: float = 20.0) -> Actor:
	var actor := Actor.new(&"gate_hero", {Stat.PHYSIQUE: physique})
	actor.set_path(PathState.new(BodyPath.PATH_ID, at_realm))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, INVENTORY_SLOTS)
	BodyTraining.synchronize(actor)
	return actor


## Top the actor up on one consumable. The quantity is far below `max_stack` so
## a restock never burns a fresh inventory slot and starves the later realms.
func stock(actor: Actor, def_id: StringName) -> void:
	if def_id == &"":
		return
	var def: ItemDef = _defs.get(def_id)
	if def == null:
		def = ItemDef.new()
		def.id = def_id
		def.stackable = true
		def.max_stack = 9999
		_defs[def_id] = def
	var inventory := ItemsApi.inventory(actor)
	if inventory != null:
		inventory.add(def, 4)


func seed_for(actor: Actor) -> BodyRealmSeed:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return null
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	return BodyRealmSeed.for_realm(target.id)


func reservoir(actor: Actor) -> ResourcePool:
	return actor.resource(BodyStats.BODY_INTEGRITY)


## Whether the shared reservoir is filled to its ceiling.
func reservoir_full(actor: Actor) -> bool:
	var pool := reservoir(actor)
	return pool != null and pool.maximum > 0.0 and pool.ratio() >= 1.0


## Any huyệt the actor HOLDS that is still short of `quality`.
##
## Blocked points are excluded on purpose: `cultivate` skips them, so asking
## about one would be asking a question no number of cultivate steps can answer.
## The gate in `BodyBreakthroughCondition` reads their quality regardless, which
## is precisely what the deviation/recovery test below pins.
func quality_below(actor: Actor, quality: float) -> bool:
	for point in BodyCultivationApi.acupoints(actor):
		if not point.blocked and point.quality < quality:
			return true
	return false


## Close every recoverable overlay a failed attempt left behind, through the
## one public action that clears it. A body that cannot be repaired here would
## deadlock the next realm, so this is a load-bearing part of the play loop and
## not a convenience.
func recover_damage(actor: Actor) -> void:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return
	var current := BodyRealmSeed.for_realm(state.rank_id)
	if current == null or current.recovery_item == &"":
		return
	var steps := 0
	while steps < MAX_RECOVERY_STEPS:
		steps += 1
		var target: StringName = &""
		for point in BodyCultivationApi.acupoints(actor):
			if point.blocked:
				var meridian_id := AcupointDefaults.meridian_of(point.id)
				if meridian_id != &"":
					target = meridian_id
					break
		if target == &"":
			for def in MeridianDefaults.all():
				var channel := actor.meridians.get_meridian(def.id)
				if channel != null and channel.is_injured():
					target = def.id
					break
		if target == &"":
			return
		stock(actor, current.recovery_item)
		if not BodyTraining.recover(actor, target):
			return


## Train one channel to `depth_cap` (or the target realm's `required_refinement`
## when it is negative), and the huyệt bound to it up to the current realm's
## ceiling. Only `BodyTraining.strengthen` is used, so elixir cost, injury
## repair, and huyệt training all behave as in play.
##
## A non-negative `depth_cap` switches the huyệt pass off. `strengthen` refines
## and trains huyệt in the SAME call, so a channel trained "to depth and no
## further" is not reachable through it — the fourth call both refines one step
## and lifts a huyệt. That mode exists for the depth-gate test, which needs a
## channel that is `strengthened` and one step short.
func train_channel(
	actor: Actor, meridian_id: StringName, target: BodyRealmSeed, depth_cap: int = -1
) -> void:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return
	var current := BodyRealmSeed.for_realm(state.rank_id)
	if current == null:
		return
	var depth := target.required_refinement if depth_cap < 0 else depth_cap
	var wants_points := depth_cap < 0
	var steps := 0
	while steps < MAX_CHANNEL_STEPS:
		steps += 1
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			actor.meridians.unlock_for_realm(state.rank_id)
			channel = actor.meridians.get_meridian(meridian_id)
			if channel == null:
				return
		var trained: bool = (
			not channel.is_injured()
			and channel.state == &"strengthened"
			and channel.refinement >= depth
		)
		if (
			trained
			and (
				not wants_points
				or not _channel_points_below(actor, meridian_id, current.quality_target)
			)
		):
			return
		stock(actor, current.strengthening_item)
		if not BodyTraining.strengthen(actor, meridian_id):
			return


func _channel_points_below(actor: Actor, meridian_id: StringName, quality: float) -> bool:
	for definition in AcupointDefaults.definitions():
		if definition.meridian_id != meridian_id:
			continue
		for point in BodyCultivationApi.acupoints(actor):
			if point.id == definition.id and (point.blocked or point.quality < quality):
				return true
	return false


## Cultivate until the work budget is paid, the reservoir is full, and every
## huyệt the realm has unlocked has reached the target realm's quality floor.
## All three are outputs of the same action and the gate checks all three, so
## the preparation must too.
func cultivate_until(actor: Actor, progress_required: float, quality_required: float) -> void:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return
	var steps := 0
	while steps < MAX_CULTIVATE_STEPS:
		if (
			state.progress >= progress_required
			and reservoir_full(actor)
			and not quality_below(actor, quality_required)
		):
			return
		steps += 1
		if not BodyTraining.cultivate(actor, BodyCultivationApi.STEPS["cultivate"]):
			return


## Meditation is the only source of comprehension, so the insight floor is
## reached by meditating and never by writing the stat.
func meditate_to(actor: Actor, insight_required: float) -> void:
	var steps := 0
	while (
		steps < MAX_MEDITATE_STEPS and actor.stats.get_base(Stat.COMPREHENSION) < insight_required
	):
		steps += 1
		BodyTraining.meditate(actor, BodyCultivationApi.STEPS["meditate"])


## Satisfy the tier gates the target realm adds.
##
## Everything except the tribulation is COMMITTED by the breakthrough itself
## (ADR 0032, and `WorldAnchor.commit` finishes the ascension when the
## Transcendent tier lands), so there is nothing to walk here — writing an
## inside world, a created world, or an ascension record is exactly what made
## R19-R30 unreachable in play. The tribulation is the one prerequisite the
## actor has to fight, and it is fought through the production entry points.
func satisfy_tier_gates(actor: Actor, target: RealmDef) -> void:
	if target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
		return
	if Breakthrough.tribulation_ok(actor, target.index):
		return
	if Breakthrough.begin_tribulation(actor, target.index) == null:
		return
	var waves := 0
	while waves < MAX_TRIBULATION_WAVES and Breakthrough.advance_tribulation(actor):
		waves += 1
	Breakthrough.resolve_tribulation(actor, true)


## Bring the actor to the brink of the next realm using only public actions.
##
## Every gate is satisfied through play, so whatever `describe_unmet` still
## reports afterwards is attributable to the one injected fault:
##   `skip_channel` — one required meridian is never trained (the channel-STATE
##     clause of `_channels_ready`).
##   `jam_point`    — one huyệt is jammed before cultivation can train it, the
##     way a deviation jams one. A blocked huyệt is skipped by `cultivate`, so
##     no number of cultivate steps raises it and the quality floor stays unmet.
##   `depth_cap`    — every required channel reaches `strengthened` but stops one
##     refinement step short (the channel-DEPTH clause of `_channels_ready`).
func prepare(
	actor: Actor, skip_channel: StringName = &"", jam_point: StringName = &"", depth_cap: int = -1
) -> BodyRealmSeed:
	var state := actor.path(BodyPath.PATH_ID)
	if state == null:
		return null
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := BodyRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	satisfy_tier_gates(actor, target)
	# Channels the target realm counts must exist before they can be trained.
	actor.meridians.unlock_for_realm(target.id)
	stock(actor, seed.breakthrough_item)
	# Recovery runs BEFORE the jam on purpose. `recover` is the only action that
	# clears a blockage, so a second pass here would silently undo the injected
	# fault and the quality gate would never be seen refusing.
	recover_damage(actor)
	if jam_point != &"":
		_jam(actor, jam_point)
	# Cultivation first: it raises the work budget, refills the reservoir, and
	# lifts every huyệt, so a channel trained afterwards is training depth and
	# nothing else. Order matters — reversing it lets the channel step be the
	# thing that pays the work budget, which hides a broken `cultivate`.
	cultivate_until(actor, seed.progress_required, seed.quality_required)
	for meridian_id in seed.required_meridians:
		if meridian_id == skip_channel:
			continue
		train_channel(actor, meridian_id, seed, depth_cap)
	meditate_to(actor, seed.insight_required)
	return seed


func _jam(actor: Actor, point_id: StringName) -> void:
	for point in BodyCultivationApi.acupoints(actor):
		if point.id == point_id:
			point.block()
			return


## The first huyệt bound to a meridian that is BOTH on the network the actor has
## unlocked AND not one the target realm requires.
##
## Both halves matter. A required meridian would be un-jammed by the channel
## training `prepare` performs, and a meridian the actor does not own yet has no
## channel to train or recover it through — so a fault placed there is not a
## fault the test can clear. Returns empty when the actor is too shallow, which
## is why the callers that need one climb first.
func unrequired_point(actor: Actor, seed: BodyRealmSeed) -> StringName:
	for point in BodyCultivationApi.acupoints(actor):
		var meridian_id := AcupointDefaults.meridian_of(point.id)
		if meridian_id == &"" or seed.required_meridians.has(meridian_id):
			continue
		if actor.meridians.get_meridian(meridian_id) != null:
			return point.id
	return &""


## Roll until the actor is standing in the next realm. Every failed attempt is
## followed by the recovery a deviation requires, which is what a player does.
func breakthrough(actor: Actor, rng: RandomNumberGenerator) -> bool:
	for _attempt in MAX_ATTEMPTS:
		if BodyAdvancement.try_breakthrough(actor, rng):
			return true
		if seed_for(actor) == null:
			return false
		prepare(actor)
	return false


## Climb from `at_realm` to `stop_at` through public actions only, so a save
## taken at the top of the ladder holds state the game can actually reach.
func climb_to(at_realm: StringName, stop_at: StringName) -> Actor:
	var actor := actor(at_realm)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20_260_301
	# One rung per iteration, and the ladder is 30 long: the cap is the whole
	# climb plus slack, not a "keep trying" budget.
	var rungs := 0
	while rungs < 40:
		rungs += 1
		var rank: StringName = actor.path(BodyPath.PATH_ID).rank_id
		if rank == stop_at or RealmDefaults.ladder().next(rank) == null:
			return actor
		if seed_for(actor) == null:
			return actor
		prepare(actor)
		if not breakthrough(actor, rng):
			return actor
	return actor


## Roll one attempt that is guaranteed to deviate.
##
## The seed is CHOSEN, not hoped for: the first draw of a seeded generator is
## known before the attempt starts, so this picks a seed whose first draw lands
## above the evaluated chance and then re-seeds a fresh generator with it.
## Sweeping seeds and hoping for a deviation instead is how a caller ends up
## asserting on a realm change — a successful breakthrough resets the work
## budget to zero and looks exactly like one.
func deviate(actor: Actor) -> bool:
	var chance := float(BodyAdvancement.preview(actor)["chance"])
	var rank: StringName = actor.path(BodyPath.PATH_ID).rank_id
	# Bounded by the seed space this sweeps, not by how long it will wait: every
	# realm authors `chance_cap` below 1.0, so 64 draws find one.
	for attempt in 64:
		var probe := RandomNumberGenerator.new()
		probe.seed = attempt + 1
		if probe.randf() < chance:
			continue
		var roll := RandomNumberGenerator.new()
		roll.seed = attempt + 1
		BodyAdvancement.try_breakthrough(actor, roll)
		return actor.path(BodyPath.PATH_ID).rank_id == rank
	return false


# --- Whole-body state: "a read changed nothing" and "a save lost nothing" ---


## Everything about a body that a read must leave alone and a save must carry,
## as plain data. `to_dict` alone is not enough: it reads the reservoir and the
## huyệt set through components, and a component that failed to serialize would
## still leave a payload that looks complete.
func snapshot(actor: Actor) -> Dictionary:
	var points := {}
	for point in BodyCultivationApi.acupoints(actor):
		points[String(point.id)] = [point.quality, point.blocked, String(point.tier)]
	var channels := {}
	for channel in actor.meridians.get_all_meridians():
		channels[String(channel.id)] = [channel.state, channel.refinement, channel.injured]
	var pool := reservoir(actor)
	var state := actor.path(BodyPath.PATH_ID)
	var progress: BodyProgress = actor.component(&"body_progress")
	return {
		"payload": actor.to_dict(),
		"points": points,
		"channels": channels,
		"resonance": actor.meridians.resonance_rank,
		"pool":
		[
			0.0 if pool == null else pool.current,
			0.0 if pool == null else pool.maximum,
			0.0 if pool == null else pool.ratio(),
		],
		"rank": &"" if state == null else state.rank_id,
		"stage": 0 if state == null else state.stage,
		"progress": 0.0 if state == null else state.progress,
		"comprehension": actor.stats.get_base(Stat.COMPREHENSION),
		"physique": actor.stats.get_base(Stat.PHYSIQUE),
		"milestones": [] if progress == null else progress.completed.duplicate(),
	}


## Recursive structural diff, so a failure names the exact field instead of
## printing two payloads. A failure message of "expected <dict>, got <dict>" is
## one nobody can act on.
func diff(left: Variant, right: Variant, path: String) -> Array[String]:
	var out: Array[String] = []
	if typeof(left) != typeof(right):
		return ["%s: %s vs %s" % [path, type_string(typeof(left)), type_string(typeof(right))]]
	if left is Dictionary:
		var before := left as Dictionary
		var after := right as Dictionary
		for key in before.keys():
			if not after.has(key):
				out.append("%s.%s: gone" % [path, key])
				continue
			out.append_array(diff(before[key], after[key], "%s.%s" % [path, key]))
		for key in after.keys():
			if not before.has(key):
				out.append("%s.%s: added" % [path, key])
		return out
	if left is Array:
		var head := left as Array
		var tail := right as Array
		if head.size() != tail.size():
			return ["%s: %d entries vs %d" % [path, head.size(), tail.size()]]
		for index in head.size():
			out.append_array(diff(head[index], tail[index], "%s[%d]" % [path, index]))
		return out
	if left != right:
		out.append("%s: %s -> %s" % [path, left, right])
	return out


## Whether any difference names `fragment`, for an assertion that has to point
## at one specific field rather than "something moved".
func names_differences(differences: Array[String], fragment: String) -> bool:
	for entry in differences:
		if entry.contains(fragment):
			return true
	return false


## A seeded generator, so an outcome is the same on every run and a failure is
## never "an unlucky stream".
static func rng(seed_value: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator


## Re-attach the modules the composition root owns when it loads a save. The
## typed huyệt set and the provider do not survive `from_dict` on their own.
static func load_save(payload: Dictionary) -> Actor:
	var actor := Actor.from_dict(payload)
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor)
	BodyTraining.synchronize(actor)
	return actor
