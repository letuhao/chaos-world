extends TestCase

## ADR 0266: a quest completion is ANNOUNCED, so a registrable System can react to it
## instead of polling.
##
## ## The defect this suite exists to end
##
## `QuestApi.advance` and `QuestApi.complete` returned `{ok, completed, paid, unspent}`
## to their CALLER and emitted nothing. Every bus that existed was an institution or
## polity domain, so a System — which is *action*-shaped, not an institution — had
## nothing to subscribe to at all. The only way to learn a quest had finished was to poll
## `QuestApi.summary()` from a screen, which fires the reward on screen-OPEN rather than
## on completion and puts game logic in the UI refresh path.
##
## ## The claims
##
##   1. Acceptance, completion and refusal each announce once, with primitives.
##   2. The once-guard is the ANNOUNCEMENT's guard too: a repeat completion pays nothing
##      and announces nothing, so a subscriber may treat the signal as "the reward
##      landed" rather than "a verdict was offered".
##   3. **A read announces nothing.** `summary()` and `offered()` re-derive on every call,
##      so a signal emitted there would fire every time a player opened a screen.
##   4. It fires on the PRODUCTION path — a real shipped quest, its fact written by the
##      module that owns it, with no `advance` call anywhere in the body.
##
## The contract's shape is asserted in `tests/contracts/test_quest_events.gd` and the
## composition-root wiring in `tests/app/test_unknown_bus_warning.gd`.

## A real shipped quest: one step, one fact (`oaths_discharged`), ungated, and authored
## `systemic`, so NOTHING hands it out — the only way to finish it is a completion driven
## from a recorded fact. Read from `res://data/quest/quests/`, never restated.
const QUEST := &"the_short_road"
const QUEST_FACT := &"oaths_discharged"

## Fixture quests, for the paths the shipped tree cannot reach from a test: quests a
## player can accept and finish by hand. `t_` prefix, so they cannot collide with an
## authored id.
const FIXTURE := &"t_bus_probe"
const FIXTURE_TWO := &"t_bus_probe_two"
const FIXTURE_FACT := &"bus_probe_kills"

const HERO := &"bus_keeper"

var _accepted: Array[Dictionary] = []
var _completed: Array[Dictionary] = []
var _refused: Array[Dictionary] = []
var _installed := false


func setup() -> void:
	_accepted.clear()
	_completed.clear()
	_refused.clear()
	_disconnect_all()
	var bus := QuestEvents.shared()
	bus.quest_accepted.connect(
		func(actor_id, quest_id, source): _row(_accepted, actor_id, quest_id, source)
	)
	bus.quest_completed.connect(
		func(actor_id, quest_id, source): _row(_completed, actor_id, quest_id, source)
	)
	bus.quest_refused.connect(
		func(actor_id, quest_id, reason): _row(_refused, actor_id, quest_id, reason)
	)
	# The production completion bridge, installed the way the composition root installs
	# it — in `setup`, not through the boot path, because `ItemWorkbenchApp._ready` needs
	# a scene tree this suite does not have. The suite that proves the GAME installs this
	# door is `test_quest_production_completion.gd`; this one proves the ANNOUNCEMENT
	# reaches a subscriber on the path the bridge drives.
	QuestFactProjection.subscribe_to_fact_ledger()
	_installed = true


## The bus is a PROCESS-WIDE static, so a connection an earlier suite left behind would
## append its own rows to these arrays and make every count below test the accumulation
## rather than this suite's emissions.
func teardown() -> void:
	_disconnect_all()
	if _installed:
		QuestFactProjection.unsubscribe_from_fact_ledger()
		_installed = false
	QuestFixtureCatalog.teardown()
	_accepted.clear()
	_completed.clear()
	_refused.clear()


func _disconnect_all() -> void:
	var bus := QuestEvents.shared()
	for connection in bus.quest_accepted.get_connections():
		bus.quest_accepted.disconnect(connection["callable"])
	for connection in bus.quest_completed.get_connections():
		bus.quest_completed.disconnect(connection["callable"])
	for connection in bus.quest_refused.get_connections():
		bus.quest_refused.disconnect(connection["callable"])


func _row(into: Array[Dictionary], actor_id: String, quest_id: StringName, third: String) -> void:
	into.append({"actor_id": actor_id, "quest_id": String(quest_id), "third": third})


## A hero with both ledgers attached, over the SHIPPED catalog.
func _hero() -> Actor:
	return QuestFixtureCatalog.hero(HERO)


## Two fixture quests watching one fact, so `advance` can finish both in a single pass.
func _install_fixtures() -> void:
	# Positional and built-in dictionaries, exactly as `test_quest.gd` builds its own
	# fixtures — the helper's keyword form is not what the house calls.
	var step_row := [{"step_id": &"bus_probe", "fact": FIXTURE_FACT, "need": 1}]
	(
		QuestFixtureCatalog
		. install(
			[
				QuestFixtureCatalog.quest(FIXTURE, QuestDef.KIND_AUTHORED, {}, step_row),
				QuestFixtureCatalog.quest(FIXTURE_TWO, QuestDef.KIND_AUTHORED, {}, step_row),
			]
		)
	)


func _completed_ids(actor: Actor) -> Array:
	return QuestApi.summary(actor)["completed"]


## Every quest id the completion announcement named, as a set — the order `advance` walks
## the active ledger in is not part of any contract, so pinning it would make this suite
## go red on a Dictionary reorder rather than on a defect.
func _announced_quests(rows: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for row in rows:
		out[String(row["quest_id"])] = true
	return out


# --- The production path ---------------------------------------------------------


## **THE CLAIM.** A real shipped quest completes in play — its fact written by `sect`,
## which knows nothing about `quest` — and the completion is ANNOUNCED to a subscriber
## that never asked for the completion.
##
## Mutation target: delete the `quest_completed.emit` from `QuestApi._complete` and this
## goes red at the count below, with the ledger and the completion both still correct.
func test_a_quest_completed_in_play_is_announced_to_a_subscriber() -> void:
	var actor := _hero()
	var def := QuestCatalog.instance().definition(QUEST)
	assert_ne(def, null, "the quest is read from the SHIPPED tree, not a fixture")
	assert_eq(
		def.kind, QuestDef.KIND_SYSTEMIC, "and nothing hands it out, so only play finishes it"
	)

	assert_eq(QuestProgram.new(actor).accept(QUEST)["ok"], true, "the program took it on")
	assert_eq(_completed.size(), 0, "accepting announces acceptance, not completion")

	# The fact, written by the module that owns it.
	SectFacts.record_oaths_discharged(actor, 1)

	assert_eq(_completed.size(), 1, "the completion in play announced itself once")
	assert_eq(String(_completed[0]["quest_id"]), String(QUEST), "naming the quest that finished")
	assert_eq(String(_completed[0]["actor_id"]), String(HERO), "and the hero it finished for")
	assert_eq(
		_completed_ids(actor).has(String(QUEST)),
		true,
		"and the announcement agrees with the ledger — it announces, it does not decide"
	)


## The once-guard is the ANNOUNCEMENT's guard. `QuestState.finish` runs before any grant
## is paid, so a repeat completion announces nothing: a subscriber may treat this signal
## as "the reward landed" rather than as "a verdict was offered", and that is only true if
## a second crossing is silent.
func test_a_repeat_completion_announces_nothing() -> void:
	var actor := _hero()
	QuestProgram.new(actor).accept(QUEST)
	SectFacts.record_oaths_discharged(actor, 1)
	assert_eq(_completed.size(), 1, "the first occurrence announced once")

	# The ledger is monotone, so a LATER occurrence is the only thing that could re-drive
	# a completion. It must not, and it must not do so by announcing.
	SectFacts.record_oaths_discharged(actor, 1)
	assert_eq(WorldFact.count(actor, QUEST_FACT), 2, "the ledger really did take a second")
	assert_eq(_completed.size(), 1, "and the second announced nothing — the once-guard holds")
	assert_eq(_completed_ids(actor).has(String(QUEST)), true, "still complete rather than twice")


# --- The direct verbs ------------------------------------------------------------


## `accept` is the other door, and it matters more than it looks: a `systemic` or
## `emergent` quest is never OFFERED (BL-0053), so for those this announcement is the only
## trace a System ever gets that a quest entered the world.
func test_accepting_a_quest_announces_the_offer_source() -> void:
	_install_fixtures()
	var actor := _hero()
	assert_eq(QuestApi.accept(actor, FIXTURE, "npc:elder")["ok"], true, "the quest was taken on")
	assert_eq(_accepted.size(), 1, "taking a quest on announces itself")
	assert_eq(String(_accepted[0]["quest_id"]), String(FIXTURE), "naming the quest")
	assert_eq(String(_accepted[0]["third"]), "npc:elder", "and where the offer came from")
	assert_eq(_completed.size(), 0, "which is not a completion")


## An empty `source` means "nothing declared one", never "unknown origin" — a caller that
## reached the module directly has not said. Asserted so a consumer cannot come to read
## the empty string as a missing answer.
func test_an_undeclared_source_is_empty_rather_than_invented() -> void:
	_install_fixtures()
	var actor := _hero()
	QuestApi.accept(actor, FIXTURE)
	assert_eq(_accepted.size(), 1, "the acceptance was announced")
	assert_eq(String(_accepted[0]["third"]), "", "with an empty source, not a fabricated one")


## `advance` is the verb ADR 0114's director hands a beat to, and the one that can finish
## SEVERAL quests in one pass. Each announces separately: one signal per completion, not
## one per call, or a subscriber cannot tell two rewards from one.
func test_advance_announces_each_quest_it_completes() -> void:
	_install_fixtures()
	var actor := _hero()
	QuestApi.accept(actor, FIXTURE)
	QuestApi.accept(actor, FIXTURE_TWO)
	assert_eq(_accepted.size(), 2, "two quests in flight")
	assert_eq(_completed.size(), 0, "neither complete yet")

	QuestFixtureCatalog.record(actor, FIXTURE_FACT, 1)
	var out := QuestApi.advance(actor, "beat:world")
	assert_eq((out["completed"] as Array).size(), 2, "one pass finished both")
	assert_eq(_completed.size(), 2, "so each announced itself — one signal per completion")
	var announced := _announced_quests(_completed)
	assert_eq(announced.has(String(FIXTURE)), true, "the first pass announced its own quest")
	assert_eq(announced.has(String(FIXTURE_TWO)), true, "and the second announced its own")
	for row in _completed:
		assert_eq(String(row["third"]), "beat:world", "both carry the caller's provenance")

	# A second pass over the same ledger finds everything already completed.
	QuestApi.advance(actor, "beat:world")
	assert_eq(_completed.size(), 2, "and a repeat pass announces nothing")


## The explicit hand-off `complete()` — a dialogue that ran its course, an npc stage that
## reached its end (DEF-0122). It routes through the SAME `_complete`, so the
## announcement cannot be one of the two paths and not the other.
func test_the_explicit_completion_verb_announces_the_same_way() -> void:
	_install_fixtures()
	var actor := _hero()
	QuestApi.accept(actor, FIXTURE)
	QuestFixtureCatalog.record(actor, FIXTURE_FACT, 1)
	assert_eq(QuestApi.complete(actor, FIXTURE)["ok"], true, "the story decided the completion")
	assert_eq(_completed.size(), 1, "announced once")
	assert_eq(String(_completed[0]["quest_id"]), String(FIXTURE), "naming the quest")
	assert_eq(String(_completed[0]["third"]), "", "and with no source: `complete` declares none")


# --- Refusals -------------------------------------------------------------------


## The one signal that announces something did NOT become true, and that is the point of
## it rather than an exception: the returned dictionary says `ok: false`, and this says
## WHICH rule refused and ON WHICH QUEST. Two independent facts, so a panel renders the
## rule it was given instead of inventing one.
func test_a_refusal_announces_the_rule_that_refused() -> void:
	_install_fixtures()
	var actor := _hero()

	var never_accepted := QuestApi.complete(actor, FIXTURE)
	assert_eq(String(never_accepted["reason"]), "not_active", "the answer says what refused")
	assert_eq(_refused.size(), 1, "and the refusal announced itself")
	assert_eq(String(_refused[0]["quest_id"]), String(FIXTURE), "naming the quest")
	assert_eq(String(_refused[0]["third"]), "not_active", "and the rule, verbatim")
	assert_eq(_completed.size(), 0, "a refusal is never a completion")

	# An id the catalog does not define. The ANSWER carries `unknown_quest` rather than
	# the catalog's own "no such definition" word, and so must the announcement.
	var absent := QuestApi.accept(actor, &"t_bus_probe_absent")
	assert_eq(String(absent["reason"]), "unknown_quest", "the catalog does not define that id")
	assert_eq(_refused.size(), 2, "so that refusal announced itself too")
	assert_eq(String(_refused[1]["quest_id"]), "t_bus_probe_absent", "naming what was asked for")
	assert_eq(String(_refused[1]["third"]), "unknown_quest", "naming the rule, verbatim")


## Every refusal on the facade is built in ONE place, so no call site can forget to
## announce — the argument `ConflictApi._refuse` and `HoldingsApi._refuse` make for their
## own buses (DEF-0221). Pinned by driving a refusal from BOTH doors: a version of the
## facade that announced at one call site and not the other fails the second count.
func test_every_door_that_refuses_announces() -> void:
	_install_fixtures()
	var actor := _hero()
	QuestApi.accept(actor, FIXTURE)
	assert_eq(_refused.size(), 0, "nothing refused yet")

	var duplicate := QuestApi.accept(actor, FIXTURE)
	assert_eq(String(duplicate["reason"]), "already_active", "the second accept is refused")
	assert_eq(_refused.size(), 1, "and `accept` announced that refusal")

	var early := QuestApi.complete(actor, FIXTURE)
	assert_eq(String(early["reason"]), "steps_unmet", "an unfinished quest cannot complete")
	assert_eq(_refused.size(), 2, "and `complete` announced its own refusal too")
	assert_eq(String(_refused[1]["third"]), "steps_unmet", "with its own rule, verbatim")


# --- A read announces nothing ----------------------------------------------------


## THE claim that keeps the bus honest. `offered` and `summary` RE-DERIVE on every call,
## and `summary` reaches `offered` through `_offered_ids` — so an emit in a read would
## fire every time a player opened a screen, which is the polling defect the bus exists to
## remove, reintroduced from the other side.
func test_reading_the_module_announces_nothing() -> void:
	_install_fixtures()
	var actor := _hero()
	QuestApi.attach(actor)
	QuestApi.offered(actor)
	QuestApi.active(actor)
	QuestApi.summary(actor)
	QuestApi.summary(actor)
	QuestApi.steps(actor, FIXTURE)
	QuestApi.gates_for(actor, FIXTURE)
	assert_eq(
		_accepted.size() + _completed.size() + _refused.size(),
		0,
		"seven reads, and not one announced a thing — a read is not a fact"
	)
