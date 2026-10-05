class_name ConflictApi
extends RefCounted

## Public facade for the `conflict` module (ADR 0085, ADR 0245). Owns how a DECIDED standoff
## over a contested resource node resolves — and owns no number that could decide one.
##
## ## A conflict is a DECLARATION of sides and a prize, never a formula
##
## This module **never calls combat, never reads a combat stat, and owns no `rng`** (ADR 0085).
## Its only arithmetic is `verdicts + 1` against a declared quota. A verdict arrives from
## OUTSIDE — a `CombatApi.exchange` the caller ran, a tournament result, a tribunal's ruling —
## and this module counts it and pays the prize that was declared before the first one.
##
## ## The standoff is OPENED by a claim, and this module only binds the prize
##
## `HoldingsApi.claim` on held ground already writes the `{conflict_id, challenger}` contest row
## and leaves `holder` byte-identical (ADR 0085). That is the invariant that separates a claim
## from a conquest. `declare` does not open a second standoff: it reads the contest row
## `holdings` wrote, checks the caller is declaring against the node that actually has one, and
## attaches the **declared prize** and the quota to it.
##
## ## The payout belongs to `holdings`, and that is why this module exists
##
## `HoldingsApi.apply_prize` was written with the docstring "Called by the conflict module,
## never by the holder — one module owns how a conflict ends" and had no caller: the conflict
## module was never built (DEF-0311). `holdings`, `market` and `custody` are each at the
## twelve-method facade cap, so a fourth verb cannot be added to `holdings` either. This module
## is the caller that was named, and it declares exactly one module edge — `holdings`, reached
## only through `holdings/api.gd`, the same shape `forage` already declares.
##
## ## The prize is DECLARED UP FRONT and never computed at resolution
##
## `declare` refuses a prize outside the closed shape `ownership | recognition | tribute` as
## `undeclared_prize`, **by name**, and writes nothing. `resolve` reads the declaration verbatim
## and hands it to `apply_prize`; it cannot invent a prize because there is nothing in it that
## could produce one.
##
## ## A standoff is a WORLD fact and lives in an injected store (ADR 0101)
##
## A standoff has three parties and no owner, so keeping it in one actor's `module_data` would
## give each of them their own copy and let a verdict resolve against a row the other side cannot
## see. `set_store` takes any object with `read_ledger()` / `write_ledger(ledger)`; `attach` still
## mirrors onto the actor so a single-player save carries the standoffs.
##
## ## There is no clock
##
## Nothing here reads `Time` and nothing accrues on its own. A verdict is an explicit call, which
## is the whole of this module's passage of time (DEF-0111).
##
## ## Refusals are named authored constants
##
## Every refusal is built in `_refuse` and ANNOUNCED on `ConflictEvents`, exactly
## `HoldingsApi._refuse` does (DEF-0221): the returned dictionary says nothing was written, and
## the signal says WHICH rule refused and ON WHICH NODE, so a panel renders the rule it was given
## rather than inventing one.

# --- the only module edge this facade declares --------------------------------

## `holdings`, reached through its facade and through nothing else. This is the edge ADR 0245
## records: a standoff over a resource node is paid by the module that owns resource nodes, and
## the cycle argument is `holdings -> {"contracts", "core"}`, so `conflict -> holdings` cannot
## close a loop. `nation` is deliberately NOT reached: its standoffs are keyed by a
## lexicographic pair of polity ids and are paid by `NationResolve` over a territory row, which
## is a different fact with a different owner.
const HOLDINGS_FACADE := preload("res://src/modules/holdings/api.gd")

## The `actor.module_data` key the versioned ledger persists under (ADR 0027).
const MODULE_KEY := ConflictState.MODULE_KEY

static var _store: RefCounted = null
static var _events: ConflictEvents = null


## The event contract, for a consumer to subscribe to. On the facade and not behind a projection
## because a subscriber in another module has to be able to reach it (ADR 0093).
static func events() -> ConflictEvents:
	if _events == null:
		_events = ConflictEvents.new()
	return _events


## Install the shared ledger — any object with `read_ledger()` and `write_ledger(ledger)`.
##
## ## The default is the actor mirror, and that default is documented as WRONG
##
## It is correct for a single-holder save and wrong the moment a second party exists, so `app/`
## installs a real store and a test installs `ConflictWorldLedger`. See `set_store`'s counterpart
## in `HoldingsApi` and ADR 0101, which decided the shape for every world-scoped ledger in this
## program.
##
## ## `read_ledger`/`write_ledger`, never `load`/`save`
##
## Those are global GDScript builtins, and a `RefCounted` method of that name resolves to the
## builtin — a compile error rather than a loud failure, so it stays invisible until someone
## runs the suite.
static func set_store(store: RefCounted) -> void:
	_store = store


## Attach the module to `actor`: restore and normalize whatever a prior `Actor.from_dict`
## carried. Idempotent, and safe on an actor in no standoff at all, which is the ordinary
## starting state.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, ConflictState.normalize(actor.get_module_data(MODULE_KEY)))


## Bind a declared PRIZE and a verdict quota to the open standoff over `node_id`.
##
## `prize` is `{prize: ownership|recognition|tribute}` and is **read verbatim at resolution**;
## `quota` is how many verdicts the standoff takes, defaulting to one (a tribunal). Declaring
## both now is what makes a standoff a political object rather than a scoring function: both
## sides know what is at stake before the first verdict.
##
## ## It requires a contest row `holdings` already wrote
##
## Refuses `no_contest` for a node with no open challenge. A declaration cannot OPEN a standoff
## on its own, because opening one is what `HoldingsApi.claim` does and it does it in a way that
## leaves the holder byte-identical (ADR 0085). If this verb could write the contest row itself,
## two modules would own opening a standoff and the invariant would have two implementations.
##
## ## Refuses `unknown_side` when the challenger is nobody
##
## `no_challenger` — an unclaimed standoff has no party to pay a prize to, and inventing one
## would be a verdict this module has no authority to reach.
static func declare(
	actor: Actor, node_id: StringName, prize: Dictionary, quota: int = ConflictState.DEFAULT_QUOTA
) -> Dictionary:
	var ledger := _state(actor)
	# ## A CALLER'S OWN ARGUMENT is validated before anything is read of the world
	#
	# The prize and the quota are what this call HANDS OVER. `no_contest` and `no_challenger`
	# are facts about the world, and the world is the same either way — so when a caller hands
	# over a prize outside the closed vocabulary AND the node happens to be uncontested,
	# answering `no_contest` names a rule about the ground and buries the one about the
	# declaration. That is not pedantry: this suite's event contract calls
	# `declare(&"conquest")` over a node nobody claimed, and with the checks in world-first
	# order the announcement read `no_contest`, so the panel rendered a rule the caller could
	# not act on while the declaration it had just written was refused for something else
	# entirely.
	#
	# Validating the argument first costs nothing — both refusals still write nothing and both
	# are still named — and it makes the answer depend on the CALL, not on what the world
	# happened to look like when the caller made it.
	if (
		not prize is Dictionary
		or not ConflictState.PRIZES.has(StringName((prize as Dictionary).get("prize", "")))
	):
		return _refuse(actor, node_id, ConflictState.UNDECLARED_PRIZE)
	if quota <= 0 or quota > ConflictState.MAX_QUOTA:
		return _refuse(actor, node_id, ConflictState.BAD_QUOTA)
	var contest := _contest(actor, node_id)
	if contest.is_empty():
		return _refuse(actor, node_id, ConflictState.NO_CONTEST)
	var challenger = contest.get("challenger", {})
	if not challenger is Dictionary or (challenger as Dictionary).is_empty():
		return _refuse(actor, node_id, ConflictState.NO_CHALLENGER)
	# ## The prize was checked at the DOOR; `ConflictState.open` checks it again
	#
	# "A conflict is a declaration of sides and a prize, and never a formula." A prize outside
	# the closed vocabulary is refused `undeclared_prize` rather than resolved to the nearest
	# shape, because silently picking a prize is the module deciding what was at stake — the
	# one thing ADR 0085 says it may never do. Validating HERE rather than only in
	# `ConflictState.open` matters: `open` is the ledger, this is the door, and a refusal a
	# caller has to reach into the ledger to discover is a refusal nobody will find. `open`
	# keeps its own check because it is reachable without passing this door.
	var opened := ConflictState.open(
		ledger,
		node_id,
		String(contest.get("conflict_id", "")),
		_contest_holder(actor, node_id),
		challenger as Dictionary,
		prize,
		quota
	)
	if not bool(opened["ok"]):
		return _refuse(actor, node_id, String(opened["reason"]))
	_save(actor, ledger)
	var row := ConflictState.standoff(ledger, node_id)
	events().standoff_declared.emit(
		String(actor.id),
		node_id,
		String(opened.get("conflict_id", "")),
		String(row.get("prize", {}).get("prize", "")),
		int(row.get("quota", ConflictState.DEFAULT_QUOTA))
	)
	return _ok(
		{
			"node_id": String(node_id),
			"conflict_id": String(opened.get("conflict_id", "")),
			"prize": String(row.get("prize", {}).get("prize", "")),
			"quota": int(row.get("quota", ConflictState.DEFAULT_QUOTA)),
			"verdicts": int(row.get("verdicts", 0)),
			"holder": (row.get("holder", {}) as Dictionary).duplicate(true),
			"challenger": (row.get("challenger", {}) as Dictionary).duplicate(true),
		}
	)


## Record a verdict ALREADY DECIDED ELSEWHERE and pay the DECLARED prize once the quota is met.
##
## ## The verdict is INJECTED, never computed here
##
## `winner_id` is the outcome somebody else decided — a `CombatApi.exchange` the caller ran, a
## tournament result, a tribunal's ruling. This module reads no combat stat, rolls nothing and
## owns no `rng` (ADR 0085). A verdict naming nobody the declaration named refuses
## `unknown_side` rather than resolving a standoff between two parties the caller did not pick
## between.
##
## ## The prize is PAID by `holdings`, not by this module
##
## On the verdict that meets the quota, the DECLARED prize is handed to
## `HoldingsApi.apply_prize`, which is the module that owns the holder and the tribute line, and
## which clears the contest row. This module then marks the standoff settled, so a second
## resolution refuses `already_resolved` and pays nothing.
##
## ## A verdict BELOW the quota records and pays nothing
##
## It is counted and the standoff stays open. That is the whole meaning of a quota, and it is
## why this verb is safe to call from the same place a fight decides.
static func resolve(actor: Actor, node_id: StringName, winner_id: String) -> Dictionary:
	var ledger := _state(actor)
	if not ConflictState.is_open(ledger, node_id):
		return _refuse(actor, node_id, _closed_reason(ledger, node_id))
	var row := ConflictState.standoff(ledger, node_id)
	var verdicted := ConflictState.record_verdict(ledger, node_id, winner_id)
	if not bool(verdicted["ok"]):
		_save(actor, ledger)
		return _refuse(actor, node_id, String(verdicted["reason"]))
	if not bool(verdicted["met"]):
		_save(actor, ledger)
		return _ok(
			{
				"node_id": String(node_id),
				"conflict_id": String(row.get("conflict_id", "")),
				"paid": false,
				"verdicts": int(verdicted["verdicts"]),
				"quota": int(row.get("quota", 1)),
			}
		)
	var prize := (row.get("prize", {}) as Dictionary).duplicate(true)
	var declared := String(prize.get("prize", ""))
	# The PRIZE is declared and closed-vocabulary, so this is a re-check on the way out rather
	# than a judgement: `HoldingsState.normalize` dropped any row whose prize left the
	# vocabulary, so a prize arriving here has already survived one. It is still checked,
	# because a payout reaching `holdings` that holdings refuses would close the standoff
	# without paying it, and a war that closes unpaid and unannounced is the silent failure
	# this module exists to end.
	prize["winner"] = _winner_ref(row, winner_id)
	prize["loser"] = _loser_ref(row, winner_id)
	prize["tribute_periods"] = int(row.get("quota", 1))
	var paid: Dictionary = HOLDINGS_FACADE.apply_prize(actor, node_id, prize)
	if not bool(paid.get("ok", false)):
		_save(actor, ledger)
		return _refuse(actor, node_id, String(paid.get("reason", ConflictState.NO_CONTEST)))
	ConflictState.settle(ledger, node_id, declared, winner_id)
	_save(actor, ledger)
	events().standoff_resolved.emit(
		String(actor.id), node_id, String(row.get("conflict_id", "")), declared, winner_id
	)
	return _ok(
		{
			"node_id": String(node_id),
			"conflict_id": String(row.get("conflict_id", "")),
			"paid": true,
			"prize": declared,
			"winner_id": winner_id,
			"verdicts": int(verdicted["verdicts"]),
			"quota": int(row.get("quota", 1)),
		}
	)


## The versioned ledger exactly as core persists it, so a caller never reaches into
## `module_data`. `{}` with no actor — ADR 0083's first state, "this does not exist".
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return ConflictState.empty()
	var ledger := _state(actor)
	actor.set_module_data(MODULE_KEY, ledger)
	return ledger


## The read model: every standoff this world knows, primitives only, nested under `standoffs`.
## `{}` with no actor, exactly as `HoldingsApi.summary` answers it.
##
## Every read a screen needs folds in here rather than becoming a facade method: nine facades
## already sit at the twelve-method cap, so "add a method" is not a free move in this program.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var ledger := _state(actor)
	var rows: Dictionary = {}
	for node_id in (ledger["standoffs"] as Dictionary).keys():
		var row := (ledger["standoffs"] as Dictionary)[node_id] as Dictionary
		rows[String(node_id)] = _view(row)
	return {
		"actor_id": String(actor.id),
		"standoffs": rows,
		"standoff_count": rows.size(),
		"open_count": int(_open_count(ledger)),
		"resolved_count": int(_resolved_count(ledger)),
		# `PRIZES` is authored `Array[StringName]`. Duplicating it verbatim put three
		# `StringName`s into the read model a screen renders, and `JSON.stringify` emits a
		# `StringName` as the STRING it holds rather than converting it the way `String()` does
		# — so they survived the round trip as values a strict consumer cannot type, which is
		# the JSON hazard ADR 0027 records, one layer out from the ledger it was written for.
		# Widened here rather than at the constant, because `ConflictState.PRIZES` is a
		# membership list that must stay `StringName` for `.has(&"ownership")` to read right.
		"prizes": _prizes_out(),
		# ADR 0165: a caller must be able to tell "no store is wired" from "a store holding
		# an empty world", which before this were the same answer.
		"store_installed": _store != null,
	}


# --- internals ---------------------------------------------------------------


## The closed prize vocabulary as the read model publishes it: `String` per entry, in the
## authored order. Separate from the constant rather than widening it, because `PRIZES` is
## typed `Array[StringName]` on purpose — that is what makes `.has(&"ownership")` at every
## declaration a correct membership test rather than a comparison that happens to hold.
static func _prizes_out() -> Array:
	var out: Array = []
	for kind in ConflictState.PRIZES:
		out.append(String(kind))
	return out


## One standoff row as a screen reads it: who holds, who is challenging, what is at stake and
## how far the standoff has run. The DECLARED prize is published verbatim and never recomputed
## for display (ADR 0085).
static func _view(row: Dictionary) -> Dictionary:
	var resolved = row.get("resolved", {})
	return {
		"node_id": String(row.get("node_id", "")),
		"conflict_id": String(row.get("conflict_id", "")),
		"holder": (row.get("holder", {}) as Dictionary).duplicate(true),
		"challenger": (row.get("challenger", {}) as Dictionary).duplicate(true),
		"prize": (row.get("prize", {}) as Dictionary).duplicate(true),
		"quota": int(row.get("quota", 1)),
		"verdicts": int(row.get("verdicts", 0)),
		"open": (resolved as Dictionary).is_empty(),
		"resolved_prize": String((resolved as Dictionary).get("prize", "")),
		"winner_id": String((resolved as Dictionary).get("winner_id", "")),
	}


## The `OwnerRef` `holdings` recorded as the node's holder, verbatim, or `{}` when the node
## has none. Read through the facade rather than re-derived, so the side this module declares is
## BY CONSTRUCTION the side `holdings` thinks holds the ground — a declaration that named a
## different holder would be a second authority on who owns a node.
##
## `actor` is passed rather than dropped: `HoldingsApi.summary` answers `{}` for a null actor,
## and the ledger it would read is the SHARED store (ADR 0101). Threading the actor is what makes
## this a read of the one world both parties wrote rather than of an empty one.
static func _contest_holder(actor: Actor, node_id: StringName) -> Dictionary:
	var nodes := _holdings_nodes(actor)
	var row = nodes.get(String(node_id))
	if not row is Dictionary:
		return {}
	var owner = (row as Dictionary).get("owner", {})
	return (owner as Dictionary).duplicate(true) if owner is Dictionary else {}


## The open contest row `holdings` wrote for `node_id`, or `{}`. Read through the facade rather
## than through `HoldingsState`, because `tools arch` permits one file of `holdings` and the
## facade is that file.
static func _contest(actor: Actor, node_id: StringName) -> Dictionary:
	var row = _holdings_nodes(actor).get(String(node_id))
	if not row is Dictionary:
		return {}
	if not bool((row as Dictionary).get("contested", false)):
		return {}
	return {
		"conflict_id": String((row as Dictionary).get("conflict_id", "")),
		"challenger": _challenger_ref(actor, node_id),
	}


## The challenger ref, read from the holder side of the ledger `holdings` owns. `holdings`
## publishes a contest row's `conflict_id` and `contested` on `summary`, and the challenger's
## own `OwnerRef` is on the ledger row it keeps, so this is the one shape read straight from the
## facade rather than re-derived.
static func _challenger_ref(actor: Actor, node_id: StringName) -> Dictionary:
	var ledger: Dictionary = HOLDINGS_FACADE.state(actor)
	var contested: Dictionary = ledger.get("contested", {})
	var row = contested.get(String(node_id))
	if not row is Dictionary:
		return {}
	var challenger = (row as Dictionary).get("challenger", {})
	return (challenger as Dictionary).duplicate(true) if challenger is Dictionary else {}


## `holdings`' per-node view of the world, or `{}` when it publishes none. One helper because
## three call sites need the same read and the actor-threading above is the part that is easy to
## get wrong by hand.
static func _holdings_nodes(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var summary: Dictionary = HOLDINGS_FACADE.summary(actor)
	var nodes = summary.get("nodes", {})
	return nodes as Dictionary if nodes is Dictionary else {}


## The winner's `OwnerRef`, read from the two sides the declaration named rather than rebuilt
## from the bare id the verdict carried.
static func _winner_ref(row: Dictionary, winner_id: String) -> Dictionary:
	for side in ["holder", "challenger"]:
		var ref: Dictionary = row.get(side, {})
		if String(ref.get("id", "")) == winner_id:
			return ref.duplicate(true)
	return {}


## The other side's ref: the party the verdict decided against, which is who a tribute prize
## charges.
static func _loser_ref(row: Dictionary, winner_id: String) -> Dictionary:
	for side in ["holder", "challenger"]:
		var ref: Dictionary = row.get(side, {})
		if String(ref.get("id", "")) != winner_id:
			return ref.duplicate(true)
	return {}


## Why `resolve` refused when the standoff is not open: a PAID standoff and a standoff that was
## never declared are different answers, and a caller that paid a prize must be able to tell it
## from one that never existed.
static func _closed_reason(ledger: Dictionary, node_id: StringName) -> String:
	var row := ConflictState.standoff(ledger, node_id)
	if row.is_empty():
		return ConflictState.NO_CONTEST
	return ConflictState.ALREADY_RESOLVED


static func _open_count(ledger: Dictionary) -> int:
	var count := 0
	# Snapshot the bound BEFORE the walk; this loop only counts.
	var keys: Array = (ledger["standoffs"] as Dictionary).keys()
	for node_id in keys:
		if ConflictState.is_open(ledger, StringName(String(node_id))):
			count += 1
	return count


static func _resolved_count(ledger: Dictionary) -> int:
	var count := 0
	var keys: Array = (ledger["standoffs"] as Dictionary).keys()
	for node_id in keys:
		if not ConflictState.is_open(ledger, StringName(String(node_id))):
			count += 1
	return count


## Read the ledger. With a store installed it is shared by every actor, so both parties to a
## standoff see it; without one it falls back to the actor's own mirror, which is correct for a
## single-holder save and is why `attach` still mirrors there.
static func _state(actor: Actor) -> Dictionary:
	if _store != null and _store.has_method(&"read_ledger"):
		return ConflictState.normalize(_store.call(&"read_ledger"))
	if actor == null:
		return ConflictState.empty()
	return ConflictState.normalize(actor.get_module_data(MODULE_KEY))


## Write the ledger back to the store when there is one, and always mirror it onto the actor so
## a single-player save still carries the standoffs.
static func _save(actor: Actor, state: Dictionary) -> void:
	var normalized := ConflictState.normalize(state)
	if _store != null and _store.has_method(&"write_ledger"):
		_store.call(&"write_ledger", normalized)
	if actor != null:
		actor.set_module_data(MODULE_KEY, normalized)


## ## The ONE place every refusal leaves this facade, and it ANNOUNCES (DEF-0221)
##
## `ConflictApi` builds every refusal here rather than at each call site, so the refusal ANSWER
## and the refusal ANNOUNCEMENT cannot be two code paths that drift. `actor` and `node_id` are
## parameters rather than read from module state precisely because the identity a refusal
## announces is part of the refusal.
static func _refuse(actor: Actor, node_id: StringName, reason: String) -> Dictionary:
	if actor != null:
		events().conflict_refused.emit(String(actor.id), node_id, reason)
	return {"ok": false, "reason": reason, "paid": false, "state": _state(actor)}


static func _ok(detail: Dictionary) -> Dictionary:
	var out := {"ok": true, "reason": ""}
	for key in detail.keys():
		out[String(key)] = detail[key]
	return out
