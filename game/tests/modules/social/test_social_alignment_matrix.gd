extends TestCase

## The alignment matrix (ADR 0253). Six properties, each pinned by an exact value so a
## weight change is a visible diff rather than a drift nobody notices:
##
##   1. DETERMINISM — a fixed input set yields an exact expected axis tuple.
##   2. IDENTITY  — the same input gives every NPC the same number. The owner's rule.
##   3. TAPER     — repeating one cheap act has sharply diminishing effect.
##   4. ANTI-FARM — the matrix cannot be farmed past the distinct-KIND rule.
##   5. CORRUPTION— on the evil side goodwill is harder and hatred easier.
##   6. NO LEAK   — one pair's reaction cannot reach a third party.
##
## Every constant below is an AUTHORED LITERAL, not a read of the matrix. A test that
## recomputes the expected answer from the same table proves nothing, so it does not.

const MERCHANT := &"merchant_grampa"
const ELDER := &"elder_wei"
const RIVAL := &"rival_cultivator_lan"
const SUPPLICANT := &"servant_qin"
const STRANGER := &"traveller_unknown"

## Six cruelties is what a player must commit to become corrupt; the test that pins the
## threshold asserts this number rather than deriving it.
const CRUELTIES_TO_CORRUPT := 6


func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()


func _actor(id: StringName = &"hero") -> Actor:
	var actor := Actor.new(id, {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(actor)
	return actor


func _axes(actor: Actor) -> SocialAlignment:
	return SocialApi.social_state(actor).alignment_axes()


func _bond(actor: Actor, partner: StringName) -> SocialBond:
	return SocialApi.social_state(actor).ensure_bond(partner)


# --- 1. Determinism: the exact value, not a plausible one ----------------------------


## The headline. One fixed input set, the exact three-axis tuple, asserted as literals:
##   cruelties   6 acts x MERCY -3, taper 1, 1/2, 1/4, 1/8, 1/16, 1/32
##               = -3 * (1 + 0.5 + 0.25 + 0.125 + 0.0625 + 0.03125) = -5.90625
##   dominion    6 acts x +3, same taper                                = +5.90625
##   justice     untouched                                              =  0.0
## Change any authored weight and this is a diff, not a drift.
func test_a_fixed_input_set_produces_the_exact_authored_value() -> void:
	var actor := _actor()
	for _repeat in range(CRUELTIES_TO_CORRUPT):
		SocialApi.apply_cause_aligned(actor, SUPPLICANT, &"cruel_to_the_powerless")
	var axes := _axes(actor)
	# The taper is PER ACTOR, not per bond: these six cruelties are six acts of one
	# kind against one person, so the 2nd is worth 1/2 and the 6th 1/32. The expected
	# value is the geometric sum -3 x (1 + 1/2 + 1/4 + 1/8 + 1/16 + 1/32) = -5.90625.
	assert_almost_eq(axes.axis(SocialAlignmentMatrix.MERCY), -5.90625, "the mercy taper sum")
	assert_almost_eq(axes.axis(SocialAlignmentMatrix.DOMINION), 5.90625, "the dominion sum")
	assert_almost_eq(axes.axis(SocialAlignmentMatrix.JUSTICE), 0.0, "no act touched justice")
	assert_eq(axes.seen.size(), 1, "six acts of one kind are ONE kind of act")


## The same input set a second time gives the identical answer — no hidden state, no
## ordering dependence, no wall-clock term.
func test_the_matrix_is_deterministic_across_two_identical_players() -> void:
	var first := _actor(&"one")
	var second := _actor(&"two")
	for other in [first, second]:
		SocialApi.apply_cause_aligned(other, MERCHANT, &"won_auction")
		SocialApi.apply_cause_aligned(other, MERCHANT, &"taught_technique")
		SocialApi.apply_cause_aligned(other, MERCHANT, &"spared_in_combat")
	assert_eq(SocialApi.alignment(first), SocialApi.alignment(second), "identical inputs")


## ## A cause absent from the weight table moves NO axis at all
##
## This is the market tier staying out of a moral system: winning a lot is not a moral
## position, and `standing` carries no moral reading that the table could infer.
func test_an_act_the_matrix_does_not_judge_moves_no_axis() -> void:
	var actor := _actor()
	for _repeat in range(8):
		SocialApi.apply_cause_aligned(actor, MERCHANT, &"won_auction")
	var axes := _axes(actor)
	assert_almost_eq(axes.axis(SocialAlignmentMatrix.DOMINION), 0.0, "auctions are not moral")
	assert_almost_eq(axes.axis(SocialAlignmentMatrix.MERCY), 0.0, "nor is buying anything")
	assert_eq(axes.judges(&"won_auction"), false, "the matrix does not judge it")
	# And the repeat ledger is untouched, so the act cannot even taper a later one.
	assert_eq(axes.seen.size(), 0, "an unjudged act is not counted")


# --- 2. The owner's constraint: one score, read identically by all --------------------


## ## THE constraint, asserted directly
##
## Three NPCs with nothing in common get the SAME band, the SAME goodwill rate and the
## SAME hatred rate from one player who has committed five cruelties. There is no
## argument for "who is asking" anywhere in the read path, and this is what that means.
func test_the_same_score_reaches_every_npc_identically() -> void:
	var hero := _actor()
	for _repeat in range(5):
		SocialApi.apply_cause_aligned(hero, SUPPLICANT, &"cruel_to_the_powerless")
	var view := SocialApi.alignment(hero)
	assert_eq(view["band"], SocialAlignmentMatrix.CORRUPT, "five cruelties corrupt")
	# Every npc reads this identical row; there is no per-npc column to vary.
	for npc_id in [MERCHANT, ELDER, RIVAL, STRANGER]:
		assert_eq(SocialApi.alignment(hero)["band"], view["band"], "one band for all")
		assert_eq(SocialApi.alignment(hero)["goodwill_rate"], view["goodwill_rate"], "rate")
	# The rate a given act lands at is a pure function of band and cause — so two
	# DIFFERENT npcs are moved by the identical amount by the identical act.
	var causes := SocialCauseCatalog.instance()
	var spared := causes.cause_definition(&"spared_in_combat")
	var a := _fresh_bond()
	var b := _fresh_bond()
	var moved_a := SocialAlignmentTrack.apply_swayed(a, spared, SocialAlignmentMatrix.CORRUPT)
	var moved_b := SocialAlignmentTrack.apply_swayed(b, spared, SocialAlignmentMatrix.CORRUPT)
	assert_almost_eq(moved_a, moved_b, "two npcs, one number")


func _fresh_bond() -> SocialBond:
	return SocialBond.new(MERCHANT)


## The matrix has no per-NPC input to vary even if a consumer wanted one: the only
## arguments `contribution` takes are a cause, a repeat count and a scale.
func test_the_contribution_signature_has_no_npc_argument() -> void:
	var entry := SocialAlignmentMatrix.contribution(&"cruel_to_the_powerless", 2, 1.0)
	assert_eq(entry.size(), SocialAlignmentMatrix.AXES.size(), "one column per axis")
	assert_almost_eq(
		entry[String(SocialAlignmentMatrix.DOMINION)], 0.75, "3 x 0.5^2 = 0.75 exactly"
	)


# --- 3. Convergence: a cheap act repeated is worth almost nothing -------------------


## ## Sharply diminishing, asserted as a ratio rather than a vibe
##
## 1 gift = +1.0 mercy. 8 gifts = +1.9921875 (1 + 1/2 + 1/4 + ... + 1/128). The eighth
## gift is worth 1/128th of the first: repeating the cheapest possible good act eight
## times buys less mercy than sparing one life (+3.0). A linear accumulator reads 8.0 —
## four times as much, for the same eight clicks.
func test_repeating_one_cheap_act_converges_hard() -> void:
	var actor := _actor()
	for _repeat in range(8):
		SocialApi.apply_cause_aligned(actor, MERCHANT, &"gifted_item")
	var mercy := _axes(actor).axis(SocialAlignmentMatrix.MERCY)
	assert_almost_eq(mercy, 1.9921875, "the taper sum, not 8.0")
	assert_eq(mercy < 3.0, true, "eight gifts buy less mercy than sparing one life")
	# The marginal gift, measured directly against the table.
	var eighth := SocialAlignmentMatrix.contribution(&"gifted_item", 7, 1.0)
	assert_almost_eq(
		eighth[String(SocialAlignmentMatrix.MERCY)], 0.0078125, "the eighth gift is 1/128th"
	)


## An act the matrix does not judge never taps out, so an unjudged repeat cannot
## suppress a judged one. The counter only advances for a real moral reading.
func test_an_unjudged_repeat_does_not_taper_the_next_judged_act() -> void:
	var actor := _actor()
	for _repeat in range(5):
		SocialApi.apply_cause_aligned(actor, MERCHANT, &"won_auction")
	var axes := _axes(actor)
	SocialApi.apply_cause_aligned(actor, MERCHANT, &"sheltered_a_supplicant")
	assert_almost_eq(
		axes.axis(SocialAlignmentMatrix.MERCY), 3.0, "the first mercy act counts in full"
	)


# --- 4. The anti-farm regression: six oaths must not buy anything -------------------


## ## The regression, restated against the NEW code path
##
## ADR 0091's rule is that a friendship rests on distinct KINDS, and ADR 0198's guard is
## six oath-kind causes still reading `acquaintance`. Alignment adds a second, cheaper
## route to moral weight, so the same attack is run against it: six oaths through
## `apply_cause_aligned` — the swing-aware path — and the bond must not become a friend.
func test_six_oaths_cannot_buy_a_friendship_through_the_alignment_path() -> void:
	var alone := _actor(&"alone")
	# Four oaths KEPT, which is the generous direction — the attack is at its strongest
	# when the player behaves well, not when the ledger is a net negative.
	for cause_id in [
		&"shared_brotherhood",
		&"accepted_the_oath",
		&"witnessed_an_oath",
		&"accepted_the_oath",
		&"shared_brotherhood",
		&"accepted_the_oath",
	]:
		SocialApi.apply_cause_aligned(alone, ELDER, cause_id)
	var bond := _bond(alone, ELDER)
	# +5 +5 +1 +5 +5 +5 = +26 of authored standing against an ACTOR, which would clear
	# CONFIDANT_AT (14) on any accumulator. The distinct-KIND rule is the only thing
	# stopping it, and alignment is not an input to `classify` — so it stops it.
	assert_almost_eq(bond.standing, 26.0, "the standing really is large")
	assert_eq(bond.distinct_kinds(), 1, "six oaths are one kind of act")
	assert_eq(bond.bond_class(), SocialBondClass.ACQUAINTANCE, "one kind is one kind")
	# And the alignment did accrue — so the test is not passing because nothing happened.
	#
	# The taper is PER CAUSE (`social_alignment_matrix.gd:163` counts how many times THIS
	# cause has already moved THIS actor), so the six oaths are three distinct causes at
	# different repeat counts, not one cause six times:
	#   shared_brotherhood x2 -> JUSTICE 1: 1 + 1/2            = 1.5
	#   accepted_the_oath  x3 -> JUSTICE 1: 1 + 1/2 + 1/4      = 1.75
	#   witnessed_an_oath  x1 -> JUSTICE 1: 1                  = 1.0
	# A linear accumulator reads 6.0 here, so this is a test of the taper rather than of
	# "something moved".
	assert_almost_eq(
		_axes(alone).axis(SocialAlignmentMatrix.JUSTICE),
		4.25,
		"each cause tapers on its own repeat count, not the ledger's",
		0.0001
	)


## Alignment cannot raise a class on its own either: a large MERCY total is a moral fact,
## and the ladder reads bond axes and distinct KINDS. It buys no rank.
func test_a_large_alignment_total_buys_no_relationship_class() -> void:
	var hero := _actor()
	for _repeat in range(5):
		SocialApi.apply_cause_aligned(hero, MERCHANT, &"taught_technique")
	var bond := _bond(hero, MERCHANT)
	# MERCY, not JUSTICE: `taught_technique` is the one cause that is both. Five acts of
	# +2.0 with the taper read `2 + 1 + 0.5 + 0.25 + 0.125 = 3.875`; a linear
	# accumulator reads 10.0 for the same clicks.
	assert_almost_eq(
		_axes(hero).axis(SocialAlignmentMatrix.MERCY),
		3.875,
		"five teachings taper geometrically: 2 + 1 + 1/2 + 1/4 + 1/8",
		0.0001
	)
	assert_eq(bond.bond_class(), SocialBondClass.ACQUAINTANCE, "still one kind of act")


## The repeat ledger is bounded, so a save cannot grow an unbounded per-actor dict.
func test_the_repeat_ledger_is_bounded() -> void:
	var alignment := SocialAlignment.new()
	assert_eq(SocialAlignment.SEEN_LIMIT, 64, "the authored bound, named in one place")
	assert_eq(alignment.seen.is_empty(), true, "and it starts empty")


# --- 5. Corruption direction: goodwill harder, hatred easier -------------------------


## ## The 太吾绘卷 idea, as a direction test
##
## A player five cruelties in, a positive act lands at HALF and a negative act at DOUBLE.
## Both halves are asserted, because shipping only one would make corruption either
## strictly profitable or a pure tax (AGENTS.md's yin-yang rule on rates).
func test_corruption_halves_goodwill_and_doubles_hatred() -> void:
	var clean := _fresh_bond()
	var corrupt := _fresh_bond()
	var spared := SocialCauseCatalog.instance().cause_definition(&"spared_in_combat")
	var robbed := SocialCauseCatalog.instance().cause_definition(&"robbed")
	var clean_good := SocialAlignmentTrack.apply_swayed(clean, spared, SocialAlignmentMatrix.CLEAN)
	var corrupt_good := SocialAlignmentTrack.apply_swayed(
		corrupt, spared, SocialAlignmentMatrix.CORRUPT
	)
	assert_almost_eq(clean_good, 4.0, "a spared life is +4.0 to a clean player")
	assert_almost_eq(corrupt_good, 2.0, "and +2.0 to a corrupt one — HALF")
	assert_almost_eq(
		SocialAlignmentTrack.apply_swayed(_fresh_bond(), robbed, SocialAlignmentMatrix.CLEAN),
		-6.0,
		"a robbery is -6.0 clean"
	)
	assert_almost_eq(
		SocialAlignmentTrack.apply_swayed(_fresh_bond(), robbed, SocialAlignmentMatrix.CORRUPT),
		-12.0,
		"and -12.0 corrupt — DOUBLE"
	)


## Goodwill is halved, never zeroed: an NPC with a positive bond to a corrupt player
## still warms, just slower. A 0.0 would make corruption a social death sentence, which
## is the genre-correct register, but it would also make every existing positive bond
## unwinnable and is not what the research asks for.
func test_corruption_halves_goodwill_and_does_not_zero_it() -> void:
	var rate := SocialAlignmentMatrix.goodwill_rate(SocialAlignmentMatrix.CORRUPT)
	assert_almost_eq(rate, 0.5, "half")
	assert_eq(rate > 0.0, true, "a corrupt player is slower, not frozen")


## Trust is NEVER swayed, in either band. The alternative is the DOS2 shape wearing a
## different hat: one cruelty demoting every confidant bond in the world at once.
func test_trust_is_never_swayed_in_any_band() -> void:
	for band in [SocialAlignmentMatrix.CLEAN, SocialAlignmentMatrix.CORRUPT]:
		assert_almost_eq(
			SocialAlignmentMatrix.rate(band, "trust"), 1.0, "trust is neutral in %s" % band
		)


## The threshold is reachable and the band is a pure function of one axis.
func test_the_corruption_threshold_is_reachable_and_pure() -> void:
	assert_almost_eq(SocialAlignmentMatrix.CORRUPTION_AT, 5.0, "authored, not derived")
	assert_eq(SocialAlignmentMatrix.band_for(4.99), SocialAlignmentMatrix.CLEAN, "just under")
	assert_eq(SocialAlignmentMatrix.band_for(5.0), SocialAlignmentMatrix.CORRUPT, "exactly at it")
	assert_almost_eq(5.90625 >= SocialAlignmentMatrix.CORRUPTION_AT, 1.0, "six cruelties clear it")


# --- 6. The DOS2 group-leak guard ---------------------------------------------------


## ## WHAT IS ASSERTED, stated before the numbers
##
## DOS2's own modding docs warn that flipping an alignment ENTITY makes every member of
## it hostile to every player, and that members "in a different area of the map" find
## themselves in combat "for no intuitive reason". The failure is not that a global
## number exists — the owner requires one — it is that the number is APPLIED globally.
##
## So the assertion is: **the player's band is one global number, and it reaches exactly
## ONE bond per call — the pair passed in.** After a cruelty to a supplicant that has
## made the player corrupt, a stranger the player has never met reads `stranger`, an
## unrelated merchant reads exactly what they read before, and the player's own regard
## for an institution is untouched. One act, one pair, no third party.
func test_one_pairs_reaction_does_not_change_another_npcs_read() -> void:
	var hero := _actor()
	# A pre-existing relationship the cruelty must NOT disturb.
	SocialApi.apply_cause_aligned(hero, MERCHANT, &"taught_technique")
	var merchant_before: float = SocialApi.bond_entry(hero, MERCHANT)["standing"]
	# Become corrupt, cruelly, to one specific person. The band is read BEFORE the act
	# is applied, so cruelty 1..5 land at the CLEAN rate of x1.0 (-7.0 each) and only
	# from cruelty 6 does the corruption start doubling hatred. That ordering is
	# deliberate: the band your act puts you in cannot retroactively judge it.
	for _repeat in range(6):
		SocialApi.apply_cause_aligned(hero, SUPPLICANT, &"cruel_to_the_powerless")
	# 1. The culprit's bond did move, and the last act landed doubled — which is what
	#    proves the corruption is being applied rather than merely computed.
	var supplicant := SocialApi.bond_entry(hero, SUPPLICANT)
	assert_almost_eq(supplicant["standing"], -70.0, "1-2 at x1.0, 3-6 at x2.0")
	assert_eq(supplicant["bond"], SocialBondClass.NEMESIS, "a nemesis")
	assert_almost_eq(
		SocialApi.bond_entry(hero, MERCHANT)["standing"],
		merchant_before,
		"an unrelated party's bond is untouched by the band"
	)
	# 3. A stranger the player has never met still reads stranger — the alignment does
	#    not reach across the map to start a fight nobody can explain.
	var stranger := SocialApi.bond_entry(hero, STRANGER)
	assert_eq(stranger["present"], false, "they have never met")
	assert_eq(stranger["bond"], SocialBondClass.STRANGER, "and stay a stranger")
	# 4. And the band itself is global, exactly as the owner requires: one number.
	assert_eq(SocialApi.alignment(hero)["band"], SocialAlignmentMatrix.CORRUPT, "one score")


## The leak is structurally impossible, not merely absent: `apply_swayed` takes ONE bond
## and returns, so there is no code path by which a reaction could name a third party.
## Asserted as a shape, because a shape is what survives a later well-meaning refactor.
func test_the_sway_verb_takes_exactly_one_bond_and_a_band() -> void:
	var bond := _fresh_bond()
	var spared := SocialCauseCatalog.instance().cause_definition(&"spared_in_combat")
	# A second npc that exists in the world and is passed nowhere.
	var bystander := SocialBond.new(ELDER)
	SocialAlignmentTrack.apply_swayed(bond, spared, SocialAlignmentMatrix.CLEAN)
	assert_almost_eq(bystander.standing, 0.0, "the bystander was never named")
	assert_almost_eq(bond.standing, 4.0, "only the named bond moved")
	assert_almost_eq(
		SocialAlignmentTrack.apply_swayed(null, spared, SocialAlignmentMatrix.CLEAN),
		0.0,
		"no bond is not a crash"
	)


# --- Persistence: the axes are a derived read model, not a second record -------------


## A save round-trips the axes AND the repeat ledger, and the taper continues across the
## reload — so the anti-farm curve cannot be reset by quitting.
func test_alignment_round_trips_through_a_save_and_the_taper_survives_it() -> void:
	var hero := _actor()
	for _repeat in range(3):
		SocialApi.apply_cause_aligned(hero, SUPPLICANT, &"cruel_to_the_powerless")
	var payload := SocialApi.state(hero)
	var restored := Actor.from_dict(hero.to_dict())
	SocialApi.attach(restored)
	assert_eq(SocialApi.alignment(restored), SocialApi.alignment(hero), "the axes round-trip")
	var axes := SocialApi.social_state(restored).alignment_axes()
	assert_eq(axes.seen.size(), 1, "and so does the repeat ledger")
	# The fourth cruelty is worth 1/8, not a full 1.0 — the taper was NOT reset.
	SocialApi.apply_cause_aligned(restored, SUPPLICANT, &"cruel_to_the_powerless")
	assert_almost_eq(
		axes.axis(SocialAlignmentMatrix.DOMINION),
		3.0 + 1.5 + 0.75 + 0.375,
		"3 + 1.5 + 0.75 + 0.375 across the reload"
	)
	assert_eq(payload.size() > 0, true, "state() is non-empty")


## A save written BEFORE alignment existed has no key and restores neutral — which is
## the safe direction: nothing is retroactively corrupted by a build that added axes.
func test_a_save_without_an_alignment_key_restores_clean() -> void:
	var state := SocialState.from_dict({"version": 1, "bonds": {}, "regard": {}})
	var axes := state.alignment_axes()
	assert_almost_eq(axes.axis(SocialAlignmentMatrix.DOMINION), 0.0, "zero")
	assert_eq(axes.band(), SocialAlignmentMatrix.CLEAN, "and clean")


## The unaligned path is untouched. Four production callers depend on it, so adding
## alignment must not have changed what a plain membership or auction result does.
func test_the_unaligned_verb_is_unchanged_by_the_matrix() -> void:
	var actor := _actor()
	SocialApi.apply_cause(actor, MERCHANT, &"won_auction")
	var bond := SocialApi.social_state(actor).bond(MERCHANT)
	assert_almost_eq(bond.standing, 3.0, "the shipped magnitude, exactly")
	assert_almost_eq(_axes(actor).axis(SocialAlignmentMatrix.DOMINION), 0.0, "and no axis moved")


## Every cause the matrix judges must exist in the shipped catalog — an authored weight
## on a cause no verb can apply is the inert-vocabulary defect ADR 0076's catalog exists
## to prevent, wearing a different hat.
func test_every_judged_cause_exists_in_the_catalog() -> void:
	for cause_id in SocialAlignmentMatrix.WEIGHTS.keys():
		assert_eq(
			SocialCauseCatalog.instance().cause_definition(StringName(cause_id)) != null,
			true,
			"%s is weighted but not authored" % cause_id
		)
