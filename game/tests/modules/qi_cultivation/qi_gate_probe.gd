extends RefCounted

## Not a suite: the runner only collects `test_*.gd`, so this helper is named to
## sit outside discovery.
##
## Shared fixtures for the qi path's gate audits. Every reachability question the
## qi suites ask is the same question — "from the strongest pre-state a player
## standing in realm R can hold, is the gate on R+1 reachable, and is it
## discriminating?" — so the way to build that pre-state lives here, once.
##
## Three rules this file exists to enforce on its callers:
##
## 1. **No forged content.** Items come from `Crafting.resolve`, so the real
##    `max_stack` and `stackable` apply and a realm whose content does not exist
##    fails the suite instead of passing on a fabricated stub. The traversal used
##    to mint `ItemDef.new()` with `max_stack = 9999`, which proved nothing about
##    whether the content it was spending exists.
## 2. **No forged channel state.** Every channel transition goes through
##    `QiCultivationApi.train_channel`. A test that called `open_meridian` /
##    `expand_meridian` / `strengthen_meridian` directly was asserting the gate
##    against a state it had written itself, so a gate no player could satisfy
##    still measured as satisfied (ADR 0036's whole subject).
## 3. **Every wait is bounded and named.** A `while` on game state with no bound
##    is what wrote a 1 GB/s Godot log onto the user's disk. Each wait below names
##    the condition, bounds it small, and reports whether it converged, so an
##    unreachable gate fails an assertion instead of hanging.

## The ladder has 30 realms, so there are 29 boundaries between them.
const BOUNDARY_COUNT := 29

## A channel climbs closed -> open -> expanded -> strengthened in three elixirs,
## and every further step of depth costs one more. The bound is that climb plus
## slack, and it names the condition: a channel that will not climb.
const CLIMB_BOUND := 6

## One sitting sized to the whole gate the actor stands before, so a test is not a
## UI pressing a fixed step thousands of times.
const GATE_BOUND := 6

## A full reservoir, a met progress floor, and the next realm's dantian quality.
const FILL_BOUND := 6

## `meditate` steps by the facade's own 1.0 against `INSIGHT_GAIN`, and the
## authored floor reaches 66, so the bound is the largest floor.
const MEDITATE_BOUND := 512

## Authored item defs resolved once. `Crafting.resolve` falls through to a
## recursive scan of the whole item content tree when the id does not sit in the
## category its prefix implies, so an uncached resolve per stocking call turns a
## 30-realm audit into minutes of directory walking.
static var _defs: Dictionary = {}

## One earned pre-state per realm. A full walk costs one elixir per (climb + depth)
## on every required channel, and three suites ask for the same boundary, so
## rebuilding it three times bought nothing but minutes. A suite that MUTATES a
## prepared actor must call `clear_prepared` first or it is measuring a stale one.
static var _prepared: Dictionary = {}


static func _def(def_id: StringName) -> ItemDef:
	if _defs.has(def_id):
		return _defs[def_id]
	var resolved := Crafting.resolve(def_id)
	_defs[def_id] = resolved
	return resolved


## Resolve a real authored item and put at least `count` of it in the actor's
## inventory, adding whole authored stacks rather than one unit at a time. Returns
## false when the content does not resolve, so a caller can assert on it rather
## than quietly stocking nothing.
static func stock(actor: Actor, def_id: StringName, count: int = 64) -> bool:
	if def_id.is_empty():
		return false
	var def := _def(def_id)
	if def == null:
		return false
	var inventory := ItemsApi.inventory(actor)
	var step := maxi(1, def.max_stack)
	var have := inventory.count(def_id)
	while have < count:
		var added := mini(step, count - have)
		inventory.add(def, added)
		var now := inventory.count(def_id)
		if now <= have:
			# The inventory is full and refused it: nothing more can be stocked,
			# and an unbounded loop here is exactly the disk hazard AGENTS.md warns
			# about. Report the shortfall instead of spinning.
			return now > 0
		have = now
	return true


## An actor at `rank_id` with the module attached and nothing earned. `attach`
## creates the dantian (ADR 0095), so this is the whole production wiring.
static func fresh_actor(rank_id: StringName) -> Actor:
	var actor := Actor.new(
		&"qi_gate_hero", {Stat.COMPREHENSION: 0.0, QiStats.DANTIAN_CAPACITY: 100.0}
	)
	actor.set_path(PathState.new(QiPath.PATH_ID, rank_id))
	actor.meridians.unlock_for_realm(rank_id)
	QiCultivationApi.attach(actor)
	ItemsApi.attach(actor, 512)
	QiTraining.synchronize(actor)
	return actor


## The work one `cultivate` call must do to earn a realm's whole progress gate.
static func gate_work(seed: QiRealmSeed) -> float:
	return 0.0 if seed == null else seed.progress_required


## Cultivate until the progress floor is met. `state.progress` is the condition and
## `GATE_BOUND` is that condition's canary.
static func earn_progress(actor: Actor, seed: QiRealmSeed) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	if state == null or seed == null:
		return false
	var waited := 0
	while waited < GATE_BOUND and state.progress < seed.progress_required:
		waited += 1
		if not QiCultivationApi.cultivate(actor, gate_work(seed)):
			return false
	return state.progress >= seed.progress_required


## Earn the target realm's ELEMENT gate (ADR 0004's "master elements to rise"), through
## the public verbs: `awaken` opens a spark on a body born without one — the same door a
## player uses, and the only way `practise` accepts a sitting — and `practise` raises the
## mastery at the shared rate. One sitting is sized to the whole gate, like
## `earn_progress`, and `GATE_BOUND` is the canary: a gate no sitting closes reports
## false instead of pressing forever.
static func earn_element_mastery(actor: Actor, target: QiRealmSeed) -> bool:
	if target == null:
		return false
	if target.element_mastery_required <= 0.0:
		return true
	if actor.affinities.get_value(ElementStats.FIRE) <= 0.0:
		ElementsApi.awaken(actor, ElementStats.FIRE, 1.0)
	var waited := 0
	while (
		waited < GATE_BOUND and ElementsApi.total_mastery(actor) < target.element_mastery_required
	):
		waited += 1
		if not bool(
			ElementsApi.practise(actor, ElementStats.FIRE, target.element_mastery_required).get(
				"ok", false
			)
		):
			return false
	return ElementsApi.total_mastery(actor) >= target.element_mastery_required


## Cultivate until the dantian is full and carries the next realm's quality.
## `dantian.is_full` and `dantian.quality` are the conditions.
static func fill_and_refine(actor: Actor, seed: QiRealmSeed) -> bool:
	var dantian := QiTestKit.dantian(actor)
	if dantian == null or seed == null:
		return false
	var waited := 0
	while (
		waited < FILL_BOUND
		and (not dantian.is_full(actor) or dantian.quality < seed.dantian_quality_required)
	):
		waited += 1
		if not QiCultivationApi.cultivate(actor, gate_work(seed)):
			return false
	return dantian.is_full(actor) and dantian.quality >= seed.dantian_quality_required


## Meditate to the realm's insight floor. `COMPREHENSION` is the condition; nothing
## else on this path raises it.
static func meditate_to_floor(actor: Actor, floor: float) -> bool:
	var waited := 0
	while waited < MEDITATE_BOUND and actor.stats.derived(Stat.COMPREHENSION) < floor:
		waited += 1
		if not QiCultivationApi.meditate(actor, QiCultivationApi.MEDITATE_STEP):
			return false
	return actor.stats.derived(Stat.COMPREHENSION) >= floor


## Train one channel to the gate `target` demands, through the public verb only.
##
## The whole walk is bounded by ONE budget taken before the first elixir: the state
## climb to the demanded state plus the outstanding depth, plus one more if the
## channel is injured (because `train_channel` repairs rather than climbs, and
## `meets` fails on the injury flag alone). Re-reading the budget each step made it
## move under the walk, which gave up one step early and reported a reachable gate
## as unreachable.
static func train_to_gate(actor: Actor, meridian_id: StringName, target: QiRealmSeed) -> bool:
	if target == null:
		return false
	var channel := actor.meridians.get_meridian(meridian_id)
	if channel == null:
		return false
	var budget := QiTraining.elixirs_to_gate(actor, meridian_id, target)
	if channel.is_injured():
		budget += 1
	var spent := 0
	while not target.channel_met(channel):
		if spent >= budget:
			return false
		spent += 1
		if not _train(actor, meridian_id):
			return false
		channel = actor.meridians.get_meridian(meridian_id)
		if channel == null:
			return false
	return true


## What one elixir spent on one channel looks like. The caller has already stocked:
## this is deliberately NOT stocking per step. Adding one unit per elixir turned a
## 20-channel gate into hundreds of inventory operations, and an inventory that
## quietly filled up turned a reachable gate into "the elixir was not there" — the
## walk then reported a data defect that was a fixture defect.
static func _train(actor: Actor, meridian_id: StringName) -> bool:
	return QiCultivationApi.train_channel(actor, meridian_id)


## How many elixirs the whole gate costs from here: one per outstanding state step
## per channel, one per outstanding depth step per channel, and one more per
## channel for a repair, because `train_channel` repairs an injured channel instead
## of climbing it. At least one per channel, so the number is never zero for a
## gate that names channels.
static func gate_elixir_budget(actor: Actor, target: QiRealmSeed) -> int:
	if target == null:
		return 0
	var total := 0
	for meridian_id in target.required_meridians:
		total += QiTraining.elixirs_to_gate(actor, meridian_id, target)
		var channel := actor.meridians.get_meridian(meridian_id)
		if channel != null and channel.is_injured():
			total += 1
	return maxi(total, target.required_meridians.size())


## Train every channel the target realm's gate names, to that gate, on one stocked
## elixir budget. The elixir spent is the SOURCE realm's `training_item`, because
## that is the only one `train_channel` accepts while the actor stands here.
static func train_gate_channels(actor: Actor, target: QiRealmSeed) -> bool:
	var state := actor.path(QiPath.PATH_ID)
	if state == null or target == null:
		return false
	var source := QiRealmSeed.for_realm(state.rank_id)
	if source == null:
		return false
	if not stock(actor, source.training_item, gate_elixir_budget(actor, target) + 1):
		return false
	for meridian_id in target.required_meridians:
		if not train_to_gate(actor, meridian_id, target):
			return false
	return true


## The strongest pre-state a player standing in `rank_id` can hold, reached only
## through the production actions: the target realm's channels trained, its work
## budget and insight floor earned, the dantian full and refined, the pill in hand,
## and whatever deviation damage closed with the realm's recovery elixir.
##
## Nothing here reaches past the facade to open, strengthen or refine a channel, to
## hand-write progress, or to write a rank. It reports whether it converged; the
## audit suites assert the gate values themselves so a prepare that could not
## finish surfaces as a named gate failure rather than a null dereference.
static func prepared(rank_id: StringName, target: QiRealmSeed) -> Actor:
	if _prepared.has(rank_id):
		return _prepared[rank_id]
	var actor := fresh_actor(rank_id)
	if target == null:
		return actor
	# The tribulation is the player's fight (ADR 0041), so it is part of standing
	# ready — nothing in the module starts it. What this cannot earn is the anchor
	# the PREVIOUS breakthrough commits, which is why the high tier's readiness is
	# proven by the traversal rather than by a single boundary.
	var target_realm := target_after(rank_id)
	if target_realm != null:
		fight(actor, target_realm)
	# The ascent is the player's walk (ADR 0058), and above the Micro tier it is what
	# the gate reads, so standing ready includes it.
	walk_ascent(actor)
	# Close whatever an earlier attempt left behind first: an injured channel
	# refuses to climb, and a scarred dantian caps at 75% of its own capacity.
	recover_all(actor)
	stock(actor, target.breakthrough_item)
	if not train_gate_channels(actor, target):
		return actor
	recover_all(actor)
	if not earn_progress(actor, target):
		return actor
	if not earn_element_mastery(actor, target):
		return actor
	if not meditate_to_floor(actor, target.comprehension_required):
		return actor
	fill_and_refine(actor, target)
	recover_all(actor)
	fill_and_refine(actor, target)
	stock(actor, target.breakthrough_item)
	if not ensure_dao_heart(actor, target.id):
		return actor
	_prepared[rank_id] = actor
	return actor


## Stand ready for the DEEPEST tier's dao-heart ask (BL-0932) the way a player meets
## it: authored gear, whose fixed modifiers are what APPLY (a consumable's stat targets
## are reported, never applied — ADR 0001). The two uniques below are the ones the
## realm-tier guard admits at the boundary that asks: `unique_void_coil_coiled_heart`
## grants +20 and is wearable from the Immortal tier up, `unique_ironhide_hearthguard`
## grants +6 from the Mortal tier — 26 together against the ask of 24. The lantern's
## +40 is refused until the Transcendent tier is reached, so it cannot answer this ask.
## Tiers that ask nothing return true immediately.
static func ensure_dao_heart(actor: Actor, target_realm_id: StringName) -> bool:
	if actor == null:
		return false
	var tier := RealmDefaults.ladder().tier_of(target_realm_id)
	var required := float(Breakthrough.DAO_HEART_BY_TIER.get(tier, 0.0))
	if required <= 0.0 or actor.stats.derived(Stat.DAO_HEART) >= required:
		return true
	for def_id in [&"unique_void_coil_coiled_heart", &"unique_ironhide_hearthguard"]:
		var def := _def(def_id)
		if def == null or not stock(actor, def_id, 1):
			return false
		if not ItemsApi.equip_item(actor, def.subcategory, def):
			return false
	return actor.stats.derived(Stat.DAO_HEART) >= required


## Forget the cached pre-states. A suite that mutates one between assertions needs
## this, or it would keep measuring against the actor it first built.
static func clear_prepared() -> void:
	_prepared.clear()


## Spend the realm's recovery elixir until nothing on the actor is injured. The
## condition is "no wound left", and the bound is the wounds the path can carry.
##
## The elixir is stocked HERE rather than by the caller: `recover_next` spends the
## realm's `recovery_item`, so a caller that forgot to stock it got a scarred
## dantian it could never close — and a traversal that re-prepared without it looped
## on the same unmet `dantian_injured` until the framework's failure backstop fired.
static func recover_all(actor: Actor) -> bool:
	var path_state := actor.path(QiPath.PATH_ID)
	if path_state == null:
		return false
	var seed := QiRealmSeed.for_realm(path_state.rank_id)
	if seed == null:
		return false
	if not seed.recovery_item.is_empty():
		stock(actor, seed.recovery_item, 8)
	var waited := 0
	while waited < 64:
		var dantian := QiTestKit.dantian(actor)
		var wounded := dantian != null and dantian.injured
		for channel in actor.meridians.get_all_meridians():
			wounded = wounded or channel.is_injured()
		if not wounded:
			return true
		waited += 1
		if not QiCultivationApi.recover_next(actor):
			return false
	return true


## Fight the tribulation bound to `target` to a decided win, through the
## production entry points only (ADR 0041). Finishing the phases is not enough: a
## gate opens only for a decided win. A survivor of another realm does not stand
## in for this one (ADR 0032), so it is always fought for the realm it gates.
static func fight(actor: Actor, target: RealmDef) -> void:
	if Breakthrough.tribulation_ok(actor, target.index):
		return
	if Breakthrough.begin_tribulation(actor, target.index) == null:
		return
	for _wave in 16:
		if not Breakthrough.advance_tribulation(actor):
			break
	Breakthrough.resolve_tribulation(actor, true)


## Walk the Transcendent ascent through core's own entry point (ADR 0058). The R28
## breakthrough only BEGINS it — naming the dao and granting the milestone's one
## ability — so `Breakthrough.ascension_ok` stays shut until the player walks it, and
## nothing in `src/` calls `ascend` yet.
##
## Bounded even though core says the walk terminates on state: a bound that names its
## condition is cheaper to read than a trust in someone else's comment, and an
## unbounded loop here is the disk hazard AGENTS.md warns about. Only `ascend` and
## `AscensionState.is_complete` are read, because those are the two members core
## documents as the walk's contract.
static func walk_ascent(actor: Actor) -> bool:
	if actor.ascension == null:
		# No ascent has begun, so there is nothing to walk and nothing is owed here.
		# The R28 breakthrough is what begins one (ADR 0058), so this is the ordinary
		# answer below the Transcendent tier.
		return true
	if actor.ascension.is_complete():
		return true
	var walked := 0
	while walked < 16 and not actor.ascension.is_complete():
		walked += 1
		if not WorldAnchor.ascend(actor):
			break
	return actor.ascension.is_complete()


## The gate inputs `preview` reports for the realm after `rank_id`.
static func preview(actor: Actor) -> Dictionary:
	return QiBreakthroughTransaction.preview(actor)


static func realm_at(index: int) -> RealmDef:
	return RealmDefaults.ladder().realms()[index]


static func target_after(rank_id: StringName) -> RealmDef:
	return RealmDefaults.ladder().next(rank_id)


static func target_seed_after(rank_id: StringName) -> QiRealmSeed:
	var target := target_after(rank_id)
	return null if target == null else QiRealmSeed.for_realm(target.id)


## Drop the resolved-def cache. Content tooling that regenerates items needs it,
## or a suite would keep asserting against a stale `ItemDef`.
static func clear_cache() -> void:
	_defs.clear()
