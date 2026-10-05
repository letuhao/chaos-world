class_name QuestArrivalProjection
extends RefCounted

## The `quest` module's other end of the ledger: a `systemic` or `emergent` quest
## is not OFFERED, it **ARRIVES**.
##
## ## The defect this file closes
##
## `QuestApi.offered` skips every quest whose `kind` is not `authored`
## (`api.gd`), and the only production caller of `QuestApi.accept` is
## `QuestProgram`, which only ever sees rows that came out of `offered`. So
## `what_the_rotation_cost` (`emergent`), `the_short_road` (`systemic`) and
## `the_severed_calling` (`systemic`) had **no production door at all**: a player
## could stand the rotation, win three counted duels, spare the third man, and the
## quest naming exactly that never entered `QuestState.active_ids`. Their steps
## were satisfied, their grants unreachable, and `QuestApi.advance` walked an
## active set those three were never in.
##
## ## Why the `offered` filter STAYS
##
## Removing it would be the wrong fix and this file is the reason it is wrong.
## BL-0670 closed `QuestDef.kind` as genuinely read, and that single reader is
## the distinction between a board and an emergence: a board that listed a quest
## the instant its facts happened would be a board, not a world. `kind` says
## WHERE a quest came from, and this file is where the second half of that fact is
## spent — the arrival — so `kind` now has two readers with two different jobs
## rather than one reader and a lie.
##
## ## Why an ACCEPT and not a completion
##
## The door is a world-driven `QuestApi.accept`, not a bypass of it. An arrived
## quest is a real entry in `QuestState`: it has a `started` stamp, it appears in
## `QuestApi.active` and `QuestApi.summary`, it is persisted by the same
## `QuestState` every other quest uses, and it is completed by the SAME
## `QuestApi.advance` path that completes a handed one. Nothing here decides a
## completion, and nothing here writes a ledger — this file reads the shared fact
## ledger and calls one existing facade verb, exactly as ADR 0113 requires of
## every reader in the game.
##
## **No new facade verb.** `QuestApi` is AT `rules.MAX_FACADE_PUBLIC_METHODS`, and
## `accept` already has a production caller, so "the world took the quest on" is
## a CALLER, not a thirteenth verb.
##
## ## "When they happen", not "when they are already true"
##
## The arrival predicate reads the ledger only inside the dispatch for the fact
## that just landed. It never runs on a timer, on a screen open or on a save load,
## so a quest cannot arrive from history: it arrives at the crossing. A hero who
## never spared anyone is never silently handed `what_the_rotation_cost`, and a
## hero who spared someone before this line shipped is not retroactively credited
## either — which is the honest answer, and the only one that keeps "emergent"
## meaning something.

## The `source` an arrival carries, recorded by `QuestApi.accept` on the entry.
## Not an NPC, not a board: `"arrival"` is the vocabulary word for a quest that
## entered because the world's own facts put it there, so a save or a log names
## the door the quest came through rather than leaving it to be guessed at.
const ARRIVAL_SOURCE := "arrival"

## The kinds that ARRIVE. The complement of the one kind `QuestApi.offered` hands
## out, read from the same closed set rather than restated as a literal, so a
## fourth kind authored later is a one-line edit here and in `quest_def.gd`.
const ARRIVING_KINDS: Array[StringName] = [QuestDef.KIND_SYSTEMIC, QuestDef.KIND_EMERGENT]

## Memo of `fact -> the ARRIVING quests that watch it`, rebuilt only when the
## catalog's content changes. The same cache shape, and the same staleness rule,
## as [method QuestFactProjection._watched_set]: it is a memo of AUTHORED
## CONTENT, never player state, and it is keyed on the catalog instance it was
## built from so a suite that installs a fixture catalog is answered from THAT
## catalog's quests.
static var _candidates: Dictionary = {}
## The catalog generation [method _candidate_map] read — the identity of the
## singleton the memo was built from, because `QuestCatalog` publishes no counter.
static var _catalog: QuestCatalog = null


## Install [method on_fact_recorded] into `core`'s post-write hook slot, beside
## `DestinyProjection.subscribe_to_fact_ledger()` and
## `QuestFactProjection.subscribe_to_fact_ledger()`.
##
## **Subscribe order is the ordering decision this module makes.** It installs
## AFTER the completion projection, so on the fact that makes a quest enterable the
## completion dispatch has already run — over an active set the arrival has not yet
## joined — and the quest completes on the SAME fact, one dispatch later. The
## other order also works, and would make the quest complete on the NEXT fact of a
## kind it watches instead; same-dispatch is chosen because the world that just
## wrote the crossing fact has, in that instant, finished something, and a player
## who earns two fates at once should see both in one frame rather than watching a
## finished quest sit in the journal until the next duel.
static func subscribe_to_fact_ledger() -> bool:
	return WorldFact.subscribe(Callable(QuestArrivalProjection, "on_fact_recorded"))


## Whether [method subscribe_to_fact_ledger] is installed, read rather than
## compared against the install's return value, for the reason
## `QuestFactProjection.is_subscribed_to_fact_ledger` states.
static func is_subscribed_to_fact_ledger() -> bool:
	return WorldFact.has_subscriber(Callable(QuestArrivalProjection, "on_fact_recorded"))


## Remove the bridge. The exact inverse of
## [method subscribe_to_fact_ledger], and idempotent — which is what the shared
## test process needs, since a subscriber left installed here would hand every
## later suite's heroes the quests their own facts happen to satisfy.
static func unsubscribe_from_fact_ledger() -> bool:
	return WorldFact.unsubscribe(Callable(QuestArrivalProjection, "on_fact_recorded"))


## The ARRIVING quests that watch `fact` and are not yet in `actor`'s ledger, as
## ids, in the catalog's own order.
##
## The predicate, published rather than folded into [method on_fact_recorded], so a
## test can ask the question without taking the action — and so the idempotence
## claim is checkable: an empty answer here means `accept` was never reached,
## which is a different fact from "`accept` refused".
static func arriving(actor: Actor, fact: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if actor == null or fact == &"":
		return out
	for quest_id in _watching(fact):
		if _arrives(actor, quest_id):
			out.append(quest_id)
	return out


## Take on every quest of `actor` that this fact just made enterable.
##
## **Idempotence is decided HERE, not by `accept`.** [method _arrives] refuses a
## quest the ledger already tracks, so a second occurrence of the same fact
## short-circuits before any facade call is made. `QuestApi.accept` carries its
## own once-guard as well — it must, it is the authority — but leaning on that
## alone would make the arrival's own guard untestable, and a guard that cannot be
## told apart from the one beneath it is not a guard.
##
## Returns the ids this dispatch ACTUALLY entered, which is the observable that
## distinguishes "refused before the call" from "refused by the call".
static func on_fact_recorded(actor: Actor, fact: StringName, amount: int = 1) -> Array[StringName]:
	var entered: Array[StringName] = []
	if actor == null or fact == &"" or amount < 1:
		return entered
	for quest_id in arriving(actor, fact):
		var outcome := QuestApi.accept(actor, quest_id, ARRIVAL_SOURCE)
		if bool(outcome.get("ok", false)):
			entered.append(quest_id)
	return entered


# --- Internals -------------------------------------------------------------


## Whether `quest_id` is an ARRIVING quest that has just become satisfiable for
## `actor`: of a kind that arrives, not yet in the ledger, with at least one
## required step and EVERY required step reading done.
##
## The step reads come from `QuestApi.steps` — the shared `WorldFactLedger`, per
## ADR 0113 — so the arrival reads exactly the memory the completion will later
## be decided against. If those two ever disagreed, a quest would arrive and then
## refuse to complete; routing both through the one public read makes that
## impossible by construction rather than by care.
static func _arrives(actor: Actor, quest_id: StringName) -> bool:
	var def := QuestCatalog.instance().definition(quest_id)
	if def == null or not ARRIVING_KINDS.has(def.kind):
		return false
	if QuestState.is_tracked(_ledger(actor), quest_id):
		return false
	var required := 0
	for step in QuestApi.steps(actor, quest_id) as Array[Dictionary]:
		if bool(step["optional"]):
			continue
		required += 1
		if not bool(step["done"]):
			return false
	# A quest with no required step has not "just become satisfiable" — it was
	# satisfiable the moment it was defined, so it is nothing to arrive.
	return required > 0


## The arriving quests watching `fact`, as `StringName` ids, from the memo.
static func _watching(fact: StringName) -> Array[StringName]:
	var found = _candidate_map().get(String(fact), [])
	if not (found is Array):
		return []
	var out: Array[StringName] = []
	for quest_id in found as Array:
		out.append(quest_id)
	return out


## `fact -> Array[StringName]`, covering only ARRIVING quests.
##
## Narrower than [method QuestFactProjection._watched_set] on purpose: that set
## gates the completion dispatch and must include every shipped step fact, while
## this one gates an accept and only needs the ones a non-`authored` quest
## watches. Building both from the catalog on its own terms keeps each one
## answerable as the cheap question it actually is.
##
## Rebuilt whenever the catalog identity changes, so installing a fixture catalog
## mid-process is answered from ITS quests rather than from the shipped tree.
static func _candidate_map() -> Dictionary:
	var catalog := QuestCatalog.instance()
	if _catalog == catalog and not _candidates.is_empty():
		return _candidates
	_catalog = catalog
	_candidates.clear()
	# Bounded by the authored quest count, over the catalog's own materialized
	# array — the shape `test_no_unbounded_wait` accepts.
	for quest_id in catalog.quest_ids():
		var def := catalog.definition(quest_id)
		if def == null or not ARRIVING_KINDS.has(def.kind):
			continue
		for fact in def.watched_facts():
			var key := String(fact)
			if not _candidates.has(key):
				_candidates[key] = [] as Array[StringName]
			(_candidates[key] as Array[StringName]).append(quest_id)
	return _candidates


## `actor`'s quest ledger, normalized. Read through the same `QuestState` the
## facade reads it through, so a repaired payload is what the arrival sees rather
## than the raw one.
static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return QuestState.empty()
	return QuestState.normalize(actor.get_module_data(QuestApi.MODULE_KEY))


## Every fact an ARRIVING quest in `catalog` watches, canonically ordered.
## Published so a probe — or `tools arch` — can read the set this door listens on
## instead of re-deriving it from the `.tres` tree.
static func watched_facts() -> Array[StringName]:
	var strings: Array[String] = []
	for key in _candidate_map().keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out
