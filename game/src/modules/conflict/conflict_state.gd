class_name ConflictState
extends RefCounted

## The standoff ledger for a contested resource node (ADR 0085, ADR 0245).
##
## ## A standoff is a DECLARATION, not a fight
##
## One row per contested node, carrying the two sides, the **declared prize** and a verdict
## quota. There is no `army_strength`, no `territory_defense`, no hit points and no unit count:
## ADR 0085 refuses a second magnitude ladder beside `realm_power_table.tres`, and the module
## that owns a war may own no number at all. The only arithmetic this ledger supports is
## `verdicts + 1` against `quota`.
##
## ## Why a WORLD fact
##
## A standoff belongs to no actor: the holder, the challenger and the caller that runs the
## verdict are three different bodies, and ADR 0101 records what happens when a world fact lives
## in one of them — two actors keep two copies, a rival reads held ground as vacant, and the
## conquest ADR 0085 forbids happens silently while every single-actor test passes. So the
## ledger lives in an injected store and `attach` mirrors it onto the actor for the save only.
##
## ## Three states, never two (ADR 0083)
##
## A node with no standoff is `{}` — it is not a conflict. A node with an OPEN standoff carries
## the row and leaves `HoldingsState.holder` byte-identical. A node whose standoff was paid is
## absent again: the prize landed, and there is nothing left to announce. `{}` therefore means
## both "never declared" and "already resolved", which is why `resolved` is recorded as a
## CLOSED row rather than an erase: a second resolution must refuse by name, and a delete could
## not refuse anything.
##
## ## String keys throughout, no `StringName` anywhere
##
## `Actor.to_dict` converts only the OUTER `module_data` key (ADR 0027), so an inner `StringName`
## reaches the save untouched and breaks every round trip.

const MODULE_KEY := &"conflict_state"
const SCHEMA_VERSION := 1

## The ceiling on tracked standoffs, so a ledger cannot grow without bound.
const MAX_STANDOFFS := 32

## The refusal reasons. Every one is a named game rule (ADR 0084), never free text, and each is
## a string a panel can render as written.
const UNKNOWN_NODE := "unknown_node"
const NO_CONTEST := "no_contest"
const NO_CHALLENGER := "no_challenger"
const UNDECLARED_PRIZE := "undeclared_prize"
const UNKNOWN_SIDE := "unknown_side"
const ALREADY_RESOLVED := "already_resolved"
const QUOTA_UNMET := "quota_unmet"
const BAD_QUOTA := "bad_quota"
const TOO_MANY := "too_many_standoffs"
const STANDOFF_CLOSED := "standoff_closed"

## The closed prize vocabulary. A prize outside it is refused `undeclared_prize` rather than
## resolved to the strongest shape on the list, because ADR 0085's one prohibition is a
## resolution that quietly invents what was at stake.
const PRIZES: Array[StringName] = [&"ownership", &"recognition", &"tribute"]

## The default quota, and the floor and ceiling a declaration may set. A quota of one verdict
## is a tribunal; a quota above the ceiling is a war no verdict sequence in this program can
## produce, so it refuses rather than storing a standoff that can never close.
const DEFAULT_QUOTA := 1
const MAX_QUOTA := 5


## The ledger skeleton, authored in exactly one place so a new key cannot be half-written.
static func empty() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"standoffs": {},
	}


## Fold any payload into the current shape. Coerces on the way in, drops a row whose prize is
## not in the closed vocabulary, and drops a row whose sides no longer name anybody: a standoff
## whose winner could not be identified can never be paid and would sit in a ledger forever.
static func normalize(data: Variant) -> Dictionary:
	var out := empty()
	if not data is Dictionary:
		return out
	var source := data as Dictionary
	# A version from a NEWER build is carried through, not stamped down (ADR 0101's rule,
	# shared by every world ledger in this program), so a store can refuse it by name.
	var stamped := int(source.get("version", 0))
	if stamped > SCHEMA_VERSION:
		out["version"] = stamped
	var standoffs = source.get("standoffs", {})
	if not standoffs is Dictionary:
		return out
	var rows: Dictionary = standoffs as Dictionary
	# Snapshot the bound BEFORE the walk: this loop writes into a different container, and a
	# loop that tested a container it is itself growing never terminates (INC-0002).
	var keys: Array = rows.keys()
	for node_id in keys:
		var row = rows[node_id]
		if not row is Dictionary:
			continue
		var normalized := _normalize_row(row as Dictionary)
		if normalized.is_empty():
			continue
		out["standoffs"][String(node_id)] = normalized
	return out


## One standoff row in its current shape, or `{}` when the row is unusable. Written as a
## function rather than inline in `normalize` so the shape is authored in exactly one place.
static func _normalize_row(row: Dictionary) -> Dictionary:
	var prize: Variant = row.get("prize", {})
	if not prize is Dictionary:
		return {}
	var kind := StringName((prize as Dictionary).get("prize", ""))
	if not PRIZES.has(kind):
		return {}
	var holder := _side(row.get("holder", {}))
	var challenger := _side(row.get("challenger", {}))
	if holder.is_empty() or challenger.is_empty():
		return {}
	# `clampi`, NOT `maxi`/`mini`: a GDScript global like `maxi` takes a Variant and returns
	# one, so writing an int through it round-trips as a FLOAT — which is how `quota: 2`
	# becomes `2.0` and a JSON round trip stops being byte-identical. The JSON safety test
	# caught it, and it is the kind of drift that would otherwise sit here forever.
	var quota: int = clampi(int(row.get("quota", DEFAULT_QUOTA)), 1, MAX_QUOTA)
	var paid := (
		row.get("resolved", {}) is Dictionary
		and not (row.get("resolved", {}) as Dictionary).is_empty()
	)
	# The prize is rebuilt key by key rather than duplicated: a declared prize carries its
	# `prize` as a `StringName`, and `Actor.to_dict` converts only the OUTER `module_data` key,
	# so an inner `StringName` would reach the save untouched (ADR 0027).
	return {
		"conflict_id": String(row.get("conflict_id", "")),
		"holder": holder,
		"challenger": challenger,
		# The DECLARED prize, verbatim, and never recomputed for display or for payment.
		"prize": _prize_out(prize as Dictionary),
		"quota": quota,
		# `verdicts`, like `quota`, is written with `maxi` NOT because it needs clamping —
		# it does not — but because `maxi` takes a `Variant` and returns one, so a `0` written
		# through it is a FLOAT the moment it lands in the dictionary. `int(...)` around it is
		# what keeps an int an int, and an int is what makes `JSON.stringify` emit `0` rather
		# than `0.0`. See `quota` above and ADR 0027: only the OUTER `module_data` key is
		# converted on the way to a save, so a float down here survives into the file.
		"verdicts": int(maxi(0, int(row.get("verdicts", 0)))),
		"last_winner_id": String(row.get("last_winner_id", "")),
		"resolved": (row.get("resolved", {}) as Dictionary).duplicate(true) if paid else {},
	}


## The declared prize with every value JSON-safe: the shape name as a `String`, and each
## numeric term an `int`. `tribute_periods` arriving as `2.0` would make a prize that is
## declared in whole periods read as fractional, and the round-trip test compares verbatim.
static func _prize_out(prize: Dictionary) -> Dictionary:
	var out: Dictionary = {"prize": String(prize.get("prize", ""))}
	for key in prize.keys():
		if String(key) == "prize":
			continue
		var value: Variant = prize[key]
		out[String(key)] = (
			int(value) if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT else value
		)
	return out


## An `OwnerRef` as `{"kind", "id"}`, or `{}` when the value names no holder. Reached through
## `OwnerRef.from_dict`, which drops an unknown kind rather than keeping a ref nothing can
## resolve (ADR 0097).
static func _side(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	return OwnerRef.from_dict(value).to_dict()


## The standoff over `node_id`, or `{}` when there is none.
static func standoff(state: Dictionary, node_id: StringName) -> Dictionary:
	var entry = (state["standoffs"] as Dictionary).get(String(node_id))
	return (entry as Dictionary) if entry is Dictionary else {}


## Whether `node_id` carries an OPEN standoff. A paid one reads as closed, so a caller asking
## "is this still contested" is answered by the same row it will pay.
static func is_open(state: Dictionary, node_id: StringName) -> bool:
	var row := standoff(state, node_id)
	return not row.is_empty() and (row.get("resolved", {}) as Dictionary).is_empty()


## Record one standoff row against `node_id`, with its declared prize and quota.
##
## Refuses `already_resolved` when a PAID standoff is there, so a prize cannot be paid twice,
## and refuses over an OPEN one so two rival prizes can never exist on one node.
static func open(
	state: Dictionary,
	node_id: StringName,
	conflict_id: String,
	holder: Dictionary,
	challenger: Dictionary,
	prize: Dictionary,
	quota: int
) -> Dictionary:
	var key := String(node_id)
	if (state["standoffs"] as Dictionary).has(key):
		var existing := standoff(state, node_id)
		if (existing.get("resolved", {}) as Dictionary).is_empty():
			return {"ok": false, "reason": ALREADY_RESOLVED}
		return {"ok": false, "reason": STANDOFF_CLOSED}
	var kind := StringName(prize.get("prize", ""))
	if not PRIZES.has(kind):
		return {"ok": false, "reason": UNDECLARED_PRIZE}
	if challenger.is_empty() or holder.is_empty():
		return {"ok": false, "reason": NO_CHALLENGER}
	if (state["standoffs"] as Dictionary).size() >= MAX_STANDOFFS:
		return {"ok": false, "reason": TOO_MANY}
	(state["standoffs"])[key] = {
		"conflict_id": conflict_id,
		"holder": holder.duplicate(true),
		"challenger": challenger.duplicate(true),
		"prize": prize.duplicate(true),
		"quota": clampi(quota, 1, MAX_QUOTA),
		"verdicts": 0,
		"resolved": {},
	}
	return {"ok": true, "reason": "", "conflict_id": conflict_id}


## Record one verdict already decided elsewhere against `node_id`. The ONLY arithmetic in this
## module: a counter plus one, and a comparison with the declared quota (ADR 0085).
##
## Returns `met` so the caller knows whether this verdict was the resolution, rather than
## reading a count back and re-deriving it.
static func record_verdict(state: Dictionary, node_id: StringName, winner_id: String) -> Dictionary:
	var row := standoff(state, node_id)
	if row.is_empty():
		return {"ok": false, "reason": NO_CONTEST}
	if not (row.get("resolved", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": ALREADY_RESOLVED}
	if not _names_side(row, winner_id):
		return {"ok": false, "reason": UNKNOWN_SIDE}
	var verdicts := int(row.get("verdicts", 0)) + 1
	row["verdicts"] = verdicts
	row["last_winner_id"] = winner_id
	(state["standoffs"])[String(node_id)] = row
	return {
		"ok": true, "reason": "", "verdicts": verdicts, "met": verdicts >= int(row.get("quota", 1))
	}


## Whether `winner_id` is one of the two sides the declaration named. A verdict naming nobody
## is refused rather than resolving a standoff between two people the caller did not pick
## between (ADR 0085: a conflict DECLARES sides).
static func _names_side(row: Dictionary, winner_id: String) -> bool:
	if winner_id == "":
		return false
	return (
		winner_id == String((row.get("holder", {}) as Dictionary).get("id", ""))
		or winner_id == String((row.get("challenger", {}) as Dictionary).get("id", ""))
	)


## Close `node_id`'s standoff as PAID, recording what the prize was. The row is KEPT rather
## than erased, and that is what makes a second resolution refuse by name: a delete could not
## refuse anything, and a paid war nobody can re-answer is exactly the double-payout ADR 0085
## forbids.
static func settle(
	state: Dictionary, node_id: StringName, prize: String, winner_id: String
) -> Dictionary:
	var row := standoff(state, node_id)
	if row.is_empty():
		return {}
	row["resolved"] = {"prize": prize, "winner_id": winner_id}
	(state["standoffs"])[String(node_id)] = row
	return row.duplicate(true)
