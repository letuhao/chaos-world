class_name PursuitLedger
extends RefCounted

## **An NPC's own disposition toward the player, held on the NPC's ledger** (ADR 0256).
##
## ## Why this file exists at all
##
## ADR 0091 records as an accepted cost that `SocialApi.apply_cause` writes **one
## direction only**: "how a merchant regards you is not the same fact as how you regard the
## merchant, and the module that owns the interaction is the one that knows whether the
## other party felt it." Before this file, the **only** path in the whole game where an
## NPC held a bond toward the player was `BrotherhoodOath` writing `accepted_the_oath` to
## the npc's own ledger (`social_brotherhood.gd:53,232`) — one hardcoded act for one verb.
## A general NPC→player direction did not exist.
##
## ## And it is NOT a second SocialState
##
## **The `SocialState` bond is already symmetric by TYPE and is the right home for
## *regard*.** `SocialApi.bond_entry(npc, player_id)` already answers "how does this npc
## regard the player", and the brotherhood mirror already writes to it. What did not
## exist is everything that is **not** regard:
##
##  - an impression that happened once (`SocialAttractionSeed`),
##  - a willingness to make a claim, which is a function of regard **and** opportunity,
##  - a *claim* — which is a world fact, not an opinion held by either party.
##
## Putting a second copy of standing here would be the ADR 0066 failure with a new name.
## So this ledger holds **no standing, no trust and no class**, and `PursuitStance` reads
## the regard axis from `SocialApi` and this ledger for the rest.
##
## ## What this ledger holds, in full
##
## `{seeds, dispositions, claims}` — three maps, all keyed by the **player's actor id**,
## all riding the NPC's own `module_data`. Nothing here is read by the player's ledger
## and nothing here is authored by the player.

## The `actor.module_data` key. Rides the actor's OWN payload for the ADR 0027 reason
## `SocialState` does — `Actor.to_dict` round-trips `module_data`, so no core schema bump
## is owed and an npc needs no bespoke save slot.
const MODULE_KEY := &"pursuit_ledger"

## ## The budget on how many rows one ledger may hold.
##
## **Named, not inferred.** This program has crashed a 95 GB machine twice and a pursuit
## path that scans all NPCs is exactly the shape that would do it again. An npc's ledger
## is keyed by the players who have met them; a single npc met by 40 000 distinct players
## must not grow a dictionary without limit. The cap is generous for one npc (a save with
## 10 000 tracked NPCs would need 400 M rows to hit it) and is enforced on write.
const SEED_LIMIT := 8
const DISPOSITION_LIMIT := 8
const CLAIM_LIMIT := 4

## Printed when a ledger is already at its cap. **Refusal, not eviction** — evicting an
## old impression to make room for a new one would let a player erase history by flooding,
## which is a farm of a different kind.
const AT_LIMIT := &"at_limit"

var seeds: Dictionary = {}
var dispositions: Dictionary = {}
var claims: Dictionary = {}


func _init() -> void:
	pass


## ## The live ledger for `actor`, restored from `module_data` on first read.
##
## Exactly `BrotherhoodOath.consent`'s pattern (`social_brotherhood.gd:414`): a
## component holds the live object so the bond ledger and this one cannot disagree, and
## the component is created lazily so an actor who has met nobody pays nothing.
static func for_actor(actor: Actor) -> PursuitLedger:
	if actor == null:
		return null
	var ledger := actor.component(MODULE_KEY) as PursuitLedger
	if ledger != null:
		return ledger
	ledger = from_dict(actor.get_module_data(MODULE_KEY))
	actor.set_component(MODULE_KEY, ledger)
	return ledger


## ## Fold the ledger into `module_data`, so `Actor.to_dict` alone is a complete save.
##
## Called on EVERY mutating verb, for the same reason `SocialApi._persist` is: a caller
## that seeded an impression and then serialised should not have to know a second verb
## exists to flush.
func persist(actor: Actor) -> void:
	if actor == null:
		return
	actor.set_module_data(MODULE_KEY, to_dict())


## ## The one seed this actor holds of `player_id`, or `{}`.
func seed_for(player_id: StringName) -> Dictionary:
	return seeds.get(String(player_id), {})


## ## Record the seed row. Refused at the cap rather than evicting.
func set_seed(player_id: StringName, row: Dictionary) -> Dictionary:
	if not seeds.has(String(player_id)) and seeds.size() >= SEED_LIMIT:
		return {"ok": false, "reason": String(AT_LIMIT)}
	seeds[String(player_id)] = row.duplicate(true)
	return {"ok": true, "reason": ""}


## ## The disposition row for `player_id`, or `{}`.
func disposition_for(player_id: StringName) -> Dictionary:
	return dispositions.get(String(player_id), {})


## ## Record the disposition row. Refused at the cap.
func set_disposition(player_id: StringName, row: Dictionary) -> Dictionary:
	if not dispositions.has(String(player_id)) and dispositions.size() >= DISPOSITION_LIMIT:
		return {"ok": false, "reason": String(AT_LIMIT)}
	dispositions[String(player_id)] = row.duplicate(true)
	return {"ok": true, "reason": ""}


## ## The claim this actor holds against `player_id`, or `{}`.
##
## ## One claim per row — that is the exclusivity rule
##
## **A single dictionary keyed by the player makes exclusivity structural rather than
## checked.** An npc holds at most one claim against one player because there is one slot
## per player id and a second claim overwrites it. Exclusivity decided by a threshold that
## could drift is a rule that eventually is not a rule; this one cannot be two at once by
## construction, which is the shape `BrotherhoodOath`'s `ledger.answered()` precedent chose.
func claim_for(player_id: StringName) -> Dictionary:
	return claims.get(String(player_id), {})


func set_claim(player_id: StringName, row: Dictionary) -> Dictionary:
	if not claims.has(String(player_id)) and claims.size() >= CLAIM_LIMIT:
		return {"ok": false, "reason": String(AT_LIMIT)}
	claims[String(player_id)] = row.duplicate(true)
	return {"ok": true, "reason": ""}


## ## Forget everything this actor holds about `player_id`.
##
## **What a retired NPC calls, and the whole reason a transient's pursuit is free.** A
## minor npc who is gone has nothing left to remember, so retiring them drops the rows
## rather than leaving them in a save forever. `SocialApi.forget` drops the regard bond
## the same way; this drops the seed, the disposition and the claim.
func forget(player_id: StringName) -> bool:
	var removed := seeds.erase(String(player_id))
	removed = dispositions.erase(String(player_id)) or removed
	removed = claims.erase(String(player_id)) or removed
	return removed


func seed_count() -> int:
	return seeds.size()


func disposition_count() -> int:
	return dispositions.size()


func claim_count() -> int:
	return claims.size()


func to_dict() -> Dictionary:
	return {
		"version": 1,
		"seeds": seeds.duplicate(true),
		"dispositions": dispositions.duplicate(true),
		"claims": claims.duplicate(true),
	}


static func from_dict(data: Dictionary) -> PursuitLedger:
	var ledger := PursuitLedger.new()
	for key in data.get("seeds", {}).keys():
		ledger.seeds[String(key)] = data["seeds"][key]
	for key in data.get("dispositions", {}).keys():
		ledger.dispositions[String(key)] = data["dispositions"][key]
	for key in data.get("claims", {}).keys():
		ledger.claims[String(key)] = data["claims"][key]
	return ledger


## The empty payload, so a caller with no actor gets the same shape rather than `{}`.
static func empty() -> Dictionary:
	return {"version": 1, "seeds": {}, "dispositions": {}, "claims": {}}
