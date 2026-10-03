extends TestCase

## BL-0629: `NpcStageDef.advance_after` was `0` on every shipped stage, so
## `NpcApi.tally`'s trigger `if current.advance_after > 0` could never pass and the whole
## progression mechanic was theatre. These assert against the AUTHORED content loaded
## from disk, not a hand-installed fixture — a suite that installs its own defs would
## pass against an implementation whose shipped content is inert.

const ELDER := &"elder_wei"
const SMITH := &"smith_bearcutter"
const CAST_ROOT := "res://data/npc/cast"


func setup() -> void:
	NpcCatalog.instance().reset()
	NpcRegistry.instance().reset()
	NpcCatalog.instance().load_authored()


func teardown() -> void:
	NpcRegistry.instance().reset()


func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	NpcApi.set_minter(func(_def: NpcDef, _role: StringName = &"npc") -> Actor:
		return Actor.new(&"npc")
	)
	NpcApi.attach(actor)
	return actor


## The defect in one assertion: at least one shipped stage must carry a threshold, or
## `tally` cannot move anybody.
func test_shipped_content_carries_a_stage_threshold_tally_can_cross() -> void:
	var thresholded := 0
	for npc_id in NpcCatalog.instance().npc_ids():
		var def := NpcCatalog.instance().definition(npc_id)
		if def == null:
			continue
		for stage in def.stages:
			if stage.advance_after > 0:
				thresholded += 1
	assert_ne(
		thresholded,
		0,
		"at least one authored stage names a tally threshold, or advance_stage is unreachable"
	)


func test_the_elder_starts_at_a_stage_that_has_one() -> void:
	var elder := NpcCatalog.instance().definition(ELDER)
	assert_ne(elder, null, "the elder loads from disk")
	var first := elder.stage(elder.starting_stage_id())
	assert_ne(first, null, "he has a starting stage")
	assert_ne(
		first.advance_after,
		0,
		"and his FIRST stage is the one a tally can move, not a dead rung"
	)


## The end-to-end claim: tallying the elder enough times advances him a rung. This is the
## assertion that would have failed before BL-0629, because every shipped stage was 0.
func test_tallying_the_elder_past_the_threshold_advances_him_a_rung() -> void:
	var player := _player()
	NpcApi.spawn(ELDER)
	assert_eq(NpcApi.summary(ELDER)["stage_id"], "gatekeeper", "he starts as a gatekeeper")
	var first := NpcCatalog.instance().definition(ELDER).stage("gatekeeper")
	var needed: int = first.advance_after
	# One short of the threshold: still a gatekeeper.
	for _i in range(needed - 1):
		NpcApi.tally(ELDER, &"favours")
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"gatekeeper",
		"one favour short of the threshold does not move him"
	)
	NpcApi.tally(ELDER, &"favours")
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"sworn_servant",
		"the favour that crosses the threshold advances him"
	)


func test_an_unknown_verb_does_not_cross_a_threshold_it_does_not_earn() -> void:
	var player := _player()
	NpcApi.spawn(ELDER)
	var needed: int = NpcCatalog.instance().definition(ELDER).stage("gatekeeper").advance_after
	for _i in range(needed + 4):
		NpcApi.tally(ELDER, &"unrelated_verb")
	assert_eq(
		NpcApi.summary(ELDER)["stage_id"],
		"gatekeeper",
		"a different verb accumulates its own tally and never crosses this threshold"
	)