class_name QuestFixtureCatalog
extends RefCounted

## A test-local stand-in for `QuestCatalog`, holding `QuestDef` resources built in
## code. The module reads content through the catalog singleton and the shipped
## content tree is authored independently of this suite, so the logic tests
## install their own catalog for the span of one test rather than depending on
## which `.tres` files happen to exist today.
##
## The content tests (`test_quest_content.gd`) do the opposite: they read the real
## `res://data/quest/quests/` tree and assert that shipped content is well
## formed. Between them, a fixture can never quietly become the only thing that
## works.
##
## Fixtures use a reserved `t_` id prefix so they can never collide with a real
## authored quest, and `teardown()` restores whatever catalog the process held
## beforehand.
##
## ## Facts are written here, never by the quest module
##
## The helper below writes the ADR 0113 ledger payload into `actor.module_data`
## directly, which is exactly what core's `WorldFactLedger.record(actor, id,
## amount)` does. A test therefore produces a real ledger row without the quest
## module ever holding a write verb — which is the property under test.

const LEDGER_MODULE_KEY := &"world_facts"


## A quest with the given steps authored as `{step_id, fact, need, optional}`.
##
## `grants` is copied into a TYPED `Array[Dictionary]` before it is assigned.
## Assigning the caller's untyped `Array` straight to `QuestDef.grants`
## (`Array[Dictionary]`) is a runtime type error, and it is a fatal one: it
## aborts `quest()` before the `return`, so the caller installed a `null`
## definition and every assertion in the suite answered `unknown_quest`. A
## fixture that silently returns null looks exactly like a module with no
## catalog, which is how this hid behind a parse error for so long.
static func quest(
	quest_id: StringName,
	kind: StringName = QuestDef.KIND_AUTHORED,
	gate: Dictionary = {},
	steps: Array = [],
	grants: Array = []
) -> QuestDef:
	var def := QuestDef.new()
	def.id = quest_id
	def.display_name = String(quest_id).capitalize()
	def.description = "A fixture quest of kind %s." % kind
	def.kind = kind
	def.tier = 1
	def.requirement = gate
	for entry in steps:
		def.steps.append(step(entry))
	var typed: Array[Dictionary] = []
	for entry in grants:
		typed.append(entry as Dictionary)
	def.grants = typed
	return def


## One step from a `{step_id, fact, need, optional}` dictionary.
static func step(entry: Dictionary) -> QuestStepDef:
	var built := QuestStepDef.new()
	built.step_id = StringName(entry.get("step_id", entry.get("fact", "")))
	built.fact = StringName(entry.get("fact", ""))
	built.need = int(entry.get("need", 1))
	built.display_name = String(entry.get("label", built.fact))
	built.optional = bool(entry.get("optional", false))
	return built


## A grant in the `{kind, id, amount}` shape, defaulted to a single unit.
static func grant(kind: StringName, id: StringName, amount: int = 1) -> Dictionary:
	return {"kind": kind, "id": id, "amount": amount}


## Attach a fate gate to a quest def built by `quest()`. Returns the same def
## so the call chains: `QuestFixtureCatalog.quest(...).with_fate_gate([...])`.
static func with_fate_gate(def: QuestDef, fate_ids: Array[StringName]) -> QuestDef:
	def.fate_gate = fate_ids
	return def


## Replace the module's catalog singleton for the span of one test.
static func install(defs: Array[QuestDef] = []) -> void:
	var catalog := QuestCatalog.new()
	for def in defs:
		catalog._defs[String(def.id)] = def
	catalog._loaded = true
	QuestCatalog.shared = catalog


## Undo `install`. The real catalog is what the singleton lazily rebuilds when
## `shared` is null, so a restored test that needs shipped content simply has none
## installed.
static func teardown() -> void:
	QuestCatalog.shared = null


## Record `amount` of `fact` on `actor`, exactly as core's ledger does.
##
## This is the ONLY way a test makes progress happen. `QuestApi` exposes no write
## verb, so a step can only ever be satisfied by something outside this module —
## which is the ADR 0113 claim the suite exists to prove.
static func record(actor: Actor, fact: StringName, amount: int = 1) -> void:
	var ledger: Dictionary = actor.get_module_data(LEDGER_MODULE_KEY)
	if ledger.is_empty():
		ledger = {"version": 1, "facts": {}}
	ledger["facts"][String(fact)] = {
		"count": int(ledger["facts"].get(String(fact), {"count": 0}).get("count", 0)) + amount,
		"since": 0,
	}
	actor.set_module_data(LEDGER_MODULE_KEY, ledger)


## How many of `fact` the actor's ledger holds. Read through the module's own
## reader, so a test never re-implements the lookup it is checking.
static func held(actor: Actor, fact: StringName) -> int:
	return QuestFactReader.count(actor, fact)


## A hero with both ledgers attached and no progress recorded.
static func hero(actor_id: StringName = &"keeper") -> Actor:
	var actor := Actor.new(actor_id, {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.add_resource(ResourcePool.new(&"health", 100.0))
	DestinyApi.attach(actor)
	QuestApi.attach(actor)
	return actor
