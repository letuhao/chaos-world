class_name WorldFact
extends RefCounted

## One row of the world's memory, plus the ledger API that owns it (ADR 0113).
##
## ## Why this is a value object in `core/` and not in a module
##
## Four systems already needed this memory and none of them could be reused:
## `ItemDef.sources`, `DestinyState`, `NpcState` and the institutional ledgers.
## A fourth copy of "a thing happened, count it" is the ADR 0066 failure mode
## spelled `realm_power_table.tres`, and a fifth module inventing its own flag
## store is worse. So the type is shared foundation, and shared foundation lives
## in `core/` beside `InstitutionClaim` (ADR 0083) and `RealmRate` (ADR 0066):
## `core` is a LAYER rather than a module, so the cross-module facade rule never
## applied to it and this file adds zero new edges. The consolidation is the
## `DestinyState` shape read at file scope — `SCHEMA_VERSION`, `normalize`,
## read verbs, one write verb, JSON-round-trippable — so a reviewer comparing
## the two sees one ledger rather than two.
##
## ## What a fact is NOT
##
## No reward, no flag semantics, no effect reference. A fact is a thing that
## happened, not a thing that grants something: granting here would put the
## world's memory in charge of the economy, the loot table and the fate tree in
## one row. A thing that is consumed is a quest step, not a fact.
##
## ## Monotone, and no verb here lowers a count
##
## ADR 0065's rule — fate is earned, never removed — is the house position on
## remembered things, so `record` raises a count and nothing else can lower one.
## A fact cannot be spent, spent again or revoked. Rejected: a `spend`/`consume`
## verb, because the moment a fact can be taken back this file needs a second
## concept (a reservation) and a verb that can fail, and both of those are the
## quest system's problem to own rather than a property of memory.
## [method normalize_payload] may DROP a row it cannot READ; it may never drop a
## row because the player did something. That distinction is ADR 0065's design.
##
## ## `since` is the count at first record
##
## `since` is written on the first `record` and never moves again, which is what
## makes a "first time" gate answerable from one row: a fact whose `since` still
## equals its `count` has happened exactly once. ADR 0113 names the field "the
## count at first record" without saying whether that is before or after the
## first accrual lands; this file reads it as AFTER, so a first record of three
## is `count == since == 3` and the two halves can never disagree.
##
## ## No clock, ever
##
## Every accrual takes an explicit `amount` from a caller that owns the moment.
## No timer, no `Time.get_ticks*`, no `get_tree()` in `core` (DEF-0111). A
## "days survived" fact therefore needs a clock this file refuses to have; the
## ADR records that as deferred rather than quietly inventing one.

## ## One writer, and therefore ONE place a consequence can hang off a fact
##
## [method record] is the only verb in the repository that writes this ledger, and
## every producer reaches it: `app/BeatDirector`, `combat/CombatFacts`,
## `clan/ClanFacts`, `sect/SectFacts`, `event/EventBeatWriter` and
## `app/CharacterCreationFlow`. A subscriber that wants to know "this happened"
## therefore has exactly two honest shapes: call [method record] itself and hope
## every writer went through it, or be told. The hook slot below is the being-told.
##
## **Dispatching somewhere else cannot work, and this is the measurement.**
## `BeatDirector.offer` looks like the choke point — it is the one place a beat is
## resolved (ADR 0114) — but it has exactly ONE production caller,
## `app/WorldPulse.offer`, and that caller offers only the period fact and the four
## `app/WorldAmbient` roster facts. A dispatch there moves a counter for none of the
## facts a module actually records, which is the whole defect: the machinery was
## green and unwired (ADR 0149). A subscriber installed here is reached by all six
## writers, including the five that bypass the director by design.
##
## **This file names no subscriber and no module.** `tools arch` holds `core/` to
## `LAYER_DEPS["core"] == {"core", "contracts"}`, so a `destiny` reference here —
## `res://` path, `extends`, or bare class name — would be a boundary violation, and
## `BARE_REF_UNITS` deliberately excludes `core/`, so a bare name would not even be
## seen as an edge. The slot is a `Callable` and the composition root fills it
## (`app/item_workbench_app.gd`), which keeps the edge `app/` -> `destiny` and never
## `core/` -> `destiny`. Rejected: a `res://` preload with a lazy resolve, which is
## the same dependency wearing a disguise.

const SCHEMA_VERSION := 1
## `actor.module_data` key (ADR 0027's pattern, the key `DestinyState` uses).
const MODULE_KEY := &"world_facts"

## Which recorded fact this row is. A bare id in ONE flat namespace: no
## `quest:` prefix, mirroring ADR 0065's refusal to let an id join a namespace
## that would "read as a working reference and silently grant nothing".
var id: StringName = &""
## How many times it has happened. Rises only, and never falls.
##
## Named `total`, not `count`, and the reason is mechanical rather than stylistic:
## ADR 0113 freezes the ledger verb as `WorldFact.count(actor, id)`, and GDScript
## refuses a class that holds a member variable and a method of one name, so the
## member yields. The stored row key stays `"count"` — `DestinyGate`, the event
## module's `has_fact` and `QuestFactReader` all read it by that name — so the
## rename is invisible to every reader and the freeze is not.
var total: int = 0
## The count this fact took when it was first recorded. Written once.
var since: int = 0

# --- The post-write hook ------------------------------------------------------

## The subscribers [method record] tells after a successful write, in install order.
##
## **A list, not one slot.** A single `static var` is last-install-wins, which is
## invisible: a second consumer — or a test that installs its own — overwrites the
## first with no error and no report, and the bug reads as "the hook did not fire".
## A list makes every install observable, makes removal answerable by identity, and
## lets a subscriber leave the process exactly as it found it, which matters here
## because `tests/run_tests.gd` runs every suite in ONE process.
##
## **Iterated over a COPY.** A subscriber is allowed to subscribe, unsubscribe or
## fail; mutating the array a `for` is walking is the shape that skips or repeats an
## entry, and a counter moved once per recorded occurrence is the property this slot
## exists to make true.
static var _subscribers: Array[Callable] = []


## Tell `subscriber` after every successful [method record].
##
## `subscriber` is called as `subscriber.call(actor, id, amount)`: the three facts a
## consequence needs, and nothing else. It is NOT handed `record`'s report — a
## subscriber that learned the report could start answering "did it write" from a
## dictionary rather than from [method count], which is the one read path.
##
## A null or already-installed `subscriber` is refused, because a duplicate is a
## second handler answering one occurrence — the same rule `BeatDirector.add_sink`
## states, and for the same reason.
static func subscribe(subscriber: Callable) -> bool:
	if subscriber.is_null() or _subscribers.has(subscriber):
		return false
	_subscribers.append(subscriber)
	return true


## Remove `subscriber` and answer whether it was there. The inverse of
## [method subscribe], and idempotent: removing what is not installed is not an error.
static func unsubscribe(subscriber: Callable) -> bool:
	# `Array.erase()` returns void in Godot 4, so the answer comes from a membership
	# test taken BEFORE the removal rather than from its return value -- which also
	# makes "was it there" independent of erase's signature.
	if subscriber.is_null() or not _subscribers.has(subscriber):
		return false
	_subscribers.erase(subscriber)
	return true


## Whether `subscriber` is installed. A read rather than a compare against
## [method subscribe]'s return value, so a caller holding no reference to the
## `Callable` it installed earlier can still ask.
static func has_subscriber(subscriber: Callable) -> bool:
	return not subscriber.is_null() and _subscribers.has(subscriber)


## How many subscribers are installed. Published for a probe and for a suite to
## assert on: a hook that is installed for nobody looks identical to one that fires
## for nobody, and this is the difference.
static func subscriber_count() -> int:
	return _subscribers.size()


## Drop every subscriber, and answer how many were dropped. For a process that
## tears the wiring down rather than running a game forever; a normal caller
## unsubscribes what it installed.
static func clear_subscribers() -> int:
	var dropped := _subscribers.size()
	_subscribers.clear()
	return dropped


# --- The ledger ---------------------------------------------------------------


## The empty ledger. A missing key, an unreadable payload and this are the same
## value, so "nothing has happened" has one spelling instead of three.
static func empty() -> Dictionary:
	return normalize_payload({})


## The ledger `actor` carries right now, repaired. Never throws: a save is
## untrusted input, `Actor.get_module_data` already answers an empty dictionary
## for a payload that is not a dictionary at all, and every field below is
## coerced on the way in. A payload that cannot be read is diagnosed as empty
## rather than partially applied — half a ledger is worse than none, because it
## would silently change what the player is owed (ADR 0065).
static func normalize(actor: Actor) -> Dictionary:
	if actor == null:
		return empty()
	return normalize_payload(actor.get_module_data(MODULE_KEY))


## A ledger rebuilt from a saved payload, JSON hop included.
##
## Named apart from [method from_dict] because a class may hold one method of a
## name and the two readers are genuinely different things: this one normalises
## a PAYLOAD (ADR 0113's `from_dict`, the entry point a file-backed save takes),
## and [method from_dict] builds a FACT from one row. Rows that read back with a
## count of zero or less are dropped rather than persisted — the same repair
## ADR 0065's `normalize` does, for the same reason.
static func normalize_payload(payload: Dictionary) -> Dictionary:
	var out := {"version": SCHEMA_VERSION, "facts": {}}
	var facts = payload.get("facts", {})
	if not (facts is Dictionary):
		return out
	for key in (facts as Dictionary).keys():
		var entry = (facts as Dictionary)[key]
		var row := {"id": String(key)}
		if entry is Dictionary:
			row["count"] = (entry as Dictionary).get("count", 0)
			row["since"] = (entry as Dictionary).get("since", 0)
		var fact := from_dict(row)
		# A row is kept only when it names something AND counts something. The
		# empty id matters: an unnamed row can never be read back by any verb, so
		# keeping it would persist a fact no query can reach — a memory nothing
		# can ask for.
		if fact.id != &"" and fact.total > 0:
			out["facts"][String(key)] = {"count": fact.total, "since": fact.since}
	return out


## The JSON-safe payload a save carries. Identical to what
## `Actor.to_dict`/`Actor.from_dict` move under [constant MODULE_KEY].
##
## `String` keys throughout and no `StringName` anywhere: `Actor.to_dict`
## converts only the OUTER `module_data` key, so an inner `StringName` key would
## reach the save untouched and break every round trip. `InstitutionClaim`
## documents the same trap for `obligation`.
static func to_dict(actor: Actor) -> Dictionary:
	return normalize(actor)


## One fact from one row. Every field is coerced, and `since` is clamped into
## `[0, count]` rather than persisted out of range: the invariant
## `0 <= since <= count` is what "written on the first record, never advanced"
## means in storage, and a hand-edited save must not be able to state otherwise.
## A row that lost its `since` keeps a zero — the ledger is monotone and will
## not invent a history it was not told.
static func from_dict(data: Dictionary) -> WorldFact:
	var fact := WorldFact.new()
	fact.id = StringName(data.get("id", ""))
	fact.total = maxi(0, int(data.get("count", 0)))
	fact.since = clampi(int(data.get("since", 0)), 0, fact.total)
	return fact


## The JSON-safe row for this fact. The inverse of [method from_dict].
func to_row() -> Dictionary:
	return {"id": String(id), "count": total, "since": since}


## Every fact id the ledger holds, canonically ordered by its STRING value.
##
## Not `out.sort()`: `Array[StringName].sort()` is not specified to order by
## StringName's string value and the ids are interned, so the result could depend
## on which id loaded first. `DestinyState._sorted_keys` is copied for the same
## reason, because the order is load-bearing — a codex cycling this list must not
## reorder itself between reads.
static func ids(actor: Actor) -> Array[StringName]:
	var strings: Array[String] = []
	for key in _rows(actor).keys():
		strings.append(String(key))
	strings.sort()
	var out: Array[StringName] = []
	for key in strings:
		out.append(StringName(key))
	return out


## How many times `id` has happened, or 0 when it never has.
##
## A missing fact and a zero count are the same answer, exactly as
## `DestinyState.counter_value` reports them: a count never falls, so nothing can
## have happened zero times.
static func count(actor: Actor, id: StringName) -> int:
	var rows := _rows(actor)
	var entry = rows.get(String(id), {})
	if not (entry is Dictionary):
		return 0
	return maxi(0, int((entry as Dictionary).get("count", 0)))


## Whether `id` has been recorded at least `need` times.
##
## `need` defaults to 1, so `has(id)` means "counted at least once", and it is
## FLOORED at 1 rather than trusted: `has(id, 0)` reading true for a fact nobody
## recorded would open a gate on content the player never reached, which is the
## malformed-requirement refusal `DestinyGate` states for the same reason.
static func has(actor: Actor, id: StringName, need: int = 1) -> bool:
	return count(actor, id) >= maxi(1, need)


## Record that `id` happened `amount` more times. The ONLY verb that writes.
##
## `amount` must be at least 1 and is taken from a caller that owns the moment
## (DEF-0111). Zero or less is REFUSED with a reason and mutates nothing: a
## caller computing a delta of zero has a bug, and silently absorbing it would
## leave the ledger claiming a thing happened that did not. `since` is written
## on the first record only and never advanced, which is what makes the
## "first time" gate in the class docstring answerable from one row.
##
## Returns `{ok, reason, id, count, since}` on success and
## `{ok: false, reason}` on a refusal — a primitives-only payload, because the
## result is an announcement about a remembered thing and travels into logs and
## UI summaries. Rejected: a silent `void`, because a refusal a caller cannot
## read is a bug reported three stages later as "the quest never completed".
##
## ## Subscribers are told AFTER the write, and only on `ok: true`
##
## Every refusal returns above, before the ledger is touched and before a single
## subscriber is called: a claim that was refused moved nothing, so a consequence
## derived from it must move nothing either. And the notification is the LAST
## thing this verb does, so a subscriber reads the ledger through [method count]
## and sees the occurrence already in it — the same reason `BeatDirector` records
## before it consults a sink (ADR 0114).
##
## **A subscriber is told, not asked to decide.** It returns nothing that this verb
## reads: the ledger write is the whole answer to "did it happen", and a
## consequence that could veto, retry or reverse it would be a second writer wearing
## a notification's clothes.
static func record(actor: Actor, id: StringName, amount: int = 1) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor"}
	if id == &"":
		return {"ok": false, "reason": "empty_id"}
	if amount <= 0:
		return {"ok": false, "reason": "non_positive"}
	var ledger := normalize(actor)
	var rows := ledger["facts"] as Dictionary
	var key := String(id)
	var entry = rows.get(key, {})
	var previous := 0
	var first_since := 0
	if entry is Dictionary:
		previous = maxi(0, int((entry as Dictionary).get("count", 0)))
		first_since = clampi(int((entry as Dictionary).get("since", 0)), 0, previous)
	var total := previous + amount
	# First record writes `since` to the total it just reached; every later record
	# leaves the stored `since` exactly where the first one put it.
	var since := total if previous <= 0 else first_since
	rows[key] = {"count": total, "since": since}
	actor.set_module_data(MODULE_KEY, ledger)
	var report := {"ok": true, "reason": "", "id": key, "count": total, "since": since}
	_notify_recorded(actor, id, amount)
	return report


## Tell every installed subscriber that `id` happened `amount` more times.
##
## Private because a caller must not announce an occurrence it did not record: the
## ONLY legal way to reach it is [method record]'s tail, which is what makes "one
## occurrence moves a consequence exactly once" a property of the code rather than
## of every caller's discipline.
##
## **The zero-subscriber case returns immediately.** It is the overwhelmingly
## common one — most facts no fate, quest or event reads — so the common case must
## not allocate a copy of the subscriber list to discover there is nobody to call.
static func _notify_recorded(actor: Actor, id: StringName, amount: int) -> void:
	if _subscribers.is_empty():
		return
	for subscriber in _subscribers.duplicate():
		# An entry an EARLIER subscriber's own callback removed is SKIPPED rather than
		# called. That is the one way this loop could otherwise double-fire a
		# consequence: iterating a copy taken before the callback ran, an entry that
		# is no longer installed would still be called from the copy. Re-reading
		# membership per entry closes it at the cost of one array scan per subscriber.
		if not _subscribers.has(subscriber):
			continue
		subscriber.call(actor, id, amount)


## The row for `id` as a value object, or an empty one naming nothing when it
## was never recorded.
##
## A COPY, never a view: writing to the returned fact changes no ledger, because
## the ledger exposes no setter and this class is the only thing that may write.
## Rejected: handing back the stored dictionary, which would be a second way to
## edit memory past the monotone verb above.
static func fact(actor: Actor, id: StringName) -> WorldFact:
	var row := {"id": String(id)}
	var entry = _rows(actor).get(String(id), {})
	if entry is Dictionary:
		row["count"] = (entry as Dictionary).get("count", 0)
		row["since"] = (entry as Dictionary).get("since", 0)
	return from_dict(row)


# --- Internals ---------------------------------------------------------------


## The repaired fact rows of `actor`, or empty ones for a null actor. One read
## path for every verb, so `count` and `record` cannot disagree about what the
## ledger holds.
static func _rows(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var ledger := normalize(actor)
	return ledger["facts"] as Dictionary
