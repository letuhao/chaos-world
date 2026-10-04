extends TestCase

## The mind path's comprehension GATE is priced by the actor power ladder, and
## this file makes a second curve impossible to reintroduce quietly.
##
## ## What was retired
##
## `MindRealmSeed.comprehension_required` was `2r^2 + 6r + 10` in the realm's ladder
## ORDINAL, at all 30 realms and to the last decimal — a private power curve beside
## the actor SSOT. `core/realm_power_table.tres` runs 1.00 -> 551.46 over the same
## 30 realms and is roughly linear, so the gate's price disagreed with every other
## magnitude in the game by up to 22.2x, and nothing in the tree tied the 30
## literals together or checked that they agreed with each other.
##
## `core/mind_comprehension_scale.gd` is the replacement: `SCALE * power(realm_id)`,
## one power curve, keyed by realm id. `SCALE` is DERIVED, not chosen — it is the
## geometric mean over the 30 rungs of the retired quadratic's per-rung
## `comprehension / power` ratio, which is the multiplier that preserves the gate's
## TOTAL work across the ladder instead of re-centring it. Leg 6 recomputes it from
## the data, so the docblock's claim is machine-checked rather than asserted.
##
## ## Why these legs read SOURCE
##
## A value comparison cannot see a copy. A second declaration of the same constant,
## or a re-derived closed form, is numerically identical today and free to drift
## tomorrow, so every structural check below reads text and not results. That is the
## ADR 0116 failure mode this file exists to prevent: one number, one place.
##
## SCOPE, stated so a reader does not think the scan is wider than it is. These legs
## cover `res://src` and `res://data/mind_cultivation/realms`. They deliberately do
## NOT cover the body's `insight_required`, which carries the same quadratic as
## `body_cultivation/breakthrough_condition.gd:45`'s entry gate AND a term in the
## body's breakthrough chance (`advancement.gd:62`: `0.1 + 0.01 * insight_required`).
## Moving that is a second path's balance ruling, not this one's; the cross-path
## equality that made it look like a shared sequence is retired in
## `game/tests/modules/test_seed_generator_parity.gd`. Nor do they cover
## `tools/cultivation/seed_systems.py:124`, which is Python (outside `res://`) and
## owned by another live session — tracked in `docs/deferred.jsonl`. The qi's own
## `comprehension_required` is a different field on a different path, authored
## linearly, and is out of scope for a ruling about the MIND gate.
##
## Each structural leg was proved RED by breaking the tree it guards (one seed
## literal, the `SCALE` declaration, and a reinstated ordinal-based computation),
## not by reading it. A green guard that cannot fail is worse than no guard
## (INC-0016).

const SRC_ROOT := "res://src"
const SEED_DIR := "res://data/mind_cultivation/realms"
const SCALE_FILE := "res://src/core/mind_comprehension_scale.gd"
const FIRST := &"qi_refining"
const LAST := &"primordial_origin"
const UNKNOWN := &"not_a_realm"

## The shape tokens that spelled the quadratic wherever it was written. Leg 4 fails on
## any of them appearing in `res://src`, so copying an old file back is caught by the
## expression rather than by the file name.
const QUADRATIC_TOKENS := ["i * i", "index * index", "ordinal * ordinal"]


## The exact closed form that was retired, kept here so leg 6 can reproduce `SCALE`
## from it and leg 5 can prove the data no longer obeys it. This is the ONE place in
## `res://src` the quadratic may be written down, and it is inert arithmetic in a
## test: nothing here prices a gate from it.
func _retired_quadratic(ordinal: int) -> float:
	return 2.0 * float(ordinal) * float(ordinal) + 6.0 * float(ordinal) + 10.0


## The primary leg: every shipped seed is the ladder answer, to the last decimal.
## `required()` returns `round(SCALE * power)` and the `.tres` carries that same
## nearest integer, so this is an equality and not a tolerance — a hand-edited
## literal, or a `SCALE` retune that was not pushed into the data, fails here.
func test_every_seed_is_the_ladder_answer() -> void:
	var realms := RealmDefaults.ladder().realms()
	assert_eq(realms.size(), 30, "the whole ladder is 30 realms")
	var counted := 0
	for realm in realms:
		var seed := MindRealmSeed.for_realm(realm.id)
		assert_ne(seed, null, "%s has a seed" % realm.id)
		if seed == null:
			continue
		assert_eq(
			seed.comprehension_required,
			MindComprehensionScale.required(realm.id),
			(
				"%s comprehension_required is SCALE x power (%.4f), not %s"
				% [
					realm.id,
					MindComprehensionScale.SCALE * RealmDefaults.POWER.power_for(realm.id),
					str(seed.comprehension_required),
				]
			)
		)
		counted += 1
	assert_eq(counted, 30, "all 30 seeds were checked")


## `insight_required` is a strict weaker copy of the gate at exactly half of it, so
## it is pinned as a DERIVATION here rather than as a second hand-typed ladder.
func test_every_insight_floor_is_half_the_gate() -> void:
	for realm in RealmDefaults.ladder().realms():
		var seed := MindRealmSeed.for_realm(realm.id)
		if seed == null:
			continue
		assert_eq(
			seed.insight_required,
			MindComprehensionScale.insight_floor(realm.id),
			"%s insight_required is half its gate" % realm.id
		)


## `SCALE` is authored in exactly one file in `res://src`. Matched on the const NAME
## and not a prefix, because `items/option_catalog.gd` legitimately declares
## `SCALE_PATH` and `SCALE_VERSION` and `core/realm_scaling.gd` declares
## `SCALED_STATS` — a prefix match would fail on names that have nothing to do with
## this curve.
func test_scale_is_declared_in_exactly_one_place() -> void:
	var declarations: Array[String] = []
	for path in ContentScan.files_under(SRC_ROOT, ".gd"):
		for declaration in _declarations(FileAccess.get_file_as_string(path), "const"):
			declarations.append("%s: %s" % [path, declaration])
	var ours: Array[String] = []
	for entry in declarations:
		var name := String(entry).split(": ", false)[1].split(" ", false)[1]
		if name == "SCALE":
			ours.append(entry)
	assert_eq(ours.size(), 1, "exactly one `const SCALE` in %s, found %d" % [SRC_ROOT, ours.size()])
	assert_eq(
		ours[0].begins_with(SCALE_FILE),
		true,
		"and it is authored in %s, found %s" % [SCALE_FILE, ours[0]]
	)


## The number itself, not just its name. A second copy spelled as
## `const GATE_FACTOR := 27.9448` would pass the leg above, so the literal is counted
## in CODE across `res://src` and must appear once. Comments are stripped first: the
## derivation in the scale's own docblock legitimately quotes the number, and a guard
## that failed on the explanation would teach the next agent to write a worse one.
func test_the_scale_literal_appears_once_in_code() -> void:
	var hits: Array[String] = []
	for path in ContentScan.files_under(SRC_ROOT, ".gd"):
		if _code_only(FileAccess.get_file_as_string(path)).contains("27.9448"):
			hits.append(path)
	assert_eq(
		hits.size(),
		1,
		"27.9448 is written once in code under %s, found %d: %s" % [SRC_ROOT, hits.size(), hits]
	)
	assert_eq(hits[0], SCALE_FILE, "and the one copy is %s" % SCALE_FILE)


## The pin that GENERALISES, and the one to read first.
##
## A gate requirement is a MAGNITUDE, so its only legitimate input is the realm's
## authored power. If the scale ever reached for the ladder's ORDINAL instead, it
## would be a second curve wearing the first curve's name — and it would still be
## numerically plausible, because the power table is superlinear too. So the check is
## not "does another copy of the quadratic exist" but "does the scale compute per
## realm from anywhere but the power table".
func test_the_scale_reads_the_power_table_and_never_a_ladder_ordinal() -> void:
	var code := _code_only(FileAccess.get_file_as_string(SCALE_FILE))
	assert_ne(code, "", "%s is readable" % SCALE_FILE)
	assert_eq(
		code.contains("RealmDefaults.POWER.power_for"),
		true,
		"the scale resolves a realm through the authored power table"
	)
	for ordinal_api in ["RealmDefaults.ladder()", "index_of", "realm_id.to_int()"]:
		assert_eq(
			code.contains(ordinal_api),
			false,
			(
				(
					"%s reads %s — a gate requirement is a MAGNITUDE, so its only "
					+ "per-realm input is power(realm_id); an ordinal is a second curve"
				)
				% [SCALE_FILE, ordinal_api]
			)
		)


## The closed form itself is gone from the source tree. Copying an old file back is
## the exact failure this closes, and a file name is too easy to change, so the
## search is for the shape rather than for the file.
func test_the_retired_quadratic_is_gone_from_the_source() -> void:
	for path in ContentScan.files_under(SRC_ROOT, ".gd"):
		var code := _code_only(FileAccess.get_file_as_string(path))
		if path == get_script().resource_path:
			continue
		for token in QUADRATIC_TOKENS:
			assert_eq(
				code.contains(token),
				false,
				(
					(
						"%s contains '%s' — the comprehension gate is priced by "
						+ "power(realm_id), not by a closed form in the ladder ordinal"
					)
					% [path, token]
				)
			)


## ...and gone from the DATA, which is the half a source scan cannot see. Both ends
## are asserted by name because they are where the quadratic and the ladder diverge
## most (R1 10 -> 28, R30 1866 -> 15410); a leg that only checked the middle could
## be satisfied by a curve that merely crosses the old one.
func test_the_retired_quadratic_is_gone_from_the_data() -> void:
	var realms := RealmDefaults.ladder().realms()
	var last_index := realms.size() - 1
	var first_seed := MindRealmSeed.for_realm(realms[0].id)
	var last_seed := MindRealmSeed.for_realm(realms[last_index].id)
	var first_quad := _retired_quadratic(0)
	var last_quad := _retired_quadratic(last_index)
	assert_ne(first_seed, null, "R1 has a seed")
	assert_ne(last_seed, null, "R30 has a seed")
	if first_seed == null or last_seed == null:
		return
	assert_ne(
		first_seed.comprehension_required,
		first_quad,
		"R1 comprehension_required is the ladder's, not the quadratic's %s" % first_quad
	)
	assert_ne(
		last_seed.comprehension_required,
		last_quad,
		"R30 comprehension_required is the ladder's, not the quadratic's %s" % last_quad
	)
	# And it is not a near miss anywhere either: the ladder governs every rung, so
	# no realm may still be sitting on the old value.
	var still_quadratic := 0
	for index in realms.size():
		var seed := MindRealmSeed.for_realm(realms[index].id)
		if seed != null and is_equal_approx(seed.comprehension_required, _retired_quadratic(index)):
			still_quadratic += 1
	assert_eq(
		still_quadratic,
		0,
		(
			"%d realm(s) still carry the retired quadratic — the ladder governs every rung"
			% still_quadratic
		)
	)


## `SCALE` is DERIVED, not chosen, and the derivation is reproducible from the data.
## Without this leg the docblock's claim that 27.9448 is the geometric mean would be
## prose, and the next agent retuning it would have no way to tell a derived number
## from a typed-in one. The arithmetic mean of the same 30 ratios is 38.0011, so the
## `geometric_mean < 30.0` assertion below is what names WHICH mean was taken.
func test_scale_is_the_geometric_mean_of_the_retired_quadratics_ratios() -> void:
	var realms := RealmDefaults.ladder().realms()
	var log_total := 0.0
	var counted := 0
	for index in realms.size():
		var power := RealmDefaults.POWER.power_for(realms[index].id)
		assert_eq(power > 0.0, true, "%s has a positive power" % realms[index].id)
		if power <= 0.0:
			continue
		log_total += log(_retired_quadratic(index) / power)
		counted += 1
	assert_eq(counted, 30, "all 30 rungs contributed a ratio")
	var geometric_mean := exp(log_total / float(counted))
	assert_almost_eq(
		geometric_mean,
		MindComprehensionScale.SCALE,
		"SCALE is the geometric mean of the retired quadratic's per-rung ratios",
		0.001
	)
	assert_eq(
		geometric_mean < 30.0, true, "the geometric mean is taken, not the arithmetic one (38.0011)"
	)


## The authored literals are the NEAREST INTEGER to `SCALE * power`, and
## `roundf` rounds halves away from zero. If any rung landed exactly on a half, the
## rule would be ambiguous between this engine's `roundf` and Python's banker's
## `round`, and the authored data and the resolver could disagree on a tie with
## nothing to say which is right. No rung does today — a fractional part above 0.5
## is not a tie, it simply rounds up, which is why this asserts absence of exactly
## 0.5 and nothing about the size of the fraction.
func test_the_rounding_rule_is_unambiguous() -> void:
	for realm in RealmDefaults.ladder().realms():
		var exact := MindComprehensionScale.SCALE * RealmDefaults.POWER.power_for(realm.id)
		var fraction := absf(exact - floorf(exact))
		assert_ne(
			is_equal_approx(fraction, 0.5),
			true,
			(
				(
					"%s: SCALE x power is exactly %.4f, a rounding tie — roundf (half away "
					+ "from zero) and Python's round() would disagree here"
				)
				% [realm.id, exact]
			)
		)
		# And the resolver and the shipped literal agree on this rung, tie or not,
		# which is the property that actually matters to a gate comparison.
		var seed := MindRealmSeed.for_realm(realm.id)
		if seed != null:
			assert_eq(
				seed.comprehension_required,
				roundf(exact),
				"%s carries the nearest integer to SCALE x power" % realm.id
			)


## The gate must still get harder as the actor does, or following the ladder has
## quietly turned it into a flat tax. Strictly rising at all 30 realms.
func test_the_gate_rises_strictly_across_the_ladder() -> void:
	var previous := 0.0
	var counted := 0
	for realm in RealmDefaults.ladder().realms():
		var required := MindComprehensionScale.required(realm.id)
		assert_eq(
			required > previous,
			true,
			(
				"%s gate %s does not rise above the previous realm's %.0f"
				% [realm.id, str(required), previous]
			)
		)
		previous = required
		counted += 1
	assert_eq(counted, 30, "the whole ladder was walked")


## An id that is not on the ladder prices at R1 rather than at zero: `power_for`
## falls back to a neutral 1.0, so the gate stays a gate. A missing entry must never
## make a breakthrough free, which is the failure a bare `multipliers[realm_id]` has.
func test_an_unknown_realm_prices_at_r1_and_never_zero() -> void:
	var first_price := MindComprehensionScale.required(FIRST)
	assert_eq(first_price > 0.0, true, "R1's gate is a real number")
	for realm_id in [&"", UNKNOWN]:
		assert_eq(
			MindComprehensionScale.required(realm_id),
			first_price,
			"an unknown realm '%s' prices at R1, not at zero" % realm_id
		)


## The two ends, pinned by name so a change to the ladder's SHAPE is visible in a
## failure message rather than hidden behind 30 identical per-seed assertions. R1's
## gate is 2.8x the retired quadratic and R30's is 8.3x it: the ladder outprices the
## old curve at BOTH ends, and outprices it far more the deeper you go, because the
## power table is superlinear where the quadratic was nearly linear. That divergence
## is why `SCALE` is the geometric mean rather than either end — calibrating to R1
## leaves R30 at 8.3x the old difficulty, calibrating to R30 makes R1 five times
## cheaper than it was, and only the mean keeps the total honest.
func test_the_retired_curve_and_the_ladder_disagreed_at_both_ends() -> void:
	var realms := RealmDefaults.ladder().realms()
	var last_index := realms.size() - 1
	var first_ratio := _retired_quadratic(0) / MindComprehensionScale.required(FIRST)
	var last_ratio := _retired_quadratic(last_index) / MindComprehensionScale.required(LAST)
	assert_almost_eq(
		first_ratio, 10.0 / 28.0, "R1: the ladder price is 2.8x the retired quadratic", 0.01
	)
	assert_almost_eq(
		last_ratio, 1866.0 / 15410.0, "R30: the ladder price is 8.3x the retired quadratic", 0.01
	)
	assert_eq(
		first_ratio < 1.0 and last_ratio < 1.0,
		true,
		(
			"the ladder outprices the retired quadratic at both ends (R1 %.3f, R30 %.3f)"
			% [first_ratio, last_ratio]
		)
	)
	assert_eq(
		last_ratio < first_ratio,
		true,
		(
			"and the gap WIDENS with depth (R30 %.3f under R1 %.3f) — neither end alone sets SCALE"
			% [last_ratio, first_ratio]
		)
	)


## Source with every whole-line `#` comment removed. Only whole-line comments:
## GDScript's `#` inside a string is not a comment, and pretending to parse it would
## make this guard a second parser to keep correct. A multi-line string that hid a
## ladder read is a review finding, not a blind spot worth a parser here.
func _code_only(source: String) -> String:
	var kept: Array[String] = []
	for line in source.split("\n"):
		var stripped := String(line).strip_edges()
		if not stripped.begins_with("#"):
			kept.append(stripped)
	return "\n".join(kept)


## Every `const <NAME> ...` / `class_name <Name>` a source file declares, as written.
func _declarations(source: String, keyword: String) -> Array[String]:
	var found: Array[String] = []
	for line in source.split("\n"):
		var stripped := String(line).strip_edges()
		if stripped.begins_with("%s " % keyword):
			found.append(stripped)
	return found
