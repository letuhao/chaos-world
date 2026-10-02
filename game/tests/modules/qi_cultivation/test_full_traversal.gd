extends TestCase

## Full R1→R30 traversal for the qi path (ADR 0032). Mirrors the body traversal:
## the whole ladder is walked through public actions only — cultivate, train a
## channel, meditate, recover, and breakthrough. Nothing here writes rank,
## channel state, world systems, or success flags; a failed attempt is recovered
## from content and retried.
##
## The high tier is only reachable because the breakthrough *commits* the inside
## world, world, and ascension its own tier produces (`WorldAnchor`), so this
## suite is also the proof that R19-R30 are reachable in play.

const PATH := QiPath.PATH_ID

var _defs: Dictionary = {}


func _actor() -> Actor:
	var actor := Actor.new(
		&"qi_traversal", {Stat.COMPREHENSION: 40.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(PATH, &"qi_refining"))
	actor.meridians.unlock_for_realm(&"qi_refining")
	QiCultivationApi.attach(actor)
	QiCultivationApi.attach_dantian(actor)
	# A full run keeps one pill, one elixir, and one recovery elixir per realm.
	ItemsApi.attach(actor, 128)
	QiTraining.synchronize(actor)
	return actor


## Top the actor up on one realm's consumable. The quantity stays far below
## `max_stack` so a re-stock merges into the same stack instead of burning a
## fresh inventory slot and starving the later realms.
func _stock(actor: Actor, def_id: StringName) -> void:
	if def_id == &"":
		return
	var def: ItemDef = _defs.get(def_id)
	if def == null:
		def = ItemDef.new()
		def.id = def_id
		def.stackable = true
		def.max_stack = 9999
		_defs[def_id] = def
	ItemsApi.inventory(actor).add(def, 4)


func _dantian_full(actor: Actor) -> bool:
	var dantian := QiCultivationApi.dantian(actor)
	return dantian != null and dantian.ratio(actor) >= 1.0


## Circulate until all three outputs of the same action are satisfied: the
## progress floor, a full single qi reservoir, and the dantian quality the next
## realm demands. A deviation halves quality and `recover` deliberately does not
## restore it, so preparation must circulate again after every recovery.
func _cultivate_until(actor: Actor, progress_required: float, quality_required: float) -> void:
	var state := actor.path(PATH)
	var guard := 0
	while (
		guard < 4096
		and (
			state.progress < progress_required
			or not _dantian_full(actor)
			or QiCultivationApi.dantian(actor).quality < quality_required
		)
	):
		guard += 1
		if not QiTraining.cultivate(actor, 25.0):
			return


## Meditation is the only source of comprehension, so the insight floor is
## reached by meditating rather than by writing the stat.
func _meditate_to_floor(actor: Actor, comprehension_required: float) -> void:
	var guard := 0
	while guard < 8192 and actor.stats.derived(Stat.COMPREHENSION) < comprehension_required:
		guard += 1
		QiTraining.meditate(actor, 1.0)


## Fight and win the tribulation for the realm being entered, through the
## production entry points only. The world systems a tier produces are committed
## by the breakthrough itself, so this must not write them (ADR 0032), and a
## finished-but-undecided fight is not a survivor (ADR 0041).
func _satisfy_tier_gates(actor: Actor, target: RealmDef) -> void:
	if target.index < Breakthrough.IMMORTAL_REALM_THRESHOLD:
		return
	if Breakthrough.tribulation_ok(actor, target.index):
		return
	if Breakthrough.begin_tribulation(actor, target.index) == null:
		return
	var guard := 0
	while Breakthrough.advance_tribulation(actor) and guard < 64:
		guard += 1
	assert_eq(Breakthrough.resolve_tribulation(actor, true), true, "tribulation won")


## Close whatever a deviation left behind, using the public recovery action.
func _recover_damage(actor: Actor) -> void:
	var current := QiRealmSeed.for_realm(actor.path(PATH).rank_id)
	if current == null or current.recovery_item == &"":
		return
	_stock(actor, current.recovery_item)
	var guard := 0
	while guard < 32:
		guard += 1
		if not QiCultivationApi.recover_next(actor):
			return


func _train_channel(actor: Actor, meridian_id: StringName, target: QiRealmSeed) -> void:
	var current := QiRealmSeed.for_realm(actor.path(PATH).rank_id)
	var guard := 0
	while guard < 256:
		guard += 1
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel == null:
			actor.meridians.unlock_for_realm(actor.path(PATH).rank_id)
			channel = actor.meridians.get_meridian(meridian_id)
			if channel == null:
				return
		if not channel.is_injured() and channel.meets(current.required_channel_state):
			if current == null or channel.refinement >= target.channel_refinement_cap:
				return
		_stock(actor, current.training_item)
		if not QiTraining.train_channel(actor, meridian_id):
			return


## Bring the actor to the brink of the next realm using only public actions.
func _prepare(actor: Actor) -> QiRealmSeed:
	var state := actor.path(PATH)
	var target := RealmDefaults.ladder().next(state.rank_id)
	if target == null:
		return null
	var seed := QiRealmSeed.for_realm(target.id)
	if seed == null:
		return null
	_satisfy_tier_gates(actor, target)
	actor.meridians.unlock_for_realm(target.id)
	_stock(actor, seed.breakthrough_item)
	_recover_damage(actor)
	for meridian_id in seed.required_meridians:
		_train_channel(actor, meridian_id, seed)
	_recover_damage(actor)
	_cultivate_until(actor, seed.progress_required, seed.dantian_quality_required)
	_recover_damage(actor)
	_meditate_to_floor(actor, seed.comprehension_required)
	return seed


## Attempts allowed before declaring a realm unreachable, sized from the
## evaluated chance so the traversal cannot flake on a legitimate deviation.
func _attempt_budget(chance: float) -> int:
	if chance >= 1.0:
		return 1
	return maxi(3, ceili(log(0.000001) / log(1.0 - chance)))


func _breakthrough(actor: Actor, rng: RandomNumberGenerator) -> bool:
	var budget := _attempt_budget(float(QiBreakthroughTransaction.preview(actor)["chance"]))
	for _attempt in budget:
		if QiBreakthroughTransaction.execute(actor, rng):
			return true
		if _prepare(actor) == null:
			return false
	return false


func test_qi_full_traversal_all_30_realms() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ladder := RealmDefaults.ladder()
	var visited: Array[StringName] = [actor.path(PATH).rank_id]
	var breakthroughs := 0
	var guard := 0
	while true:
		guard += 1
		if guard > 64:
			push_error("qi traversal did not reach the terminal realm")
			break
		var state := actor.path(PATH)
		var target := ladder.next(state.rank_id)
		if target == null:
			break
		var seed := _prepare(actor)
		assert_ne(seed, null, "seed for %s" % target.id)
		if seed == null:
			break
		# The preview and the transaction must agree, or the gate is decorative.
		var preview := QiBreakthroughTransaction.preview(actor)
		assert_eq(
			bool(preview["can_attempt"]),
			true,
			"preview ready for %s: %s" % [target.id, preview["unmet_conditions"]]
		)
		assert_eq(_breakthrough(actor, rng), true, "breakthrough succeeded for %s" % target.id)
		breakthroughs += 1
		visited.append(target.id)
		assert_eq(actor.path(PATH).rank_id, target.id, "advanced to %s" % target.id)
	assert_eq(visited.size(), 30, "visited all 30 realms")
	assert_eq(breakthroughs, 29, "advanced 29 times")
	assert_eq(visited[-1], &"primordial_origin", "at the terminal realm")
	assert_eq(ladder.next(visited[-1]), null, "no realm after R30")


func test_qi_high_tier_commits_its_own_anchors() -> void:
	# Entering R19 must produce the Seed inside world without anything having
	# forged it; that is what makes the gate above satisfiable in play.
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	while actor.path(PATH).rank_id != &"spirit_ascension":
		if _prepare(actor) == null:
			break
		if not _breakthrough(actor, rng):
			break
	assert_eq(actor.path(PATH).rank_id, &"spirit_ascension", "reached the last mortal realm")
	assert_eq(actor.inside_world, null, "no inside world below the Immortal tier")
	_prepare(actor)
	assert_eq(_breakthrough(actor, rng), true, "entered R19")
	assert_eq(actor.path(PATH).rank_id, &"earth_immortal", "advanced to R19")
	assert_ne(actor.inside_world, null, "R19 committed the inside world")
	assert_eq(actor.inside_world.is_stable(), true, "and it is stable")


func test_qi_transcendent_tier_commits_world_and_ascension() -> void:
	var actor := _actor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var guard := 0
	while actor.path(PATH).rank_id != &"immortal_sovereign" and guard < 96:
		guard += 1
		if _prepare(actor) == null:
			break
		if not _breakthrough(actor, rng):
			break
	assert_eq(actor.path(PATH).rank_id, &"immortal_sovereign", "reached the last immortal realm")
	_prepare(actor)
	assert_eq(_breakthrough(actor, rng), true, "entered the Transcendent tier")
	assert_eq(actor.path(PATH).rank_id, &"transcendent", "advanced to R28")
	assert_ne(actor.world, null, "R28 committed the micro world")
	assert_ne(actor.ascension, null, "R28 committed the ascension")
	assert_eq(actor.ascension.is_complete(), true, "and the ascension is finished")
