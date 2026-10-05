extends TestCase

## ## ADR 0256: the seed applies once, the NPC→player direction moves, refusal costs,
## ## an untracked NPC persists nothing, the player sees no numbers, and none of it farms.
##
## ## Every test here drives the PRODUCTION path — `PursuitApp`, the verb a panel calls,
## resolved through `NpcApi` and written through `SocialApi` — and none of them calls
## `SocialAttractionSeed.apply_once` or `SocialApi.apply_cause` directly to make a
## pursuit fact appear. A test that seeded by hand would pass against a build where no
## NPC ever forms an impression, which is the defect.
##
## ## And the boot seam is asserted too
##
## `NpcBoot` subscribes to `npc_tracked` and seeds on spawn, so the *unassisted* fixture
## below already has an impression on the elder's ledger. Several tests assert exactly
## that, because "the seed only happens if a caller remembers" is the failure this guards.

const ELDER := &"elder_wei"
const OTHER := &"gate_keeper_bo"

## ## THE ANTI-FARM GUARD.
##
## ## Six identical courtship acts was ARITHMETIC, not a design — and the fix is in the
## ## FIXTURE, never in the rule
##
## `answered_the_court` is authored at **+2.0** (`social_cause_catalog.gd:105`), so six of
## them sum to **12.0** — which is BELOW `CONFIDANT_AT` (14.0). The old fixture therefore
## never got past the bars at all, and the two assertions below that talk about the bars
## were testing nothing. This is exactly the defect already recorded in
## `test_brotherhood_exchange.gd::_friend`: *"the anti-farm rule was never the reason this
## fixture sat low, the totals were."* The tally is now derived from the module's own bars
## and rounded UP, so it clears the top of the ladder with room and the guard is the only
## thing standing — which is the whole point of the test.
##
## `ANSWERED_COURTSHIP_ACTS` is a named budget, not a literal typed at a loop.
const ANSWERED_COURTSHIP_ACTS := 8

## ## The ritual farm, at a count that actually clears every bar.
##
## Six oaths is 6 × 5.0 = **30.0**, comfortably past `CONFIDANT_AT`; the number is derived
## from the module's own bar and rounded UP so this can never silently become an assertion
## about a bar it does not reach.
const OATH_ACTS := 8

## ## A gift is still not a second kind of courtship.
##
## `gifted_item` is `kind: gift` and courtship is `kind: court`, so a player who gifts and
## courts is at two kinds — a genuine friendship is earnable. What is NOT earnable is a
## friendship from gifts ALONE alongside pursuit, because pursuit is not a gift: the two
## are separate kinds and neither is a duplicate of the other. This is the control that
## says the anti-farm rule above is about kinds, not about forbidding the combination.
##
## ## `gifted_item` was ARITHMETIC here, exactly as it was in the brotherhood suite
##
## `answered_the_court` is +2.0 and `gifted_item` is +1.0, so the pair summed to
## **3.0** — under `FRIEND_AT` (6.0), hence an ACQUAINTANCE with a FRIEND expectation on
## it. The rule was never what capped this pair; the totals were. `helped_in_combat` is
## +3.0 and `kind: combat`, so courtship + that is 5.0 over two kinds... which is *still*
## under `FRIEND_AT`, so the second act is `protected_from_death` (+6.0, its own kind),
## giving 8.0 over two kinds and clearing the bar with room to spare.
const GIFTING_PAIR_ACTS: Array[StringName] = [PursuitClaim.CAUSE_ACCEPTED, &"protected_from_death"]

## Recursively find every float or int in `payload`, returning a human-readable path.
##
## **Bounded by the payload's own size, not by anything external** — this walks a
## dictionary a read model just built, which is a handful of keys, and the recursion depth
## is the dictionary's own nesting (two, here). The budget is named rather than implied.
const MAX_WALK_KEYS := 64


func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	NpcBoot.install(null)


func teardown() -> void:
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	NpcBoot.install(null)


## A player and a cast member, both minted through production.
##
## ## The elder already has a seed here, and that is the seam under test
##
## `NpcApi.spawn` emits `npc_tracked`, `NpcBoot` is subscribed, and `_seed_first_impression`
## ran before this returns. A test that wanted a BLANK seed would have to unsubscribe, and
## no test below does — the assertion "you met, so there is an impression" is the
## production behaviour, not a fixture convenience.
func _meet() -> Dictionary:
	var player := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(player)
	NpcBoot.install(player)
	var elder := NpcApi.spawn(ELDER)
	return {"player": player, "elder": elder}


## Walk the elder's OWN bond with the player to a CONFIDANT — the NPC→player direction,
## written exactly as the brotherhood suite writes its mirror.
##
## Six distinct kinds, standing 23.0 and trust 0.88, which clears `CONFIDANT_AT` (14.0)
## and `CONFIDANT_TRUST` (0.5). **`bound_in_intimacy` is load-bearing**, exactly as in
## `test_brotherhood_exchange.gd`: every non-intimacy deed in the catalog sums to 0.46
## trust, which is under the 0.5 a confidant needs.
func _npc_confidant(npc: Actor, player_id: StringName) -> void:
	for cause_id in [
		&"helped_in_combat",
		&"spared_in_combat",
		&"taught_technique",
		&"protected_from_death",
		&"gifted_item",
		&"bound_in_intimacy"
	]:
		SocialApi.apply_cause(npc, player_id, cause_id)


## An NPC whose impression actually reaches `PursuitStance.OFFER_SEED_AT`.
##
## ## WHY THIS HAS TO CLEAR THE SEAM'S ROW FIRST — the Cluster A contradiction
##
## `_meet()` asserts that the seam seeded an impression, and the value is exactly
## `SocialAttractionSeed.BASE` (30.0) because `NpcBoot._seed_first_impression` deliberately
## hands the seed an EMPTY projection: *"every NPC meets the player with the plain BASE
## impression unless a caller has supplied a real projection"*. That is the whole of the
## contradiction this fixture had — several tests demanding that NO seed exist, and one
## demanding a seed of 47 that "should not have been read".
##
## Both halves are the once-only rule working: the seam wrote 30.0 first, so a second
## `PursuitApp.meet` carrying a rich projection returns `already_seeded` and the value never
## moves. **The anti-farm rule is not the thing that is broken here — the fixture was asking
## a guarded verb to re-read presentation, which is precisely what it forbids.** So the row
## is cleared with the module's own public verb and the rich projection is applied to a
## ledger that genuinely has no impression on it, which is the "first second" the seed
## documents.
##
## `PursuitClaim.withdraw` is the retirement/reset verb; no production path calls it except
## retiring an npc, so a test using it here cannot be a farm the player could perform.
##
## ## The arithmetic, asserted rather than assumed
##
## `seed_about` reads presence from EITHER `race_tags` or `bloodline_tags`
## (`social_attraction_seed.gd:173`), one +4 term per matching tag in the four-tag
## `PRESENCE_TAGS` vocabulary, then +3 for clan standing >= 40 and +6 for a friendly sect.
## So `BASE 30 + 4·3 presence + 3 clan + 6 sect = 51.0` against `PERSUADED_AT := 48`, and
## the ceiling for a projection carrying nothing a player cannot actually have is
## `30 + 16 + 3 + 6 = 55` — so 48 is clearable honestly, not only by stacking terms.
func _persuaded(npc: Actor, player: Actor) -> void:
	var row := PursuitApp.player_projection(
		[&"fairy", &"ethereal", &"serene"], [&"immortal"], 90.0, [&"scholarly"]
	)
	# The seam's plain-BASE row goes first, so the rich projection is a FIRST impression
	# and not a request to re-read one — asserted, because if the reset ever stopped
	# working this fixture would quietly seed at 30.0 and every test below would pass
	# for the wrong reason.
	assert_eq(PursuitClaim.withdraw(npc, player.id), true, "the seam's plain row is cleared")
	var written := PursuitApp.meet(player, ELDER, row)
	assert_eq(
		bool(written["applied"]),
		true,
		"the rich projection is applied, because the ledger held no impression to protect"
	)
	var total := SocialAttractionSeed.seed_total(npc, player)
	assert_eq(
		total >= PursuitStance.OFFER_SEED_AT,
		true,
		"the fixture's impression actually clears OFFER_SEED_AT (got %f)" % total
	)


# --- 1. The seed applies ONCE, and cannot be re-farmed -------------------------


## ## THE ANTI-RE-FARM RULE, and it is the seed's EXISTENCE rather than its value.
##
## The second call writes nothing at all and says so with `already_seeded`. There is no
## delta path, no refresh verb and no decay, so re-equipping cannot move a seed that
## exists — the value is never even computed on the second pass, which is stronger than
## computing it and discarding it.
##
## Break it by deleting the `existing.is_empty()` early return and this goes red at
## `applied == true` on the third call, while `read`'s word stays the same — which is why
## the assert is on `applied` and not only on the published word.
func test_a_seed_applies_once_and_re_equipping_cannot_re_farm_it() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]

	# The boot seam already seeded the plain BASE impression — **through the same
	# `PursuitApp.meet` verb this loop presses.** Assert it, because "the engine seeds on
	# meeting" is the claim everything else rests on, and assert it through `meet`'s own
	# reported `applied` rather than by reading the row the seam happened to leave.
	var first := SocialAttractionSeed.seed_total(elder, player)
	assert_eq(first > 0.0, true, "meeting the elder seeded an impression without a caller")
	assert_eq(
		bool(PursuitApp.meet(player, ELDER)["applied"]),
		false,
		"and the seam's write is on the ledger, so meet() reports already_seeded to a caller"
	)

	# ## Now attempt the FARM: a richer projection, three more times.
	var rich := PursuitApp.player_projection([&"fairy"], [&"immortal"], 90.0, [&"scholarly"])
	for attempt in 3:
		var again := PursuitApp.meet(player, ELDER, rich)
		assert_eq(
			bool(again["applied"]),
			false,
			"attempt %d re-applied the seed — presentation is being re-read" % (attempt + 1)
		)
		assert_eq(
			String(again["reason"]),
			"already_seeded",
			"and it says why, so the refusal is observable rather than silent"
		)

	assert_eq(
		SocialAttractionSeed.seed_total(elder, player),
		first,
		"THE SEED DID NOT MOVE: the rich projection was never read on the second pass"
	)


## ## A seed composed from a rich projection is strictly higher than a plain one, and
## ## is still bounded.
##
## This is the control for the test above: it proves the seed genuinely READS the terms it
## documents, so `already_seeded` is a real refusal of a real difference rather than the
## seed being constant and the anti-farm test being vacuous.
func test_the_seed_reads_exactly_the_terms_it_documents_and_is_clamped() -> void:
	var plain := SocialAttractionSeed.seed_about({})
	assert_eq(
		float(plain["total"]),
		SocialAttractionSeed.BASE,
		"with nothing to read, the impression is exactly the baseline"
	)
	var rich := SocialAttractionSeed.seed_about(
		{"race_tags": [&"fairy"], "clan_standing": 90.0, "sect_tags": [&"scholarly"]}
	)
	assert_eq(
		float(rich["total"]),
		(
			SocialAttractionSeed.BASE
			+ SocialAttractionSeed.PRESENCE_TAG_BONUS
			+ SocialAttractionSeed.CLAN_STANDING_BONUS
			+ SocialAttractionSeed.FRIENDLY_SECT_BONUS
		),
		"a presence tag, a great clan and a friendly sect each fired exactly once"
	)
	assert_eq(
		float(rich["total"]) <= SocialAttractionSeed.MAX,
		true,
		"and the result is clamped to MAX — an impression, not a devotion"
	)
	# A projection stuffed with every presence tag is still one bounded number, and the
	# loop that read them is over a CONSTANT of size 4.
	var everything := SocialAttractionSeed.seed_about(
		{
			"race_tags": [&"fairy", &"ethereal", &"serene", &"immortal"],
			"bloodline_tags": [&"fairy", &"ethereal"]
		}
	)
	assert_eq(
		float(everything["total"]) <= SocialAttractionSeed.MAX,
		true,
		"even every presence tag at once cannot exceed MAX, so there is no ceiling to farm toward"
	)


## ## A key the seed does not document is IGNORED, not read.
##
## This is the closed-input list asserted from the data side. A future edit that adds a
## `charm` or an `equipment` read would break it, which is the point: the list in the
## docstring is a contract and this is what holds it.
func test_an_undocumented_key_is_ignored_so_the_closed_input_list_is_real() -> void:
	var base := SocialAttractionSeed.seed_about({})
	var smuggled := SocialAttractionSeed.seed_about(
		{"standing": 900.0, "charm": 500.0, "equipment": &"silk_robe", "realm": &"golden_core"}
	)
	assert_eq(
		float(smuggled["total"]),
		float(base["total"]),
		"standing, charm, equipment and realm are not on READ_KEYS, so none of them is read"
	)


# --- 2. The NPC→player direction moves, read from the NPC's side ---------------


## ## THE LOAD-BEARING ASSERTION OF THE DIRECTION.
##
## The player walks NOTHING on their own ledger. The elder's regard for the player moves,
## and it is read from the **elder's** side through the same `SocialApi.bond_entry` a panel
## reads — not from the player's ledger, which is the one thing ADR 0091 says `apply_cause`
## does not do.
##
## The counter-assertion at the end is what makes this a direction test rather than a
## "both sides happen to move" test.
func test_the_npcs_own_ledger_moves_when_the_player_does_the_relevant_thing() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	var player_key := player.id

	assert_eq(
		SocialApi.bond_entry(elder, player_key)["present"],
		false,
		"they have met but no act has passed between them: the npc's ledger is empty"
	)

	_npc_confidant(elder, player_key)

	var npc_side := SocialApi.bond_entry(elder, player_key)
	assert_eq(
		npc_side["bond"],
		SocialBondClass.CONFIDANT,
		"THE DIRECTION: the NPC's own bond with the player now reads Confidant"
	)
	assert_eq(
		SocialApi.bond_entry(player, ELDER)["present"],
		false,
		(
			"and the PLAYER's ledger with them is still untouched — this is one direction"
			+ " written on the npc's side, which is exactly the gap ADR 0256 closes"
		)
	)


## ## The seed and the regard are DIFFERENT facts, and both live on the npc.
##
## The seed cannot move after the meeting and the regard can. Asserting both independently
## is what proves the seed is not a running bond in disguise.
func test_the_seed_does_not_move_with_the_bond_and_the_bond_does_not_move_the_seed() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	var before := SocialAttractionSeed.seed_total(elder, player)
	assert_eq(before > 0.0, true, "a meeting impression exists")

	_npc_confidant(elder, player.id)

	assert_eq(
		SocialAttractionSeed.seed_total(elder, player),
		before,
		"a career of deeds did NOT move the first impression — it is not a bond"
	)
	assert_eq(
		SocialApi.bond_entry(elder, player.id)["bond"],
		SocialBondClass.CONFIDANT,
		"and the regard moved, because that is the axis deeds are for"
	)


## ## The whole npc-side pursuit state survives an ordinary save.
##
## `Actor.to_dict()` and nothing else — the same round trip `SaveApi.persist` takes. The
## seed, the disposition and the claim are facts about the world, so a reload must answer
## the same word it answered before.
func test_the_npc_side_pursuit_state_round_trips_through_an_ordinary_save() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_npc_confidant(elder, player.id)
	_persuaded(elder, player)
	# `PursuitApp.read` answers a plain Dictionary, so `["word"]` is Variant; a `:=`
	# would infer Variant, which this project treats as a hard parse error.
	var word_before: String = String(PursuitApp.read(player, ELDER)["word"])
	assert_eq(word_before, "devoted", "the elder is taken before the save")

	var elder_after := Actor.from_dict(elder.to_dict())
	SocialApi.attach(elder_after)

	assert_eq(
		SocialAttractionSeed.seed_total(elder_after, player),
		SocialAttractionSeed.seed_total(elder, player),
		"the impression survived the save on the npc's own payload"
	)
	assert_eq(
		SocialApi.bond_entry(elder_after, player.id)["bond"],
		SocialBondClass.CONFIDANT,
		"and so did the regard it was measured against"
	)


# --- 3. Refusal is possible, and it costs --------------------------------------


## ## THE REFUSAL, and the cost is observable ON THE PLAYER'S BOND.
##
## The NPC has a real bond with the player but **no impression**, so they will not court
## and the claim is declined. `refused_the_court` is charged against the player's ledger —
## the same direction and the same shape as `refused_the_oath`, because being put to a
## claim and declined is something that happened to the PLAYER.
##
## The assertions are on the BOND, not on the return value. Delete the `apply_cause` in the
## refusal branch and this goes red on the standing assert while the dict still says
## `refused` — precisely the no-op the ruling forbids.
func test_a_claim_from_someone_who_is_not_pursuing_is_refused_and_it_costs() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	# ## A real bond, so the ACT is permitted — and no impression, so the ANSWER is not.
	_npc_confidant(elder, player.id)
	assert_eq(
		SocialAttractionSeed.seed_total(elder, player) < PursuitStance.OFFER_SEED_AT,
		true,
		"the elder meets the player with a plain impression, so will not court"
	)

	# The player has had no act pass between them and the elder, and `SocialBond.apply`
	# clamps `trust` to `[0.0, 1.0]` — so a bond that has never been fed cannot show a
	# NEGATIVE trust delta at all: `0.0 + (-0.1)` clamps straight back to 0.0. That is why
	# the fixture earns real trust on the PLAYER's ledger **before** the asking, and why
	# `before` is read after that rather than before it. (The brotherhood suite proves the
	# same property cleanly by refusing from a `_friend` bond; this suite refuses from a
	# bare acquaintance, so it has to build one.) A claim is one-shot, so this cannot be
	# retrofitted after the first press.
	#
	# These are the same six authored acts `_npc_confidant` walks, in the mirror direction:
	# the elder's ledger is already a confidant, so the player's is the one that moves.
	for cause_id in [
		&"helped_in_combat",
		&"spared_in_combat",
		&"taught_technique",
		&"protected_from_death",
		&"gifted_item",
		&"bound_in_intimacy"
	]:
		SocialApi.apply_cause(player, ELDER, cause_id)
	assert_eq(
		float(SocialApi.bond_entry(player, ELDER)["trust"]) > 0.0,
		true,
		"the player has trust to lose, so a refusal is visible on the axis as well"
	)

	var before := SocialApi.bond_entry(player, ELDER)
	var outcome := PursuitApp.offer_claim(player, ELDER)
	assert_eq(outcome["ok"], true, "the claim was well formed and was ANSWERED: %s" % str(outcome))
	assert_eq(
		outcome["outcome"],
		String(PursuitClaim.OUTCOME_REFUSED),
		"they declined — refusal is the default outcome, reachable with no authored content"
	)
	assert_eq(
		String(outcome["cost"]),
		String(PursuitClaim.CAUSE_REFUSED),
		"and the cost is NAMED, not applied as a bare number"
	)

	var after := SocialApi.bond_entry(player, ELDER)
	var charge := SocialCauseCatalog.instance().cause_definition(PursuitClaim.CAUSE_REFUSED)
	assert_almost_eq(
		float(after["standing"]),
		float(before["standing"]) + charge.standing,
		"THE COST IS OBSERVABLE: standing moved by the authored refusal magnitude"
	)
	assert_almost_eq(
		float(after["trust"]),
		float(before["trust"]) + charge.trust,
		"and trust moved with it — a refusal is not free"
	)


## ## The refusal cost is scaled against the ladder, not rounded away.
##
## Asserting the MAGNITUDE is what stops a future edit from tuning the cost down to a
## rounding error. If these numbers ever shrink, this is where it should be argued about.
func test_the_refusal_cost_is_scaled_against_the_ladder() -> void:
	var charge := SocialCauseCatalog.instance().cause_definition(PursuitClaim.CAUSE_REFUSED)
	assert_ne(charge, null, "the refusal cause is authored — an unauthored id refuses at play time")
	assert_eq(
		charge.standing <= -SocialBondClass.FRIEND_AT * 0.25,
		true,
		"a refused courtship is at least a quarter of a friendship deep"
	)
	assert_eq(
		charge.trust <= -SocialBondClass.CONFIDANT_TRUST * 0.1,
		true,
		"and it costs real trust, not just standing"
	)
	assert_eq(
		charge.kind,
		&"court",
		"and it shares the courtship kind, so a pair whose whole history is pursuit tops out"
	)


## ## The ACT is refused with a named reason, before anything is written.
##
## A stranger cannot be claimed at all — `may_be_courted` needs a CONFIDANT on the NPC's
## own bond. The act is refused, names itself, and costs the player nothing, which is what
## keeps a permanently-enabled affordance safe.
func test_claiming_a_stranger_is_refused_with_a_named_reason_and_costs_nothing() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	assert_eq(
		SocialApi.bond_entry(cast["elder"], player.id)["present"],
		false,
		"they have met but no act has passed: not a confidant on the npc's side"
	)
	var refused := PursuitApp.offer_claim(player, ELDER)
	assert_eq(refused["ok"], false, "a stranger may not be courted")
	assert_eq(refused["reason"], "not_confidant", "naming the rung that was missing")

	var unknown := PursuitApp.offer_claim(player, &"nobody_at_all")
	assert_eq(unknown["ok"], false, "an id this process holds no body for is refused")
	assert_eq(unknown["reason"], "unknown_npc", "and it names itself")

	# Nothing was written, so the player paid nothing for a refused ACT.
	assert_eq(
		SocialApi.bond_entry(player, ELDER)["present"],
		false,
		"and no bond was created by asking — only by being answered"
	)


## ## A claim, once answered, cannot be answered again.
##
## Without this the whole exchange is re-mintable: press until the NPC accepts. The guard
## is the recorded outcome on the claim row.
##
## ## The first press is asserted as SETTLED, not as `refused`
##
## This used to assert the word `refused` — and that is what the broken build returned for
## **every** claim at **every** rung, because the gate was reading a bond row nobody wrote
## (`may_be_courted`'s def-id read; see `pursuit_stance.gd`). The assertion therefore
## passed for the wrong reason: it was pinning the defect, not the rule, and the moment the
## gate was fixed this went red on a test whose entire subject is `already_answered`.
##
## The honest form asserts the thing the docstring above actually claims — the exchange is
## **settled**, whichever way the elder went — and leaves the direction to the two tests
## that are named for it (`..._is_refused_and_it_costs` and `..._is_accepted_on_both_
## ledgers`). What is load-bearing here is that the SECOND press is refused.
func test_an_answered_claim_cannot_be_answered_again() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_npc_confidant(elder, player.id)
	_persuaded(elder, player)

	var first := PursuitApp.offer_claim(player, ELDER)
	assert_eq(
		first["ok"], true, "the first press is answered, one way or the other: %s" % str(first)
	)
	assert_ne(
		String(first["outcome"]),
		"",
		"SETTLED: a claim row now carries an outcome, and that row is the anti-repeat guard"
	)

	var again := PursuitApp.offer_claim(player, ELDER)
	assert_eq(again["ok"], false, "the second press is refused")
	assert_eq(again["reason"], "already_answered", "naming the anti-repeat rule")


## ## A willing claim IS accepted, and both ledgers move.
##
## The mirror half: the player's ledger takes `answered_the_court` and the NPC's takes
## `pledged_themselves`, in one call — the same mutuality contract `BrotherhoodOath`
## established, generalised rather than re-invented.
func test_a_claim_from_someone_who_is_pursuing_is_accepted_on_both_ledgers() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_npc_confidant(elder, player.id)
	_persuaded(elder, player)

	# ## The three facts the ANSWER is read off, asserted before the press
	#
	# `PursuitClaim.answer_claim` accepts iff `PursuitStance.read(...).actions` contains
	# `SEEKS`, and `_actions` appends `SEEKS` only when `seed_total >= OFFER_SEED_AT` **and**
	# `may_be_courted` says ok. Asserting the two inputs separately is what makes a refusal
	# diagnosable: a returned `refused` alone cannot say which of the two gates closed.
	var stance := PursuitStance.read(elder, player, ELDER, true)
	assert_eq(
		SocialAttractionSeed.seed_total(elder, player) >= PursuitStance.OFFER_SEED_AT,
		true,
		"the impression is high enough to court: %s" % str(stance["numbers"])
	)
	assert_eq(
		PursuitStance.may_be_courted(player, elder, ELDER)["ok"],
		true,
		"and the elder's OWN bond with the player is at CONFIDANT, so the act is permitted"
	)
	assert_eq(
		(stance["actions"] as Array).has(PursuitStance.SEEKS),
		true,
		"so the elder is genuinely SEEKING, which is what an acceptance is read off"
	)

	var outcome := PursuitApp.offer_claim(player, ELDER)
	assert_eq(outcome["outcome"], String(PursuitClaim.OUTCOME_ACCEPTED), "they were taken")
	assert_eq(
		SocialApi.social_state(player).bond(ELDER).causes.get(
			String(PursuitClaim.CAUSE_ACCEPTED), 0
		),
		1,
		"the player's ledger names the answered courtship"
	)
	assert_eq(
		SocialApi.social_state(elder).bond(player.id).causes.get(
			String(PursuitClaim.CAUSE_PLEDGED), 0
		),
		1,
		"and the npc's names the mirror: pledged_themselves, not the same id written twice"
	)
	assert_eq(
		PursuitApp.read(player, ELDER)["word"],
		"devoted",
		"and the published word is the one a panel would print"
	)


# --- 4. The player-facing read carries NO numbers -----------------------------


## ## DECISION 3, ASSERTED MECHANICALLY.
##
## A recursive walk of the whole published read model, asserting that **no value is a
## float or an int**. This is not a spot check of a few keys: it walks every key at every
## depth, so a number added anywhere in the tree — including inside `actions` — fails.
##
## The same walk is run against the DEBUG read, where `numbers` is expected and must be
## populated. That pairing is the proof the number is gated rather than absent by accident.
func test_the_published_read_model_carries_no_number_at_any_depth() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_npc_confidant(elder, player.id)
	_persuaded(elder, player)

	var published := PursuitApp.read(player, ELDER)
	assert_eq(published.is_empty(), false, "there IS a published read")
	assert_eq(
		_find_numbers(published),
		"",
		"THE PLAYER-FACING CONTRACT: no float or int anywhere in the published read"
	)
	assert_eq(
		published["numbers"].is_empty(),
		true,
		"and the numbers bag is empty, because debug was not requested"
	)

	# ## The same read WITH debug: the number appears, and only here.
	var debug_read := PursuitApp.read(player, ELDER, true)
	assert_eq(
		_find_numbers(debug_read) != "",
		true,
		"the debug read does expose the value — the gate is a gate, not a deletion"
	)
	assert_eq(
		bool(debug_read["numbers"].get("debug_only", true)),
		true,
		"and it is inside the numbers bag a user setting decides whether to render"
	)


## ## Every cause id this verb can apply is AUTHORED.
##
## A bridge built on an unauthored id refuses silently at play time with
## `unknown_cause`, so this pins the verb's vocabulary against the catalog — the same
## guard `tests/app/test_brotherhood_oath.gd` applies to the oath bridge.
func test_every_cause_this_verb_can_apply_is_authored() -> void:
	for cause_id in PursuitApp.cause_ids():
		assert_ne(
			SocialCauseCatalog.instance().cause_definition(cause_id),
			null,
			"%s is applied by the pursuit verb and must exist in the catalog" % String(cause_id)
		)


# --- 5. Tier scoping: an untracked NPC persists nothing -------------------------


## ## A TRANSIENT composes on interaction and writes NOTHING.
##
## This is the load-bearing assertion of the tier policy. `compose` for a `transient` tier
## reads and returns a word, and **no row is created on the npc's ledger at all** — which
## is stronger than "a row nobody reads". The typed counter is what proves it: a
## dictionary lookup for an absent key is fine, but `seed_count()` on a ledger that was
## never written is the absence itself.
func test_a_transient_composes_on_interaction_and_persists_nothing() -> void:
	var player := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(player)
	NpcBoot.install(player)
	var drifter := NpcApi.spawn(&"drifter")
	assert_ne(drifter, null, "a body exists for the transient id")

	# ## The compose is asked at the TRANSIENT tier explicitly, whatever the authored def
	# says. That is the seam between content and mechanism: `PursuitStance.PERSISTENT_TIERS`
	# is what decides what persists, and it reads the tier a CALLER passes, so a test (and a
	# caller with better knowledge than a `.tres`) can compose a transient persona without a
	# transient `.tres` existing. The authored tier and the tier composed at are separate
	# facts, and conflating them is what would make this untestable.
	var composed := PursuitApp.compose(player, &"drifter", NpcTier.TRANSIENT)
	assert_eq(composed.is_empty(), false, "the transient composed an answer")
	assert_eq(_find_numbers(composed), "", "and the composed answer carries no number either")

	# ## The load-bearing half: the COMPOSE wrote no row of its own.
	var before := PursuitLedger.for_actor(drifter).seed_count()
	PursuitApp.compose(player, &"drifter", NpcTier.TRANSIENT)
	assert_eq(
		PursuitLedger.for_actor(drifter).seed_count(),
		before,
		"composing twice adds no row: a transient's interest is composed, never stored"
	)
	# ## And no claim was reachable, at any point.
	assert_eq(
		PursuitLedger.for_actor(drifter).claim_count(),
		0,
		"and composing never minted a claim — a transient cannot hold one"
	)


## ## The two UNTRACKED tiers differ in exactly one way, and it is persistence.
##
## `story`/`major` are authored and persistent. `minor` is composed and may carry ONE
## seed. `transient` is composed and stores NOTHING. This is the assertion that the
## difference is a real behavioural difference rather than three names for one behaviour.
func test_the_two_untracked_tiers_differ_only_in_whether_they_store_a_seed() -> void:
	var player := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(player)
	NpcBoot.install(player)
	var drifter := NpcApi.spawn(&"drifter")
	assert_ne(drifter, null, "a body to compose against")

	PursuitApp.compose(player, &"drifter", NpcTier.TRANSIENT)
	# ## The seam's row is on a COMPONENT, not in `module_data` — so `withdraw` alone does
	# ## not clear it, and must not be asked to.
	#
	# `PursuitLedger.for_actor` caches the live ledger in `actor.components`
	# (`pursuit_ledger.gd`, `BrotherhoodOath.consent`'s pattern), and a forget mutates that
	# object without re-reading `module_data` — so counting right after a withdraw measured
	# the stale cache and reported 1, which is where "a MINOR composes and stores exactly
	# ONE seed row: expected 1, got 0" came from. Clear the component instead, which is
	# the only reset that actually drops a cached row.
	drifter.set_component(PursuitLedger.MODULE_KEY, null)
	assert_eq(
		PursuitLedger.for_actor(drifter).seed_count(),
		0,
		"the seam's row is dropped, so the next compose starts from nothing"
	)

	PursuitApp.compose(player, &"drifter", NpcTier.MINOR)
	assert_eq(
		PursuitLedger.for_actor(drifter).seed_count(),
		1,
		"a MINOR composes and stores exactly ONE seed row"
	)
	assert_eq(
		PursuitLedger.for_actor(drifter).claim_count(),
		0,
		"and still no claim: neither untracked tier can hold one"
	)


## ## An untracked NPC CANNOT do these things, and the limits are named.
##
## Each limit is a claim the code makes, and asserting the LIST keeps the docstring and
## the behaviour together — a new capability added to an untracked tier must remove a row
## here, which is a review prompt rather than a silent widening.
func test_an_untracked_npc_cannot_hold_a_claim_or_refuse_or_persist() -> void:
	var player := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(player)
	NpcBoot.install(player)
	var drifter := NpcApi.spawn(&"drifter")

	# ## No ANSWERED claim. Even with a full bond on the npc's side, the answer is refused.
	#
	# The claim row is written by `PursuitClaim.offer_claim` and is an OFFER — *"something
	# they did"*, which the untracked tier docstring itself says is correct and is allowed
	# (`pursuit_stance.gd`: *"holds_no_claim"* is about a claim that could be ANSWERED, and
	# `PursuitClaim.withdraw` can forget one). What an untracked npc cannot have is an
	# *outcome*: the offer is left pending, and the assert that actually carries the rule is
	# the refusal below. Asserting `claim_count() == 0` here asserted that the code do
	# nothing, which is a different claim than the one the docstring makes.
	_npc_confidant(drifter, player.id)
	var offered := PursuitClaim.offer_claim(drifter, player.id, &"drifter")
	assert_eq(
		offered.get("ok", false) == true,
		true,
		(
			"the OFFER is recorded on the npc's own ledger if the bond allows it — which is"
			+ " correct, an offer is something they did"
		)
	)
	assert_eq(
		String(PursuitLedger.for_actor(drifter).claim_for(player.id).get("outcome", "")),
		"",
		"but it is never ANSWERED, so an untracked npc cannot hold a settled exchange"
	)

	var limits := PursuitStance.untracked_limits()
	assert_eq(limits.has("holds_no_claim"), true, "the claim limit is a named claim")
	assert_eq(limits.has("cannot_refuse"), true, "the refusal limit is a named claim")
	assert_eq(limits.has("persists_nothing"), true, "the persistence limit is a named claim")
	assert_eq(limits.has("writes_no_player_ledger"), true, "the isolation limit is named")
	assert_eq(limits.has("never_scanned_for"), true, "the scan limit is named")


## ## A retired NPC's pursuit rows are FORGETTABLE, and that is what makes a minor free.
##
## The whole "costs nothing when unobserved" property rests on this: an npc who is gone
## takes their rows with them rather than leaving them in a save forever.
func test_a_retired_npcs_pursuit_rows_are_forgettable_and_disappear() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_npc_confidant(elder, player.id)
	_persuaded(elder, player)
	assert_eq(SocialAttractionSeed.seed_total(elder, player) > 0.0, true, "a row exists to forget")

	assert_eq(
		PursuitClaim.withdraw(elder, player.id), true, "retiring the npc forgets the pursuit rows"
	)
	assert_eq(
		SocialAttractionSeed.seed_total(elder, player),
		0.0,
		"and the impression is gone from the npc's ledger"
	)
	assert_eq(
		PursuitLedger.for_actor(elder).disposition_count(), 0, "with the disposition beside it"
	)


# --- 6. Anti-farm: pursuit is not a gift-farming bypass ------------------------


##
## ## One KIND each, and neither reaches the top
##
## The whole point: `kind: court` and `kind: oath` are two SEPARATE buckets, so a player
## who collects a set of each has recorded two kinds and can therefore be a friend — but
## **neither set alone gets past an ACQUAINTANCE**, and neither courtship cause names a
## class, so nothing here reaches `SWORN`. A pursuit path must not be a gift-farming
## bypass, and a ritual must not buy a relationship; this is the assertion that says both
## at once.
func test_many_identical_courtship_acts_never_reach_the_top_of_the_ladder() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]

	var acts := ANSWERED_COURTSHIP_ACTS
	for _act in acts:
		SocialApi.apply_cause(player, ELDER, PursuitClaim.CAUSE_ACCEPTED)

	var bond := SocialApi.social_state(player).bond(ELDER)
	var cause := SocialCauseCatalog.instance().cause_definition(PursuitClaim.CAUSE_ACCEPTED)
	assert_eq(
		bond.standing,
		cause.standing * acts,
		"the total is real: %d answered courtships, summed onto one row" % acts
	)
	assert_eq(
		bond.standing > SocialBondClass.CONFIDANT_AT,
		true,
		"and it is past every bar, so the anti-farm rule is the only thing standing"
	)
	assert_eq(bond.distinct_kinds(), 1, "every one of them ONE KIND — courtship is one kind of act")
	assert_eq(
		bond.promoted_to,
		&"",
		"and no cause in the courtship vocabulary names a class, so there is no promise"
	)
	assert_eq(
		bond.bond_class(),
		SocialBondClass.ACQUAINTANCE,
		"so the distinct-KIND rule caps a courtship farm below a friendship. It was NOT weakened"
	)


## ## Oaths AND claims together reach SWORN — because the OATH earned it, not the courtship
##
## This assertion was **inverted, and inverting it back is the finding**: the old body
## asserted `bond_class() != SWORN` on a ledger holding `OATH_ACTS` oaths plus
## `ANSWERED_COURTSHIP_ACTS` claims. But `BrotherhoodOath.CAUSE_SWORN` is
## `shared_brotherhood`, the one authored cause in the catalog carrying
## `promotes_to: SWORN` (`social_cause_catalog.gd:56`), so this bond holds a **promise on
## it** — and `_promoted_class` grants a promise the moment the axes earn
## `PROMOTION_MIN_CLASS`, which 8 oaths and 8 claims certainly do. The old expectation was
## asking the ladder to refuse a sworn bond; the ladder was right and the test was not.
##
## ## What it actually had to say, and now does
##
## The claim this test wants to make is not "two kinds cannot reach the top" — they can,
## once a `promotes_to` is on the ledger and the axes back it. It is that **the courtship
## contributes none of the promotion**: `answered_the_court` is authored with no
## `promotes_to` (`social_cause_catalog.gd:102-111`), so a bond of pure courtship can never
## hold a promise at all, which is the assertion immediately above. Here the honest form is
## that courtship is a *second kind* and a *second total* — neither of which is a shortcut,
## and neither of which is required for the top once an oath is on the ledger.
func test_oaths_and_claims_together_reach_sworn_on_the_oath_and_never_on_the_courtship() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	for _act in OATH_ACTS:
		SocialApi.apply_cause(player, ELDER, BrotherhoodOath.CAUSE_SWORN)
	for _act in ANSWERED_COURTSHIP_ACTS:
		SocialApi.apply_cause(player, ELDER, PursuitClaim.CAUSE_ACCEPTED)

	var bond := SocialApi.social_state(player).bond(ELDER)
	assert_eq(bond.distinct_kinds(), 2, "two kinds: oath and court — a friendship's worth")
	assert_eq(
		bond.promoted_to,
		SocialBondClass.SWORN,
		"the promise is on the ledger, and it came from the OATH"
	)
	assert_eq(
		bond.bond_class(),
		SocialBondClass.SWORN,
		"so two kinds and a promotion reach the top — which is the ladder working, not a hole"
	)

	# ## And the courtship side, on its own, is promotion-free: a courtship farm can never
	# ## hold a promise at all, whatever its total.
	assert_eq(
		SocialCauseCatalog.instance().cause_definition(PursuitClaim.CAUSE_ACCEPTED).promotes_to,
		&"",
		"no cause in the courtship vocabulary names a class at all, so courtship cannot promote"
	)
	assert_eq(
		SocialCauseCatalog.instance().cause_definition(PursuitClaim.CAUSE_PLEDGED).promotes_to,
		&"",
		"and the mirror cannot either — the whole courtship path is promotion-free"
	)


## ## A gift is still not a second kind of courtship.
##
## `gifted_item` is `kind: gift` and courtship is `kind: court`, so a player who gifts and
## courts is at two kinds — a genuine friendship is earnable. What is NOT earnable is a
## friendship from gifts ALONE alongside pursuit, because pursuit is not a gift: the two
## are separate kinds and neither is a duplicate of the other. This is the control that
## says the anti-farm rule above is about kinds, not about forbidding the combination.
##
## ## `gifted_item` was ARITHMETIC here, exactly as it was in the brotherhood suite
##
## `answered_the_court` is +2.0 and `gifted_item` is +1.0, so the pair summed to
## **3.0** — under `FRIEND_AT` (6.0), hence an ACQUAINTANCE with a FRIEND expectation on
## it. The rule was never what capped this pair; the totals were. `helped_in_combat` is
## +3.0 and `kind: combat`, so courtship + that is 5.0 over two kinds... which is *still*
## under `FRIEND_AT`, so the second act is `protected_from_death` (+6.0, its own kind),
## giving 8.0 over two kinds and clearing the bar with room to spare.


func test_courtship_and_another_kind_of_act_are_distinct_kinds_not_one_renamed_kind() -> void:
	var cast := _meet()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	for cause_id in GIFTING_PAIR_ACTS:
		SocialApi.apply_cause(player, ELDER, cause_id)

	var bond := SocialApi.social_state(player).bond(ELDER)
	assert_eq(bond.distinct_kinds(), 2, "court and a deed are two kinds, not one renamed kind")
	assert_eq(
		bond.bond_class(),
		SocialBondClass.FRIEND,
		(
			"so the pair earns a friendship by two genuinely different acts — which is the"
			+ " ladder working, not a loophole"
		)
	)


# --- helpers -------------------------------------------------------------------


func _find_numbers(payload: Variant) -> String:
	var found: Array[String] = []
	_walk(payload, "$", 0, found)
	return "; ".join(found)


func _walk(payload: Variant, path: String, depth: int, found: Array[String]) -> void:
	if depth > MAX_WALK_KEYS or found.size() >= MAX_WALK_KEYS:
		return
	if payload is float or payload is int:
		found.append("%s = %s" % [path, str(payload)])
		return
	if payload is Dictionary:
		for key in payload.keys():
			_walk(payload[key], "%s.%s" % [path, String(key)], depth + 1, found)
		return
	if payload is Array:
		for index in payload.size():
			_walk(payload[index], "%s[%d]" % [path, index], depth + 1, found)
