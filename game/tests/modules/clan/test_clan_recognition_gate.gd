extends TestCase

## `ClanGate`'s eighth verb, `recognised_at_least`, and the rule that makes it a gate
## rather than a second way to buy standing.
##
## ## Why this verb exists at all
##
## `ClanStats.STANDING` (`&"clan_standing"`) had exactly one producer
## (`clan/provider.gd`) and ZERO consumers. A published number nothing reads confers
## nothing, so the social advantage a clan was designed to grant existed in ADR prose
## only. `standing_at_least` was already gated on the raw integer, so the missing piece
## was not a way to ask about standing — it was a way to ask about the number ADR 0064
## calls the hinge, i.e. recognition scaled by founding-bloodline purity.
##
## **It reads the LEDGER.** A stat can be satisfied by an item or a pill (ADR 0076), so
## a gate that read one would be a gate the player could buy. There is no `ClanStats` id
## for recognition at all, so the question cannot even be asked of a stat here.

const HOUSE := &"t_house"
const RIVAL := &"t_rival"
const LINE := &"hearthborn"

const UNMET_KEYS := ["kind", "id", "required", "actual", "label"]


func setup() -> void:
	_install_house()
	SocialCauseCatalog.instance().install_defaults()


func teardown() -> void:
	ClanFixtureCatalog.teardown()


## ## Why this suite opens admission at 0.0, which `open()` does not
##
## The standing MULTIPLIER only says a member carries none of the founder's line. It
## does not open the door to a house that set a bar — and `ClanFixtureCatalog.open`
## publishes `min_purity = 0.3`, so a `join` at 0.0 purity is REFUSED there and every
## recognition assertion below would be reading the empty ledger rather than the floor.
##
## `open()` is left exactly as the other clan suites find it: this suite needs to ask
## about members the house would never have admitted, so it lowers the bar on its OWN
## copies of the defs rather than in the fixture file every other suite shares. The bar
## is lowered before `install`, because `install` copies the definitions in — editing a
## fresh `ClanDef` afterwards would read as a change and change nothing.
func _install_house() -> void:
	var house := ClanFixtureCatalog.open(HOUSE)
	var rival := ClanFixtureCatalog.open(RIVAL)
	house.min_purity = 0.0
	rival.min_purity = 0.0
	var defs: Array[ClanDef] = [house, rival]
	ClanFixtureCatalog.install(defs)


## The premise every recognition assertion rests on. A member who carries no founder's
## line still has to BE a member, or `recognised_of` is answering about nobody.
func _member(purity: float = 1.0, standing: int = 100) -> Actor:
	var actor := Actor.new(&"member", {Stat.PHYSIQUE: 10.0})
	SocialApi.attach(actor)
	ClanApi.attach(actor)
	BloodlineApi.attach(actor)
	BloodlineApi.set_purity(actor, LINE, purity)
	ClanApi.join(actor, HOUSE, standing)
	return actor


func test_the_diluted_member_is_a_real_member_here() -> void:
	var actor := _member(0.0, 100)
	assert_eq(ClanApi.clan_of(actor), HOUSE, "the fixture house really did admit them")
	assert_eq(ClanApi.standing_of(actor), 100, "on the standing they were passed")


func _unmet_entry(verdict: Dictionary, index: int = 0) -> Dictionary:
	return (verdict["unmet"] as Array)[index]


# --- It opens and closes on the ledger -----------------------------------------


## ## The door this verb exists for, stated as a bar the multiplier straddles
##
## The fixture opens admission at 0.3, so a member at exactly the bar is admitted on
## the strength of carrying a thirtieth of the line. At 100 standing and 0.3 purity that
## is recognition of 37.0 — above a bar of 37, below a bar of 37.01. Same actor, same
## ledger, same standing: only the authored bar moved.
func test_the_verb_opens_and_closes_on_the_ledger_alone() -> void:
	var actor := _member(0.3, 100)
	var expected := 100.0 * (ClanGate.UNSCALED + (1.0 - ClanGate.UNSCALED) * 0.3)
	assert_almost_eq(ClanGate.recognised_of(actor), expected, "the reading is what we expect")
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"recognised_at_least", "at": expected})["ok"]),
		true,
		"exactly at the bar is enough"
	)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"recognised_at_least", "at": expected + 0.01})["ok"]),
		false,
		"and one hundredth over is not"
	)
	# Nothing about the actor changed between the two calls — the bar is authored data.
	assert_almost_eq(ClanGate.recognised_of(actor), expected, "the ledger never moved")


## ## The same bar, two members, opposite verdicts
##
## This is the gate the feature buys: content can ask "is this person one the house
## actually recognises" and get DIFFERENT answers for two members of equal earned
## standing, because the lineage differs. `standing_at_least` cannot do this — it reads
## the integer both of them hold.
func test_two_members_on_equal_standing_opposite_purity_straddle_one_bar() -> void:
	var bar := 50.0
	var carrier := _member(1.0, 100)
	var diluted := _member(0.0, 100)
	assert_eq(ClanApi.standing_of(carrier), ClanApi.standing_of(diluted), "equal standing")
	assert_eq(
		bool(ClanApi.unmet(carrier, {"verb": &"recognised_at_least", "at": bar})["ok"]),
		true,
		"a carrier clears it"
	)
	assert_eq(
		bool(ClanApi.unmet(diluted, {"verb": &"recognised_at_least", "at": bar})["ok"]),
		false,
		"and a diluted member does not"
	)
	# `standing_at_least` is the contrast: it reads the integer, so it cannot tell them
	# apart at any bar below 100. This is the verb that had to exist.
	assert_eq(
		bool(ClanApi.unmet(carrier, {"verb": &"standing_at_least", "at": bar})["ok"]),
		true,
		"the raw-standing verb opens for both"
	)
	assert_eq(
		bool(ClanApi.unmet(diluted, {"verb": &"standing_at_least", "at": bar})["ok"]),
		true,
		"which is precisely what it cannot do"
	)


func test_rising_standing_opens_the_door_and_falling_standing_closes_it() -> void:
	var actor := _member(1.0, 0)
	var bar := 40.0
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"recognised_at_least", "at": bar})["ok"]),
		false,
		"shut at zero standing"
	)
	ClanApi.move_standing(actor, 40)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"recognised_at_least", "at": bar})["ok"]),
		true,
		"opens on earning exactly the bar"
	)
	ClanApi.move_standing(actor, -40)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"recognised_at_least", "at": bar})["ok"]),
		false,
		"and closes again on losing it"
	)
	assert_eq(ClanApi.clan_of(actor), HOUSE, "losing standing never evicts anybody")


func test_a_zero_bar_means_belongs_to_a_house_and_nothing_further() -> void:
	var member := _member(0.0, 0)
	assert_eq(
		bool(ClanApi.unmet(member, {"verb": &"recognised_at_least", "at": 0.0})["ok"]),
		true,
		"any member clears zero"
	)
	# ## Why the non-member is shut out by this verb and not by a comparison
	##
	# `recognised_of(outsider)` is 0 — absence, not a missing key — and `0 >= 0` holds,
	# so the bar alone cannot tell a member nobody respects from nobody at all. The
	# MEMBERSHIP is the only thing that can, and `recognised_at_least` reads it, which is
	# what makes `at: 0` mean "belongs to a house" without content having to say so in
	# two verbs. `is_clan` says the same thing; this verb says it AND the bar.
	var outsider := Actor.new(&"outsider")
	ClanApi.attach(outsider)
	assert_eq(
		bool(ClanApi.unmet(outsider, {"verb": &"is_clan", "id": String(HOUSE)})["ok"]),
		false,
		"the outsider belongs to no house"
	)
	assert_eq(
		bool(ClanApi.unmet(outsider, {"verb": &"recognised_at_least", "at": 0.0})["ok"]),
		false,
		"and so a zero recognition bar is shut to them"
	)
	assert_almost_eq(
		ClanGate.recognised_of(outsider), 0.0, "their recognition is absence, not a shortfall"
	)
	# Every bar above zero was already refusing them, because their recognition is zero:
	# the membership arm buys `at: 0` and nothing else.
	for bar in [0.01, 1.0, 25.0]:
		assert_eq(
			bool(ClanApi.unmet(outsider, {"verb": &"recognised_at_least", "at": bar})["ok"]),
			false,
			"and so does a bar of %.2f" % bar
		)


func test_a_negative_bar_is_read_as_zero_rather_than_as_a_refusal() -> void:
	# The same reading `standing_at_least` gives a negative `at`: a bar below zero is
	# zero, which is satisfiable, not a content bug.
	var actor := _member(1.0, 0)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"recognised_at_least", "at": -5.0})["ok"]),
		true,
		"clamped, and therefore satisfiable by any member"
	)


# --- The verdict shape ---------------------------------------------------------


func test_the_verdict_carries_the_three_keys_a_panel_needs() -> void:
	var verdict := ClanApi.unmet(_member(0.0, 100), {"verb": &"recognised_at_least", "at": 80.0})
	assert_eq(verdict.has("ok"), true, "ok is present")
	assert_eq(verdict.has("reason"), true, "reason is present")
	assert_eq(verdict.has("unmet"), true, "unmet is present")
	assert_eq(String(verdict["reason"]), "unmet", "and this is a plain unmet, not a refusal")
	assert_eq((verdict["unmet"] as Array).size(), 1, "one complaint")
	var entry := _unmet_entry(verdict)
	assert_eq(entry.keys().size(), UNMET_KEYS.size(), "no extra key")
	for key in UNMET_KEYS:
		assert_eq(entry.has(key), true, "carries '%s'" % key)
	assert_eq(String(entry["kind"]), String(ClanGate.KIND_RECOGNITION), "and it is a recognition")
	assert_eq(String(entry["id"]), String(HOUSE), "about the house the member is in")
	assert_almost_eq(float(entry["required"]), 80.0, "the bar it was asked for")
	assert_almost_eq(
		float(entry["actual"]), 100.0 * ClanGate.UNSCALED, "and what the member actually holds"
	)
	assert_ne(String(entry["label"]), "", "with a label a panel can render")


func test_the_facade_adds_nothing_to_the_verdict() -> void:
	var actor := _member(0.5, 40)
	for requirement in [
		{},
		{"verb": &"recognised_at_least", "at": 10.0},
		{"verb": &"recognised_at_least", "at": 9999.0},
		{"verb": &"not_a_verb"},
	]:
		assert_eq(
			ClanApi.unmet(actor, requirement),
			ClanGate.evaluate(actor, requirement),
			"the facade is a pass-through for %s" % [requirement]
		)


# --- Refuse-with-cause, like every sibling verb --------------------------------


## An unreadable bar is malformed content, not a player being told no — so it refuses
## and says why, rather than reading an absent `at` as zero and opening the door.
func test_a_recognition_gate_with_no_numeric_bar_refuses() -> void:
	for requirement in [
		{"verb": &"recognised_at_least"},
		{"verb": &"recognised_at_least", "at": "high"},
		{"verb": &"recognised_at_least", "at": null},
		{"verb": &"recognised_at_least", "at": {}},
	]:
		var verdict := ClanApi.unmet(_member(), requirement)
		assert_eq(bool(verdict["ok"]), false, "%s refuses" % [requirement])
		assert_eq(String(verdict["reason"]), "malformed", "as malformed")
		assert_ne(String(_unmet_entry(verdict)["label"]), "", "and says so in the label")


func test_the_new_verb_composes_inside_the_aggregates() -> void:
	var member := _member(1.0, 100)
	var outsider_bar := {
		"verb": &"all_of",
		"of":
		[
			{"verb": &"is_clan", "id": String(HOUSE)},
			{"verb": &"recognised_at_least", "at": 50.0},
		],
	}
	assert_eq(bool(ClanApi.unmet(member, outsider_bar)["ok"]), true, "all_of satisfied")
	var impossible := {
		"verb": &"any_of",
		"of":
		[
			{"verb": &"is_clan", "id": String(RIVAL)},
			{"verb": &"recognised_at_least", "at": 50.0},
		],
	}
	assert_eq(bool(ClanApi.unmet(member, impossible)["ok"]), true, "any_of satisfied")
	var forbidden := {
		"verb": &"none_of",
		"of": [{"verb": &"recognised_at_least", "at": 50.0}],
	}
	assert_eq(bool(ClanApi.unmet(member, forbidden)["ok"]), false, "none_of refuses a match")
	# And a malformed child still poisons the composite, exactly as before.
	var poisoned := {
		"verb": &"all_of",
		"of": [{"verb": &"recognised_at_least"}, {"verb": &"is_clan", "id": String(HOUSE)}],
	}
	assert_eq(String(ClanApi.unmet(member, poisoned)["reason"]), "malformed", "poisoned still")


func test_a_sibling_modules_verb_is_still_refused_rather_than_obeyed() -> void:
	# The eight-verb set is closed: `regard_at_least` belongs to `SocialApi.gate`, and
	# reading it here would be this module reaching past its own vocabulary.
	var verdict := ClanApi.unmet(
		_member(), {"verb": &"regard_at_least", "partner": String(HOUSE), "at_least": 1.0}
	)
	assert_eq(bool(verdict["ok"]), false, "refused")
	assert_eq(String(verdict["reason"]), "unknown_verb", "as unknown, not as malformed")


func test_the_gate_never_refuses_a_null_actor_rather_than_crashing_on_one() -> void:
	var verdict := ClanApi.unmet(null, {"verb": &"recognised_at_least", "at": 10.0})
	assert_eq(bool(verdict["ok"]), false, "no")
	assert_eq(String(verdict["reason"]), "unmet", "as unmet rather than as a refusal")
	assert_eq((verdict["unmet"] as Array).size(), 1, "and it says why")


# --- The gate reads a ledger, not a stat ---------------------------------------


## ## The anti-buyout rule, as an assertion rather than a comment
##
## An item that grants `clan_standing` moves the derived stat, because a stat can be
## granted by anything. This is the shape that must NOT open the door — which is why
## the verb reads `ClanState` and `BloodlineState` and has no `StatContext` anywhere in
## its path (ADR 0076: "Gates read the ledger, never a stat").
func test_a_modifier_that_raises_the_published_stat_does_not_open_the_door() -> void:
	var actor := _member(1.0, 0)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"recognised_at_least", "at": 50.0})["ok"]),
		false,
		"shut on the ledger"
	)
	actor.stats.add_modifier(
		StatModifier.new(ClanStats.STANDING, Stat.Op.FLAT, 1000.0, &"a_purchased_item")
	)
	actor.mark_stats_dirty()
	assert_almost_eq(
		actor.stats.derived(ClanStats.STANDING), 1000.0, "the stat now reads a thousand"
	)
	assert_eq(
		bool(ClanApi.unmet(actor, {"verb": &"recognised_at_least", "at": 50.0})["ok"]),
		false,
		"and the door is still shut: the gate never read it"
	)
	assert_eq(ClanGate.recognised_of(actor), 0.0, "the read model is unmoved too")
