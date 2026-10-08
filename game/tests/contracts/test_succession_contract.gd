extends TestCase

## Slice 8a: succession and schism as SHARED capabilities (goal 40d9bc19, org-slice8a).
##
## The design answer, measured rather than assumed: the contracts needed NO
## widening. `Successive` and `Schismatic` already capture the two shared
## properties — a succession is WALKED with a spent clock and no roll, a split
## costs BOTH halves — in kind-agnostic context dicts, so a non-tier pack claims
## them by registering the contract classes and driving them, with NO sect code
## in the path. What CHANGED is on the sect side: `SectSchism.unassigned` walked
## the CALLER's list (an empty word and a doubled id both shrank the bill) and
## there was no free-price gate at all, so a zero-cost tuning shipped a free
## schism. Both are fixed here; the three remaining divergences live in
## `sect/api.gd`, outside this slice, and are REPORTED, not taken:
## (1) re-opening a walk resets it instead of refusing `already_open`
## (`SectSuccession.is_open` is the one-line seam); (2) `accrue` banks unbounded
## periods while the contract clamps one wait to `MAX_WAIT_PERIODS` — the sect
## constant exists and is never read; (3) `wait` on `periods < 1` or on a
## finished walk no-ops instead of refusing `no_periods` / `walk_complete`.
## Sect's `walk_complete` collapse (unwalkable method reads as finished) is a
## DELIBERATE vocabulary difference, documented, not drift.
##
## ## D8: the cost, the counter and the scarcity of each shared behavior
##
## Succession — cost: every stage SPENDS the office's authored `stage_periods`
## out of the vacancy clock, so a stage cannot be taken twice on one waiting.
## Counter: the walk is a visible row (`walk` publishes `side`/`ready`), so the
## vacancy is public while it lasts. Scarcity: one open walk per office
## (`already_open` refuses a second) and a finite authored `walk_length`.
## Schism — cost: BOTH halves pay the whole bill (`price` + per-unassigned),
## settling from one `settled` number. Counter: the shortfall is published when
## the price exceeds the inheritance, and the plan carries `price` + `unassigned`
## for the record. Scarcity: halves inherit FLOOR halves, so repeated splits
## decay geometrically (`kept * 2 + odd + 2 * price == undivided`, so the halves
## hold strictly less than the whole whenever the price is real), and a free
## split is refused by name (`no_price`).
##
## Three-state vocabulary throughout: `{}` (no such walk/row), a visible vacancy
## (`side == vacant`, never `0`), and `{"ok": false, "reason": <named constant>}`
## (refused). No clock anywhere: every accrual takes an explicit `periods`.
## Position and standing never derive from each other: nothing here promotes,
## and the only standing moved is the schism's own priced division.
##
## ## Every loop in this file is a `for`
##
## Walks are over literal ranges, fixed probe arrays, or a shipped def's own
## authored lists; no body appends to the container it walks, so no bound grows
## in lockstep with its own body and `test_no_unbounded_wait.gd` has nothing to
## reject.

## The shipped trading guild, READ and never mutated.
const LANTERN := "res://data/institutions/lantern_exchange.tres"
const LANTERN_ID := &"lantern_exchange"
const SEAT := &"first_ledger"


func setup() -> void:
	InstitutionContract.instance().clear()
	expect_assertions(3)


func teardown() -> void:
	InstitutionContract.instance().clear()


# --- the shipped suites hold --------------------------------------------------


## The suites this slice registers are the suites Slice 1 shipped: empty
## findings on the contract classes themselves, so `register` admits the kind.
func test_shipped_successive_and_schismatic_suites_hold() -> void:
	assert_eq(Successive.new().contract_findings(), [], "successive holds its own suite")
	assert_eq(Schismatic.new().contract_findings(), [], "schismatic holds its own suite")
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(contract.register(&"trading_guild", [Successive.new(), Schismatic.new()])["ok"]),
		true,
		"a guild claiming both registers with no tier module"
	)


# --- a non-tier pack walks a succession ---------------------------------------


## The Lantern Exchange claims `successive` and walks a full three-stage walk
## with NO sect code loaded: the office id is the guild's own shipped
## `first_ledger`, the walk numbers are the case's (a generic office authors no
## walk — the Slice 1 cost-pair discipline), and every property the contract
## owns is measured: determinism by TEXT, one stage per call, the spent clock,
## the second-step refusal, and the finished walk.
func test_the_trading_guild_walks_a_succession_with_no_sect_code() -> void:
	var def := load(LANTERN) as InstitutionDef
	assert_ne(def, null, "the shipped guild loads")
	assert_eq(String(def.kind), "trading_guild", "and it is a trading guild, not a sect")
	assert_ne(def.position(SEAT), null, "and its top seat exists")
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(contract.register(&"trading_guild", [Successive.new()])["ok"]),
		true,
		"the kind registers with no tier module"
	)
	var impl := contract.of(&"trading_guild", &"successive")["capability"] as Successive
	var base := {
		"kind": "trading_guild",
		"institution": String(LANTERN_ID),
		"member": "probe_factor",
		"office": String(SEAT),
		"open": false,
		"stage": 0,
		"walk_length": 3,
		"stage_periods": 2,
		"held_periods": 0,
		"periods": 2,
	}
	# Nothing has started: stepping is a caller mistake, refused by name.
	assert_eq(
		String(impl.advance(base.duplicate(true)).get("reason", "")),
		Successive.R_NO_SUCH_WALK,
		"no walk has started"
	)
	var opened := impl.open(base.duplicate(true))
	assert_eq(bool(opened.get("ok", false)), true, "the seat goes vacant")
	assert_eq(String((opened["plan"] as Dictionary)["side"]), String(Successive.VACANT), "vacant")
	# Scarcity: one open walk per office — a second opening is a reset refused.
	var reopen := base.duplicate(true)
	reopen["open"] = true
	assert_eq(
		String(impl.open(reopen).get("reason", "")),
		Successive.R_ALREADY_OPEN,
		"a second opening refuses already_open"
	)
	# The clock is empty: the first stage waits.
	var walking := base.duplicate(true)
	walking["open"] = true
	assert_eq(
		String(impl.advance(walking).get("reason", "")),
		Successive.R_PERIOD_NOT_ELAPSED,
		"the vacancy has not aged"
	)
	var empty := base.duplicate(true)
	empty["open"] = true
	empty["periods"] = 0
	assert_eq(
		String(impl.wait(empty).get("reason", "")),
		InstitutionCapability.R_NO_PERIODS,
		"waiting no time is refused, not absorbed"
	)
	# Two identical calls answer by TEXT: the walk is deterministic, no roll.
	var due := walking.duplicate(true)
	due["held_periods"] = 2
	var first := impl.advance(due.duplicate(true))
	var second := impl.advance(due.duplicate(true))
	assert_eq(JSON.stringify(first), JSON.stringify(second), "two runs answer identically")
	assert_eq(bool(first.get("ok", false)), true, "the first stage plans")
	assert_eq(int((first["plan"] as Dictionary)["stage"]), 1, "exactly one stage per call")
	assert_eq(int((first["plan"] as Dictionary)["held_periods"]), 0, "and the clock was SPENT")
	# Apply the plan and step again: nothing is due.
	var after := walking.duplicate(true)
	after["stage"] = 1
	after["held_periods"] = 0
	assert_eq(
		String(impl.advance(after).get("reason", "")),
		Successive.R_PERIOD_NOT_ELAPSED,
		"a second stage in one waiting is refused"
	)
	# Walk the whole length, one waiting per stage.
	var stage := 0
	var held := 0
	for _i in 3:
		var waited: Dictionary = impl.wait(_walk_ctx(walking, stage, held))
		assert_eq(bool(waited.get("ok", false)), true, "a waiting accrues")
		held = int((waited["plan"] as Dictionary)["held_periods"])
		var landed := impl.advance(_walk_ctx(walking, stage, held))
		assert_eq(bool(landed.get("ok", false)), true, "and the next stage lands")
		stage = int((landed["plan"] as Dictionary)["stage"])
		held = int((landed["plan"] as Dictionary)["held_periods"])
	assert_eq(stage, 3, "three waitings walked three stages")
	var done := _walk_ctx(walking, stage, held)
	assert_eq(
		String(impl.advance(done).get("reason", "")),
		Successive.R_WALK_COMPLETE,
		"a finished walk refuses"
	)
	assert_eq(
		String(impl.wait(done).get("reason", "")),
		Successive.R_WALK_COMPLETE,
		"and there is nothing left to wait for"
	)
	# The finished plan is JSON-stable: parse, write, parse again is a fixed
	# point, so a save/load cycle cannot drift it. (JSON has one number type,
	# so ints read back as floats — the loader's clamps, not the text, own the
	# types, which is why this asserts stability rather than identity.)
	var succession_text := JSON.stringify(first["plan"])
	var succession_once = JSON.parse_string(succession_text)
	assert_ne(succession_once, null, "the plan parses")
	assert_eq(
		JSON.parse_string(JSON.stringify(succession_once)),
		succession_once,
		"the plan survives a save round-trip"
	)


## One waiting's context for the walk above: the office's row plus the periods
## the caller that owns time hands in.
func _walk_ctx(walking: Dictionary, stage: int, held: int) -> Dictionary:
	var ctx := walking.duplicate(true)
	ctx["stage"] = stage
	ctx["held_periods"] = held
	return ctx


# --- a non-tier pack declares a schism ----------------------------------------


## The Lantern Exchange claims `schismatic` and splits with NO sect code: the
## institution id is the guild's own, the places are its own authored
## `claimed_territories()` (empty — the guild authors no ground, which is itself
## measured), and the price is the case's. Every property is measured: the odd
## point charged away, ONE settled number for both halves, the parent not
## profiting, the ruinous split planning with its shortfall, and the free split
## refused by name.
func test_the_trading_guild_declares_a_schism_with_no_sect_code() -> void:
	var def := load(LANTERN) as InstitutionDef
	assert_ne(def, null, "the shipped guild loads")
	var places: Array = []
	for place in def.claimed_territories():
		places.append(String(place))
	assert_eq(places, [], "the guild authors no ground: its per-place charge is zero")
	var contract := InstitutionContract.instance()
	assert_eq(
		bool(contract.register(&"trading_guild", [Schismatic.new()])["ok"]),
		true,
		"the kind registers with no tier module"
	)
	var impl := contract.of(&"trading_guild", &"schismatic")["capability"] as Schismatic
	var probe := {
		"kind": "trading_guild",
		"institution": String(LANTERN_ID),
		"seceding": "lantern_splinter",
		"member": "probe_factor",
		"undivided": 41,
		"price": 5,
		"places": places,
		"assigned": [],
		"cost_per_unassigned": 2,
	}
	var read := impl.settle(probe.duplicate(true))
	assert_eq(bool(read.get("ok", false)), true, "the arithmetic reads")
	assert_eq(
		int(read["half"]) * 2 + int(read["odd_charged"]),
		int(read["undivided"]),
		"the odd point is charged away, never minted"
	)
	assert_eq(int(read["kept"]), int(read["seceded"]), "both halves start from ONE number")
	assert_eq(int(read["price"]), 5, "no authored ground means the base price alone")
	assert_eq(int(read["unassigned"]), 0, "and nothing left unassigned")
	assert_eq(
		int(read["kept"]) * 2 + int(read["odd_charged"]) + 2 * int(read["price"]),
		int(read["undivided"]),
		"the halves plus what both paid sum back to the whole exactly"
	)
	assert_eq(
		int(read["kept"]) + int(read["seceded"]) <= int(read["undivided"]),
		true,
		"the parent does not profit: the halves hold no more than the whole did"
	)
	var answer := impl.declare(probe.duplicate(true))
	assert_eq(bool(answer.get("ok", false)), true, "the declaration plans")
	var halves: Array = (answer["plan"] as Dictionary)["halves"]
	assert_eq(halves.size(), 2, "two halves")
	assert_ne(String(halves[0]), String(halves[1]), "and they are not one id twice")
	assert_eq(
		int((answer["plan"] as Dictionary)["settled"]),
		int(read["settled"]),
		"the plan settles what the read settled"
	)
	# Two identical declarations answer by TEXT: the split is walked, never rolled.
	assert_eq(
		JSON.stringify(answer),
		JSON.stringify(impl.declare(probe.duplicate(true))),
		"deterministic across two runs"
	)
	# A ruinous price still PLANS, settling at zero with the shortfall said.
	var ruinous := probe.duplicate(true)
	ruinous["price"] = 1000
	var doomed := impl.declare(ruinous)
	assert_eq(bool(doomed.get("ok", false)), true, "an unaffordable split plans, not refuses")
	assert_eq(int((doomed["plan"] as Dictionary)["settled"]), 0, "settling at zero")
	assert_eq(int((doomed["plan"] as Dictionary)["shortfall"]) > 0, true, "with the shortfall said")
	# And the free split — the strictly-positive action — is refused by name.
	var free := probe.duplicate(true)
	free["price"] = 0
	free["cost_per_unassigned"] = 0
	assert_eq(
		String(impl.declare(free).get("reason", "")),
		Schismatic.R_NO_PRICE,
		"a declaration charging nothing refuses"
	)
	var lonely := probe.duplicate(true)
	lonely["undivided"] = 1
	assert_eq(
		String(impl.declare(lonely).get("reason", "")),
		Schismatic.R_NOTHING_TO_SPLIT,
		"one point splits into two halves of nothing"
	)
	var itself := probe.duplicate(true)
	itself["seceding"] = itself["institution"]
	assert_eq(
		String(impl.declare(itself).get("reason", "")),
		Schismatic.R_CANNOT_SECEDE_FROM_ITSELF,
		"the undivided cannot secede from itself"
	)
	# The plan is JSON-stable: parse, write, parse again is a fixed point, so a
	# save/load cycle cannot drift it (see the succession case for why floats).
	var schism_text := JSON.stringify(answer["plan"])
	var schism_once = JSON.parse_string(schism_text)
	assert_ne(schism_once, null, "the plan parses")
	assert_eq(
		JSON.parse_string(JSON.stringify(schism_once)),
		schism_once,
		"the plan survives a save round-trip"
	)


## The authored-list billing, measured without sect code: a short assignment
## list leaves MORE places unassigned rather than fewer, because the walk counts
## the AUTHORED places. The guild authors none, so this case authors two.
func test_a_short_assignment_list_cannot_shrink_the_bill() -> void:
	var impl := Schismatic.new()
	var probe := {
		"kind": "trading_guild",
		"institution": String(LANTERN_ID),
		"seceding": "lantern_splinter",
		"member": "probe_factor",
		"undivided": 41,
		"price": 5,
		"places": ["probe_meadow", "probe_harbour"],
		"assigned": ["probe_meadow"],
		"cost_per_unassigned": 2,
	}
	var read := impl.settle(probe.duplicate(true))
	assert_eq(int(read["unassigned"]), 1, "one authored place left")
	assert_eq(int(read["price"]), 7, "base plus the one unassigned place")
	var short := probe.duplicate(true)
	short["assigned"] = []
	assert_eq(int(impl.settle(short)["unassigned"]), 2, "an empty list bills every authored place")


# --- the sect-side fixes this slice landed ------------------------------------


## `SectSchism.unassigned` walks the AUTHORED list: an empty word names no
## place, a doubled id abandons its place once, and an id the sect never
## claimed is not a place a split can abandon. Each arm below failed before the
## rewrite — the old walk counted the caller's list, so `[""]` and `["a", "a"]`
## both shrank the bill.
func test_sect_unassigned_counts_the_authored_places() -> void:
	var def := SectDef.new()
	var held: Array[StringName] = [&"a_meadow", &"b_harbour"]
	def.territory_ids = held
	var both: Array[StringName] = [&"a_meadow", &"b_harbour"]
	assert_eq(SectSchism.unassigned(def, both), 0, "everywhere assigned")
	var one: Array[StringName] = [&"a_meadow"]
	assert_eq(SectSchism.unassigned(def, one), 1, "one place left")
	var none: Array[StringName] = []
	assert_eq(SectSchism.unassigned(def, none), 2, "a short list bills, never shrinks")
	var empty_word: Array[StringName] = [&"", &"a_meadow"]
	assert_eq(SectSchism.unassigned(def, empty_word), 1, "an empty word names no place")
	var doubled: Array[StringName] = [&"a_meadow", &"a_meadow"]
	assert_eq(SectSchism.unassigned(def, doubled), 1, "a doubled id abandons its place once")
	var stranger: Array[StringName] = [&"nowhere_at_all"]
	assert_eq(SectSchism.unassigned(def, stranger), 2, "an unclaimed id is no place at all")
	assert_eq(SectSchism.unassigned(null, one), 0, "no def, no bill")
	# The price built on it is one number both halves pay: base plus per-place.
	var tuning := SectTuning.new()
	tuning.schism_cost = 25
	tuning.schism_cost_per_unassigned = 5
	assert_eq(SectSchism.price(tuning, 1), 30, "base plus the one unassigned place")
	assert_eq(SectSchism.price(null, 9), 0, "no tuning, no price")


## The free-price gate, and its parity with the contract: a bill of zero or
## less is no price at all, and the contract refuses exactly that declaration
## as `no_price`. `SectTuning` defaults BOTH costs to `0`, so this is the
## refusal an unpriced tuning reaches — the applier edit (`sect/api.gd`
## `declare_schism`, reported, not taken) reads this predicate.
func test_a_free_schism_is_refused_by_name_on_both_sides() -> void:
	assert_eq(SectSchism.is_free_price(0), true, "zero is no price")
	assert_eq(SectSchism.is_free_price(-3), true, "and less than zero is none either")
	assert_eq(SectSchism.is_free_price(1), false, "one is a price")
	assert_eq(SectSchism.R_NO_PRICE, Schismatic.R_NO_PRICE, "the sect names the contract's reason")
	assert_eq(
		bool((SectSchism.REASONS as Dictionary).has(SectSchism.R_NO_PRICE)),
		true,
		"and publishes it in its reason table"
	)
	var impl := Schismatic.new()
	var free := {
		"kind": "trading_guild",
		"institution": String(LANTERN_ID),
		"seceding": "lantern_splinter",
		"member": "probe_factor",
		"undivided": 41,
		"price": 0,
		"places": [],
		"assigned": [],
		"cost_per_unassigned": 0,
	}
	assert_eq(
		String(impl.declare(free).get("reason", "")),
		Schismatic.R_NO_PRICE,
		"the contract refuses the same declaration"
	)


## No clock and no generator in any file this slice owns or leans on: the walk
## is a pure function of its context and the split a pure function of its bill.
## Comment prose is skipped — the class notes name the banned words to document
## the ban, so only executable lines are read.
func test_no_touched_file_consults_a_clock_or_a_generator() -> void:
	for rel in [
		"res://src/contracts/successive.gd",
		"res://src/contracts/schismatic.gd",
		"res://src/modules/sect/sect_succession.gd",
		"res://src/modules/sect/sect_schism.gd",
	]:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		for banned in [
			"RandomNumberGenerator",
			"randi(",
			"randf(",
			"randomize(",
			"Time.get_ticks_msec(",
			"Time.get_ticks_usec(",
		]:
			assert_eq(_calls(body, banned), 0, "%s never calls %s" % [rel.get_file(), banned])


## How many times `needle` appears in CODE, ignoring `##` prose.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits
