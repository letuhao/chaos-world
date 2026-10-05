class_name HoldingsState
extends RefCounted

## The holder ledger for resource nodes (ADR 0097).
##
## ## Why the ledger, and why `actor.module_data`
##
## A node's state is a WORLD fact, but this repo has already refused world-object
## persistence: `DomainApi` keeps a map under `actor.module_data["domain_run"]` and erases
## it on leave, keeping only `discovered`. There is no file-backed world store
## (`ItemStateStore` is items-only). So the first slice persists under the player actor and
## **records the gap** rather than inventing a second store — the same discipline ADR 0083
## used when it disclosed its own.
##
## ## Yield is a ledger line, never items
##
## `line[node_id]` holds units owed, which is `InstitutionClaim.obligation`'s shape: ids and
## counts, never a pile of goods. An institution that held items would make a second
## authority for what it owns (BL-0191).
##
## ## Three states, never two
##
## A node that exists with no holder is `{"vacant": true}` (ADR 0083). `{}` means the
## `node_id` is not a node at all. A holder that is present but contested carries a
## `challenger` row and an **unchanged** `holder` — that invariant is the whole difference
## between a claim and a conquest (ADR 0085).

const MODULE_KEY := &"holdings_state"
const SCHEMA_VERSION := 1

## The refusal reasons. Every one is a named game rule (ADR 0084's shape), never free text.
const UNKNOWN_NODE := "unknown_node"
const ALREADY_HELD := "already_held"
const NO_HOLDER := "no_holder"
const HOLDER_MISMATCH := "holder_mismatch"
## The holder does not yet hold `claim_floor` nodes (ADR 0248). The rule kept its name
## when what it counts changed from a standing to a count of ground already held — the
## refusal is still "your claim is under the floor", never "your standing is too low".
const CLAIM_BELOW_FLOOR := "claim_below_floor"
const CLAIM_COST_UNPAID := "claim_cost_unpaid"
const CANNOT_RELEASE_FOREIGN := "cannot_release_foreign"
const NO_PERIODS := "no_periods"
const NODE_RESTING := "node_resting"
const DEPLETED := "depleted"
const REALM_BELOW_GATE := "realm_below_gate"
const ALREADY_CONTESTED := "already_contested"
const NOT_A_CHALLENGER := "not_a_challenger"
const NO_RESOLVER := "no_resolver"
const UNKNOWN_OWNER_KIND := OwnerRef.UNKNOWN_KIND
const UNKNOWN_OWNER := "unknown_owner"


## The ledger skeleton, authored in exactly one place so a new key cannot be half-written.
## String keys throughout and no `StringName` anywhere: `Actor.to_dict` converts only the
## OUTER `module_data` key (ADR 0027).
static func empty() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"nodes": {},
		"contested": {},
		"line": {},
	}


## Fold any payload into the current shape. Coerces on the way in and drops an entry whose
## owner no longer parses, because a node that names a holder kind the game does not have
## can never be resolved and would sit in a ledger forever.
static func normalize(data: Variant) -> Dictionary:
	var out := empty()
	if not data is Dictionary:
		return out
	var source := data as Dictionary
	# ## A version from a NEWER build is carried through, not stamped down
	#
	# `empty()` above stamped THIS build's number, and normalize used to leave it there — so
	# a ledger authored at a higher `SCHEMA_VERSION` was silently re-stamped as this build's
	# own. The newer build's ledger then read as compatible here, and the next autosave wrote
	# it back missing whatever the newer build had moved. Carrying the number is what lets
	# `WorldLedgerStore` refuse it by name instead (`future_schema`).
	#
	# Only the FUTURE half travels: an older version is re-normalized onto the current shape,
	# which is the whole migration story and belongs here rather than at the store.
	var stamped := int(source.get("version", 0))
	if stamped > SCHEMA_VERSION:
		out["version"] = stamped
	var nodes = source.get("nodes", {})
	if nodes is Dictionary:
		for node_id in (nodes as Dictionary).keys():
			var entry = (nodes as Dictionary)[node_id]
			if not entry is Dictionary:
				continue
			var ref := OwnerRef.from_dict((entry as Dictionary).get("owner", {}))
			if ref.is_empty():
				# An absent holder is written back as the explicit VACANT marker, never as
				# `{}`: `{}` means "not a node at all" (ADR 0083), and collapsing the two is
				# what makes an unclaimed vein look like a vein that does not exist.
				out["nodes"][String(node_id)] = {
					"owner": OwnerRef.vacant(),
					"condition": maxi(0, int((entry as Dictionary).get("condition", 0))),
					"resting": maxi(0, int((entry as Dictionary).get("resting", 0))),
				}
				continue
			out["nodes"][String(node_id)] = {
				"owner": ref.to_dict(),
				"condition": maxi(0, int((entry as Dictionary).get("condition", 0))),
				"resting": maxi(0, int((entry as Dictionary).get("resting", 0))),
			}
	var contested = source.get("contested", {})
	if contested is Dictionary:
		for conflict_id in (contested as Dictionary).keys():
			var row = (contested as Dictionary)[conflict_id]
			if row is Dictionary:
				out["contested"][String(conflict_id)] = (row as Dictionary).duplicate(true)
	var line = source.get("line", {})
	if line is Dictionary:
		for node_id in (line as Dictionary).keys():
			out["line"][String(node_id)] = maxi(0, int((line as Dictionary)[node_id]))
	return out


## The holder of `node_id`, or `{}` when the node is not in the ledger at all.
static func holder(state: Dictionary, node_id: StringName) -> Dictionary:
	var entry = (state["nodes"] as Dictionary).get(String(node_id))
	if not entry is Dictionary:
		return {}
	return (entry as Dictionary).get("owner", {}) as Dictionary


## Whether `node_id` exists but is unheld — the `{"vacant": true}` state.
static func is_vacant(state: Dictionary, node_id: StringName) -> bool:
	return (
		(state["nodes"] as Dictionary).has(String(node_id))
		and OwnerRef.is_vacant(holder(state, node_id))
	)


## Whether `node_id` is known at all. Distinct from vacant: `{}` is not a node, `vacant` is
## a node with no holder.
static func knows(state: Dictionary, node_id: StringName) -> bool:
	return (state["nodes"] as Dictionary).has(String(node_id))


## The condition left on `node_id`, or `0` when unknown. Condition is what depletion spends.
static func condition(state: Dictionary, node_id: StringName) -> int:
	var entry = (state["nodes"] as Dictionary).get(String(node_id))
	if not entry is Dictionary:
		return 0
	return int((entry as Dictionary).get("condition", 0))


## The yield `node_id` has paid into `line`, in units. Always non-negative.
static func accrued(state: Dictionary, node_id: StringName) -> int:
	return int((state["line"] as Dictionary).get(String(node_id), 0))


## Add `units` to the accrued line for `node_id`, clamped at zero. Returns the amount that
## actually landed, so a caller can publish how much of a request was accepted rather than
## assuming all of it.
static func accrue(state: Dictionary, node_id: StringName, units: int) -> int:
	var key := String(node_id)
	var before := int((state["line"] as Dictionary).get(key, 0))
	var after := maxi(0, before + units)
	state["line"][key] = after
	return after - before


## Spend the accrued line — the settlement verb, called by whoever consumes the yield.
## All-or-nothing: a line that cannot cover `units` settles nothing.
static func settle(state: Dictionary, node_id: StringName, units: int) -> int:
	var key := String(node_id)
	var owed := int((state["line"] as Dictionary).get(key, 0))
	if units <= 0 or owed < units:
		return 0
	state["line"][key] = owed - units
	return units


## The challenge on `node_id`, or `{}` when it is not contested. The `holder` is untouched
## while a row exists here — that is ADR 0085's invariant, and the reason a claim opens a
## standoff instead of flipping a flag.
static func contest(state: Dictionary, node_id: StringName) -> Dictionary:
	var entry = (state["contested"] as Dictionary).get(String(node_id))
	return (entry as Dictionary) if entry is Dictionary else {}


## Record one challenge row against `node_id`, keyed by `conflict_id`. Refuses to overwrite
## an existing challenge: two open standoffs on one node would leave two rival prizes and no
## way to say which one pays.
static func contest_node(
	state: Dictionary, node_id: StringName, conflict_id: StringName, challenger: Dictionary
) -> Dictionary:
	var key := String(node_id)
	if (state["contested"] as Dictionary).has(key):
		return {"ok": false, "reason": ALREADY_CONTESTED}
	if challenger.is_empty():
		return {"ok": false, "reason": NOT_A_CHALLENGER}
	state["contested"][key] = {
		"conflict_id": String(conflict_id),
		"challenger": challenger.duplicate(true),
	}
	return {"ok": true, "reason": "", "conflict_id": String(conflict_id)}


## Clear the challenge on `node_id`, returning the row that was there so a caller can read
## what it just closed.
static func resolve_contest(state: Dictionary, node_id: StringName) -> Dictionary:
	var row := contest(state, node_id)
	(state["contested"] as Dictionary).erase(String(node_id))
	return row
