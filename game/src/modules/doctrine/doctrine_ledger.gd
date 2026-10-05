class_name DoctrineLedger
extends RefCounted

## The persisted per-System state, and the only arithmetic that touches it.
##
## ## Why the balance is NOT an `Actor` `ResourcePool`, measured not assumed
##
## A doctrine currency is an ACCUMULATOR: a System you have not spent from still
## holds what you farmed. `ResourcePool` cannot be that, and the reason is arithmetic:
## `change` clamps to `maximum` (`contracts/resource_pool.gd:28-30`) and
## `CultivationPathDef.ensure_resources` mints a declared pool with `maximum = 0.0`
## (`core/cultivation_path_def.gd:44`), so `change(+amount)` on any pool the game
## declares through that seam is `clampf(amount, 0.0, 0.0)` — a guaranteed `0.0`. A
## pool that cannot accumulate cannot be a currency, so the balance lives here. That
## also keeps a doctrine off a cultivation path's own capped pool, which is the other
## half of the reason: `qi` and `integrity` are capped stats, and earning into one
## would be a magnitude table wearing a currency's name.
##
## ## Every key this file writes is `String`, and `balance` is a MIRROR
##
## `Actor.to_dict` converts the OUTER `module_data` key and nothing else
## (`core/actor.gd:397-402`), so a `StringName` inner key reaches the save untouched
## and returns as a `String` — a map that reads empty after a reload. Hence
## `String(pool)`. And `balance` mirrors the FIRST declared pool so the flat shape a
## single-currency System reads is right, while `balances` stays authoritative for a
## System that declares more than one. `AGENTS.md`'s no-second-copy rule cuts both
## ways: a rule must never read `balances` and expect its own deduction to be there.
##
## ## Who owns which key, and why the split is the design
##
## Framework: `version`, `joined`, `balance`, `balances`, `earnings`, `redemptions`.
## Rule: `points`, `points_max`, `owned`. That split is what keeps ADR 0267's "one
## writer" true while the rule stays the only thing that can advance a counter: the
## rule spends and trains itself inside `redeem`, and the framework owns the money.
## `owned` is passed through verbatim rather than reshaped, because it is the rule's
## map and a framework that retyped its keys would break the rule's own lookups.

## The save-schema version of the ledger this module writes.
const VERSION := 1

const KEY_VERSION := "version"
const KEY_JOINED := "joined"
const KEY_POINTS := "points"
const KEY_POINTS_MAX := "points_max"
const KEY_BALANCE := "balance"
const KEY_BALANCES := "balances"
const KEY_OWNED := "owned"
const KEY_EARNINGS := "earnings"
const KEY_REDEMPTIONS := "redemptions"


## `raw` as this module's ledger, whatever a save or a rule handed over. Always a NEW
## dictionary and always String-keyed inside, so `Actor.get_module_data` — which returns
## the LIVE dictionary, and a save is untrusted input — is never written through by
## accident. A counter is `maxi`'d and a balance `maxf`'d because a JSON round trip
## turns every number into a float.
static func normalize(raw: Variant) -> Dictionary:
	var out := {
		KEY_VERSION: VERSION,
		KEY_JOINED: false,
		KEY_POINTS: 0,
		KEY_POINTS_MAX: 0,
		KEY_BALANCE: 0.0,
		KEY_BALANCES: {},
		KEY_OWNED: {},
		KEY_EARNINGS: 0,
		KEY_REDEMPTIONS: 0,
	}
	if not raw is Dictionary:
		return out
	var source := raw as Dictionary
	out[KEY_JOINED] = bool(source.get(KEY_JOINED, false))
	out[KEY_POINTS] = maxi(0, int(source.get(KEY_POINTS, 0)))
	out[KEY_POINTS_MAX] = maxi(0, int(source.get(KEY_POINTS_MAX, 0)))
	out[KEY_BALANCE] = maxf(0.0, float(source.get(KEY_BALANCE, 0.0)))
	out[KEY_EARNINGS] = maxi(0, int(source.get(KEY_EARNINGS, 0)))
	out[KEY_REDEMPTIONS] = maxi(0, int(source.get(KEY_REDEMPTIONS, 0)))
	# `keys()` is snapshotted by the `for` itself and nothing is appended to it, so the
	# walk cannot outrun its input (INC-0002).
	var balances: Variant = source.get(KEY_BALANCES, {})
	if balances is Dictionary:
		var copied: Dictionary = {}
		for key in (balances as Dictionary).keys():
			copied[str(key)] = maxf(0.0, float((balances as Dictionary)[key]))
		out[KEY_BALANCES] = copied
	var owned: Variant = source.get(KEY_OWNED, {})
	if owned is Dictionary:
		out[KEY_OWNED] = (owned as Dictionary).duplicate(true)
	return out


## What `actor`'s ledger holds in `pool`, or `0.0` for a pool it never declared.
static func balance(ledger: Dictionary, pool: StringName) -> float:
	var balances: Variant = normalize(ledger).get(KEY_BALANCES, {})
	if not balances is Dictionary:
		return 0.0
	return maxf(0.0, float((balances as Dictionary).get(String(pool), 0.0)))


## Apply one ACCEPTED earn proposal: credit `amount` into `pool` and count the occurrence.
##
## Returns `{ok, reason, ledger}` and never a bare ledger, because a caller that wrote a
## refused proposal anyway would be a silent money printer. A non-positive amount claims
## nothing (`NOT_CLAIMED`) — the contract already makes `amount` non-negative, and a zero
## earn is not an earn. A pool the System never declared is `UNDECLARED_POOL` rather than
## a balance in a currency nobody declared.
static func credit(
	ledger: Dictionary, pools: Array[StringName], pool: StringName, amount: float
) -> Dictionary:
	if not declares(pools, pool):
		return {"ok": false, "reason": DoctrineRule.UNDECLARED_POOL, "ledger": ledger}
	if amount <= 0.0:
		return {"ok": false, "reason": DoctrineRule.NOT_CLAIMED, "ledger": ledger}
	var out := normalize(ledger)
	_credit(out, pool, amount)
	out[KEY_EARNINGS] = int(out[KEY_EARNINGS]) + 1
	_mirror(out, pools)
	return {"ok": true, "reason": "", "ledger": out}


## Book one spend of `amount` out of `pool`. Symmetric with [method credit]: a pool the
## System never declared is a content defect diagnosed BEFORE the balance is read, so a
## typo is never reported as a broke actor (ADR 0067's refuse-don't-repair ordering).
static func debit(
	ledger: Dictionary, pools: Array[StringName], pool: StringName, amount: float
) -> Dictionary:
	var out := normalize(ledger)
	# A zero spend is not a pool question at all: a row that costs nothing names no pool,
	# and refusing it for the empty pool it correctly does not name would make every free
	# row unbuyable. Registration already refuses a PRICED row with no pool, so nothing can
	# hide a defect behind a zero.
	if amount <= 0.0:
		# A free row still counts: it consumed a press and a tier band.
		out[KEY_REDEMPTIONS] = int(out[KEY_REDEMPTIONS]) + 1
		_mirror(out, pools)
		return {"ok": true, "reason": "", "ledger": out}
	if not declares(pools, pool):
		return {"ok": false, "reason": DoctrineRule.UNDECLARED_POOL, "ledger": ledger}
	if balance(out, pool) < amount:
		return {"ok": false, "reason": DoctrineRule.INSUFFICIENT, "ledger": ledger}
	_credit(out, pool, -amount)
	out[KEY_REDEMPTIONS] = int(out[KEY_REDEMPTIONS]) + 1
	_mirror(out, pools)
	return {"ok": true, "reason": "", "ledger": out}


## The ledger a [method join] writes. Preserves whatever a restored save carried, so
## reloading an actor who has already joined is not a second join.
static func joined(ledger: Dictionary) -> Dictionary:
	var out := normalize(ledger)
	out[KEY_JOINED] = true
	return out


## The ledger a [method leave] writes, and it is DESTRUCTIVE on purpose.
##
## Leaving forfeits the counter, the tier bands it reached and every unspent coin.
## A leave that kept them would not be an opt-out at all — it would be a free bank, and
## leaving and rejoining would be the cheapest way to bank a System's whole progression.
## The counterpart `AGENTS.md` wants is the price, and the price is the progress.
##
## What it deliberately does NOT do is reverse a grant. A row's effect is a
## `StatusEffect` on the actor and nothing in the tree removes one but the status layer,
## so a left System leaves its granted rows standing until they expire on their own.
## That asymmetry is DEF-0321's removal half and it is out of this slice.
static func left(_ledger: Dictionary) -> Dictionary:
	var out := normalize({})
	out[KEY_JOINED] = false
	return out


## Whether `pool` is one of the pools `pools` declares. A pool id must be NAMED: an empty
## id is what makes two Systems' balances collide on one key.
static func declares(pools: Array[StringName], pool: StringName) -> bool:
	return pool != &"" and pools.has(pool)


## Whether `pool` is one core reserves for a capped stat (`ActorPools`). A doctrine
## currency on either would be a second writer for a stat the derived pipeline owns.
static func is_reserved(pool: StringName) -> bool:
	return pool != &"" and ActorPools.CORE_POOL_STATS.has(pool)


static func _credit(ledger: Dictionary, pool: StringName, amount: float) -> void:
	var balances: Dictionary = ledger[KEY_BALANCES]
	var key := String(pool)
	balances[key] = maxf(0.0, float(balances.get(key, 0.0)) + amount)


static func _mirror(ledger: Dictionary, pools: Array[StringName]) -> void:
	if pools.is_empty():
		ledger[KEY_BALANCE] = 0.0
		return
	ledger[KEY_BALANCE] = balance(ledger, pools[0])
