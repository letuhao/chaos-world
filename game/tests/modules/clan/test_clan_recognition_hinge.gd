extends TestCase

## ADR 0064's hinge, made executable: **a clan reads the member's purity in its
## founding bloodline as a STANDING MULTIPLIER** — "a clan does not hand out power, it
## hands out recognition, and recognition scales what the member's own bloodline is
## worth."
##
## ## It did not ship, and these are the assertions that say so
##
## `ClanProvider` published `ClanStats.STANDING` as a raw integer and nothing anywhere
## in `game/src` read it, and `ClanSummary` read `founding_purity` only for the
## admission gate and the screen readout. Two audits found it. The multiplier itself
## did not exist in any form — not as a stat, not as a modifier, not as a read model.
##
## ## It is a READ MODEL, never a grant
##
## Everything below is computed from two ledgers on each read. Nothing persists a
## recognition, nothing writes a `StatModifier`, and `ClanProvider` still publishes the
## raw integer — so a save can never hold a recognition that disagrees with the lineage
## the member currently carries, and the character sheet is untouched.

const HOUSE := &"t_house"
const RIVAL := &"t_rival"
const LINE := &"hearthborn"

## A pure carrier, the top of the multiplier's range.
const PURE := 1.0
## An admitted member carrying none of the founder's line — the floor.
const DILUTED := 0.0

## ## Why this suite opens admission at 0.0, which `open()` does not
##
## The multiplier says a member carries none of the founder's line. It does not say a
## house which set a purity bar will admit them — and `ClanFixtureCatalog.open` publishes
## `min_purity = 0.3`, so every `_member(0.0, …)` below would be REFUSED and would be
## reading the empty ledger rather than the floor. That is exactly how this suite failed
## first: `equal standing: expected 0, got 100` and `the diluted member at the floor:
## expected 25.0, got 0.0`, which read like a broken curve and were a refused admission.
##
## `open()` is left exactly as the other clan suites find it — the fixture file is
## shared, and the bar is lowered on this suite's OWN copies of the defs instead. It is
## lowered BEFORE `install`, because `install` copies the definitions in: editing a fresh
## `ClanDef` afterwards would read as a change and change nothing. `PURITY_BAR` is the
## admission threshold and `LINE` is the line it is measured against — two different
## questions, and the whole hinge is about a member who is past the bar and still
## carries none of the line.
const PURITY_BAR := 0.0


func setup() -> void:
	var house := ClanFixtureCatalog.open(HOUSE)
	var rival := ClanFixtureCatalog.open(RIVAL)
	house.min_purity = PURITY_BAR
	rival.min_purity = PURITY_BAR
	var defs: Array[ClanDef] = [house, rival]
	ClanFixtureCatalog.install(defs)
	SocialCauseCatalog.instance().install_defaults()


func teardown() -> void:
	ClanFixtureCatalog.teardown()


func _member(purity: float, standing: int = 100, clan_id: StringName = HOUSE) -> Actor:
	var actor := Actor.new(&"member", {Stat.PHYSIQUE: 10.0})
	SocialApi.attach(actor)
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, LINE, purity)
	ClanApi.join(actor, clan_id, standing)
	return actor


func _scale(actor: Actor) -> float:
	return ClanGate.recognition_scale(actor)


func _recognised(actor: Actor) -> float:
	return ClanGate.recognised_of(actor)


func _regard(actor: Actor, institution_id: StringName) -> float:
	return float(
		(SocialApi.summary(actor)["regard"] as Dictionary).get(String(institution_id), 0.0)
	)


# --- The multiplier is monotonic in purity, and bounded ------------------------


## ## The two ends of the range, and why neither is the default
##
## A pure carrier reads 1.0: the house recognises them for everything they have earned.
## A member carrying none of the line reads `UNSCALED`, NOT zero — they were admitted,
## the act happened, and erasing their recognition entirely would make a house that
## admits outsiders unable to record having admitted one.
func test_the_multiplier_runs_from_the_unscaled_floor_to_one() -> void:
	assert_almost_eq(_scale(_member(PURE)), 1.0, "a pure carrier is recognised in full")
	assert_almost_eq(_scale(_member(DILUTED)), ClanGate.UNSCALED, "and a diluted member is not")
	assert_eq(ClanGate.UNSCALED > 0.0, true, "the floor is a floor, not an erasure")
	assert_eq(ClanGate.UNSCALED < 1.0, true, "and it is below the top")


## Every concentration in between lands strictly between the two ends — so the
## multiplier is a genuine continuous scale rather than two states with a step.
func test_every_concentration_between_the_ends_lands_between_them() -> void:
	var previous := -1.0
	for step in 11:
		var purity := float(step) / 10.0
		var scale := _scale(_member(purity))
		assert_eq(scale >= ClanGate.UNSCALED, true, "%.1f is at or above the floor" % purity)
		assert_eq(scale <= 1.0, true, "%.1f is at or below the top" % purity)
		assert_eq(scale > previous, true, "%.1f is strictly above %.1f" % [purity, previous])
		previous = scale


## Out-of-range and unreadable input cannot escape the range. Purity above 1.0 or below
## 0.0 is not something `BloodlineApi` produces, but a corrupt save could, and a
## multiplier that read it literally would hand one member recognition above what their
## standing could ever justify.
func test_the_multiplier_is_clamped_and_never_leaves_its_range() -> void:
	for purity in [-5.0, -0.001, 0.0, 1.0, 1.001, 42.0]:
		var scale := _scale(_member(purity))
		assert_eq(scale >= ClanGate.UNSCALED, true, "%.3f stays at or above the floor" % purity)
		assert_eq(scale <= 1.0, true, "%.3f stays at or below the top" % purity)


# --- A carrier and a diluted member read differently ---------------------------


## ## THE hinge, as one assertion
##
## Two members, one house, identical builds, identical earned standing, and the only
## difference is what lineage they carry. The house recognises both. The lineage decides
## how much the recognition is worth, and that difference is the whole character ADR
## 0064 exists to make representable.
func test_two_members_on_identical_standing_read_differently_by_lineage_alone() -> void:
	var carrier := _member(PURE, 100)
	var diluted := _member(DILUTED, 100)
	assert_eq(ClanApi.standing_of(carrier), ClanApi.standing_of(diluted), "same earned standing")
	assert_eq(BloodlineApi.purity_of(carrier, LINE), PURE, "one carries the founder's line")
	assert_eq(BloodlineApi.purity_of(diluted, LINE), DILUTED, "the other carries none of it")
	assert_almost_eq(_recognised(carrier), 100.0, "the carrier is recognised in full")
	assert_almost_eq(
		_recognised(diluted), 100.0 * ClanGate.UNSCALED, "the diluted member at the floor"
	)
	assert_eq(
		_recognised(carrier) > _recognised(diluted), true, "which is the gap the ADR is about"
	)


## ## The same gap, visible through `social` — the end a consumer actually reads
##
## `ClanApi._regard` hands the multiplier to `SocialApi.apply_cause` as `scale`, so the
## two ends of the hinge are the SAME number. If they ever disagree, either the bridge
## is passing something other than the factor or the read model has stopped being one.
func test_the_multiplier_reaches_social_regard_at_exactly_the_same_factor() -> void:
	var carrier := _member(PURE, 100)
	var diluted := _member(DILUTED, 100)
	var cause_standing := float(
		SocialCauseCatalog.instance().cause_definition(ClanApi.CAUSE_SWORN).standing
	)
	assert_almost_eq(
		_regard(carrier, HOUSE), cause_standing * _scale(carrier), "the carrier's regard"
	)
	assert_almost_eq(
		_regard(diluted, HOUSE), cause_standing * _scale(diluted), "and the diluted member's"
	)
	assert_eq(_regard(carrier, HOUSE) > _regard(diluted, HOUSE), true, "and they differ")


## Raising the member's lineage re-scales recognition on the next read, with nothing
## rewritten. This is what "computed, not stored" buys: a save cannot disagree with the
## bloodline the member actually carries.
func test_recognition_re_scales_when_the_lineage_changes_and_nothing_is_stored() -> void:
	var actor := _member(0.0, 100)
	var before := _recognised(actor)
	BloodlineApi.set_purity(actor, LINE, PURE)
	var after := _recognised(actor)
	assert_eq(after > before, true, "becoming a carrier is worth more recognition")
	assert_almost_eq(after, 100.0, "up to the full standing")
	# The ledger never learned about any of this: the raw integer is untouched, and
	# `ClanState.normalize` would not recognise a recognition field if it saw one.
	var ledger := ClanApi.state(actor)
	assert_eq(int(ledger["standing"]), 100, "the earned standing is unchanged")
	assert_eq(ledger.has("recognition"), false, "and no recognition was persisted")


# --- The house's own numbers are untouched --------------------------------------


## Recognition is a second READING of one number, not a second number. A member who
## gains standing gains recognition at the same instant, and the raw integer the house
## published is what moved.
func test_rising_standing_rises_recognition_at_the_same_instant() -> void:
	var actor := _member(PURE, 20)
	assert_almost_eq(_recognised(actor), 20.0, "twenty earns twenty")
	ClanApi.move_standing(actor, 30)
	assert_eq(ClanApi.standing_of(actor), 50, "the ledger moved first")
	assert_almost_eq(_recognised(actor), 50.0, "and recognition followed it")


## Non-members read zero recognition rather than raising on an error. This is the same
## house rule `standing_of` keeps: absence is zero, not a missing key.
func test_an_actor_with_no_house_has_no_recognition_and_no_multiplier_to_ask_about() -> void:
	var actor := Actor.new(&"outsider")
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	assert_almost_eq(_recognised(actor), 0.0, "no house, no recognition")
	assert_almost_eq(_scale(actor), 1.0, "and nothing whose opinion needs weighting")
	assert_almost_eq(ClanGate.recognised_of(null), 0.0, "a null actor is answered, not raised")


## A member at zero standing reads zero recognition even at full purity: the multiplier
## scales what was EARNED, it does not mint standing a member never had.
func test_the_multiplier_mints_no_recognition_out_of_nothing() -> void:
	var actor := _member(PURE, 0)
	assert_almost_eq(_recognised(actor), 0.0, "joining is not earning")
	ClanApi.move_standing(actor, -50)
	assert_almost_eq(_recognised(actor), 0.0, "and neither is falling below the floor")


# --- A house with no founding line ---------------------------------------------


## ## `line_less()` exists in the fixture for exactly this case
##
## With no founding bloodline there is nothing to be pure in, and reading 1.0 would
## hand every line-less house the carrier's recognition for free. The reading is
## therefore the floor — the member is recognised, and not scaled by anything.
func test_a_house_that_claims_no_founding_line_reads_at_the_unscaled_floor() -> void:
	ClanFixtureCatalog.install([ClanFixtureCatalog.line_less(&"t_lineless")])
	var actor := Actor.new(&"member")
	SocialApi.attach(actor)
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	# ## `line_less` publishes `min_purity = 0.0` as well as an empty line
	#
	# That is not an accident of `_base`: a house with no founding line has nothing to
	# set a bar against, so it cannot refuse anyone and an admitted outsider is the only
	# kind of member it has. Authoring a bar here instead would make the fixture refuse
	# every actor on earth, the join below would silently change nothing, and both
	# assertions would be reading the empty ledger rather than the floor — a green pair
	# that proved nothing.
	var admission := ClanApi.join(actor, &"t_lineless", 100)
	assert_eq(bool(admission["ok"]), true, "a line-less house admits anyone")
	assert_eq(ClanApi.clan_of(actor), &"t_lineless", "so the fixture really did admit them")
	assert_almost_eq(
		_scale(actor), ClanGate.UNSCALED, "nothing to scale by, so the floor is the honest reading"
	)
	assert_almost_eq(_recognised(actor), 100.0 * ClanGate.UNSCALED, "and it scales the ledger")
	# The cause still fires at that floor, so the house's opinion is RECORDED rather
	# than dropped — which is what "a clan recognises them" has to mean.
	assert_eq(_regard(actor, &"t_lineless") > 0.0, true, "the row is still opened")


# --- The multiplier is a read model, never a stat ------------------------------


## ## The property that makes it a read model rather than a grant
##
## `ClanProvider` publishes `ClanStats.STANDING` and four sibling summaries, and that
## list is unchanged by this feature. If recognition had been smuggled in as a sixth
## stat it would appear here, and this would fail — a stat is the buyable thing ADR
## 0064 forbids and ADR 0076's gate rule exists to keep out of gates.
##
## ## The order is the argument operand and the comparison is a BOOLEAN
##
## `assert_eq(actual, expected, …)` — `TestCase`'s FIRST argument is what the code
## produced. `carrier.stats.derived(stat_id) == diluted.stats.derived(stat_id)` is
## therefore the *actual* reading, and the literal `0.0` that used to sit in the expected
## slot was never the expected value of anything: it is the FALSE case this loop exists
## to rule out, written where an expected value belongs. The rule is not "both stats read
## 0.0" — it is "no stat in the module moves when only the lineage differs". So the
## assertion states that rule, and it reads as a comparison because the property IS one.
func test_no_stat_in_the_module_answers_to_the_hinge() -> void:
	var carrier := _member(PURE, 100)
	var diluted := _member(DILUTED, 100)
	for stat_id in [
		ClanStats.STANDING,
		ClanStats.RANK_INDEX,
		ClanStats.BAND_INDEX,
		ClanStats.PATRONAGE_TIER,
		ClanStats.RIVAL_COUNT,
	]:
		assert_eq(
			carrier.stats.derived(stat_id) == diluted.stats.derived(stat_id),
			true,
			"'%s' is identical" % stat_id
		)
	assert_almost_eq(
		carrier.stats.derived(ClanStats.STANDING),
		100.0,
		"and the published standing is the RAW integer, unscaled"
	)


## The summary publishes the factor beside the raw standing it scales, so a screen can
## render "recognised at 30 of 40" and show why the two differ.
func test_the_summary_publishes_the_recognition_and_its_factor() -> void:
	var actor := _member(0.5, 40)
	var view := ClanApi.summary(actor)
	var expected_scale := ClanGate.UNSCALED + (1.0 - ClanGate.UNSCALED) * 0.5
	assert_almost_eq(float(view["recognition_scale"]), expected_scale, "the factor is published")
	assert_almost_eq(float(view["recognition"]), 40.0 * expected_scale, "and the reading")
	assert_eq(int(view["standing"]), 40, "beside the raw standing it re-reads")
	assert_almost_eq(float(view["founding_purity"]), 0.5, "and the concentration behind it")
	# The null actor's shape is unchanged by any of this, and nothing here is NaN.
	var empty := ClanApi.summary(null)
	assert_eq(bool(empty["has_actor"]), false, "a null actor is still safe to ask about")
	assert_almost_eq(float(empty["recognition"]), 0.0, "with no recognition")
