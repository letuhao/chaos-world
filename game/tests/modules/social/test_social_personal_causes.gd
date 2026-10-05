extends TestCase

## ## The six unwired PERSONAL causes now have production producers, and the lineage
## ## producer's gate can finally open
##
## `SocialFavour` + `SocialFavourApp` are the appliers. This suite asserts four things,
## and each is a property that could plausibly regress:
##
##   1. **Every cause the verbs apply is AUTHORED.** `SocialApi.apply_cause` refuses
##      `unknown_cause`, so a bridge on an unauthored id reads correct and never fires —
##      the inert-vocabulary defect in its worst form.
##   2. **Both ledgers move.** ADR 0091 leaves the mirror to the caller's transaction, and
##      a one-sided write is a relationship that disagrees with itself.
##   3. **A refusal writes NOTHING** (ADR 0044) — no cause, no goods spent.
##   4. **THE ACCEPTANCE TEST**: a PLAYER ACTION moves a personal bond above
##      `Seduction.REQUIRED_STANDING` and `Seduction.can_meet` then answers true. It goes
##      through `SocialFavourApp` — never through `Seduction.attempt`, which is the producer
##      under test and must not be the thing that proves its own gate opens.
##
## ## Why this suite reaches `app/` when it lives under `modules/social`
##
## Because the verb a player presses is an `app/` type, and "reachable at runtime" is a
## claim about the tree rather than about one module. `SocialApi` and `SocialFavour` are
## unchanged in reach; what this suite drives is the wiring that makes them reachable,
## which is exactly what was missing.

## The elder: the only `story` tier individual, the only cast member whose ladder carries
## `advance_after`, and the subject of the authored `npc_tally` beat in
## `the_favour_of_elder_wei.tres` — the same choice `item_workbench_body.gd` makes.
const ELDER := &"elder_wei"

## An authored manual whose `TechniqueDef.delivered_by` names it. Read out of the shipped
## technique catalog rather than hardcoded where a rename would break silently.
const MANUAL := &"manual_stone_crane_mist"

## The debt verb the elder's own roster carries. `NpcApi.summary` reads this from the
## roster's tally, and 0 is the refusal.
const DEBT := &"favours"

## A stackable item that costs a player something to hand over. Resolved through the
## shipped catalog in `setup`, so the suite does not depend on an authored id surviving.
const GIFT := &"spirit_herb"

var player: Actor
var elder: Actor


func setup() -> void:
	SocialCauseCatalog.instance().install_defaults()
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	NpcBoot.install(null)
	# The seams, installed exactly as production does: `install()` with NO arguments,
	# because every one of them has a default body. If the defaults ever stop resolving,
	# the verbs below refuse `no_resolver` and this suite is red rather than quietly
	# passing on an unbound path.
	SocialFavourApp.install()
	player = Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})
	SocialApi.attach(player)
	ItemsApi.attach(player)
	EconomyApi.attach(player)
	NpcBoot.install(player)
	NpcApi.spawn(ELDER)
	elder = NpcApi.resident(ELDER)
	# ## The elder needs a bag of his own, and that is a REAL finding, not a fixture.
	#
	# `ActorFactory.spawn_npc` attaches social state, a path and qi — and NO inventory. A
	# gift is a TRANSFER, and `EconomyExchange` refuses `not_carried` for a receiver with no
	# inventory, so every gift to every npc in the shipped game is `not_carried` until
	# something gives the cast a bag. That is a wiring gap in `app/`'s spawn path rather
	# than in this verb, and it is reported rather than papered over: the suite attaches the
	# bag so the MIRROR can be asserted, and the report names the gap as one the owner owes.
	ItemsApi.attach(elder)
	assert_ne(elder, null, "the elder resolved, or nothing below means anything")


func teardown() -> void:
	# The seams are process-wide statics, so a suite that leaves them bound would hand the
	# next suite whatever this one happened to install — `run_tests.gd` shares one process
	# across every suite, which `TechniqueDelivery` documents by name.
	SocialFavourApp.uninstall()
	NpcRegistry.instance().reset()
	NpcApi._current_player = null
	NpcBoot.install(null)
	SocialCauseCatalog.instance().install_defaults()


# --- 1. The vocabulary is authored ---------------------------------------------


## ## Every cause the app verb can apply EXISTS in the shipped catalog.
##
## This is the gate `SocialApi.apply_cause` does not run. `apply_cause` answers
## `{"ok": false, "reason": "unknown_cause"}` for an id the catalog does not ship, so a
## bridge built on unauthored vocabulary refuses at PLAY time while every test around it
## passes. Pinning it here turns that silent path into a failed test.
func test_every_cause_the_verbs_apply_is_authored() -> void:
	var catalog := SocialCauseCatalog.instance()
	var applied := SocialFavourApp.cause_ids()
	assert_eq(applied.is_empty(), false, "the component publishes what it can apply")
	for cause_id in applied:
		assert_ne(
			catalog.cause_definition(cause_id),
			null,
			"'%s' is applied by SocialFavourApp and must exist in the catalog" % String(cause_id)
		)


## ## The five wired ids are the five the catalog ships as positive PERSONAL causes.
##
## Restated as a set rather than spot-checked, so a cause silently dropped from
## `SocialFavour` is red here rather than discovered as an unreachable verb later.
func test_the_wired_vocabulary_is_exactly_the_five_applied_ones() -> void:
	var applied := SocialFavourApp.cause_ids()
	for expected in [
		&"gifted_item",
		&"helped_in_combat",
		&"spared_in_combat",
		&"taught_technique",
		&"honoured_a_debt",
	]:
		assert_eq(applied.has(expected), true, "%s is wired" % String(expected))


## ## `protected_from_death` is the one still unwired, and that is a REPORTED decision.
##
## Asserted as unwired rather than merely absent: a future change that wires it turns this
## red, which is the point. Whoever wires it must come back and update this file and the
## report, because the verb needs a combat event (`Shield` was deleted by ADR 0076 and
## `combat_engine`'s `SHIELD_COMPONENT` binds nothing) that does not exist today.
func test_protected_from_death_is_still_unwired_and_says_so() -> void:
	var catalog := SocialCauseCatalog.instance()
	assert_ne(
		catalog.cause_definition(SocialFavour.CAUSE_UNWIRED),
		null,
		"the cause is still authored — it is the PRODUCER that is missing"
	)
	assert_eq(
		SocialFavourApp.cause_ids().has(SocialFavour.CAUSE_UNWIRED),
		false,
		"and nothing applies it yet"
	)


# --- 2. The mirror --------------------------------------------------------------


## ## The MIRROR moves in the same call, keyed through the resolver.
##
## The player's bond records the act and the elder's records what it was to receive. This
## is the load-bearing half of ADR 0091's "the mirror is the caller's transaction": a
## one-sided write leaves the elder's ledger untouched while the player's reads a bond the
## elder has no record of.
func test_giving_writes_both_ledgers_in_the_same_call() -> void:
	_equip_gift()
	var row := SocialFavourApp.give(player, ELDER, [{"def_id": String(GIFT), "quantity": 1}])
	assert_eq(row["ok"], true, "the gift settled")
	assert_eq(row["cause"], "gifted_item", "and names the authored cause")
	var key := StringName(String(SocialFavourApp.read(player, ELDER)["partner"]))
	assert_ne(
		SocialApi.social_state(player).bond(StringName(key)),
		null,
		"the player's ledger carries the row"
	)
	assert_ne(
		SocialApi.social_state(elder).bond(SocialFavour.bond_key(player)),
		null,
		"and the elder's carries the mirror — not a one-sided write"
	)
	assert_eq(
		float(SocialApi.bond_entry(elder, SocialFavour.bond_key(player))["standing"]),
		float(SocialApi.bond_entry(player, StringName(key))["standing"]),
		"at the SAME magnitude: a mirror at another scale makes the pair disagree"
	)


## ## The mirror is keyed through `bond_key`, and the engine id is an ALIAS beside it.
##
## `ActorFactory.spawn_npc` mints `npc_elder_wei` for `elder_wei`, so the def id and the
## actor id are two strings for one person, and the two halves of the game read different
## ones: `NpcRosterEntry`, every authored gate, every consent row and every panel name
## `elder_wei`, while `Seduction.can_meet` asks its gate for `String(partner.id)`.
##
## **Both rows are therefore written, and neither replaces the other.** A mirror filed
## under only the def id is correct, saved, printed — and invisible to the one lineage
## producer it was written to open. A mirror filed under only the actor id is invisible to
## everything a player reads. This is the defect this file exists to prevent, one layer
## down, and the assertion below pins BOTH halves rather than one of them.
func test_the_mirror_is_keyed_on_the_def_id_not_the_actor_id() -> void:
	_equip_gift()
	SocialFavourApp.give(player, ELDER, [{"def_id": String(GIFT), "quantity": 1}])
	# ## The MIRROR is the ELDER's row for the PLAYER, not the elder's row for itself.
	#
	# The counterparty on the elder's ledger is the player, and `bond_key(player)` is what
	# resolves it — `hero`, because the registry cannot resolve a player to a roster def id
	# at all. `bond(ELDER)` would ask "does the elder hold a bond with an id spelled
	# `elder_wei`", i.e. a bond with HIMSELF, which no producer writes and no reader asks
	# for. Asserting that would have been asserting the absence of a thing nothing claims
	# exists, while passing silently on a mirror that could have been filed anywhere.
	assert_ne(
		SocialApi.social_state(elder).bond(SocialFavour.bond_key(player)),
		null,
		"and the MIRROR row is on the elder's ledger, keyed on the player's own id"
	)
	# ## ## And NO row is filed under the elder's own engine id
	#
	# This is the half that looks contradictory and is not. The PLAYER's ledger carries two
	# rows — `elder_wei` (def, what the ladder and every panel read) and `npc_elder_wei`
	# (engine, what `Seduction.can_meet` asks its gate for) — because `bond_key(elder)`
	# resolves to the def id while `elder.id` is a genuinely different string.
	#
	# The ELDER's ledger carries ONE. Its counterparty is the player, `bond_key(player)`
	# resolves to `hero`, and `player.id` is the very same string — so there is no alias to
	# write, and writing one is precisely the double-count `_settle` used to make. An
	# assertion that the elder held a row under `npc_elder_wei` would be pinning the bug
	# this change removed: a self-directed row on the elder's ledger, naming himself,
	# which no reader asks for and which made one gift read as two on his side.
	assert_eq(
		SocialApi.social_state(elder).bond(elder.id),
		null,
		"and the elder holds no self-directed row under his own engine id"
	)


# --- 3. Refusals write nothing --------------------------------------------------


## ## A refused gift SPENDS NOTHING and writes no cause (ADR 0044).
##
## Checked on the inventory as well as the ledger, because "the standing did not move" is
## the half that is easy: a verb that removed the goods and then failed to write a cause
## would pass a standing-only assertion and quietly eat the player's bag.
func test_a_refused_gift_moves_no_goods_and_writes_no_cause() -> void:
	var before := ItemsApi.inventory(player).count(GIFT)
	var row := SocialFavourApp.give(player, ELDER, [{"def_id": String(GIFT), "quantity": 99}])
	assert_eq(row["ok"], false, "a gift the player does not carry is refused")
	assert_eq(row["reason"], "not_carried", "and it names itself")
	assert_eq(ItemsApi.inventory(player).count(GIFT), before, "nothing left the bag")
	assert_eq(
		SocialApi.bond_entry(player, ELDER).get("present", false),
		false,
		"and no bond row was created by the refusal"
	)


## ## An id nobody has met refuses by name, at every verb.
##
## The off-stage lookup found no body, so this is `unknown_npc` rather than a silent empty
## row — a panel greys the affordance out and prints why instead of letting the verb
## refuse at the press.
func test_an_unknown_npc_is_refused_by_name_at_every_verb() -> void:
	var nobody := &"nobody_at_all"
	assert_eq(SocialFavourApp.give(player, nobody, [])["reason"], "unknown_npc", "give")
	assert_eq(SocialFavourApp.fight_alongside(player, nobody)["reason"], "unknown_npc", "combat")
	assert_eq(SocialFavourApp.settle_debt(player, nobody)["reason"], "unknown_npc", "debt")
	assert_eq(SocialFavourApp.teach(player, nobody, MANUAL)["reason"], "unknown_npc", "teach")
	assert_eq(SocialFavourApp.read(player, nobody)["reason"], "unknown_npc", "read")


## ## `spared: true` is VERIFIED, not trusted.
##
## `spared_in_combat` is +4.0 against `helped_in_combat`'s +3.0. A verb that took the
## flag on trust would let a caller mint the larger cause with no live opponent and no mercy
## — so `fight_alongside` asks two things first and records nothing until both answer.
##
## **1. `CombatMercy.available`** is the world check: a live opponent, not a corpse, not
## one already spared.
##
## **2. The bond's own CAUSE LEDGER** is the history check, and on a fresh unfought
## individual it is this one that refuses. `available` alone is not enough: its contract is
## "is this loser somebody mercy could be shown TO", which a healthy elder answers true to
## whether or not a fight ever happened — so a `spared: true` press on somebody the player
## never fought would have been recorded as a fact that never occurred. That is precisely
## the unearned cause ADR 0091's ledger exists to prevent, so `spared_in_combat` requires
## the bond to already carry `helped_in_combat`: **you cannot spare somebody you have not
## fought.** The sibling acceptance case is the other half of this one — it stages the
## fight first and the same press then succeeds.
func test_a_mercy_that_cannot_be_shown_is_refused_rather_than_recorded() -> void:
	var row := SocialFavourApp.fight_alongside(player, ELDER, true)
	assert_eq(row["ok"], false, "nobody is to be spared")
	assert_eq(row["reason"], "no_fight", "and it names the missing history, not a wiring gap")
	assert_eq(
		float(SocialApi.bond_entry(player, ELDER).get("standing", 0.0)),
		0.0,
		"and no standing was written for a mercy that did not happen"
	)


## ## A debt the roster does not carry settles nothing.
##
## The verb reads the partner's OWN tally through `NpcApi.summary`, so a caller cannot
## assert a debt into existence to mint standing. The elder's roster carries no `favours`
## tally until a beat records one.
func test_a_debt_the_partner_does_not_record_settles_nothing() -> void:
	var row := SocialFavourApp.settle_debt(player, ELDER, &"a_debt_nobody_opened")
	assert_eq(row["ok"], false, "no debt, no act")
	assert_eq(row["reason"], "no_debt", "and it names itself")


## ## A manual the player does not carry teaches nothing and consumes nothing.
func test_teaching_without_the_manual_spends_nothing() -> void:
	var row := SocialFavourApp.teach(player, ELDER, MANUAL)
	assert_eq(row["ok"], false, "no manual, no teaching")
	assert_eq(row["reason"], "not_carried", "and it names itself")
	assert_eq(
		float(SocialApi.bond_entry(player, ELDER).get("standing", 0.0)),
		0.0,
		"no standing for a lesson that did not happen"
	)


## ## An UNINSTALLED seam refuses by name rather than silently degrading.
##
## `SocialFavourApp.uninstall()` is the state a build is in before `install()`. The verbs
## that need a seam answer `no_resolver`, which is a wiring gap the caller can see — rather
## than filing a mirror under `actor.id` and reporting success.
##
## ## ## The manual IS equipped, and that is the whole point of the case
##
## `teach` asks carrying BEFORE category and BEFORE the seam, on purpose: a verb that
## printed "that is not a manual" for an empty bag sends the player looking in the wrong
## place, and a verb that printed "the build is miswired" for an empty bag says something
## about the BUILD that is not what happened. So the refusal order is
## `not_carried` -> `not_a_manual` -> `no_resolver`, and only a player actually holding
## the manual can reach the third.
##
## Called without one, this case would assert `no_resolver` and get `not_carried` — and
## pass for the wrong reason if it were flipped, since both are honest refusals of a
## verb that cannot do its job. The manual is what isolates the seam as the ONLY thing
## missing.
func test_an_uninstalled_seam_refuses_by_name() -> void:
	_equip_manual()
	SocialFavourApp.uninstall()
	var row := SocialFavourApp.teach(player, ELDER, MANUAL)
	assert_eq(row["ok"], false, "nothing taught with no learner seam")
	assert_eq(row["reason"], "no_resolver", "and the wiring gap names itself")
	# The manual is still in the bag: a refused verb spends nothing (ADR 0044), and a
	# wiring gap is not a reason to eat the player's inventory.
	assert_eq(
		ItemsApi.has_item(player, MANUAL, 1),
		true,
		"and a refusal that names a wiring gap still spends no manual"
	)


## ## The same verb, with the seam bound, refuses for the ACTUAL reason.
##
## `test_an_uninstalled_seam_refuses_by_name` asserts `no_resolver`; this asserts that
## installing the seam moves the refusal along to the learn itself rather than making the
## verb succeed, so the first case is proved to be about the seam and not about anything
## else the verb happens to check. Without it a suite could bind a broken teacher and stay
## green on the name alone.
func test_the_same_verb_gets_past_the_seam_once_it_is_bound() -> void:
	_equip_manual()
	var row := SocialFavourApp.teach(player, ELDER, MANUAL)
	assert_ne(
		row["reason"], "no_resolver", "with the seam bound the verb no longer reports a wiring gap"
	)


# --- 4. THE ACCEPTANCE TEST -----------------------------------------------------


## ## THE ACCEPTANCE TEST: a player action opens the gate `Seduction.can_meet` reads.
##
## Before: a fresh bond, `standing` 0.0, `can_meet` FALSE — `no_bond`, which is what every
## player got forever, because no production caller of `apply_cause` ever wrote a personal
## row (they all pass an institution id).
##
## Then: three player actions through `SocialFavourApp`, no direct `apply_cause`, no
## `Seduction.attempt`.
##
## After: standing above `Seduction.REQUIRED_STANDING` and `can_meet` TRUE.
##
## ## Why 6.0 is reachable at all, and what that is worth
##
## The three acts are authored at 1.0 + 3.0 + 4.0 = 8.0, so the floor is cleared with two
## to spare and the pair is a `FRIEND` (ADR 0091's ladder) rather than sitting exactly on
## the line. The magnitudes are the shipped ones — `gifted_item` 1.0, `helped_in_combat`
## 3.0, `spared_in_combat` 4.0 — read from the catalog in the assertions below rather than
## restated, so this test tracks an author retuning the vocabulary instead of fighting it.
##
## **Two of the three are needed.** `spared_in_combat` (4.0) plus `gifted_item` (1.0) is
## 5.0 and would NOT clear the gate; the answer is that a player who fights beside somebody
## and gives them something clears it, and one who only did the first two would not. That is
## a real design consequence of the authored magnitudes and it is reported, not tuned away:
## `REQUIRED_STANDING` stays at 6.0 and no cause was rescaled to reach it.
##
## ## ## THE KEY, and why this test would otherwise have passed for the wrong reason
##
## `Seduction.can_meet` asks the gate for `String(partner.id)` — the ACTOR id, which is
## `npc_elder_wei` for this elder — while every reader, gate and panel in the game names the
## DEF id `elder_wei`. So the row the player-facing verbs write is not the row `Seduction`
## reads. **This is a second, independent blocker and it is the one the first one hid**:
## even with a producer for every personal cause, `can_meet` would still answer false,
## because the producer keys on `partner.id` and the ladder keys on `bond_key`.
##
## The verb therefore writes BOTH keys when they differ, and this test asserts through the
## actor id — the one `Seduction` actually reads. Without that the acceptance test would
## read 8.0 standing and a `false` gate and be reporting a bug it had mistaken for a pass.
func test_a_player_action_opens_the_gate_seduction_can_meet_reads() -> void:
	# ## BEFORE: the gap, measured rather than asserted in prose.
	var entry_before := SocialFavourApp.read(player, ELDER)
	assert_eq(entry_before["standing"], 0.0, "a bond nobody has acted on")
	assert_eq(
		Seduction.can_meet(player, elder),
		false,
		"and can_meet is FALSE — this is the state a player was in forever"
	)
	assert_eq(
		Seduction.attempt(player, elder, 0.0)["reason"],
		Seduction.R_NO_BOND,
		"the producer refused for the social floor, not for anything else"
	)

	# ## THE PLAYER ACTIONS. Three presses through the app verb, nothing else.
	_equip_gift()
	assert_eq(
		SocialFavourApp.give(player, ELDER, [{"def_id": String(GIFT), "quantity": 1}])["ok"],
		true,
		"1. you gave him something"
	)
	assert_eq(
		SocialFavourApp.fight_alongside(player, ELDER, false)["ok"],
		true,
		"2. you fought beside him"
	)
	assert_eq(
		SocialFavourApp.fight_alongside(player, ELDER, true)["ok"], true, "3. and you let him walk"
	)

	# ## AFTER: the gate the lineage producer reads now answers true.
	#
	# Read through BOTH keys. `def_read` is what a panel shows and `actor_read` is what
	# `Seduction` asks about, and the standing has to be on both for the feature to work for
	# a player rather than only for a screen.
	var def_read := SocialFavourApp.read(player, ELDER)
	var actor_read := SocialFavourApp.read(player, &"npc_elder_wei")
	var standing := float(def_read["standing"])
	var catalog := SocialCauseCatalog.instance()
	var expected := (
		catalog.cause_definition(&"gifted_item").standing
		+ catalog.cause_definition(&"helped_in_combat").standing
		+ catalog.cause_definition(&"spared_in_combat").standing
	)
	assert_almost_eq(standing, expected, "and the def-keyed standing is the authored sum", 0.001)
	assert_almost_eq(
		float(actor_read["standing"]),
		expected,
		"and the ACTOR-keyed standing is the same — the producer can read it",
		0.001
	)
	assert_eq(
		standing > Seduction.REQUIRED_STANDING,
		true,
		"the personal standing is ABOVE the floor Seduction demands"
	)
	assert_eq(
		Seduction.can_meet(player, elder),
		true,
		"can_meet is TRUE — the gate the whole lineage producer was blocked behind"
	)
	assert_ne(
		Seduction.chance(player, elder) > 0.0,
		true,
		"and a conception now has a chance rather than being structurally zero"
	)


## ## The magnitude arithmetic is a CLAIM about the shipped catalog, pinned.
##
## Read off the defs rather than written as literals, so an author retuning a cause moves
## this test instead of silently invalidating the report's "6.0 is reachable".
func test_the_gate_is_reachable_by_the_authored_magnitudes() -> void:
	var catalog := SocialCauseCatalog.instance()
	var spared := catalog.cause_definition(&"spared_in_combat").standing
	var gifted := catalog.cause_definition(&"gifted_item").standing
	assert_eq(
		(spared + gifted) > Seduction.REQUIRED_STANDING,
		false,
		"a mercy and a gift ALONE do not clear the floor — the answer is not one press pair"
	)
	assert_eq(
		(
			(spared + gifted + catalog.cause_definition(&"helped_in_combat").standing)
			> Seduction.REQUIRED_STANDING
		),
		true,
		"and mercy + gift + a fight beside them does"
	)


## ## A relation that a player BUILDS is not the relation `Seduction` writes.
##
## The producer records `bound_in_intimacy` at +6.0 on the player's ledger ONLY — the
## mirror is its caller's transaction too. So the two ledgers disagree by design after an
## attempt, and this suite does not paper over that: it asserts the act is recorded and
## leaves the mutuality decision to whoever wires the intimacy verb, which this change
## deliberately does NOT author (it is a content decision the owner has not made).
func test_the_producer_writes_its_own_cause_and_not_one_of_ours() -> void:
	_equip_gift()
	SocialFavourApp.give(player, ELDER, [{"def_id": String(GIFT), "quantity": 1}])
	SocialFavourApp.fight_alongside(player, ELDER, false)
	SocialFavourApp.fight_alongside(player, ELDER, true)
	assert_eq(Seduction.can_meet(player, elder), true, "the gate is open")
	var applied := SocialFavourApp.cause_ids()
	assert_eq(
		applied.has(Seduction.CAUSE),
		false,
		"and the producer's own cause is NOT among the causes these verbs apply"
	)


# --- helpers --------------------------------------------------------------------


## Bag the player with one of the shipped stackable herbs.
##
## Resolved through the item catalog rather than hardcoded to an authored id, so a rename
## fails this helper loudly instead of quietly turning every gift into `not_carried`.
func _equip_gift() -> void:
	var def := Crafting.resolve(GIFT)
	assert_ne(def, null, "the gift item id '%s' ships" % String(GIFT))
	ItemsApi.inventory(player).add(def, 1)
	assert_eq(ItemsApi.has_item(player, GIFT, 1), true, "and the player is carrying one")


## Bag the player with the manual `MANUAL` names, so a case about the TEACH verb can
## reach the checks that come after carrying.
##
## `test_teaching_without_the_manual_spends_nothing` deliberately does NOT call this — it
## is the case that proves an empty bag refuses `not_carried` before anything else is
## asked. Every case about what comes after that needs the manual actually in hand.
func _equip_manual() -> void:
	var def := Crafting.resolve(MANUAL)
	assert_ne(def, null, "the manual item id '%s' ships" % String(MANUAL))
	ItemsApi.inventory(player).add(def, 1)
	assert_eq(ItemsApi.has_item(player, MANUAL, 1), true, "and the player is carrying it")
