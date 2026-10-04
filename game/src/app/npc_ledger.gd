class_name NpcLedger
extends RefCounted

## The composition root's SUBSCRIBER to the npc event contract (ADR 0093, BL-0628).
##
## ## Why this file exists
##
## `contracts/npc_events.gd` declares six signals, `npc/api.gd` and `social/api.gd`
## emit all six, and until this file **nothing in the tree connected to any of them**.
## ADR 0093 line 21 promises "a subscriber connects from its own boot function, which
## `app/` calls" — but the promise had no subscriber, so the contract was a declaration
## nothing observed: exactly the "a signal nobody emits" state the contract's own
## docstring calls out. This file is the first real one, and
## `NpcBoot._install_event_seams` is the boot function that connects it.
##
## ## Six signals are subscribed. Read this to learn which job each one does
##
## **Subscribed here: `stage_advanced`, `npc_tracked`, `npc_restored`, `bond_changed`,
## `presence_changed`** — five of the six. `NpcBoot._install_event_seams` connects each
## behind an `is_connected` guard. **`npc_transient` is still unsubscribed**, because no
## consumer for it exists; its reservation is the honest bookkeeping and it is recorded as
## such in `tests/modules/npc/test_npc_event_contract.gd`.
##
## The old ruling — "exactly one signal is subscribed, the other five stay reserved" — was
## reversed by the repo owner (BL-0797). ADR 0093's "Correction (N4)" recorded the earlier
## decision and has been **superseded**, not edited, by the correction appended after it.
##
## ## ## The whole point of this file growing: it records ARRIVALS, never a current state
##
## The recorded risk on this work was that a bounded log would duplicate what
## `NpcApi.state()` and `presence_here()` already answer exactly. It does not, because of
## one rule: **every row here is an edge, and no row here is a state.**
##
## The four facets below are separated on that rule, and the separation is load-bearing
## rather than tidiness — it is what stops a reader mistaking this file for a roster:
##
##   - [member _rows] — **stage movement**. The pre-existing audit trail, bounded at
##     [constant MAX_ROWS].
##   - [member _arrivals] — **roster additions**, bounded at [constant MAX_ARRIVALS]. A
##     `state().tracked_ids` read answers "who do I know" *now* and cannot answer "who
##     arrived while this room was loaded, in what order" — an edge that exists in no read
##     model because reads do not keep history.
##   - [member _seen] — **who the composition root has ever been told about**, bounded at
##     [constant MAX_SEEN]. A set, not a log: the only question it answers is "has the bus
##     told me about this npc yet?", and a *count* or an *order* is not asked. It is
##     deliberately **not** a presence record — see the note on [method presence_seen].
##   - [member _restored] — **the set restored by the last `NpcApi.attach`**, as a count
##     plus a bounded, sorted list. NOT persisted, and see the note on [method restored].
##
## `NpcApi.state()` answers *who is on the roster*. It cannot answer *who arrived during
## this load*, `SocialApi.summary()` answers *what a bond is now*, and
## `NpcApi.presence_here()` answers *who is standing here*. Those are three states; the
## four facets below are four edges. **A state is duplicated here; nothing is.**
##
## ## Why it is a `RefCounted` in `app/` and not a `Node` autoload
##
## `BeatDirector`, `WorldPulse` and `StatusLoop` all took this shape first: wiring, not
## rules, no clock, not an autoload, no `_process`. ADR 0093 accepts one cost of a
## signal bus — "an event that fires before a subscriber connects is lost" — and says
## so rather than leaving it to be discovered. That cost is only honest because the
## connect happens at BOOT, in the same function that installs the constructor, so
## nothing can advance a stage before this ledger is listening.
##
## ## It is a set of AUDIT TRAILS, and it is not persisted
##
## **Counts and bounded lists, never a ledger a save round-trips.** The roster in
## `module_data` is the truth about who an npc is (ADR 0092); this file answers
## different questions — *what did the composition root observe, and in what order* — which
## are logs, and a log in `app/` that grew without limit is the stateful-system shape
## `tools/arch/rules.py` rejects. Hence one named constant per facet and a DROPPED oldest
## row at each bound, so the memory is a set of constants rather than a growth curve.
##
## It holds no `Actor`, reads no `module_data` and writes none, so it adds no
## `persistence` signal to `app/` and never trips the app-state check.
##
## ## Primitives only, one fact per row (ADR 0093)
##
## The stage rows are `{npc_id, stage_id, source}` — all strings. `source` is kept because
## ADR 0093 makes it the way a consumer filters its own effects: a world event that
## moved an npc is distinguishable from a direct `advance_stage` without re-deriving it.
## The bond rows are `{partner, cause, ordinal}` — an `ordinal` and **no numbers**,
## because ADR 0093 makes a cause id rather than a delta the published shape, and a
## subscriber that stored a standing here would be the second writer of a bond.

## The most rows the trail keeps. A save is a roster; this is a log, and a log that
## grew with every stage advance for the length of a session would be the unbounded
## table the composition root is not allowed to hold. The oldest row is dropped first.
const MAX_ROWS := 64

## The most roster ARRIVALS kept, for [constant MAX_ROWS]'s reason. Separate from
## [constant MAX_ROWS] because it is a different question with a different rate: a stage
## advances a handful of times in a session, a settlement can be re-stocked on every room
## load, and one cap shared by both would silently shorten the stage audit trail.
const MAX_ARRIVALS := 64

## How many distinct npcs [member _seen] remembers. A set of ids, so this is the roster's
## own scale and not a session-length scale: a named bound, with the oldest id dropped when
## it is reached, rather than a table that grows one row per event.
const MAX_SEEN := 128

## How many ids the `npc_restored` answer lists. A `NpcState.MAX_ROSTER` roster is the
## real ceiling on this count, so this is headroom over a bound that already exists
## elsewhere — the restored *count* below is exact and uncapped, and only the printable
## list is capped, because a caller asking "how many came back" is asking a real question
## that this file must not answer `64` to.
const MAX_RESTORED_LIST := 64

## How many bond edges kept, for [constant MAX_ROWS]'s reason. Separate again because
## `bond_changed` fires on every `SocialApi.apply_cause` — an interaction, not a stage
## change — so it is the fastest-moving edge on the contract and the one most likely to
## hit its cap inside a single conversation.
const MAX_CAUSES := 64

## Every `stage_advanced` this process has observed, oldest first.
##
## A `static var` because the bus is process-wide (`NpcEvents.shared()`) and a
## per-instance sink would need every owner to keep it alive to be worth connecting.
## `rules.py` excludes `static var` from the app-state heuristics by construction:
## this is process-wide memoisation, the same shape `recipe_catalog.gd` caches a
## directory walk in.
static var _rows: Array[Dictionary] = []

## Every roster ADDITION this process has observed, oldest first — `npc_tracked` only.
##
## **This is not a roster and must never be read as one.** `NpcApi.state(player)` answers
## "who do I know" at full fidelity and is the truth; this answers a narrower question
## that no read model can answer, because reads keep no history: *who entered the roster,
## and in what order, since this process started listening.* The distinction is load
## bearing and pinned by a test — a second record of the roster's contents is the
## recorded risk on this work, and a set of `npc_id` values that is only ever appended to
## and only ever read as a log is not that.
static var _arrivals: Array[Dictionary] = []

## The npcs the bus has announced, in first-seen order. Bounded by [constant MAX_SEEN].
##
## **Why this is a SET and not a log.** A count is asked ("has the bus told me about the
## elder?") and an order is not; an unbounded per-event log would be a session-length
## table in `app/`, and a bounded one that dropped arrivals would fail the count it
## exists to give. Keeping the ids and dropping only the oldest past the bound answers the
## question honestly for the whole shipped roster and says nothing about order.
static var _seen: Array[String] = []

## The npcs the most recent `NpcApi.attach` announced through `npc_restored`, newest last.
static var _restored: Array[String] = []

## How many bond edges this process has observed in total, uncapped — unlike
## [method bond_edge_count] below, which counts what is HELD. The difference is the
## point: the held table drops its oldest row at [constant MAX_CAUSES], so a counter that
## counted the table would stop moving and read as "nothing has happened since".
##
## Declared HERE rather than beside [method bond], which uses it: GDScript requires
## every field to precede every function in the global scope, and a `static var` after a
## `static func` is a `class-definitions-order` error. `gdlint` catches it, but a class
## that fails to parse is reported by every dependant as "Could not resolve class", which
## is how a two-line ordering slip in this file reddened `npc_boot.gd` and with it every
## suite that boots the app.
static var _bond_edges: int = 0

## Every `bond_changed` this process has observed, oldest first, bounded at
## [constant MAX_CAUSES]. `ordinal` is the uncapped edge number, so a row dropped from the
## front still carries the order it was announced in.
static var _causes: Array[Dictionary] = []


## The subscriber ADR 0093 names. Connected by `NpcBoot.install`; the exact static
## Callable, so `is_connected` can recognise it across boots and not connect twice.
static func advanced(npc_id: String, stage_id: StringName, source: String) -> void:
	var row := {"npc_id": npc_id, "stage_id": String(stage_id), "source": source}
	if _rows.size() >= MAX_ROWS:
		_rows.remove_at(0)
	_rows.append(row)


## ## `npc_tracked` — an arrival, not a roster
##
## Records that `npc_id` entered the roster for the first time, with the `tier` the roster
## gave it. **`NpcApi.spawn` emits this only when it created the entry**, so every row here
## is a genuine first meeting and re-spawning somebody already known writes none.
##
## The `seen` call is shared with the other four subscribers and is what makes
## [method seen] a real answer rather than a log: whichever signal names an npc first is
## the one that introduces it here.
static func tracked(npc_id: String, tier: StringName) -> void:
	_see(npc_id)
	if _arrivals.size() >= MAX_ARRIVALS:
		_arrivals.remove_at(0)
	_arrivals.append({"npc_id": npc_id, "tier": String(tier)})


## ## `npc_restored` — the roster this process came back up with
##
## Records the ids `NpcApi.attach` announced, which is the roster that was on the save.
## **Not persisted and not a second roster**: [method restored] answers the same thing
## from the ids plus a count, and the roster's contents stay `NpcApi.state`'s to publish.
##
## **Why `attach`'s emit is a restore replay and not a new fact.** `NpcApi.attach` emits
## `npc_restored` once per roster entry on EVERY call, and `install` calls `attach` on
## every boot AND after a load. So a row lands here the first time and again on each
## re-attach. A set is therefore the honest shape — an ordered log would claim an arrival
## history that the signal does not carry, and a save-migration tool reading it would see
## the same npc "restored" three times in one session. [method restored_count] answers the
## count, and the flatness across re-attach is what a test pins.
##
## `is_tracked` and `stage_id` are accepted and **not stored**: they are the two facts the
## roster already owns, and keeping either here is the second copy of the truth this work
## was warned about.
static func restored(
	npc_id: String, _tier: StringName, _stage_id: StringName, _is_tracked: bool
) -> void:
	_see(npc_id)
	if not _restored.has(npc_id):
		_restored.append(npc_id)


## ## `bond_changed` — an observed relationship edge, with the cause that made it
##
## `social/` publishes this on the shared bus because it owns the ledger, and `social/`
## may not depend on `npc/`. Recording it here is the one place the composition root
## observes a relationship it does not own.
##
## **Why this is not a second copy of the bond ledger.** `SocialApi.summary(player)`
## publishes every bond's standing, trust and class, and that read stays the truth. What
## no read model carries is the **edge**: which authored cause last moved a bond, on which
## partner, in what order — a bond's history is a set of causes and reads do not keep one.
## So this records `(partner, cause, ordinal)` and no numbers. Deliberately **not** a
## standalone table either: [method last_cause_for] reads `SocialApi.summary` at call
## time, so a row here can never disagree with the ledger about what a bond is.
static func bond(npc_id: String, cause_id: StringName) -> void:
	_see(npc_id)
	if _causes.size() >= MAX_CAUSES:
		_causes.remove_at(0)
	_causes.append({"partner": npc_id, "cause": String(cause_id), "ordinal": _bond_edges})
	_bond_edges += 1


## How many bond edges this process has observed in total, uncapped — unlike
## [method bond_edge_count] below, which counts what is HELD. The difference is the
## point: the held table drops its oldest row at [constant MAX_CAUSES], so a counter that
## counted the table would stop moving and read as "nothing has happened since".
## DECLARED ABOVE, beside the other fields: GDScript requires every field to precede
## every function, so a `static var` down here is a `class-definitions-order` parse error
## — and a class that fails to parse is reported by every dependant as "Could not resolve
## class", which is how a two-line ordering slip here reddened `npc_boot.gd` and with it
## every suite that boots the app.


## ## `presence_changed` — a membership edge, and NOTHING else
##
## This is the subscriber most at risk of being the recorded risk, so read the exclusion
## first: **this file does not hold presence.** `NpcApi.presence_here(location_id)` and
## `NpcApi.state(player)` remain the truth for who is where, and nothing here is consulted
## to answer that. What is recorded is a single edge — that `npc_id` was announced at
## all — and nothing derives from it about the current state of anyone.
##
## That is enough for the job it does have: a roster or minimap needs to know an npc
## *left* in order to drop them off a list it already holds, and there is no read model
## that says "who has left since I last looked" because reads do not keep history. The
## method that answers it is [method presence_seen], and it answers **"have I been told
## about this npc at all"** — a set, not a table of presence values, precisely so the
## bounded copy here cannot be mistaken for one.
##
## `announced` is accepted and **not stored**, for the same reason as
## [method restored]: a presence value kept here is a second writer of
## `NpcRosterEntry.presence`, and the recorded risk on this work is precisely that.
static func presence(npc_id: String, _announced: StringName) -> void:
	_see(npc_id)


## ## The shared "the bus has named this npc" edge
##
## Every one of the four subscribers calls this, so [method seen] answers for the whole
## contract rather than for whichever signal happened to fire. It is the one genuinely
## novel join available to the composition root: `NpcApi.state()` answers who is on the
## roster, and nothing anywhere answers **who has been announced but is not on it** — the
## untracked case, which is exactly where a roster screen goes wrong.
static func _see(npc_id: String) -> void:
	if npc_id.is_empty() or _seen.has(npc_id):
		return
	if _seen.size() >= MAX_SEEN:
		_seen.remove_at(0)
	_seen.append(npc_id)


## The trail, newest first — the order a panel or a probe reads it in. Copied, so a
## caller cannot reach in and rewrite history.
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in range(_rows.size() - 1, -1, -1):
		out.append((_rows[index] as Dictionary).duplicate())
	return out


## How many advances have been observed, capped at [constant MAX_ROWS].
static func count() -> int:
	return _rows.size()


## The most recent row, or `{}` when nothing has advanced yet — the same empty-shape
## answer `NpcApi.summary` gives for an npc it does not ship.
static func last() -> Dictionary:
	if _rows.is_empty():
		return {}
	return (_rows[_rows.size() - 1] as Dictionary).duplicate()


## ## The roster ARRIVAL log, newest first, and how many arrived
##
## Read this next to `NpcApi.state`, which is the roster itself: this is a subset of it
## (arrivals only, capped, and empty before the first `install`) while that is the whole
## thing. **The question only this answers is "who arrived, and in what order."**
static func arrivals() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in range(_arrivals.size() - 1, -1, -1):
		out.append((_arrivals[index] as Dictionary).duplicate())
	return out


## How many arrivals are held, capped at [constant MAX_ARRIVALS].
static func arrival_count() -> int:
	return _arrivals.size()


## Whether the bus has ever announced `npc_id`, by ANY of the subscribed signals.
##
## **True for an npc who is not on the roster.** `presence_changed` and `bond_changed`
## reach here without a roster entry ever existing, which is the whole reason this is not
## `NpcApi.state` with a different name.
static func seen(npc_id: String) -> bool:
	return _seen.has(npc_id)


## Every id the bus has announced, in first-seen order. Bounded at [constant MAX_SEEN].
static func seen_ids() -> Array[String]:
	return _seen.duplicate()


## ## `presence_changed`'s only question, and what it deliberately does NOT answer
##
## **This is not "where is this npc".** `NpcApi.presence_here(location_id)` is, and it is
## the truth; this exists so a list the composition root already holds can drop someone the
## bus has just said is no longer present, without polling a read model for a change.
static func presence_seen(npc_id: String) -> bool:
	return _seen.has(npc_id)


## ## The bond edges, newest first, and the cause that last moved a bond
##
## `bond_changed` carries a cause id and never a number (ADR 0093's anti-farm rule), so
## neither the log nor this answer contains standing, trust or class. Those stay
## `SocialApi`'s to publish and stay the truth.
static func bond_edges() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in range(_causes.size() - 1, -1, -1):
		out.append((_causes[index] as Dictionary).duplicate())
	return out


## How many bond edges are HELD, capped at [constant MAX_CAUSES]. Use
## `bond_edge_total`'s counter — use it for "how many have
## happened"; this answers "how many can I still read".
static func bond_edge_count() -> int:
	return _causes.size()


## How many bond edges this process has observed, uncapped. Continues past
## [method bond_edge_count] because the held table is bounded and this is not.
static func bond_edge_total() -> int:
	return _bond_edges


## The newest recorded cause for `partner_id`, or `""` when the bus has not announced one.
##
## **This is a log read, not a ledger read** — it answers "what cause did the bus last
## announce for this partner", which is only knowable from the announcement order. The
## magnitude and class of the bond are not here and must be read from `SocialApi`.
static func last_cause_for(partner_id: String) -> String:
	var want := String(partner_id)
	for index in range(_causes.size() - 1, -1, -1):
		var row := _causes[index] as Dictionary
		if String(row.get("partner", "")) == want:
			return String(row.get("cause", ""))
	return ""


## ## The save-load census, read as a count plus a bounded list
##
## `attach` announces one `npc_restored` per roster entry on every boot and after every
## load, so the useful answer is **"how big was the roster this process came back up
## with"**, and a count is exact. The list is capped at [constant MAX_RESTORED_LIST]
## because a save that large is one no panel can print, and the count above it stays true
## rather than reporting the cap.
static func restored_count() -> int:
	return _restored.size()


## The restored ids, sorted so two reads of the same save agree, capped at
## [constant MAX_RESTORED_LIST]. Copied, like every other read here.
static func restored_ids() -> Array[String]:
	# `duplicate()` on a typed Array still returns Variant, and a `:=` that infers
	# Variant is a hard parse error here (the warning is treated as an error), so
	# the local is annotated rather than inferred.
	var out: Array[String] = _restored.duplicate()
	out.sort()
	if out.size() > MAX_RESTORED_LIST:
		out = out.slice(0, MAX_RESTORED_LIST)
	return out


## ## The proof this file is not holding a second roster
##
## `_restored` is a set of ids with nothing else on it: no tier, no stage, no payload.
## A reader asking "who is on the roster" gets the answer from `NpcApi.state(player)`
## and never from here. **If this file ever grew a per-npc row carrying tier or stage, that
## would be exactly the second copy of the truth this work was warned about**, and
## `tests/app/test_npc_event_subscribers.gd` is written to go red if it does.
static func restored() -> Dictionary:
	return {"count": restored_count(), "ids": restored_ids()}


## Forget the trail. Only a test harness calls this: `NpcEvents.shared()` is
## process-wide and a suite that advanced an elder would otherwise leave a row behind
## for whichever npc suite runs next and read a count that is not its own.
##
## Clears **every** facet, and one `clear()` rather than five because a reset that
## forgets one facet would let the next suite read an arrival or a bond edge it did not
## write — the exact cross-suite leak the trail above was written to avoid.
static func reset() -> void:
	_rows.clear()
	_arrivals.clear()
	_seen.clear()
	_restored.clear()
	_causes.clear()
	_bond_edges = 0
