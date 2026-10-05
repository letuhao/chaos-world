class_name DomainRun
extends RefCounted

## A domain run is a BAND OF BOSSES with an exit gate, and a kill is the only thing that
## opens the next door (ADR 0229).
##
## ## What this owns, and why it is not `domain`'s existing run state
##
## `DomainApi` owns WHERE you are: the map, the rooms, the discovered set, the fixtures.
## That state is a place. This is the FIGHT in it, and it is separate because the two have
## different lifecycles and different failure modes: a player may walk out of a room and
## come back, but a fight either ends or it does not, and a run that could be half-resumed
## halfway through a boss would be two rules about when a boss is done.
##
## ## The whole model, in five facts
##
## 1. The band is a LIST of authored bosses. Every entry is still standing until it is
##    killed. The list is the progress; there is no counter, because "7 of 9 things" is a
##    quantity a player cannot act on (ADR 0229's own rejection).
## 2. `open` is the index of the first boss still standing. **A kill is the only thing
##    that moves it** — [method record_kill] is the one writer, and nothing else opens a
##    door. There is no "skip", no "clear", no ambient sweep.
## 3. A killed body is recorded with WHO killed it and WHEN in the run's own order, so a
##    listener can answer "which blow ended this" without re-deriving the fight.
## 4. The EXIT is claimable the moment the band is clear, and refused before that — and
##    refusing it costs nothing, because a player who cannot retreat cannot make a
##    commitment, and commitment is what the anchor measures (ADR 0229).
## 5. A defeat abandons the run. The whole band goes, the kills go with it, and nothing
##    is owed — the loss is the stake (ADR 0236).
##
## ## Why the ledger is a Dictionary of Primitives
##
## It lives on `actor.module_data`, so it round-trips through `Actor.to_dict()` /
## `from_dict()` with no bespoke save path (ADR 0027), exactly as `DomainApi`'s own run
## state does. Every value is an int, a float or a String, so a hand-edited save degrades
## through [method normalize] instead of failing the load.
##
## ## Every refusal is NAMED
##
## A press that quietly does nothing is the shape a player cannot act on (ADR 0150), so
## every gate here answers with a distinct reason rather than a bare false.

## This run's state key in `actor.module_data` (ADR 0027). Separate from `DomainApi`'s own
## `MODULE_KEY`: a run and a place are different records, and folding one into the other
## would make "left the domain" a rewrite of the fight ledger.
const MODULE_KEY := &"domain_band"

const STATE_VERSION := 1

## How many fights a single band may hold. A BAND is authored data, so a hand-edited count
## of ten thousand is a defect that must fail out loud rather than minting ten thousand
## doors; one step over is refused by name.
const MAX_BAND_SIZE := 16

## The default number of bosses in a band that authors none. Two, because a band of one is
## a duel and a duel is ADR 0076's boss fight wearing a map — the thing this model exists
## to be different from. Two makes "the next door" a thing that has to be opened.
const DEFAULT_BAND_SIZE := 2

## Nobody to run.
const R_NO_ACTOR := "no_actor"
## No band is in flight, so there is no door and no exit.
const R_NO_RUN := "no_run"
## The caller named a band and this run does not have one.
const R_BAND_EMPTY := "band_empty"
## A band longer than [constant MAX_BAND_SIZE] is refused rather than truncated.
const R_BAND_TOO_LARGE := "band_too_large"
## The named boss is not in this band.
const R_UNKNOWN_BOSS := "unknown_boss"
## The named boss is already down. Refused, not repeated: a kill ledger is monotone.
const R_ALREADY_DEAD := "already_dead"
## A run with no band at all cannot be won.
const R_NOTHING_TO_CLEAR := "nothing_to_clear"


## A fresh, empty ledger. Every reader starts here, so a missing key and an empty run are
## the same answer rather than a special case three call sites each have to handle.
static func blank() -> Dictionary:
	return {
		"version": STATE_VERSION,
		"domain_id": "",
		"bosses": [],
		"kills": {},
		"open_index": 0,
		"cleared": false,
		"abandoned": false,
		"gate": "closed",
	}


## A usable ledger from anything `module_data` may hold. A payload written before a field
## existed loads with that field empty rather than failing, and the version is stamped on
## the way out — the same normalize-everything rule `CombatDuel` and `LootState` use.
static func normalize(raw: Dictionary) -> Dictionary:
	var run := blank()
	if raw.is_empty():
		return run
	run["domain_id"] = String(raw.get("domain_id", ""))
	if raw.get("bosses") is Array:
		run["bosses"] = (raw["bosses"] as Array).duplicate(true)
	if raw.get("kills") is Dictionary:
		run["kills"] = (raw["kills"] as Dictionary).duplicate(true)
	run["open_index"] = maxi(0, int(raw.get("open_index", 0)))
	run["cleared"] = bool(raw.get("cleared", false))
	run["abandoned"] = bool(raw.get("abandoned", false))
	run["gate"] = String(raw.get("gate", "closed"))
	run["version"] = STATE_VERSION
	return run


## Open a band for `domain_id` over the `boss_ids` a map author listed.
##
## `boss_ids` are ORDERED by the caller, never sorted here: the authored order IS the
## run's order, and a sorted list would make every band the same band. An empty list
## becomes [constant DEFAULT_BAND_SIZE] bosses derived from the domain id, so a map that
## authors no boss still opens a real band rather than an exit with nothing behind it.
##
## Refuses rather than truncates on an oversized band: a run whose authored list does not
## fit is an authoring error, and quietly dropping the tail would make the last boss in
## every oversized domain unreachable without saying so.
static func begin(domain_id: String, boss_ids: Array) -> Dictionary:
	var run := blank()
	run["domain_id"] = domain_id
	var ids: Array = []
	for entry in boss_ids:
		ids.append(String(entry))
	if ids.is_empty():
		for index in range(DEFAULT_BAND_SIZE):
			ids.append("%s#%d" % [domain_id, index])
	run["bosses"] = ids
	run["open_index"] = 0
	return run


## Validate a ledger WITHOUT writing it, so `DomainApi.begin_band` can refuse a band
## before `DomainApi.enter` has stored one. Returns `{}` when the band is playable, and
## `{ok: false, reason: ...}` when it is not.
static func validate(run: Dictionary) -> Dictionary:
	if run.is_empty():
		return {"ok": false, "reason": R_BAND_EMPTY}
	var bosses: Array = run.get("bosses", [])
	if bosses.is_empty():
		return {"ok": false, "reason": R_BAND_EMPTY}
	if bosses.size() > MAX_BAND_SIZE:
		return {"ok": false, "reason": R_BAND_TOO_LARGE, "bosses": bosses.size()}
	return {"ok": true, "reason": ""}


## The bosses still standing, in band order, as `String`s. The read a screen renders
## under "what is left", and the reason ADR 0229 calls the smallest possible fix to
## invisible progress: it is a READ, and reading changes nothing.
static func remaining(run: Dictionary) -> Array:
	var out: Array = []
	var kills: Dictionary = run.get("kills", {})
	var bosses: Array = run.get("bosses", [])
	for boss_id in bosses:
		if not kills.has(String(boss_id)):
			out.append(String(boss_id))
	return out


## The boss whose door is open, or `""` when the band is clear. NOT a look-up of "the
## first undefeated" on every call: the door is a stored index, because the door is a
## STATE and a state cannot be re-derived without eventually disagreeing with the kill
## ledger that is supposed to be the only thing that moves it.
static func open_boss(run: Dictionary) -> String:
	if bool(run.get("cleared", false)) or bool(run.get("abandoned", false)):
		return ""
	var bosses: Array = run.get("bosses", [])
	var index := int(run.get("open_index", 0))
	if index < 0 or index >= bosses.size():
		return ""
	return String(bosses[index])


## Record that `boss_id` fell, and open the next door.
##
## **This is the only writer of `open_index`**, which is what makes "a kill is the only
## thing that opens the next door" a structural claim rather than a convention: there is
## no second verb that could advance a run, so a module that wants a run to progress has
## to go through a kill.
##
## The door is opened by `open_index + 1` rather than by "the first undefeated", so a band
## whose entries are not in a walkable order still advances one door at a time — and a
## kill recorded out of order is REFUSED rather than teleporting the band forward, because
## a band that can be completed by killing the last boss first is not a band.
static func record_kill(run: Dictionary, boss_id: String, killer_id: String = "") -> Dictionary:
	var validate_answer := validate(run)
	if not bool(validate_answer["ok"]):
		return {
			"ok": false,
			"reason": String(validate_answer["reason"]),
			"run": run,
		}
	if bool(run.get("abandoned", false)):
		return {"ok": false, "reason": R_NO_RUN, "run": run}
	var bosses: Array = run.get("bosses", [])
	var position := bosses.find(boss_id)
	if position < 0:
		return {"ok": false, "reason": R_UNKNOWN_BOSS, "run": run}
	var kills: Dictionary = run.get("kills", {})
	if kills.has(boss_id):
		return {"ok": false, "reason": R_ALREADY_DEAD, "run": run}
	var open := int(run.get("open_index", 0))
	if position != open:
		# The one door, opened by the one thing. A kill out of order is refused BY NAME
		# rather than absorbed, so "I killed the wrong one" is a message a player can act
		# on and the band cannot be finished from the back.
		return {
			"ok": false,
			"reason": "door_closed",
			"run": run,
			"open_boss": open_boss(run),
		}
	kills[boss_id] = {"killer_id": killer_id, "order": kills.size()}
	run["kills"] = kills
	run["open_index"] = open + 1
	var cleared := int(run["open_index"]) >= bosses.size()
	run["cleared"] = cleared
	run["gate"] = "open" if cleared else "closed"
	return {
		"ok": true,
		"reason": "",
		"cleared": cleared,
		"open_boss": open_boss(run),
		"remaining": remaining(run).size(),
		"gate": String(run["gate"]),
		"run": run,
	}


## Whether the exit is claimable, and why not when it is not. `gate` is the word a screen
## branches on; `reason` is the word a log can be read by.
##
## `abandoned` answers `false` on purpose: a player who lost the band has already left,
## and "the exit is open" would read as "go back and try the fight you just lost".
static func exit_gate(run: Dictionary) -> Dictionary:
	if run.is_empty():
		return {"ok": false, "reason": R_NO_RUN, "gate": "closed"}
	if bool(run.get("abandoned", false)):
		return {"ok": false, "reason": "abandoned", "gate": "closed"}
	if not bool(run.get("cleared", false)):
		return {"ok": false, "reason": "band_not_cleared", "gate": "closed"}
	return {"ok": true, "reason": "", "gate": "open"}


## Close the run. The whole band goes and the kills go with it, and nothing is owed: the
## loss is the stake on the run rather than on the account (ADR 0236).
##
## Idempotent by RETURN rather than by refusal, because a caller that abandons twice
## (a defeat that also fires the combat-exit purge) must not be handed a failure for the
## second call — the state it wants is already the state it has.
static func abandon(run: Dictionary, reason_id: String = "defeated") -> Dictionary:
	if run.is_empty():
		return {"ok": false, "reason": R_NO_RUN, "run": run}
	run["abandoned"] = true
	run["cleared"] = false
	run["gate"] = "closed"
	run["open_index"] = 0
	run["kills"] = {}
	run["version"] = STATE_VERSION
	return {"ok": true, "reason": "", "abandoned": true, "cause": reason_id, "run": run}


## The whole run as primitives, so a screen or a headless probe renders it without
## naming this class. `{}` when there is no run, which is the repo's does-not-exist
## vocabulary: a missing run must not read like a run with nothing left in it.
static func view(run: Dictionary) -> Dictionary:
	if run.is_empty():
		return {}
	var bosses: Array = run.get("bosses", [])
	var kills: Dictionary = run.get("kills", {})
	var gate := exit_gate(run)
	return {
		"version": int(run.get("version", STATE_VERSION)),
		"domain_id": String(run.get("domain_id", "")),
		"bosses": bosses.duplicate(true),
		"band_size": bosses.size(),
		"kills": kills.duplicate(true),
		"kill_count": kills.size(),
		"remaining": remaining(run),
		"remaining_count": maxi(0, bosses.size() - kills.size()),
		"open_index": int(run.get("open_index", 0)),
		"open_boss": open_boss(run),
		"cleared": bool(run.get("cleared", false)),
		"abandoned": bool(run.get("abandoned", false)),
		"gate": String(gate["gate"]),
		"gate_open": bool(gate["ok"]),
		"gate_reason": String(gate["reason"]),
	}
