class_name DomainFight
extends RefCounted

## THE CHAIN, END TO END: a player presses once in a domain, a placed inhabitant dies,
## and the run changes (ADR 0228, 0229, 0235, 0236).
##
## ## Why this is a file and not three methods on `DomainBoot`
##
## `DomainBoot` is already past the thousand-line ceiling and past its own stated reason to
## change, and the concern here is separable from both the world and the spawn seam: this
## is a CONTEST over a body a map placed, and nothing else in `app/` is about contests.
## So the chain is one file with one job, called from one place.
##
## ## Who owns what, stated so nothing is built twice
##
## | Stage | Owner | Where |
## |---|---|---|
## | intent | `domain` read model | `DomainApi.summary()["run"]` / `["population"]` |
## | action | THIS FILE | [method engage] |
## | cost | `FightLoop`'s rate gate | `fight_loop.gd:526-532` |
## | effect | `CombatBoot.resolve_hit` | `combat_boot.gd:777` |
## | outcome | `FightLoop._decide` | `fight_loop.gd:683-708` |
## | consequence | `DomainRun.record_kill` | `domain_run.gd` |
##
## **There is no second damage path here.** Every blow is `FightLoop.exchange`, which is
## `CombatBoot.resolve_hit` on both sides, which is `CombatSpine`. This file names no
## number a blow is worth; it decides WHO is fought and WHAT the verdict writes.
##
## ## And the zero crossing is the only seam anything else may listen to
##
## [method _on_zero_crossing] is the one registered callable in the game that fires on an
## actor's health crossing zero. It is registered HERE, in `app/`, which is the only layer
## permitted to hold it (ADR 0236). It is fired by the TRANSITION and not by a poll, so a
## death is once-per-death by construction and a subsequent `pool.change(-0.0)` a status
## tick makes cannot fire it again.

## Nobody, or nobody to fight.
const R_NO_HERO := "no_hero"
## The named inhabitant is not in this run's roster.
const R_NO_TARGET := "no_target"
## A `FightLoop` already holds a decided verdict; the fight is closed and a second press
## would be a blow at a corpse.
const R_FIGHT_CLOSED := "fight_closed"
## The band the kill would open a door in has already been abandoned.
const R_RUN_ABANDONED := "run_abandoned"
## The caller named a boss id this run's band does not have.
const R_NOT_A_BOSS := "not_a_boss"

## The one callable that hears a death, and the set of instance ids already paid out.
## `sealed` is a set of `instance id -> true` rather than a health read, and that is the
## whole point: a second rule about when a fight ends is exactly the defect
## `FightLoop._decide`'s docblock names, and a poller would be a second rule.
static var _listener: Callable = Callable()
static var _sealed: Dictionary = {}


## Open a fight against one placed inhabitant and report what it started from.
##
## The ONLY way a domain fight opens, and it is deliberately not `FightLoop.start_fight`:
## that mints its own generic opponent (`fight_loop.gd:206-222`), so a run driven through
## it is fighting a training dummy with no domain behind it. `begin_fight` names the body
## the map actually placed, which is what makes the kill mean something.
static func engage(hero: Actor, opponent: Actor) -> Dictionary:
	if hero == null or opponent == null:
		return {"ok": false, "reason": R_NO_HERO, "fight": {}}
	var fight := FightLoop.new(hero, opponent)
	return _answered(fight.begin_fight(opponent), fight)


## The fight as `FightLoop.summary()` publishes it, or `{}`. The one read a screen, a
## probe and a test all share, so a report can never describe a different fight than the
## one on screen.
static func summary(fight: FightLoop) -> Dictionary:
	if fight == null:
		return {}
	return fight.summary()


## Age `fight` by `delta` and report whether the hero's next blow is available.
##
## **The rate gate is a gate on the PRESS, never a background timer** (ADR 0228). Elapsed
## time arrives as an argument from whoever owns the clock, so nothing here advances a
## fight behind the player's back — and the seconds still owed are published, which is
## what lets a headless probe drive a whole fight with a verb list.
static func age(fight: FightLoop, delta: float) -> Dictionary:
	if fight == null:
		return {"ok": false, "reason": "no_fight"}
	return fight.age(delta)


## ONE press, through the root-owned `FightLoop`, and the verdict it answers with.
##
## `seed_value` of `0` means "nothing random happens and every strike lands" (ADR 0087's
## S12), which is the honest default for a live page: a whiff and a gut-punch are
## different events and a fight whose ledger depends on an unchosen generator cannot be
## asserted on. A probe passes the seed it wants.
static func press(fight: FightLoop, seed_value: int = 0) -> Dictionary:
	if fight == null:
		return {"ok": false, "reason": "no_fight"}
	return fight.exchange(seed_value)


## THE CONSEQUENCE. A decided verdict writes a run — and only a decided verdict may.
##
## ## The whole of ADR 0236's stage chain, in one function
##
## `intent → action → cost → effect → outcome`, and this is `outcome`: `_decide` has
## already closed the fight and named `hero_won` / `hero_lost`, and the ONLY thing this
## does with that word is write the run. A caller that re-derived the verdict would have
## two rules about when a fight ends, and they would drift on a corpse-with-health-left
## (`fight_loop.gd:371-375` names this as the defect).
##
## `hero_lost` abandons the band. `hero_won` records the kill **only when the body that
## fell is a door this run has** — a placed hostile that is not in the band advances
## nothing, because progress in this game is BAND progress and not body count (ADR 0229).
##
## ## `decided_by` is published, never re-derived
##
## ADR 0236's second word. `""` is the honest answer for a body fight, whose only pool is
## health; `sea` and `rupture` are the mind path's pools and a body fight must not
## fabricate them. A caller branches on `outcome` and reads `decided_by` to know why the
## fight stopped — never a number.
static func record_verdict(hero: Actor, fight: FightLoop) -> Dictionary:
	if hero == null or fight == null:
		return {"ok": false, "reason": "no_fight"}
	var report := fight.summary()
	var outcome := String(report.get("outcome", ""))
	if outcome == "":
		return {"ok": false, "reason": "undecided", "outcome": outcome}
	if outcome == FightLoop.OUTCOME_HERO_LOST:
		var abandoned := DomainRunApi.abandon_band(hero)
		return {
			"ok": true,
			"outcome": outcome,
			"decided_by": "health",
			"opponent_id": String(report.get("opponent_id", "")),
			"killer_id": "",
			"band": abandoned,
			"gate_open": false,
		}
	var boss_id := _door_of(hero, report.get("opponent_id", ""))
	if boss_id == "":
		# A placed hostile that is not in the band. The map changes and nothing else does,
		# which ADR 0229 calls the honest small reward.
		return {
			"ok": true,
			"outcome": outcome,
			"decided_by": "health",
			"opponent_id": String(report.get("opponent_id", "")),
			"killer_id": String(hero.id),
			"band": {"ok": false, "reason": R_NOT_A_BOSS},
			"gate_open": false,
		}
	var killed := DomainRunApi.record_kill(hero, boss_id, String(hero.id))
	return {
		"ok": bool(killed["ok"]),
		"reason": String(killed["reason"]),
		"outcome": outcome,
		"decided_by": "health",
		"opponent_id": String(report.get("opponent_id", "")),
		"killer_id": String(hero.id),
		"boss_id": boss_id,
		"cleared": bool(killed.get("cleared", false)),
		"open_boss": String(killed.get("open_boss", "")),
		"remaining": int(killed.get("remaining", 0)),
		"band": killed,
		"gate_open": bool(killed.get("gate_open", false)),
	}


## ## One press and its whole consequence, in one call.
##
## This is the verb a test, a probe and a screen's button all use, and it exists so none of
## them has to remember the order. `age` is the RATE GATE and defaults to
## `FightLoop.BASE_BLOW_INTERVAL`: a press made before the gate has recharged is refused by
## name with `blows_remaining` published, so a caller that drives a whole fight with a verb
## list is told which lever to turn rather than silently landing half its blows.
##
## **The result carries BOTH the blow and the consequence.** A caller branches on
## `outcome` for the fight and on `gate_open` for the run; it never has to reach past this
## verb to find out whether anything changed.
static func strike(
	hero: Actor, fight: FightLoop, delta: float = -1.0, seed_value: int = 0
) -> Dictionary:
	if hero == null or fight == null:
		return {"ok": false, "reason": R_NO_HERO, "outcome": "", "fight": {}}
	var gate := age(fight, delta if delta >= 0.0 else FightLoop.BASE_BLOW_INTERVAL)
	if not bool(gate.get("ok", false)):
		return {
			"ok": false,
			"reason": String(gate.get("reason", "")),
			"outcome": "",
			"fight": summary(fight),
		}
	var blow := press(fight, seed_value)
	if not bool(blow.get("ok", false)):
		blow["consequence"] = {"ok": false, "reason": String(blow.get("reason", ""))}
		return blow
	var consequence := record_verdict(hero, fight)
	blow["consequence"] = consequence
	blow["gate_open"] = bool(consequence.get("gate_open", false))
	blow["remaining"] = int(consequence.get("remaining", 0))
	return blow


## ## The zero crossing, and the ONLY thing this game fires a death on (ADR 0236)
##
## `Callable((actor, decided_by, killer_id) -> void)`, fired once per death from `app/`:
##
## 1. **on the TRANSITION**, not per `change()` — a health pool already at zero and
##    changed again by a status tick is not a second death;
## 2. **on a `sea` / `rupture` death too**, so a mind fight is not a silent forfeit;
## 3. **never for `spared`** — a spared opponent is on their feet (`duel.gd:174-199`), so
##    forfeiture must not read it as a loss;
## 4. **with the crossing as the payload**, not the state, so a listener cannot double-fire.
##
## Register the one callable that hears a death, and report the install. An empty Callable
## clears the binding, so an uninstall is a decision rather than an overwrite.
static func set_death_listener(listener: Callable) -> Dictionary:
	_listener = listener
	return {"ok": _listener.is_valid(), "reason": "" if _listener.is_valid() else "no_listener"}


## Whether a death listener is installed, so a caller can say "nobody is listening" and
## "the listener refused" as two different messages rather than one empty descriptor.
static func has_death_listener() -> bool:
	return _listener.is_valid()


## Fire the listener for a body that just crossed zero, and report whether it fired.
##
## Called by the layer that SPENT the pool — `app/`, which is the only layer allowed to
## depend on anything (ADR 0236). The `sealed` map is what makes this once-per-death by
## construction: a body is sealed when it dies and unsealed only by [method forget], which
## is the rebirth path.
##
## A `spared` verdict is refused BY NAME rather than silently skipped, because "nothing
## fired and nobody can tell why" is the dead surface this whole seam was opened to close.
static func cross_zero(
	actor: Actor, decided_by: String = "health", killer_id: String = ""
) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "no_actor", "fired": false}
	if String(decided_by) == "spared":
		return {"ok": false, "reason": "spared", "fired": false}
	if not _listener.is_valid():
		return {"ok": false, "reason": "no_listener", "fired": false}
	var key := actor.get_instance_id()
	if _sealed.has(key):
		return {"ok": true, "reason": "already_sealed", "fired": false}
	_sealed[key] = true
	_listener.call(actor, String(decided_by), String(killer_id))
	return {"ok": true, "reason": "", "fired": true}


## Whether `actor` has already had its death fired. A read, so a test can assert the seam
## fired ONCE without reaching into the listener and counting its calls.
static func is_sealed(actor: Actor) -> bool:
	return actor != null and _sealed.has(actor.get_instance_id())


## Unseal a body. The rebirth path: a soul arrives on a NEW body, and a body that has
## already had its death fired must not carry that over to the next one.
static func forget(actor: Actor) -> void:
	if actor != null:
		_sealed.erase(actor.get_instance_id())


# ── internals ────────────────────────────────────────────────────────────────


## The band entry a fallen body belongs to, or `""` when it belongs to none.
##
## ## Resolved through the RUN, not through a role tag
##
## The band's bosses are room-scoped (`DomainApi._open_band` names them
## `<domain>/<room_id>`), so the id a kill must carry is the ROOM the body stands in, read
## through the spawner's own placement record. That is what keeps ADR 0229's "the authored
## boss list is the thing a player can act on" and ADR 0074's "a role is a tag, never a
## branch" both true at once: the tag says what a creature IS, the band says which fight
## it belongs to, and neither has to ask the other about damage.
##
## Bounded by `DomainApi.summary(hero)["run"]`'s own `bosses` array — at most
## `DomainRun.MAX_BAND_SIZE` entries — so there is no walk whose bound is derived from
## anything this file grows.
static func _door_of(hero: Actor, opponent_id: Variant) -> String:
	var placed := _placed_boss(hero, opponent_id)
	if placed == "":
		return ""
	var band := DomainRunApi.band(hero)
	var bosses: Array = band.get("bosses", [])
	for entry in bosses:
		if String(entry) == placed:
			return placed
	return ""


## The band-scoped id of the placed body `opponent_id` stands for, or `""`.
##
## ## Why an id is a QUESTION and not a reference
##
## `spawn_inhabitant` hands `def.inhabitant_id` to `Actor.new` unchanged, so every
## `cinder_hound` in a run shares one id, a `count: 2` room holds two bodies under one
## name, and the shipped `stormwrack_reach` mints **four** `flame_dragon` — one per door —
## all under one id. There is also no `Actor` on hand here: the verdict is a dictionary of
## primitives, so `opponent_id` is the only handle it carries, and the roster is the only
## place a placed body's room and role both live (`DomainSpawner.MODULE_KEY`).
##
## ## Why the ROOM is the half that disambiguates a name the spawner shares
##
## A door id is `<domain_id>/<room_id>` (`DomainApi._open_band` mints it, `_door_id`
## re-derives it), so a body's ROOM is half the id it is being asked for. Requiring
## "exactly one body on the whole roster may carry this id" — which is what this did —
## therefore refused **every one of the shipped content's own door bodies**: a template
## that authors the same species in several rooms is ordinary authored content, and
## matching on the name alone measures a property of the CONTENT rather than of the kill.
##
## Measured on `stormwrack_reach`: the roster holds four `flame_dragon`, one in each of
## `ash_heart#10`, `#17`, `#23` and `#3`, and a hero who killed the one standing in
## `ash_heart#10` resolved to `""` and took `record_verdict`'s `not_a_boss` branch — the
## band stayed at `kill_count 0` while the door that body stood in was exactly the door the
## hero had cleared. Nothing about that answer was true and everything about it was safe.
##
## So the question is asked of the DOOR: exactly one rostered body may stand in the room
## this band's ledger currently has OPEN, carry this name, and be that door's occupant —
## which is the sentence that was WRITTEN here and never IMPLEMENTED: the code counted
## every door body under the name and then demanded exactly one, so on the shipped
## `stormwrack_reach` it counted four and refused all four (measured: `_door_of` answered
## `""` on every strike, `band.kill_count` stayed `0`, and the door the hero had just
## cleared was refused as `not_a_boss`). The OPEN door is the disambiguator, because a band
## is a queue — [method _open_door_room] names it and `DomainRun.record_kill` refuses
## anything else as `door_closed`, so the filter can only remove bodies the module would
## have refused anyway.
##
## A door claimed by two bodies under one name, or by a name no door body carries, still
## resolves to `""` — crediting a kill to a living antagonist is worse than recording none,
## so ambiguity is still REFUSED rather than guessed, and the caller still takes the
## `not_a_boss` branch it already has (ADR 0229's honest answer for a body this band does
## not own).
##
## ## And a door's occupant is not always a `boss`-tagged body
##
## The shipped `tide_vault#14` authors a `miniboss` as the occupant of a
## `roster_band: boss` room, and ADR 0229's door is the ROOM rather than the role — so a
## hostile standing in a door is a door's body, which is what a screen resolving
## `summary()["population"]` already had to decide.
##
## Bounded by the roster's own contents — one `Actor` per authored spawn ref, which
## `DomainSpawner.MAX_COUNT_PER_REF` caps at 64 per ref — so no walk here grows a bound
## this file invents.
static func _placed_boss(hero: Actor, opponent_id: Variant) -> String:
	var wanted := String(opponent_id)
	if wanted == "":
		return ""
	var open_room := _open_door_room(hero)
	var found: Actor = null
	var matched := 0
	for inhabitant in DomainBoot.placed_inhabitants():
		var actor := inhabitant as Actor
		if actor == null or String(actor.id) != wanted:
			continue
		if not _occupies_a_door(hero, actor):
			continue
		if not DomainSpawner.has_role(actor, DomainRoles.BOSS):
			if not DomainSpawner.is_hostile(actor):
				continue
		# **The OPEN door is the half that disambiguates a name the spawner shares.**
		# Four `flame_dragon` stand in four `ash_heart#n` doors, so the species id alone
		# names four bodies and refusing them all refused every door the shipped content
		# authors (measured: `_door_of` answered `""` for a hero who had just cleared the
		# door that body stood in). A band is a queue — exactly one door is open at a time
		# (`DomainRun.open_boss`), and only a kill of THAT door can be credited, so the
		# open door's room is the one fact the id cannot supply. Bodies in any other door
		# are still counted so a door this band has already opened cannot absorb a second
		# kill; a second body in the OPEN door is still REFUSED rather than guessed, because
		# crediting a kill to a living antagonist is worse than recording none.
		if open_room != "" and String(DomainSpawner.room_of(actor)) != open_room:
			continue
		matched += 1
		found = actor
	if matched != 1 or found == null:
		return ""
	return _door_id(hero, found)


## The ROOM half of the one door this band's ledger currently has open, or `""`.
##
## ## Why the ledger, and not a re-derivation
##
## `DomainRun.open_boss` is the stored index, not a scan for "the first undefeated"
## (`domain_run.gd:166-174`): the door is a STATE and re-deriving it would eventually
## disagree with the kill ledger that is the only thing allowed to move it. So this reads
## the same word the band publishes and never a second rule about which door is next.
##
## `""` outside a run, for an abandoned band, and once the band is cleared — every one of
## which the module already answers through the same verb, so this cannot invent an answer.
static func _open_door_room(hero: Actor) -> String:
	var band := DomainRunApi.band(hero)
	var open_door := String(band.get("open_boss", ""))
	var slash := open_door.rfind("/")
	if slash < 0:
		return ""
	return open_door.substr(slash + 1)


## Whether `actor` stands in a room `hero`'s band has a door on — the ROOM half of a door
## id, matched on its own suffix rather than on a re-derived half.
##
## ## Why a SUFFIX, and why it cannot collide
##
## `_door_id` mints `"<domain_id>/<room_id>"` and a room id carries its own `#n`
## (`ash_heart#10`), so `ends_with("/" + room)` matches exactly the entries of THIS run's
## band whose room is this body's room. A different domain's door cannot share the room
## half unless it shares the room id, and the band being scanned is this hero's own, so
## there is at most one such entry per room. That is what makes `matched` below a count of
## BODIES claiming one door rather than a count of doors.
##
## Bounded by the band's own `bosses` array, which `DomainRun.MAX_BAND_SIZE` caps, so no
## walk here grows a bound this file invents.
static func _occupies_a_door(hero: Actor, actor: Actor) -> bool:
	var band := DomainRunApi.band(hero)
	var suffix := "/%s" % String(DomainSpawner.room_of(actor))
	for entry in band.get("bosses", []):
		if String(entry).ends_with(suffix):
			return true
	return false


## The `<domain>/<room_id>` a boss body stands in, in the same spelling
## `DomainApi._open_band` mints. Built from the run's OWN domain id rather than restated,
## so the two cannot disagree about what a door is called.
static func _door_id(hero: Actor, actor: Actor) -> String:
	var band := DomainRunApi.band(hero)
	var domain_id := String(band.get("domain_id", ""))
	if domain_id == "":
		var state: Variant = hero.get_module_data(DomainApi.MODULE_KEY)
		if state is Dictionary:
			domain_id = String((state as Dictionary).get("domain_id", ""))
	if domain_id == "":
		return ""
	return "%s/%s" % [domain_id, String(DomainSpawner.room_of(actor))]


## One shape for [method engage]'s answer, so a caller reads `fight` rather than
## branching on which of the two it got.
static func _answered(began: Dictionary, fight: FightLoop) -> Dictionary:
	return {
		"ok": bool(began.get("ok", false)),
		"reason": String(began.get("reason", "")),
		"fight": summary(fight),
	}
