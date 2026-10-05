extends "res://tests/ui/custody_surface_fixture.gd"

## ## This file holds the SLICE half of the custody surface
##
## A player takes a subject the page was handed, captures it, hands the claim on for an
## agreed settlement, and ends it -- and the ledger and BOTH purses say so afterwards. The
## refusals the screen raises itself are asserted here by name, through the same `{ok, reason}`
## shape the modules use.
##
## ## ## The PRODUCER section, and why it drives the real callable
##
## Everything else here stages a beat by hand, which is what those cases are FOR -- they test
## `capture`, `transfer`, `settle_term` and `release`. The section under "the producer
## (ADR 0247)" does NOT, and that asymmetry is the point: it binds `Callable(NpcApi,
## "capturable")` -- the exact callable `item_workbench_app._bind_route_screen` installs --
## and reads a subject off the page's own published list. A hand-staged beat is a fixture
## agreeing with itself, which is precisely how DEF-0310's dead button stayed green.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every original body below is verbatim, and every constant, the
## `setup()` / `teardown()` pair and the helper it uses live in
## `custody_surface_fixture.gd`, which this file `extends`.
##
## The screen-contract, panel-format and shipped-source half is
## `test_custody_surface_contract.gd`.

# --- the slice, end to end ----------------------------------------------------

## THE claim of this file. A player stages a subject, captures it, hands the claim

## on for an agreed settlement, and ends it — and **the ledger and both purses say so

## afterwards**.

##

## Each beat is asserted against the LEDGER rather than against the screen's own

## summary, so a screen that rendered a row and wrote nothing could not pass.


func test_a_player_captures_a_claim_and_the_ledger_names_the_holder() -> void:
	var screen := _bound()

	assert_eq(
		int(CustodyApi.summary(_held[0])["claim_count"]), 0, "setup: the ledger holds no claim"
	)

	# Beat one: TAKE the subject. ADR 0104 leaves the CONDITION in the caller, so the

	# caller stages the beat and the screen forwards it.

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	assert_eq(
		String(screen.summary()["staged_capture"]["subject_id"]),
		String(SUBJECT),
		"and the screen publishes what a press WOULD commit, before it commits it"
	)

	assert_eq(
		bool(screen.summary()["enabled"]["capture"]),
		true,
		"so the capture control is live on a staged beat with a term"
	)

	var captured := screen.act_capture()

	assert_eq(bool(captured["ok"]), true, "the claim opens: %s" % captured["reason"])

	assert_ne(String(captured["claim_id"]), "", "and the facade names it")

	# Read the LEDGER, not the screen.

	var ledger := CustodyApi.summary(_held[0])

	assert_eq(int(ledger["claim_count"]), 1, "the ledger holds one claim")

	assert_eq(int(ledger["held_count"]), 1, "and it is held, not merely present")

	var claim: Dictionary = (ledger["claims"] as Dictionary)[String(captured["claim_id"])]

	assert_eq(String(claim["subject_id"]), String(SUBJECT), "naming the subject def id")

	assert_eq(String(claim["holder"]["id"]), String(_held[0].id), "held by this hero")

	assert_eq(int(claim["periods"]), 4, "on the term the caller staged")

	screen.free()


## The subject is HELD, which is the fact `subject()` reports on: the facade mints a

## live `Actor` from the claim's def id and writes nothing.


func test_the_subject_is_minted_from_its_def_id_and_the_ledger_is_untouched() -> void:
	var screen := _bound()

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	var captured := screen.act_capture()

	var claim_id := String(captured["claim_id"])

	screen.select_claim(claim_id)

	var before := CustodyApi.state(_held[0])

	assert_eq(screen.subject_wired(), true, "the composition root installed a constructor")

	var subject := screen.act_subject()

	assert_ne(subject, null, "so the picked claim's subject is a live body")

	assert_ne(String(subject.id), "", "with an id of its own")

	assert_eq(
		CustodyApi.state(_held[0]),
		before,
		"and minting it wrote NO row: the body is borrowed, never stored (ADR 0104)"
	)

	screen.free()


## `subject()` is null for a claim nobody can name, for a RELEASED one, and for an

## unwired constructor — three different sentences, and the third is reported by its

## own accessor rather than folded into one null.


func test_subject_is_null_for_an_unknown_claim_and_for_a_released_one() -> void:
	var screen := _bound()

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	var captured := screen.act_capture()

	var claim_id := String(captured["claim_id"])

	assert_eq(CustodyApi.subject(StringName("custody_nobody_ever_held#0")), null, "unknown claim")

	screen.select_claim(claim_id)

	assert_ne(screen.act_subject(), null, "a held claim's subject stands up")

	screen.act_release()

	# Minting a released subject's body would put a free prisoner back on the map.

	assert_eq(CustodyApi.subject(StringName(claim_id)), null, "a RELEASED claim mints nobody")

	# And the third sentence: no constructor at all is not the same as no claim.

	CustodyApi.set_minter(Callable())

	assert_eq(screen.subject_wired(), false, "an unwired constructor reports itself")

	assert_eq(screen.act_subject(), null, "and mints nothing, rather than half a body")

	screen.free()


## THE transfer case, and the one this file is most careful about.

##

## ## ## Both purses are asserted, and one alone is not enough

##

## The payer alone cannot prove MOVEMENT: a settlement that debited the payer and

## credited nobody would satisfy a payer-only assertion, and this program shipped

## exactly that once. So the receiver's purse is asserted too — the coins left one

## purse and arrived in the other, and neither half alone says that.


func test_a_transfer_moves_the_holder_and_the_coins_into_both_purses() -> void:
	var warden := _held[0]

	var buyer := _actor(&"buyer", 100)

	_held.append(buyer)

	var screen := _bound()

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	var captured := screen.act_capture()

	var claim_id := String(captured["claim_id"])

	var warden_before := EconomyApi.purse(warden)

	var buyer_before := EconomyApi.purse(buyer)

	assert_eq(buyer_before, 100, "setup: the buyer can pay")

	screen.select_claim(claim_id)

	screen.stage_transfer(_owner(&"buyer"), 20, buyer, warden)

	var staged := screen.summary()["staged_transfer"] as Dictionary

	assert_eq(String(staged["to_id"]), "buyer", "and the screen publishes the agreed target")

	assert_eq(int(staged["coins"]), 20, "and the agreed settlement")

	assert_eq(
		bool(screen.summary()["enabled"]["transfer"]),
		true,
		"so the transfer control is live on a claim this hero holds"
	)

	var moved := screen.act_transfer()

	assert_eq(bool(moved["ok"]), true, "the transfer settles: %s" % moved["reason"])

	assert_eq(int(moved["coins"]), 20, "and reports the figure that actually moved")

	# THE HOLDER, read off the ledger.

	var claim: Dictionary = (CustodyApi.summary(warden)["claims"] as Dictionary)[claim_id]

	assert_eq(String(claim["holder"]["id"]), "buyer", "the claim changed hands")

	assert_eq(String(claim["holder"]["kind"]), "actor", "to a real holder kind")

	# BOTH PURSES. The payer's side, and the receiver's — one without the other is

	# satisfiable by a settlement that simply took the money.

	assert_eq(EconomyApi.purse(buyer), buyer_before - 20, "the payer lost exactly the agreed sum")

	assert_eq(
		EconomyApi.purse(warden),
		warden_before + 20,
		"and the receiver gained it: the coins moved, they did not merely disappear"
	)

	screen.free()


## ADR 0104's ordering rule, asserted from the PLAYER's side: the coin leg runs first,

## so a settlement nobody can pay writes nothing — not the claim, and not either purse.


func test_an_unpayable_settlement_writes_nothing_and_names_the_failure() -> void:
	var warden := _held[0]

	var broke := _actor(&"broke", 1)

	_held.append(broke)

	var screen := _bound()

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	var captured := screen.act_capture()

	var claim_id := String(captured["claim_id"])

	screen.select_claim(claim_id)

	var warden_before := EconomyApi.purse(warden)

	var broke_before := EconomyApi.purse(broke)

	screen.stage_transfer(_owner(&"broke"), 500, broke, warden)

	var refused := screen.act_transfer()

	assert_eq(bool(refused["ok"]), false, "an unpayable settlement refuses")

	assert_eq(
		String(refused["reason"]),
		CustodyApi.COIN_LEG_FAILED,
		"and names the module's OWN failure, passed through verbatim"
	)

	assert_eq(
		String(screen.summary()["refusal_reason"]),
		CustodyApi.COIN_LEG_FAILED,
		"and the summary publishes that id a panel switches on"
	)

	var claim: Dictionary = (CustodyApi.summary(warden)["claims"] as Dictionary)[claim_id]

	assert_eq(String(claim["holder"]["id"]), String(warden.id), "the claim did not move")

	assert_eq(EconomyApi.purse(warden), warden_before, "the receiver got nothing")

	assert_eq(EconomyApi.purse(broke), broke_before, "and the payer lost nothing either")

	screen.free()


## Release is a HOLDER verb, always permitted, and never free: the claim STAYS in the

## ledger, reads released, and its holder is VACANT rather than empty — the distinction

## ADR 0083 makes between "no claim" and "a claim with no holder".


func test_a_release_ends_the_holding_and_leaves_the_history_readable() -> void:
	var screen := _bound()

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 7)

	var captured := screen.act_capture()

	var claim_id := String(captured["claim_id"])

	screen.select_claim(claim_id)

	assert_eq(
		bool(screen.summary()["enabled"]["release"]),
		true,
		"the release control is live for a holder"
	)

	var released := screen.act_release()

	assert_eq(bool(released["ok"]), true, "the holder may release: %s" % released["reason"])

	assert_eq(int(released["periods_left"]), 7, "and the term is NOT forgiven")

	var claim: Dictionary = (CustodyApi.summary(_held[0])["claims"] as Dictionary)[claim_id]

	assert_eq(String(claim["status"]), "released", "the claim reads as released")

	assert_eq(bool(claim["holder"].get("vacant", false)), true, "and its holder is VACANT")

	assert_ne(claim["holder"].is_empty(), true, "never an empty ref: the claim still exists")

	var after := screen.summary()

	assert_eq(int(after["released_count"]), 1, "the page counts the released claim")

	assert_eq(int(after["held_count"]), 0, "and not a held one")

	assert_eq(
		bool(after["enabled"]["release"]),
		false,
		"so release goes dead on a claim nobody holds, rather than live and refusing"
	)

	screen.free()


## A claim held by an INSTITUTION is visible here and not actionable here: a sect may

## hold a claim no press on this page took, so a claim the player can SEE is not

## automatically a claim the player can release. Asserted from the button state AND

## the verb, against the module's own id.


func test_a_claims_you_can_see_but_do_not_hold_cannot_be_released_here() -> void:
	var clerk := _actor(&"clerk")

	_held.append(clerk)

	var taken := CustodyApi.capture(clerk, SUBJECT, &"npc", _owner(SECT, &"sect"), TERM, 4)

	assert_eq(bool(taken["ok"]), true, "setup: a sect holds a claim: %s" % taken.get("reason", ""))

	var screen := _bound()

	var claim_id := String(taken["claim_id"])

	screen.select_claim(claim_id)

	var picked := screen.summary()

	assert_eq(String(picked["selected_holder_kind"]), "sect", "the row reports the institution")

	assert_eq(bool(picked["selected_held"]), true, "and reports the claim as held")

	assert_eq(
		bool(picked["selected_mine"]),
		false,
		"but NOT as this hero's: an institution is not the player"
	)

	assert_eq(
		bool(picked["enabled"]["release"]),
		false,
		"so the release control is dead on it, rather than live and refusing"
	)

	var refused := screen.act_release()

	assert_eq(bool(refused["ok"]), false, "and the hero cannot release it")

	assert_eq(
		String(refused["reason"]),
		CustodyApi.HOLDER_MISMATCH,
		"and the refusal names the module's OWN rule"
	)

	var claim: Dictionary = (CustodyApi.summary(clerk)["claims"] as Dictionary)[claim_id]

	assert_eq(
		String(claim["holder"]["id"]),
		String(SECT),
		"and the ledger still names the sect: a refused verb wrote nothing"
	)

	screen.free()


## A hand-off with no coin leg is LEGAL and must not be forced to invent one. `coins ==

## 0` skips the exchange entirely (ADR 0104), so the holder changes and neither purse

## moves — the pair of facts that together say "this was a hand-off, not a sale".


func test_a_hand_off_with_no_settlement_moves_the_holder_and_neither_purse() -> void:
	var warden := _held[0]

	var buyer := _actor(&"buyer", 100)

	_held.append(buyer)

	var screen := _bound()

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	var captured := screen.act_capture()

	var claim_id := String(captured["claim_id"])

	var warden_before := EconomyApi.purse(warden)

	var buyer_before := EconomyApi.purse(buyer)

	screen.select_claim(claim_id)

	screen.stage_transfer(_owner(&"buyer"), 0, buyer, warden)

	var moved := screen.act_transfer()

	assert_eq(bool(moved["ok"]), true, "a hand-off settles: %s" % moved["reason"])

	assert_eq(int(moved["coins"]), 0, "and moved no coins")

	var claim: Dictionary = (CustodyApi.summary(warden)["claims"] as Dictionary)[claim_id]

	assert_eq(String(claim["holder"]["id"]), "buyer", "the claim changed hands")

	assert_eq(EconomyApi.purse(buyer), buyer_before, "the payer's purse is untouched")

	assert_eq(EconomyApi.purse(warden), warden_before, "and so is the receiver's")

	screen.free()


## Settling a term is all-or-nothing, and the button is the authored single period —

## so the page states the step rather than inventing a tick (DEF-0111).


func test_settling_the_term_is_all_or_nothing_from_the_screen_too() -> void:
	var screen := _bound()

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	var captured := screen.act_capture()

	var claim_id := String(captured["claim_id"])

	screen.select_claim(claim_id)

	var partial := screen.act_settle(2)

	assert_eq(bool(partial["ok"]), true, "a partial settlement succeeds: %s" % partial["reason"])

	assert_eq(int(partial["periods_left"]), 2, "and leaves the remainder")

	var over := screen.act_settle(9)

	assert_eq(bool(over["ok"]), false, "settling more than is owed refuses")

	assert_eq(String(over["reason"]), CustodyApi.TERM_EXCEEDS, "and names the rule")

	var claims := CustodyApi.summary(_held[0])["claims"] as Dictionary

	assert_eq(
		int((claims[claim_id] as Dictionary).get("periods", -1)),
		2,
		"and the refusal settled NOTHING"
	)

	# The button's own step, asserted rather than assumed: one period a press. Read

	# through the SCREEN's published summary, so the key the page chose is itself under

	# test — `settled` is the module's own name for what was paid down, and a page that

	# republished it as `periods` would make a settlement read as an opening.

	var button := screen.act_settle()

	assert_eq(
		int(screen.summary()["last_settled"]),
		1,
		"one press of the settle button pays down one period, published as `settled`"
	)

	assert_eq(int(button["periods_left"]), 1, "and leaves exactly that much owed")

	screen.free()


# --- the producer (ADR 0247) --------------------------------------------------


## ## THE PRODUCER CASE, and the one that answers DEF-0310
##
## DEF-0310: `stage_capture` had no production caller, `_capture_subject` was never set, the
## capture control was permanently disabled, and every other case in this file stayed green.
## So this body deliberately uses **no fixture callable and no typed id**: it binds the REAL
## producer callable the composition root installs (`Callable(NpcApi, "capturable")`), reads
## the first subject off the page's OWN published list, and presses `Accept`.
##
## A fixture seam would prove a fixture agrees with itself — exactly the class of test that let
## a page whose primary verb could never fire survive an audit. This one fails the moment the
## producer is removed, whether that means `NpcApi.capturable` answering nothing, the cast
## authoring no capture term, or the root not installing the seam.
func test_the_page_takes_a_subject_from_the_producer_and_the_ledger_says_so() -> void:
	# The production read path for the cast: `NpcBoot.install` calls exactly this, so a
	# suite must not depend on some other suite having walked the tree first.
	NpcCatalog.instance().load_authored()
	var screen := _bound()
	screen.bind_capture_options(Callable(NpcApi, "capturable"))

	var listed := screen.summary()
	assert_eq(
		bool(listed["capture_options_wired"]), true, "the producer seam is bound at the route"
	)
	assert_ne(
		int(listed["available_count"]),
		0,
		"and the cast authors at least one capturable, so the page has something to offer"
	)
	# Nothing typed: the id comes off the page's own list, which is what a player reads.
	var offered := screen.takeable_subject_ids()
	assert_ne(offered.is_empty(), true, "and at least one of them is not already held")

	var subject := String(offered[0])
	assert_eq(
		screen.select_capture_subject(subject),
		true,
		"picking an offered subject arms the capture beat, and nothing typed an id"
	)
	var staged := screen.summary()["staged_capture"] as Dictionary
	assert_eq(String(staged["subject_id"]), subject, "and the beat names the subject offered")
	assert_ne(
		String(staged["term_id"]), "", "on an AUTHORED term, not a default this page invented"
	)
	assert_ne(int(staged["periods"]), 0, "and on an authored count of periods")
	assert_eq(
		bool(screen.summary()["enabled"]["capture"]),
		true,
		"so the capture control is live -- the button DEF-0310 found permanently dead"
	)

	# Press it the way a player does: `Accept` on the page, not a direct verb call.
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	assert_eq(screen.on_stack_input(accept), true, "Accept is consumed, because it took something")

	# And the LEDGER, not the screen, is what says the claim exists.
	var ledger := CustodyApi.summary(_held[0])
	assert_eq(int(ledger["claim_count"]), 1, "the ledger holds one claim")
	var claim: Dictionary = (ledger["claims"] as Dictionary)[String(screen.summary()["last_claim"])]
	assert_eq(String(claim["subject_id"]), subject, "naming the subject the page was handed")
	assert_eq(String(claim["status"]), "held", "and it is held, not merely present")
	assert_eq(
		int(claim["periods"]),
		int(staged["periods"]),
		"for the authored count of periods, never one this page computed"
	)
	screen.free()


## ## The converse, and it is the mutation half of the pair
##
## With nothing bound the page has no cause and therefore offers nothing: `available_count` is
## zero, the control is dead, and a press refuses `no_subject` by name rather than grabbing the
## first row. So **deleting the producer is observable in the summary**, which is what makes the
## case above a test of the wiring rather than of a hard-coded expectation.
func test_with_no_producer_bound_the_page_offers_nothing_and_says_which() -> void:
	var screen := _bound()
	var listed := screen.summary()
	assert_eq(bool(listed["capture_options_wired"]), false, "no seam: the page was told nothing")
	assert_eq(int(listed["available_count"]), 0, "so there is nothing capturable here")
	assert_eq(bool(listed["enabled"]["capture"]), false, "and the control is dead rather than live")
	var pressed := screen.act_capture()
	assert_eq(bool(pressed["ok"]), false, "a press refuses")
	assert_eq(String(pressed["reason"]), "no_subject", "by the screen's own id, not a guess")
	assert_eq(
		int(CustodyApi.summary(_held[0])["claim_count"]), 0, "and wrote nothing: no cause, no claim"
	)
	screen.free()


## Unbinding the seam WITHDRAWS the arming rather than leaving a stale subject staged for a
## control nobody can see the cause of -- the same rule `stage_capture("")` follows on purpose,
## and the reason the cache is emptied rather than kept.
func test_unbinding_the_producer_withdraws_the_arming_it_published() -> void:
	NpcCatalog.instance().load_authored()
	var screen := _bound()
	screen.bind_capture_options(Callable(NpcApi, "capturable"))
	assert_ne(int(screen.summary()["available_count"]), 0, "the cast offers something")

	screen.bind_capture_options(Callable())
	assert_eq(bool(screen.capture_options_wired()), false, "the seam is gone")
	assert_eq(
		int(screen.summary()["available_count"]),
		0,
		"and the page publishes nothing rather than a stale subject it can no longer justify"
	)
	screen.free()


# --- the refusals the screen raises ITSELF -----------------------------------

## Every refusal this screen authors itself is a NAMED id, published through the same

## `{ok, reason}` shape the modules use — so one renderer covers both and a probe never

## has to read a sentence.


func test_the_screens_own_refusals_are_named_and_write_nothing() -> void:
	# Nothing staged: the capture beat has no subject, and ADR 0104 puts the condition

	# in the caller, so an unstaged press must not invent one.

	var screen := _bound()

	var unstaged := screen.act_capture()

	assert_eq(bool(unstaged["ok"]), false, "an unstaged capture refuses")

	assert_eq(String(unstaged["reason"]), "no_subject", "and names the missing subject")

	assert_eq(
		int(CustodyApi.summary(_held[0])["claim_count"]),
		0,
		"and opened nothing: nothing was attempted"
	)

	# A staged beat with no term: the module's rule, refused on the same path.

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 0)

	var termless := screen.act_capture()

	assert_eq(String(termless["reason"]), CustodyApi.NO_PERIODS, "a termless beat refuses")

	assert_eq(int(CustodyApi.summary(_held[0])["claim_count"]), 0, "and still nothing written")

	# Nothing picked: each verb refuses by name rather than acting on the first row.

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	screen.act_capture()

	for verb in ["act_release", "act_settle"]:
		var refused: Dictionary = screen.call(verb) as Dictionary

		assert_eq(bool(refused["ok"]), false, "%s with nothing picked refuses" % verb)

		assert_eq(String(refused["reason"]), "no_claim_picked", "and says which input was missing")

	# A transfer with no target holder: an invented holder is a claim handed to

	# somebody nobody agreed to.

	screen.clear_transfer()

	var claim_id := String(screen.claim_ids()[0])

	screen.select_claim(claim_id)

	var untargeted := screen.act_transfer()

	assert_eq(bool(untargeted["ok"]), false, "a transfer with no target refuses")

	assert_eq(
		String(untargeted["reason"]),
		"no_transfer_target",
		"and declines rather than guessing a holder"
	)

	var claim: Dictionary = (CustodyApi.summary(_held[0])["claims"] as Dictionary)[claim_id]

	assert_eq(
		String(claim["holder"]["id"]),
		String(_held[0].id),
		"and the claim is byte-identical to before"
	)

	# A negative settlement is a refusal about the FIGURE; zero is a legal hand-off.

	screen.stage_transfer(_owner(&"buyer"), -5, _held[0], _held[0])

	assert_eq(
		String(screen.act_transfer()["reason"]),
		"no_coins",
		"a negative settlement refuses, while zero would have been legal"
	)

	screen.free()


## One subject may be held once. A second claim on the same subject would leave two

## holders and no way to say which counts, so the second capture refuses by the

## module's own id and writes nothing.


func test_one_subject_may_be_held_once_and_the_second_capture_names_the_rule() -> void:
	var screen := _bound()

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	assert_eq(bool(screen.act_capture()["ok"]), true, "the first claim opens")

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)

	var second := screen.act_capture()

	assert_eq(bool(second["ok"]), false, "a second claim on one subject refuses")

	assert_eq(
		String(second["reason"]), CustodyApi.ALREADY_CAPTIVE, "and names the module's OWN rule"
	)

	assert_eq(
		int(CustodyApi.summary(_held[0])["claim_count"]),
		1,
		"and the ledger still holds exactly one claim"
	)

	screen.free()


## `holder == subject` cannot be written at all: it is a record with no exit, since

## transfer refuses a self-transfer and release refuses a non-holder. The subject here

## is this hero's OWN id, which the facade compares on ids alone.


func test_a_hero_cannot_hold_a_claim_on_themself() -> void:
	var screen := _bound()

	var taken := CustodyApi.capture(
		_held[0], StringName(String(_held[0].id)), &"npc", _owner(_held[0].id), TERM, 4
	)

	assert_eq(bool(taken["ok"]), false, "self-hold refuses at capture, so it cannot be written")

	assert_eq(String(taken["reason"]), CustodyApi.SELF_HOLD, "and names the rule")

	assert_eq(int(CustodyApi.summary(_held[0])["claim_count"]), 0, "and nothing was written")

	screen.free()
