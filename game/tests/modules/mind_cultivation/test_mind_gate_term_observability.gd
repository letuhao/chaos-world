extends TestCase

## BL-0161: `MindBreakthroughCondition.can_breakthrough` is a conjunction, and
## until this suite nothing observed it TERM BY TERM. Deleting the sea-fill
## term, the comprehension term, or the channel term from
## `breakthrough_condition.gd` each left the whole Mind scope green.
##
## ## Why the shipped suites could not have caught it
##
## Two structural facts, not a missing test:
##
## 1. Every shipped assertion that the gate is FALSE uses an actor with ALL
##    gates shut. Removing one conjunct from an already-false conjunction
##    changes nothing, so such a test cannot fail on a one-term deletion.
## 2. No shipped test ever held an actor that satisfied EVERYTHING. Without a
##    fully satisfied pre-state there is no actor with exactly one term
##    broken, which is the only state in which a single conjunct is load
##    bearing.
##
## So the fixture is the fix. `_satisfied()` reaches a state where the gate is
## provably TRUE -- through the production actions, plus the target realm's
## breakthrough pill that `Probe.prepared` deliberately does not stock -- and
## then each test knocks out ONE term and nothing else.
##
## ## The witness that a break was surgical
##
## Each test asserts `_outstanding() == 1` as well as the refusal. That count is
## what separates this from another all-gates-shut assertion: a break that took a
## second clause down with it fails here instead of quietly proving less than it
## claims. The count is read from `preview`, which re-derives the clauses from
## the seeds INDEPENDENTLY of the object under test — which is exactly why the
## refusal itself is asserted through `MindBreakthroughCondition` and not on
## `preview`. A refusal asserted on `preview` alone would survive deleting a
## conjunct from `breakthrough_condition.gd`, because `preview` never reads it.
##
## ## Boundaries, and why more than one
##
## The anchor term is dead weight below the Immortal tier: `_anchor_ready`
## returns true unconditionally for `target.index < 18`, so at R1 it cannot fail
## and no test there could ever observe it. The eight mortal-tier terms are
## therefore broken at R1 -> R2, and the two load-bearing halves of the anchor
## term are broken at the two high-tier boundaries that separate them:
## R18 -> R19, where the anchor term is exactly the tribulation, and R19 -> R20,
## where it additionally demands a committed and REINFORCED anchor.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

## The boundary the eight mortal-tier terms are broken at: R1 -> R2.
const SOURCE := &"qi_refining"

## R18 -> R19: the first boundary whose anchor term demands anything, and it
## demands exactly the tribulation (the stage demanded is STAGE_NONE).
const TIER_BOUNDARY := &"spirit_ascension"

## R19 -> R20: the first boundary whose anchor term additionally demands an
## anchor that was committed by the previous realm AND reinforced, which is
## what separates the term's two halves from one another.
const ANCHOR_BOUNDARY := &"earth_immortal"

## How far below its own threshold a broken term is put. A FRACTION of the
## threshold read off the seed under test, never a typed-in number, so a
## retune of the authored data moves the break with it instead of silently
## leaving it above the requirement.
const STEP := 0.01

# --- The gate, and its witness ------------------------------------------------


## The conjunction under test, read through the very object that owns it.
func _gate(actor: Actor) -> bool:
	return Breakthrough.can_advance(actor, MindPath.PATH_ID, MindBreakthroughCondition.new())


## How many clauses the module independently reports as outstanding.
func _outstanding(actor: Actor) -> int:
	var conditions: Variant = MindAdvancement.preview(actor).get("conditions", [])
	return conditions.size() if conditions is Array else -1


func _clauses(actor: Actor) -> String:
	return str(MindAdvancement.preview(actor).get("conditions", []))


## An actor whose gate is genuinely TRUE.
##
## `Probe.prepared` earns every production-action gate; the target realm's
## breakthrough pill is stocked here from the seed the module itself names,
## because `prepared` deliberately stops short of it. That pill was the second
## reason no shipped test could hold a fully satisfied actor.
func _satisfied(rank_id: StringName) -> Actor:
	var actor := Probe.prepared(rank_id)
	Probe.stock(actor, _target_seed(rank_id).breakthrough_item)
	return actor


## An actor at `ANCHOR_BOUNDARY` with the anchor term's own demands paid.
##
## `earn_anchor_stage` false stops one step short — the anchor is committed and
## trialled but NOT reinforced — which breaks the stage half of `_anchor_ready`
## and nothing else. `WorldAnchor` reads a committed, stable, law-bearing inside
## world while `MindAnchor` additionally requires `anchor_strengthened`, so
## those two reads diverge on exactly this step.
##
## BOTH commits are made, in the order the real breakthrough makes them: core's
## `try_advance` calls `WorldAnchor.commit`, which creates the inside world and
## imprints its law, and then the module's `resolve_attempt` calls
## `MindAnchor.commit`, which creates and trialls the anchor. An actor built at a
## rank has skipped the advance that would have run the first of those, so
## omitting it here would leave `inside_world_ok` shut for a reason that has
## nothing to do with the term under test.
func _anchored(earn_anchor_stage: bool) -> Actor:
	var actor := _satisfied(ANCHOR_BOUNDARY)
	Probe.fight(actor, RealmDefaults.ladder().next(ANCHOR_BOUNDARY))
	WorldAnchor.commit(actor, MindAnchor.COMMIT_SEED)
	MindAnchor.commit(actor, MindAnchor.COMMIT_SEED)
	if earn_anchor_stage:
		Probe.strengthen_anchor(actor)
	return actor


func _target_seed(rank_id: StringName) -> MindRealmSeed:
	return MindRealmSeed.for_realm(RealmDefaults.ladder().next(rank_id).id)


## The pre-state, proved. Every test starts here, so a refusal afterwards is
## attributable to the ONE term it broke and to nothing else.
func _proved_open(actor: Actor, boundary: String) -> void:
	assert_eq(
		_gate(actor), true, "%s: the conjunction is satisfied before any term is broken" % boundary
	)
	assert_eq(
		_outstanding(actor),
		0,
		"%s: and no clause is outstanding to begin with (%s)" % [boundary, _clauses(actor)]
	)


## The conjunction now refuses, on exactly ONE clause, and that clause is named
## in the failure so a mutation is attributable to the term it deleted.
func _refused_on_alone(actor: Actor, term: String, boundary: String) -> void:
	assert_eq(_gate(actor), false, "%s: the %s term alone refuses the gate" % [boundary, term])
	assert_eq(
		_outstanding(actor),
		1,
		(
			"%s: and the %s term is the ONLY clause outstanding, so the break was surgical (%s)"
			% [boundary, term, _clauses(actor)]
		)
	)


# --- Term 1: the progress bar -------------------------------------------------


## `state.progress >= target_seed.progress_required`. The one that is easy to
## overlook: nothing else in the conjunction reads progress, so a deletion here
## retires the whole cultivation budget of all 29 boundaries silently.
func test_the_progress_term_alone_refuses_the_gate() -> void:
	var boundary := "R1 -> R2"
	var seed := _target_seed(SOURCE)
	var actor := _satisfied(SOURCE)
	_proved_open(actor, boundary)
	actor.path(MindPath.PATH_ID).progress = seed.progress_required * (1.0 - STEP)
	_refused_on_alone(actor, "state.progress >= target_seed.progress_required", boundary)


# --- Term 2: the comprehension floor ------------------------------------------


## `actor.stats.derived(COMPREHENSION) >= target_seed.comprehension_required`.
## The break zeroes the BASE stat and then proves the DERIVED value it is read
## through really is under the floor, because a derived bonus is a separate
## surface: without that check this test could report a refusal it had not
## earned.
func test_the_comprehension_term_alone_refuses_the_gate() -> void:
	var boundary := "R1 -> R2"
	var seed := _target_seed(SOURCE)
	var actor := _satisfied(SOURCE)
	_proved_open(actor, boundary)
	actor.stats.set_base(Stat.COMPREHENSION, 0.0)
	actor.mark_stats_dirty()
	assert_eq(
		actor.stats.derived(Stat.COMPREHENSION) < seed.comprehension_required,
		true,
		(
			"the comprehension term is actually broken: derived %s against a floor of %s"
			% [actor.stats.derived(Stat.COMPREHENSION), seed.comprehension_required]
		)
	)
	_refused_on_alone(actor, "derived(COMPREHENSION) >= comprehension_required", boundary)


# --- Term 3: the calm sea -----------------------------------------------------


## `sea.turbulence <= 0.0`, broken the way a deviation breaks it. Turbulence
## LOWERS usable capacity, which RAISES the fill ratio, so it cannot drag the
## sea-fill term down with it — which is what lets the single-clause count hold.
func test_the_turbulence_term_alone_refuses_the_gate() -> void:
	var boundary := "R1 -> R2"
	var actor := _satisfied(SOURCE)
	_proved_open(actor, boundary)
	MindCultivationApi.sea(actor).add_turbulence(0.5)
	_refused_on_alone(actor, "sea.turbulence <= 0.0", boundary)


# --- Term 4: the source realm's clarity milestone ----------------------------


## `sea.clarity >= source_seed.clarity_required` — the SOURCE realm's completed
## milestone, not the target's own training target (ADR 0013/0016/0024).
func test_the_clarity_term_alone_refuses_the_gate() -> void:
	var boundary := "R1 -> R2"
	var source_seed := MindRealmSeed.for_realm(SOURCE)
	var actor := _satisfied(SOURCE)
	_proved_open(actor, boundary)
	MindCultivationApi.sea(actor).set_clarity(source_seed.clarity_required - STEP)
	_refused_on_alone(actor, "sea.clarity >= source_seed.clarity_required", boundary)


# --- Term 5: the source realm's purity milestone -----------------------------


## `sea.purity >= source_seed.purity_required`, the source realm's milestone.
func test_the_purity_term_alone_refuses_the_gate() -> void:
	var boundary := "R1 -> R2"
	var source_seed := MindRealmSeed.for_realm(SOURCE)
	var actor := _satisfied(SOURCE)
	_proved_open(actor, boundary)
	MindCultivationApi.sea(actor).set_purity(source_seed.purity_required - STEP)
	_refused_on_alone(actor, "sea.purity >= source_seed.purity_required", boundary)


# --- Term 6: the full reservoir ----------------------------------------------


## `sea.ratio(actor) >= target_seed.sea_fill_required`, drained to a fraction of
## the TARGET's demand short of it. Draining is the production verb a granted
## breakthrough uses on the sea, so no field is hand-written.
func test_the_sea_fill_term_alone_refuses_the_gate() -> void:
	var boundary := "R1 -> R2"
	var seed := _target_seed(SOURCE)
	var actor := _satisfied(SOURCE)
	_proved_open(actor, boundary)
	var sea := MindCultivationApi.sea(actor)
	var keep := sea.effective_capacity() * maxf(seed.sea_fill_required - STEP, 0.0)
	sea.drain(actor, sea.current(actor) - keep)
	_refused_on_alone(actor, "sea.ratio(actor) >= target_seed.sea_fill_required", boundary)


# --- Term 7: the realm pill ---------------------------------------------------


## `_ITEMS.has_item(actor, target_seed.breakthrough_item)`, spent through the
## inventory's own consume verb. This is the one term a shipped test could
## almost reach on its own — and still could not, because no shipped test held
## an actor that had earned everything else.
func test_the_realm_pill_term_alone_refuses_the_gate() -> void:
	var boundary := "R1 -> R2"
	var seed := _target_seed(SOURCE)
	var actor := _satisfied(SOURCE)
	_proved_open(actor, boundary)
	assert_eq(
		ItemsApi.consume_item(actor, seed.breakthrough_item),
		true,
		"the realm pill was in hand to spend"
	)
	_refused_on_alone(actor, "_ITEMS.has_item(actor, target_seed.breakthrough_item)", boundary)


# --- Term 8: the source realm's channels -------------------------------------


## `_channels_ready(actor, source_seed)`, broken by burning ONE of the source
## realm's demanded meridians — the damage a deviation leaves behind, which
## fails `meets` on the injury flag alone. Burning exactly one of them is what
## keeps the outstanding count at one clause: `_channels_ready` reports a clause
## per unmet channel, so damaging a second would be two terms, not one.
func test_the_channel_term_alone_refuses_the_gate() -> void:
	var boundary := "R1 -> R2"
	var source_seed := MindRealmSeed.for_realm(SOURCE)
	var actor := _satisfied(SOURCE)
	_proved_open(actor, boundary)
	actor.meridians.damage_meridian(source_seed.required_meridians[0])
	_refused_on_alone(actor, "_channels_ready(actor, source_seed)", boundary)


# --- Term 9: the anchor term's shared tier gates -----------------------------


## `_anchor_ready(actor, target)` at R18 -> R19, where that term IS the
## tribulation and nothing else. Below the Immortal tier the term returns true
## unconditionally, so this boundary is the first place it can fail at all —
## which is why no mortal-tier test could have observed it.
func test_the_anchor_terms_tier_gate_alone_refuses_the_gate() -> void:
	var boundary := "R18 -> R19"
	var target := RealmDefaults.ladder().next(TIER_BOUNDARY)
	var ready := _satisfied(TIER_BOUNDARY)
	Probe.fight(ready, target)
	_proved_open(ready, boundary)
	var unfought := _satisfied(TIER_BOUNDARY)
	assert_eq(
		Breakthrough.tribulation_ok(unfought, target.index),
		false,
		"the tribulation owed for %s is genuinely unpaid" % target.id
	)
	_refused_on_alone(unfought, "_anchor_ready(actor, target) / tier_gates_met", boundary)


# --- Term 10: the anchor term's committed stage ------------------------------


## `_anchor_ready(actor, target)` at R19 -> R20, where it ALSO demands an anchor
## the previous realm committed and a milestone reinforced. This is a second,
## separate hole inside the one term: deleting only the `MindAnchor.stage_met`
## half of `_anchor_ready` still opened R20 to an unreinforced anchor, and only
## a boundary that pays the commit but not the reinforcement can see that.
func test_the_anchor_terms_committed_stage_alone_refuses_the_gate() -> void:
	var boundary := "R19 -> R20"
	var unreinforced := _anchored(false)
	var stage := MindAnchor.required_stage(RealmDefaults.ladder().next(ANCHOR_BOUNDARY).index)
	assert_eq(
		MindAnchor.stage_met(unreinforced, stage), false, "the %s anchor is unreinforced" % stage
	)
	_refused_on_alone(unreinforced, "_anchor_ready(actor, target) / MindAnchor.stage_met", boundary)
	_proved_open(_anchored(true), boundary)


# --- The suite's own premise -------------------------------------------------


## The claim every test above rests on, asserted for itself: the conjunction is
## a conjunction, and it has more terms than any one test could break. A reader
## who deleted a term and saw this suite stay green would otherwise have no way
## to tell an unobserved term from an absent one — so the count of terms is
## published here rather than left to the source file.
func test_the_gate_publishes_every_term_this_suite_breaks() -> void:
	var code := Probe.module_code("breakthrough_condition.gd")
	var conjunction := code.substr(code.find("return ("), code.find(")\n", code.find("return (")))
	for term: String in [
		"state.progress >= target_seed.progress_required",
		"actor.stats.derived(Stat.COMPREHENSION) >= target_seed.comprehension_required",
		"sea.turbulence <= 0.0",
		"sea.clarity >= source_seed.clarity_required",
		"sea.purity >= source_seed.purity_required",
		"sea.ratio(actor) >= target_seed.sea_fill_required",
		"_ITEMS.has_item(actor, target_seed.breakthrough_item)",
		"_channels_ready(actor, source_seed)",
		"_anchor_ready(actor, target)",
	]:
		assert_eq(
			conjunction.contains(term),
			true,
			"the %s term is in the conjunction these tests break" % term
		)
