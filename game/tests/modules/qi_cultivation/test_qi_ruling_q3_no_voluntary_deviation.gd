extends TestCase

const Probe := preload("res://tests/modules/qi_cultivation/qi_gate_probe.gd")

## The deviation is still REACHABLE. Deleting the voluntary verb must not have
## quietly deleted the consequence: a failed roll still halves progress, scars the
## dantian and burns a channel. This is the half of Q3 that was already sound and
## had to be preserved.
##
## The roll is not forced by poking the generator's state — that couples the test to
## Godot's PCG internals. Instead it searches a SMALL, BOUNDED span of seeds for one
## whose first `randf` loses against this actor's real chance, and reports if none
## does. `ROLL_SEED_BOUND` is the canary: the loop cannot run away, because it moves
## a counter it reads and stops at the bound (INC-0002).
const ROLL_SEED_BOUND := 64

## ADR 0180, ruling Q3: there is NO voluntary-deviation verb on the qi path, and
## this suite fails the build if one returns.
##
## The brief recorded the defect correctly and named the wrong fix. `QiAdvancement.
## cancel_attempt` (`advancement.gd:32`) forwarded to `QiBreakthroughTransaction.
## cancel`, which called `_deviate` — halving progress, scarring the dantian and
## burning a channel — and had zero callers. The suggested remedy was to publish it
## on the facade. That would have shipped a damage button.
##
## What re-deriving the code settles, and it is not what the deferred entry assumed:
##
## - **Body and mind cancel a real attempt.** Both store a `BodyAttempt` /
##   `MindAttempt` with a `trial_complete` flag, and both `cancel` the COMMITTED
##   one: `BodyAdvancement._end` (:289-296) and `MindAdvancement._end` (:482-489)
##   both call `committed.cancel()`. Their docs say the same thing — "the pill stays
##   spent and no deviation is owed: the trial never ran" (body :300-301, mind
##   :493-494). So on those two paths `cancel` is a REFUND, and its precondition is
##   an attempt that exists.
## - **Qi has no attempt to cancel.** `QiBreakthroughTransaction.execute`
##   (:92-168) validates, consumes the pill, rolls and resolves in ONE call. There
##   is no `QiAttempt`, no committed record, no `trial_complete` — `rg` finds no
##   such symbol anywhere in the module. The qi path is single-phase.
## - **So qi's `cancel` was the semantic opposite of its siblings' under the same
##   name**: they refund a deviation, it inflicts one unconditionally, with no roll
##   and no pill spent. A player reading `cancel_attempt` would halve their own
##   progress and scar their core.
##
## The involuntary path is unaffected and was never the question: `_deviate` still
## fires from `execute` on a failed roll (`breakthrough_transaction.gd:136-138`),
## and `QiChance` keeps the failure band open (`MIN_CHANCE` 0.05, `MAX_CHANCE` 0.95,
## quality-bounded), so failure reachability is unchanged. What is gone is the one
## door onto `_deviate` that needed no roll at all.
##
## Assertions are STRUCTURAL (a name is absent) because the thing being forbidden
## is a name. A behavioural test would have to assert that a verb which must not
## exist returns false — which passes for a verb that is absent for the wrong reason.


## The verb is gone from the advancement surface. Matched on the DECLARATION, not
## the bare name: `advancement.gd` names `cancel_attempt` in the comment explaining
## why it is absent, and a substring match would read that explanation as the defect.
func test_advancement_has_no_cancel_attempt() -> void:
	var script := FileAccess.get_file_as_string("res://src/modules/qi_cultivation/advancement.gd")
	assert_eq(
		script.contains("func cancel_attempt"),
		false,
		"QiAdvancement.cancel_attempt is back; it inflicts a deviation with no roll"
	)
	var facade := FileAccess.get_file_as_string("res://src/modules/qi_cultivation/api.gd")
	assert_eq(
		facade.contains("func cancel_attempt"),
		false,
		"and it is not published on the facade either (DEF-0227's suggested fix)"
	)


## `_deviate` has exactly ONE caller, and it is the failed roll inside `execute`.
## This is the assertion that carries the ruling: a voluntary door is not a second
## `public` verb somebody forgets to publish, it is a second CALL SITE.
## And from the transaction, which is where the only forwarder lived.
func test_the_transaction_has_no_cancel() -> void:
	var script := FileAccess.get_file_as_string(
		"res://src/modules/qi_cultivation/breakthrough_transaction.gd"
	)
	assert_eq(
		script.contains("func cancel("),
		false,
		(
			"QiBreakthroughTransaction.cancel is back; the qi path is single-phase and has "
			+ "no attempt to abandon"
		)
	)


## `_deviate` has exactly ONE caller, and it is the failed roll inside `execute`.
## This is the assertion that carries the ruling: a voluntary door is not a second
## `public` verb somebody forgets to publish, it is a second CALL SITE.
func test_deviate_is_reachable_only_from_a_failed_roll() -> void:
	var script := FileAccess.get_file_as_string(
		"res://src/modules/qi_cultivation/breakthrough_transaction.gd"
	)
	var calls := 0
	var roll_branch := false
	var lines := script.split("\n")
	# Bounded by the file's own line count; the counter moves once per pass and no
	# body appends to the container it walks (INC-0002).
	for index in range(lines.size()):
		var line := String(lines[index]).strip_edges()
		if line.begins_with("_deviate("):
			calls += 1
		if line.begins_with("if roll >= chance:") and index + 1 < lines.size():
			roll_branch = String(lines[index + 1]).strip_edges().begins_with("_deviate(")
	assert_eq(calls, 1, "_deviate must have exactly one call site, the failed roll")
	assert_eq(roll_branch, true, "and that call site must be the failed-roll branch")


func test_a_failed_roll_still_deviates() -> void:
	Probe.clear_prepared()
	var seed := Probe.target_seed_after(&"qi_refining")
	assert_ne(seed, null, "the boundary has a seed")
	var chance := QiChance.of(Dantian.new())
	assert_eq(chance > 0.0, true, "the roll has a chance to be lost")

	var hero := Probe.prepared(&"qi_refining", seed)
	assert_ne(hero, null, "a fully prepared actor standing before the boundary")
	var state := hero.path(QiPath.PATH_ID)
	var dantian := QiTestKit.dantian(hero)
	assert_ne(dantian, null, "and a dantian")
	var progress_at_gate: float = state.progress
	assert_eq(
		progress_at_gate > 0.0,
		true,
		"sanity: the probe earned progress, so a halving is observable"
	)
	var this_chance := QiChance.of(dantian)

	# `execute` draws exactly ONE roll at this boundary: `face_tribulation` returns
	# early below R19 because no tribulation is owed (`breakthrough.gd:201-202`), so
	# the search must not CONSUME the draw it is testing. Each candidate is probed
	# with one generator and handed over as a FRESH one carrying the same seed, so
	# `execute`'s first draw is the draw that was measured.
	var losing_seed := -1
	var tried := 0
	while losing_seed < 0 and tried < ROLL_SEED_BOUND:
		var probe_rng := RandomNumberGenerator.new()
		probe_rng.seed = tried
		if probe_rng.randf() >= this_chance:
			losing_seed = tried
		tried += 1
	assert_eq(losing_seed >= 0, true, "a losing roll exists inside the seed span")
	if losing_seed < 0:
		return
	var losing := RandomNumberGenerator.new()
	losing.seed = losing_seed

	var advanced := QiBreakthroughTransaction.execute(hero, losing)
	assert_eq(advanced, false, "a lost roll never advances the realm")
	assert_eq(
		dantian.injured,
		true,
		"and it deviates: the dantian is scarred, exactly as the failed roll always did"
	)
	assert_eq(
		state.progress < progress_at_gate, true, "progress is halved rather than merely not granted"
	)
	var burned := false
	for channel in hero.meridians.get_all_meridians():
		if channel.is_injured():
			burned = true
	assert_eq(burned, true, "and a channel the gate depended on is burned")
