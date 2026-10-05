class_name DoctrineTemplateRule
extends DoctrineRule

## THE TEMPLATE RULE. The smallest thing that touches every seam of
## [DoctrineRule], and deliberately NOT a designed System.
##
## ADR 0273: the framework ships the seams and no System. Eight candidate shapes
## are supportable and none is implemented, and balance is explicitly not a
## blocker. Every number is in `doctrines.json` beside this file, so there is no
## design intent here to mistake for one: two Systems that happen to answer the
## same event, a cheap row and a dear one, two bands named `t0` and `t1`. Read it
## for the SEAMS. It is not the first candidate System, and it is not a model of
## what one should look like.
##
## ## Who writes which ledger key, and why naming `DoctrineLedger` is not a choice
##
## The framework owns `balance`, `joined`, `earnings` and `redemptions`; the RULE
## owns `points`, `points_max` and `owned` (ADR 0272 decision 3). Those field names
## are forced, not chosen: `DoctrineLedger.normalize` rebuilds the dictionary from
## its own key list on every read and DROPS anything else, so a counter stored
## under a name of the System's own is erased by the next write. Naming the
## constants is therefore the only spelling that is not a second literal
## (ADR 0066). It is also the one hole in the published surface — the contract
## publishes `data_key()` and no field names — so a System must reach one module
## class past the facade to read its own state back.
##
## ## What is deliberately absent
##
## No clock, no tick, no scene tree (DEF-0111): `earn` is a pure proposal and the
## caller that owns the occurrence decides how much is applied. No realm id
## anywhere, so there is nowhere to put a magnitude (ADR 0273). No stat composer:
## the grant is `Actor.add_status`, the game's existing universal verb.

## This System's id, and the tail of its persisted key. EMPTY by default, which is
## what makes an unnamed System unregistrable rather than silently addressable.
var id: StringName = &""
var label: String = ""
## The pools this System earns in and spends. HELD, not declared here: they are
## what `stats.json` declared, handed in by the mod's entry point, so a System
## cannot name a pool nothing introduced.
var pools: Array[StringName] = []
## Points per tier band, and the band names. `tier_names` empty is the inert case.
var tier_points: int = 2
var tier_names: Array[String] = ["t0", "t1"]
## `0` means the counter has no ceiling, which is legitimate for an extradiegetic
## counter and is why nothing here bounds it.
var points_max: int = 0
## What one redeem adds to the counter. The counter is the RULE's, so this and
## `redeem` are the only ways it moves.
var points_per_redeem: int = 1
## The occurrence this System answers, and how much it claims from it.
var earn_kind: StringName = &""
var earn_amount: float = 0.0
## The board. Each row carries every key in [constant DoctrineRule.ROW_KEYS].
var rows: Array[Dictionary] = []


func system_id() -> StringName:
	return id


func display_name() -> String:
	return label


## The pools the mod's declaration introduced. `data_key()` is INHERITED — the
## contract derives it from [method system_id], so there is exactly one spelling
## of the save key in the repo and a System cannot write its own.
func resource_ids() -> Array[StringName]:
	return pools


## Read-only. The counter as it stands, and whether it has a ceiling.
func progress(actor: Variant) -> Dictionary:
	var ledger := _ledger(actor)
	return {
		&"points": _points(ledger),
		&"points_max": maxi(0, int(ledger.get(DoctrineLedger.KEY_POINTS_MAX, 0))),
	}


## DERIVED from [method progress] and from nothing else — no realm, no ladder
## index, no second factor. Read-only.
func tier_for(actor: Variant) -> Dictionary:
	var top := maxi(0, tier_names.size() - 1)
	var band := maxi(1, tier_points)
	var tier := clampi(_points(_ledger(actor)) / band, 0, top)
	return {
		&"tier": tier,
		&"tier_name": str(tier_names[tier]) if not tier_names.is_empty() else "",
		&"tiers": tier_names.size(),
		&"next_tier_points": 0 if tier >= top else (tier + 1) * band,
	}


## A CATALOGUE read. It MUST NOT mutate — a screen calls this once per frame, so
## a board that moved under its reader is a board that cannot be drawn. Every row
## is a COPY, because the caller owns what it is handed.
func boards(_actor: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in rows:
		out.append(row.duplicate(true))
	return out


## What `row_id` costs this actor RIGHT NOW. `{}` when there is no such row — a
## row this System does not sell has refused nothing (ADR 0083), and a panel that
## draws a refusal on a row that was never there is the defect that shape causes.
## Read-only, and `owned`/`affordable` are live, so a caller cannot derive them
## from [method boards].
func price(actor: Variant, row_id: StringName) -> Dictionary:
	var row := _row(row_id)
	if row.is_empty():
		return {}
	var pool := StringName(row.get(&"pool", &""))
	var amount := float(row.get(&"amount", 0.0))
	var refusal := _refusal(actor, row)
	return {
		&"ok": refusal == "",
		&"reason": refusal,
		&"row_id": str(row_id),
		&"pool": str(pool),
		&"amount": amount,
		&"owned": _owned(_ledger(actor), row_id),
		&"affordable": pool == &"" or _balance(_ledger(actor)) >= amount,
	}


## THE ONE MUTATOR. Charges nothing itself — the framework's ledger is debited
## from the ROW's amount after this returns — and spends and trains the System
## itself: `owned` and `points` are the rule's keys, so this is where a counter
## is allowed to move. One press, one row, one transaction.
func redeem(actor: Variant, row_id: StringName) -> Dictionary:
	var row := _row(row_id)
	if row.is_empty():
		return {}
	var pool := StringName(row.get(&"pool", &""))
	var amount := float(row.get(&"amount", 0.0))
	var ledger := _ledger(actor)
	var refusal := _refusal(actor, row)
	if refusal != "":
		return _answer(row_id, pool, 0.0, refusal, [])
	var owned := _owned_map(ledger)
	owned[str(row_id)] = _owned(ledger, row_id) + 1
	var stored := ledger.duplicate(true)
	stored[DoctrineLedger.KEY_OWNED] = owned
	stored[DoctrineLedger.KEY_POINTS] = maxi(0, _points(ledger) + points_per_redeem)
	stored[DoctrineLedger.KEY_POINTS_MAX] = maxi(0, points_max)
	(actor as Actor).set_module_data(data_key(), stored)
	# The EXISTING universal grant verb, never a stat composer of this System's own.
	var granted := (actor as Actor).add_status(StatusEffect.new(_status_id(row_id)))
	return _answer(row_id, pool, amount, "", [granted])


## A PROPOSAL, and PURE. Two Systems may answer the same occurrence, so the
## arbitration belongs to the caller that owns the event (ADR 0272 decision 4),
## and a write here would be the framework's money moved without a decision.
## Claiming nothing is the safe default: an unclaimed System has no income, so
## its board is unpayable and renders inert rather than paying out.
func earn(_actor: Variant, event: Dictionary) -> Dictionary:
	if pools.is_empty() or StringName(event.get("kind", &"")) != earn_kind:
		return {"ok": false, "reason": DoctrineRule.NOT_CLAIMED, "pool": &"", "amount": 0.0}
	return {"ok": true, "reason": "", "pool": pools[0], "amount": earn_amount}


# --- Internals -------------------------------------------------------------


## The band first, then the wallet, then the count. A locked actor and a broke
## one are two different answers and a panel renders them differently, so the
## order is the message.
func _refusal(actor: Variant, row: Dictionary) -> String:
	if int(tier_for(actor).get(&"tier", 0)) < int(row.get(&"tier_min", 0)):
		return DoctrineRule.TIER_LOCKED
	var ledger := _ledger(actor)
	var row_id := StringName(row.get(&"row_id", &""))
	if (
		not bool(row.get(&"repeatable", false))
		and _owned(ledger, row_id) >= maxi(1, int(row.get(&"max_count", 1)))
	):
		return DoctrineRule.ALREADY_MAXED
	if float(row.get(&"amount", 0.0)) > _balance(ledger):
		return DoctrineRule.INSUFFICIENT
	return ""


func _answer(
	row_id: StringName, pool: StringName, spent: float, reason: String, granted: Array
) -> Dictionary:
	return {
		"ok": reason == "",
		"reason": reason,
		"row_id": str(row_id),
		"pool": str(pool),
		"spent": spent,
		"granted": granted,
	}


## The state as persisted, RAW. `Actor.get_module_data` returns the LIVE
## dictionary, so every write duplicates before storing and no caller is ever
## written through by accident.
func _ledger(actor: Variant) -> Dictionary:
	return (actor as Actor).get_module_data(data_key())


func _points(ledger: Dictionary) -> int:
	return maxi(0, int(ledger.get(DoctrineLedger.KEY_POINTS, 0)))


func _balance(ledger: Dictionary) -> float:
	return maxf(0.0, float(ledger.get(DoctrineLedger.KEY_BALANCE, 0.0)))


## `String`, not `StringName`: `Actor.to_dict` converts only the OUTER
## `module_data` key, so an inner StringName key returns as a String and the map
## reads empty after a reload.
func _owned(ledger: Dictionary, row_id: StringName) -> int:
	var owned: Variant = ledger.get(DoctrineLedger.KEY_OWNED, {})
	if not owned is Dictionary:
		return 0
	return int((owned as Dictionary).get(str(row_id), 0))


func _owned_map(ledger: Dictionary) -> Dictionary:
	var owned: Variant = ledger.get(DoctrineLedger.KEY_OWNED, {})
	return (owned as Dictionary).duplicate(true) if owned is Dictionary else {}


func _row(row_id: StringName) -> Dictionary:
	# `rows` is this System's own authored array and the walk appends to nothing,
	# so the lookup terminates on whatever the mod declared (INC-0002).
	for row in rows:
		if StringName(row.get(&"row_id", &"")) == row_id:
			return row
	return {}


## Namespaced by the System id, so two Systems selling the same row id cannot
## collide on one status.
func _status_id(row_id: StringName) -> StringName:
	return StringName("doctrine_%s_%s" % [str(id), str(row_id)])
