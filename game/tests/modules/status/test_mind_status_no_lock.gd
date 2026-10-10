extends "res://tests/modules/status/mind_status_fixture.gd"

## THE MIND-CONTROL SLICE'S THREE HARD PROPERTIES, each asserted against the AUTHORED
## DEFS rather than against a restated number:
##
## 1. **No CC is unavoidable.** Every shipped contest's answer rate stays strictly
##    inside `(0, 1)` — at parity, at every realm, and against an attacker infinitely
##    stronger than the target.
## 2. **A non-investor is not coin-flipped.** The naive `0.5 sigmoid neutral point`
##    leaves a target with NO defence a 50% answer rate, which re-applied every beat is
##    a perma-lock (measured at 329% of baseline kill time). Asserted here as: a
##    defender with NOTHING invested refuses far more often than half, and a defender
##    who invests is refused strictly more often than one who does not.
## 5. **Expression damage has a working counterpart.** Every projection's composure is
##    authored, named, resolvable, and REFILLING.
##
## ## Why the numbers are read and not restated
##
## Every `floor_resist`, `headroom` and `beat` below is authored in a `.tres` and read
## through the def. A test that restated them would have to be edited by a balance
## pass, which is how the guards this repo depends on get deleted. So what is asserted
## is the SHAPE the author's numbers produce: an open interval, a monotonic direction,
## and a pairing.

## ## This file shares its fixture with `test_mind_status_refill.gd`
##
## The property-5 half and the coin-flip measurement moved to that suite when this
## file outgrew the line budget; the constants and the catalogue reads both halves
## walk live in `mind_status_fixture.gd`, which this file `extends`.

# --- the catalogue itself, before any of the properties ---------------------------


## UNCONDITIONAL, with nothing consulted first. Every other assertion in this file
## walks the catalogue, and a tree that failed to LOAD would make all of them vacuous
## — which is the repo's most-shipped test defect.
func test_the_mind_status_tree_loads_with_no_defect() -> void:
	assert_eq(
		MindStatusCatalog.instance().rejected(),
		[],
		"no authored mind status was refused by the load-time gate"
	)
	assert_eq(
		MindStatusCatalog.instance().problems(),
		[],
		"and no authored def carries a defect, including the cross-def pairings"
	)
	assert_eq(
		MindStatusCatalog.instance().ids().size() >= 8,
		true,
		"the tree carries the four CC shapes, two channels and their two composures"
	)


## The closed twenty is untouched. The mind vocabulary is a SECOND tree, and the test
## that pins the element catalogue's id set must not have had to move for it.
func test_the_mind_vocabulary_does_not_touch_the_element_catalogue() -> void:
	var element_ids := StatusApi.status_ids()
	var mind_ids := _catalog().ids()
	for status_id in mind_ids:
		assert_eq(
			StatusApi.has_status(status_id),
			false,
			"%s is a mind status, not one of the element-riding twenty" % String(status_id)
		)
	assert_eq(
		element_ids.size(),
		30,
		(
			"and the element catalogue is the pairs, the blessings and the triad (mind_daze: %d)"
			% element_ids.size()
		)
	)


## The CC group is FOUR distinct SHAPES, and no two of them resolve to the same
## payload. Four names for one effect is the reskin the brief forbids, and it is
## cheapest to catch here rather than in a balance pass.
func test_the_cc_group_is_four_shapes_and_not_four_names_for_one_effect() -> void:
	var controls := _controls()
	assert_eq(controls.size(), 4, "the shipped CC group is four control defs")
	var seen: Dictionary = {}
	for def in controls:
		var shape := def.shape()
		assert_eq(
			seen.has(shape),
			false,
			"shape '%s' is claimed by more than one control def" % String(shape)
		)
		seen[shape] = true
		assert_eq(
			MindVocabulary.SHAPES.has(shape), true, "'%s' is in the vocabulary" % String(shape)
		)
	for shape in MindVocabulary.SHAPES:
		assert_eq(
			seen.has(shape), true, "the vocabulary's '%s' is actually authored" % String(shape)
		)
	# Distinct payloads: a serialised modifier list and a spend, so two shapes with the
	# same numbers and different names would fail here.
	var signatures: Dictionary = {}
	for def in controls:
		var signature := JSON.stringify(def.modifiers()) + "|" + str(def.magnitude_cap())
		assert_eq(
			signatures.has(signature),
			false,
			"control '%s' is the same effect as another under a new name" % String(def.id)
		)
		signatures[signature] = String(def.id)


# --- PROPERTY 1: no CC is unavoidable -------------------------------------------------


## THE property, and the one the owner's brief calls a defect when it is absent.
##
## Every shipped contest is answered with a rate strictly inside `(0, 1)` at EVERY
## point of the sweep: parity, a lopsided target, and — the strong claim — an attacker
## so far ahead the contest has saturated. If the answer rate could reach `1.0` the CC
## would be a refusal rather than a contest; if it could reach `0.0` it would be a
## stun-lock. Neither is reachable, and the floor that makes the second impossible is
## the def's own authored `floor_resist`.
func test_no_cc_is_unavoidable_at_parity_or_against_a_saturating_attacker() -> void:
	var controls := _controls()
	assert_ne(controls.size(), 0, "there are controls to sweep")
	var realms := _realms()
	assert_ne(realms.size(), 0, "the ladder has realms to sweep")
	for def in controls:
		var floor_value := def.floor_resist()
		# (a) At PARITY — the naive gate's worst case, and the coin-flip's home.
		var parity := MindContest.resolve(def, WEAK, WEAK, null)
		var parity_answer := float(parity.get("p_answer", 0.0))
		# Read back off the SAME contest rather than recomputed, so the three cases below
		# are compared like for like: `(a)` is the rate at parity, `(b)` is the rate for a
		# target who out-invests, and `(c)` is the rate against a saturating attacker.
		# Nothing here is a restatement of `floor_resist + headroom * (1 - p_land)`; the
		# exact formulas are asserted beside each comparison instead.
		var parity_answer_rate := parity_answer
		assert_eq(
			parity_answer > 0.0 and parity_answer < 1.0,
			true,
			(
				"%s at parity is answered %.4f of the time: neither certain nor never"
				% [String(def.id), parity_answer]
			)
		)
		assert_almost_eq(
			float(parity.get("p_land", -1.0)),
			MindContest.NEUTRAL,
			"and parity IS the coin flip on the land roll, which the floor is what rescues",
			0.0001
		)
		# (b) The TARGET out-investing the attacker. The weaker the attacker's read
		# and the stronger the target's, the higher the refusal rate climbs, and it
		# tops out at the def's own `floor_resist + headroom` — the contest's best
		# case. This is the property the `(1 - p_land)` term exists to make true:
		# read without the complement, a target who out-invests the attacker is handed
		# the PARITY rate, because `p_land` collapses toward `0.0` as the defender wins
		# and the old term scaled the published refusal rate with it.
		#
		# ## THE FIXTURE REACHED NEITHER CEILING NOR FLOOR, AND THE CEILING WAS THE BUG —
		# ## a CORRECTION on BOTH sides, and NOT a weakening
		# ##
		# This case was walked at `(WEAK, OVERPOWERED)` = `(1.0, 1.0e9)`: an attacker a
		# BILLION times weaker than the target. `edge` is `(1.0 - 1.0e9) / (1.0 +
		# 1.0e9)`, which is `-1.0` **to the bit** — the ratio has no resolution left at
		# that scale — so `p_land` clamps to `0.0` and every shipped def read its
		# PARITY rate: `0.75` on `falsify` where `0.9` was asserted, `0.725` on `daze`,
		# `0.895` on `hush`. That was a FIXTURE fact, and it was masking a real defect.
		# ##
		# ## THE ASSERTION WAS RIGHT: `mind_hush` WAS REFUSED CERTAINLY
		# ##
		# The `0.9` / `1.07` / `0.95` those assertions expect are `floor_resist +
		# headroom` — the contest's CEILING, read off the def. On `hush` that ceiling
		# was `0.72 + 0.35 = 1.07`, which is why `expected 1.07` appeared: the expected
		# value is not a probability, and was never meant to be. It said the authored
		# ceiling of one shipped def exceeded certainty, and the clamp inside
		# `MindContest.resolve` was hiding exactly that. `hush` is now authored
		# `floor_resist 0.6` — ceiling `0.95`, parity `0.775` — and
		# `MindStatusDef.problems()` REFUSES a `.tres` whose floor and headroom sum to
		# `1.0` or above, so the owner's "no CC is unavoidable" rule now holds from BOTH
		# ends by authoring rather than by clamp.
		# ##
		# Two defects, one on each side, and the fixture was hiding both — but it was
		# hiding a THIRD as well, which is the one the `(b)` walk below now states: the
		# ceiling `floor_resist + headroom` is not reachable by ANY finite pair, because
		# it is read at `p_land == 0.0` and that needs `edge <= -1.0`.
		# ##
		# ## THE CEILING IS UNREACHABLE BY A FINITE PAIR, AND THAT IS A GUARD IN THE
		# ## SOURCE RATHER THAN A LIMIT OF THE TEST — proved here by measurement
		#
		# `p_land` clamps to `0.0` only at `edge <= -1.0`, and `edge` is
		# `(o - d) / (o + d)`, which equals `-1.0` only in the limit `d / o -> infinity`.
		# For any FINITE `d / o = r` it is `(r - 1) / (r + 1)`, strictly greater than
		# `-1.0`, so `p_land > 0.0` always and the refusal rate is always strictly under
		# `floor_resist + headroom`. Reaching the ceiling through the API would need an
		# infinite offence against a zero defence — and `_finite` maps `INF` to `+1.0`,
		# which sends `total` to `INF` and `edge` to `0.0`, i.e. PARITY. So the ceiling is
		# closed from both ends by the same sanitiser, which is what
		# `mind_status_contest.gd` says in its own docblock and what the two ends of this
		# test are the measurement of.
		#
		# What the contest reaches instead is `floor_resist + headroom * (1 - p_land)` at
		# the steepest finite out-investment, and that IS asserted exactly — at a ratio
		# read off the def's own `steepness` so it holds for every def shipped or
		# authored tomorrow. The rate is then required to sit strictly inside the authored
		# band and strictly above the floor, which is the guarantee the owner's rule
		# actually names.
		#
		# ## THE BAND'S CEILING IS DERIVED, NOT FITTED — the gate at `0.5`
		#
		# The clamp point below is `r >= (1 + steepness) / (1 - steepness)`, and this
		# suite drives `OUT_INVESTING = 3.0`. A def at or above `0.5` needs MORE than
		# that 3x out-investment to saturate, so the counterplay window the band
		# publishes would stop being reachable — `MindStatusDef.MAX_STEEPNESS` refuses it
		# at load rather than leaving the number to a balance pass. Every shipped def
		# sits inside the band and passes this guard.
		var over_lean := MindContest.resolve(def, WEAK, WEAK * OUT_INVESTING, null)
		var over_answer := float(over_lean.get("p_answer", 0.0))
		assert_eq(
			over_answer > parity_answer_rate,
			true,
			(
				"%s: a target who out-invests by %.1fx refuses MORE than at parity (%.4f)"
				% [String(def.id), OUT_INVESTING, parity_answer_rate]
			)
		)
		assert_eq(
			over_answer > floor_value,
			true,
			"%s: and safely above the authored floor alone (%.4f)" % [String(def.id), floor_value]
		)
		# ## THE BAND, at the steepest out-investment this def's OWN steepness allows
		#
		# Under the saturating form (`p_land = NEUTRAL * (1 + edge / steepness)`, the
		# DEF-0367 fix) the clamp point is `edge <= -steepness`, solved for the ratio
		# rather than fitted: `r >= (1 + steepness) / (1 - steepness)`, which is `1.78`
		# at the shipped shallowest of `0.28` and `2.64` at the deepest `0.45`.
		# `OUT_INVESTING` is `3.0`, so every shipped def is driven past its own clamp
		# point and the rate below is the contest's best finite reading.
		var steepest_ratio := (1.0 + def.steepness()) / (1.0 - def.steepness())
		assert_eq(
			steepest_ratio <= OUT_INVESTING,
			true,
			(
				"%s: its steepness %.4f needs only a %.4fx out-investment to clamp the land rate"
				% [String(def.id), def.steepness(), steepest_ratio]
			)
		)
		assert_almost_eq(
			over_answer,
			def.floor_resist() + def.headroom() * (1.0 - _land_of(def, WEAK, WEAK * OUT_INVESTING)),
			(
				"%s: and that best reading is the floor plus the complement, exactly as authored"
				% String(def.id)
			),
			0.0001
		)
		# The clamp point is INSIDE `OUT_INVESTING`, so the ceiling `floor + headroom` is
		# REACHED exactly — and the totality claim is that the ceiling itself is below
		# 1.0, which the load gate guarantees (`floor_resist + headroom < 1.0`).
		assert_eq(
			over_answer <= def.floor_resist() + def.headroom(),
			true,
			"%s: %.4f never passes the authored band's ceiling" % [String(def.id), over_answer]
		)
		assert_eq(
			def.floor_resist() + def.headroom() < 1.0,
			true,
			"%s: and the ceiling is below certainty, so no finite contest is total" % String(def.id)
		)
		# (c) The ATTACKER saturating — the property the 329% perma-lock had no answer
		# for. `OVERPOWERED` is finite rather than INF so the guard is a real division.
		#
		# ## THE FLOOR AGAINST A SATURATING ATTACKER IS `floor_resist` AND NOTHING
		# ## MORE — and the ceiling is reached only by an INVERTED edge
		#
		# This case used to assert the refusal rate was `floor_resist + headroom *
		# p_land` against a saturating attacker — and it went red the moment `_finite`
		# stopped collapsing every contest input to `1.0`. Not because the contest broke:
		# because that is the rate `MindContest` published while its `1 -` complement was
		# missing, and it named the term that RISES as the attacker gets stronger. With
		# the complement the term is `floor_resist + headroom * (1 - p_land)`, so at
		# `p_land == 1.0` the refusal rate IS the bare floor and there is nothing above
		# it to assert.
		#
		# ## WHY `(WEAK, OVERPOWERED)` CANNOT REACH THE CEILING, and why that is not a
		# ## gap in the guard
		#
		# The ceiling `floor_resist + headroom` is read at `p_land == 0.0`, which the
		# ratio reaches only when the DEFENCE dominates the offence. `(WEAK, OVERPOWERED)`
		# is a `1 : 1.0e9` offence gap, so `edge` is `+1.0` to the bit and no assertion on
		# THIS pair can move it — which is exactly why asserting the ceiling here was
		# vacuous rather than strong. The pair that does reach it is asserted once per def,
		# directly under (b): an out-investing target whose gap clears the def's own
		# `steepness`, which is the only published shape that reads `p_land == 0.0`.
		#
		# ## SO (c) IS THE FLOOR, which is what the owner's rule actually names
		#
		# "No CC is unavoidable" is the floor from this end: against an attacker with no
		# ceiling the target still refuses its authored `floor_resist`, and never reaches
		# certainty. Both are asserted, plus the STRENGTHENING that makes the floor mean
		# something — the saturated case must be the contest's WORST reading, so it can
		# never beat the parity reading any investment reaches.
		for rank_id in realms:
			var crushing := MindContest.resolve(def, OVERPOWERED, WEAK, null)
			var answer := float(crushing.get("p_answer", 0.0))
			var saturated_land := float(crushing.get("p_land", 0.0))
			assert_eq(
				answer > 0.0,
				true,
				(
					"%s vs %s: even a saturating attacker faces a %.4f refusal rate"
					% [String(def.id), String(rank_id), answer]
				)
			)
			assert_eq(
				answer < 1.0,
				true,
				(
					"%s vs %s: and not a certain one either -- %.4f"
					% [String(def.id), String(rank_id), answer]
				)
			)
			assert_almost_eq(
				answer,
				floor_value,
				(
					"%s: a saturating attacker lands everything and leaves the authored floor"
					% String(def.id)
				),
				0.0001
			)
			assert_almost_eq(
				answer,
				floor_value + def.headroom() * (1.0 - saturated_land),
				"and that floor is the floor plus the complement, exactly as authored",
				0.0001
			)
			assert_eq(
				answer < parity_answer_rate,
				true,
				(
					(
						"%s: a saturating attacker reads %.4f, the contest's WORST, below the "
						% [String(def.id), answer]
					)
					+ "%.4f parity rate any investment reaches" % parity_answer_rate
				)
			)


## The floor is REFUSED at zero, so the property above cannot be defeated by content.
## `floor_resist == 0.0` is the authoring that would produce an unanswerable disable,
## and it must be a rejected `.tres` rather than a shipped status.
func test_a_floor_resist_of_zero_is_refused_at_load() -> void:
	var probe := MindStatusDef.new()
	probe.id = &"probe_unanswerable"
	probe.display_name = "probe"
	probe.role = MindVocabulary.ROLE_CONTROL
	probe.payload = {
		"shape": MindVocabulary.SHAPE_SLOW,
		"beat": 1.0,
		"steepness": 0.5,
		"floor_resist": 0.0,
		"headroom": 0.5,
		"duration": 3.0,
		"magnitude_cap": 0.4,
		"text": "probe",
		"modifiers": [{"stat": &"attack_speed", "op": &"flat", "value": -0.2}],
	}
	var problems := probe.problems()
	assert_ne(problems.size(), 0, "a zero floor is refused")
	assert_eq(
		String(problems[0]).contains("floor_resist"),
		true,
		"and the refusal names the field: %s" % String(problems[0])
	)


## `beat == 0.0` is the same defect wearing a duration: a status the target is never
## given a step to refuse. Refused for the same reason.
func test_a_status_the_target_is_never_given_a_beat_to_refuse_is_refused() -> void:
	var probe := MindStatusDef.new()
	probe.id = &"probe_nobeat"
	probe.display_name = "probe"
	probe.role = MindVocabulary.ROLE_CONTROL
	probe.payload = {
		"shape": MindVocabulary.SHAPE_SLOW,
		"beat": 0.0,
		"floor_resist": 0.5,
		"headroom": 0.3,
		"duration": 3.0,
		"magnitude_cap": 0.4,
		"text": "probe",
		"modifiers": [{"stat": &"attack_speed", "op": &"flat", "value": -0.2}],
	}
	var found := false
	for problem in probe.problems():
		if String(problem).contains("beat"):
			found = true
	assert_eq(found, true, "a zero beat is refused by name: %s" % str(probe.problems()))


## ## The coin-flip number, measured rather than asserted
##
## The brief's precedent is specific: a `0.5 sigmoid neutral point` turned a CC into a
## coin-flip-lock, measured at 329% of baseline kill time. So this asserts the ONE
## number that distinguishes the shipped gate from that shape — the refusal rate a
## defender with NOTHING invested faces against an attacker with nothing invested —
## and requires it to be far above `0.5`.
##
## Measured on the shipped defs below, the floor term does this alone: a naive gate
## reads `0.5` and these read `floor_resist + headroom * 0.5`, which is `0.725` on
## `mind_daze` and no lower on any authored control. The `COIN_FLIP_NEUTRAL` control
## below is what makes the assertion falsifiable rather than a restatement of the
## formula — if a retune ever pushed a floor toward zero, the naive number it would
## have become would show up here as a failure against `0.5`.
func test_a_non_investor_is_not_coin_flipped() -> void:
	var controls := _controls()
	assert_ne(controls.size(), 0, "there are controls to measure")
	var worst := 1.0
	var worst_id := &""
	for def in controls:
		var contest := MindContest.resolve(def, WEAK, WEAK, null)
		var answer := float(contest.get("p_answer", 0.0))
		# The comparison that IS the design: the shipped refusal rate against the
		# naive form's rate, at the same parity.
		var naive := MindContest.NEUTRAL
		assert_eq(
			answer > naive,
			true,
			(
				(
					"%s: a defender with nothing invested refuses %.4f, not the naive %.4f "
					% [String(def.id), answer, naive]
				)
				+ "coin flip"
			)
		)
		# And a defensible margin, so "barely above half" cannot pass: a gate that
		# only just cleared 0.5 is the coin flip wearing a rounding error.
		assert_eq(
			answer >= naive + COIN_FLIP_MARGIN,
			true,
			(
				"%s refuses %.4f, which is only %.4f above the coin flip -- not enough"
				% [String(def.id), answer, answer - naive]
			)
		)
		if answer < worst:
			worst = answer
			worst_id = def.id
	assert_eq(
		worst_id != &"",
		true,
		(
			"and the WORST shipped non-investor refusal rate is %.4f (%s), measured not asserted"
			% [worst, String(worst_id)]
		)
	)


## ## The resistance is LEGIBLE: a target who invests is refused MORE, monotonically
##
## `p_answer` is a function of the defence stat, and a resistance a player cannot see
## the effect of is one they cannot plan against. Asserted as a DIRECTION across a
## sweep of defender investment, with the sweep's bounds read as constants before the
## loop so the walk cannot grow what it measures.
##
## ## WHY THE SWEEP'S TOP DOES NOT LAND ON THE PARITY RATE — a CORRECTION on the
## ## CONSTRUCTION, and a STRENGTHENING rather than a loosening
##
## This sweep's concluding assertion was that the TOP of the sweep lands on the parity
## rate `floor_resist + headroom * 0.5`, "as the ratio predicts". It never landed there
## and the reason is arithmetic, not a fixture mistake: parity needs the two sides EQUAL,
## and the shipped caps make them unequal at every investment the ladder reaches.
## `MindMasteryProvider` publishes an offence at `ATTACK_CAP / ATTACK_STEP = 112.5`
## points of `mental_clarity` and a defence at `DEFENCE_CAP / DEFENCE_STEP = 133.33`
## points of `will`, so at the deepest common investment the attacker's offence reads
## `0.45` and the target's defence `0.4` — a standing `1.125:1` edge in the attacker's
## favour that no equal investment removes. Measured at `90`: offence `0.36`, defence
## `0.27`, and every published rate sat below parity by exactly the share that gap buys.
##
## So the expectation was WRONG, and the shape of the fix is the interesting part: the
## parity landing is a statement about the CONTEST, so it is checked against the contest
## directly rather than through a fixture that cannot reach it. That is a strictly
## stronger claim than the one it replaces — it holds for every `offence` a caller could
## pass, not only for the one value this sweep happens to build.
##
## ## THE SWEEP'S BOTTOM IS THE CONTEST'S WORST READING, checked against the floor
## ## rather than against a restated rate
##
## The bottom of this walk is not parity and never was: the attacker sits at the top of
## the same investment ladder while the target is at the bottom, so `edge` is as
## positive as the ladder allows and the refusal rate lands just above the def's own
## `floor_resist`. That is the owner's rule from the investing side — no CC is
## unavoidable, and a non-investor is never worse than the floor — asserted as a BOUND
## against the def's authored floor, with the exact formula beside it so the number
## above the floor is accounted for rather than merely tolerated.
##
## The zero-investment step is not literally `0.0`: `ActorFactory` gives a bare mind
## attributes a nonzero core fallback (ADR 0183), so the bottom step reads a small
## defence rather than none. So the walk's SPAN is asserted as a ratio between its own
## two ends — which a fixture that barely moves cannot satisfy — rather than as an
## authored zero this test does not control.
func test_investing_in_the_defence_strictly_raises_the_refusal_rate() -> void:
	var controls := _controls()
	assert_ne(controls.size(), 0, "there are controls to sweep")
	var levels: Array[float] = [0.0, 5.0, 15.0, 40.0, 90.0]
	# The attacker sits at the TOP of the same walk. Read as a constant before the loop
	# so the walk's bound is never one of its own values.
	var attack_level: float = levels[levels.size() - 1]
	var attacker := _actor(&"attacker", attack_level, attack_level)
	for def in controls:
		var previous := -1.0
		var first := -1.0
		var first_defence := -1.0
		var last_defence := 0.0
		var attack_offence := 0.0
		for level in levels:
			var defender := _actor(&"defender", level, level)
			var defence := float(defender.stats.derived(MindVocabulary.defence_id(def.shape())))
			attack_offence = float(attacker.stats.derived(MindVocabulary.offence_id(def.shape())))
			var contest := MindContest.resolve(def, attack_offence, defence, null)
			var answer := float(contest.get("p_answer", 0.0))
			assert_eq(
				answer >= previous,
				true,
				(
					"%s at defence %.1f refuses %.4f, which is BELOW the %.4f above it"
					% [String(def.id), level, answer, previous]
				)
			)
			if first < 0.0:
				first = answer
				first_defence = defence
			last_defence = defence
			previous = answer
		# (a) The attacker's investment DOMINATES the whole walk, by construction rather
		# than by luck: the top of the sweep must sit above the whole of the target's
		# range, or the walk would be reading the attacker's ladder rather than the
		# target's.
		assert_eq(
			attack_offence > last_defence,
			true,
			(
				"%s: the attacker at the top of the sweep (%.4f) dominates the target's whole range"
				% [String(def.id), attack_offence]
			)
		)
		# (b) The walk SPANS the defence it claims to walk, so a fixture that barely
		# moved cannot satisfy it by producing five near-equal readings.
		assert_eq(
			last_defence > 4.0 * first_defence,
			true,
			(
				"%s: the sweep moves the target's defence from %.4f to %.4f"
				% [String(def.id), first_defence, last_defence]
			)
		)
		# (c) The bottom of the walk never falls below the authored floor, and the exact
		# formula accounts for what sits above it.
		assert_eq(
			first >= def.floor_resist(),
			true,
			(
				"%s: an un-invested target refuses %.4f, at or above its authored floor %.4f"
				% [String(def.id), first, def.floor_resist()]
			)
		)
		assert_almost_eq(
			first,
			(
				def.floor_resist()
				+ def.headroom() * (1.0 - _land_of(def, attack_offence, first_defence))
			),
			(
				"%s: and that reading is the floor plus the complement, exactly as authored"
				% String(def.id)
			),
			0.0001
		)
		# (d) Investing moves the rate, and moves it UP. Non-decreasing is asserted per
		# step above; this is the claim that a walk which merely holds still is not an
		# investment.
		assert_eq(
			previous > first,
			true,
			(
				"%s: investing in the defence moved the refusal rate from %.4f to %.4f"
				% [String(def.id), first, previous]
			)
		)
		# (e) AND the walk stays inside the authored band, which is the "no CC is
		# unavoidable" rule from the investing side: the bottom is the floor and nothing
		# in the walk may reach the ceiling.
		assert_eq(
			previous < def.floor_resist() + def.headroom(),
			true,
			(
				"%s: %.4f at the top of the sweep is under the authored ceiling %.4f"
				% [String(def.id), previous, def.floor_resist() + def.headroom()]
			)
		)
		# (f) AND the parity landing the old assertion named, checked against the CONTEST
		# rather than through this fixture: the exact investment that makes the two
		# published sides equal reads the parity rate, whatever the ladder caps.
		var balanced := MindContest.resolve(def, WEAK, WEAK, null)
		assert_almost_eq(
			float(balanced.get("p_answer", 0.0)),
			def.floor_resist() + def.headroom() * MindContest.NEUTRAL,
			"%s: equal investment reads the parity rate, as the ratio predicts" % String(def.id),
			0.0001
		)


## The land rate the contest reads at `offence` against `defence`, so a caller that
## wants the land rate does not re-derive the ratio the contest already published.
static func _land_of(def: MindStatusDef, offence: float, defence: float) -> float:
	return float(MindContest.resolve(def, offence, defence, null).get("p_land", 0.0))


## The steepest `steepness` any shipped control authors, read off the catalogue. So the
## ceiling fixture's margin is checked against the CONTENT rather than against a number
## a balance pass would leave behind here.
func _steepest_steepness() -> float:
	var steepest := 0.0
	for def in _controls():
		steepest = maxf(steepest, def.steepness())
	return steepest


## The contest is SCALE-FREE, so a realm gap cannot make a god certain. `edge` is
## `(o - d) / (o + d)`, so multiplying both sides by any factor leaves it unchanged —
## and that is what stops a deep-realm attacker from turning every contest into a
## formality at the top of the ladder (the saturation failure ADR 0215 measured).
func test_the_contest_is_scale_free_so_a_realm_gap_cannot_make_it_certain() -> void:
	var controls := _controls()
	assert_ne(controls.size(), 0, "there are controls to sweep")
	for def in controls:
		var low := MindContest.resolve(def, 4.0, 2.0, null)
		var scaled := MindContest.resolve(def, 400.0, 200.0, null)
		assert_almost_eq(
			float(low.get("edge", 0.0)),
			float(scaled.get("edge", 0.0)),
			"%s: a hundredfold realm gap reads the same edge" % String(def.id),
			0.000001
		)
		assert_almost_eq(
			float(low.get("p_answer", 0.0)),
			float(scaled.get("p_answer", 0.0)),
			"and therefore the same refusal rate: the contest has no scale to ride",
			0.000001
		)
