class_name ShopDef
extends Resource

## One authored shop (ADR 0100). The def is **stock and policy only** — it owns no items.
##
## ## Why a shop is an Actor and not a ledger
##
## `EconomyExchange.exchange(from, to, …)` takes two Actors and nothing else. Stock in a
## ledger keyed by shop id would force one of three failures: a second transfer
## implementation, a throwaway Actor per call, or a shop that "owns" items outside the items
## module — which `institution_claim.gd:119` explicitly refuses. So a merchant is an Actor
## carrying an `Inventory`, realized from this def on contact.
##
## ## A merchant is a role, not a class
##
## ADR 0092: a role is a `StringName` on `Actor.tags`, never a subclass. The shop's identity
## is its def id; the Actor is the container.

## The closed set of shop kinds. Content, never branched on by a price formula — exactly as
## `RoomDef.kind` decides shape and `tags` decide content.
const KINDS: Array[StringName] = [&"stall", &"trader", &"caravan", &"auction_house"]

@export var shop_id: StringName = &""
@export var display_name: String = ""
@export var kind: StringName = &"stall"

## Authored baseline stock: `[{def_id, quantity}]`. Realized on contact from a seed derived
## from `(shop_id, def_id)`, so a shop is reproducible without an rng decision at read time.
@export var stock: Array[Dictionary] = []

## Def ids this shop will BUY. Empty means it buys nothing at all, which is what makes a
## black market a content choice rather than a price modifier (ADR 0100: reactivity is
## expressed through stock and refusal, never through an index).
@export var buys: Array[StringName] = []

## Where this shop trades. Differentiates a traveling merchant without a second formula.
@export var location_id: StringName = &""

## Inventory slots a shop's stock occupies. Bounded so a large authored stock cannot become
## an unbounded Actor.
@export var capacity: int = 24


func normalized_kind() -> StringName:
	return kind if KINDS.has(kind) else KINDS[0]


## Whether this shop buys `def_id`. An empty `buys` is a shop that buys nothing — the refusal
## is authored, so a black market needs no code.
func buys_def(def_id: StringName) -> bool:
	return buys.has(def_id)


## Deterministic seed for realizing `def_id`'s stock: derived from the shop and the def, so
## the same shop always rolls the same items and a test needs no generator.
static func stock_seed(shop_id: StringName, def_id: StringName) -> int:
	return hash("%s:%s" % [String(shop_id), String(def_id)])


func to_dict() -> Dictionary:
	var rows: Array = []
	for entry in stock:
		rows.append(
			{"def_id": String(entry.get("def_id", "")), "quantity": int(entry.get("quantity", 0))}
		)
	var buy_ids: Array = []
	for def_id in buys:
		buy_ids.append(String(def_id))
	return {
		"shop_id": String(shop_id),
		"display_name": display_name,
		"kind": String(normalized_kind()),
		"stock": rows,
		"buys": buy_ids,
		"location_id": String(location_id),
		"capacity": capacity,
	}
