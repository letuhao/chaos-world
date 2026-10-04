extends TestCase

## The custody surface, end to end: a player opens a claim, hands it on for an agreed
## settlement, and ends it — with the ledger and BOTH purses asserting the outcome.
##
## ## What this suite is FOR
##
## The audit that found `HoldingsApi.claim` with no production caller found
## `CustodyApi.capture` with none either. A captive was therefore a ledger row: the
## brief asked that captured actors and mobs be reachable, ADR 0094 refused a captive
## as a tradeable thing, and ADR 0104 answered "a custody CLAIM" — and nothing a
## player can press opened, moved or ended one, while every custody suite stayed green.
## So these cases drive the screen the way a player does and assert the OUTCOME in the
## ledger.
##
## ## ## Both purses, on the transfer, and why
##
## The transfer case asserts the payer's purse AND the receiver's. One side alone
## cannot prove MOVEMENT — a bug this program shipped once, where a settlement debited
## the payer and credited nobody. A assertion that only watched the payer's figure
## would pass on exactly that bug. Two sides is the whole claim: the coins left one
## purse and arrived in the other, which is what "moved" means.
##
## ## ## Every refusal is a named constant
##
## A test asserting only `ok == false` would pass for a screen that refused
## everything. Each refusal is asserted BY NAME, because the name is the contract a
## panel switches on and this screen publishes it verbatim.
##
## ## ## Nothing leaks
##
## `CustodyApi._store`, `CustodyApi._resolver` and `CustodyApi._minter` are
## process-wide and the runner shares ONE process across every suite, calling
## `teardown` after EVERY test. Each is released per-test, not per-suite. And
## `setup` installs a FRESH `CustodyWorldLedger` — see the note there: `subject`
## reads its claim through `_state(null)`, which reaches the SHARED store, so a
## durable ledger left by an earlier suite would leak its claims into this one.

const SCREEN_SCENE := preload("res://src/ui/screens/custody_screen.tscn")
const ROW_SCENE := preload("res://src/ui/panels/custody_claim_row.tscn")
const SCRIPT_PATH := "res://src/ui/screens/custody_screen.gd"
const PANEL_SCRIPT_PATH := "res://src/ui/panels/custody_claim_row.gd"
const ROUTES_PATH := "res://src/app/screen_routes.gd"
const ROUTE := &"custody"

## A REAL authored `NpcDef` under `game/data/npc/cast`, so `EconomyBoot`'s minter
## resolves it and `subject()` mints a body rather than a null. A claim about a subject
## this build does not ship is a fixture that agrees with itself.
const SUBJECT := &"smith_bearcutter"
const SECOND_SUBJECT := &"drifter"
## The numéraire `CustodyApi.transfer` settles through — named here only as the item a
## purse is asked about; the SCREEN never names it, and `test_the_screen_names_one_facade
## _and_nothing_else` asserts that.
const COIN := &"curr_spirit_coin"
const TERM := &"custody"
## An institution holder, so the `sect` arm of the closed `OwnerRef.KINDS` set has a
## case the screen can read but cannot act on. `OwnerResolver` refuses an id no sect
## catalog carries, so this must be authored.
const SECT := &"iron_vine"

var _held: Array[Actor] = []


func setup() -> void:
	# ## ## A floor, because this file's first run proved why it needs one
	#
	# A body that dies mid-way records neither a pass nor a failure, so a suite with no
	# declared floor reports `0 failed` having skipped its own proof — and the version of
	# this file that first ran green did exactly that: `act_settle`'s chained index
	# aborted on one test, the abort printed only a `SCRIPT ERROR` on stderr, and the
	# tally read clean. `expect_assertions(2)` is the lowest floor every body in this
	# file clears by a wide margin, so an abort is charged rather than skipped. See
	# `tests/framework.gd:expect_assertions` for why a FLOOR and not an exact count.
	expect_assertions(2)
	# A REAL resolver and a REAL minter, because the claim refuses `no_resolver`
	# without a resolver and `subject()` returns null with no minter — a suite that
	# installed neither would be measuring the seam rather than the slice.
	# `EconomyBoot.install` is the production installer and it is idempotent, so
	# using it here is the same wiring a boot performs.
	EconomyBoot.install(null)
	_held.clear()
	_held.append(_actor(&"custody_warden"))
	EconomyBoot.install(_held[0])
	# **Then** a FRESH world ledger, and this is not belt-and-braces. `EconomyBoot
	# ._store_for` asks `SaveApi.store_for("custody")` first and falls back to an
	# in-memory `CustodyWorldLedger` only when nothing has registered one — and a
	# suite that registered a DURABLE store earlier in the same process left its
	# ledger ON DISK. The runner shares one process across every suite, so under
	# `--suite ui` that disk holds another suite's claims: `CustodyApi._state` reads
	# them through `read_ledger`, and a subject this file needs vacant arrives held,
	# so `act_capture` comes back `already_captive` and this suite measures somebody
	# else's ledger. `CustodyWorldLedger.new()` is the same isolation
	# `tests/modules/custody/test_custody_claim.gd` uses, and it is a SHARED world
	# ledger on purpose — the new holder must see the claim the old holder opened, or
	# the transfer cases below would pass against a per-actor ledger that can never
	# disagree with itself.
	CustodyApi.set_store(CustodyWorldLedger.new())


func teardown() -> void:
	for actor in _held:
		if actor != null:
			actor = null
	_held.clear()
	CustodyApi.set_minter(Callable())
	CustodyApi.set_resolver(Callable())
	CustodyApi.set_store(null)


## A hero with everything a custody verb needs: an inventory to hold a purse, the
## economy ledger `trade` writes, and the custody ledger the claim names.
func _actor(id: StringName, coins: int = 0) -> Actor:
	var actor := Actor.new(id, {})
	ItemsApi.attach(actor, 24)
	if coins > 0:
		ItemsApi.inventory(actor).add(Crafting.resolve(COIN), coins)
	EconomyApi.attach(actor)
	CustodyApi.attach(actor)
	return actor


func _owner(id: StringName, kind: StringName = &"actor") -> Dictionary:
	return {"kind": String(kind), "id": String(id)}


## A fresh, unbound screen. Every case frees what it is handed, because the runner
## shares one process across every suite and a screen left alive holds its whole row
## pool.
func _screen() -> CustodyScreen:
	return (SCREEN_SCENE as PackedScene).instantiate() as CustodyScreen


## A screen bound to the hero. **No seam is bound**, deliberately: this screen takes
## none, so a test that bound one would be testing a door that does not exist.
func _bound() -> CustodyScreen:
	var screen := _screen()
	screen.setup(_held[0])
	return screen


## The claim `screen` is showing for `subject_id`, or `{}`.
func _row_for(screen: CustodyScreen, subject_id: String) -> Dictionary:
	for row in screen.summary()["rows"] as Array:
		if String((row as Dictionary).get("subject_id", "")) == subject_id:
			return row as Dictionary
	return {}


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


# --- the screen contract -----------------------------------------------------


## `{}` with no actor, so a screen that reported keys would make ADR 0083's first state
## unreadable rather than merely empty.
##
## ## The floor of TWO is why this has a second assertion
##
## This body was one assertion long on its first run, and the suite's declared floor
## caught it — an aborted body records neither a pass nor a failure, so a one-assertion
## test can die half way and report green. So the second claim here is the one that
## matters most: **staging is not state.** A screen that reported its own staged beat as
## part of `summary()` would render a page whose whole content is a claim nobody has
## taken yet, and every probe would read that as a real world.
func test_the_screen_summary_is_empty_without_an_actor() -> void:
	var screen := _screen()
	assert_eq(screen.summary(), {}, "empty with no actor, not a half-built view")
	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 2)
	assert_eq(
		screen.summary(),
		{},
		"and still empty with a beat staged: staging is the CALLER's input, never state"
	)
	screen.free()


## Every claim in the ledger is a row, and NONE is truncated. The pool grows through
## `RowBudget.cap`, so a cap low enough to bite would silently drop a claim off the end
## — and the count is asserted against the LEDGER rather than against the pool.
func test_every_claim_is_listed_rather_than_truncated() -> void:
	var screen := _bound()
	var held := int(CustodyApi.summary(_held[0])["claim_count"])
	# Two distinct subjects, so the board is more than one row and the sort has to order
	# them rather than falling out of a one-element list.
	var others: Array[String] = []
	for subject in [SECOND_SUBJECT]:
		var holder := _actor(StringName("holder_%s" % String(subject)))
		_held.append(holder)
		var taken := CustodyApi.capture(holder, subject, &"npc", _owner(holder.id), TERM, 2)
		assert_eq(bool(taken["ok"]), true, "setup: a second claim opens")
		others.append(String(taken["claim_id"]))
	screen.refresh()
	# The shared ledger means this hero's page shows EVERY claim, whoever opened it —
	# which is ADR 0101's whole answer for a world fact.
	assert_eq(
		int(screen.summary()["claim_count"]),
		held + others.size(),
		"the page lists every claim in the ledger, not a per-actor subset"
	)
	assert_eq(
		screen.claim_ids().size(),
		screen.summary()["claim_count"],
		"the pickable list and the reported count agree, so no row was truncated"
	)
	screen.free()


## The pick walks the SHOWN list and is declined on an empty one — which is what keeps
## `ui_cancel` free by association.
func test_the_pick_walks_the_shown_list_and_accept_releases_what_this_hero_holds() -> void:
	var screen := _bound()
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	assert_eq(screen.on_stack_input(down), false, "down on an empty board is declined")
	assert_eq(screen.on_stack_input(null), false, "and a null event is too")

	screen.stage_capture(String(SUBJECT), "npc", String(TERM), 4)
	var captured := screen.act_capture()
	assert_eq(screen.on_stack_input(down), true, "down picks the first claim")
	assert_eq(
		String(screen.summary()["selected_claim"]),
		String(captured["claim_id"]),
		"and it is the one that was just opened"
	)

	# `ui_accept` fires the verb the pick's own state makes primary — release, for a
	# claim THIS hero holds.
	var accept := InputEventAction.new()
	accept.action = &"ui_accept"
	accept.pressed = true
	assert_eq(screen.on_stack_input(accept), true, "accept is consumed, because it did something")
	assert_eq(
		String(screen.summary()["last_reason"]),
		"",
		"and what it did was the release, which succeeds"
	)
	var claim: Dictionary = (CustodyApi.summary(_held[0])["claims"] as Dictionary)[String(
		captured["claim_id"]
	)]
	assert_eq(String(claim["status"]), "released", "so the claim reads released")
	screen.free()


## The four `ScreenStack` hooks exist and are safe with nothing bound, and `ui_cancel`
## is DECLINED so the stack pops exactly as it pops every other screen. A screen that
## swallowed cancel would trap the player on a page with four verbs.
func test_the_stack_hooks_exist_and_cancel_is_left_to_the_stack() -> void:
	var screen := _screen()
	for hook in [&"on_screen_shown", &"on_screen_hidden", &"focus_initial", &"on_stack_input"]:
		assert_eq(screen.has_method(hook), true, "%s is implemented" % hook)
	screen.on_screen_shown()
	screen.on_screen_hidden()
	screen.focus_initial()
	assert_eq(screen.summary(), {}, "still empty, so a focus call did not invent state")

	screen.setup(_held[0])
	assert_eq(screen.on_stack_input(null), false, "a null event is declined")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	assert_eq(screen.on_stack_input(cancel), false, "cancel is declined so the stack pops")
	var right := InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	assert_eq(screen.on_stack_input(right), false, "and so is everything else")
	screen.free()


## `{}` is the row's FIRST state: a spare row in the pool that no claim occupies is not
## the same thing as a claim that was released, and a collapsed row would throw the
## distinction away.
func test_the_row_keeps_a_released_claim_apart_from_a_spare_pool_row() -> void:
	var row := (ROW_SCENE as PackedScene).instantiate() as CustodyClaimRow
	assert_eq(row.summary(), {}, "a spare pool row reports nothing at all")
	assert_eq(row.is_filled(), false, "and is not filled")

	(
		row
		. show_claim(
			{
				"claim_id": "custody_drifter#0",
				"subject_id": "drifter",
				"subject_kind": "npc",
				"holder": {"kind": "actor", "id": "warden"},
				"term_id": "custody",
				"periods": 3,
				"opened_period": 12,
				"status": "held",
			}
		)
	)
	assert_eq(row.is_filled(), true, "an authored claim fills it")
	assert_eq(row.is_held(), true, "and is held")
	assert_eq(row.is_vacant(), false, "with a holder, so not vacant")

	(
		row
		. show_claim(
			{
				"claim_id": "custody_drifter#0",
				"subject_id": "drifter",
				"subject_kind": "npc",
				"holder": {"vacant": true},
				"term_id": "custody",
				"periods": 3,
				"opened_period": 12,
				"status": "released",
			}
		)
	)
	assert_eq(row.is_released(), true, "a released claim says so")
	assert_eq(row.is_vacant(), true, "and its holder is vacant, not absent")
	assert_eq(row.is_filled(), true, "and the row is STILL filled: the claim exists")
	assert_ne(
		String(row.summary()["card_tone"]),
		"ClaimCard",
		"on a different card, so the two never read alike"
	)

	row.clear()
	assert_eq(row.summary(), {}, "and clearing empties it again, rather than blanks")
	row.free()


# --- the panel owns every format ---------------------------------------------


## AGENTS.md: "no number formatting in a screen — the panel owns `%d/%d`, decimals and
## widths." So the row's rendered term line carries the figures and the SCREEN's summary
## carries them raw.
func test_the_row_panel_prints_the_figures_and_the_screen_formats_none() -> void:
	var row := (ROW_SCENE as PackedScene).instantiate() as CustodyClaimRow
	(
		row
		. show_claim(
			{
				"claim_id": "custody_drifter#0",
				"subject_id": "drifter",
				"subject_kind": "npc",
				"holder": {"kind": "sect", "id": "iron_vine"},
				"term_id": "custody",
				"periods": 6,
				"opened_period": 12,
				"status": "held",
			}
		)
	)
	var shown := row.summary()
	var term := String(shown["term_line"])
	# `str`, not `String(int)`: Godot 4.7 has no `String` constructor taking an int,
	# and the figure has to be the one the row printed, so it is rendered the same way.
	assert_ne(
		term.find(str(int(shown["periods"]))),
		-1,
		"the row prints the periods, which the record authored rather than the screen"
	)
	assert_ne(term.find("6"), -1, "and the authored six specifically")
	assert_ne(
		term.find(String(shown["term_id"])),
		-1,
		"and the term id, so a player reads what they are owed before pressing"
	)
	assert_ne(
		String(shown["holder_line"]).find("iron_vine"),
		-1,
		"and the holder's id, which is the only name on this row"
	)
	row.free()


# --- the boundaries, read off the SHIPPED source ------------------------------


## ## ## ADR 0104's load-bearing rule, machine-checked
##
## "A custody record has NO `description`, no `flavor`, and no `display_name`… prose in
## a save schema is how prose becomes what gets read." The FACADE already asserts this
## for the record; this is the half that was open — that the SURFACE does not grow a
## prose field either. A row that printed the subject's name beside the def id would be
## a second copy of it in the one place that has no authorization to author it, and no
## facade assertion could see that.
##
## Read as CODE, for the reason the scan in `test_forage_surface` gives: both files
## DOCUMENT the fields they are barred from, in the very sentences that forbid them, so
## a raw text scan would assert the comment and fail on the boundary it was written to
## prove.
func test_the_screen_invents_no_prose_field_over_the_custody_record() -> void:
	for path in [SCRIPT_PATH, PANEL_SCRIPT_PATH]:
		var code := _code_only(path)
		for forbidden in ['"description"', '"flavor"', '"display_name"', '"note"', '"note_"']:
			assert_eq(
				code.contains(forbidden),
				false,
				(
					"%s authors a prose field the ADR 0104 record does not carry: %s"
					% [path.get_file(), forbidden]
				)
			)
	# And the CONVERSE, which is the half a prohibition cannot state on its own: the
	# subject is named by its DEF ID and by nothing else. The row reads
	# `subject_id` and falls back to a constant of its own, so a name field could only
	# arrive as an id the row resolved — and `npc` is not in `UI_MODULES`, so there is
	# no catalog for this row to have resolved one through.
	assert_eq(
		_code_only(PANEL_SCRIPT_PATH).contains("subject_id"),
		true,
		"the row names a subject by the def id the claim carries"
	)
	for catalog in ["NpcDef", "NpcCatalog", "NpcApi", "npc/"]:
		assert_eq(
			_code_only(PANEL_SCRIPT_PATH).contains(catalog),
			false,
			(
				(
					"and the row names %s: the subject's name is authored on its def and read "
					% catalog
				)
				+ "through the catalog, which `ui/` may not reach"
			)
		)
	# The SCREEN may not reach it either, and the reason is sharper here than for a
	# node: a node's `display_name` arrives in `ForageApi.view`, whereas a custody record
	# carries NO name at all, so the screen has nothing to pass down even if it could.
	assert_eq(
		_code_only(SCRIPT_PATH).contains("NpcDef"),
		false,
		"the screen names no `NpcDef`: `custody` is in UI_MODULES with no module reach"
	)


## The screen names ONE facade and nothing else from `custody`, and no `app/` type.
## `tools arch` checks the module side of that boundary; this checks the UI side, by
## reading the shipped source.
func test_the_screen_names_one_facade_and_nothing_else_from_the_module() -> void:
	var code := _code_only(SCRIPT_PATH)
	# One call site per verb, so a screen that quietly re-implemented a verb beside the
	# facade's would be visible as a count rather than as a reading.
	for verb in ["CustodyApi.capture(", "CustodyApi.transfer(", "CustodyApi.release("]:
		assert_eq(code.count(verb), 1, "the screen calls %s by name, exactly once" % verb)
	assert_eq(
		code.count("CustodyApi.summary("),
		1,
		"and reads the facade once per refresh, so a refresh costs one call"
	)
	assert_eq(
		code.count("CustodyApi.settle_term("),
		1,
		"and settles a term through the facade rather than through a state interior"
	)
	# Module INTERIORS, and the app layer this program may not name at all.
	for interior in ["CustodyState", "CustodyWorldLedger", "EconomyApi", "EconomyValuation"]:
		assert_eq(
			code.contains(interior),
			false,
			(
				(
					"the screen names %s; ui/ may reach only the facade, and a custody term is "
					% interior
				)
				+ "never priced here"
			)
		)
	assert_eq(
		code.contains("EconomyBoot"),
		false,
		(
			"and no `app/` type: `app` is a PRIVATE_UNIT, so this screen has no seam and "
			+ "needs none"
		)
	)
	assert_eq(
		code.contains("res://src/modules/"),
		false,
		"and paths into no module; a panel calls the facade by bare name"
	)
	# The panel holds the same line: it renders a dictionary and reaches nothing.
	var panel := _code_only(PANEL_SCRIPT_PATH)
	for interior in ["CustodyApi", "CustodyState", "CustodyWorldLedger", "ActorFactory"]:
		assert_eq(
			panel.contains(interior),
			false,
			"the row names %s either; it renders a dictionary and reaches nothing" % interior
		)
	# `OwnerRef` is a CONTRACT, not a module interior: `ui` may depend on `core` and
	# `contracts`, so reading the vacancy marker off a holder ref is legal and is the
	# only reason a released claim and a spare pool row can look different.
	assert_eq(
		panel.contains("OwnerRef.is_vacant("),
		true,
		"and the row may read `OwnerRef`, which is the one contract this page leans on"
	)


## The route is REACHABLE, not merely shippable, and the REAL `ScreenRoutes` API is
## what answers. There is no `route_for_scene`: the table is keyed by id, so the claim
## is read the way the shell reads it — `id_for_scene` for the seam back, `scene_of`
## for the load, `action_of` for the key.
func test_the_custody_route_is_published_and_bound_to_a_key() -> void:
	assert_eq(
		ScreenRoutes.id_for_scene(String(SCREEN_SCENE.resource_path)),
		ROUTE,
		"the route table mounts this scene, and names it by id"
	)
	assert_eq(ScreenRoutes.has(ROUTE), true, "and the id is in the table")
	assert_eq(
		ScreenRoutes.scene_of(ROUTE),
		String(SCREEN_SCENE.resource_path),
		"and the route and the loaded scene are the same file, in both directions"
	)
	assert_eq(
		ScreenRoutes.node_of(ROUTE),
		"CustodyScreen",
		"and the mounted node says which route it is in"
	)
	assert_eq(
		SCREEN_SCENE.can_instantiate(),
		true,
		"so the path the table names is a scene that actually loads"
	)
	var action := ScreenRoutes.action_of(ROUTE)
	assert_eq(InputMap.has_action(action), true, "and the action is declared in project.godot")
	assert_eq(
		String(ScreenRoutes.route_for_action(action)),
		String(ROUTE),
		"and the action routes back to this route, so no key can open another screen"
	)
	# And the key is this route's OWN: a shared key is a route a keyboard player can
	# only reach by accident.
	for other in ScreenRoutes.ids():
		if other == ROUTE:
			continue
		assert_ne(
			ScreenRoutes.action_of(other), action, "no other route shares this route's input action"
		)


## ## The route is BOUND — and it is bound by the PLAIN default arm
##
## This is the claim `ForageScreen` could not make: custody needs no injected `Callable`
## at all, because `rules.UI_MODULES` grants `custody` with no module reach and every
## verb takes primitives plus the actor the screen already holds. So the composition
## root's `_bind_route_screen` reaches this route through its `_:` default arm, and
## asserting that is what makes "no seam is needed" a fact about the shipped tree rather
## than an intention in this file's docblock.
func test_the_composition_root_binds_the_custody_route_through_the_default_arm() -> void:
	# Read CODE, not the file: `item_workbench_app.gd` documents this program at
	# length in docstrings that name `ForageScreen` and `bind_harvest` too, so a raw
	# text scan would be asserting the comment. `_code_only` strips them first.
	var source := _code_only("res://src/app/item_workbench_app.gd")
	assert_ne(source.is_empty(), true, "the composition root's source is readable")
	# No arm of its own: the route is served by the `_:` default, which is the ONLY
	# arm that passes an actor and nothing else.
	assert_eq(
		source.contains("ROUTE_CUSTODY"),
		false,
		"the root declares no custody arm, because custody needs no seam to inject"
	)
	# And the screen takes no seam: a `bind_*` method on it would be a door nothing
	# ever opens, which is the fight page's original defect in reverse.
	for seam in ["bind_custody", "bind_harvest", "bind_quests", "bind_fight"]:
		assert_eq(
			(screen_method_names() as Array).has(seam),
			false,
			"the screen publishes no %s(): nothing opens that door" % seam
		)


## ## The last three bans, read off the SHIPPED screen
##
## No `queue_free()` — a deferred free never runs under a runner driven from
## `SceneTree._initialize()`, so it leaks a screen's whole row pool for the life of the
## process. No `theme_override_*`. No `@onready`. And no number formatting of its own.
##
## ## ## Why the formatting scan looks at ASSIGNMENT targets and not at `%d`
##
## The rule is "no number formatting in a screen — the panel owns `%d/%d`", and what it
## protects is the FIGURES A PLAYER READS. The screen may still name a count it does
## not display: it grows its row pool with `row.name = "Claim%d"`, and a node's name in
## the scene tree is not an authored figure on a card. So the scan looks for a format in
## the same expression as an assignment to something a `Label` reads.
func test_the_screen_breaks_none_of_the_three_bans_the_ui_standard_states() -> void:
	var code := _code_only(SCRIPT_PATH)
	assert_eq(code.contains("queue_free"), false, "no queue_free(): the runner never defers")
	assert_eq(code.contains("theme_override_"), false, "no theme_override_*: the theme owns style")
	assert_eq(code.contains("@onready"), false, "no @onready: nodes resolve in _bind_nodes()")
	assert_eq(code.contains("func _bind_nodes()"), true, "which this screen declares")
	for sink in [".text =", "rates_line", "term_line", "subject_line", "holder_line"]:
		for format in ["%d", "%.1f", "%.2f"]:
			var line := ""
			for candidate in code.split("\n"):
				if candidate.contains(sink) and candidate.contains(format):
					line = candidate
					break
			assert_eq(
				line.is_empty(),
				true,
				"no formatted figure reaches a label: %s (%s)" % [sink, format]
			)
	# The pool grows; it never mints a control the scene did not mount. `RowBudget` and
	# `ActionSet` are the two things a screen legitimately grows and delegates to.
	assert_eq(code.count("instantiate()"), 2, "it grows rows and only rows")


## The panel holds the same line, for the reason `test_forage_surface` gives: the runner
## drives it with no scene tree, so a widget bound in `@onready` is never bound.
func test_the_row_binds_its_nodes_lazily_and_builds_no_widgets_in_ready() -> void:
	var code := _code_only(PANEL_SCRIPT_PATH)
	assert_eq(code.contains("@onready"), false, "no @onready in a panel")
	assert_eq(code.contains("func _bind_nodes()"), true, "it binds in _bind_nodes()")
	assert_eq(code.contains(".new()"), false, "and mints no widget, which a scene mounts")
	assert_eq(code.contains("queue_free"), false, "and never defers a free")


## The scene itself is composed: anchors and Containers only, and styled through
## `theme_type_variation` rather than a `theme_override_*`. Read from the SHIPPED scene
## rather than asserted about the script, because a `.tscn` is where a stray
## `position = Vector2(…)` would live and a script scan cannot see it.
func test_the_scene_is_anchors_and_containers_only() -> void:
	var scene := FileAccess.get_file_as_string(String(SCREEN_SCENE.resource_path))
	assert_ne(scene.is_empty(), true, "the screen scene is readable")
	assert_eq(scene.contains("theme_override"), false, "the scene styles by variation only")
	assert_eq(scene.contains("anchors_preset"), true, "and the root is anchored")
	for banned in ["position = Vector2", "offset_left", "offset_top"]:
		assert_eq(
			scene.contains(banned), false, "the scene declares no absolute geometry: %s" % banned
		)
	# The panel scene too, since it is a second shipped surface.
	var row_scene := FileAccess.get_file_as_string(String(ROW_SCENE.resource_path))
	assert_ne(row_scene.is_empty(), true, "the row scene is readable")
	assert_eq(row_scene.contains("theme_override"), false, "and it styles by variation only")


# --- plumbing ----------------------------------------------------------------


## Every method name the shipped screen publishes, for the seam assertion above.
## Read off the live node rather than off the script's member list, so an inherited
## `bind_*` from `UiScreen` would count — which is the point: the claim is that NO door
## of that shape exists, inherited or declared.
func screen_method_names() -> Array:
	var screen: Node = _screen()
	var out: Array = []
	for method in screen.get_method_list():
		out.append(String(method.get("name", "")))
	screen.free()
	return out


## The shipped source of `path` with every comment removed.
##
## A `#` line, and everything from an inline `#` to end of line, is prose. Asserting on
## prose is worse than useless here: this suite's whole subject is a boundary BETWEEN
## what a script says about a module and what it calls, and a docstring naming a banned
## symbol would turn a real boundary check into a typo detector. Same shape as
## `test_ui_conventions.gd:_strip_comments` and
## `test_forage_surface.gd:_code_only`.
func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash := line.find("#")
		out.append(line.substr(0, hash) if hash >= 0 else line)
	return "\n".join(out)
