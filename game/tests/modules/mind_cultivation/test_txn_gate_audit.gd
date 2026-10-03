extends TestCase

## Systematic entry-gate audit for the Mind path: is every gate the entry rules
## apply SATISFIABLE from a legal pre-state AND non-trivial — can it actually be
## false?
##
## ADR 0029 records the bug class twice on this module, and ADR 0051 records the
## third: a gate that read its own output as its input. A gate that always passes is
## worse than one that errors, because it hides the defect while every unit test
## still goes green — which is why the companion question (is the gate REACHABLE) is
## answered by a whole-ladder walk rather than by a per-gate unit test.
##
## Every gate is knocked out one at a time and required to report itself unmet, so
## "can be false" is measured rather than assumed. Thresholds are read from the
## gate report `preview` publishes, never restated.
##
## The suite also records, as a measurement, the one coupling that is still wrong:
## the roll reads the sea's clarity and the entry gate pins clarity to a single
## legal value, so the chance is a per-realm constant on every legal pre-state. That
## is a defect record, not a design goal — see the test that names it.

## One realm of the ladder is one boundary; 30 realms make 29 transitions.
const LADDER_SIZE := 30

## Bounds for the cultivation loop. A correct actor converges in two or three
## iterations, so this cap only turns a wrong value into a loud failure.
const CULTIVATE_CAP := 128


func _bare(rank_id: StringName) -> Actor:
	var actor := Actor.new(&"txn_gate_hero", {Stat.COMPREHENSION: 0.0, Stat.WILL: 0.0})
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	actor.meridians.unlock_for_realm(rank_id)
	MindCultivationApi.attach(actor)
	MindCultivationApi.attach_sea(actor)
	ItemsApi.attach(actor, 64)
	MindTraining.synchronize(actor)
	return actor


func _number(entry: Variant, key: String) -> float:
	var gate: Dictionary = entry if entry is Dictionary else {}
	var value: Variant = gate.get(key, 0.0)
	return float(value) if value is float or value is int else 0.0


func _gate(actor: Actor, key: String) -> Variant:
	var gates: Dictionary = MindAdvancement.preview(actor).get("gates", {})
	return gates.get(key, {})


## Cultivate a standing actor as hard as the sea allows and report the clarity and
## purity it converges on. Bounded twice: by a small cap, and by stopping as soon as
## a pass moves neither — which is what "converged on the realm's target" means.
func _cultivate_to_the_ceiling(actor: Actor) -> SeaOfConsciousness:
	var sea := MindCultivationApi.sea(actor)
	var guard := 0
	var settled := -1.0
	# No drain here, and none is needed: `cultivate` accepts a full sea, because
	# sea-fill and progress are BOTH entry gates and the reservoir fills first. The
	# drain this loop used to carry answered the BL-0101 stall by doing the player's
	# job -- and, worse, it meant this audit never measured what a real actor can do.
	while guard < CULTIVATE_CAP:
		guard += 1
		if not MindTraining.cultivate(actor, 5000.0):
			break
		var reached := sea.clarity + sea.purity
		if reached == settled:
			break
		settled = reached
	return sea


# --- Every gate can be false --------------------------------------------------


## Non-triviality, measured. Each gate is knocked out on its own and must report
## itself unmet at every boundary it applies to — otherwise it is a formality that
## reads true whatever the actor has done.
func test_every_gate_the_entry_rules_apply_can_be_false() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		var target := ladder.next(realm.id)
		if target == null:
			continue
		var label := "%s -> %s" % [realm.id, target.id]

		# One actor per knock-out, so no knock-out can mask another.
		var bare := _bare(realm.id)
		for key: String in ["progress", "comprehension", "sea_fill"]:
			var gate: Dictionary = _gate(bare, key)
			assert_eq(
				_number(gate, "value") < _number(gate, "required"),
				true,
				"the %s gate is closed on a bare actor at %s" % [key, label]
			)
			audited += 1

		var clouded := _bare(realm.id)
		var cloud_sea := MindCultivationApi.sea(clouded)
		cloud_sea.set_clarity(0.0)
		cloud_sea.set_purity(0.0)
		cloud_sea.add_turbulence(0.5)
		var turbulence: Dictionary = _gate(clouded, "turbulence")
		assert_eq(
			_number(turbulence, "value") > _number(turbulence, "required"),
			true,
			"the turbulence gate opens on a turbulent sea at %s" % label
		)
		audited += 1
		for key: String in ["clarity", "purity"]:
			var gate: Dictionary = _gate(clouded, key)
			assert_eq(
				_number(gate, "value") < _number(gate, "required"),
				true,
				"the %s gate opens on a clouded sea at %s" % [key, label]
			)
			audited += 1

		var pill: Dictionary = _gate(bare, "pill")
		assert_eq(
			pill.get("value"), false, "the pill gate is closed on an empty pack at %s" % label
		)
		audited += 1

		var channels: Array = _gate(bare, "channels")
		assert_eq(channels.is_empty(), false, "channels are reported at %s" % label)
		for entry: Dictionary in channels:
			assert_eq(
				entry.get("met"),
				false,
				"%s is not already %s at %s" % [entry.get("id"), entry.get("required"), label]
			)
		audited += channels.size()

		var tribulation: Dictionary = _gate(bare, "tribulation")
		if bool(tribulation.get("required")):
			assert_eq(
				tribulation.get("value"),
				false,
				"the tribulation gate is shut without a decided win at %s" % label
			)
			audited += 1

		var anchor: Dictionary = _gate(bare, "anchor")
		if bool(anchor.get("required")):
			assert_eq(
				anchor.get("value"),
				false,
				"the anchor gate is shut with no committed anchor at %s" % label
			)
			audited += 1
	assert_eq(audited > LADDER_SIZE, true, "every gate at every boundary was knocked out")


## A gate that is trivially satisfiable everywhere is as bad as one that is
## impossible: the ladder stops being a ladder and nothing notices. No boundary may
## be open on a bare actor's defaults alone.
func test_no_boundary_is_open_on_a_bare_actor() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		if ladder.next(realm.id) == null:
			continue
		audited += 1
		assert_eq(
			MindAdvancement.preview(_bare(realm.id)).get("ready"),
			false,
			"entry into %s is not open on defaults alone" % ladder.next(realm.id).id
		)
	assert_eq(audited, LADDER_SIZE - 1, "every boundary between the 30 realms was audited")


# --- The roll reads no gate input -------------------------------------------


## The chance is a function of the sea's clarity and nothing else: it equals the
## formula the module publishes, evaluated on the clarity the module's own report
## measured. Derived from `preview`, so a second term added to the roll would have
## to raise this.
func test_the_roll_equals_the_published_formula_on_the_reported_clarity() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		var target := ladder.next(realm.id)
		if target == null:
			continue
		var actor := _bare(realm.id)
		MindCultivationApi.sea(actor).set_clarity(0.42)
		var report := MindAdvancement.preview(actor)
		var clarity := _number((report.get("gates", {}) as Dictionary).get("clarity", {}), "value")
		var expected := clampf(
			MindAdvancement.MIN_CHANCE + clarity * MindAdvancement.CLARITY_TO_CHANCE,
			MindAdvancement.MIN_CHANCE,
			MindAdvancement.MAX_CHANCE
		)
		assert_almost_eq(
			float(report.get("chance", -1.0)),
			expected,
			"the roll at %s is the formula on the clarity %s reported" % [target.id, clarity],
			0.0001
		)
		audited += 1
	assert_eq(audited, LADDER_SIZE - 1, "every boundary was audited")


## ADR 0051's fix, pinned: at no boundary does a legal pre-state roll at or above
## certainty. `Stat.BREAKTHROUGH_CHANCE` is derived by core from comprehension and
## comprehension is this path's own entry gate, so reading it made 25 of 29
## breakthroughs guaranteed successes. The roll must stay strictly inside its clamp
## even when the actor holds far more insight than the gate demands.
func test_no_boundary_rolls_at_certainty_even_past_every_gate() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		var target := ladder.next(realm.id)
		if target == null:
			continue
		var seed := MindRealmSeed.for_realm(target.id)
		for multiple: float in [1.0, 8.0]:
			var actor := _bare(realm.id)
			MindCultivationApi.sea(actor).set_clarity(
				minf(1.0, MindRealmSeed.for_realm(realm.id).clarity_required)
			)
			actor.stats.set_base(Stat.COMPREHENSION, seed.comprehension_required * multiple)
			actor.mark_stats_dirty()
			var chance := float(MindAdvancement.preview(actor).get("chance", -1.0))
			assert_eq(
				chance < MindAdvancement.MAX_CHANCE,
				true,
				(
					"%s -> %s rolls %s at x%s insight, under certainty"
					% [realm.id, target.id, chance, multiple]
				)
			)
			assert_eq(
				chance > MindAdvancement.MIN_CHANCE,
				true,
				(
					"%s -> %s rolls %s at x%s insight, above the floor"
					% [realm.id, target.id, chance, multiple]
				)
			)
		audited += 1
	assert_eq(audited, LADDER_SIZE - 1, "every boundary was audited")


## Nothing the entry gate pins may move the roll, and the only input that does must
## actually do so. A constant would satisfy the invariance half on its own, so the
## spread is asserted too.
func test_only_clarity_moves_the_roll() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		var target := ladder.next(realm.id)
		if target == null:
			continue
		var seed := MindRealmSeed.for_realm(target.id)
		var ceiling := minf(1.0, MindRealmSeed.for_realm(realm.id).clarity_required)
		var base := _chance(realm.id, ceiling, seed.comprehension_required, 0.0, false)
		var past_insight := _chance(
			realm.id, ceiling, seed.comprehension_required * 8.0, 0.0, false
		)
		var worked := _chance(
			realm.id, ceiling, seed.comprehension_required, seed.progress_required, true
		)
		assert_almost_eq(
			past_insight, base, "insight past the gate does not move the roll at %s" % realm.id, 0.0
		)
		assert_almost_eq(
			worked, base, "progress and a full sea do not move the roll at %s" % realm.id, 0.0
		)
		assert_eq(
			base > _chance(realm.id, 0.0, seed.comprehension_required, 0.0, false),
			true,
			"and clarity is the one input that does, at %s" % realm.id
		)
		audited += 1
	assert_eq(audited, LADDER_SIZE - 1, "every boundary was audited")


## The chance `preview` evaluates for an actor whose only free inputs are named.
## Everything else stays at a bare default, so any difference between two calls is
## caused by exactly the argument that changed.
func _chance(
	rank_id: StringName, clarity: float, comprehension: float, progress: float, filled: bool
) -> float:
	var actor := _bare(rank_id)
	var sea := MindCultivationApi.sea(actor)
	sea.set_clarity(clarity)
	actor.stats.set_base(Stat.COMPREHENSION, comprehension)
	actor.mark_stats_dirty()
	actor.path(MindPath.PATH_ID).progress = progress
	if filled:
		var guard := 0
		while not sea.is_full(actor) and guard < 16:
			guard += 1
			sea.fill(actor, sea.maximum(actor))
	return float(MindAdvancement.preview(actor).get("chance", -1.0))


# --- Recorded defect: the gate pins the input the roll reads -----------------


## DEFECT RECORD, not a design goal. The entry gate demands the sea reach the
## SOURCE realm's clarity and purity, and cultivation caps both at exactly that
## value, so a pre-state that passes the gate holds one clarity — and the roll, which
## reads clarity, is a per-realm constant however much the player prepares.
##
## This asserts the PIN itself, because that is the falsifiable half: if a cap ever
## rises above the demanded value the roll regains a preparation axis and this test
## fails, which is the moment the coupling should be re-examined. Fixing it means
## giving the roll an input the gate does not pin (channel refinement past the
## required state, or work held above the progress budget); that is a balance
## decision, not a bug fix, and it is recorded rather than taken here.
func test_the_entry_gate_pins_the_clarity_and_purity_the_roll_reads() -> void:
	var ladder := RealmDefaults.ladder()
	var pinned := 0
	for realm in ladder.realms():
		if ladder.next(realm.id) == null:
			continue
		var seed := MindRealmSeed.for_realm(realm.id)
		var sea := _cultivate_to_the_ceiling(_bare(realm.id))
		assert_almost_eq(
			sea.clarity,
			minf(1.0, seed.clarity_required),
			"cultivation at %s converges on exactly the clarity the gate demands" % realm.id,
			0.0001
		)
		assert_almost_eq(
			sea.purity,
			minf(1.0, seed.purity_required),
			"and on exactly the purity the gate demands" % realm.id,
			0.0001
		)
		pinned += 1
	assert_eq(pinned, LADDER_SIZE - 1, "every realm standing before a boundary was measured")


# --- Nothing is permanently shut --------------------------------------------


## A gate whose threshold no legal pre-state can reach is a soft-lock, not a hard
## gate: the ladder stops at that boundary and the only way past is a test writing
## state. Every realm must therefore author the consumables its own actions spend,
## and every threshold must sit inside the range of what it measures.
func test_no_boundary_is_permanently_shut_by_missing_content() -> void:
	var ladder := RealmDefaults.ladder()
	var audited := 0
	for realm in ladder.realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		assert_ne(seed, null, "a mind profile exists for %s" % realm.id)
		if seed == null:
			continue
		for role: String in [
			"breakthrough_item",
			"training_item",
			"sea_catalyst",
			"recovery_item",
		]:
			# An empty recovery item makes a deviation unrecoverable at that realm,
			# and an empty pill or catalyst makes its milestone impossible to pay for.
			assert_ne(
				String(seed.get(role)),
				"",
				"%s authors its %s, so %s is playable" % [realm.id, role, realm.id]
			)
		assert_eq(
			seed.progress_required > 0.0, true, "the progress budget at %s is positive" % realm.id
		)
		assert_eq(
			seed.comprehension_required > 0.0,
			true,
			"the insight floor at %s is positive" % realm.id
		)
		assert_eq(
			seed.clarity_required > 0.0 and seed.purity_required > 0.0,
			true,
			"the sea milestones at %s are positive, so they are not satisfied by default" % realm.id
		)
		assert_eq(
			seed.sea_fill_required > 0.0 and seed.sea_fill_required <= 1.0,
			true,
			"the sea fill demand at %s is a real fraction" % realm.id
		)
		assert_eq(
			seed.required_meridians.is_empty(),
			false,
			"the channel gate at %s names at least one channel" % realm.id
		)
		audited += 1
	assert_eq(audited, LADDER_SIZE, "every realm was audited")
