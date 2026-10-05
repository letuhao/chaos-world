class_name PursuitClaim
extends RefCounted

## **The claim, the answer, and what a refusal costs** (ADR 0256, closing the pursuit half
## of the brotherhood-oath precedent).
##
## ## This is `BrotherhoodOath` a second time, deliberately
##
## BL-0745 closed on one rule: **an offer with no refusal is a button.** That file owns
## the oath; this one owns courtship, and it obeys the same four rules rather than
## inventing a second pattern:
##
##  1. **A stranger cannot be claimed.** `may_be_courted` reads the NPC's OWN bond through
##     `SocialApi.gate` at `PursuitStance.COURT_AT`.
##  2. **The answer is read off the ledger, not rolled.** No RNG, so an answer is
##     reproducible from a save and a player cannot re-roll a refusal — which is the only
##     way an answer can be *consent* rather than a slot machine.
##  3. **Refusal is the DEFAULT for anyone who asks early**, reachable with no authored
##     content, and it is reached by the very act the ruling names.
##  4. **Refusal is charged to the player's own bond**, as an authored cause, and
##     `already_answered` makes the exchange one-shot.
##
## ## And it is NOT a gift-farming path
##
## This is the load-bearing anti-farm property and it is structural, not tuned. See
## `CAUSE_REFUSED` below for the whole argument; the short form is that the whole
## pursuit vocabulary is **`kind: court`**, one kind, so six courtship acts are six acts of
## one KIND and `SocialBondClass.FRIEND_DISTINCT_CAUSES` tops the bond at an
## ACQUAINTANCE however large the total. **Six oaths must not buy a relationship, and six
## claims must not either.**

## ## What the player presses, and what the NPC may answer with.
##
## Recorded on the NPC's ledger, like every other pursuit fact — a claim is something
## someone believes ABOUT you, so it belongs where their beliefs live.
const OUTCOME_ACCEPTED := &"accepted"
const OUTCOME_REFUSED := &"refused"

## ## What an acceptance charges the PLAYER's bond: an answered courtship is a fact
## between two people and the world can explain it (ADR 0091).
##
## **`promotes_to` is deliberately ABSENT.** The oath is the only shipped cause allowed to
## name a class, and courtship does not get to be a second one — it is a different bond
## from brotherhood and must not reach the top of the ladder.
const CAUSE_ACCEPTED := &"answered_the_court"

## ## What a refusal costs the PLAYER: −3.0 standing, −0.1 trust.
##
## ## Why a refusal costs the player at all
##
## Following BL-0745 exactly: being put to a claim and declined is something that happened
## TO YOU, and it is your regard that the world records differently afterwards. Charging
## the npc instead would mean the player's pursuit is free and the NPC is a machine the
## player spends.
##
## ## Sized against the ladder, and it is deliberately SMALLER than the oath's refusal
##
## `refused_the_oath` is −4.0/−0.15. This is −3.0/−0.1 because **courtship is cheaper to
## refuse than brotherhood**: being declined is a bad afternoon, being refused an oath is a
## broken word. It is still more than a rounding error — a third of `FRIEND_AT` — so it is
## felt, and it is still `kind: court`, so repeating it farms nothing.
const CAUSE_REFUSED := &"refused_the_court"

## ## What a player's OWN acceptance of a claim costs THEM, against the claimer.
##
## Accepting a courtship is a commitment, and the bond records that you took one: this
## writes to the NPC's ledger, so it is the mirror direction and it is what makes a claim
## mutual rather than a prize the player collects.
const CAUSE_PLEDGED := &"pledged_themselves"


## ## Record that `npc` has made a claim against `player_id`. Free, and it records itself.
##
## Returns `{ok, reason}`. **An offer costs nothing** — the price is charged on the
## ANSWER, which is what makes it safe to leave the affordance enabled, and it is the
## same rule `BrotherhoodOath.offer_brotherhood` follows.
static func offer_claim(npc: Actor, player_id: StringName, _npc_key: StringName) -> Dictionary:
	if npc == null or player_id == &"":
		return {"ok": false, "reason": "no_actor"}
	var ledger := PursuitLedger.for_actor(npc)
	var existing := ledger.claim_for(player_id)
	if not existing.is_empty() and String(existing.get("outcome", "")) != "":
		# ## The anti-repeat rule, and it is load-bearing.
		#
		# An offer that has been ANSWERED is not a second offer. Without this the whole
		# exchange is re-mintable: court someone who accepts on the right tick, over and
		# over, for the cost of one refusal.
		return {"ok": false, "reason": "already_answered"}
	# ## The gate is asked of the NPC's OWN bond, with `player_id` as the partner.
	#
	# This is the NPC→player direction read literally: the rung that decides whether this
	# person may be courted is a rung on **the npc's** ledger toward the player, not on the
	# player's toward them. `PursuitStance.may_be_courted` takes an `Actor` for the player
	# only so a caller can hand it one; here there is no player actor yet — the offer
	# arrives from the NPC — so the gate is asked directly, on the same bond, through the
	# same one gate system.
	var gate := SocialApi.gate(
		npc, {"verb": &"bond_at_least", "partner": player_id, "at_least": PursuitStance.COURT_AT}
	)
	if not bool(gate.get("ok", false)):
		return {
			"ok": false,
			"reason": "not_" + String(PursuitStance.COURT_AT),
			"unmet": gate.get("unmet", []),
		}
	var written := ledger.set_claim(player_id, {"offered": true, "outcome": "", "cost": ""})
	if not bool(written.get("ok", false)):
		return {"ok": false, "reason": String(written.get("reason", PursuitLedger.AT_LIMIT))}
	ledger.persist(npc)
	return {"ok": true, "reason": ""}


## ## The answer, read off the NPC's own ledger. `npc` answers; the PLAYER is charged.
##
## **Accept iff the NPC would actually be pursuing** — a claim from an NPC whose seed is
## below `OFFER_SEED_AT` is not answered on their terms, because they have no standing to
## ask, and that is what keeps `make_a_claim` a consequence of the seed rather than an
## independent button.
static func answer_claim(npc: Actor, player: Actor, npc_key: StringName) -> Dictionary:
	if npc == null or player == null:
		return {"ok": false, "reason": "no_actor"}
	var ledger := PursuitLedger.for_actor(npc)
	var row := ledger.claim_for(player.id)
	if row.is_empty():
		return {"ok": false, "reason": "no_offer"}
	if String(row.get("outcome", "")) != "":
		return {"ok": false, "reason": "already_answered"}
	var actions: Array = PursuitStance.read(npc, player, npc_key).get("actions", [])
	var pursuing: bool = actions.has(PursuitStance.SEEKS)
	if not pursuing:
		# ## THE REFUSAL, and what it costs.
		#
		# Charged to the PLAYER'S bond, as an authored cause — the same charge shape
		# `BrotherhoodOath.answer_offer` makes, so a reader can find the cost in the cause
		# ledger rather than in an unexplained delta.
		var charged := SocialApi.apply_cause(player, npc_key, CAUSE_REFUSED)
		_answer(ledger, npc, player.id, OUTCOME_REFUSED, CAUSE_REFUSED)
		return {
			"ok": true,
			"outcome": String(OUTCOME_REFUSED),
			"cost": String(CAUSE_REFUSED),
			"charged": bool(charged.get("ok", false)),
			"word": String(PursuitStance.word_for(npc, player)),
		}
	return accept_claim(npc, player, npc_key)


## ## Accept it, when the ledger says they were actually pursuing.
static func accept_claim(npc: Actor, player: Actor, npc_key: StringName) -> Dictionary:
	var ledger := PursuitLedger.for_actor(npc)
	var charged := SocialApi.apply_cause(player, npc_key, CAUSE_ACCEPTED)
	var pledged := SocialApi.apply_cause(npc, player.id, CAUSE_PLEDGED)
	var state := PursuitStance.note_disposition(npc, player.id, PursuitStance.CLAIMED)
	_answer(ledger, npc, player.id, OUTCOME_ACCEPTED, CAUSE_ACCEPTED)
	return {
		"ok": bool(charged.get("ok", false)) and bool(state.get("ok", false)),
		"outcome": String(OUTCOME_ACCEPTED),
		"cost": String(CAUSE_ACCEPTED),
		"charged": bool(charged.get("ok", false)),
		"pledged": bool(pledged.get("ok", false)),
		"word": String(PursuitStance.word_for(npc, player)),
	}


## ## Whether the player may answer a claim right now, and what the answer would be.
##
## `{ok, reason, will_accept, word}` — published so an affordance can say "asking now
## would be declined" rather than letting the verb refuse at the player. The same
## two-beat shape `BrotherhoodOath.eligibility` established.
static func eligibility(npc: Actor, player: Actor, npc_key: StringName) -> Dictionary:
	if npc == null or player == null:
		return {"ok": false, "reason": "no_actor", "will_accept": false, "word": ""}
	var ledger := PursuitLedger.for_actor(npc)
	var row := ledger.claim_for(player.id)
	if row.is_empty():
		return {"ok": false, "reason": "no_offer", "will_accept": false, "word": ""}
	if String(row.get("outcome", "")) != "":
		return {"ok": false, "reason": "already_answered", "will_accept": false, "word": ""}
	var gate := PursuitStance.may_be_courted(player, npc, npc_key)
	var read := PursuitStance.read(npc, player, npc_key)
	var actions: Array = read.get("actions", [])
	var will_accept: bool = bool(gate.get("ok", false)) and actions.has(PursuitStance.SEEKS)
	return {
		"ok": true,
		"reason": "",
		"unmet": gate.get("unmet", []),
		"will_accept": will_accept,
		"word": String(PursuitStance.word_for(npc, player)),
	}


## ## Write the answer onto the NPC's ledger and fold it into `module_data`.
static func _answer(
	ledger: PursuitLedger, npc: Actor, player_id: StringName, outcome: StringName, cost: StringName
) -> void:
	ledger.set_claim(player_id, {"offered": true, "outcome": String(outcome), "cost": String(cost)})
	ledger.persist(npc)


## ## Forget the claim against `player_id`. A retired npc's cleanup, and a test's reset.
static func withdraw(npc: Actor, player_id: StringName) -> bool:
	if npc == null:
		return false
	var ledger := PursuitLedger.for_actor(npc)
	if not ledger.forget(player_id):
		return false
	ledger.persist(npc)
	return true
