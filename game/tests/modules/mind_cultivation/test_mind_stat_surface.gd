extends TestCase

## BL-0154 and BL-0163: the mind module's emitted stat surface, and the proof that
## filling the Sea of Consciousness is not inert.
##
## ## What this file asserts, and what it deliberately does not
##
## BL-0154 reported "filling the sea changes no stat that anything reads" and
## named `MindProvider`'s discarded `mind_power_ratio`. The discarded local was
## real and is gone. The *conclusion* was wrong, and the difference matters:
## `MindBreakthroughCondition` gates on `seed.sea_fill_required`, which every one
## of the 30 seeds authors as `1.0`, and `MindTraining.cultivate` is the only
## thing that fills the reservoir. So a full sea is a HARD precondition of every
## one of the 29 breakthroughs, and the second half of this file proves it by
## flipping one clause of one gate with one production action.
##
## The other half is the emitted id set, asserted exactly. A provider that grows
## an unread stat is how BL-0104, BL-0114, BL-0163 and this file's deletions all
## happened, so the set is a shape assertion rather than a value assertion: four
## ids the module published with no reader were DELETED, and a shape test is the
## only thing that notices the fifth appearing tomorrow.

const Probe := preload("res://tests/modules/mind_cultivation/mind_gate_probe.gd")

const RANK := &"qi_refining"
const TARGET := &"foundation"

## The mind provider's whole published surface. `mental_defense` is here on
## purpose even though nothing reads it yet: ADR 0071 names it as the mitigation
## input of `MindDamage`, whose nine tuning numbers already exist in
## `combat_tuning.gd` defaulted to 0.0. That is a seam with an accepted ADR behind
## it, not dead content, and `test_mind_stats.gd` is what stops the four deleted
## ids coming back.
const PROVIDER_SURFACE := [
	MindStats.MENTAL_ATTACK,
	MindStats.MENTAL_DEFENSE,
	MindStats.SPIRITUAL_SENSE_RANGE,
	MindStats.MIND_CLARITY,
	MindStats.MIND_VEIL,
	MindStats.ILLUSION_RESISTANCE,
	MindStats.MIND_TECHNIQUE_POWER,
]

## The sea's whole published surface. Clarity, turbulence and fullness were
## deleted (BL-0163): the first two restated component fields ADR 0071 reads off
## the component, and the third was a second, disagreeing definition of "full".
const SEA_SURFACE := [MindStats.SEA_CAPACITY]


func _actor() -> Actor:
	var actor := (
		Actor
		. new(
			&"mind_surface",
			{
				Stat.SPIRIT: 10.0,
				Stat.WILL: 10.0,
				Stat.COMPREHENSION: 10.0,
				MindStats.PERCEPTION: 20.0,
				MindStats.MENTAL_CLARITY: 15.0,
			}
		)
	)
	actor.set_path(PathState.new(MindPath.PATH_ID, RANK))
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	return actor


## Exactly these ids, no more. A value assertion could not see a sixth unread
## stat; this can, and it names the one that would be missing.
func test_the_mind_provider_publishes_exactly_its_authored_surface() -> void:
	var actor := _actor()
	var emitted: Dictionary = MindProvider.new().contribute(actor.stats._context)
	var keys: Array = emitted.keys()
	keys.sort()
	var expected: Array = PROVIDER_SURFACE.duplicate()
	expected.sort()
	assert_eq(keys, expected, "the provider's published surface is exactly this list")


func test_the_sea_provider_publishes_exactly_its_authored_surface() -> void:
	var actor := _actor()
	var emitted: Dictionary = SeaProvider.new().contribute(actor.stats._context)
	var keys: Array = emitted.keys()
	keys.sort()
	assert_eq(keys, SEA_SURFACE, "capacity is the whole sea surface")


## The absent case, stated: no sea means no contribution at all rather than a zero
## capacity somebody downstream has to know to distrust.
func test_no_sea_component_means_no_contribution() -> void:
	var actor := Actor.new(&"bare", {Stat.WILL: 10.0, MindStats.MENTAL_CLARITY: 15.0})
	# `attach` is deliberately NOT called here. It used to leave the actor sea-less,
	# which is how this test built the absent case -- but ADR 0095's shape now makes the
	# sea part of the path, so `attach` guarantees one (BL-0523). Calling it would make
	# the absent case unreachable and this assertion would silently stop testing
	# anything. A bare actor is the honest way to have no sea.
	var emitted: Dictionary = SeaProvider.new().contribute(actor.stats._context)
	assert_eq(emitted, {}, "nothing to say without a sea")


## Nothing published by either provider may answer to a rate core already owns.
## `comprehension_bonus` was exactly this bug: core's `Stat.INSIGHT_GAIN` term
## plus a realm-rate term, on a quantity `MindTraining._grant_insight` reads
## `Stat.INSIGHT_GAIN` for. One dial per quantity, or a gate gets priced twice
## through two numbers that will drift.
##
## ## Probed, not listed
##
## This used to build `shared` from `Stat.RATE_STATS` and assert no published key was in
## it. That inferred OWNERSHIP from a list whose membership is a claim about SHAPE: BL-0675
## registered `mind_focus_chance`, `mind_avoidance` and `illusion_resistance` there — they
## were genuinely rates, and a FLAT on one had to be refused. ADR 0215 removed their caps,
## so all three are MAGNITUDES and left `RATE_STATS` entirely; the ids in this file moved
## with that (they are `mind_clarity` / `mind_veil` now), which is why the list-comparison
## version would have quietly stopped guarding anything. `test_mind_renamed_stat_ids.gd`
## had the same inference and the same repair; `test_combat_stats_shape.gd:116` is where
## the probe idiom came from, after BL-0362 recorded that the list comparison had passed a
## real `penetration` collision because core's derived ids are in no list at all.
func test_the_module_publishes_no_second_dial_on_a_shared_rate() -> void:
	var actor := _actor()
	var emitted: Dictionary = MindProvider.new().contribute(actor.stats._context)
	assert_ne(emitted.size(), 0, "the provider published something to judge")
	# No provider is attached to `probe`, and every base attribute is generous, so a
	# core-derived id reads non-zero while a module-owned one reads exactly 0.0.
	var generous := {}
	for stat_id in Stat.BASE_ATTRIBUTES:
		generous[stat_id] = 100.0
	var probe := Actor.new(&"probe", generous)
	for key in emitted:
		assert_almost_eq(
			probe.stats.derived(key),
			0.0,
			(
				(
					"%s is derived by nothing, so no other owner can reach it -- a non-zero "
					% String(key)
				)
				+ "here means core or another provider already owns this string"
			)
		)
	# The negative control, so the probe is falsifiable rather than vacuous.
	assert_ne(
		probe.stats.derived(Stat.CRIT_CHANCE),
		0.0,
		"core's own CRIT_CHANCE is non-zero on this probe"
	)


## The two locals BL-0154 named, plus the one it missed: `Stat.SPIRIT` was read
## into `spirit` and fed nothing. Reading source is the only check that works --
## an unused local has no value to compare and no runtime symptom at all, which is
## precisely why it survived. Comment lines are stripped so the docblock recording
## the deletion does not fail its own guard.
func test_the_provider_computes_nothing_it_does_not_publish() -> void:
	var code := Probe.module_code("provider.gd")
	assert_ne(code, "", "provider.gd is readable")
	for dead in ["mind_power_ratio", "Stat.SPIRIT", "comprehension_bonus"]:
		assert_eq(code.contains(dead), false, "provider.gd no longer reads %s" % dead)


# --- BL-0154: the sea fill is a gate, not a decoration ------------------------


## Every clause of the entry gate except the fill, satisfied through production
## actions only. Returns an actor whose sea is full and whose gate is otherwise
## ready, so the fill is the single remaining variable. The pill is stocked because
## the condition reads it too, and a gate that refuses for want of a pill proves
## nothing about the sea.
func _ready_except_the_fill() -> Actor:
	var actor := Probe.prepared(RANK)
	assert_ne(actor, null, "an R1 actor can be prepared for %s" % TARGET)
	if actor != null:
		Probe.stock(actor, MindRealmSeed.for_realm(TARGET).breakthrough_item)
	return actor


func _condition(_actor: Actor) -> MindBreakthroughCondition:
	return MindBreakthroughCondition.new()


## The headline. One clause of one gate, flipped by the module's central verb:
## the sea goes full, the gate refuses; the sea is emptied, the gate refuses for a
## different reason; the sea is refilled by cultivating, and the gate opens.
##
## The drain is `SeaOfConsciousness.drain` — the module's own method, and the one
## `MindAdvancement.resolve_attempt` calls on a successful breakthrough. The state
## it creates is therefore a state a player is in: the sea is emptied on every
## breakthrough, and the actor has to fill it again before the next attempt. That
## is what makes this an isolation rather than a contrivance, and it is why the
## fill is a real gate and BL-0154's "no observable effect" was wrong.
func test_filling_the_sea_is_what_opens_the_breakthrough_gate() -> void:
	var actor := _ready_except_the_fill()
	var condition := _condition(actor)
	var state := actor.path(MindPath.PATH_ID)
	var sea := MindCultivationApi.sea(actor)

	assert_almost_eq(sea.ratio(actor), 1.0, "preparation leaves the sea full")
	assert_eq(condition.can_breakthrough(actor, state, {}), true, "so the gate is open")

	# Emptied. `drain` is what a successful breakthrough does, so this is reachable.
	sea.drain(actor, sea.current(actor))
	assert_almost_eq(sea.ratio(actor), 0.0, "the reservoir really is empty")
	assert_eq(
		condition.can_breakthrough(actor, state, {}), false, "an empty sea refuses the attempt"
	)
	var fill_gate: Dictionary = Probe.gate(actor, "sea_fill")
	assert_almost_eq(
		float(fill_gate.get("value", -1.0)), 0.0, "and the published sea_fill value says so"
	)

	# Refilled by the central verb, through the facade, in sittings.
	assert_eq(Probe.fill_sea(actor), true, "cultivation fills the sea again")
	assert_eq(condition.can_breakthrough(actor, state, {}), true, "and the gate reopens")
	fill_gate = Probe.gate(actor, "sea_fill")
	assert_almost_eq(
		float(fill_gate.get("value", -1.0)),
		float(fill_gate.get("required", 0.0)),
		"the fill gate reads the seed's own authored floor"
	)


## The same flip expressed through the gate the module publishes, so the isolation
## above does not rest on one private predicate: the published `sea_fill` value
## moves with the reservoir and nothing else on that entry does.
func test_only_the_sea_fill_clause_moves_when_the_sea_is_emptied() -> void:
	var actor := _ready_except_the_fill()
	var sea := MindCultivationApi.sea(actor)
	var before: Dictionary = Probe.gate(actor, "sea_fill")
	sea.drain(actor, sea.current(actor))
	var after: Dictionary = Probe.gate(actor, "sea_fill")
	assert_almost_eq(
		float(before.get("value", 0.0)), float(before.get("required", 1.0)), "full before"
	)
	assert_almost_eq(float(after.get("value", -1.0)), 0.0, "empty after")
	# Everything else the condition reads is untouched by draining: clarity,
	# purity, progress, comprehension and the channels. Asserted as "still met",
	# not "still equal" -- cultivation overshoots a budget and that is correct.
	for clause in ["progress", "comprehension", "clarity", "purity"]:
		var entry: Dictionary = Probe.gate(actor, clause)
		assert_eq(
			Probe.value_of(actor, clause) >= float(entry.get("required", INF)) - 0.0001,
			true,
			(
				"%s is still met after the drain (%s of %s)"
				% [clause, Probe.value_of(actor, clause), entry.get("required", -1.0)]
			)
		)
