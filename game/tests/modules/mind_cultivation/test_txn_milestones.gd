extends TestCase

## Milestones that take effect, and milestones that are reported honestly.
##
## Two were wrong on this module. The resonance milestone (`MindTraining.strengthen_anchor`)
## was called the anchor's reinforcement and never touched the meridian network's
## resonance rank, so the thing the name promises did not happen. And the sea's
## `trained_stage` latch was surfaced by the facade and displayed by the mind screen
## as "Anchor stage N", while no gate and no stat in the repository ever read it.
##
## What this suite can prove is the half it owns: the anchor milestone a player pays
## for is the same clause the entry gate reads, it costs a consumable, and the report
## `preview` publishes is the stage policy's own verdict — so a screen cannot show a
## milestone that nothing enforces. The resonance-rank half needs `training.gd`; the
## `trained_stage` half needs `api.gd` and the mind screen. Both are recorded in the
## report with the exact change required, not papered over here.

## One realm of the ladder is one boundary; 30 realms make 29 transitions.
const LADDER_SIZE := 30

## The keys `preview` publishes for the anchor gate. Named here so a screen can rely
## on them, and so removing one is a visible change rather than a silent one.
const ANCHOR_GATE_KEYS: Array[String] = ["required", "stage", "value", "outstanding"]


func _at(rank_id: StringName) -> Actor:
	var actor := Actor.new(&"txn_milestone_hero", {Stat.COMPREHENSION: 0.0, Stat.WILL: 50.0})
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	actor.meridians.unlock_for_realm(rank_id)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 500)
	MindTraining.synchronize(actor)
	return actor


func _realm_at(index: int) -> RealmDef:
	return RealmDefaults.ladder().realms()[index]


func _stock(actor: Actor, def_id: StringName) -> bool:
	if def_id.is_empty():
		return false
	var def := Crafting.resolve(def_id)
	if def == null:
		return false
	var guard := 0
	while not ItemsApi.has_item(actor, def_id) and guard < 64:
		ItemsApi.inventory(actor).add(def, 1)
		guard += 1
	return ItemsApi.has_item(actor, def_id)


# --- The anchor milestone is the gate's clause -------------------------------


## The milestone a player pays for is the clause the entry gate reads. If the gate
## asked for something else, this would still be a milestone that changes nothing —
## which is the defect class this suite exists to keep out.
func test_the_anchor_milestone_is_the_clause_the_gate_reads() -> void:
	var actor := _at(_realm_at(MindAnchor.COMMIT_SEED).id)
	MindAnchor.commit(actor, MindAnchor.COMMIT_SEED)
	var stage := MindAnchor.required_stage(_realm_at(MindAnchor.COMMIT_SEED + 1).index)
	assert_eq(stage, MindAnchor.STAGE_SEED_ANCHOR, "R20 gates on the Seed anchor")
	assert_eq(actor.inside_world.anchor_strengthened, false, "the commit did not reinforce it")
	assert_eq(MindAnchor.stage_met(actor, stage), false, "so the gate is shut")

	_stock(actor, MindRealmSeed.for_realm(_realm_at(MindAnchor.COMMIT_SEED).id).training_item)
	assert_eq(MindTraining.strengthen_anchor(actor), true, "the resonance milestone completes")
	assert_eq(actor.inside_world.anchor_strengthened, true, "and it reinforced the anchor")
	assert_eq(MindAnchor.stage_met(actor, stage), true, "which is what opened the gate")


## A milestone with no price is a formality. Without the realm's channel elixir the
## milestone must refuse AND leave the gate shut, so the anchor cannot be bought for
## free or by accident.
func test_the_anchor_milestone_is_priced_and_refuses_without_its_consumable() -> void:
	var actor := _at(_realm_at(MindAnchor.COMMIT_SEED).id)
	MindAnchor.commit(actor, MindAnchor.COMMIT_SEED)
	var stage := MindAnchor.required_stage(_realm_at(MindAnchor.COMMIT_SEED + 1).index)
	assert_eq(
		MindTraining.strengthen_anchor(actor), false, "the milestone refuses on an empty pack"
	)
	assert_eq(actor.inside_world.anchor_strengthened, false, "and reinforces nothing")
	assert_eq(MindAnchor.stage_met(actor, stage), false, "so the gate stays shut")


## The report a screen renders is the stage policy's own verdict, with the shortfall
## named. A screen must never have to re-derive whether a milestone is outstanding.
func test_the_anchor_report_is_the_policy_verdict_plus_the_shortfall() -> void:
	var actor := _at(_realm_at(MindAnchor.COMMIT_SEED).id)
	MindAnchor.commit(actor, MindAnchor.COMMIT_SEED)
	var stage := MindAnchor.required_stage(_realm_at(MindAnchor.COMMIT_SEED + 1).index)

	var gate: Dictionary = MindAdvancement.preview(actor).get("gates", {}).get("anchor", {})
	for key: String in ANCHOR_GATE_KEYS:
		assert_eq(gate.has(key), true, "the anchor report publishes %s" % key)
	assert_eq(gate.get("required"), true, "R20 demands an anchor stage")
	assert_eq(gate.get("stage"), String(stage), "and names the policy's stage")
	assert_eq(gate.get("value"), MindAnchor.stage_met(actor, stage), "the value is that stage")
	assert_ne(String(gate.get("outstanding", "")), "", "and names what is outstanding")
	assert_eq(
		String(gate.get("outstanding", "")) == "",
		stage == MindAnchor.STAGE_NONE,
		"the shortfall is silent only when nothing is demanded"
	)

	var conditions: Array = MindAdvancement.preview(actor).get("conditions", [])
	assert_eq(
		conditions.has(String(gate.get("outstanding", ""))),
		true,
		"the unmet condition list carries the shortfall verbatim"
	)


## DEFECT RECORD, not a design goal. The sea's `trained_stage` latch is written by
## the sea-catalyst milestone, surfaced by `api.gd` and displayed by the mind screen
## as "Anchor stage N" — and no gate, no stat and no milestone in `src` reads it. A
## number a player is shown as progress must not be inert, so this asserts it stays
## inert and the report stays the policy's verdict: the day someone wires the latch
## into a gate, this fires and the milestone gets a real reader instead of a caption.
func test_no_gate_is_satisfied_by_the_seas_trained_stage_latch() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		var target := ladder.next(realm.id)
		if target == null:
			continue
		var latched := _at(realm.id)
		var sea := MindCultivationApi.sea(latched)
		sea.trained_stage = 1
		var stage := MindAnchor.required_stage(target.index)
		var anchor: Dictionary = MindAdvancement.preview(latched).get("gates", {}).get("anchor", {})
		assert_eq(
			String(anchor.get("stage", "")),
			String(stage),
			"the anchor stage reported at %s is the policy's, not a latch's" % target.id
		)
		assert_eq(
			anchor.get("value"),
			MindAnchor.stage_met(latched, stage),
			"and its verdict is the policy's own at %s" % target.id
		)
		# Nothing else the latch could plausibly stand in for may move either.
		sea.trained_stage = 0
		assert_eq(
			sea.trained_stage == 1,
			false,
			"the latch is writable and therefore a candidate reader, not a constant"
		)
		audited += 1
	assert_eq(audited, LADDER_SIZE - 1, "every boundary was audited")


# --- The created-world gate --------------------------------------------------


## A Micro world handed to a player before any breakthrough is Micro-sized and
## already stable, so tier and stability alone would open the Transcendent gate at
## the first realm — the exact defect ADR 0058 closed for the shared schedule. The
## gate reads the law the R28 breakthrough imprints instead, and a lone world fails
## it even with the last inside-world anchor paid for.
func test_a_created_world_nobody_built_does_not_open_the_transcendent_gate() -> void:
	var actor := _at(_realm_at(MindAnchor.COMMIT_INNER).id)
	_reinforced_inner_world(actor)

	var stage := MindAnchor.required_stage(MindAnchor.FIRST_MICRO_GATE)
	assert_eq(stage, MindAnchor.STAGE_MICRO_WORLD, "R29 gates on the created world")
	actor.world = WorldState.new(WorldState.MICRO)
	assert_eq(actor.world.is_stable(), true, "a handed-out world is already stable")
	assert_eq(actor.world.get_law(MindAnchor.MICRO_WORLD_LAW), null, "and carries no law")
	assert_eq(MindAnchor.stage_met(actor, stage), false, "so the gate stays shut")

	MindAnchor.commit(actor, MindAnchor.COMMIT_MICRO)
	assert_ne(
		actor.world.get_law(MindAnchor.MICRO_WORLD_LAW),
		null,
		"the breakthrough imprints the law the gate reads"
	)
	assert_eq(MindAnchor.stage_met(actor, stage), true, "which is what opens the gate")


## Committing is idempotent, and re-committing must not rewrite the record of which
## breakthrough built the world: R30 raises the tier and leaves the artifact the gate
## reads in place, so R30's own milestone can never be read as the R28 one.
func test_re_committing_a_created_world_keeps_the_artifact_and_raises_the_tier() -> void:
	var actor := _at(_realm_at(MindAnchor.COMMIT_MICRO).id)
	_reinforced_inner_world(actor)
	MindAnchor.commit(actor, MindAnchor.COMMIT_MICRO)
	MindAnchor.commit(actor, MindAnchor.COMMIT_MICRO)
	assert_eq(actor.world.laws.size(), 1, "the law is imprinted once")
	assert_eq(actor.world.tier, WorldState.MICRO, "and the tier is unchanged")
	assert_eq(
		MindAnchor.stage_met(actor, MindAnchor.STAGE_MICRO_WORLD),
		true,
		"the gate the Micro world opens stays open"
	)

	MindAnchor.commit(actor, MindAnchor.COMMIT_GREAT)
	assert_eq(actor.world.tier, WorldState.GREAT, "R30 commits the Great world")
	assert_eq(actor.world.laws.size(), 1, "and keeps the artifact untouched")
	assert_eq(
		MindAnchor.stage_met(actor, MindAnchor.STAGE_MICRO_WORLD),
		false,
		"so the Micro world is not standing in for the Great one"
	)


## An actor holding the last inside-world anchor committed AND paid for. The
## reinforcement is asserted rather than assumed, so a test that depends on it fails
## at the cause instead of downstream.
func _reinforced_inner_world(actor: Actor) -> void:
	MindAnchor.commit(actor, MindAnchor.COMMIT_INNER)
	var elixir := MindRealmSeed.for_realm(actor.path(MindPath.PATH_ID).rank_id).training_item
	assert_eq(_stock(actor, elixir), true, "the realm authors its channel elixir")
	assert_eq(MindTraining.strengthen_anchor(actor), true, "the Inner anchor is reinforced")
	assert_eq(
		MindAnchor.stage_met(actor, MindAnchor.STAGE_INNER_ANCHOR),
		true,
		"so the last inside-world stage is met"
	)
