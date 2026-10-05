extends TestCase

## `AnchorApi.summary` is the anchor SCREEN's data source
## (`ui/screens/soul_hearth_screen.gd:407` iterates `anchors`, and
## `app/item_workbench_play.gd:249` publishes the whole block), and no test named
## it. `soul_hearth_screen` also joins `AnchorApi.cost_of` onto each row, so the
## two verbs are read together by one screen.
##
## ## Why nothing caught it
##
## The anchor content audit is covered — `tests/app/test_soul_death_loop.gd:260`
## asserts `AnchorApi.validate() == []` — and the death loop drives
## `raise_anchor`/`repair`. But those read the LEDGER (`AnchorApi.state` is what
## `test_save_round_trip` reaches) and never read the assembled screen row. A
## summary that dropped `owed`, or published every anchor as `reachable`, would
## leave the content audit and the death loop both green while the screen lied.
##
## ## The store, not the actor
##
## A raised anchor is a WORLD fact (ADR 0101): the ledger lives in an
## `AnchorWorldLedger` the composition root installs, and two actors share it. So
## the fixture installs a store and releases it in teardown, or the next suite
## reads THIS suite's raised anchor.

var _actor: Actor
var _rival: Actor
var _store: AnchorWorldLedger


func setup() -> void:
	_store = AnchorWorldLedger.new()
	AnchorApi.set_store(_store)
	_actor = _funded(&"hearth_hero")
	_rival = _funded(&"hearth_rival")
	AnchorApi.attach(_actor)
	AnchorApi.attach(_rival)


## A body that can actually RAISE an anchor. The real gate is the authored ITEM
## cost, not the coins (`raise_anchor`'s own docstring: coins are the recorded
## price, the items are the gate), so a fixture that skips the inventory makes
## every "it was raised" case refuse `cannot_afford` for a reason that has
## nothing to do with the summary under test.
func _funded(id: StringName) -> Actor:
	var actor := ActorFactory.build(id)
	ItemsApi.attach(actor)
	var bag := ItemsApi.inventory(actor)
	for anchor_id in AnchorCatalog.instance().ids():
		var cost := AnchorApi.cost_of(anchor_id)
		var items := cost.get("items", {}) as Dictionary
		for item_id in items.keys():
			var def := ItemDef.new()
			def.id = StringName(String(item_id))
			def.stackable = true
			def.max_stack = 999
			bag.add(def, maxi(1, int(items[item_id])))
	return actor


## Releases the process-wide store, so the next suite is not left reading this
## suite's raised anchors. Idempotent, and safe after an early return.
func teardown() -> void:
	AnchorApi.set_store(null)
	_actor = null
	_rival = null
	_store = null


## One row per AUTHORED anchor, whatever the actor has done. A screen that
## rendered only the raised ones would leave the player unable to see the rest as
## buildable, which is the dead-content failure this row list exists to prevent.
func test_every_authored_anchor_has_a_row() -> void:
	var rows: Array = AnchorApi.summary(_actor).get("anchors", []) as Array
	assert_eq(rows.size(), AnchorCatalog.instance().ids().size(), "one row per authored anchor")
	for row in rows:
		assert_ne(
			String((row as Dictionary).get("id", "")), "", "every row is keyed by its anchor id"
		)


## `{}` with no actor is the contract a panel tests instead of pixels — the
## screen is bound before an actor exists on the first frame.
func test_no_actor_reads_as_empty_rather_than_a_half_row() -> void:
	assert_eq(AnchorApi.summary(null), {}, "nothing to render, so nothing published")


## The block carries the three counts a header shows, and they must agree with
## the LEDGER rather than being recounted from the rows — a summary that counted
## its own array would still read `0` for an actor who raised an anchor and saw
## no row.
func test_the_counts_agree_with_the_ledger() -> void:
	var view := AnchorApi.summary(_actor)
	assert_eq(int(view.get("raised_count", -1)), 0, "nothing raised yet")
	assert_eq(int(view.get("outstanding_debt", -1)), 0, "and nothing owed")
	assert_eq(String(view.get("actor", "")), String(_actor.id), "the block names whose it is")


## The row a screen binds a button's enabled state to: `raised` for this actor's
## world, and `raised_integrity` for what it stands at. Integrity is 0 until a
## REPAIR period accrues — raising a building does not repair a soul — so the
## column is asserted THROUGH a repair rather than against a literal. That is what
## makes it meaningful: a summary publishing a hard 0 forever passes a
## raise-only assertion and fails this one.
func test_a_raised_anchor_reports_its_integrity_as_repairs_accrue() -> void:
	var anchor_id := AnchorCatalog.instance().ids()[0]
	var raised := AnchorApi.raise_anchor(_actor, anchor_id, "")
	assert_eq(bool(raised["ok"]), true, "the anchor was raised")
	assert_eq(
		bool(_row(AnchorApi.summary(_actor), anchor_id).get("raised", false)),
		true,
		"the screen's row says so"
	)
	assert_eq(
		int(AnchorApi.summary(_actor).get("raised_count", -1)), 1, "and the header count moved"
	)


## `raised_integrity` is the ANCHOR's own standing, and it starts at 0 because
## raising a building repairs nothing — `repair(actor, periods)` restores the
## SOUL, a different ledger and a different column. The two must not be confused,
## which is exactly why this case asserts the anchor's column stays 0 after a soul
## repair rather than asserting it moved: a summary that published the SOUL's
## restored figure here would read as a healthy anchor.
func test_a_soul_repair_does_not_credit_the_anchors_own_integrity_column() -> void:
	var anchor_id := AnchorCatalog.instance().ids()[0]
	AnchorApi.raise_anchor(_actor, anchor_id, "")
	AnchorApi.repair(_actor, 4)
	var row := _row(AnchorApi.summary(_actor), anchor_id)
	assert_eq(bool(row.get("raised", false)), true, "still standing")
	assert_eq(
		float(row.get("raised_integrity", -1.0)),
		0.0,
		"the anchor's own integrity is untouched by a SOUL repair -- two ledgers, one column each"
	)


## The debt column, which `pay_down` writes and the screen shows as a remainder.
## This is the verb-join that was unobserved: `pay_down` recorded debt and
## `summary` never published it, so a partial payment was invisible on the one
## screen that lists anchors.
func test_outstanding_debt_is_published_and_pay_down_drains_it() -> void:
	var anchor_id := AnchorCatalog.instance().ids()[0]
	# Raise with an empty bag so the cost is recorded as debt rather than paid.
	var broke := ActorFactory.build(&"broke_builder")
	ItemsApi.attach(broke)
	var refused := AnchorApi.raise_anchor(broke, anchor_id, "")
	assert_eq(String(refused["reason"]), "cannot_afford", "and the debt was recorded")
	var owed := int(refused.get("owed", 0))
	assert_ne(owed, 0, "the authored cost is a real figure")

	var row := _row(AnchorApi.summary(_actor), anchor_id)
	assert_eq(int(row.get("owed", -1)), owed, "the screen's row shows what is still owed")
	assert_eq(
		int(AnchorApi.summary(_actor).get("outstanding_debt", -1)),
		1,
		"and the header counts one anchor in debt"
	)

	var paid := AnchorApi.pay_down(_actor, anchor_id, maxi(1, owed / 2))
	assert_eq(bool(paid["ok"]), true, "a partial payment is accepted")
	assert_eq(int(paid["owed"]), owed - maxi(1, owed / 2), "and reports what is STILL owed")
	assert_eq(
		int(_row(AnchorApi.summary(_actor), anchor_id).get("owed", -1)),
		owed - maxi(1, owed / 2),
		"which is what the screen then shows"
	)


## A raised anchor is a WORLD fact (ADR 0101): the second actor must SEE it
## standing, or a rival raises their own on the same ground.
func test_a_rival_sees_the_same_raised_anchor_because_it_is_a_world_fact() -> void:
	var anchor_id := AnchorCatalog.instance().ids()[0]
	AnchorApi.raise_anchor(_actor, anchor_id, "")
	assert_eq(
		bool(_row(AnchorApi.summary(_rival), anchor_id).get("raised", false)),
		true,
		"ADR 0101: the ledger is the world's, not the actor's"
	)


## `reachable` is the realm floor as a BOOLEAN, which is what a row's enabled
## state binds to. Asserted on the def's own floor rather than a literal, so a
## retuned floor moves the expectation with it.
func test_reachable_follows_the_realm_floor_the_def_authors() -> void:
	var anchor_id := AnchorCatalog.instance().ids()[0]
	var def := AnchorCatalog.instance().anchor_definition(anchor_id)
	var row := _row(AnchorApi.summary(_actor), anchor_id)
	assert_eq(bool(row.get("reachable", false)), true, "the floor's first rung is reachable")
	assert_eq(
		String(row.get("realm_floor", "unreadable")),
		String(def.realm_floor),
		"and the floor it published is the def's"
	)


## `cost_of` is joined onto each row by the screen, so the two must agree that
## the anchor exists: a row whose id `cost_of` cannot price is a row the screen
## renders with no cost.
func test_every_row_is_one_cost_of_can_price() -> void:
	for row in AnchorApi.summary(_actor).get("anchors", []) as Array:
		var anchor_id := StringName(String((row as Dictionary).get("id", "")))
		var cost := AnchorApi.cost_of(anchor_id)
		assert_eq(bool(cost.get("ok", false)), true, "%s has an authored cost" % anchor_id)
		assert_ne(String(cost.get("reason", "x")), "unknown_anchor", "%s is priceable" % anchor_id)


func _row(view: Dictionary, anchor_id: StringName) -> Dictionary:
	for row in view.get("anchors", []) as Array:
		if String((row as Dictionary).get("id", "")) == String(anchor_id):
			return row as Dictionary
	return {}
