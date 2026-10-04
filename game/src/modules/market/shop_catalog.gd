class_name ShopCatalog
extends RefCounted

## The authored shop catalog (ADR 0100). Reads `res://data/market/shops` the way every peer
## catalog reads its own tree — `ContentScan.files_under`, a `script_class="ShopDef"` text
## test so a `.tres` of another resource type in the same folder is skipped rather than
## mis-cast, and `load()` per file.
##
## ## Why this file exists (DEF-0218)
##
## Five authored `ShopDef` `.tres` shipped and **nothing in `game/src` read this directory**
## — only a content test did. `MarketApi.buy`/`sell` both take `shop_actor: Actor`, so the
## defs had no way to become the Actor the verbs demand and no shop could ever be found at
## runtime. A catalog is the half of the gap that is pure content lookup; [ShopCounter] is
## the half that realizes a def as that Actor, and `app/` wires both.
##
## ## Lazy `_ensure_loaded`, exactly as `SectCatalog` and `ResourceNodeCatalog` do
##
## The scan runs on first READ rather than at load. `ContentScan.files_under` walks a
## directory, which is I/O, and a module must not do that merely because a test touched a
## facade. `sect` calls `sect_ids()` and pays for one scan then and never again.
##
## ## An absent directory is empty, not a crash
##
## `ContentScan` returns nothing for a directory it cannot open, so `tools test` is runnable
## before a single `.tres` is authored. An unanswered question is an empty catalog.

## `res://data/market/shops` — the authored shop definitions.
const SHOPS_ROOT := "res://data/market/shops"
## The `script_class` a `.tres` must declare to be read as a shop.
const SHOP_SCRIPT_CLASS := "ShopDef"

static var _shared: ShopCatalog = null

var _shops: Dictionary = {}
var _loaded: bool = false


static func instance() -> ShopCatalog:
	if _shared == null:
		_shared = ShopCatalog.new()
	return _shared


## One authored shop definition, or null when the id is unknown. Null rather than a guess:
## a shop nothing defines stocks nothing and buys nothing, and inventing one would hide a
## content bug behind a working-looking stall.
func definition(shop_id: StringName) -> ShopDef:
	_ensure_loaded()
	return _shops.get(String(shop_id))


## Every authored shop id, canonically ordered. Sorted, not dictionary order, so a caller
## that walks "every shop here" gets the same answer twice — the `AuctionReadModel.lots`
## rule applied to content.
func shop_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _shops.keys():
		out.append(StringName(key))
	out.sort()
	return out


func has_definition(shop_id: StringName) -> bool:
	_ensure_loaded()
	return _shops.has(String(shop_id))


## Every shop at `location_id`, canonically ordered, or an empty array.
##
## **The `location_id` query is the whole point of the catalog.** `ShopDef.location_id` is
## authored content that differentiates a travelling merchant without a second price
## formula (ADR 0100), and until something read it a caravan authored in the spirit sea
## traded everywhere. The filter is here rather than in a caller so "which shops are in
## this room" has exactly one answer in the build.
func at_location(location_id: StringName) -> Array[ShopDef]:
	_ensure_loaded()
	var out: Array[ShopDef] = []
	for shop_id in shop_ids():
		var def := definition(shop_id)
		if def != null and def.location_id == location_id:
			out.append(def)
	return out


## Every shop as a primitive view, for a reader that wants the whole catalog in one call.
func views() -> Array:
	_ensure_loaded()
	var out: Array = []
	for shop_id in shop_ids():
		var def := definition(shop_id)
		if def != null:
			out.append(def.to_dict())
	return out


## Install a set of authored defs. The TEST seam, and deliberately not a scan: a suite
## installs exactly the shops it needs and every assertion stays independent of what content
## the build happens to ship — the `NpcCatalog.install` split, verbatim.
##
## Idempotent per id, and a duplicate is dropped rather than silently overwritten, because
## a second def answering for a first id is a content bug nobody would find.
func install(defs: Array[ShopDef]) -> void:
	for def in defs:
		if def == null or def.shop_id == &"":
			continue
		_shops[String(def.shop_id)] = def


## Test seam: drop every authored shop AND forget that the tree was ever read, so the next
## real read scans it again. Clearing `_loaded` as well as `_shops` is what makes this a
## seam rather than a one-way door.
func reset() -> void:
	_shops.clear()
	_loaded = false


## Read the authored tree once.
##
## `ContentScan` is the ONE walker every catalog uses. A local `_scan` here would be a second
## implementation with its own depth rule, which is precisely what
## `tests/arch_rules/test_no_unbounded_wait.gd` cannot see through: a recursive walk is a
## `while` in disguise, so a copy with no `MAX_DEPTH` cap is invisible to the guard that
## exists for it.
func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in _scan(SHOPS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		if not FileAccess.get_file_as_string(path).contains(
			'script_class="%s"' % SHOP_SCRIPT_CLASS
		):
			continue
		var def := load(path) as ShopDef
		if def == null or def.shop_id == &"":
			continue
		_shops[String(def.shop_id)] = def


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
