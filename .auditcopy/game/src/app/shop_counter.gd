class_name ShopCounter
extends RefCounted

## **A `ShopDef` realized as the live `Actor` the market verbs demand** (ADR 0100, DEF-0218).
##
## ## Why this file exists and lives in `app/`
##
## `MarketApi.buy(shop_actor, player, rows)` and `MarketApi.sell(shop_def, shop_actor, …)`
## both take an `Actor`, because `EconomyExchange.exchange` takes two Actors and nothing
## else. Five authored `ShopDef` `.tres` shipped and NOTHING in `game/src` ever turned one
## into that Actor — so `buy` had no argument a caller could produce and no shop could be
## found at runtime.
##
## Three constraints put the realization here and nowhere else:
##
## 1. **`market` may not name `items` internals.** `Crafting.resolve` is `items`' private
##    resolver, and `MarketApi` reaches it only from inside the module. Realizing stock
##    means resolving every authored `def_id` to an `ItemDef` and adding the REALIZED
##    quantity to a bag — which is `Crafting.resolve` plus `Inventory.add`.
## 2. **`market` may not name `economy`.** It does, in fact — but a shop's own purse is the
##    one thing a shop is allowed to have, and `EconomyValuation.numeraire_id()` is the
##    numeraire's own constant rather than a price this file assembles.
## 3. **A shop is minted, not constructed.** `ActorFactory.build` is the one place that
##    knows the provider spine, and `app/` is the only layer allowed to name it (ADR 0002).
##
## So `app/` supplies it, exactly as `CustodyApi.set_minter` is supplied by
## `EconomyBoot._install_minter` — and this is the **same seam shape, deliberately**, not a
## new idea. See the `MarketApi` question in the report: a `set_shop_minter` seam there
## would have been a THIRTEENTH public method on a facade already at
## `rules.MAX_FACADE_PUBLIC_METHODS`, so no seam was added there at all.
##
## ## Why the Actor is realized ON DEMAND and then REUSED
##
## `MarketApi.buy` mutates the shop's inventory — that is the whole point, the goods LEAVE
## the merchant. A fresh Actor per call would hand every caller a full shelf and make the
## spread testable but the game nonsense. So the counter is **cached by shop id**: the first
## call realizes stock from the def, and every later call is the same Actor with whatever
## it has since sold. This is also the only shape that keeps `MarketState.MAX_SHOPS`
## meaningful — a world remembers a bounded number of off-stage shops.
##
## ## Deterministic, and there is NO rng
##
## `ShopDef.stock_seed(shop_id, def_id)` exists precisely for this: the same shop always
## rolls the same items, which is what makes a shop reproducible and a test need no
## generator. Realization goes through `ItemsApi.generate(actor, def, seed)`, the facade
## verb that realizes from a seeded roll — so a shop's rare stock is the SAME rare stock on
## every boot, and no price anywhere reads a random number (ADR 0094's rule).

# --- refusals ------------------------------------------------------------------
# Named constants rather than prose, so a caller is never left with a null it has to
# interpret (ADR 0084). Every one of these wrote nothing.

## The id names no authored shop. A counter for a shop nothing defines is a shop that
## stocks nothing and buys nothing.
const UNKNOWN_SHOP := "unknown_shop"
## The merchant could not be minted, so there is no Actor to trade through.
const NO_COUNTER := "no_counter"
## A `null` def was handed in. Refused by name rather than dereferenced.
const NO_SHOP := "no_shop"

## The tag stamped on every counter's `Actor.tags`. **A role is a `StringName` tag, never a
## subclass** (ADR 0092) — the shop's identity is its def id and the Actor is the container,
## exactly as `ShopDef`'s own docstring says.
const ROLE := &"shop"

## The prefix of a counter's actor id, so a merchant is distinguishable from a person in a
## log or a ledger key.
const ID_PREFIX := "shop_"

## The live counters, keyed by shop id. A `static var` because the realized merchant IS
## world state — the goods it has already sold are gone — and `rules.py` excludes
## `static var` from the app-state heuristics by construction, the same shape
## `NpcLedger._rows` documents.
static var _counters: Dictionary = {}


## The live merchant for `shop_id`, realized from its authored def on first ask and reused
## after that. Returns `null` when the id names no authored shop.
##
## The whole verb is a cache read plus [method realize], and it takes no lock because
## `tools test` runs the whole suite in one thread on one frame — which is the same
## assumption every other lazy `_ensure_loaded` in the repo makes.
static func counter(shop_id: StringName) -> Actor:
	var def := ShopCatalog.instance().definition(shop_id)
	if def == null:
		return null
	var cached: Actor = _counters.get(String(shop_id))
	if cached != null:
		return cached
	return realize(def)


## Mint and fund one merchant from `def`. This is the public seam: it takes a **`ShopDef`**,
## so a caller holding an installed fixture realizes it without a directory read.
##
## ## A shop is FUNDED, and the funding is not a gift
##
## `MarketTransfer.price` refuses `SHOP_CANNOT_PAY` when the paying side holds no coins,
## and when a PLAYER sells, the SHOP is the payer. So a counter that minted no purse could
## never buy anything from anybody, and half of ADR 0100 would be unreachable — the
## `buys` list, the refusal policy that is the whole of "a black market is a content
## choice".
##
## The purse is minted from the shop's OWN authored stock at the buy rate: what the goods
## in the shop are worth to it is what it can pay with. That is [method _funding_coins]
## below, and it is the only number this file invents.
static func realize(def: ShopDef) -> Actor:
	if def == null or def.shop_id == &"":
		return null
	var actor := ActorFactory.build(StringName(ID_PREFIX + String(def.shop_id)))
	actor.display_name = def.display_name
	actor.tags.append(ROLE)
	# The authored `kind` travels as a tag too, so content can gate on "is this a caravan"
	# exactly as it gates on any other role (ADR 0074: a tag read by content).
	actor.tags.append(def.normalized_kind())
	# `ShopDef.capacity` is the authored bound on the bag, and it is honoured here rather
	# than defaulting to `ItemsApi.DEFAULT_CAPACITY`: a content author who wrote 8 meant 8,
	# and a large authored stock must not be able to become an unbounded Actor.
	ItemsApi.attach(actor, maxi(1, def.capacity))
	EconomyApi.attach(actor)
	MarketApi.attach(actor)
	_stock(actor, def)
	_fund(actor, def)
	_counters[String(def.shop_id)] = actor
	return actor


## Forget every minted counter. **Only a test harness calls this.** A counter is a live
## `Actor` holding a realized `Inventory`, and a suite that left one installed would hold
## that graph alive until the engine shuts down — ObjectDB then reports leaked instances at
## exit with every assertion green, which is the worst possible reading. The authored
## catalog is deliberately NOT reset: a counter is a realization, not content.
static func reset() -> void:
	_counters.clear()


## How many counters this process has minted.
static func count() -> int:
	return _counters.size()


## The read model a shop panel labels itself with: the def as primitives, what the counter
## currently HOLDS, and what it can pay. `{}` when the shop is unknown — the empty shape
## every other facade answer uses, and the contract a panel tests instead of pixels.
##
## ## It reads through the two facades and never a third
##
## `MarketApi.summary` for the spread and the floor, `ShopDef.to_dict` for the authored
## policy. Nothing here prices anything: every number on the shelf comes from
## [method priced_rows], which is the same reader `MarketTransfer.price` settles through. So
## this file names no weight, no realm curve and no unit price — the `AuctionReadModel` rule.
##
## ## `shelf` is what makes `EconomyApi.quote` reachable
##
## The priced shelf was computed for `funding` and `_can_afford` and then thrown away, so the
## preview that priced it published nothing a panel could read. It is published now: a shop
## screen shows `coins` per row, and that number is the one `MarketApi.buy` will charge,
## because both read the same function. A preview nobody can reach is a paid-for feature no
## one bought (DEF-0219).
static func summary(shop_id: StringName) -> Dictionary:
	var def := ShopCatalog.instance().definition(shop_id)
	if def == null:
		return {}
	var actor := counter(shop_id)
	if actor == null:
		return {"shop_id": String(shop_id), "ok": false, "reason": NO_COUNTER}
	var inventory := ItemsApi.inventory(actor)
	var stock: Array = []
	if inventory != null:
		for stack in inventory.stacks():
			stock.append({"def_id": String(stack.def_id), "quantity": int(stack.quantity)})
	stock.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return String(a["def_id"]) < String(b["def_id"])
	)
	# The shelf is priced the way the shop SELLS, because that is the direction a player at
	# this counter trades in: `coins` is the charge, and `_can_afford` compares a purse to it.
	var shelf := priced_rows(def, true)
	return {
		"shop_id": String(def.shop_id),
		"ok": true,
		"reason": "",
		"has_actor": true,
		"actor_id": String(actor.id),
		"definition": def.to_dict(),
		"stock": stock,
		"stock_count": stock.size(),
		"shelf": shelf,
		"shelf_count": shelf.size(),
		"purse": EconomyApi.purse(actor),
		"funding": _funding_coins(def),
		"spread": MarketSpread.view(),
		"market": MarketApi.summary(actor),
	}


## The whole priced read model for one player standing at one location: every authored shop
## here, priced for that purse, and nothing invented for a shop this build does not ship.
##
## **This is the door a caller actually walks through.** Before it, "which shops are here"
## had no answer in `game/src` at all; `ShopDef.location_id` was authored content no code
## read. Returns `{location_id, shops, shop_count}` and each row is a `summary` plus
## `can_buy` — whether that player could afford the cheapest thing on the shelf, so a
## panel can grey an affordance out instead of letting the verb refuse.
static func at_location(location_id: StringName, player: Actor = null) -> Dictionary:
	var out: Array = []
	for def in ShopCatalog.instance().at_location(location_id):
		var row := summary(def.shop_id)
		row["can_buy"] = _can_afford(def, player)
		out.append(row)
	return {"location_id": String(location_id), "shops": out, "shop_count": out.size()}


# --- internals ---------------------------------------------------------------


## The one number this file invents, and why it is not a price formula.
##
## A counter must hold coins to buy with, and it may not hold a magic number nobody
## authored. So the purse IS the shop's own stock valued at `MarketSpread.buy_price` —
## what the goods on its shelf are worth to it, which is also the most it could pay for
## them. That reuses the ONE spread `MarketTransfer.price` already charges at, so funding
## and pricing cannot disagree, and it reads no rarity weight, no realm curve and no unit
## price: `Crafting.resolve`'s def is asked for its worth only through the same
## `EconomyValuation` constant every other settlement path uses.
##
## ## Why it is not the SELL side, and why that is deliberate
##
## Funding at the sell price would double a shop's apparent wealth and let a player
## bankrupt the world by selling into a stall; funding at the buy price means a counter is
## worth roughly what it holds, which is the honest reading of "a merchant has stock and
## a little cash". A shop that runs out of both is a shop that refuses `shop_cannot_pay`,
## which is a game rule with teeth rather than a money printer.
static func _funding_coins(def: ShopDef) -> int:
	var coins := 0
	for row in priced_rows(def, false):
		coins += int(row["coins"])
	return maxi(0, coins)


## Put the authored baseline stock on the shelf, realized from the def's own seed.
##
## ## ONE realization per row, not one per unit — and that is the whole bug this shape fixes
##
## `ItemsApi.generate` realizes a SINGLE unit and returns null when the bag is full, so
## looping it `quantity` times spends one INVENTORY SLOT PER UNIT. `qi_refining_ore_stall`
## authors 12 + 8 + 6 = 26 units against a `capacity` of 16, so the loop filled the bag
## with 16 single-unit slots, the funding coins then had nowhere to go, and **every sale
## refused `no_room`**. The shop was unbuyable from the very directory that authored it.
##
## A stackable good is ONE batch of `quantity`, which is what `ShopDef.stock` means — a
## count, not a pile of instances — and `Inventory.add_batch` files a batch as a single slot.
## So the def is realized ONCE from `ShopDef.stock_seed(shop_id, def_id)` and the whole
## authored count is placed from that one realization. Still no rng, still reproducible, and
## a shelf of 26 units now occupies 3 slots.
##
## ## A row that does not fit is reported, not absorbed
##
## A non-stackable good (a curio, a keystone) genuinely needs one slot per unit, so a shop
## whose authored capacity cannot hold its own stock still fails — but it **shouts**, naming
## the shop, the def and the capacity, the `NpcCatalog.load_authored` "a file that will not
## load is reported, not absorbed" rule. A silent short shelf is a content bug nobody finds.
static func _stock(actor: Actor, def: ShopDef) -> void:
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return
	for row in def.stock:
		if not row is Dictionary:
			continue
		var def_id := StringName(row.get("def_id", ""))
		var quantity := int(row.get("quantity", 0))
		if def_id == &"" or quantity <= 0:
			continue
		var item_def := Crafting.resolve(def_id)
		if item_def == null:
			_warn(def, def_id, quantity, "resolves to no ItemDef")
			continue
		if item_def.stackable:
			var batch := ItemStack.from_instance(
				_realize(item_def, ShopDef.stock_seed(def.shop_id, def_id)), quantity
			)
			batch.def_ref = item_def
			if inventory.add_batch(batch) != 0:
				_warn(def, def_id, quantity, "did not fit the authored capacity")
			continue
		# **The bound is the AUTHORED row count, snapshotted before the loop**: a loop that
		# tests a container it is itself growing never terminates (INC-0002).
		for _unit in quantity:
			if (
				inventory.add_instance(_realize(item_def, ShopDef.stock_seed(def.shop_id, def_id)))
				!= 0
			):
				_warn(def, def_id, quantity, "did not fit the authored capacity")
				return


## One realized unit of `def` from `seed`, carrying the def's own rarity and realm so the
## priced row and the shelf agree. **`ItemGenerator` is `items` internals**, which is one of
## the three reasons this file lives in `app/` — the other two are `Crafting.resolve` and
## `ActorFactory.build`.
static func _realize(def: ItemDef, seed_value: int) -> ItemInstance:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var instance := ItemGenerator.generate(def, &"%s_shop" % String(def.id), rng)
	instance.def_ref = def
	return instance


## Name the shop, the def and the reason, so a short shelf is a message rather than a
## mystery. `push_warning`, never `push_error`: a too-small authored capacity is a content
## choice the author may have made, and it does not stop the shop trading what did fit.
static func _warn(def: ShopDef, def_id: StringName, quantity: int, why: String) -> void:
	push_warning(
		(
			"ShopCounter: '%s' wanted %d of '%s' but that %s"
			% [String(def.shop_id), quantity, String(def_id), why]
		)
	)


static func _fund(actor: Actor, def: ShopDef) -> void:
	var coins := _funding_coins(def)
	if coins <= 0:
		return
	ItemsApi.inventory(actor).add(Crafting.resolve(EconomyValuation.numeraire_id()), coins)


## Whether `player` could afford the cheapest thing on this shelf right now.
##
## **The PURSE, not the unit.** A player with 300 coins and a shop whose cheapest unit is
## 140 coins cannot buy anything: the shop charges the whole count, not one unit, so a
## cheaper unit price on a dearer row is not affordability. Comparing the purse to the
## minimum `sell_total` is the same comparison `MarketTransfer.price` makes, so this is a
## read of the real rule rather than a second one.
##
## `null` player is a viewer with no purse, which is false rather than an error — a panel
## asks this question before it knows whether there is a player at all.
static func _can_afford(def: ShopDef, player: Actor) -> bool:
	if player == null:
		return false
	var purse := EconomyApi.purse(player)
	var cheapest := 0
	for row in priced_rows(def, true):
		var coins := int(row["coins"])
		if coins <= 0:
			continue
		cheapest = coins if cheapest == 0 else mini(cheapest, coins)
	return cheapest > 0 and purse >= cheapest


## One priced row per AUTHORED stock entry, valued the same way [method MarketTransfer.price]
## values the very rows it is handed.
##
## ## Why this is a DELEGATE and not a second reader
##
## This used to walk `def.stock` itself: resolve the def, realize an instance from
## `ShopDef.stock_seed`, call `EconomyValuation.price_of`, then re-derive the coins from
## `MarketSpread`. Every one of those numbers was right, and it was still a second pricing
## path — one that would have drifted the moment a row rule changed, because nothing made the
## shelf and the settlement agree. They agree now because this asks `MarketTransfer.quote`
## for them, and `MarketTransfer.price` asks the same function to plan a trade's two legs.
## The shelf, the funding purse, the affordability check and the settlement are one reader.
##
## A stock row is only ever realized once per def id, from `ShopDef.stock_seed`, so the price
## here is the price of the item that is actually ON the shelf — rolled options and rarity
## included. An authored row valued against a hand-built common instance would quote a rolled
## relic at the price of a pebble, and the panel would grey out a purchase the verb then
## happily settles. Each row therefore carries its realized instance into `quote` rather than
## a bare def id, which is also why this does NOT read the minted counter: reading the counter
## would make `realize` depend on its own funding, since `_fund` prices this shelf.
static func priced_rows(def: ShopDef, shop_is_seller: bool) -> Array[Dictionary]:
	var quoted := MarketTransfer.quote(null, null, _stock_rows(def), shop_is_seller, &"")
	var out: Array[Dictionary] = []
	for row in quoted["rows"] as Array:
		(
			out
			. append(
				{
					"def_id": StringName(row["def_id"]),
					"quantity": int(row["quantity"]),
					"unit_price": int(row["unit_price"]),
					"coins": int(row["coins"]),
				}
			)
		)
	return out


## The authored stock as priced rows, each carrying the ONE realized instance it is worth.
## A row that resolves to no `ItemDef` is dropped here and reported by `_stock`, which is the
## function that shouts about a short shelf; `quote` is not the place for a content warning.
##
## ## The loop bound is SNAPSHOTTED before it starts
##
## `_stock` and `_fund` both fill bags, and a loop that tests a container it is itself growing
## does not terminate (INC-0002) — so `def.stock.size()` is read once, before the first row.
static func _stock_rows(def: ShopDef) -> Array:
	var out: Array = []
	if def == null:
		return out
	var authored: int = def.stock.size()
	for index in authored:
		if index >= def.stock.size():
			break
		var row: Dictionary = def.stock[index]
		if not row is Dictionary:
			continue
		var def_id := StringName(row.get("def_id", ""))
		var quantity := int(row.get("quantity", 0))
		if def_id == &"" or quantity <= 0:
			continue
		var item_def := Crafting.resolve(def_id)
		if item_def == null:
			continue
		var instance := _realize(item_def, ShopDef.stock_seed(def.shop_id, def_id))
		if instance == null:
			continue
		out.append({"def_id": def_id, "quantity": quantity, "instance": instance})
	return out
