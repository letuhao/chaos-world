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
	MindStats.MIND_FOCUS_CHANCE,
	MindStats.MIND_AVOIDANCE,
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
	var actor := (
		Actor
		. new(&"bare", {Stat.WILL: 10.0, MindStats.MENTAL_CLARITY: 15.0})
	)
	MindCultivationApi.attach(actor)
	var emitted: Dictionary = SeaProvider.new().contribute(actor.stats._context)
	assert_eq(emitted, {}, "nothing to say without a sea")


## Nothing published by either provider may answer to a rate core already owns.
## `comprehension_bonus` was exactly this bug: core's `Stat.INSIGHT_GAIN` term
## plus a realm-rate term, on a quantity `MindTraining._grant_insight` reads
## `Stat.INSIGHT_GAIN` for. One dial per quantity, or a gate gets priced twice
## through two numbers that will drift.
func test_the_module_publishes_no_second_dial_on_a_shared_rate() -> void:
	var actor := _actor()
	var emitted: Dictionary = MindProvider.new().contribute(actor.stats._context)
	for key in emitted:
		assert_eq(
			emitted.has(key) and String(key) in [String(id) for id in Stat.RATE_STATS],
			false,
			"%s is not a second dial on core's %s" % [String(key), String(key)]
		)


## The two locals BL-0154 named, plus the one it missed: `Stat.SPIRIT` was read
## into `spirit` and fed nothing. Reading source is the only check that works —
## an unused local has no value to compare and no runtime symptom at all, which is
## precisely why it survived.
func test_the_provider_computes_nothing_it_does_not_publish() -> void:
	var source := FileAccess.get_file_as_string("res://src/modules/mind_cultivation/provider.gd")
	assert_ne(source, "", "provider.gd is readable")
	for dead in ["mind_power_ratio", "Stat.SPIRIT", "comprehension_bonus"]:
		assert_eq(source.contains(dead), false, "provider.gd no longer reads %s" % dead)


# --- BL-0154: the sea fill is a gate, not a decoration ------------------------


## Every clause of the entry gate except the fill, satisfied through production
## actions only. Returns an actor whose sea is full and whose gate is otherwise
## ready, so the fill is the single remaining variable.
func _ready_except_the_fill() -> Actor:
	var actor := Probe.prepared(RANK)
	assert_ne(actor, null, "an R1 actor can be prepared for %s" % TARGET)
	return actor


func _condition(actor: Actor) -> MindBreakthroughCondition:
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
	# purity, progress, comprehension and the channels.
	assert_almost_eq(
		Probe.value_of(actor, "progress"),
		float(Probe.gate(actor, "progress").get("required", -1.0)),
		"progress is still met after the drain",
		0.01
	)
	assert_almost_eq(
		Probe.value_of(actor, "clarity"),
		float(Probe.gate(actor, "clarity").get("required", -1.0)),
		"and so is clarity",
		0.0001
	)