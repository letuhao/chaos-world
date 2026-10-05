extends TestCase

## ADR NNNN: the registrable System contract, and its defaults, asserted.
##
## Two halves, and the second is the one that exists to prove anything:
##
##  1. THE DEFAULTS ARE SAFE. A System is registered by something that is not this
##     repo's module — a template, a mod — so an override that is forgotten has to
##     produce an inert board rather than one that grants for free. Every default is
##     asserted here, including that `price`/`redeem` answer `{}` for a row that does
##     not exist instead of a refusal: ADR 0083 makes that a different answer, and a
##     panel that collapses them draws a refusal on a row that was never there.
##  2. THE CONTRACT IS IMPLEMENTABLE. `_FakeSystem` is a hand-written
##     implementation, it goes through the SAME assertions the defaults do, and that
##     is what proves the declared key vocabulary is satisfiable rather than
##     aspirational — AGENTS.md's LSP rule, which cannot be satisfied by an
##     interface nobody has written against.
##
## ## The purity assertions have TWO witnesses, because one can pass while the
## ## other fails
##
## `_FakeSystem.writes` counts calls that reached `set_module_data`, and the ledger
## is additionally compared BY VALUE before and after every read. A read that
## mutated the dictionary it was handed in place never calls `_store`, so the
## counter alone would report a clean board for a board that changed. The fake
## therefore reads `get_module_data`'s LIVE dictionary — copying it would make the
## second witness vacuous.
##
## Nothing here asserts module behaviour, because there is no module yet. This suite
## is the contract's own proof obligation.

## The currency the fake earns in and spends. Declared INSIDE `_FakeSystem` on
## purpose: an inner class does not reliably see the outer file's constants, and a
## test that fails to parse proves nothing.
##
## ## Suffixes that make a KEY magnitude-shaped
##
## `AGENTS.md` and ADR 0001: `core/realm_power_table.tres` is the only magnitude
## table, and a new power-shaped number needs its own ADR. The contract answers
## that with SHAPE rather than a rule a reviewer must remember — no method takes a
## realm id and none returns a multiplier — so the strongest check available is that
## the vocabulary it declares cannot even NAME one. `_magnitude_shaped` is given a
## fabricated key below, so the sweep is a check and not a tautology.
const MAGNITUDE_SUFFIXES: Array[String] = [
	"_mult",
	"_multiplier",
	"_scale",
	"_scaling",
	"_power",
	"_factor",
	"_coefficient",
]


## A hand-written implementation of the contract. An inner class rather than a
## `class_name`: this is test scaffolding, and a global name would make it look like
## a shipped System to the next reader — `test_beat_director.gd` says the same of
## `CountingSink`. It doubles as the worked example of the one thing the contract's
## docblock tells every implementer and cannot enforce for them: cast the `Variant`
## actor ONCE, at the top.
class _FakeSystem:
	extends DoctrineRule

	const CURRENCY := &"insight"
	const TIER_POINTS := 10
	const TIER_COUNT := 3
	const POINTS_PER_PURCHASE := 5
	const TIER_NAMES: Array[String] = ["transmitted", "practised", "embodied"]

	## How many times `redeem` reached the persistence seam. The first purity
	## witness, and the only one that catches a write through any other door.
	var writes := 0
	## A pool this System declares that no row spends, for the yin-yang guard's
	## negative control. Empty everywhere else.
	var unsunk_pool := &""

	func system_id() -> StringName:
		return &"way_of_the_iron_bell"

	func display_name() -> String:
		return "Way of the Iron Bell"

	func resource_ids() -> Array[StringName]:
		var out: Array[StringName] = [CURRENCY]
		if unsunk_pool != &"":
			out.append(unsunk_pool)
		return out

	func progress(actor: Variant) -> Dictionary:
		var ledger := _ledger(actor)
		return {"points": int(ledger.get("points", 0)), "points_max": 0}

	func tier_for(actor: Variant) -> Dictionary:
		var ledger := _ledger(actor)
		var tier := clampi(int(ledger.get("points", 0)) / TIER_POINTS, 0, TIER_COUNT - 1)
		return {
			"tier": tier,
			"tier_name": TIER_NAMES[tier],
			"tiers": TIER_COUNT,
			"next_tier_points": 0 if tier >= TIER_COUNT - 1 else (tier + 1) * TIER_POINTS,
		}

	func boards(_actor: Variant) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for row in _row_table():
			out.append(row.duplicate(true))
		return out

	func price(actor: Variant, row_id: StringName) -> Dictionary:
		var row := _row(row_id)
		if row.is_empty():
			return {}
		var ledger := _ledger(actor)
		var pool := StringName(row.get("pool", &""))
		var amount := float(row.get("amount", 0.0))
		var refusal := _refusal(actor, row, ledger)
		return {
			"ok": refusal == "",
			"reason": refusal,
			"row_id": row_id,
			"pool": pool,
			"amount": amount,
			"owned": _owned(ledger, row_id),
			"affordable": pool == &"" or float(ledger.get("balance", 0.0)) >= amount,
		}

	func redeem(actor: Variant, row_id: StringName) -> Dictionary:
		var row := _row(row_id)
		if row.is_empty():
			return {}
		var ledger := _ledger(actor)
		var refusal := _refusal(actor, row, ledger)
		var pool := StringName(row.get("pool", &""))
		var amount := float(row.get("amount", 0.0))
		if refusal != "":
			return _answer(row_id, pool, 0.0, refusal, [])
		var owned := _owned(ledger, row_id)
		# A COPY, then written back: the contract names `set_module_data` as the
		# persistence seam, so the write is a visible event rather than an in-place
		# mutation the ledger's owner never hears about.
		var updated := ledger.duplicate(true)
		var owned_map: Dictionary = updated.get("owned", {})
		owned_map[row_id] = owned + 1
		updated["owned"] = owned_map
		updated["balance"] = float(ledger.get("balance", 0.0)) - amount
		updated["points"] = int(ledger.get("points", 0)) + POINTS_PER_PURCHASE
		_store(actor, updated)
		# The EXISTING universal grant verb, not a stat composer of its own: it
		# already owns stacking, merging and stat-cache invalidation.
		var grant := _actor(actor).add_status(
			StatusEffect.new(StringName("doctrine_%s" % String(row_id)))
		)
		return _answer(row_id, pool, amount, "", [grant])

	func earn(_actor: Variant, event: Dictionary) -> Dictionary:
		# A PROPOSAL, and deliberately write-free: the caller that owns the event
		# arbitrates, because two Systems may answer the same occurrence.
		if StringName(event.get("kind", &"")) != &"defeat":
			return {"ok": false, "reason": DoctrineRule.NOT_CLAIMED}
		return {
			"ok": true,
			"reason": "",
			"pool": CURRENCY,
			"amount": maxf(0.0, float(event.get("amount", 1.0))),
		}

	func _refusal(actor: Variant, row: Dictionary, ledger: Dictionary) -> String:
		var pool := StringName(row.get("pool", &""))
		var amount := float(row.get("amount", 0.0))
		var row_id := StringName(row.get("row_id", &""))
		var owned := _owned(ledger, row_id)
		if int(_tier_of(actor)) < int(row.get("tier_min", 0)):
			return DoctrineRule.TIER_LOCKED
		var ceiling := maxi(1, int(row.get("max_count", 1)))
		if not bool(row.get("repeatable", false)) and owned >= ceiling:
			return DoctrineRule.ALREADY_MAXED
		# BEFORE the balance check, deliberately: a row spending a pool this System
		# never declared is a content defect, and a defect must not be reported as
		# the player's wallet being short.
		if pool != &"" and not resource_ids().has(pool):
			return DoctrineRule.UNDECLARED_POOL
		if pool != &"" and float(ledger.get("balance", 0.0)) < amount:
			return DoctrineRule.INSUFFICIENT
		return ""

	func _answer(
		row_id: StringName, pool: StringName, spent: float, reason: String, granted: Array
	) -> Dictionary:
		return {
			"ok": reason == "",
			"reason": reason,
			"row_id": row_id,
			"pool": pool,
			"spent": spent,
			"granted": granted,
		}

	func _tier_of(actor: Variant) -> int:
		return int(tier_for(actor).get("tier", 0))

	## The LIVE ledger. Not a copy, on purpose — see the suite docstring: copying
	## would hide an in-place mutation from the only witness that can see one.
	func _ledger(actor: Variant) -> Dictionary:
		return _actor(actor).get_module_data(data_key())

	func _store(actor: Variant, data: Dictionary) -> void:
		writes += 1
		_actor(actor).set_module_data(data_key(), data)

	func _owned(ledger: Dictionary, row_id: StringName) -> int:
		var owned: Dictionary = ledger.get("owned", {})
		return int(owned.get(row_id, 0))

	## The actor arrives as `Variant` because `contracts/` is a leaf layer and may
	## not name `Actor`; casting once here is what the contract's docblock asks of
	## every implementation.
	func _actor(value: Variant) -> Actor:
		return value as Actor

	func _row(row_id: StringName) -> Dictionary:
		for row in _row_table():
			if StringName(row.get("row_id", &"")) == row_id:
				return row
		return {}

	func _row_table() -> Array[Dictionary]:
		return [
			{
				"row_id": &"open_form",
				"label": "Open Form",
				"tier_min": 0,
				"pool": CURRENCY,
				"amount": 5.0,
				"repeatable": true,
				"max_count": 0,
			},
			{
				"row_id": &"sealed_form",
				"label": "Sealed Form",
				"tier_min": 1,
				"pool": CURRENCY,
				"amount": 20.0,
				"repeatable": false,
				"max_count": 1,
			},
			{
				"row_id": &"first_light",
				"label": "First Light",
				"tier_min": 0,
				"pool": &"",
				"amount": 0.0,
				"repeatable": false,
				"max_count": 1,
			},
			# Spends a pool this System never declares, and costs more than a broke
			# actor has, so the refusal it draws proves the undeclared-pool check
			# runs BEFORE the affordability one.
			{
				"row_id": &"ghost_row",
				"label": "Ghost Row",
				"tier_min": 0,
				"pool": &"ghost",
				"amount": 7.0,
				"repeatable": false,
				"max_count": 1,
			},
		]


func setup() -> void:
	# The floor every body below clears, so a body that dies on its first line is
	# reported as an abort rather than as a suite that quietly asserted nothing.
	expect_assertions(4)


# --- 1. the defaults fail SAFE ------------------------------------------------------


## A System that overrides NOTHING is an inert board, never a generous one. Each
## assertion is one way a stub could lie: an id that registers, a key two Systems
## share, a price that reads as payable, an earn that pays out.
func test_a_rule_that_overrides_nothing_is_inert() -> void:
	var actor := Actor.new(&"hero")
	var bare := DoctrineRule.new()
	assert_eq(bare.system_id(), &"", "no id: an unnamed System is unregistrable")
	assert_eq(bare.display_name(), "", "no name")
	assert_eq(bare.data_key(), &"", "and no persistence key, so two unnamed Systems cannot collide")
	assert_eq(bare.resource_ids().is_empty(), true, "declares no pool")
	assert_eq(bare.boards(actor).is_empty(), true, "sells nothing")
	assert_eq(
		bare.price(actor, &"anything").is_empty(),
		true,
		"an unknown row does not exist: {} and not a refusal"
	)
	assert_eq(bare.redeem(actor, &"anything").is_empty(), true, "and it redeems to nothing either")
	var tier := bare.tier_for(actor)
	assert_eq(int(tier.get("tier", -1)), 0, "tier 0")
	assert_eq(int(tier.get("tiers", -1)), 0, "of NO tiers at all, so every gated row stays locked")
	var earn := bare.earn(actor, {"kind": "defeat"})
	assert_eq(
		bool(earn.get("ok", true)), false, "a System that never overrides earn claims nothing"
	)
	assert_eq(String(earn.get("reason", "")), DoctrineRule.NOT_CLAIMED, "and says so by name")


## The declared key lists are the contract's shape, so every default has to satisfy
## the list that governs it. A widening that adds a key fails HERE, naming the key,
## which is what stops the shape drifting away from the defaults that produce it.
func test_every_default_payload_carries_its_required_keys() -> void:
	var actor := Actor.new(&"hero")
	var bare := DoctrineRule.new()
	var payloads: Array = [
		[bare.progress(actor), DoctrineRule.PROGRESS_KEYS],
		[bare.tier_for(actor), DoctrineRule.TIER_KEYS],
		[bare.earn(actor, {}), DoctrineRule.EARN_KEYS],
	]
	var checked := 0
	for entry in payloads:
		var payload: Dictionary = entry[0]
		var required: Array[StringName] = entry[1]
		checked += 1
		assert_eq(
			DoctrineRule.missing_keys(payload, required).is_empty(),
			true,
			"every key of %s is present in %s" % [required, payload.keys()]
		)
		assert_eq(
			DoctrineRule.is_primitive_payload(payload),
			true,
			"and the payload is primitives-only: %s" % [payload]
		)
	assert_eq(checked, 3, "the sweep above actually read three payloads, not none")


# --- 2. the fake satisfies the contract ---------------------------------------------


## LSP, as a test rather than a hope: every payload a real implementation returns
## passes the same shape and type checks the defaults do. This is what proves the
## declared vocabulary is satisfiable — an interface no one has written against has
## never been shown to be implementable.
func test_the_fake_satisfies_every_declared_key_set() -> void:
	var actor := _funded(100.0, 5)
	var system := _FakeSystem.new()
	var rows := system.boards(actor)
	assert_eq(rows.size(), 4, "the fake really publishes a board")
	for row in rows:
		assert_eq(
			DoctrineRule.missing_keys(row, DoctrineRule.ROW_KEYS).is_empty(),
			true,
			"every row carries ROW_KEYS: %s" % [row]
		)
		assert_eq(
			DoctrineRule.is_primitive_payload(row), true, "and it is primitives-only: %s" % [row]
		)
	var priced := system.price(actor, &"open_form")
	assert_eq(
		DoctrineRule.missing_keys(priced, DoctrineRule.PRICE_KEYS).is_empty(),
		true,
		"price carries PRICE_KEYS: %s" % [priced]
	)
	var bought := system.redeem(actor, &"open_form")
	assert_eq(
		DoctrineRule.missing_keys(bought, DoctrineRule.REDEEM_KEYS).is_empty(),
		true,
		"redeem carries REDEEM_KEYS: %s" % [bought]
	)
	var earned := system.earn(actor, {"kind": "defeat", "amount": 3.0})
	assert_eq(
		DoctrineRule.missing_keys(earned, DoctrineRule.EARN_KEYS).is_empty(),
		true,
		"earn carries EARN_KEYS: %s" % [earned]
	)
	assert_eq(
		(
			DoctrineRule.is_primitive_payload(priced)
			and DoctrineRule.is_primitive_payload(bought)
			and DoctrineRule.is_primitive_payload(earned)
		),
		true,
		"and every payload the fake answers with is primitives-only"
	)


## `boards` and `price` must not write, or a board cannot be drawn and a price
## cannot be trusted. TWO witnesses: the seam counter catches a write through
## `set_module_data`, the by-value snapshot catches one that mutated the dictionary
## it was handed in place.
func test_the_reads_do_not_write_and_redeem_is_the_only_mutation() -> void:
	var actor := _funded(10.0)
	var system := _FakeSystem.new()
	var before := str(actor.get_module_data(system.data_key()))
	system.boards(actor)
	system.price(actor, &"open_form")
	system.progress(actor)
	system.tier_for(actor)
	system.earn(actor, {"kind": "defeat"})
	assert_eq(system.writes, 0, "no read reached the persistence seam")
	assert_eq(str(actor.get_module_data(system.data_key())), before, "the ledger is byte-identical")
	assert_almost_eq(float(_ledger(system, actor).get("balance", -1.0)), 10.0, "balance untouched")
	assert_almost_eq(float(_ledger(system, actor).get("points", -1.0)), 0.0, "counter untouched")
	system.redeem(actor, &"open_form")
	assert_eq(system.writes, 1, "redeem is the one write")
	assert_almost_eq(float(_ledger(system, actor).get("balance", -1.0)), 5.0, "and it spent")


## `earn` is a PROPOSAL and the caller applies it. That is the asymmetry the contract
## docblock argues for — an earn is event-driven and two Systems may answer the same
## occurrence, so the arbitration belongs to whoever owns the event — and it is only
## visible if a test shows the balance moving when the CALLER writes and not when the
## rule is asked.
func test_earn_proposes_and_the_caller_applies() -> void:
	var actor := _funded(0.0)
	var system := _FakeSystem.new()
	var declined := system.earn(actor, {"kind": "purchase"})
	assert_eq(bool(declined.get("ok", true)), false, "an event this System wants nothing from")
	assert_eq(String(declined.get("reason", "")), DoctrineRule.NOT_CLAIMED, "is declined by name")
	var proposal := system.earn(actor, {"kind": "defeat", "amount": 4.0})
	assert_eq(bool(proposal.get("ok", false)), true, "a defeat pays")
	assert_almost_eq(float(proposal.get("amount", -1.0)), 4.0, "and names the amount")
	assert_eq(system.writes, 0, "the rule wrote nothing: the balance is still the caller's to move")
	# The caller applying it, by hand — which is the whole point.
	actor.set_module_data(system.data_key(), {"balance": 4.0, "points": 0, "owned": {}})
	assert_almost_eq(float(_ledger(system, actor).get("balance", -1.0)), 4.0, "the caller paid it")


## The grant goes through `Actor.add_status`, the verb that already owns stacking,
## merging and cache invalidation — so the contract adds no second grant path, and a
## status landing is observable from outside the System that granted it.
func test_redeem_grants_through_the_existing_universal_verb() -> void:
	var actor := _funded(10.0)
	var system := _FakeSystem.new()
	assert_eq(actor.has_status(&"doctrine_open_form"), false, "nothing granted yet")
	var answer := system.redeem(actor, &"open_form")
	assert_eq(actor.has_status(&"doctrine_open_form"), true, "the status landed through add_status")
	assert_almost_eq(float(answer.get("spent", -1.0)), 5.0, "and the answer reports what it spent")
	var granted: Array = answer.get("granted", [])
	assert_eq(granted.size(), 1, "one grant reported")
	assert_eq(
		bool((granted[0] as Dictionary).get("ok", false)),
		true,
		"and the verb's own answer came back ok"
	)
	assert_eq(
		DoctrineRule.is_primitive_payload(answer), true, "the whole answer is primitives-only"
	)


## ADR 0083's three states, on the two verbs where they must differ: no such row,
## a row that exists and refuses, and a row that succeeds.
func test_does_not_exist_is_not_a_refusal() -> void:
	var actor := _funded(100.0, 5)
	var system := _FakeSystem.new()
	assert_eq(
		system.price(actor, &"no_such_row").is_empty(), true, "an unpriced row does not exist"
	)
	assert_eq(system.redeem(actor, &"no_such_row").is_empty(), true, "and it redeems to nothing")
	var locked := system.price(actor, &"sealed_form")
	assert_eq(bool(locked.get("ok", true)), false, "a row behind an unreached tier is refused")
	assert_eq(String(locked.get("reason", "")), DoctrineRule.TIER_LOCKED, "by name")
	assert_eq(
		DoctrineRule.REASONS.has(String(locked.get("reason", ""))),
		true,
		"and the name is in the contract's closed set"
	)
	var bought := system.price(actor, &"open_form")
	assert_eq(bool(bought.get("ok", false)), true, "an affordable row is not refused")
	assert_eq(String(bought.get("reason", "x")), "", "and carries no reason on success")


## A content defect must never be reported as the player's wallet being short: the
## ghost row costs more than a broke actor has AND spends a pool the System never
## declared, so which reason comes back proves the order of the checks.
func test_an_undeclared_pool_is_diagnosed_before_affordability() -> void:
	var actor := _funded(0.0)
	var system := _FakeSystem.new()
	var ghost := system.price(actor, &"ghost_row")
	assert_eq(String(ghost.get("reason", "")), DoctrineRule.UNDECLARED_POOL, "the defect wins")
	assert_eq(
		bool(ghost.get("affordable", true)), false, "and the row is still reported unaffordable"
	)
	var broke := system.price(actor, &"open_form")
	assert_eq(
		String(broke.get("reason", "")),
		DoctrineRule.INSUFFICIENT,
		"a real shortfall is its own reason"
	)
	var refused := system.redeem(actor, &"ghost_row")
	assert_eq(bool(refused.get("ok", true)), false, "and the ghost row cannot be bought")
	assert_eq(system.writes, 0, "a refusal spends nothing")


## The ledger records the purchase, so a second press of a non-repeatable row is a
## refusal with a name rather than a silent double charge.
func test_a_spent_row_is_refused_and_the_ledger_says_so() -> void:
	var actor := _funded(0.0)
	var system := _FakeSystem.new()
	var first := system.redeem(actor, &"first_light")
	assert_eq(bool(first.get("ok", false)), true, "a free row buys")
	assert_eq(
		int(_ledger(system, actor).get("owned", {}).get(&"first_light", 0)),
		1,
		"the ledger records it"
	)
	var second := system.redeem(actor, &"first_light")
	assert_eq(bool(second.get("ok", true)), false, "a second press is refused")
	assert_eq(String(second.get("reason", "")), DoctrineRule.ALREADY_MAXED, "by name")
	assert_almost_eq(float(second.get("spent", -1.0)), 0.0, "and a refusal spends nothing")
	assert_eq(system.writes, 1, "the refused press wrote nothing")


## `tier_for` is DERIVED from `progress` and from nothing else — no realm, no ladder
## index, no second factor — which is the shape answer to "does a System scale with
## power". A counter with no ceiling stays uncapped, because `AGENTS.md` bounds the
## OUTPUT and never the input.
func test_the_tier_is_derived_from_the_counter_and_nothing_else() -> void:
	var actor := _funded(0.0)
	var system := _FakeSystem.new()
	assert_eq(int(system.tier_for(actor).get("tier", -1)), 0, "tier 0 on a fresh ledger")
	actor.set_module_data(system.data_key(), {"balance": 0.0, "points": 25, "owned": {}})
	assert_eq(int(system.progress(actor).get("points", -1)), 25, "the counter moved")
	assert_eq(int(system.tier_for(actor).get("tier", -1)), 2, "and the tier followed it")
	assert_eq(String(system.tier_for(actor).get("tier_name", "")), "embodied", "with its own name")
	assert_eq(
		int(system.tier_for(actor).get("next_tier_points", -1)),
		0,
		"an uncapped counter's top tier has no next"
	)
	assert_eq(int(system.progress(actor).get("points_max", -1)), 0, "and no ceiling of its own")


# --- 3. the design rules the shape has to make checkable ---------------------------


## `AGENTS.md`'s yin-yang rule: a resource generated with no place to spend it is an
## accumulating debt. `resource_ids()` is the earn side and `boards()` the sink side,
## and this is the only place the pairing is checkable while the module does not
## exist. The negative control is what stops the first assertion being vacuous.
func test_every_declared_currency_has_a_sink() -> void:
	var actor := _funded(100.0)
	var system := _FakeSystem.new()
	assert_eq(system.resource_ids().size(), 1, "one currency declared")
	assert_eq(
		_unsunk(system, actor).is_empty(), true, "and a row spends it, so the earn has a sink"
	)
	system.unsunk_pool = &"favor"
	var orphans := _unsunk(system, actor)
	assert_eq(orphans.size(), 1, "a declared pool no row spends IS reported")
	assert_eq(String(orphans[0]), "favor", "and it is the declared one")


## The strongest available check on "a doctrine grants values and rates, never a
## magnitude": the vocabulary the contract declares cannot NAME one. A key added for
## a multiplier fails here by name rather than in a review nobody reads.
func test_the_declared_vocabulary_cannot_name_a_magnitude() -> void:
	var declared := _declared_keys()
	assert_ne(declared.size(), 0, "the sweep reads a non-empty vocabulary")
	var offenders: Array[String] = []
	for key in declared:
		if _magnitude_shaped(StringName(key)):
			offenders.append(String(key))
	assert_eq(
		offenders.is_empty(),
		true,
		"these keys name a magnitude, so a doctrine could scale: %s" % [offenders]
	)
	# The negative control, without which the sweep above is a tautology.
	assert_eq(_magnitude_shaped(&"damage_multiplier"), true, "the predicate fires on a multiplier")
	assert_eq(_magnitude_shaped(&"tier_power"), true, "and on a power")
	assert_eq(_magnitude_shaped(&"doctrine_points"), false, "and does not fire on a counter")


## The primitives-only rule, on each shape a payload actually takes here: a value, a
## nested array, a dictionary value, and a non-primitive KEY.
func test_a_payload_smuggling_a_type_is_refused() -> void:
	assert_eq(
		DoctrineRule.is_primitive_payload(RefCounted.new()), false, "an object is not a primitive"
	)
	assert_eq(
		DoctrineRule.is_primitive_payload(Callable(self, "setup")), false, "nor is a callable"
	)
	assert_eq(DoctrineRule.is_primitive_payload({"grant": Resource.new()}), false, "nor a resource")
	assert_eq(
		DoctrineRule.is_primitive_payload([1, RefCounted.new()]), false, "nor one inside an array"
	)
	var keyed := {}
	keyed[RefCounted.new()] = 1
	assert_eq(DoctrineRule.is_primitive_payload(keyed), false, "nor an object as a KEY")
	assert_eq(
		DoctrineRule.is_primitive_payload(
			{"ok": true, "reason": "", "pool": &"insight", "amount": 1.5, "owned": 0}
		),
		true,
		"the primitives themselves pass"
	)


## The recursive walk terminates because its depth is a constant, and a payload too
## deep to verify is REFUSED rather than trusted (AGENTS.md: recursion needs a depth
## cap that a `while` scan cannot see for it).
func test_the_depth_cap_is_a_bound_and_past_it_is_refused() -> void:
	var within := _nested(DoctrineRule.MAX_PAYLOAD_DEPTH - 1)
	var beyond := _nested(DoctrineRule.MAX_PAYLOAD_DEPTH)
	assert_eq(DoctrineRule.is_primitive_payload(within), true, "a payload at the cap is verified")
	assert_eq(
		DoctrineRule.is_primitive_payload(beyond), false, "and past it is refused, not trusted"
	)
	assert_eq(within.size(), 1, "the probe is really nested, so the refusal is about depth")
	assert_eq(beyond.size(), 1, "on both sides of the boundary")
	assert_eq(DoctrineRule.MAX_PAYLOAD_DEPTH >= 2, true, "the cap is a real bound")
	assert_eq(DoctrineRule.MAX_PAYLOAD_DEPTH <= 16, true, "and small enough to be one")


## One spelling of the save key, derived rather than hand-written per System — and
## none at all for an unnamed one, or two of them would share a dictionary.
func test_the_persistence_key_is_derived_and_an_unnamed_system_has_none() -> void:
	var system := _FakeSystem.new()
	var key := system.data_key()
	assert_ne(key, &"", "a named System has a key")
	assert_eq(
		String(key).begins_with(String(DoctrineRule.DATA_KEY_PREFIX)),
		true,
		"under the shared prefix"
	)
	assert_eq(
		String(key),
		"%s%s" % [String(DoctrineRule.DATA_KEY_PREFIX), String(system.system_id())],
		"derived from the id, so there is one spelling of it"
	)
	assert_eq(DoctrineRule.new().data_key(), &"", "and an unnamed System has none")


## A caller that must validate a refusal needs the closed set to be closed: every
## reason the contract names is present, and none is listed twice.
func test_the_refusal_reasons_are_a_closed_deduplicated_set() -> void:
	assert_ne(DoctrineRule.REASONS.is_empty(), true, "the set is not empty")
	var unique := {}
	for reason in DoctrineRule.REASONS:
		unique[reason] = true
	assert_eq(unique.size(), DoctrineRule.REASONS.size(), "and carries no duplicate name")
	for reason in DoctrineRule.REASONS:
		assert_eq(String(reason).is_empty(), false, "'%s' is a name, not the empty string" % reason)


## What a screen shows when the player cannot afford the cheapest row: the row is
## still priced, still named, and the reason is one a panel can compare. A silent
## `{}` here would hide the board entirely.
func test_an_unaffordable_row_is_still_rendered_with_a_named_reason() -> void:
	var actor := _funded(0.0)
	var system := _FakeSystem.new()
	var quoted := system.price(actor, &"open_form")
	assert_eq(bool(quoted.get("ok", true)), false, "not payable")
	assert_eq(bool(quoted.get("affordable", true)), false, "and reported unaffordable")
	assert_eq(
		String(quoted.get("reason", "")),
		DoctrineRule.INSUFFICIENT,
		"with the reason a panel compares"
	)
	assert_almost_eq(float(quoted.get("amount", -1.0)), 5.0, "while still quoting the price")
	assert_eq(String(quoted.get("row_id", "")), "open_form", "and naming the row")


# --- helpers -----------------------------------------------------------------------


## An actor carrying one System's seeded ledger. Seeded through `set_module_data` —
## the seam the contract names — so the fake's reads see a LIVE dictionary and an
## in-place mutation would be visible.
func _funded(balance: float, points: int = 0) -> Actor:
	var actor := Actor.new(&"hero")
	actor.set_module_data(
		_FakeSystem.new().data_key(),
		{"points": points, "points_max": 0, "balance": balance, "owned": {}}
	)
	return actor


func _ledger(system: DoctrineRule, actor: Actor) -> Dictionary:
	return actor.get_module_data(system.data_key())


## Pools `system` declares that no row on its board spends: an accumulating debt,
## expressed as a question the contract can answer. Both walks are over the rule's
## own returned collections and neither appends to what it is walking.
func _unsunk(system: DoctrineRule, actor: Actor) -> Array[StringName]:
	var spent := {}
	for row in system.boards(actor):
		var pool := StringName(row.get("pool", &""))
		if pool != &"":
			spent[pool] = true
	var out: Array[StringName] = []
	for pool_id in system.resource_ids():
		if not spent.has(pool_id):
			out.append(pool_id)
	return out


## Every key the contract DECLARES, read from its own lists rather than from a second
## copy kept here, which is the copy that goes stale (BL-0619).
func _declared_keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for keys in [
		DoctrineRule.ROW_KEYS,
		DoctrineRule.PRICE_KEYS,
		DoctrineRule.REDEEM_KEYS,
		DoctrineRule.EARN_KEYS,
		DoctrineRule.PROGRESS_KEYS,
		DoctrineRule.TIER_KEYS,
	]:
		for key in keys:
			out.append(key)
	return out


func _magnitude_shaped(key: StringName) -> bool:
	var text := String(key)
	for suffix in MAGNITUDE_SUFFIXES:
		if text.ends_with(suffix):
			return true
	return false


## `levels` nested dictionaries around one int, built from the inside out. `levels`
## is the bound and the body runs once per value in it, so this terminates on any
## input — a negative level is an empty range, not a wait.
func _nested(levels: int) -> Dictionary:
	var value: Variant = 1
	for _step in range(levels):
		value = {"next": value}
	return value as Dictionary
