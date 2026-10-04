class_name CombatDuel
extends RefCounted

## The player's record of the fights they have finished, persisted on the actor under
## `module_data["combat_duel"]` so a fight survives a save (ADR 0027's pattern: a plain
## versioned dictionary applied through `Actor.set_module_data`, never a serialized type).
##
## A DEFEAT and a duel ENDED are both recorded here, and they are recorded on the
## opponent whose fight it was: a defeat on the loser, an ending on the side that ended
## it. `LootApi` owns what a run is worth and what a run costs; `combat` owns how a
## fight between two people finished, so a screen can say so. Kept deliberately thin —
## the fight's own state (whose vitality is spent) belongs to the encounter that owns it.
##
## ## Why a WIN is recorded and a spare is a STATE
##
## `CombatExchange.exchange` counted defeats only, so a win had no ledger anywhere and
## `exchange.gd`'s own note that "a winning fight never reaches `record_defeat`" was a
## statement about a hole. A win is counted here for symmetry.
##
## A spare is different in kind: it is not a tally, it is a **terminal state of the
## loser**, and it lives on the loser precisely so that a later blow can be REFUSED
## against it (`CombatDuelHit.resolve`'s `defender_spared`). A counter on the victor
## alone would record that somebody was merciful once and would leave the defeated
## opponent available to be killed afterwards, which is not mercy, it is a note.

const SCHEMA_VERSION := 1
const MODULE_KEY := &"combat_duel"

## The fate a felled encounter leaves behind (DEF-0105).
##
## It is granted by `CombatDuel.record_defeat`, which is the ONE place a fight is
## decided lost, and NOT by `CombatExchange._record_defeat` which calls it: putting
## it in both would make "the duel ledger counted a defeat" and "the player earned a
## fate" two statements about the same event that could disagree.
##
## `vigil_broken_by_hand` is the authored fate whose own text is about a duel fought
## AWAY from the one that was owed — "Came off the wall mid-watch to settle a private
## matter ... Two of its dead were not the reason anyone remembers you", with
## `counters = [watch_turned, duels_won]` — and the boss run this module counts a
## defeat inside IS the private matter. It is also granted by
## `what_the_rotation_cost.tres`, and `earn_fate` is exactly-once, so the quest pays
## nothing twice (ADR 0065).
const FATE_FELL := &"vigil_broken_by_hand"

## The fate a WON duel earns — `first_blood_duel` (DEF-0105).
##
## Its own text is the shape `CombatDuel.record_win` decides: "Opened a duel and
## closed it, alone, without assistance ... the second party filed nothing."
## `record_win` fires on the KILLING blow and on nothing else — a spared opponent
## deliberately never reaches it — so "closed it" and "did not file" are both
## already true of the moment this is granted.
##
## It is also paid by `tournament_of_the_spirit_peaks.tres`, which is GATED on
## `{"verb": &"has_fate", "id": &"first_blood_duel"}` — so until a duel pays it,
## that event cannot open for anybody. `earn_fate` is exactly-once, so the tournament
## pays nothing twice.
const FATE_FIRST_BLOOD := &"first_blood_duel"

## How many recent fights are remembered by name. A bounded ring, not a history: the
## count is the durable fact and the last few entries are the readable ones.
const HISTORY_LIMIT := 5

## The `source` string every fate `combat` earns carries, exactly as
## `QuestGrants.FATE_SOURCE_PREFIX + quest_id` and `EventDef.fate_source()` build
## theirs: it names the SYSTEM that earned the fate and never the fate id, so an
## audit reading the ledger cannot mistake a duel for a quest or an event (ADR 0065
## on id namespaces).
const EARN_SOURCE := "combat"


static func blank() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"defeats": 0,
		"wins": 0,
		"last_defeat": {},
		"last_spare": {},
		"spared_by": "",
		"history": [],
	}


## A usable record from anything `module_data` may hold. A payload written before a field
## existed loads with that field empty rather than failing, and the version is stamped on
## the way out.
static func normalize(raw: Dictionary) -> Dictionary:
	var duel := blank()
	if raw.is_empty():
		return duel
	duel["defeats"] = maxi(0, int(raw.get("defeats", 0)))
	duel["wins"] = maxi(0, int(raw.get("wins", 0)))
	if raw.get("last_defeat") is Dictionary:
		duel["last_defeat"] = (raw["last_defeat"] as Dictionary).duplicate(true)
	if raw.get("last_spare") is Dictionary:
		duel["last_spare"] = (raw["last_spare"] as Dictionary).duplicate(true)
	duel["spared_by"] = String(raw.get("spared_by", ""))
	if raw.get("history") is Array:
		duel["history"] = (raw["history"] as Array).duplicate(true).slice(-HISTORY_LIMIT)
	duel["version"] = SCHEMA_VERSION
	return duel


## Record one defeat: `taken` is the share of the player's health the final blow spent.
##
## ## DEF-0105: this is where combat earns a fate
##
## It is the ONE place a fight is decided lost, and `CombatExchange._answer` calls
## it on the run that ends, so a defeat is the moment combat OWNS and nothing else
## decides. `combat` therefore calls the facade here rather than listening: fate is
## a write target, never a listener (ADR 0065).
##
## ## The earn is VERIFIED, because `earn_fate` returns the LEDGER and never a verdict
##
## Every refusal path — unknown id, already-held, a null actor — returns that same
## ledger, byte for byte, and queues nothing. Treating the call as "already offered"
## is the defect `event_prize.gd:95-96` ships; the only correct idiom is
## `character_creation_flow.gd:280-284`'s: ask `has_fate` afterwards and branch on
## THAT. The returned boolean is what a caller reads, so `exchange` can report a
## refused earn instead of silently presenting an unearned one.
static func record_defeat(duel: Dictionary, entry: Dictionary, actor: Actor = null) -> Dictionary:
	duel["defeats"] = int(duel.get("defeats", 0)) + 1
	duel["last_defeat"] = entry.duplicate(true)
	if actor != null:
		DestinyApi.earn_fate(actor, FATE_FELL, EARN_SOURCE)
	return _remember(duel, entry)


## Record one duel won. The same entry shape as a defeat, on the other side of the same
## fight, so a screen can render both off one history rather than keeping two.
##
## ## DEF-0105: this is where a KILL pays a fate
##
## `CombatDuelHit._record_win` calls this on the one blow that ended a duel on a
## killing stroke, and `CombatDuel.spared` deliberately keeps a spared opponent out
## of it — so this is where `combat` owns "a duel was closed", and the earn belongs
## here for the same reason the loss's does: the owning module decides, `destiny`
## records (ADR 0065).
##
## VERIFIED the same way [method record_defeat] verifies its own, and for the same
## reason: `earn_fate` hands back the ledger rather than a verdict, and an unverified
## call on a typo'd or absent id is a silently lost reward.
static func record_win(duel: Dictionary, entry: Dictionary, actor: Actor = null) -> Dictionary:
	duel["wins"] = int(duel.get("wins", 0)) + 1
	var earned := true
	if actor != null:
		DestinyApi.earn_fate(actor, FATE_FIRST_BLOOD, EARN_SOURCE)
		earned = DestinyApi.has_fate(actor, FATE_FIRST_BLOOD)
	if not earned:
		push_warning(
			(
				(
					"combat: a duel was recorded as won but %s was not earned (id unknown to the "
					+ "fate catalog?). The ledger and the fate are separate writes, so nothing here "
					+ "records the debt."
				)
				% String(FATE_FIRST_BLOOD)
			)
		)
	return _remember(duel, entry)


## Mark this actor SPARED by `entry["winner_id"]`, which is the state a later blow is
## refused against. Idempotent by refusal rather than by a guard: the caller asks
## `spared_by` first, so a second mercy is a refusal with a reason and not a second copy
## of the same row.
static func record_spare(duel: Dictionary, entry: Dictionary) -> Dictionary:
	duel["last_spare"] = entry.duplicate(true)
	duel["spared_by"] = String(entry.get("winner_id", ""))
	return _remember(duel, entry)


## Whether this actor's last duel was ended in mercy. The one read of the state, so a
## refusal in `CombatDuelHit` and a row in `view()` cannot disagree about it.
static func spared(duel: Dictionary) -> bool:
	return String(duel.get("spared_by", "")) != ""


## Primitives only, so a panel can render it without naming this class.
static func view(duel: Dictionary) -> Dictionary:
	return {
		"defeats": int(duel.get("defeats", 0)),
		"wins": int(duel.get("wins", 0)),
		"last_defeat": (duel.get("last_defeat", {}) as Dictionary).duplicate(true),
		"last_spare": (duel.get("last_spare", {}) as Dictionary).duplicate(true),
		"spared_by": String(duel.get("spared_by", "")),
		"spared": spared(duel),
		"history": (duel.get("history", []) as Array).duplicate(true),
	}


## Append one entry to the bounded ring. Shared by all three writers above, because a
## second copy of `slice(-HISTORY_LIMIT)` is a second place the ring could stop being
## bounded.
static func _remember(duel: Dictionary, entry: Dictionary) -> Dictionary:
	var history: Array = duel.get("history", [])
	history.append(entry.duplicate(true))
	duel["history"] = history.slice(-HISTORY_LIMIT)
	duel["version"] = SCHEMA_VERSION
	return duel
