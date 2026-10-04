class_name QuestFactProjection
extends RefCounted

## The `quest` module's end of ADR 0149: the subscriber that makes a quest chain
## complete in production, where "a fact written ANYWHERE is observed by the
## ledger's consumers everywhere".
##
## ## The defect this file closes
##
## `QuestApi.advance` — the only verb that completes a quest, and the only caller
## of `QuestGrants.pay` — had **exactly one production caller**: `BeatDirector`,
## through `QuestBeatHandler`. And `BeatDirector`'s only production offer point is
## `app/WorldPulse.offer`, which offers `PERIOD_FACT`
## (`world_period_elapsed`) and the four `WorldAmbient.ROSTER` ids. **Not one
## authored quest step watches any of those five.** Every authored step watches
## `sect_post_held`, `oaths_discharged`, `household_heir_registered`,
## `third_man_spared` or `duels_won` — all written by module writers that bypass
## the director by design (ADR 0137). So a player could accept a quest, satisfy
## every one of its steps in play, and it never completed.
##
## `tests/app/test_world_beat_chain.gd` proved this green: it installs a *fixture*
## quest whose single step watches `PERIOD_FACT` — the one id the pulse actually
## offers — so the suite asserted a fact about its own fixture, never about the
## game.
##
## ## Why the SUBSCRIPTION and not a wider `BeatDirector.offer`
##
## Measured, and stated once: `core/world_fact.gd`'s own docstring records that
## "dispatching somewhere else cannot work, and this is the measurement" — 0 of the
## eight `COUNTER_FACTS` rows could fire when the dispatch sat on
## `BeatDirector.offer`, for exactly this reason. **The ledger is the only
## chokepoint every writer reaches**; the director is not, and widening the
## director would put the ledger's traffic through a second queue that six of the
## eight writers never touch.
##
## ADR 0117's rule that looks like it argues the other way is *"recording is not
## dispatching"*, and this file does not violate it: nothing here records. The
## write already happened — that is what fired the hook — and this subscriber only
## RE-READS the ledger to decide what completed. It is a reader of a fact, not a
## second writer of one, and ADR 0114's "a handler never mutates" survives because
## `QuestApi.advance` mutates no ledger either (only `QuestState`, which is the
## quest's own).
##
## So this is the symmetric half of the ADR 0149 fix. `destiny`'s bridge moved a
## counter off the ledger; **this moves a quest completion off the same ledger**,
## and the two are now reached by identical means, which is the point of ADR 0149:
## a claim about what is NOT wired needs to be executed to be trusted, as much as a
## claim about what is.
##
## ## The gate: a fact only dispatches when an ACTIVE quest WATCHES it
##
## The overwhelmingly common case is a fact no quest cares about, and it must cost
## one cheap predicate — not a scan of every active quest's every step. So this
## reads the authored catalog's WATCHED FACTS once and holds them as a flat set.
## That is the same predicate `QuestBeatHandler.handles` already uses
## (`QuestDef.watches_fact`), asked of the CONTENT rather than of the player's
## active set, because the two questions have different costs: "does any shipped
## quest watch this?" is answerable from content alone and never changes while a
## hero lives, whereas "does THIS hero's active set watch it" is per-actor state.
##
## **A catalog change is a stale cache, not a bug.** `_watched` is rebuilt when
## `QuestCatalog.instance()` reports a different generation than the one it read —
## see [method _watched_set] — so installing a fixture catalog mid-process (which
## several suites do) is picked up rather than answered from the shipped set.

## The source string ADR 0114's vocabulary uses for a module-owned fact, so a save
## or a log says which system earned the accrual rather than leaving the beat's own
## `source` to be guessed at. The five authored step facts are written by `combat`,
## `clan` and `sect`; `"fact"` is the neutral word for "the ledger itself reported
## this", and `QuestApi.advance` records it verbatim on each completion's grant
## ledger (ADR 0061's audit trail).
const FACT_SOURCE := "fact"

## Memo of the watched-fact set, rebuilt only when the catalog's content changes.
## A `Dictionary` (empty until first read) rather than a value object: it is a cache
## of AUTHORED CONTENT, rebuilt from the catalog, never player state.
static var _watched: Dictionary = {}
## The catalog generation [method _watched_set] read. `QuestCatalog` exposes no
## generation counter, so this is the identity of the catalog singleton the set was
## built from — a new catalog instance (what `QuestFixtureCatalog.install` swaps in)
## is a different object and therefore a different generation.
static var _catalog: QuestCatalog = null


## Install [method on_fact_recorded] into `core`'s post-write hook slot. The
## composition root calls this beside `DestinyProjection.subscribe_to_fact_ledger()`.
##
## This is a MODULE verb and not a lambda installed by `app/`, for the reason
## `DestinyProjection.subscribe_to_fact_ledger` states: the callable this layer
## publishes states the signature a reader is already looking at, and the module can
## describe what it promises to do with the call. A lambda assembled in `app/` would
## leave `app/` holding the rule and `quest/` holding only a lookup table.
static func subscribe_to_fact_ledger() -> bool:
	return WorldFact.subscribe(Callable(QuestFactProjection, "on_fact_recorded"))


## Whether [method subscribe_to_fact_ledger] is installed. A read rather than a
## compare against the install's return value, so a probe or a test holding no
## reference to the callable can still ask whether the bridge is live.
static func is_subscribed_to_fact_ledger() -> bool:
	return WorldFact.has_subscriber(Callable(QuestFactProjection, "on_fact_recorded"))


## Remove the bridge. The exact inverse of [method subscribe_to_fact_ledger], and
## idempotent. Exists because the test runner shares one process across every
## suite: a suite that left a subscriber installed would complete quests for every
## later suite that records a fact, which is a failure belonging to neither.
static func unsubscribe_from_fact_ledger() -> bool:
	return WorldFact.unsubscribe(Callable(QuestFactProjection, "on_fact_recorded"))


## Re-read every ACTIVE quest of `actor` against the ledger and complete whatever
## crossed the line. **This is the whole body of the dispatch**, for the reason
## `DestinyProjection.on_fact_recorded` is: a chokepoint that also branches is a
## chokepoint that can be reached in a second order.
##
## Returns whether any quest completed. `amount` is deliberately UNUSED: a step is
## satisfied by a ledger COUNT, never by a delta handed to the hook, so one occurrence
## that adds three completes a step needing three exactly as three occurrences of one
## would. It is accepted because the hook's signature is
## `(actor, fact_id, amount)` and that signature is `core`'s, not this file's.
##
## The first read is a cheap predicate against authored content, and only a fact
## some SHIPPED quest watches reaches [method QuestApi.advance] — which is itself
## the module's whole active-set walk, and so is not free.
static func on_fact_recorded(actor: Actor, fact: StringName, amount: int = 1) -> bool:
	if actor == null or fact == &"" or amount < 1:
		return false
	if not _watches(fact):
		return false
	return not (QuestApi.advance(actor, FACT_SOURCE).get("completed", []) as Array).is_empty()


## Whether ANY quest in the catalog watches `fact`.
##
## The content predicate, as opposed to [method QuestBeatHandler.watches], which asks
## the narrower per-hero question. Reading content rather than the active set is what
## makes this cheap enough to run on every recorded fact in the game: it touches no
## `Actor` state and no ledger.
static func _watches(fact: StringName) -> bool:
	var watched := _watched_set()
	if watched.is_empty():
		return false
	return watched.has(String(fact))


## The flat set of every fact any shipped quest's steps watch, as `String` keys,
## memoised against the catalog instance it was built from.
##
## **Rebuilt whenever the catalog identity changes**, so a suite that installs a
## fixture catalog (`QuestFixtureCatalog.install`) is answered from ITS quests and not
## from the shipped tree. A stale memo here would be a suite that asserts a fixture
## quest completes and gets the shipped set's answer instead — a green test about
## the wrong content, which is the failure this whole file exists to end.
static func _watched_set() -> Dictionary:
	var catalog := QuestCatalog.instance()
	if _catalog == catalog and not _watched.is_empty():
		return _watched
	_catalog = catalog
	_watched.clear()
	# Bounded by the authored quest count, and every id a `.tres` ships. A `for` over
	# the catalog's own materialized array, which is the shape `test_no_unbounded_wait`
	# accepts.
	for quest_id in catalog.quest_ids():
		var def := catalog.definition(quest_id)
		if def == null:
			continue
		for fact in def.watched_facts():
			_watched[String(fact)] = true
	return _watched


## The fact ids every quest in `catalog` watches, canonically ordered. Published so a
## probe — and `tools arch`/a content suite — can read the set this dispatch gates
## on rather than re-deriving it from `.tres` files.
static func watched_facts() -> Array[StringName]:
	var watched := _watched_set()
	var strings: Array[String] = []
	for key in watched.keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out
