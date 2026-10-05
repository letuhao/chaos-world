class_name NpcRosterBridge
extends RefCounted

## The injected view of "who is in the room the player is actually standing in".
##
## ## Why this exists, and why it is not `NpcApi` called directly
##
## `npc` is **not** in `rules.UI_MODULES` and `world_spawn` is not either, so
## `tools/arch` refuses a `ui/` file that names `NpcApi` or `WorldSpawnApi` at all —
## and `app/` is a `PRIVATE_UNIT`, so a panel may not name `NpcBoot` either. Every
## other surface that needed an undeclared module got a bridge: `LootBridge` for the
## loot module, `WorldPulseBridge` for the world's clock, `DomainBridge` for the whole
## domain program. This is the same door for the settlement roster.
##
## ## One slot, and the reason it is one
##
## The panel does not get `location_id` and `cast` as two independent reads. It gets
## ONE verb, and that verb answers the place and the cast **for that exact place** in a
## single dictionary. That is the whole honesty guarantee of DEF-0261: a panel that held
## a location and then re-read presence on its own could pair the room it was told with
## a cast read at a different moment, and the stale-cast panel would be one refactor
## away. There is no seam on which that mistake can be written.
##
## ## Nothing here is cached, and nothing here is a second copy of a truth
##
## The callables forward to `NpcBoot.where_is`, which reads `world_spawn`'s own durable
## ledger on every call. A bridge that held the last answer would be a second copy of
## the location, and the panel would be showing yesterday's room for exactly as long as
## nobody refreshed it.
##
## ## An unwired bridge reads as "no roster", not as a crash
##
## [method read_room_roster] returns `{}` when the composition root filled nothing. The
## panel then says so on the row — a missing seam is visible to the player rather than
## being a blank list they read as "nobody is here".
##
## ## WHY A STATIC SLOT RATHER THAN A ROUTE-BINDING ARM
##
## Every other bridge here is handed to a screen by `item_workbench_app.gd`'s
## `_bind_route_screen`, one `match` arm per route. That file is mid-refactor by another
## agent and read-only for this change, so the roster could not have been bound there
## without either editing it or shipping a panel nothing ever fills — which is the
## unrouted, unwired surface `tests/app/test_screen_reachability.gd` exists to catch.
##
## So the injection is the OTHER idiom this repo already ships three times
## ([code]NpcApi.set_minter[/code], [code]HoldingsApi.set_store[/code],
## [code]Tribulation.set_preparation_credit[/code]): a [code]static var Callable[/code]
## the composition root fills. [code]NpcBoot.install[/code] fills it — the one seam that
## runs before anything can spawn and that re-runs on a fresh boot, a restore AND a
## rebirth, so the roster is live on all three paths rather than only the one a
## route-bind would have covered.
##
## **A LIST would be safer still, but one reader is the whole world here.** There is one
## composition root and one player, and a duplicate install is REFUSED rather than
## last-install-wins — so a second root in the same process cannot silently take the seam
## away from the first, which is exactly the hazard `WorldFact.subscribe` documents for
## its own list of subscribers.

## `NpcBoot.where_is(actor)` -> Dictionary. The tracked current room AND the presence
## for that room, in one read: `{has_actor, location_id, display_name, located, here}`.

## The reader the composition root installed. Empty until `NpcBoot.install` runs, and
## private because [method install_room_reader] is the only legal way to fill it.
static var _reader: Callable = Callable()
var read_room: Callable


## Hand the roster reader over. Called by `NpcBoot.install`; refused when the reader is
## already installed, so a second root cannot take the seam away from the first.
##
## An empty callable CLEARS the seam and answers true, which is how a test un-installs
## it deterministically rather than by overwriting it.
static func install_room_reader(reader: Callable) -> bool:
	if reader.is_null():
		_reader = Callable()
		return true
	if _reader.is_valid():
		return false
	_reader = reader
	return true


## Whether a roster reader is installed. Published so a test can tell a MISSING seam
## from a reader that installed and then answered nothing.
static func has_room_reader() -> bool:
	return _reader.is_valid()


## Remove the installed reader, and answer whether there was one. Idempotent: removing
## what is not installed is not an error.
static func clear_room_reader() -> bool:
	var held := _reader.is_valid()
	_reader = Callable()
	return held


## A bridge over whatever reader is installed. A NEW instance per call and no cached
## answer inside it, so no caller can be holding yesterday's room.
static func shared() -> NpcRosterBridge:
	var seam := NpcRosterBridge.new()
	seam.read_room = _reader
	return seam


## Whether this bridge is wired to anything. A panel reads this to decide whether its
## roster row is a real answer or a missing seam.
func wired() -> bool:
	return read_room.is_valid()


## The player standing where they are standing, and who is there with them. `{}` when
## nothing filled this bridge, so a caller never null-checks it.
##
## ## An unwired callable and a wired one answering `{}` are the SAME thing here
##
## Both mean "no roster can be shown", and both are reported by the panel as a missing
## seam. A screen that rendered an empty list for an unwired bridge would be showing the
## player a room with nobody in it — a false statement — so the two are collapsed here
## on purpose.
func read_room_roster(actor: Actor) -> Dictionary:
	if not wired():
		return {}
	var result: Variant = read_room.bindv([actor]).call()
	return result as Dictionary if result is Dictionary else {}


## The wiring itself, as primitives, so a test can assert the SEAM rather than infer it
## from a roster that quietly rendered empty.
func summary() -> Dictionary:
	return {"wired": wired(), "actions": ["read_room"]}
