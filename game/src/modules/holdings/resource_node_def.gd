class_name ResourceNodeDef
extends Resource

## One authored resource node (ADR 0097): a mine, a farm, a hunting ground, a spirit vein.
## It is PLACED by a room fixture and OWNED through a holder ledger, so the two live in
## different modules on purpose.
##
## ## Why placement is not state
##
## `RoomDef.fixtures` is deep-copied per map realization by `DomainGenerator._copy_def`, so
## a fixture has no stable per-instance identity. State filed there would fork itself every
## time a domain was generated. `node_id` is the stable identity and the holder ledger is
## keyed by it, which is what lets a node outlive the actor harvesting it.
##
## ## A node pays a ledger line, never items
##
## `yield_per_period` accrues into an obligation line keyed by `node_id`, ids and counts,
## which is `InstitutionClaim.obligation`'s shape. An institution never holds a pile of
## items (BL-0191).

## The closed set of what a node is. A `kind` is CONTENT — it never branches a damage or
## price formula, exactly as `RoomDef.kind` decides the shape and `tags` decide the content.
const KINDS: Array[StringName] = [&"ore", &"herb", &"beast", &"timber", &"spirit_vein"]
const DEFAULT_KIND := &"ore"

@export var node_id: StringName = &""
@export var display_name: String = ""

## One of `KINDS`. Empty is authored as `DEFAULT_KIND`, never guessed per placement.
@export var kind: StringName = &""

## The realm band this node belongs to. **A GATE, never a multiplier.** Scaling yield by
## realm power would be a second magnitude ladder (ADR 0050); instead a deeper actor cannot
## work a shallow node at all, and pays their own realm's `work_required` for a deep one,
## which keeps a fixed yield meaningful at both ends of the 551x ladder.
@export var realm: StringName = &""

## Authored units per `period`. Deliberately fixed: see the `realm` note above.
@export var yield_per_period: int = 1

## Units charged against the holder per `period`. Upkeep is what makes a claim a decision
## rather than a free grab, and it is paid out of the same obligation ledger.
@export var upkeep_per_period: int = 0

## What a first claim costs: `{term_id: periods}` — obligation TERMS, never amounts, so
## retuning a rate never rewrites a save.
@export var claim_cost: Dictionary = {}

## Periods of yield before the node rests. Zero is inexhaustible, which is authored as
## authored rather than as a large number.
@export var depletion: int = 0

## How many resource nodes a holder must ALREADY hold before this one opens to them
## (ADR 0248). A claim without one would let a first-day hero walk onto the deepest vein
## in the corpus.
##
## **A count of ground, never a standing.** It used to read the owner ref's `standing`,
## which a `{kind, id}` ref does not carry, so every authored value above 0 refused
## forever; and there is no actor-global `standing` in this repo to have read instead —
## every one belongs to a single institution's capped ledger, and a resource node has no
## business naming an institution. The gate is now answered from the holdings ledger, so
## it is satisfiable, kind-agnostic and free of a module edge. Zero is authored as zero
## and means "anyone may take this".
@export var claim_floor: int = 0


func normalized_kind() -> StringName:
	return kind if KINDS.has(kind) else DEFAULT_KIND


## Whether this node's realm band is one `actor` may work, read as an ordinal comparison on
## the shared ladder. An actor with no path is refused rather than assumed, because a node
## that answers to anyone is a node with no gate.
func permits(actor_realm: StringName) -> bool:
	if realm == &"" or actor_realm == &"":
		return false
	var ladder := RealmDefaults.ladder()
	var needed := ladder.index_of(realm)
	var held := ladder.index_of(actor_realm)
	if needed < 0 or held < 0:
		return false
	return held >= needed


func to_dict() -> Dictionary:
	var cost := {}
	for term in claim_cost.keys():
		cost[String(term)] = int(claim_cost[term])
	return {
		"node_id": String(node_id),
		"display_name": display_name,
		"kind": String(normalized_kind()),
		"realm": String(realm),
		"yield_per_period": yield_per_period,
		"upkeep_per_period": upkeep_per_period,
		"claim_cost": cost,
		"depletion": depletion,
		"claim_floor": claim_floor,
	}


static func from_dict(data: Dictionary) -> ResourceNodeDef:
	var node := ResourceNodeDef.new()
	node.node_id = StringName(data.get("node_id", ""))
	node.display_name = String(data.get("display_name", ""))
	node.kind = StringName(data.get("kind", ""))
	node.realm = StringName(data.get("realm", ""))
	node.yield_per_period = maxi(0, int(data.get("yield_per_period", 0)))
	node.upkeep_per_period = maxi(0, int(data.get("upkeep_per_period", 0)))
	node.depletion = maxi(0, int(data.get("depletion", 0)))
	node.claim_floor = maxi(0, int(data.get("claim_floor", 0)))
	var cost = data.get("claim_cost", {})
	if cost is Dictionary:
		for term in (cost as Dictionary).keys():
			node.claim_cost[StringName(term)] = int((cost as Dictionary)[term])
	return node
