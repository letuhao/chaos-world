extends TestCase

## ADR 0172: an anchor TRIAL is not a third paid act, so the flag it needed is gone.
##
## `InsideWorld.anchor_trial_passed` was a conjunct of `MindAnchor._inside_ok` that
## no actor could ever fail: both commits called `pass_anchor_trial()` on the line
## after `create_anchor()`, so `anchor_created` implied it. That made two things
## untrue at once — the conjunct constrained nothing, and the shortfall string it
## guarded, `"anchor trial not passed"`, was unreachable by any legal player.
##
## A conjunction that cannot be false is a lie in a conjunction, so it was REMOVED
## rather than commented. Reinforcement is the one paid clause and it is paid with a
## verb; the trial was paid by nothing.
##
## ## Why this file is mostly SOURCE-reading, and the rule it follows
##
## Two of the three things that had to be proven cannot be proven by behaviour. An
## unfailable conjunct does not change what any actor can do, so restoring it leaves
## every value assertion green — exactly the failure `tests/core/test_realm_rate.gd`
## was written for, where a numerically identical fourth copy of the rate curve
## passed everything. And the removed `improve_stability(0.1)` loop sat behind a
## condition that was already false when it was written, so restoring it is also
## invisible to behaviour. Only reading the source sees either.
##
## Every scan below therefore carries an UNCONDITIONAL liveness term: an assertion
## with no filter and no dependence on the thing being scanned, proving the scanner
## read something. Three guards in this repo passed for years while asserting
## nothing, and a scan that returns an empty list vacuously satisfies every
## "contains no X" check ever written against it.

## Every `.gd` file under `res://src`. Enough that a scan which silently read
## nothing cannot clear the floor: the tree is ~500 and grows, so this only fires
## on a broken scan or a deleted tree.
const MIN_SOURCE_FILES := 200

## The retired names. Field, writer, and the string the removed conjunct guarded —
## all three, because a partial restore compiles and is just as dead.
const RETIRED := ["anchor_trial_passed", "pass_anchor_trial", "anchor trial not passed"]

const ANCHOR_PATH := "res://src/core/inside_world.gd"
const SHARED_COMMIT_PATH := "res://src/core/world_anchor.gd"

## The removed convergence loop's guard, so this file does not re-derive the number.
const STABILITY_FLOOR := 0.5

## Every stage this file probes, with the tier that stage's gate reads and a tier it
## does not. Pairing them matters: the wrong-tier row is only a wrong tier if it is
## genuinely a different one, so the probe reads the pair from `MindAnchor`'s own
## vocabulary rather than restating which tier means what.
const STAGES := [
	[MindAnchor.STAGE_SEED_ANCHOR, InsideWorld.SEED, InsideWorld.INNER],
	[MindAnchor.STAGE_POCKET_ANCHOR, InsideWorld.POCKET, InsideWorld.INNER],
	[MindAnchor.STAGE_INNER_ANCHOR, InsideWorld.INNER, InsideWorld.SEED],
]


## Every source file under `res://src`, through the shared depth-capped walk. Not a
## local `_scan`: `ContentScan` is the one implementation and the arch rule can see
## its bound.
func _sources() -> Array[String]:
	return ContentScan.files_under("res://src", ".gd")


## The body of one `static func`, as written, from its signature to the next
## top-level `func`, with COMMENT lines dropped. Extracted rather than
## pattern-matched in place so the guard is about what the function DOES, not about
## whether a token appears anywhere in the file — `world_anchor.gd` legitimately
## writes `actor.world.stability` in a different function, and its prose legitimately
## discusses stability. Only the code is the behaviour.
func _function_body(path: String, signature: String) -> String:
	var source := FileAccess.get_file_as_string(path)
	var start := source.find(signature)
	if start < 0:
		return ""
	var from_end := source.find("\n", start)
	if from_end < 0:
		return ""
	var body := ""
	for line in source.substr(from_end).split("\n"):
		if line.begins_with("static func ") or line.begins_with("func "):
			break
		if line.strip_edges().begins_with("#"):
			continue
		body += line + "\n"
	return body


## Nothing under `res://src` may name the trial again. This is the guard that catches
## the restoration the other two cannot: the conjunct, the string, and the field are
## one shape, and the field's absence is what makes the other two a compile error
## rather than a silent lie.
func test_no_source_file_names_the_retired_anchor_trial() -> void:
	var sources := _sources()
	# UNCONDITIONAL liveness: the scan is proven to have read the tree before any
	# "found nothing" assertion is allowed to count.
	assert_eq(
		sources.size() >= MIN_SOURCE_FILES,
		true,
		"the scan read %d files, so a vacuous pass is impossible" % sources.size()
	)
	for path in sources:
		var source := FileAccess.get_file_as_string(path)
		# UNCONDITIONAL liveness per file: it read a script, not an empty string.
		assert_ne(source, "", "%s was read by the scan" % path)
		for retired in RETIRED:
			assert_eq(
				source.contains(retired),
				false,
				"%s names %s — a trial no verb can fail is not a gate (ADR 0172)" % [path, retired]
			)


## The scan above would pass on an empty tree, so it is pinned against the two files
## that carried the defect BY NAME: this asserts each is still readable and still
## carries the flags that survived, so the scan is anchored to real content.
func test_the_two_defect_files_are_readable_and_still_carry_the_surviving_anchors() -> void:
	for path in [ANCHOR_PATH, SHARED_COMMIT_PATH]:
		var source := FileAccess.get_file_as_string(path)
		assert_ne(source, "", "%s is readable" % path)
	assert_eq(
		FileAccess.get_file_as_string(ANCHOR_PATH).contains("var anchor_created"),
		true,
		"the field that remains is still declared where it was"
	)
	assert_eq(
		FileAccess.get_file_as_string(ANCHOR_PATH).contains("func create_anchor()"),
		true,
		"and its writer survives, or the surviving flag is also unreachable"
	)


## A payload written by this build carries no retired key, and every fact it does
## carry survives the trip. Direction one of the round trip.
func test_a_payload_written_by_this_build_round_trips() -> void:
	var world := InsideWorld.new(InsideWorld.INNER, 50.0, 0.8, 3.0, 5.0)
	world.add_law(&"fire", 0.8)
	world.add_law(&"earth", 0.6)
	world.create_anchor()
	# 0.8 in, and the milestone must leave it EXACTLY there: `strengthen_anchor` pays the
	# flag, not a number (BL-0830), so this pins that it raises nothing. The round trip
	# is taken through the production verbs, not by writing the flag.
	world.strengthen_anchor()
	assert_eq(world.stability, 0.8, "and the milestone moved no stability at all")
	var data := world.to_dict()
	assert_eq(
		data.has("anchor_trial_passed"),
		false,
		"the writer emits no retired key, so a save is smaller than it was"
	)
	assert_eq(data["anchor_created"], true, "the created anchor is written")
	assert_eq(data["anchor_strengthened"], true, "and the paid one")
	var restored := InsideWorld.from_dict(data)
	assert_eq(restored.tier, InsideWorld.INNER, "tier survives")
	assert_eq(restored.size, 50.0, "size survives")
	assert_eq(restored.stability, 0.8, "stability survives")
	assert_eq(restored.qi_density, 3.0, "qi_density survives")
	assert_eq(restored.time_flow, 5.0, "time_flow survives")
	assert_eq(restored.get_law(&"fire"), 0.8, "one law survives")
	assert_eq(restored.get_law(&"earth"), 0.6, "and the other")
	assert_eq(restored.anchor_created, true, "the created anchor is restored")
	assert_eq(restored.anchor_strengthened, true, "and the paid one")


## A payload written by an OLDER build — one that still writes the retired key —
## still loads. This is the direction the change could have broken, and the repo's
## rule for it is `Actor.from_dict`'s own: a field the schema does not read is
## IGNORED, never refused, so a load never fails on it. Refusing here would be
## worse than the defect: every existing save would be thrown away to protect a
## boolean nothing read.
func test_a_payload_carrying_the_retired_key_still_loads() -> void:
	var old_payload := {
		"tier": "inner",
		"size": 50.0,
		"stability": 0.9,
		"qi_density": 3.0,
		"time_flow": 5.0,
		"laws": {"fire": 0.8},
		"anchor_created": true,
		"anchor_trial_passed": true,
		"anchor_strengthened": true,
	}
	var restored := InsideWorld.from_dict(old_payload)
	assert_ne(restored, null, "a payload carrying the retired key loads rather than erroring")
	assert_eq(restored.tier, InsideWorld.INNER, "the tier it named still reads")
	assert_eq(restored.stability, 0.9, "and its stability, which the key sits beside")
	assert_eq(restored.get_law(&"fire"), 0.8, "and its laws")
	assert_eq(restored.anchor_created, true, "and the anchor flags that still exist")


## The same thing through the REAL save path, because the field-level test would
## pass while `Actor`'s payload plumbing dropped or refused the slot.
func test_an_actor_payload_carrying_the_retired_key_still_loads() -> void:
	var actor := Actor.new(&"trial_hero", {})
	actor.inside_world = InsideWorld.new(InsideWorld.POCKET, 2.0, 0.7, 1.0, 1.0)
	actor.inside_world.add_law(&"heaven", 1.0)
	actor.inside_world.create_anchor()
	var payload := actor.to_dict()
	# What an older build's file looks like: the retired key, present and true.
	payload["inside_world"]["anchor_trial_passed"] = true
	var restored := Actor.from_dict(payload)
	assert_ne(restored, null, "the actor loads")
	assert_ne(restored.inside_world, null, "and so does its inside world")
	assert_eq(restored.inside_world.tier, InsideWorld.POCKET, "at the tier it was saved at")
	assert_eq(restored.inside_world.anchor_created, true, "with the anchor it had created")
	assert_eq(restored.inside_world.get_law(&"heaven"), 1.0, "and the law the gate reads")
	assert_eq(
		restored.to_dict()["inside_world"].has("anchor_trial_passed"),
		false,
		"and re-saving it does not resurrect the key"
	)


## Every conjunct of the anchor gate is falsifiable by a state a player can legally
## reach. This is the guard against the defect RETURNING as a new conjunct: a term
## no state can fail is not a gate, and no behavioural assertion can see one that is
## added beside the removed one.
##
## These rows FORGE the flags, which is the only way to isolate one conjunct while
## the others hold. "The gate still opens" is deliberately NOT asserted here — see
## `test_the_anchor_gate_opens_on_an_actor_built_by_production_verbs`, which builds
## that state the way the game builds it.
func test_every_conjunct_of_the_anchor_gate_is_falsifiable() -> void:
	for row in STAGES:
		var stage: StringName = row[0]
		var tier: StringName = row[1]
		var other: StringName = row[2]
		assert_eq(
			_gate_open(stage, tier, false, false, 0.5), false, "%s is shut on a bare actor" % stage
		)
		assert_eq(
			_gate_open(stage, tier, true, false, 0.5),
			false,
			"%s is shut when the anchor is created but unpaid" % stage
		)
		assert_eq(
			_gate_open(stage, tier, false, true, 0.5),
			false,
			"%s is shut when the anchor is paid but never created" % stage
		)
		assert_eq(
			_gate_open(stage, tier, true, true, 0.4),
			false,
			"%s is shut on an unstable world" % stage
		)
		assert_eq(
			_gate_open(stage, other, true, true, 0.5),
			false,
			"%s is shut on the wrong tier however paid" % stage
		)


## The gate must still OPEN, or the removal traded a lie for a soft-lock.
##
## Built through the production verbs rather than by forging flags, because a forged
## state answers a different question. The forged table above once carried an
## "it opens" row, and mutation showed it reporting a shut gate that a real actor
## walks straight through — the fixture, not the gate, was what it was measuring.
func test_the_anchor_gate_opens_on_an_actor_built_by_production_verbs() -> void:
	var actor := Actor.new(&"trial_hero", {})
	MindAnchor.commit(actor, MindAnchor.COMMIT_SEED)
	assert_ne(actor.inside_world, null, "the commit produced a Seed world")
	assert_eq(actor.inside_world.anchor_created, true, "which the commit anchored")
	assert_eq(actor.inside_world.anchor_strengthened, false, "and left unpaid, as it must")
	assert_eq(
		MindAnchor.stage_met(actor, MindAnchor.STAGE_SEED_ANCHOR),
		false,
		"so the gate is shut on the very actor that created the anchor"
	)
	actor.inside_world.strengthen_anchor()
	assert_eq(
		MindAnchor.stage_met(actor, MindAnchor.STAGE_SEED_ANCHOR),
		true,
		"and paying the milestone opens it — the removal introduced no soft-lock"
	)
	assert_eq(
		MindAnchor.outstanding(actor, MindAnchor.STAGE_SEED_ANCHOR),
		"",
		"with nothing outstanding once it is paid"
	)


## The reported shortfall is reachable and never the retired one. Walks the shut
## states above and requires a NON-EMPTY string exactly when the gate is shut — a
## gate that refuses silently and a gate that reports a fiction are both failures.
func test_the_shortfall_is_reachable_and_never_names_the_retired_trial() -> void:
	for row in STAGES:
		var stage: StringName = row[0]
		for state in [
			[row[1], false, false, 0.5],
			[row[1], true, false, 0.5],
			[row[1], false, true, 0.5],
			[row[1], true, true, 0.4],
			[row[2], true, true, 0.5],
		]:
			var actor := _actor_with(state[0], state[1], state[2], state[3])
			var outstanding := MindAnchor.outstanding(actor, stage)
			assert_eq(
				outstanding == "",
				MindAnchor.stage_met(actor, stage),
				"%s reports exactly when it is shut (%s)" % [stage, outstanding]
			)
			assert_ne(outstanding, "", "%s explains itself (%s)" % [stage, stage])
			assert_eq(
				outstanding.contains("trial"),
				false,
				"%s never reports a trial, which no verb performs (%s)" % [stage, outstanding]
			)


## The root of the removed loop: an inside world is born AT the threshold
## `is_stable` demands, so no commit ever had a shortfall to close. Stated as a
## behavioural fact, because the source scan below can only say the code agrees.
func test_an_inside_world_is_born_stable_so_the_removed_loop_had_no_shortfall() -> void:
	var fresh := InsideWorld.new(InsideWorld.SEED)
	assert_eq(fresh.stability, STABILITY_FLOOR, "a fresh world starts exactly at the floor")
	assert_eq(fresh.is_stable(), true, "so it already satisfies its own threshold")
	# And the shared commit leaves it exactly where the constructor put it: the
	# removed convergence loop took zero steps, on this state and on every other.
	var actor := Actor.new(&"commit_hero", {})
	WorldAnchor.commit(actor, WorldAnchor.COMMIT_SEED)
	assert_ne(actor.inside_world, null, "the shared commit produced a world")
	assert_eq(
		actor.inside_world.stability,
		InsideWorld.new(InsideWorld.SEED).stability,
		"and the commit moved its stability by nothing"
	)
	assert_eq(actor.inside_world.is_stable(), true, "so the committed world is stable")


## `_commit_inside_world` writes no stability at all. Named per FUNCTION so the
## created world's own convergence loop — which is live, because
## `modules/world/api.gd` really does lower a created world's stability — is not
## mistaken for the inside-world one that was dead.
func test_the_shared_inside_world_commit_writes_no_stability() -> void:
	var body := _function_body(SHARED_COMMIT_PATH, "static func _commit_inside_world")
	# UNCONDITIONAL liveness: the extractor found the function. Without this, an
	# empty body would satisfy every "contains no" assertion below.
	assert_ne(body, "", "%s was found and its body extracted" % SHARED_COMMIT_PATH)
	assert_eq(
		body.contains("stability"),
		false,
		(
			"the inside-world commit stabilises nothing, because a fresh world is born at"
			+ " the threshold and nothing lowers it — a convergence loop here has an"
			+ " unsatisfiable guard (ADR 0172)"
		)
	)
	# And the created world's loop is still there, so this guard is not satisfied by
	# the file having lost both of them.
	var created := _function_body(SHARED_COMMIT_PATH, "static func _commit_created_world")
	assert_ne(created, "", "the created-world commit was found too")
	assert_eq(
		created.contains("stability"),
		true,
		"a CREATED world can be destabilised, so its convergence loop is live"
	)


## What makes the removed loop permanently dead rather than dead today: no writer
## anywhere in `res://src` can take an INSIDE world below the threshold. A negative
## `improve_stability`, or an assignment to an `inside_world`'s stability, would
## revive it.
func test_no_production_writer_can_destabilise_an_inside_world() -> void:
	var sources := _sources()
	assert_eq(
		sources.size() >= MIN_SOURCE_FILES,
		true,
		"the scan read %d files, so a vacuous pass is impossible" % sources.size()
	)
	for path in sources:
		var source := FileAccess.get_file_as_string(path)
		assert_ne(source, "", "%s was read by the scan" % path)
		# A negative amount is the only way `improve_stability` can lower one.
		assert_eq(
			source.contains("improve_stability(-"),
			false,
			"%s destabilises an inside world, which would revive the removed loop" % path
		)
		# And a direct write to one, which is how a `WorldState` stability gets
		# lowered today — narrowed to inside worlds by the two-part pattern.
		assert_eq(
			(
				source.contains("inside_world.stability =")
				or source.contains("inside_world.stability -=")
			),
			false,
			"%s writes an inside world's stability directly" % path
		)


## A helper holding one of the states the gate is asked about. The flags are set
## directly rather than through production verbs, because the question here is which
## CONJUNCTS exist, not which verbs reach them — and a forged state is the only way
## to isolate one term while the others hold.
##
## `stability` is assigned LAST and unconditionally, so the probe's own stability input
## is the number asked for and not a leftover of the verbs run above. (`strengthen_anchor`
## used to raise it by 0.1 on the way through; it sets no stability at all since BL-0830.)
func _actor_with(tier: StringName, created: bool, strengthened: bool, stability: float) -> Actor:
	var actor := Actor.new(&"trial_hero", {})
	var world := InsideWorld.new(tier)
	if created:
		world.create_anchor()
	if strengthened:
		world.strengthen_anchor()
	world.stability = stability
	actor.inside_world = world
	return actor


func _gate_open(
	stage: StringName, tier: StringName, created: bool, strengthened: bool, stability: float
) -> bool:
	return MindAnchor.stage_met(_actor_with(tier, created, strengthened, stability), stage)
