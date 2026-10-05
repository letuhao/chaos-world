extends TestCase

## Shared kit for the doctrine suites. NOT a suite itself: the runner discovers
## `test_*.gd` only, so this file is never executed on its own.
##
## It exists for the reason `domain_fixture_kit.gd` does: the worked System, its row
## table and its ids are ONE copy. A second copy of a System would let every suite pass
## against its own fixture and none of them against the contract.
##
## [codeblock]
## FakeSystem is a `DoctrineRule` implementation, so nothing here needs a `class_name`
## and nothing here can be mistaken for a shipped System.
## [/codeblock]
##
## ## What the fixture deliberately does NOT do
##
## It never writes `balance`, `balances`, `joined`, `earnings` or `redemptions`. Those are
## the framework's keys (`DoctrineLedger`), and a System that wrote them would be the second
## writer the split exists to prevent — so every assertion about money in these suites is an
## assertion that the framework moved it, never that the fixture did. What the fixture DOES
## write is `points` and `owned`, which are the rule's, exactly as ADR 0267 leaves them.

## The id the worked System answers under, and the ids the defect builders vary.
const IRON_BELL := &"way_of_the_iron_bell"
const SILENT_BELL := &"way_of_the_silent_bell"
const GREED_BELL := &"way_of_the_greed_bell"
const INSIGHT := &"insight"
const RAGE := &"rage"

## Rows the worked System sells. Tier bands and the pool both vary so a board exercises the
## three answers a row can have: free, paid, and locked.
const ROW_OPEN := &"open_form"
const ROW_SEALED := &"sealed_form"
const ROW_TRANSCENDENT := &"transendent_form"


class FakeSystem:
	extends DoctrineRule

	var id: StringName = IRON_BELL
	var label: String = "Way of the Iron Bell"
	var pools: Array[StringName] = [INSIGHT]
	var rows: Array[Dictionary] = []
	var tier_points: int = 10
	var tier_names: Array[String] = ["transmitted", "practised", "embodied"]
	## What one redeem adds to the counter. The counter is the RULE's, so this is the only
	## way a tier moves in these suites.
	var points_per_redeem: int = 5
	## The event this System answers, and how much it claims from it.
	var earn_kind: StringName = &"defeat"
	var earn_amount: float = 1.0
	## Empty means "the first declared pool".
	var earn_pool: StringName = &""
	var earn_claims: bool = true
	## Keys each declared key list should be MISSING, so a suite can prove the registration
	## gate holds the vocabulary rather than trusting the implementer to have read it.
	var row_omits: Array[StringName] = []
	var price_omits: Array[StringName] = []
	var earn_omits: Array[StringName] = []
	var progress_omits: Array[StringName] = []
	var tier_omits: Array[StringName] = []

	func system_id() -> StringName:
		return id

	func display_name() -> String:
		return label

	func resource_ids() -> Array[StringName]:
		return pools

	func progress(actor: Variant) -> Dictionary:
		var ledger := _ledger(actor)
		var out := {
			&"points": int(ledger.get(DoctrineLedger.KEY_POINTS, 0)),
			&"points_max": int(ledger.get(DoctrineLedger.KEY_POINTS_MAX, 0)),
		}
		for key in progress_omits:
			out.erase(key)
		return out

	func tier_for(actor: Variant) -> Dictionary:
		var ledger := _ledger(actor)
		var top := maxi(0, tier_names.size() - 1)
		var tier := clampi(
			int(ledger.get(DoctrineLedger.KEY_POINTS, 0)) / maxi(1, tier_points), 0, top
		)
		var out := {
			&"tier": tier,
			&"tier_name": tier_names[tier] if not tier_names.is_empty() else "",
			&"tiers": tier_names.size(),
			&"next_tier_points": 0 if tier >= top else (tier + 1) * maxi(1, tier_points),
		}
		for key in tier_omits:
			out.erase(key)
		return out

	func boards(_actor: Variant) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for row in rows:
			var copy := row.duplicate(true)
			for key in row_omits:
				copy.erase(key)
			out.append(copy)
		return out

	func price(actor: Variant, row_id: StringName) -> Dictionary:
		var row := _row(row_id)
		if row.is_empty():
			return {}
		var ledger := _ledger(actor)
		var pool := StringName(row.get("pool", &""))
		var amount := float(row.get("amount", 0.0))
		var refusal := _refusal(actor, row, ledger)
		var out := {
			&"ok": refusal == "",
			&"reason": refusal,
			&"row_id": String(row_id),
			&"pool": String(pool),
			&"amount": amount,
			&"owned": _owned(ledger, row_id),
			&"affordable":
			pool == &"" or float(ledger.get(DoctrineLedger.KEY_BALANCE, 0.0)) >= amount,
		}
		for key in price_omits:
			out.erase(key)
		return out

	func redeem(actor: Variant, row_id: StringName) -> Dictionary:
		var row := _row(row_id)
		if row.is_empty():
			return {}
		var ledger := _ledger(actor)
		var pool := StringName(row.get("pool", &""))
		var amount := float(row.get("amount", 0.0))
		var refusal := _refusal(actor, row, ledger)
		if refusal != "":
			return _answer(row_id, pool, 0.0, refusal, [])
		var updated := ledger.duplicate(true)
		var owned: Dictionary = updated.get(DoctrineLedger.KEY_OWNED, {})
		owned[String(row_id)] = _owned(ledger, row_id) + 1
		updated[DoctrineLedger.KEY_OWNED] = owned
		updated[DoctrineLedger.KEY_POINTS] = (
			int(ledger.get(DoctrineLedger.KEY_POINTS, 0)) + points_per_redeem
		)
		_store(actor, updated)
		# The EXISTING universal grant verb, never a stat composer of this module's own.
		var grant := _actor(actor).add_status(
			StatusEffect.new(StringName("doctrine_%s" % String(row_id)))
		)
		return _answer(row_id, pool, amount, "", [grant])

	func earn(_actor: Variant, event: Dictionary) -> Dictionary:
		# A PROPOSAL, and write-free: the caller that owns the event arbitrates, because two
		# Systems may answer the same occurrence. The omit lists apply to BOTH branches,
		# because the contract declares every EARN_KEY "including on a refusal".
		var out: Dictionary = {}
		if not earn_claims or StringName(event.get("kind", &"")) != earn_kind:
			out = {"ok": false, "reason": DoctrineRule.NOT_CLAIMED, "pool": &"", "amount": 0.0}
		else:
			out = {"ok": true, "reason": "", "pool": claimed_pool(), "amount": earn_amount}
		for key in earn_omits:
			out.erase(key)
		return out

	func claimed_pool() -> StringName:
		return earn_pool if earn_pool != &"" else (pools[0] if not pools.is_empty() else &"")

	func _refusal(actor: Variant, row: Dictionary, ledger: Dictionary) -> String:
		var pool := StringName(row.get("pool", &""))
		var amount := float(row.get("amount", 0.0))
		if int(_tier_of(actor)) < int(row.get("tier_min", 0)):
			return DoctrineRule.TIER_LOCKED
		if (
			not bool(row.get("repeatable", false))
			and (
				_owned(ledger, StringName(row.get("row_id", &"")))
				>= maxi(1, int(row.get("max_count", 1)))
			)
		):
			return DoctrineRule.ALREADY_MAXED
		# BEFORE the balance check, deliberately: a row spending a pool this System never
		# declared is a content defect, and a defect is not a broke actor.
		if pool != &"" and not pools.has(pool):
			return DoctrineRule.UNDECLARED_POOL
		if pool != &"" and float(ledger.get(DoctrineLedger.KEY_BALANCE, 0.0)) < amount:
			return DoctrineRule.INSUFFICIENT
		return ""

	func _answer(
		row_id: StringName, pool: StringName, spent: float, reason: String, granted: Array
	) -> Dictionary:
		return {
			"ok": reason == "",
			"reason": reason,
			"row_id": String(row_id),
			"pool": String(pool),
			"spent": spent,
			"granted": granted,
		}

	func _tier_of(actor: Variant) -> int:
		return int(tier_for(actor).get(&"tier", 0))

	func _owned(ledger: Dictionary, row_id: StringName) -> int:
		# `String`, not `StringName`: `Actor.to_dict` converts only the OUTER module_data
		# key, so an inner StringName key returns as a String and the map reads empty.
		var owned: Variant = ledger.get(DoctrineLedger.KEY_OWNED, {})
		if not owned is Dictionary:
			return 0
		return int((owned as Dictionary).get(String(row_id), 0))

	func _row(row_id: StringName) -> Dictionary:
		for row in rows:
			if StringName(row.get("row_id", &"")) == row_id:
				return row
		return {}

	func _ledger(actor: Variant) -> Dictionary:
		return _actor(actor).get_module_data(data_key())

	func _store(actor: Variant, data: Dictionary) -> void:
		_actor(actor).set_module_data(data_key(), data)

	func _actor(value: Variant) -> Actor:
		return value as Actor


# --- Builders --------------------------------------------------------------


## The worked System: three rows over one currency, the middle one a real price.
func iron_bell() -> FakeSystem:
	var rule := FakeSystem.new()
	rule.id = IRON_BELL
	rule.label = "Way of the Iron Bell"
	rule.pools = [INSIGHT]
	rule.rows = [
		{
			&"row_id": ROW_OPEN,
			&"label": "Open Form",
			&"tier_min": 0,
			&"pool": INSIGHT,
			&"amount": 5.0,
			&"repeatable": true,
			&"max_count": 0,
		},
		{
			&"row_id": ROW_SEALED,
			&"label": "Sealed Form",
			&"tier_min": 1,
			&"pool": INSIGHT,
			&"amount": 20.0,
			&"repeatable": false,
			&"max_count": 1,
		},
		{
			&"row_id": ROW_TRANSCENDENT,
			&"label": "Transendent Form",
			&"tier_min": 2,
			&"pool": &"",
			&"amount": 0.0,
			&"repeatable": false,
			&"max_count": 1,
		},
	]
	return rule


## A second System over its own currency and its own event, so two answering the same
## occurrence is a real competition rather than one System asked twice.
func silent_bell() -> FakeSystem:
	var rule := FakeSystem.new()
	rule.id = SILENT_BELL
	rule.label = "Way of the Silent Bell"
	rule.pools = [RAGE]
	rule.earn_amount = 3.0
	rule.rows = [
		{
			&"row_id": ROW_OPEN,
			&"label": "Held Breath",
			&"tier_min": 0,
			&"pool": RAGE,
			&"amount": 2.0,
			&"repeatable": true,
			&"max_count": 0,
		}
	]
	return rule


## A System with no rows at all: the inert case ADR 0267's defaults exist for, and the only
## System whose `boards()` and `price()` are empty.
func empty_system(id: StringName) -> FakeSystem:
	var rule := FakeSystem.new()
	rule.id = id
	rule.label = String(id)
	rule.pools = []
	rule.rows = []
	rule.earn_claims = false
	return rule


func actor(name: String = "doctrine_tester") -> Actor:
	return Actor.new(StringName(name))


## Register `rule` and assert it was admitted, so a suite fails on the registration rather
## than on the behaviour it was written to prove.
func register(rule: FakeSystem) -> FakeSystem:
	var verdict := DoctrineApi.attach(rule)
	assert_eq(bool(verdict.get("ok", false)), true, "fixture registered %s" % String(rule.id))
	return rule


## An actor already opted into `rule`.
func joined_actor(rule: FakeSystem) -> Actor:
	var subject := actor()
	var verdict := DoctrineApi.join(subject, rule.system_id())
	assert_eq(bool(verdict.get("ok", false)), true, "fixture joined %s" % String(rule.id))
	return subject


## Farm `times` occurrences of `rule`'s event through the SHIPPED verb, so a suite never
## credits a balance by writing the ledger itself.
##
## It NAMES the System, which is the whole point: the unnamed verb asks every joined System
## and one occurrence pays exactly one of them, so farming one System's currency with it
## would silently pay a rival instead.
func farm(actor_value: Actor, rule: FakeSystem, times: int) -> Dictionary:
	var last: Dictionary = {}
	for _pass in maxi(0, times):
		last = DoctrineApi.earn(actor_value, {"kind": String(rule.earn_kind)}, rule.system_id())
	return last


## Seed a counter the framework has no verb for.
##
## Nothing in this module writes `points` — the rule owns its counter and advances it inside
## its own `redeem`, which is ADR 0267's one-writer rule. So a suite that wants a million
## levels has to seed it the way the rule would, and it does so through `DoctrineLedger`
## normalize rather than by hand-poking `module_data`.
func seed_points(actor_value: Actor, rule: FakeSystem, points: int, points_max: int = 0) -> void:
	var ledger := DoctrineLedger.normalize(actor_value.get_module_data(rule.data_key()))
	ledger[DoctrineLedger.KEY_POINTS] = points
	ledger[DoctrineLedger.KEY_POINTS_MAX] = points_max
	actor_value.set_module_data(rule.data_key(), ledger)


func balance_of(actor_value: Actor, rule: FakeSystem) -> float:
	var ledger := DoctrineLedger.normalize(actor_value.get_module_data(rule.data_key()))
	return float(ledger[DoctrineLedger.KEY_BALANCE])


func points_of(actor_value: Actor, rule: FakeSystem) -> int:
	return int(rule.progress(actor_value).get(&"points", 0))


func tier_of(actor_value: Actor, rule: FakeSystem) -> int:
	return int(rule.tier_for(actor_value).get(&"tier", 0))


func _is_joined(actor_value: Actor, rule: FakeSystem) -> bool:
	var ledger := DoctrineLedger.normalize(actor_value.get_module_data(rule.data_key()))
	return bool(ledger[DoctrineLedger.KEY_JOINED])


func setup() -> void:
	# The registry is process-wide static state, so a suite that did not empty it would
	# inherit whatever the previous suite registered.
	DoctrineRegistry.clear()


func teardown() -> void:
	DoctrineRegistry.clear()
