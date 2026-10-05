extends TestCase

## Shared kit for the two auction-bid suites. NOT a suite itself: the runner discovers
## `test_*.gd` only, so this file is never executed on its own (`run_tests.gd::_find_tests`).
##
## Split out of the original single-file suite purely for size -- gdlint's
## `max-file-lines` is 1000. Nothing was rewritten, no assertion changed and no
## method renamed: the cases below are the original bodies verbatim, and every
## constant, builder and helper they use now lives here, which both halves `extends`.
##
## `setup()` and `teardown()` MUST live here rather than in one half. `MarketApi.set_store`
## is PROCESS-WIDE, and the runner calls `teardown()` after EVERY test on whichever
## suite instance ran it -- so a store installed by one half and cleared by the other
## outlives the suite and is inherited by everything that runs later.
##
## The determinism / refusal / personality half is `test_auction_bids.gd`. The
## settlement and structural-pin half is `test_auction_settlement.gd`.

## ADR 0102 / BL-0049: **NPCs bid, and the bid is arithmetic.**
##
## BL-0049 asked for "NPC bidders with wealth/personality; rare items attract powerful
## cultivators; consequences emerge". These assert the three properties that make that
## true rather than decorative:
##
##   - the bid is a function of (purse, tag, lot) and of nothing else — no rng anywhere;
##   - a bidder who cannot reach the opening bid writes NOTHING;
##   - a legendary lot opens four times above a common one, so only a deep purse clears
##     it. That is the whole "rare items attract powerful cultivators" claim, and it is
##     `RARITY_WEIGHT` multiplied through one frozen price rather than a simulation.
##
## ## Read the STORE, never the actor's own mirror
##
## `MarketApi.state(actor)` returns the actor's OWN mirror by design; `summary` goes
## through the shared world store. A test that read `state` therefore saw a **stale**
## ledger — the world row written by `_save`, which on a fresh house still carries the
## previous test's lots — and asserted against a bid count of zero. Every lot assertion
## below goes through [_lots], which is the only shape that cannot go stale.
##
## ## Fixtures are held, not returned
##
## `Actor` is a `RefCounted`. An actor built inside a helper is **freed the moment that
## helper returns**, the ledger stores ids rather than references, and nothing keeps it
## alive — so every actor here is appended to `_held`. Same reason
## `test_market_auction.gd` does it.

const COIN := &"curr_spirit_coin"
const GOOD := &"currency_spirit_stone"
const CAST_ROOT := "res://data/npc/cast"

## Every cast member an authored appetite reaches, with the appetite the table gives it.
## A restated expectation on purpose: a test that read the number back out of
## `APPETITE_PERCENT` would pass if both the tag and the number drifted together.
const AUTHORED_BIDDERS: Array = [
	{"file": "elder_wei.tres", "tag": &"collector", "percent": 90},
	{"file": "smith_bearcutter.tres", "tag": &"thrifty", "percent": 45},
	{"file": "drifter.tres", "tag": &"opportunist", "percent": 30},
	{"file": "gate_keeper_bo.tres", "tag": &"opportunist", "percent": 30},
]

## The tags a module must not acquire an edge to. `npc` is here because the bidding verb
## is composed, not because any module names it — the assertion is structural, so it
## holds whether the verb lives in `app/` or somebody later moves it.
const FORBIDDEN_IN_MARKET: Array = [
	"NpcApi", "NpcCatalog", "NpcDef", "NpcState", "NpcEvents", "NpcBoot"
]

## Every seed and generator token GDScript offers, as a TEST-LOCAL fixture. Nothing in
## production wants this table: it is the vocabulary the structural pin searches FOR, and
## `auction_bids.gd` is the only file it is ever read against — so a production constant
## for it would put a list of forbidden words in the shipping facade, which is the
## opposite of the ADR 0102 rule it exists to protect.
##
## `seed(` is here too even though `market/api.gd` writes a `"seed"` key while rebuilding
## a saved instance: a `"seed":` string key is saved data, not a generator call, and this
## list is matched against `auction_bids.gd` only.
const GENERATORS: Array = [
	"RandomNumberGenerator",
	"randf(",
	"randi(",
	"rand_range(",
	"randf_range(",
	"rand_weighted(",
	"rand_from_seed(",
	"randomize(",
	"shuffle(",
	"seed(",
	"Time.",
	"get_ticks",
	"get_tree()",
]

var _held: Array[Actor] = []
## The `AuctionBids._lot` helper reads through `MarketApi.summary`, so it is handed a
## HOUSE-SCOPED store: one bid call resolves only the lots that house listed, and a
## "compare two collectors" case can then be stated as two houses instead of two ids
## that collide into one escrow check.
var _store: MarketWorldLedger = null
## A counter for unique seller ids. A member rather than a `static var` because a static
## would carry across suites in this one process.
var _next_seller := 0


func setup() -> void:
	# A lot is a WORLD fact: a bidder must see the seller's lot or every bid refuses
	# `lot_not_open` (ADR 0101).
	_store = MarketWorldLedger.new()
	MarketApi.set_store(_store)
	_held.clear()


func teardown() -> void:
	# Process-wide, and the runner calls this after EVERY test — a lot left in the shared
	# store outlives the suite and the next one inherits it.
	MarketApi.set_store(null)
	_store = null
	_held.clear()


## Point the shared store at a fresh world. Called between two lots that would otherwise
## collide on `lot_<seller>_<instance>`.
##
## **Both halves of a comparison must be built INSIDE the world they are compared in.**
## `MarketApi.list` writes the lot through `_save`, which writes the shared store AND mirrors
## the row onto `seller.module_data`. `_state` reads the shared store when there is one, so
## a lot listed in world A is INVISIBLE to every reader once the store points at world B —
## while the seller's own `module_data` mirror still carries it. That split is the shape
## `MarketApi.state` warns about in its own docstring, and it produces two different broken
## results depending on which side reads: a BIDDER resolves `no_lot`, while a `_lot()` call
## resolves the seller's stale mirror. `_new_world` therefore exists to be called BEFORE a
## lot is listed, never between a listing and the bid that answers it — which is exactly
## where the previous version of this file called it, and why eight of its cases read
## `required 11` against `required 901` on the same fixture.
func _new_world() -> void:
	_store = MarketWorldLedger.new()
	MarketApi.set_store(_store)


# --- fixtures ------------------------------------------------------------------


## The house: an actor holding ONE realized instance to list, and an empty purse to be
## paid into. Added as an instance rather than a stack because `remove_instance` only
## ever reaches the `_instances` half, which is the same shape `loot` escrows.
##
## **`next_seller` makes BOTH ids unique per house.** A lot id is
## `lot_<seller>_<instance_id>`, so a unique seller id alone is not enough — it was
## `MarketApi.list`'s duplicate-instances scan that refused, and that scan matches
## `instance_id` ALONE across the whole world ledger. Every house minted
## `ItemInstance.new(def.id, &"lot_candidate")`, so house 1 escrowed the lot
## `lot_auction_house_1_lot_candidate` and house 2's very different instance — a different
## seller, a different lot id — was refused `lot_already_listed` for "re-listing" it. The
## second listing returned `""`, and every later read of `""` then failed in a way that had
## nothing to do with the property under test: a `required_bid` of 0, a ceiling of 0, a
## second `assert_eq` over the same two numbers printing the same 0-vs-450 twice. So the
## instance id is minted per house as well, which is what makes a comparison two real lots
## in one world — the world store is what makes a lot visible to a bidder, so separating
## them into different worlds only separates the lot from the reader as well.
func _house(rarity: StringName = &"") -> Actor:
	_next_seller += 1
	var actor := Actor.new()
	actor.id = &"auction_house_%d" % _next_seller
	ItemsApi.attach(actor, 24)
	# A seller's floor and lots are WORLD facts (ADR 0101). `MarketApi.attach` is what
	# installs the shared store onto a fresh actor; without it a house that never sold
	# anything reads an empty mirror and the escrow row is written somewhere no bidder
	# can see.
	MarketApi.attach(actor)
	var def := Crafting.resolve(GOOD)
	var instance := ItemInstance.new(def.id, &"lot_candidate_%d" % _next_seller)
	instance.def_ref = def
	instance.rarity = rarity if rarity != &"" else def.rarity
	# A realized price must come from AUTHORED worth: ADR 0094 refuses an instance whose
	# `rolled` carries a `trade_value`, and `list` returns `no_settlement` for one.
	instance.rolled = []
	instance.realm = &""
	ItemsApi.inventory(actor).add_instance(instance)
	EconomyApi.attach(actor)
	_held.append(actor)
	return actor


## A bidder with `coins` of purse and the given appetite tags.
##
## `Actor.tags` is `Array[StringName]`, so a plain `Array` cannot be ASSIGNED to it —
## and a rejected assignment returns from the function, so the helper silently handed
## back an untyped actor and every bid refused for a reason three frames away. Appended
## element-wise for that reason.
func _bidder(id: StringName, coins: int, tags: Array[StringName] = []) -> Actor:
	var actor := Actor.new()
	actor.id = id
	ItemsApi.attach(actor, 24)
	ItemsApi.inventory(actor).add(Crafting.resolve(COIN), coins)
	for tag in tags:
		actor.tags.append(tag)
	EconomyApi.attach(actor)
	_held.append(actor)
	return actor


func _list_good(house: Actor) -> String:
	var instance_id := &""
	for instance in ItemsApi.inventory(house).instances():
		instance_id = instance.instance_id
		break
	var listed := MarketApi.list(house, instance_id, 3)
	assert_eq(
		bool(listed.get("ok", false)), true, "the fixture lot lists: %s" % listed.get("reason", "")
	)
	return String(listed.get("lot_id", ""))


## The lots of the current world, as the READ MODEL sees them — through `summary`, which
## goes via the world store, and never through `MarketApi.state`, whose actor mirror goes
## stale. A fresh throwaway actor is the reader, because `summary` takes any actor.
func _lots() -> Array:
	return (
		MarketApi.summary(_bidder(&"a_reader", 0, [] as Array[StringName])).get("lots", []) as Array
	)


## The one lot of the current world. Returns `{}` rather than indexing when the count is
## wrong, so a broken fixture turns the NEXT assertion red with a message instead of
## aborting this one halfway through.
func _lot() -> Dictionary:
	var rows := _lots()
	assert_eq(rows.size(), 1, "the fixture listed exactly one lot")
	return (rows[0] as Dictionary) if rows.size() == 1 else {}


## The lot named by `lot_id`, out of the current world. **The selector for a case that
## deliberately holds two lots at once** — `_lot()` asserts the count is exactly one, which
## is the right guard for a single-lot case and the wrong one for a comparison, where the
## previous version reached for `_lot()` anyway and read whichever row sorted first.
func _row(lot_id: String) -> Dictionary:
	for row in _lots():
		if String((row as Dictionary).get("lot_id", "")) == lot_id:
			return row as Dictionary
	return {}


## Resolve a bid row's actor id to a live body, exactly as a caller of `settle_lot` must.
func _resolver(actors: Array) -> Callable:
	return func(id: String) -> Actor:
		for actor in actors:
			if actor != null and String(actor.id) == id:
				return actor as Actor
		return null


## `source` with every `##` documentation line dropped, so a structural pin can forbid a
## token in CODE while the file is still free to explain the rule in prose. A whole-line
## comment is dropped and an inline trailing comment is truncated at its `#`.
func _executable(source: String) -> String:
	var out: Array[String] = []
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		var hash_at := line.find("#")
		out.append(line.substr(0, hash_at) if hash_at >= 0 else line)
	return "".join(out)


func _player() -> Actor:
	var actor := Actor.new(&"hero", {Stat.PHYSIQUE: 12.0, Stat.WILL: 8.0})
	actor.attach_core_resources()
	SocialApi.attach(actor)
	ItemsApi.attach(actor, 24)
	EconomyApi.attach(actor)
	return actor
