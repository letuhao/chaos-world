extends "res://tests/modules/doctrine/doctrine_fixture_kit.gd"

## The TEMPLATE mod, loaded through the REAL pipeline (ADR 0267, ADR 0273,
## ADR 0275). This is the slice that answers "can a System ship as a mod at all",
## and it answers it the only way that counts: the loader discovers the mod's
## `mod.json`, the runtime plays its `stats.json` through the sixth seam, the
## registry resolves the api path, the mod's own entry point admits its Systems
## from its own numbers, and everything after that goes through [DoctrineApi].
##
## ## What is NOT shared with the kit, and why
##
## The kit's worked System is a CONTRACT fixture; this suite's System ships as a
## MOD, so sharing it would be the second copy the kit exists to prevent. Only the
## PLUMBING is inherited — `setup`/`teardown` emptying the process-wide registry
## above all — plus the [DoctrineRule]-typed readers below, because the kit's own
## are typed to its `FakeSystem`.

## The template mod's own directory, and the tree it ships inside.
const MOD_DIR := "res://tests/fixtures/mods/doctrine_system"
const FIXTURES_DIR := "res://tests/fixtures/mods"
const MOD_ID := "w8_fixture_doctrine_system"
const MODULE_NAME := "w8_fixture_doctrine"
const API_PATH := "res://tests/fixtures/mods/doctrine_system/api.gd"

## The ids the mod's own JSON declares, spelled so a failure names the value.
const MARK := &"w8_template_mark"
const FIRST := &"w8_template_first"
const SECOND := &"w8_template_second"
const ROW_CHEAP := &"r_cheap"
const ROW_DEAR := &"r_dear"
const EVENT_KIND := &"hunt"

# --- The load path ---------------------------------------------------------


## The PRODUCTION path: `ModBoot.run` computes the order, folds the
## registrations, publishes the boot and fires `on_load` — which is what calls
## [method DoctrineTemplateModApi.boot] through the manifest's `callable` spec.
## A direct `boot(ctx)` call proves the mod's arithmetic and nothing about the
## seam, so this leg is the one that goes red when the production firing is
## removed. `finalize` runs before the firing because it is what reads
## `stats.json` and puts the declared pools on the context; the other order
## admits Systems with no pools, and every priced row is refused as
## `UNDECLARED_POOL`.
func _load_mod() -> Dictionary:
	DoctrineTemplateModApi.last_boot_report = {}
	var boot := ModBoot.new()
	var out := boot.run([MOD_DIR])
	var registrations: Dictionary = boot.registrations
	boot.free()
	var contexts: Array = out.get("contexts", [])
	return {
		"loaded": out,
		"context": contexts[0] if not contexts.is_empty() else null,
		"report": DoctrineTemplateModApi.last_boot_report,
		"registrations": registrations,
	}


## Load and admit, for the tests about behaviour rather than about the load path.
func _boot_mod() -> DoctrineRule:
	var report: Dictionary = _load_mod()["report"]
	assert_eq(
		bool(report["ok"]), true, "the template admitted everything: %s" % str(report["refused"])
	)
	return _system(FIRST)


## The System as the REGISTRY holds it, never the mod's own copy.
func _system(id: StringName) -> DoctrineRule:
	var rule := DoctrineRegistry.find(id)
	assert_ne(rule, null, "system '%s' is registered" % str(id))
	return rule


func _joined_actor(rule: DoctrineRule) -> Actor:
	var subject := actor()
	var verdict := DoctrineApi.join(subject, rule.system_id())
	assert_eq(bool(verdict.get("ok", false)), true, "joined '%s'" % str(rule.system_id()))
	return subject


func _farm(subject: Actor, rule: DoctrineRule, times: int) -> Dictionary:
	var last: Dictionary = {}
	# The count is a LITERAL argument and this walk appends to `last` only, so it
	# terminates on its own bound, not on a container it grows (INC-0002).
	for _pass in maxi(0, times):
		last = DoctrineApi.earn(subject, {"kind": str(EVENT_KIND)}, rule.system_id())
	return last


func _ledger(subject: Actor, rule: DoctrineRule) -> Dictionary:
	return DoctrineLedger.normalize(subject.get_module_data(rule.data_key()))


func _balance(subject: Actor, rule: DoctrineRule) -> float:
	return float(_ledger(subject, rule)[DoctrineLedger.KEY_BALANCE])


func _points(subject: Actor, rule: DoctrineRule) -> int:
	return int(rule.progress(subject).get(&"points", 0))


func _joined(subject: Actor, rule: DoctrineRule) -> bool:
	return bool(_ledger(subject, rule)[DoctrineLedger.KEY_JOINED])


## `String`-keyed, because `Actor.to_dict` converts only the OUTER module_data key
## and an inner StringName key returns as a String after a reload.
func _owned(subject: Actor, rule: DoctrineRule, row_id: StringName) -> int:
	var owned: Variant = _ledger(subject, rule)[DoctrineLedger.KEY_OWNED]
	if not owned is Dictionary:
		return 0
	return int((owned as Dictionary).get(str(row_id), 0))


# --- The tests --------------------------------------------------------------


## The whole point of the slice: the mod is FOUND by the loader and its api path
## RESOLVES through the module registry. A `preload` and a direct instantiation
## would pass every test below this one and prove nothing about the seams.
func test_the_template_is_discovered_and_its_api_path_resolves() -> void:
	var out := ModsApi.load_order([MOD_DIR])
	assert_eq(bool(out["ok"]), true, "loaded: %s" % str(out.get("detail", "")))
	assert_eq((out["order"] as Array).size(), 1, "one mod under the template's own root")
	assert_eq(str(out["order"][0]), MOD_ID, "and the manifest's own id is what loads")
	var ctx: RegistrationContext = out["contexts"][0]
	assert_eq(ctx.mod_id, MOD_ID, "one context, stamped with the mod that owns it")
	assert_eq(ctx.modules.size(), 1, "the module seam recorded one row")
	assert_eq(bool(ctx.modules[0]["ok"]), true, "and the registry accepted it")
	var registry: ModuleRegistry = out["registry"]
	assert_eq(registry.api_path_of(MODULE_NAME), API_PATH, "the api path RESOLVES")
	assert_eq(FileAccess.file_exists(API_PATH), true, "and it is a real file on disk")
	var registrations := ModRuntime.finalize(out["contexts"], registry)
	assert_eq(bool(registrations["modules"]["ok"]), true, "the whole attach order resolves")


## The attach verb `AttachPipeline.attach_module` calls. `no_attach` would be the
## silent skip ADR 0184 §8 forbids, so it is asserted as an answer of its own.
func test_the_module_attach_verb_runs_through_the_attach_pipeline() -> void:
	var out := ModsApi.load_order([MOD_DIR])
	var registry: ModuleRegistry = out["registry"]
	var subject := actor()
	DoctrineTemplateModApi.attach_count = 0
	var verdict := AttachPipeline.new().attach_module(
		MODULE_NAME, registry.api_path_of(MODULE_NAME), subject
	)
	assert_eq(bool(verdict["ok"]), true, "the pipeline attached the module")
	assert_eq(str(verdict["reason"]), "", "and it FOUND an attach verb rather than skipping")
	assert_eq(DoctrineTemplateModApi.attach_count, 1, "so the mod's own attach ran, exactly once")
	assert_eq(DoctrineTemplateModApi.last_actor_id, subject.id, "on the actor the pipeline passed")
	# Attaching admits NOTHING: the ledger is created by `join` and normalized on
	# every read (ADR 0272), and `boot` is what registers the Systems.
	assert_eq(DoctrineRegistry.count(), 0, "and attaching one actor registered no System")
	assert_eq(int(DoctrineApi.summary(subject)["system_count"]), 0, "and the facade agrees")


## ADR 0275's closure, end to end: the pool is introduced by `stats.json`, reaches
## the runtime registrations as an OWNED pool, and is what the Systems spend —
## none of it a string literal in the mod's GDScript.
func test_the_declared_pool_reaches_the_seam_and_the_systems_spend_it() -> void:
	var loaded := _load_mod()
	var report: Dictionary = loaded["report"]
	assert_eq(bool(report["ok"]), true, "boot: %s" % str(report["refused"]))
	assert_eq((report["attached"] as Array).size(), 2, "both Systems were admitted")
	assert_eq(str(report["attached"][0]), str(FIRST), "in declaration order")
	assert_eq(str(report["attached"][1]), str(SECOND), "and then the second")
	var pools: Array = report["pools"]
	assert_eq(pools.size(), 1, "one pool, and it came from the declaration")
	assert_eq(StringName(pools[0]), MARK, "which is the id stats.json declares")
	var registrations: Dictionary = loaded["registrations"]
	assert_eq((registrations["declaration_refusals"] as Array).size(), 0, "nothing was refused")
	assert_eq(
		str(registrations["declared_resources"][str(MARK)]),
		MOD_ID,
		"the runtime records which mod owns the pool"
	)
	assert_eq((registrations["stat_declarations"] as Array).size(), 2, "both stat rows arrived")
	var rule := _system(FIRST)
	assert_eq(rule.resource_ids().size(), 1, "the System spends the DECLARED pool")
	assert_eq(rule.resource_ids()[0], MARK, "and not one of its own")
	var declared := DoctrineApi.rules()
	assert_eq(declared.size(), 2, "both Systems are visible through the facade")
	assert_eq(str(declared[0]["data_key"]), "doctrine/%s" % str(FIRST), "under the derived key")
	assert_eq(str(declared[0]["pools"]), str([str(MARK)]), "and the pool rides the declaration")


## The opt-in and its counterpart. `leave` is the PRICE-bearing half: it forfeits
## the counter and the coin, which is what makes joining a decision rather than a
## free re-accumulation (ADR 0272 decision 6).
func test_join_then_leave_is_an_opt_in_with_a_price() -> void:
	_boot_mod()
	var rule := _system(FIRST)
	var subject := actor()
	assert_eq(int(DoctrineApi.summary(subject)["system_count"]), 2, "both Systems are registered")
	assert_eq(int(DoctrineApi.summary(subject)["joined_count"]), 0, "and neither is joined")
	var joined := DoctrineApi.join(subject, rule.system_id())
	assert_eq(bool(joined["ok"]), true, "the opt-in is accepted")
	assert_eq(str(joined["data_key"]), str(rule.data_key()), "under the key derived from the id")
	assert_eq(_joined(subject, rule), true, "and the ledger records it")
	assert_eq(
		str(DoctrineApi.join(subject, rule.system_id())["reason"]),
		DoctrineRule.ALREADY_MAXED,
		"a second join is a refusal"
	)
	assert_eq(int(DoctrineApi.summary(subject)["joined_count"]), 1, "not a second ledger")
	_farm(subject, rule, 3)
	assert_eq(float(_balance(subject, rule)), 3.0, "three occurrences banked three")
	var left := DoctrineApi.leave(subject, rule.system_id())
	assert_eq(bool(left["ok"]), true, "leaving is accepted")
	assert_eq(_joined(subject, rule), false, "and forfeits the opt-in")
	assert_eq(float(_balance(subject, rule)), 0.0, "and the unspent coin with it")
	assert_eq(_points(subject, rule), 0, "and the counter, which is the price of leaving")
	assert_eq(
		str(DoctrineApi.leave(subject, rule.system_id())["reason"]),
		DoctrineRule.NOT_CLAIMED,
		"leaving a System you are not in is a refusal"
	)


## An earn is a PROPOSAL. Nothing moves until the facade that owns the occurrence
## decides, which is ADR 0272 decision 4 and the reason `earn` writes nothing.
func test_an_earn_proposes_and_only_the_facade_books_it() -> void:
	_boot_mod()
	var rule := _system(FIRST)
	var subject := _joined_actor(rule)
	var event := {"kind": str(EVENT_KIND)}
	var claim := rule.earn(subject, event)
	assert_eq(bool(claim["ok"]), true, "the System claims its own event")
	assert_eq(float(claim["amount"]), 1.0, "for the amount its JSON names")
	assert_eq(StringName(claim["pool"]), MARK, "out of the declared pool")
	assert_eq(float(_balance(subject, rule)), 0.0, "and a proposal moves nothing by itself")
	assert_eq(
		str(rule.earn(subject, {"kind": "unrelated"})["reason"]),
		DoctrineRule.NOT_CLAIMED,
		"an occurrence it does not answer is declined by name"
	)
	var answer := DoctrineApi.earn(subject, event, rule.system_id())
	assert_eq(bool(answer["ok"]), true, "the facade arbitrates and applies it")
	assert_eq(int(answer["candidate_count"]), 1, "naming one System asks exactly that System")
	assert_eq(float(_balance(subject, rule)), 1.0, "so the framework's balance moved")
	assert_eq(
		int(_ledger(subject, rule)[DoctrineLedger.KEY_EARNINGS]), 1, "and it counted the occurrence"
	)


## Two Systems, ONE occurrence, exactly one booked. The winner is the largest
## claim (ADR 0272 decision 4), so the answer cannot depend on registry order —
## which is what makes it a rule rather than a coincidence.
func test_two_systems_answer_one_occurrence_and_exactly_one_is_booked() -> void:
	_boot_mod()
	var first := _system(FIRST)
	var second := _system(SECOND)
	var subject := _joined_actor(first)
	DoctrineApi.join(subject, second.system_id())
	var answer := DoctrineApi.earn(subject, {"kind": str(EVENT_KIND)})
	assert_eq(int(answer["candidate_count"]), 2, "every JOINED System was asked")
	assert_eq((answer["applied"] as Array).size(), 1, "and exactly one claim was booked")
	assert_eq(
		str(answer["applied"][0]["system_id"]), str(second.system_id()), "the largest takes it"
	)
	assert_eq(float(answer["applied"][0]["amount"]), 4.0, "for its own amount")
	assert_eq((answer["declined"] as Array).size(), 1, "and the other is declined")
	assert_eq(str(answer["declined"][0]["system_id"]), str(first.system_id()), "named, not dropped")
	assert_eq(float(_balance(subject, first)), 0.0, "the loser's ledger never moved")
	assert_eq(float(_balance(subject, second)), 4.0, "and the winner's holds the occurrence")


## A catalogue and a live quote. Both rows sit at tier 0, so the only thing
## separating them is the WALLET — a locked row and a broke one are two answers.
func test_the_board_prices_one_row_affordably_and_another_beyond_the_wallet() -> void:
	_boot_mod()
	var rule := _system(FIRST)
	var subject := _joined_actor(rule)
	var board := DoctrineApi.boards(subject, rule.system_id())
	assert_eq(board.size(), 2, "the row count is the mod's JSON row count")
	for row in board:
		assert_eq(
			DoctrineRule.missing_keys(row, DoctrineRule.ROW_KEYS).size(),
			0,
			"row '%s' carries every declared key" % str(row.get("row_id", ""))
		)
	assert_eq(
		DoctrineApi.price(subject, rule.system_id(), &"r_absent"),
		{},
		"a row this System does not sell is {} and not a refusal"
	)
	var broke := DoctrineApi.price(subject, rule.system_id(), ROW_CHEAP)
	assert_eq(bool(broke["ok"]), false, "an empty wallet refuses every priced row")
	assert_eq(str(broke["reason"]), DoctrineRule.INSUFFICIENT, "by name")
	assert_eq(bool(broke["affordable"]), false, "and the quote says so")
	assert_eq(int(broke["owned"]), 0, "with nothing held")
	_farm(subject, rule, 1)
	var cheap := DoctrineApi.price(subject, rule.system_id(), ROW_CHEAP)
	assert_eq(bool(cheap["ok"]), true, "one occurrence pays the cheap row")
	assert_eq(bool(cheap["affordable"]), true, "and the quote agrees")
	assert_eq(float(cheap["amount"]), 1.0, "quoting the row's own price")
	var dear := DoctrineApi.price(subject, rule.system_id(), ROW_DEAR)
	assert_eq(bool(dear["ok"]), false, "nine is more than one occurrence banked")
	assert_eq(str(dear["reason"]), DoctrineRule.INSUFFICIENT, "and it says which reason")
	assert_eq(float(dear["amount"]), 9.0, "for the row's own price")
	assert_eq(
		bool(DoctrineApi.redeem(subject, rule.system_id(), ROW_DEAR)["ok"]),
		false,
		"so the press is refused rather than half-honoured"
	)
	assert_eq(float(_balance(subject, rule)), 1.0, "and the balance is intact")


## The one transaction, and BOTH writers: the framework's money and the rule's own
## counter. ADR 0272 decision 3 splits the keys precisely so both can be watched.
func test_a_redeem_moves_the_frameworks_money_and_the_rules_own_counter() -> void:
	_boot_mod()
	var rule := _system(FIRST)
	var subject := _joined_actor(rule)
	_farm(subject, rule, 1)
	var answer := DoctrineApi.redeem(subject, rule.system_id(), ROW_CHEAP)
	assert_eq(bool(answer["ok"]), true, "the press is honoured")
	assert_eq(float(answer["spent"]), 1.0, "for the row's own price")
	assert_eq(float(_balance(subject, rule)), 0.0, "the FRAMEWORK's balance moved")
	assert_eq(
		int(_ledger(subject, rule)[DoctrineLedger.KEY_REDEMPTIONS]), 1, "and it counted the press"
	)
	assert_eq(_points(subject, rule), 2, "the RULE's counter moved, by its own authored amount")
	assert_eq(_owned(subject, rule, ROW_CHEAP), 1, "and the rule's own count of the row")
	assert_eq(_joined(subject, rule), true, "a spend does not forfeit the opt-in")
	assert_eq((answer["granted"] as Array).size(), 1, "one grant landed")
	assert_eq(
		subject.has_status(StringName(answer["granted"][0]["status_id"])),
		true,
		"through Actor.add_status, and the id is the one the grant reported"
	)
	assert_eq(
		int(rule.tier_for(subject)["tier"]), 1, "and the band is derived from the counter alone"
	)


## Every payload this mod can put in front of a panel is primitives-only. The
## budget is `MAX_PAYLOAD_DEPTH = 4` and a row already sits three levels down.
func test_every_read_model_the_mod_exposes_is_primitives_only() -> void:
	_boot_mod()
	var rule := _system(FIRST)
	var subject := _joined_actor(rule)
	_farm(subject, rule, 1)
	DoctrineApi.redeem(subject, rule.system_id(), ROW_CHEAP)
	var summary := DoctrineApi.summary(subject)
	assert_eq(DoctrineRule.is_primitive_payload(summary), true, "summary")
	assert_eq(DoctrineRule.is_primitive_payload(DoctrineApi.state(subject)), true, "state")
	assert_eq(
		DoctrineRule.is_primitive_payload(DoctrineApi.available(subject)[0]),
		true,
		"one available row"
	)
	assert_eq(
		DoctrineRule.is_primitive_payload(DoctrineApi.boards(subject, rule.system_id())[0]),
		true,
		"one board row"
	)
	assert_eq(
		DoctrineRule.is_primitive_payload(DoctrineTemplateModApi.panel_state(subject)),
		true,
		"and the mod's own panel payload"
	)
	assert_eq(DoctrineApi.summary(null), {}, "the read model is {} with no actor")
	assert_eq(DoctrineTemplateModApi.panel_state(null), {}, "and the mod's panel agrees")
	assert_eq(
		(summary["pools"] as Array).has(str(MARK)),
		true,
		"the declared pool rides the read model, which is how the vocabulary stays readable"
	)


## ADR 0273: an unnamed System has NO state key rather than a shared one, because
## two of them writing one dictionary restores one board into another's. This is
## the template's own default, so it is what a mod that forgets its id gets.
func test_an_unnamed_system_has_no_save_key_and_cannot_be_registered() -> void:
	var unnamed := DoctrineTemplateRule.new()
	assert_eq(str(unnamed.system_id()), "", "the template's default id is empty")
	assert_eq(str(unnamed.data_key()), "", "so there is no key two unnamed Systems could share")
	var verdict := DoctrineApi.attach(unnamed)
	assert_eq(bool(verdict["ok"]), false, "and it is refused, not persisted somewhere arbitrary")
	assert_eq(str(verdict["reason"]), DoctrineRule.NOT_CLAIMED, "by one of the closed reasons")
	assert_eq(DoctrineRegistry.count(), 0, "and nothing was recorded")
	assert_eq(DoctrineApi.boards(actor(), unnamed.system_id()), [], "nothing to read for it")


## DEF-0111, and this is the suite that should own it: the template is the thing
## an author COPIES. Read as TEXT — no value assertion sees a call not made.
func test_the_template_owns_no_clock_and_no_scene_tree() -> void:
	var paths := ContentScan.files_under(MOD_DIR, ".gd")
	assert_eq(paths.size(), 2, "the template's two scripts, walked by ContentScan")
	# `paths` is the directory's own file list and this walk appends to nothing,
	# so it terminates on its input rather than on a container it grows (INC-0002).
	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		assert_eq(source.contains("Time.get_ticks"), false, "%s reads no clock" % path)
		assert_eq(source.contains("get_tree("), false, "%s reaches no scene tree" % path)
		assert_eq(source.contains("_process"), false, "%s declares no tick" % path)


## A mod is not a special case: it loads beside the other three fixture mods, in
## priority order, in one pass. A template that could only load alone is not a mod.
func test_the_template_loads_beside_the_other_fixture_mods() -> void:
	var out := ModsApi.load_order([FIXTURES_DIR])
	assert_eq(bool(out["ok"]), true, "every fixture mod still loads")
	var order: Array = out["order"]
	assert_eq(order.size(), 4, "four fixture mods, one per directory: %s" % str(order))
	assert_eq(order.has(MOD_ID), true, "and the template is one of them")
	assert_eq(order.find(MOD_ID), 3, "priority 40 loads after the other three")


## The unit leg: `boot(ctx)` answers its own report with no pipeline in the way.
## The production leg proves the WIRING; this pins the function's contract, so a
## wiring failure cannot be misread as an arithmetic failure.
func test_the_entry_point_contract_in_isolation() -> void:
	var out := ModsApi.load_order([MOD_DIR])
	var ctx: RegistrationContext = out["contexts"][0]
	ModRuntime.finalize(out["contexts"], out["registry"])
	DoctrineTemplateModApi.last_boot_report = {}
	var report := DoctrineTemplateModApi.boot(ctx)
	assert_eq(bool(report["ok"]), true, "boot admits its own Systems: %s" % str(report["refused"]))
	assert_eq((report["attached"] as Array).size(), 2, "both, in declaration order")
	assert_eq(DoctrineTemplateModApi.last_boot_report, report, "and the report is observable")
