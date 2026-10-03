class_name CustodyApi
extends RefCounted

## Public facade for the `custody` module (ADR 0104). Owns who holds a captive, on what
## term, and for how many periods.
##
## ## A captive is a CLAIM, not a thing
##
## A record names a subject **def id** and an `OwnerRef` holder, and carries a term as a
## COUNT of periods. It is never an `Actor`, never an `ItemInstance`, and **never a price** —
## so nothing here can answer "what is this person worth". ADR 0094 refuses a captive as a
## tradeable thing because it has no `ItemDef`; this module is what a refusal leaves behind.
##
## ## Zero edges to the institution modules
##
## A holder may be an `actor`, a `clan`, a `sect` or a `nation` — four modules that do not
## contain each other, and `tools arch`'s bare-reference detector excludes `modules/*`, so
## calling into them would build a cycle the gate cannot see. Resolution is an **injected
## `Callable`** over the closed `OwnerRef.KINDS`, the `NpcApi.set_minter` seam verbatim.
##
## ## The coin leg runs FIRST
##
## `transfer` prices the coins the caller agreed and runs `EconomyApi.trade`; only on success
## does it write the new holder. `EconomyExchange` plans against `Inventory.snapshot()` of
## both sides before its first mutation, so a refused coin leg has written nothing — and the
## custody state has not been touched. The reverse order is the "granted but never written"
## failure ADR 0101 records for holdings, and is unrecoverable without a rollback path.
##
## ## No escape verb, and no description field
##
## Release is a **holder** verb; an escape is decided by combat and the caller then releases
## afterwards. And there is deliberately no `description` here: the subject's name is authored
## on its def and read through the catalog, because prose in a save schema becomes what gets
## read.

## The `actor.module_data` key the versioned ledger persists under (ADR 0027).
const MODULE_KEY := CustodyState.MODULE_KEY

# --- refusals -----------------------------------------------------------------
const NO_ACTOR := "no_actor"
const NO_TERMS := "no_terms"
const SELF_HOLD := "self_hold"
const ALREADY_CAPTIVE := "already_captive"
const CUSTODY_FULL := "custody_full"
const UNKNOWN_SUBJECT_KIND := "unknown_subject_kind"
const UNKNOWN_OWNER := "unknown_owner"
const UNKNOWN_OWNER_KIND := OwnerRef.UNKNOWN_KIND
const NO_RESOLVER := "no_resolver"
const NO_SUCH_CLAIM := "no_such_claim"
const NOT_HELD := "not_held"
const HOLDER_MISMATCH := "holder_mismatch"
const SELF_TRANSFER := "self_transfer"
const COIN_LEG_FAILED := "coin_leg_failed"
const NO_SETTLEMENT_PARTY := "no_settlement_party"
const NO_PERIODS := "no_periods"
const CLAIM_SETTLED := "claim_settled"
const TERM_EXCEEDS := "term_exceeds"

static var _store: RefCounted = null
static var _resolver: Callable = Callable()


## Restore and normalize whatever a prior `Actor.from_dict` carried. Idempotent, and safe on
## an actor holding nobody — holding nobody is the ordinary starting state, not a failure.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, CustodyState.normalize(actor.get_module_data(MODULE_KEY)))


## Install the holder resolver: `(kind, id) -> {"ok": bool, "reason": String}`, answering
## whether an `OwnerRef` names something real. `app/` wires it against the institution
## modules so this one keeps no edge to any of them.
##
## With nothing installed a claim by an institution refuses `no_resolver` and writes nothing
## (ADR 0002: a null injection fails loudly rather than dereferencing nothing).
static func set_resolver(resolver: Callable) -> void:
	_resolver = resolver


## Install the shared ledger store. **Custody is a WORLD fact**: the new holder must see the
## claim the old holder opened, or a transfer refuses `no_such_claim` and custody is
## invisible across actors (ADR 0101). Any object with `read_ledger()`/`write_ledger()`.
static func set_store(store: RefCounted) -> void:
	_store = store


## Take custody of `subject_id` for `holder`, on an authored `term_id` owed for `periods`.
##
## `subject_id` is a DEF id, never an `Actor` — a live subject is minted on demand by the
## caller through the same seam `NpcApi` uses, so this module never holds a stat-provider
## graph and never depends on `npc`.
##
## Refuses `no_terms` for a zero term (a capture with no term is a free grab, which is a game
## rule and not validation), `self_hold` when the holder IS the subject, `already_captive`
## because one subject may be held once, and `custody_full` at the cap.
static func capture(
	actor: Actor,
	subject_id: StringName,
	subject_kind: StringName,
	holder: Dictionary,
	term_id: StringName,
	periods: int,
	opened_period: int = 0
) -> Dictionary:
	if actor == null:
		return _refuse(NO_ACTOR)
	if periods <= 0 or term_id == &"":
		return _refuse(NO_TERMS)
	if not CustodyState.SUBJECT_KINDS.has(subject_kind):
		return _refuse(UNKNOWN_SUBJECT_KIND)
	# `holder == subject` is a record with no exit: transfer refuses a self-transfer, release
	# refuses a non-holder, and the claim is permanent. Refused at capture so it cannot be
	# written in the first place.
	#
	# The comparison is on **ids alone, deliberately ignoring `kind`**. A subject is named by
	# a def id and a holder by an `OwnerRef`, and they are different vocabularies: matching
	# `kind` to `subject_kind` would mean an `actor` holder can never be refused against an
	# `npc` subject, which is exactly the loop this exists to prevent — the id is what makes
	# two references the SAME being.
	if String(holder.get("id", "")) == String(subject_id) and String(holder.get("id", "")) != "":
		return _refuse(SELF_HOLD)
	var resolved := _resolve(holder)
	if not bool(resolved["ok"]):
		return _refuse(String(resolved["reason"]))
	var state := _state(actor)
	if not CustodyState.claim_on_subject(state, String(subject_id)).is_empty():
		return _refuse(ALREADY_CAPTIVE)
	var ref := OwnerRef.from_dict(holder)
	if ref.is_empty():
		return _refuse(UNKNOWN_OWNER)
	var claim_id := "custody_%s#%d" % [String(subject_id), (state["claims"] as Dictionary).size()]
	var claim := {
		"claim_id": claim_id,
		"subject_id": String(subject_id),
		"subject_kind": String(subject_kind),
		"holder": ref.to_dict(),
		"term_id": String(term_id),
		"periods": int(periods),
		"opened_period": opened_period,
		"status": CustodyState.HELD,
	}
	var written := CustodyState.put(state, claim)
	if not bool(written["ok"]):
		return _refuse(String(written["reason"]))
	_save(actor, state)
	return {
		"ok": true,
		"reason": "",
		"claim_id": claim_id,
		"holder": ref.to_dict(),
		"periods": int(periods),
	}


## Move custody of `claim_id` from `holder` to `to_holder`, with an optional agreed coin
## settlement.
##
## **The coin leg runs first and the claim moves only after it succeeds** — see the class
## note. `coins == 0` is a legitimate hand-off and skips the exchange entirely, because a
## transfer with no coin leg must not be forced to invent one.
##
## `coin_payer` is the `Actor` that funds the settlement; a holder that is an institution has
## no `Actor` to spend from, so it passes the coins it is owed instead. Refuses
## `self_transfer` because a same-party sale at an agreed price is a money printer — the same
## reason `EconomyExchange` refuses `SAME_ACTOR`.
static func transfer(
	actor: Actor,
	claim_id: StringName,
	holder: Dictionary,
	to_holder: Dictionary,
	coins: int = 0,
	coin_payer: Actor = null,
	coin_receiver: Actor = null
) -> Dictionary:
	if actor == null:
		return _refuse(NO_ACTOR)
	var state := _state(actor)
	var claim := CustodyState.claim(state, claim_id)
	if claim.is_empty():
		return _refuse(NO_SUCH_CLAIM)
	if String(claim.get("status", "")) != CustodyState.HELD:
		return _refuse(NOT_HELD)
	if _key(CustodyState.holder(claim)) != _key(holder):
		return _refuse(HOLDER_MISMATCH)
	if _key(to_holder) == _key(holder):
		return _refuse(SELF_TRANSFER)
	var target := OwnerRef.from_dict(to_holder)
	if target.is_empty():
		return _refuse(UNKNOWN_OWNER)
	var resolved := _resolve(to_holder)
	if not bool(resolved["ok"]):
		return _refuse(String(resolved["reason"]))
	var paid := 0
	if coins > 0:
		if coin_payer == null or coin_receiver == null:
			return _refuse(NO_SETTLEMENT_PARTY)
		var leg := EconomyApi.trade(
			coin_payer,
			coin_receiver,
			[{"def_id": String(EconomyValuation.numeraire_id()), "quantity": int(coins)}],
			[],
			coin_payer.id
		)
		if not bool(leg.get("ok", false)):
			# Nothing was written on either inventory AND the claim has not moved, because
			# this returns before the mutation below. A refused transfer writes nothing.
			return _refuse(COIN_LEG_FAILED)
		paid = int(coins)
	# The claim moves only now, after the money is settled.
	var moved := CustodyState.set_holder(state, claim_id, target.to_dict())
	if not bool(moved["ok"]):
		return _refuse(String(moved["reason"]))
	_save(actor, state)
	return {
		"ok": true,
		"reason": "",
		"claim_id": String(claim_id),
		"holder": target.to_dict(),
		"coins": paid,
	}


## End custody of `claim_id`. **A holder verb only** — a subject cannot release themself, and
## an escape is decided by combat and released afterwards by whoever holds the claim.
##
## Always allowed for the holder, and it does NOT forgive the term: `periods_left` is
## reported and the claim stays in the ledger as `released`, so the history reads as history
## and a subject can be captured again under a new claim rather than the old one reopening.
static func release(actor: Actor, claim_id: StringName, holder: Dictionary) -> Dictionary:
	if actor == null:
		return _refuse(NO_ACTOR)
	var state := _state(actor)
	var claim := CustodyState.claim(state, claim_id)
	if claim.is_empty():
		return _refuse(NO_SUCH_CLAIM)
	if String(claim.get("status", "")) != CustodyState.HELD:
		return _refuse(NOT_HELD)
	if _key(CustodyState.holder(claim)) != _key(holder):
		return _refuse(HOLDER_MISMATCH)
	claim["status"] = CustodyState.RELEASED
	claim["holder"] = OwnerRef.vacant()
	state["claims"][String(claim_id)] = claim
	_save(actor, state)
	return {
		"ok": true,
		"reason": "",
		"claim_id": String(claim_id),
		"periods_left": int(claim.get("periods", 0)),
	}


## Settle up to `periods` against the claim's term. All-or-nothing, so a holder is never
## left owing less than it claimed to owe and never silently forgiven.
static func settle_term(actor: Actor, claim_id: StringName, periods: int) -> Dictionary:
	if actor == null:
		return _refuse(NO_ACTOR)
	var state := _state(actor)
	var settled := CustodyState.settle_term(state, claim_id, periods)
	if not bool(settled["ok"]):
		return _refuse(String(settled["reason"]))
	_save(actor, state)
	return settled


## The whole read model: every claim, each with its holder, term and periods, plus whether a
## resolver is wired. `{}` when there is no actor — the contract a panel tests instead of
## pixels.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var state := _state(actor)
	var held := 0
	var views: Dictionary = {}
	for claim_id in (state["claims"] as Dictionary).keys():
		var claim := state["claims"][claim_id] as Dictionary
		if String(claim.get("status", "")) == CustodyState.HELD:
			held += 1
		views[String(claim_id)] = {
			"claim_id": String(claim_id),
			"subject_id": String(claim.get("subject_id", "")),
			"subject_kind": String(claim.get("subject_kind", "")),
			"holder": (claim.get("holder", {}) as Dictionary).duplicate(true),
			"term_id": String(claim.get("term_id", "")),
			"periods": int(claim.get("periods", 0)),
			"opened_period": int(claim.get("opened_period", 0)),
			"status": String(claim.get("status", "")),
		}
	return {
		"actor_id": String(actor.id),
		"claims": views,
		"claim_count": views.size(),
		"held_count": held,
		"claim_capacity": CustodyState.MAX_CLAIMS,
		"resolver_installed": _resolver.is_valid(),
		"store_installed": _store != null,
	}


## The ledger exactly as core persists it, so a caller never reaches into `module_data`.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return CustodyState.empty()
	var state := CustodyState.normalize(actor.get_module_data(MODULE_KEY))
	actor.set_module_data(MODULE_KEY, state)
	return state


# --- internals ---------------------------------------------------------------


## The holder of `claim`, or `{}` when it has none.
static func _holder(claim: Dictionary) -> Dictionary:
	return claim.get("holder", {}) as Dictionary


## A stable comparison key for an owner, so two dictionaries that name the same holder
## compare equal regardless of key order or an extra field.
static func _key(owner: Dictionary) -> String:
	var ref := OwnerRef.from_dict(owner)
	return ref.storage_key() if not ref.is_empty() else ""


static func _resolve(owner: Dictionary) -> Dictionary:
	if owner.is_empty():
		return {"ok": false, "reason": UNKNOWN_OWNER}
	var kind := StringName(owner.get("kind", ""))
	if not OwnerRef.KINDS.has(kind):
		return {"ok": false, "reason": UNKNOWN_OWNER_KIND}
	if not _resolver.is_valid():
		return {"ok": false, "reason": NO_RESOLVER}
	var answered: Variant = _resolver.call(String(kind), String(owner.get("id", "")))
	if not answered is Dictionary:
		return {"ok": false, "reason": UNKNOWN_OWNER}
	if not bool((answered as Dictionary).get("ok", false)):
		return {
			"ok": false, "reason": String((answered as Dictionary).get("reason", UNKNOWN_OWNER))
		}
	return {"ok": true, "reason": ""}


static func _state(actor: Actor) -> Dictionary:
	if _store != null and _store.has_method(&"read_ledger"):
		return CustodyState.normalize(_store.call(&"read_ledger"))
	if actor == null:
		return CustodyState.empty()
	return CustodyState.normalize(actor.get_module_data(MODULE_KEY))


static func _save(actor: Actor, state: Dictionary) -> void:
	var normalized := CustodyState.normalize(state)
	if _store != null and _store.has_method(&"write_ledger"):
		_store.call(&"write_ledger", normalized)
	if actor != null:
		actor.set_module_data(MODULE_KEY, normalized)


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "coins": 0, "holder": {}}
