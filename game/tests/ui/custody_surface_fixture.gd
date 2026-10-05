extends TestCase

## Shared fixture for the two halves of the custody surface suite. NOT a suite itself:
## the runner discovers `test_*.gd` only (`run_tests.gd::_find_tests`), so this file is
## never executed on its own.
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no method
## renamed: every constant, the `setup()` / `teardown()` pair and the private helper both
## halves use now live here, which both halves `extends`. No state is duplicated.
##
## `setup()` / `teardown()` MUST live here rather than in one half. `CustodyApi._store`,
## `CustodyApi._resolver` and `CustodyApi._minter` are all PROCESS-WIDE, and the runner
## shares one process across every suite and calls `teardown()` after EVERY test -- so a
## store installed by one half and cleared by the other outlives the suite and is
## inherited by everything that runs later.
##
## The slice half -- capture, transfer, settlement and release driven the way a player
## does -- is `test_custody_surface.gd`. The screen-contract, panel-format and
## shipped-source half is `test_custody_surface_contract.gd`.

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
