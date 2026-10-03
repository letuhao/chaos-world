extends TestCase

## The high tier is ONE spine read by three paths, walked here per path
## (ADR 0018-0021, 0058, 0103). Every claim is made three times, once per path id:
## a gate proved on the qi path and asserted for body and mind is a gate proved once.
## Nothing here writes a rank, a law, a world, an ascension stage or a success flag —
## the walks use only shipped verbs (`Breakthrough.face_tribulation`,
## `WorldAnchor.ascend`, `Breakthrough.try_advance_gated`, `WorldAnchor.commit`), so a
## walk that succeeds is a walk a player could take.
##
## SCOPE, stated so it is not over-read: the shared high-tier SPINE, per path. The
## cultivation-only gates below R19 — dantian quality, sea clarity, meridian depth,
## realm pills — are each path's own condition and are measured by
## `tests/modules/<path>/test_full_traversal.gd`. The tribulation gate itself, its
## cost and its save boundary are in `test_tribulation_entry.gd`.

## Ladder index of R19, the first realm the Immortal tier gates (0-based).
const IMMORTAL := Breakthrough.IMMORTAL_REALM_THRESHOLD
## Ladder index of R30, the last realm on the ladder.
const TERMINAL := 29

const PATHS := [BodyPath.PATH_ID, QiPath.PATH_ID, MindPath.PATH_ID]
## The paths whose Transcendent gate reads the walked ascent. Mind substitutes
## `MindAnchor` and never reads it (ADR 0058).
const ASCENSION_PATHS := [BodyPath.PATH_ID, QiPath.PATH_ID]

## Bounds that name what they catch. A ladder that stopped adding realms would spin
## the walk instead of walking 29 transitions; a phase machine that stopped
## converging would spin the fight; an undecided fight would spin the verdict search.
const LADDER_GUARD := 64
const WAVE_GUARD := 16
const SEED_GUARD := 64
const ASCENT_WALK_GUARD := 16

## Passes the stocking retry may take before it gives up on finding a slot. Headroom,
## not a budget: one pass adds the single unit the milestone costs, and the spend
## that follows frees the slot again.
const STOCK_GUARD := 64

## One canonical walk from the first realm to R30, cached per path so the three
## walks are the same code measured three times. Declared with the other globals:
## `gdlint` reads a `var` after a method as out of order.
static var _walks: Dictionary = {}

## Authored item defs resolved once. The cache is load-bearing rather than tidy:
## `Crafting.resolve` falls through to a recursive scan of the whole item content tree
## whenever the id does not sit in the category its prefix implies, so an uncached
## resolve per stocked milestone turns a 29-transition walk into seconds of directory
## walking.
static var _defs: Dictionary = {}

# --- Fixtures -----------------------------------------------------------------


func _realm_id(index: int) -> StringName:
	return RealmDefaults.ladder().realms()[index].id


func _hero_at(index: int, path_id: StringName) -> Actor:
	var actor := Actor.new(&"high_tier", {Stat.COMPREHENSION: 40.0})
	actor.set_path(PathState.new(path_id, _realm_id(index)))
	actor.meridians.unlock_for_realm(_realm_id(index))
	# Inventory and nothing more: the milestones Mind owes are paid in items, so a
	# walk that could not spend one could not be a walk a player takes. Body and qi
	# spend nothing here, and an empty inventory costs them nothing.
	ItemsApi.attach(actor)
	return actor


## An actor one realm below the Immortal tier on `path_id`, channels unlocked and
## otherwise untrained: the legal prior state the R19 gate reads.
func _at_r18(path_id: StringName) -> Actor:
	return _hero_at(IMMORTAL - 1, path_id)


## Walk the whole ascent with the player's verb. Bounded by `ASCENT_WALK_GUARD`,
## which names the ritual that failed to finish; `ascend` refuses past its own step
## count, so the bound is never the reason the walk ends.
func _walk_ascent(actor: Actor) -> int:
	var guard := 0
	while guard < ASCENT_WALK_GUARD and WorldAnchor.ascend(actor):
		guard += 1
	return guard


## Fight the tribulation this path owes until the gate opens, trying seeds until one
## rolls the actor through. The search is over SEEDS, never over game state: a lost
## fight leaves a decided record, and the next attempt replaces it, so every attempt
## runs a whole new fight and the loop always terminates on the gate or on the bound.
func _fight(actor: Actor, path_id: StringName) -> bool:
	if _gate_open(actor, path_id):
		return true
	for candidate in range(1, SEED_GUARD):
		var rng := _seeded(candidate)
		var guard := 0
		while guard < WAVE_GUARD and not _gate_open(actor, path_id):
			guard += 1
			Breakthrough.face_tribulation(actor, path_id, rng)
		if _gate_open(actor, path_id):
			return true
	return false


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Whether the tribulation gate in front of this path's next realm is already open.
## True at the top of the ladder, where no realm remains to owe one.
func _gate_open(actor: Actor, path_id: StringName) -> bool:
	var upcoming := RealmDefaults.ladder().next(actor.path(path_id).rank_id)
	if upcoming == null:
		return true
	return Breakthrough.tribulation_ok(actor, RealmDefaults.ladder().index_of(upcoming.id))


## Fight the tribulation owed for the realm this path is about to enter, if any.
func _face_next(actor: Actor, path_id: StringName) -> bool:
	var upcoming := RealmDefaults.ladder().next(actor.path(path_id).rank_id)
	if upcoming == null:
		return true
	var index := RealmDefaults.ladder().index_of(upcoming.id)
	if index < IMMORTAL:
		return true
	return _fight(actor, path_id)


## The milestones one path commits when it enters `entered`. Body and Qi commit the
## shared schedule; Mind commits its own, because it never reads the shared one.
func _commit(path_id: StringName, actor: Actor, entered: int) -> void:
	WorldAnchor.commit(actor, entered)
	if path_id == MindPath.PATH_ID:
		MindAnchor.commit(actor, entered)


## The anchor milestone one path has to PAY for, as distinct from the ones its commit
## settles. Body and qi read the shared `WorldAnchor.stage_met` schedule, which a
## commit writes directly, so they owe nothing here and this is a no-op on both.
##
## Mind reads `MindAnchor`, whose demand additionally requires the anchor REINFORCED.
## Reinforcement is the resonance milestone: the realm's channel elixir spent through
## `MindCultivationApi.strengthen_anchor`, and no commit grants it (ADR 0115 — while
## `_commit_inside_world` stamped it, the breakthrough `Breakthrough.try_advance` makes
## for every path paid the very gate it was supposed to govern). It is called on all
## three paths so the difference stays the module's rather than the fixture's: a walk
## that skipped the spend for Mind would be asserting the old, broken gate.
func _pay_anchor(path_id: StringName, actor: Actor) -> void:
	if path_id != MindPath.PATH_ID:
		return
	var rank_id: StringName = actor.path(MindPath.PATH_ID).rank_id
	if RealmDefaults.ladder().index_of(rank_id) < IMMORTAL:
		return
	var seed := MindRealmSeed.for_realm(rank_id)
	if seed == null:
		return
	_stock(actor, seed.training_item)
	MindCultivationApi.strengthen_anchor(actor)


## Put one unit of a real authored item in the actor's inventory. Resolving through
## the item content tree is what proves the milestone's elixir exists and loads.
func _stock(actor: Actor, def_id: StringName) -> void:
	if def_id.is_empty():
		return
	var def := _item_def(def_id)
	if def == null:
		return
	for _unit in STOCK_GUARD:
		if ItemsApi.has_item(actor, def_id):
			return
		ItemsApi.inventory(actor).add(def, 1)


func _item_def(def_id: StringName) -> ItemDef:
	if _defs.has(def_id):
		return _defs[def_id]
	var resolved := Crafting.resolve(def_id)
	_defs[def_id] = resolved
	return resolved


## The anchor gate the given path actually reads at `index`. Mind substitutes its own
## policy and never reads the shared schedule; body and qi read the shared schedule
## and know nothing of Mind's. Asserting either against the other would prove a
## policy neither path plays by.
func _anchor_gate_met(path_id: StringName, actor: Actor, index: int) -> bool:
	if path_id == MindPath.PATH_ID:
		return MindAnchor.stage_met(actor, MindAnchor.required_stage(index))
	return WorldAnchor.stage_met(actor, index)


## Climb from the first realm to `target_id` with shipped verbs only, stopping the
## walk of the ascent so the caller can decide when the ritual is walked. Bounded by
## `LADDER_GUARD`: a gate that never opens stops the climb, and the caller asserts
## the realm it reached.
func _climbed_to(target_id: StringName, path_id: StringName) -> Actor:
	var actor := _hero_at(0, path_id)
	var guard := 0
	while actor.path(path_id).rank_id != target_id and guard < LADDER_GUARD:
		guard += 1
		var current := actor.path(path_id).rank_id
		if RealmDefaults.ladder().next(current) == null:
			break
		_face_next(actor, path_id)
		if not Breakthrough.try_advance_gated(actor, path_id):
			break
		_commit(path_id, actor, RealmDefaults.ladder().index_of(actor.path(path_id).rank_id))
	return actor


# --- The ascent ---------------------------------------------------------------


## The ascent is shared and path-agnostic: one artifact on the actor, no path named,
## four steps on every path and a fifth refused on every path.
func test_the_ascent_is_one_shared_walk_on_every_path() -> void:
	for path_id in PATHS:
		var actor := _at_r18(path_id)
		_commit(path_id, actor, WorldAnchor.COMMIT_MICRO)
		assert_eq(WorldAnchor.ascend(actor), true, "%s: step one" % path_id)
		var walked := 1
		var guard := 0
		while guard < ASCENT_WALK_GUARD and WorldAnchor.ascend(actor):
			guard += 1
			walked += 1
		assert_eq(walked, AscensionState.ASCENT_STEPS, "%s: the whole ladder" % path_id)
		assert_eq(WorldAnchor.ascend(actor), false, "%s: refuses a fifth" % path_id)
		assert_eq(WorldAnchor.ascension_unmet(actor), "", "%s: nothing left" % path_id)


## Climbing to R28 begins the ascent and walks none of it, so R29 is shut until the
## ritual is walked. A breakthrough that finished its own prerequisite would open the
## gate in front of it for free.
func test_r29_is_shut_until_the_ascent_is_walked() -> void:
	for path_id in ASCENSION_PATHS:
		var actor := _climbed_to(&"transcendent", path_id)
		assert_eq(actor.path(path_id).rank_id, &"transcendent", "%s: reached R28" % path_id)
		assert_ne(actor.ascension, null, "%s: the ascent was begun" % path_id)
		assert_eq(actor.ascension.steps, 0, "%s: and no step walked" % path_id)
		assert_eq(
			Breakthrough.ascension_ok(actor, WorldAnchor.COMMIT_MICRO + 1),
			false,
			"%s: R29 wants a walked ascent" % path_id
		)
		assert_ne(
			WorldAnchor.ascension_unmet(actor), "", "%s: and the shortfall is reported" % path_id
		)
		_face_next(actor, path_id)
		_walk_ascent(actor)
		assert_eq(
			Breakthrough.ascension_ok(actor, WorldAnchor.COMMIT_MICRO + 1),
			true,
			"%s: R29 opens once it is walked" % path_id
		)
		assert_eq(
			Breakthrough.try_advance_gated(actor, path_id), true, "%s: and R29 is taken" % path_id
		)


# --- The top of the ladder ----------------------------------------------------


## R30 is the end. No path advances past it, and nothing is owed past it either, so
## the terminal realm is a wall and not a name.
func test_r30_refuses_to_advance_on_every_path() -> void:
	for path_id in PATHS:
		var actor := _hero_at(TERMINAL, path_id)
		assert_eq(
			RealmDefaults.ladder().next(_realm_id(TERMINAL)), null, "%s: there is no R31" % path_id
		)
		assert_eq(Breakthrough.can_advance(actor, path_id), false, "%s: can_advance" % path_id)
		assert_eq(Breakthrough.try_advance(actor, path_id), false, "%s: try_advance" % path_id)
		assert_eq(Breakthrough.try_advance_gated(actor, path_id), false, "%s: gated" % path_id)
		assert_eq(
			Breakthrough.try_advance_with_ascension(actor, path_id),
			false,
			"%s: ascent-gated" % path_id
		)
		assert_eq(
			Breakthrough.face_tribulation(actor, path_id), true, "%s: no fight is owed" % path_id
		)
		assert_eq(actor.tribulation, null, "%s: and none was begun" % path_id)
		assert_eq(actor.path(path_id).rank_id, _realm_id(TERMINAL), "%s: rank held" % path_id)


# --- The whole ladder, per path ----------------------------------------------


func _walk_for(path_id: StringName) -> Dictionary:
	if not _walks.has(path_id):
		_walks[path_id] = _walked(path_id)
	return _walks[path_id]


## Walk R1 -> R30 with shipped verbs only, recording what each transition had to earn.
func _walked(path_id: StringName) -> Dictionary:
	var ladder := RealmDefaults.ladder()
	var actor := _hero_at(0, path_id)
	var steps: Array = []
	var guard := 0
	while ladder.next(actor.path(path_id).rank_id) != null and guard < LADDER_GUARD:
		guard += 1
		var next_realm := ladder.next(actor.path(path_id).rank_id)
		var next_index := ladder.index_of(next_realm.id)
		var gate_before := Breakthrough.tribulation_ok(actor, next_index)
		# Captured before the commit, because the anchor this transition had to earn
		# is the one standing when the gate is read — never the one this very
		# breakthrough produces.
		var anchor_before := _anchor_gate_met(path_id, actor, next_index)
		var won := _face_next(actor, path_id)
		_walk_ascent(actor)
		var advanced := Breakthrough.try_advance_gated(actor, path_id)
		if advanced:
			_commit(path_id, actor, ladder.index_of(actor.path(path_id).rank_id))
			# Paid AFTER the commit, because the milestone reinforces the anchor the
			# commit creates — and BEFORE the next transition reads the gate, so the
			# gate the walk is about to face is one the walk has already paid for.
			_pay_anchor(path_id, actor)
		(
			steps
			. append(
				{
					"target": next_realm.id,
					"index": next_index,
					"gate_before": gate_before,
					"won": won,
					"gate_after": Breakthrough.tribulation_ok(actor, next_index),
					"advanced": advanced,
					"rank": actor.path(path_id).rank_id,
					"anchor": anchor_before,
				}
			)
		)
		# A transition that did not advance ends the walk. Spinning the ladder guard
		# on a gate that never opens would report the same refusal sixty-four times
		# and bury the one line that says which gate it was.
		if not advanced:
			break
	return {"actor": actor, "steps": steps}


## The ladder is traversable end to end on every path, with no forged state.
func test_the_ladder_is_traversable_on_every_path() -> void:
	for path_id in PATHS:
		var walked := _walk_for(path_id)
		var steps: Array = walked["steps"]
		var actor: Actor = walked["actor"]
		assert_eq(steps.size(), TERMINAL, "%s: every transition walked" % path_id)
		assert_eq(
			actor.path(path_id).rank_id, &"primordial_origin", "%s: the terminal realm" % path_id
		)
		for step: Dictionary in steps:
			assert_eq(step["advanced"], true, "%s: entered %s" % [path_id, step["target"]])
			assert_eq(step["rank"], step["target"], "%s: the rank is the target" % path_id)
			assert_eq(
				step["anchor"],
				true,
				"%s: the anchor gate was met at %s" % [path_id, step["target"]]
			)


## Every high-tier transition of the walk started with the gate SHUT and earned it.
## This is the R19 threshold measured across all twelve gated transitions of each
## path, not measured once and asserted.
func test_every_high_tier_transition_was_gated_on_every_path() -> void:
	for path_id in PATHS:
		var gated := 0
		for step: Dictionary in _walk_for(path_id)["steps"]:
			if int(step["index"]) < IMMORTAL:
				assert_eq(step["gate_before"], true, "%s: no gate below the tier" % path_id)
				continue
			gated += 1
			assert_eq(step["gate_before"], false, "%s: %s started shut" % [path_id, step["target"]])
			assert_eq(step["won"], true, "%s: %s was fought and won" % [path_id, step["target"]])
			assert_eq(
				step["gate_after"], true, "%s: %s earned its gate" % [path_id, step["target"]]
			)
		assert_eq(gated, TERMINAL - IMMORTAL + 1, "%s: every gated transition" % path_id)


## The walk is deterministic: a second walk of the same path reaches the same realm,
## so the traversal above is a property of the gates and not of one lucky roll.
func test_the_walk_is_deterministic() -> void:
	for path_id in PATHS:
		var again := _walked(path_id)
		assert_eq(
			(again["actor"] as Actor).path(path_id).rank_id,
			&"primordial_origin",
			"%s: the same terminal realm on a second walk" % path_id
		)
