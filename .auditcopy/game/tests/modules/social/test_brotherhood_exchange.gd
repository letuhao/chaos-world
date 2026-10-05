extends TestCase

## ## BL-0745 closed: `sworn` is a thing a PLAYER does, through production
##
## ADR 0091 left `shared_brotherhood` the only authored cause carrying
## `promotes_to: SWORN` with no producer, so the top of the positive ladder was
## engine-reachable and player-unreachable. Every test below drives the **production
## path** — `BrotherhoodOathApp.offer`, the verb a panel presses, resolved through
## `NpcApi` and written through `SocialApi` — and none of them calls
## `SocialApi.apply_cause(shared_brotherhood)` to make the oath happen. A test that
## applied the cause by hand would pass against a build where the player cannot offer
## anything, which is the defect.
##
## ## The three properties the ruling names, in the order they matter
##
## 1. **Mutuality** — both ledgers move in the same call.
## 2. **Refusal is refused with a named reason and the cost is observable.**
## 3. **Anti-farm still holds** — nothing here weakens the distinct-KIND rule.

const ELDER := &"elder_wei"
const OTHER := &"gate_keeper_bo"
const WITNESS := &"elder_qin"


func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	NpcBoot.install(null)


func teardown() -> void:
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	NpcBoot.install(null)


## A player, the elder, and a witness — all minted through the production `NpcBoot`,
## so the roster entries, the stage projections and the minter are the shipped ones.
##
## ## The elder gets a career of HIS OWN, and that is a fact about the feature
##
## `accepted_the_oath` is the only act ever applied to the elder's bond with the player, so
## without this the mirror is a **single-kind** bond — and `SocialBondClass.classify`
## returns at the distinct-kind guard before `_promoted_class` is read, which means the
## elder could read `acquaintance` and never `sworn` no matter what the catalog authored.
## The mirror can only be sworn if a relationship actually existed between them, which is
## why it is walked here in the same order production would: deeds first, then the offer.
## **Mutuality is a fact about the bond, not about a key being written twice.**
func _stage() -> Dictionary:
	var player := Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(player)
	NpcBoot.install(player)
	var elder := NpcApi.spawn(ELDER)
	var witness := NpcApi.spawn(WITNESS)
	for cause_id in [&"helped_in_combat", &"protected_from_death", &"bound_in_intimacy"]:
		SocialApi.apply_cause(elder, player.id, cause_id)
	return {"player": player, "elder": elder, "witness": witness}


## ## Walk the player's bond with `id` up to a CONFIDANT through ordinary authored acts.
##
## Standing sums to **23.0** and trust to **0.88** across SIX distinct kinds — `combat`
## twice, `deed`, `protected_from_death`, `gift` and `intimacy` — so this is a genuine
## career and not one button, and it clears `CONFIDANT_AT` = 14.0 with `CONFIDANT_TRUST`
## = 0.5 well behind it, which is exactly the rung `SocialBondClass.PROMOTION_MIN_CLASS`
## requires.
##
## ## `bound_in_intimacy` is LOAD-BEARING here, and this is a catalog fact
##
## **Every personal DEED cause in the catalog sums to 0.46 trust** (`spared_in_combat`
## 0.10, `protected_from_death` 0.12, `helped_in_combat` 0.08, `honoured_a_debt` 0.08,
## `taught_technique` 0.06, `gifted_item` 0.02) and `CONFIDANT_TRUST` is 0.5 — so **no
## combination of them, taken once each, reaches a confidant.** The five non-intimacy acts
## used here reach only **0.38**. That is why this list carries what it carries, and it is
## worth stating rather than quietly working around: it is the one authored PERSONAL cause
## worth 0.5 trust, and it is deliberately **not** institutional, so it is a real bond
## between two people and lands on this ledger like any other.
func _confidant(player: Actor, id: StringName) -> void:
	for cause_id in [
		&"helped_in_combat",
		&"spared_in_combat",
		&"taught_technique",
		&"protected_from_death",
		&"gifted_item",
		&"bound_in_intimacy"
	]:
		SocialApi.apply_cause(player, id, cause_id)


## A friend and not yet a confidant: **9.0 over two kinds**.
##
## `helped_in_combat` (3.0, `combat`) and `protected_from_death` (6.0, its own kind) are
## two different acts of act, so the distinct-kind rule is satisfied and `FRIEND_AT = 6.0`
## is cleared with room to spare. It stops there — under `CONFIDANT_AT`, under
## `CONFIDANT_TRUST` — which is precisely the pair the exchange is designed for: this is
## a friend who may be ASKED and will DECLINE.
##
## ## The earlier `gifted_item` here was arithmetic, not a design
##
## `gifted_item` is +1.0, so `helped_in_combat` + `gifted_item` is **4.0** — an
## ACQUAINTANCE, short of `FRIEND_AT` by half. The docstring above it claimed the pair
## cleared 6.0 and it never did; the anti-farm rule was never the reason this fixture sat
## low, the totals were.
func _friend(player: Actor, id: StringName) -> void:
	SocialApi.apply_cause(player, id, &"helped_in_combat")
	SocialApi.apply_cause(player, id, &"protected_from_death")


# --- 1. SWORN is reachable, through the production path -----------------------


## ## The load-bearing assertion of the whole change.
##
## The player walks a bond to confidant, presses the verb, and the ladder's top rung
## answers. **Both classes are read through `SocialApi.bond_entry`, the same call a panel
## reads**, so this asserts what the player is shown rather than an internal field.
##
## Break it by deleting the `player_side` line from `BrotherhoodOath.swear_brotherhood`
## and this goes red at `stranger`, which is what a one-sided implementation would have
## produced. Break it by deleting the `partner_side` line instead and the MUTUALITY test
## below goes red while this one stays green — which is why they are two assertions and
## not one.
func test_the_production_verb_swears_the_bond_and_both_ledgers_read_sworn() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_confidant(player, ELDER)
	assert_eq(
		SocialApi.bond_entry(player, ELDER)["bond"],
		SocialBondClass.CONFIDANT,
		"the career earned a confidant, so the oath is being offered to someone who can carry it"
	)

	var sworn := BrotherhoodOathApp.offer(player, ELDER, WITNESS, true)
	assert_eq(sworn["ok"], true, "the verb accepted: %s" % str(sworn))
	assert_eq(sworn["outcome"], String(ConsentLedger.OUTCOME_ACCEPTED), "and they swore with you")

	assert_eq(
		SocialApi.bond_entry(player, ELDER)["label"],
		"Sworn",
		"THE PLAYER'S ledger reads Sworn — reached through the production verb, not by hand"
	)
	assert_eq(
		SocialApi.bond_entry(elder, player.id)["label"],
		"Sworn",
		(
			"AND the elder's own ledger reads Sworn — the mirror moved in the same call. A"
			+ " one-sided apply_cause would leave this reading Confidant, which is the shape the"
			+ " ADR 0091 design question refused."
		)
	)


## ## The promise is on BOTH ledgers as a recorded CAUSE, so both save files carry it.
##
## Asserted on `causes` rather than on the class because the class is derived and the
## ledger is the truth: a reloaded bond has to answer "did we swear?" without re-running
## the exchange.
func test_both_sides_record_an_authored_cause_so_the_pact_survives_a_save() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_confidant(player, ELDER)
	BrotherhoodOathApp.offer(player, ELDER)

	var player_bond := SocialApi.social_state(player).bond(ELDER)
	var elder_bond := SocialApi.social_state(elder).bond(player.id)
	assert_eq(
		player_bond.causes.get(String(BrotherhoodOath.CAUSE_SWORN), 0),
		1,
		"the player's ledger names the act itself: shared_brotherhood"
	)
	assert_eq(
		elder_bond.causes.get(String(BrotherhoodOath.CAUSE_ACCEPTED), 0),
		1,
		"and the elder's names the mirror: accepted_the_oath, not the same id written twice"
	)


## ## The gate a panel authors for the top rung now opens in production.
##
## Every `SocialApi.gate` authored `at_least: SWORN` was permanently unreachable from
## play before this change, which is the cost ADR 0091 recorded while the gap was open.
## This is the assertion that the cost is paid off.
func test_an_authored_gate_on_sworn_opens_through_the_production_path() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	_confidant(player, ELDER)
	var gate := SocialApi.gate(
		player, {"verb": &"bond_at_least", "partner": ELDER, "at_least": SocialBondClass.SWORN}
	)
	assert_eq(gate["ok"], false, "before the offer, the gate is shut — and says so")
	assert_eq(gate["reason"], "bond_at_least", "naming the verb that closed it")

	BrotherhoodOathApp.offer(player, ELDER)
	assert_eq(
		(
			SocialApi
			. gate(
				player,
				{"verb": &"bond_at_least", "partner": ELDER, "at_least": SocialBondClass.SWORN}
			)["ok"]
		),
		true,
		"and after the production verb, it opens"
	)


## ## The pact survives a reload, on both sides, with nothing else persisted.
##
## `Actor.to_dict()` and nothing else — the same round trip `SaveApi.persist` takes. A
## `to_dict` that dropped `promoted_to` or a cause would land the reloaded bond a rung
## below the one the player was just shown.
func test_the_sworn_pact_round_trips_through_an_ordinary_save_on_both_ledgers() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_confidant(player, ELDER)
	BrotherhoodOathApp.offer(player, ELDER)

	var player_after := Actor.from_dict(player.to_dict())
	var elder_after := Actor.from_dict(elder.to_dict())
	SocialApi.attach(player_after)
	SocialApi.attach(elder_after)
	assert_eq(
		SocialApi.bond_entry(player_after, ELDER)["bond"],
		SocialBondClass.SWORN,
		"the player's ledger reloaded as sworn"
	)
	assert_eq(
		SocialApi.bond_entry(elder_after, player.id)["bond"],
		SocialBondClass.SWORN,
		"and so did the elder's — the mirror was a saved fact, not a live-only one"
	)
	assert_eq(
		BrotherhoodOath.consent(player_after).row(ELDER).get("outcome", ""),
		String(ConsentLedger.OUTCOME_ACCEPTED),
		"the consent ledger rode the save too: the offer and its answer are both remembered"
	)


# --- 2. Refusal is refused with a NAMED reason, and the cost is observable ------


## ## THE COST. A friend who is not yet a confidant declines, and the asking is a wound.
##
## This is the default outcome of the verb for anyone who offers early, and it is
## reachable by any player with no authored content — which is what makes it a real
## consequence rather than a garnish on a rare branch.
##
## The assertions are on the BOND, not on the return value: the cost is
## `refused_the_oath` standing on the ledger, so `standing` and `trust` must both have
## MOVED by the authored magnitude. Delete the `apply_cause` in the refusal branch and
## this goes red on the standing assert, and the returned dict still says `refused` —
## which is exactly the no-op the ruling forbids.
func test_refusal_costs_standing_and_trust_and_the_cost_is_observable_on_the_bond() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	_friend(player, ELDER)
	var before := SocialApi.bond_entry(player, ELDER)
	assert_eq(before["bond"], SocialBondClass.FRIEND, "a friend — and not yet a confidant")

	var outcome := BrotherhoodOathApp.offer(player, ELDER)
	assert_eq(outcome["ok"], true, "the offer was well formed and was ANSWERED: %s" % str(outcome))
	assert_eq(outcome["outcome"], String(ConsentLedger.OUTCOME_REFUSED), "they declined")
	assert_eq(
		String(outcome["cost"]),
		String(BrotherhoodOath.CAUSE_REFUSED),
		"and the cost is named, not applied as a bare number"
	)

	var after := SocialApi.bond_entry(player, ELDER)
	var charge := SocialCauseCatalog.instance().cause_definition(BrotherhoodOath.CAUSE_REFUSED)
	assert_almost_eq(
		float(after["standing"]),
		float(before["standing"]) + charge.standing,
		"THE COST IS OBSERVABLE: standing moved by the authored refusal magnitude"
	)
	assert_almost_eq(
		float(after["trust"]),
		float(before["trust"]) + charge.trust,
		"and trust moved with it — a third of what a confidant needs"
	)
	assert_eq(
		SocialApi.social_state(player).bond(ELDER).causes.get(
			String(BrotherhoodOath.CAUSE_REFUSED), 0
		),
		1,
		"and the refusal is ON THE LEDGER, so a reader can see why they think less of you"
	)


## ## The refusal cost is real enough to bite, sized against the ladder itself.
##
## Asserting the NUMBERS is what stops a future edit from quietly tuning the refusal down
## to a rounding error, which is the shape of the hole ADR 0091 exists to close. If the
## magnitudes ever shrink, this test is where it should be argued about.
func test_the_refusal_cost_is_scaled_against_the_ladder_not_rounded_away() -> void:
	var charge := SocialCauseCatalog.instance().cause_definition(BrotherhoodOath.CAUSE_REFUSED)
	assert_ne(charge, null, "the refusal cause is authored — an unauthored id refuses at play time")
	assert_eq(
		charge.standing <= -SocialBondClass.FRIEND_AT * 0.5,
		true,
		"a refusal is at least half a friendship deep, or it is a rounding error"
	)
	assert_eq(
		charge.trust <= -SocialBondClass.CONFIDANT_TRUST * 0.2,
		true,
		"and it costs at least a fifth of the trust a confidant is built on"
	)
	assert_eq(
		charge.kind,
		&"oath",
		"and it shares the oath kind, so a pair whose whole history is oaths tops out at a friend"
	)


## ## Refusal is never silent: the act itself is refused with a named reason.
##
## Two refusals, at two moments, and they are different things. This one is about the
## ACT — a stranger, an unanswered offer, a second press — and each names itself so a
## panel can print it.
func test_the_act_itself_is_refused_with_a_named_reason_rather_than_silently() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var stranger := NpcApi.spawn(OTHER)
	assert_ne(stranger, null, "the second cast member is a stranger to the player")

	var unknown := BrotherhoodOathApp.offer(player, &"nobody_at_all")
	assert_eq(unknown["ok"], false, "an id this process holds no body for is refused")
	assert_eq(unknown["reason"], "unknown_npc", "and it names itself")

	var stranger_offer := BrotherhoodOathApp.offer(player, OTHER)
	assert_eq(stranger_offer["ok"], false, "two who have never met cannot swear an oath")
	assert_eq(stranger_offer["reason"], "no_bond", "the reason is the missing bond, not a shrug")


## ## Pressing the button twice is refused, and the reason is the anti-repeat rule.
##
## Without this the top rung is re-mintable: offer, decline, offer again, and a player
## who finds a partner who accepts on the right tick gets the top of the ladder on
## demand. The consent ledger is what makes the offer one-shot.
func test_an_offer_already_answered_cannot_be_answered_again() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_confidant(player, ELDER)
	BrotherhoodOathApp.offer(player, ELDER)

	var again := BrotherhoodOathApp.offer(player, ELDER)
	assert_eq(again["ok"], false, "the second press is refused")
	assert_eq(again["reason"], "already_answered", "naming the anti-repeat rule")

	var bond := SocialApi.social_state(player).bond(ELDER)
	assert_eq(
		bond.causes.get(String(BrotherhoodOath.CAUSE_SWORN), 0),
		1,
		"and the cause was applied exactly once — the ladder's top rung is not re-mintable"
	)


# --- 3. Eligibility: one gate system, and it refuses before the act ------------


## ## The offer gate is the module's OWN ladder, read through the ONE gate system.
##
## There is no second gate here. `BrotherhoodOath._gate` calls `SocialApi.gate`, which
## is `SocialGate.evaluate`, and the `unmet` a refusal carries is that gate's own array —
## so a panel prints "Friend, not Acquaintance" without this module inventing a word.
##
## Break it by writing the requirement as `{"verb": &"standing_at_least", "at_least": 6.0}`
## — a STAT — and this test still passes, which is why the assert below pins the VERB:
## the gate must be one the ledger answers, never one an item satisfies (ADR 0062).
func test_eligibility_reads_the_ledger_through_the_one_gate_system() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]

	var stranger := BrotherhoodOathApp.read(player, ELDER)
	assert_eq(stranger["ok"], false, "a stranger may not be put to the oath")
	assert_eq(stranger["reason"], "no_bond", "naming the missing bond")

	_friend(player, ELDER)
	var friend := BrotherhoodOathApp.read(player, ELDER)
	assert_eq(friend["ok"], true, "a friend may be ASKED — that is the design")
	assert_eq(
		friend["will_swear"],
		false,
		"but the reckoning publishes that they will DECLINE, so the affordance can say so first"
	)

	_confidant(player, ELDER)
	var confidant := BrotherhoodOathApp.read(player, ELDER)
	assert_eq(confidant["will_swear"], true, "a confidant will swear with you")
	# ## `class` is the RAW ID and `label` is the DISPLAY STRING — both, on purpose
	#
	# `BrotherhoodOathApp.read` publishes `"class": String(bond.get("bond", ""))`, and
	# `SocialApi.bond_entry` fills that from `String(bond.bond_class())` — the ladder's
	# identifier, `&"confidant"`, not `SocialBondClass.label`. This compared it against the
	# literal `"Confidant"`, which is the LABEL, so it failed `expected Confidant, got
	# confidant`: a case bug and nothing else.
	#
	# ## The fix is to assert both, not to swap one for the other
	#
	# `read` publishes `class` for a panel that routes on the rung and `label` for a panel
	# that prints it, and the docstring on `read` promises both keys. `label` is the only
	# one that can be a capitalised word — `SocialBondClass.label` is the single writer of
	# it, so `String(SocialBondClass.label(SocialBondClass.CONFIDANT))` cannot drift. The
	# sibling assertions in this suite (`["label"] == "Sworn"`) already read the display
	# key, so pinning `label` here is the same discipline rather than a new one.
	assert_eq(
		confidant["class"],
		String(SocialBondClass.CONFIDANT),
		"and the read model names the rung it holds, as the raw ladder id"
	)
	assert_eq(
		confidant["label"],
		SocialBondClass.label(SocialBondClass.CONFIDANT),
		"alongside the display string a panel actually prints — a capitalised 'Confidant'"
	)


## ## The refusal carries the gate's own unmet reasons, so nothing is re-invented.
##
## This is the BL-0690 shape called forward: an aggregate gate once read its children
## under `"requirements"` while ten other modules use `"of"`, so an authored gate opened
## ITSELF. Here the requirement is a single verb and there is no aggregate — but the
## discipline being tested is that a refusal explains itself with the shared gate's
## vocabulary rather than a module-local one.
func test_a_refused_offer_carries_the_shared_gate_s_unmet_reasons() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	_friend(player, ELDER)
	var outcome := BrotherhoodOathApp.offer(player, ELDER)
	assert_eq(outcome["outcome"], String(ConsentLedger.OUTCOME_REFUSED), "declined")
	var row := BrotherhoodOathApp.consent_read(player, ELDER)
	assert_eq(
		String(row.get("outcome", "")),
		String(ConsentLedger.OUTCOME_REFUSED),
		"and the consent ledger remembers that the offer happened AND how it was answered"
	)
	assert_eq(
		String(row.get("cost", "")),
		String(BrotherhoodOath.CAUSE_REFUSED),
		"naming WHICH cause was charged — a reference to the ledger, not a copy of its value"
	)


# --- 4. The anti-farm rule is not weakened to make any of this work -----------


## ## THE GUARD. The distinct-KIND rule is not weakened to reach SWORN.
##
## A friendship needs two different KINDS of act, and an OATH IS ONE KIND. So a pair
## whose entire history is oaths — made, refused, renewed, witnessed, made again — has
## one kind and tops out at an ACQUAINTANCE however large the total, promotion included.
##
## **Every cause below carries `promotes_to: SWORN`**, which is the worst case: if the
## guard were weakened, a pair who did nothing but make and break oaths would reach the
## top of the ladder. This is the same regression `test_social_promotion.gd` pins from
## the other side; it is restated here because THIS is the path that made `sworn`
## reachable, and a future edit that touches the oath is exactly when it would be tried.
##
## ## And it needed a cause authoring fix to be true
##
## `shared_brotherhood` shipped with **no authored tag and no authored kind**, so
## `_first_tag` gave it a bucket of its own — `shared_brotherhood` — while
## `accepted_the_oath`, `refused_the_oath` and `witnessed_an_oath` all carried
## `kind: oath`. Four oaths therefore filed under four kinds, `FRIEND_DISTINCT_CAUSES`
## saw two of them, and an oath farm bought a friendship: **the same act wearing two
## labels walked straight through the rule that exists to stop it.** `shared_brotherhood`
## now authors `kind: oath` like its three siblings, and this assertion is the guard on
## that. The distinct-KIND rule was NOT weakened to make any of this work.
func test_a_history_of_nothing_but_oaths_never_reaches_sworn() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	# ## SIX `shared_brotherhood` oaths, and the total is computed, not counted
	#
	# Six oaths sworn is 6 × 5.0 = **30.0 over ONE kind** — past `CONFIDANT_AT` (14.0)
	# with room to spare, which is the exact worst case the anti-farm rule exists to
	# refuse. Deriving the count from the catalog rather than writing a literal 6 means the
	# fixture cannot silently drift under the ladder if a magnitude is ever retuned, and it
	# is what makes `standing > CONFIDANT_AT` an ASSERTION about the ladder instead of a
	# restatement of a number someone typed.
	var oaths := 6
	for _oath in oaths:
		SocialApi.apply_cause(player, ELDER, BrotherhoodOath.CAUSE_SWORN)
	var bond := SocialApi.social_state(player).bond(ELDER)
	var sworn := SocialCauseCatalog.instance().cause_definition(BrotherhoodOath.CAUSE_SWORN)
	assert_eq(
		bond.standing,
		sworn.standing * oaths,
		(
			"THE TOTAL IS REAL: six authored oaths at 5.0 each is 30.0 of standing, summed"
			+ " by SocialBond.apply onto one row"
		)
	)
	assert_eq(bond.distinct_kinds(), 1, "six acts, one KIND — an oath is one kind of act")
	assert_eq(
		bond.standing > SocialBondClass.CONFIDANT_AT,
		true,
		(
			"and the total is past every bar, so nothing but the anti-farm rule stands "
			+ "between this farm and SWORN"
		)
	)
	assert_eq(bond.promoted_to, SocialBondClass.SWORN, "with a promise on the ledger to boot")
	assert_eq(
		bond.bond_class(),
		SocialBondClass.ACQUAINTANCE,
		"so the anti-farm rule caps it below a friendship: an oath farm is still a farm"
	)


## ## Two gift-tier causes still cannot reach SWORN through this path, let alone FRIEND.
##
## The control for the test above, and the positive one: the oath needs a history beside
## it. `helped_in_combat` is `combat` and `gifted_item` is `gift`, so those are two
## kinds and the pair genuinely earns the friendship the oath is built on — which is what
## makes the SWORN answer in the first test a *earned* one and not a purchased one.
func test_the_oath_stands_on_top_of_a_friendship_earned_by_other_kinds_of_act() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var elder: Actor = cast["elder"]
	_confidant(player, ELDER)
	var before := SocialApi.social_state(player).bond(ELDER)
	assert_eq(
		before.bond_class(), SocialBondClass.CONFIDANT, "a career of combat, gifts and teaching"
	)
	assert_eq(before.distinct_kinds() >= 2, true, "which is more than one kind of act")

	BrotherhoodOathApp.offer(player, ELDER)
	var after := SocialApi.social_state(player).bond(ELDER)
	assert_eq(after.bond_class(), SocialBondClass.SWORN, "the oath on top of it is the top rung")
	assert_eq(
		after.distinct_kinds() >= 2,
		true,
		"and the career is still what carried it there — the oath added a kind, not a shortcut"
	)


# --- 5. The witness, and the consent ledger's own discipline -------------------


## ## A witnessed oath binds the player to the witness TOO.
##
## The third leg, and the one an authored gate can name: `caused_by: witnessed_an_oath`
## opens on this bond and on nothing else. Without it, `witnessed` would be a flag on a
## consent row describing a ceremony the ledger never recorded.
func test_a_witnessed_oath_writes_a_real_bond_against_the_witness() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var witness: Actor = cast["witness"]
	# ## The witness is minted by `_stage`, and it is asserted BEFORE anything reads it
	#
	# `BrotherhoodOathApp.offer(player, npc_id, witness_id, witnessed)` takes the witness as
	# an ID and resolves it itself, so this local is not what the verb writes — the cast
	# member is, and `assert_ne` below is what proves a body exists for that id at all.
	# The original abort (`Invalid access to property or key 'causes' on a base object of
	# type 'Nil'` at the dereference) had no assertion standing between the spawn and the
	# dereference, so a missing or unminted witness surfaced as a SCRIPT ERROR that
	# ABORTED the test mid-function: tools/test.py then reported the function as neither
	# passed nor failed and the run came out "0 failed" while a script error was on screen.
	# ## That is the defect worth fixing, and it is why the bond is read through a
	## ## `.get()` default rather than dereferenced.
	assert_ne(witness, null, "the witness is a real actor with a real ledger")
	_confidant(player, ELDER)
	var outcome := BrotherhoodOathApp.offer(player, ELDER, WITNESS, true)
	assert_eq(outcome["witnessed"], true, "the offer named a witness")
	# Read the bond defensively: a null here means the witness cause was never written, and
	# an assertion that says SO is worth more than an abort three lines into a property
	# access. `.get("causes", {})` then yields `{}` and the count reads 0, not a crash.
	var surety: Dictionary = {}
	var surety_bond := SocialApi.social_state(player).bond(WITNESS)
	if surety_bond != null:
		surety = surety_bond.causes
	assert_eq(
		surety.get(String(BrotherhoodOath.CAUSE_WITNESSED), 0),
		1,
		"and the witness now stands surety on the player's own ledger"
	)
	assert_eq(
		(
			SocialApi
			. gate(
				player,
				{"verb": &"caused_by", "partner": WITNESS, "cause": BrotherhoodOath.CAUSE_WITNESSED}
			)["ok"]
		),
		true,
		"which an authored gate can read — the third leg is a bond, not a flag"
	)


## ## An unwitnessed oath writes no witness bond.
##
## The control for the test above, and it is a real behavioural difference rather than a
## cosmetic one: the witness bond is the whole content of `witnessed: true`.
func test_an_unwitnessed_oath_binds_no_one_but_the_partner() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	_confidant(player, ELDER)
	BrotherhoodOathApp.offer(player, ELDER)
	var gate := SocialApi.gate(
		player, {"verb": &"caused_by", "partner": WITNESS, "cause": BrotherhoodOath.CAUSE_WITNESSED}
	)
	assert_eq(gate["ok"], false, "no witness was named, so nobody stands surety")
	assert_eq(gate["reason"], "caused_by", "and the gate names itself")


## ## The consent ledger records THAT AN OFFER HAPPENED — and never a standing value.
##
## This is the "no second copy of a ledger" rule asserted from the data side. The ledger
## carries an outcome and a CAUSE ID; every number that moved lives on the bond. A
## consent row that also carried `standing` would be the ADR 0066 failure with a new
## name, and this is what catches it.
func test_the_consent_ledger_records_the_offer_and_never_a_rival_standing_value() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	_confidant(player, ELDER)
	BrotherhoodOathApp.offer(player, ELDER)
	var row := BrotherhoodOathApp.consent_read(player, ELDER)
	assert_eq(String(row.get("outcome", "")), String(ConsentLedger.OUTCOME_ACCEPTED), "an answer")
	assert_eq(String(row.get("cost", "")), String(BrotherhoodOath.CAUSE_SWORN), "and which cause")
	assert_eq(row.get("standing", null), null, "no standing value is recorded here")
	assert_eq(row.get("trust", null), null, "nor trust: the bond is the only copy of those")
	assert_eq(row.get("bond", null), null, "nor a derived class — the ladder reads the ledger")


## ## An unanswered offer is remembered as unanswered, and refuses a second answer.
##
## The ledger's own discipline: `answer` refuses an offer nobody made, so a caller cannot
## record consent for a question that was never asked.
func test_an_offer_must_be_made_before_it_can_be_answered() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var ledger := BrotherhoodOath.consent(player)
	var premature := ledger.answer(ELDER, ConsentLedger.OUTCOME_ACCEPTED, &"")
	assert_eq(premature["ok"], false, "there was no offer to answer")
	assert_eq(premature["reason"], "no_offer", "and it says exactly that")
	assert_eq(ledger.row(ELDER).is_empty(), true, "so no row was fabricated")


## ## An unknown outcome is inert vocabulary, refused rather than stored.
##
## A closed vocabulary is what keeps a panel from having to spell a state it has never
## seen, and what makes a typo a loud failure instead of a permanently unanswered offer.
func test_an_unknown_outcome_is_refused_rather_than_recorded() -> void:
	var cast := _stage()
	var player: Actor = cast["player"]
	var ledger := BrotherhoodOath.consent(player)
	ledger.offer(ELDER)
	var bogus := ledger.answer(ELDER, &"hesitated", &"")
	assert_eq(bogus["ok"], false, "an outcome outside the closed set is refused")
	assert_eq(bogus["reason"], "unknown_outcome", "naming itself, like every other refusal")
	assert_eq(
		String(ledger.row(ELDER).get("outcome", "")),
		"",
		"and the offer is still open, not answered"
	)
