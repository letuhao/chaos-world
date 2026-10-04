class_name EconomyBoot
extends RefCounted

## The composition root's economy wiring (ADR 0094, ADR 0097, ADR 0100, ADR 0101,
## ADR 0104). Wiring, not rules: `app/` attaches the four ledgers, injects the three
## stores, the one shared owner resolver and the constructor that mints a captive, and the
## granter that turns a foraged unit into an item. Every module keeps owning what its
## numbers mean.
##
## ## Why this file exists
##
## Five modules shipped, each tested, each **completely unwired** — and the shape of the
## unwiring was the same in all five. Every one of them had a seam (`set_store`,
## `set_resolver`, `set_minter`, `set_granter`) with ZERO production callers, so:
##
##   - a holder's resource node lived in the holder's own `module_data`, so a rival read
##     a held node as vacant and conquered it outright (ADR 0097);
##   - the market floor and the auction lots were invisible to anybody but the dropper, so
##     `take` refused `no_such_drop` for anything anybody else left (ADR 0100);
##   - a custody claim was invisible across actors, so a transfer refused
##     `no_such_claim` for a claim someone else took (ADR 0104);
##   - an institution claim refused `no_resolver` on BOTH ledgers, so a clan, a sect or a
##     nation could hold nothing at all;
##   - a foraged unit could never become an item, so the `gather` acquisition source had
##     no verb behind it and `ItemSources.KINDS` had to mark it unshipped.
##
## That is the same failure ADR 0074 measured for npcs and ADR 0089 for statuses: a feature
## nobody can start is decoration. This is the `NpcBoot`/`DomainBoot`/`CombatBoot` shape,
## and it is deliberately wiring-only — no rules, no state of its own, nothing that ticks.
##
## ## One clock, no clock of its own
##
## Nothing here ticks. `app/` already owns the single time wire (`WorldPulse.pull`, fed by
## the one `_process` in `item_workbench_app.gd`), and `HoldingsApi.accrue`,
## `MarketApi.settle` and `CustodyApi.settle_term` all take an explicit `periods` from a
## caller that owns time (DEF-0111). A boot that advanced them would be a second source of
## truth for when a save happened.
##
## ## Idempotent, so it is meant to be called twice
##
## Every `attach` is idempotent and every setter is a plain assignment, so calling this on
## boot and again after a save load is the intended usage rather than a mistake. The
## report says so, and `install(null)` refuses by name rather than dereferencing nothing.

## The name of the installed owner resolver, so a report can name what was wired rather
## than handing a caller a `Callable` it has to introspect.
const RESOLVER := "OwnerResolver.resolve"
## The name of the injected constructor for a captive's live body (ADR 0104).
const MINTER := "ActorFactory.spawn_npc"

## `true` on the booleans rather than the object, so a caller is never handed a module type
## it has to downcast — the same primitives-only rule every other facade answer follows.
const _BOUND := true


## Install every economy-module seam and report what each one did.
##
## `{ok, bound, attached, store, resolver, minter, granter, shops, standing, reason}` — one
## call, one answer, and no caller has to reach into a module to find out whether it is
## wired.
##
## ## The attach order is the order the modules depend on each other
##
## `economy` first, because `market` and `custody` both settle through `EconomyApi.trade`
## and a market floor that settles before the trade ledger exists prices against a purse
## nothing has recorded. Then `market`, `holdings` and `custody`: the three that share the
## resolver, in the order they were built. `forage` attaches nothing — it has no ledger of
## its own — so it is last, because it is the one seam that depends on a module being
## complete before it can answer.
##
## ## Idempotent by construction
##
## `attach` normalizes, the setters assign, and the resolver is a bare static-function
## reference rather than a lambda — the form `NpcBoot` documents at length, because a typed
## lambda calling another script's static function killed the process with an access
## violation on the shell's first frame with nothing in the log.
static func install(actor: Actor) -> Dictionary:
	if actor == null:
		return {
			"ok": false,
			"bound": false,
			"attached": [],
			"store": false,
			"resolver": false,
			"minter": false,
			"granter": false,
			"shops": false,
			"standing": false,
			"reason": "no_actor",
		}
	EconomyApi.attach(actor)
	MarketApi.attach(actor)
	HoldingsApi.attach(actor)
	CustodyApi.attach(actor)
	# **AFTER every attach**, and for the same reason `item_workbench_app._build_actor`
	# binds its seams at `:289`: a seam is only correct if the module it wires is already
	# complete.
	var store: bool = _install_stores()
	var resolver: bool = _install_resolver()
	var minter: bool = _install_minter()
	var granter: bool = _install_granter()
	# **Content and the subscriber come last**, and both are `app/`-only for the same
	# reason the resolver is here: neither `market` nor `social` may name the other, and
	# `app/` is the one layer allowed to know both. `ShopCatalog` reads the five authored
	# `ShopDef` files nothing else read (DEF-0218) and `AuctionStanding` is the subscriber
	# ADR 0102 promises for the four auction signals (DEF-0217). Both are idempotent — a
	# lazy one-shot scan and a set of `is_connected`-guarded connects — so a boot and a
	# re-install after a save load cost a directory walk's absence rather than a rescan and
	# a duplicated handler.
	var shops: bool = _install_shops()
	var standing: bool = _install_standing(actor)
	return {
		"ok": store and resolver and minter and granter and shops and standing,
		"bound": _BOUND,
		"attached": ["economy", "market", "holdings", "custody"],
		"store": store,
		"resolver": resolver,
		"minter": minter,
		"granter": granter,
		"shops": shops,
		"standing": standing,
		"reason":
		(
			""
			if (store and resolver and minter and granter and shops and standing)
			else "seam_not_installed"
		),
	}


## ## Three stores, ONE world — and this is not duplication
##
## `HoldingsApi`, `MarketApi` and `CustodyApi` all take an object with
## `read_ledger()`/`write_ledger()`, and the ONE world those three share is this boot: every
## actor in the process now reads and writes the same three ledgers, so a rival sees a
## held vein, a taker sees a drop and a new holder sees a claim. That is ADR 0101's whole
## answer to "a world fact kept per actor is a correctness bug, not a simplification".
##
## **The three instances are separate, and they MUST be.** Each store re-normalizes with its
## OWN state class on the way in and out: `WorldLedger` with `HoldingsState.normalize`,
## `MarketWorldLedger` with `MarketState.normalize`, `CustodyWorldLedger` with
## `CustodyState.normalize`. Those normalizers are not interchangeable — a holdings ledger
## has no `floor`, a `lots` or a `claims` container, so `MarketState.normalize` reading one
## **silently drops the floor and every open lot**, and the ledger the market then writes
## back is an empty one. The failure is silent, total and invisible in a single-actor test,
## which is exactly how ADR 0101 found the original bug. They are three objects because
## three modules own three ledgers; `app/` wires them together, it does not merge them.
static func _install_stores() -> bool:
	HoldingsApi.set_store(WorldLedger.new())
	MarketApi.set_store(MarketWorldLedger.new())
	CustodyApi.set_store(CustodyWorldLedger.new())
	return true


## ## One resolver, two consumers, because the contract is identical
##
## `HoldingsApi.set_resolver` and `CustodyApi.set_resolver` take the same
## `(kind, id) -> {ok, reason}` callable and answer the same question — does this `OwnerRef`
## name a real holder in this build. `OwnerResolver.resolve` is installed into BOTH, so a
## sect that may hold a node may also take a captive, and a fix to one cannot drift from
## the other.
##
## `app/` is the only layer allowed to name four institution modules at once (ADR 0002,
## dependency inversion), which is why the resolver is here and not inside either module.
static func _install_resolver() -> bool:
	HoldingsApi.set_resolver(OwnerResolver.resolve)
	CustodyApi.set_resolver(OwnerResolver.resolve)
	return OwnerResolver.resolve.is_valid()


## ## The minter a claim's subject is minted through
##
## ADR 0104 says a live subject is minted on demand through the same injected-`Callable`
## seam `NpcApi.set_minter` already uses, so `custody` keeps no `npc` edge and no stat
## provider graph.
##
## ## Why this is an adapter and not `ActorFactory.spawn_npc` handed over bare
##
## The instruction this file implements says "wire `CustodyApi.set_minter
## (ActorFactory.spawn_npc)`", and it is right about the SEAM — but that exact Callable
## does not fit the call, because the two signatures disagree:
##
##   - `spawn_npc(npc_def: NpcDef = null, role, rank_id, base)` takes an **`NpcDef`**;
##   - `CustodyApi.subject` has a **subject def ID**, a plain `String`, because ADR 0104
##     stores an id and never a resource.
##
## Handing the bare constructor across is an invalid-type error at the call, which is
## "a null injection fails loudly" one level below the thing it protects. So the SEAM is
## still an injected `Callable` and the module still names no concrete type — the
## composition root simply supplies the one function that speaks both vocabularies, which
## is the entire job of this layer.
##
## ## And why the adapter is a static function rather than a lambda
##
## `NpcBoot.install` and `DomainBoot.install` both hand over a bare static-function
## reference, and both document the same reason: a typed lambda whose body calls another
## script's static function killed the process with an access violation on the shell's
## first frame, with nothing in the log. This is that shape, not a closure over one.
##
## ## The catalog lookup lives HERE, not in `custody`
##
## `registry.json` gives `custody` `["contracts", "core", "economy"]` and no `npc`, so
## resolving a subject id against `NpcCatalog` from inside the module would be an
## **undeclared dependency** the boundary checker fails on. `app/` may name any concrete
## type by construction, so the edge is legal here and nowhere else — ADR 0002's dependency
## inversion, enforced rather than asserted.
static func _install_minter() -> bool:
	CustodyApi.set_minter(EconomyBoot._subject_minter)
	return CustodyApi.has_minter()


## The granter a forage settles through — the fourth seam in this file, and the one that
## makes `gather` a real route instead of a flag.
##
## `forage` owns the harvest RULE and deliberately declares no `items` edge: `ItemsApi` sits
## at its twelve-method cap so no def-resolution verb can be added to it, `Crafting.resolve`
## is `items` internals that only `app/` may name, and `holdings` may not name `ItemsApi` at
## all. So the conversion arrives through the injected-`Callable` seam this file has already
## installed three times, and `ForageGranary` is the adapter — the same
## "the SEAM is right, the SIGNATURES disagree" situation `_install_minter` documents for
## the captive minter.
##
## **Before this seam existed the gather route had no verb behind it at all.** Sixteen nodes
## were authored and `ItemSources.KINDS` marked `gather` unshipped, because nothing in
## `game/src` knew which item a node produced: `ResourceNodeDef` carries no item id and
## cannot be given one. Installing the granter is what makes `is_shipped(KIND_GATHER)` a
## claim about shipping code rather than a hope.
static func _install_granter() -> bool:
	ForageApi.set_granter(ForageGranary.deliver)
	return ForageApi.has_granter()


## Read the authored shop content — the fifth seam, and the only one that is CONTENT.
##
## ## Why a boot line at all, when the catalog is lazy
##
## `ShopCatalog._ensure_loaded` scans on first read, exactly as `SectCatalog` and
## `ResourceNodeCatalog` do, so nothing here is required for the scan to happen. What the
## line **does** is make the boot the first reader, which is the difference between a shop
## being found when a player walks into a market row and being found when some panel
## happens to read a catalog first. `NpcBoot.install` states the same reason in full:
## "the cast is CONTENT, and it is read here … so a new cast member is a `.tres` and never
## a code edit".
##
## ## And it is what makes DEF-0218's inventory honest
##
## Five `ShopDef` files shipped and **nothing in `game/src` read the directory** — only
## `tests/modules/market/test_economy_content.gd` did, so no shop could ever be found at
## runtime. `NpcCatalog`'s own docstring records the identical failure for npcs (BL-0626:
## "`NpcApi.spawn` refused every id … and a player could meet nobody"), and this is the
## same line in the same place for the same reason.
##
## **The scan is not run here.** `shop_ids()` is the read, and it walks the tree once. A
## boot that counted the files itself would be a second scan and a second answer.
static func _install_shops() -> bool:
	ShopCatalog.instance().shop_ids()
	return true


## Connect the auction event contract to its social bridge — the sixth seam, and the one
## that closes ADR 0102's promise that the four auction signals reach `SocialApi.apply_cause`
## through `app/` (DEF-0217).
##
## ## Why this is here and not inside `market`
##
## `market` declares `["contracts", "core", "economy", "items"]` and may not name `social`;
## ADR 0093's inversion says the observer registers with the subject and the module names
## no consumer. `NpcBoot._install_event_seams` is the identical precedent, and this is the
## same function with a different bus — including the bare static `Callable` rather than a
## lambda, for the access-violation reason `install` documents.
##
## ## And why `MarketApi` grew no `events()` accessor
##
## It publishes exactly `rules.MAX_FACADE_PUBLIC_METHODS` public methods, so a thirteenth
## fails `tools arch`. `AuctionEvents.shared()` is the door instead — the contract owns the
## singleton, which `contracts/` may do because it is the leaf layer, and which
## `AuctionReadModel`'s own docstring already relies on.
##
## **True means every connect was ALREADY in place**, so a caller can tell a fresh wiring
## from a no-op re-install after a load. `actor` is recorded so a lot naming the player can
## resolve to a live body; a party this process holds no body for is skipped by name in
## `AuctionLedger`, never dropped.
static func _install_standing(actor: Actor) -> bool:
	return AuctionStanding.install(actor)


## Mint a live body for a subject def id, through `ActorFactory.spawn_npc`.
##
## The def is passed when it is AUTHORED and `null` when it is not, because `spawn_npc`'s
## own contract says a null def "mints a plain actor at the supplied realm". That is the
## right answer for a captive rather than an error: a claim names an id, the body is
## borrowed for the moment it is displayed, and a subject this build ships no individual for
## is still a body instead of a null the caller cannot tell apart from an unwired seam.
static func _subject_minter(subject_id: String) -> Actor:
	return ActorFactory.spawn_npc(NpcCatalog.instance().definition(StringName(subject_id)))
