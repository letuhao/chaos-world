class_name PursuitStance
extends RefCounted

## **Pursuit as behaviour — the telling, not the bar** (ADR 0256).
##
## ## What an NPC does about its interest, and what it cannot do
##
## A stance is a WORD plus a repertoire of ACTIONS, derived from two independent inputs:
##
##  - **the impression** (`SocialAttractionSeed`) — what this npc thought in the first
##    second, fixed;
##  - **the regard** (`SocialApi.bond_entry(npc, player_id)`) — what the player has done
##    to them since, and the only one of the two the player can move.
##
## ## ## The two gates are at DIFFERENT rungs, and that is the whole design
##
## The reference research found the genre's best-documented failure: **players find the
## courtship path incoherent when traits gate it invisibly**, and an NPC with 忠贞不渝
## "cannot be courted AND is very hard to lose" — a double gate. So:
##
##  - **May they COURT?** needs a **confidant**. An impression is not courtship; a
##    relationship is.
##  - **Will they COURT?** needs `PERSUADED_AT` on the seed.
##
## A player who cannot make the claim is told exactly which one failed, and both answers
## are computed on demand by `read`. **No hidden trait gates anything.** The famous NPC
## is hard to win and easy to lose, because the only thing that moves the seed is nothing
## at all and the only thing that moves regard is what the player does — in either
## direction, freely.
##
## ## And we do NOT couple the gates (the research's one clear recommendation)
##
## The genre's 情有独钟 trait makes affinity-gain −10/−20/−30% **and** affinity-loss
## −20/−40/−60%: being hard to win is also being hard to lose. **We refuse that
## coupling**, deliberately: here regard is an ordinary authored cause ledger, so a
## courtship you botched is recoverable by doing something else worth doing. A romance
## with no exit is a punishment, not a tragedy.

## ## The word ladder the player sees. **No numbers** — this is the whole player-facing
## half of decision 3, and the ladder is ordered so a panel can walk it without a lookup.
const NONE := &"indifferent"
const PLEASED := &"pleased"
const TAKEN := &"taken"
const DEVOTED := &"devoted"
const DECLINED := &"declined"

## ## The repertoire. An npc's interest is legible through WHICH of these they will do.
##
## Not a bar. `seeks_you_out` is the tell, `unavailable` is the pressure, `makes_a_claim`
## is the commitment — and the owner named exactly these three.
const SEEKS := &"seeks_you_out"
const UNAVAILABLE := &"unavailable"
const CLAIMS := &"makes_a_claim"

## ## The rung on the ladder an NPC may be COURTED at, read through the ONE gate system.
##
## **`SocialBondClass.CONFIDANT` is `PROMOTION_MIN_CLASS`** — the rung an oath itself
## demands — so this is not a rule invented beside the ladder, it is the ladder's own bar
## read before the act. And it is read through `SocialApi.gate`, never off a stat
## (ADR 0062): no item and no pill can satisfy it.
const COURT_AT := SocialBondClass.CONFIDANT

## ## The seed value at which a courtship is even offered.
##
## Below this an npc is friendly and nothing more. Sized so the plain baseline `BASE` (30)
## plus ONE ordinary input is well short of it — an npc does not pursue a stranger the
## player happened to be charming near.
const OFFER_SEED_AT := SocialAttractionSeed.PERSUADED_AT

## ## The disposition an NPC reaches purely by impression, with no bond at all.
##
## `BOND` is the disposition earned by regard alone (a confidant with an indifferent
## seed still regards you). An NPC that meets BOTH — a real impression and a real
## relationship — reads `DEVOTED` and is the one that makes a claim.
const IMPRESSION := &"impressed"
const BOND := &"attached"
const CLAIMED := &"claimed"

## ## What this npc will DO about it, in repertoire order.
##
## ## Bounded by the three-item constant, never by the size of anything else
##
## The loop is over `ACTIONS` — a `const` of size 3 — so no player history, roster size
## or world state can make this scan grow. `npc_key` is threaded in rather than guessed,
## because the courtship rung is read off the **npc's** bond with the player and an empty
## key would silently read "no bond" and refuse every courtship in the game. That is the
## subtle half of the direction: the gate has to be asked the same question the write uses.
const ACTIONS: Array[StringName] = [SEEKS, UNAVAILABLE, CLAIMS]

## ## The tiers whose pursuit may persist anything.
##
## **`story` and `major` are named rather than `not tracked`,** for the reason
## `NpcTier.COMPOSED` is a named set: the tier is data and a mechanism never branches on
## one. Adding a fifth persistent tier is one row here.
const PERSISTENT_TIERS: Array[StringName] = NpcTier.TRACKED


## ## Whether `npc` may be courted at all. `{ok, reason, unmet}` — the same shape the
## whole gate system returns, so a panel prints a reason it did not have to invent.
static func may_be_courted(player: Actor, npc: Actor, npc_key: StringName) -> Dictionary:
	if player == null or npc == null:
		return {"ok": false, "reason": "no_actor", "unmet": []}
	var entry := SocialApi.bond_entry(npc, npc_key)
	if not bool(entry.get("present", false)):
		return {"ok": false, "reason": "no_bond", "unmet": []}
	var verdict := SocialApi.gate(
		npc, {"verb": &"bond_at_least", "partner": player.id, "at_least": COURT_AT}
	)
	if bool(verdict.get("ok", false)):
		return {"ok": true, "reason": "", "unmet": []}
	return {
		"ok": false,
		"reason": "not_" + String(COURT_AT),
		"unmet": verdict.get("unmet", []),
		"gate_reason": String(verdict.get("reason", "")),
	}


## ## The NPC's whole read for the player, as primitives.
##
## ## `numbers` is present but EMPTY, always
##
## This is decision 3 enforced mechanically rather than by review. The player-facing
## contract is `word`, `actions` and `may_court`; `numbers` exists as a key so the
## DEBUG read has somewhere to put the real value — and it is populated only when
## `debug` is explicitly requested, because the full debug read is hidden by default
## behind a user setting (ADR 0256's DOS/decision-3 tie-in). A caller that never asks
## cannot get a number out of this.
##
## Returned keys are primitives and `actions` only, so this satisfies the `summary()`
## contract a panel tests instead of pixels.
static func read(npc: Actor, player: Actor, npc_key: StringName, debug: bool = false) -> Dictionary:
	var out := {
		"word": String(SocialAttractionSeed.word(npc, player)),
		"actions": [] as Array[StringName],
		"may_court": false,
		"reason": "",
		"numbers": {},
	}
	if npc == null or player == null:
		return out
	var ledger := PursuitLedger.for_actor(npc)
	var disposition := String(ledger.disposition_for(player.id).get("state", ""))
	var actions := _actions(npc, player, npc_key, disposition)
	out["actions"] = actions
	var gate := may_be_courted(player, npc, npc_key)
	out["may_court"] = bool(gate.get("ok", false))
	out["reason"] = String(gate.get("reason", ""))
	if debug:
		# ## The ONLY path by which a number reaches this dictionary.
		out["numbers"] = {
			"seed": SocialAttractionSeed.seed_total(npc, player),
			"offer_at": OFFER_SEED_AT,
			"disposition": disposition,
			"bond": String(SocialApi.bond_entry(npc, npc_key).get("bond", "")),
		}
	return out


static func _actions(
	npc: Actor, player: Actor, npc_key: StringName, disposition: String
) -> Array[StringName]:
	var out: Array[StringName] = []
	var seed_total := SocialAttractionSeed.seed_total(npc, player)
	var gate := may_be_courted(player, npc, npc_key)
	var courting := seed_total >= OFFER_SEED_AT and bool(gate.get("ok", false))
	# ## And a declined suitor does ANYTHING. Which is the recovery the refusal buys.
	if disposition == String(DECLINED) and seed_total < OFFER_SEED_AT:
		return out
	for action in ACTIONS:
		match action:
			SEEKS:
				if courting:
					out.append(action)
			UNAVAILABLE:
				# Unavailable is answered on impression alone — a person may be drawn to you
				# without being available to you. This is the pressure of the fantasy and it
				# is deliberately the rung BELOW courtship, so it can happen to a friend.
				if seed_total >= OFFER_SEED_AT:
					out.append(action)
			CLAIMS:
				if disposition == String(CLAIMED):
					out.append(action)
	return out


## ## Move the NPC's disposition by `cause_id`, an AUTHORED cause.
##
## ## The mirror, generalised
##
## This is what "the npc's own disposition moves when the player does the relevant
## thing" means in code. `BrotherhoodOath.swear_brotherhood` hardcoded one mirror line for
## one act; this is the general case, and it is the ONLY writer of `dispositions`.
##
## **`ok: false` here means the ledger was at its cap** — refusal, not a silent success,
## so a caller cannot believe it moved something it did not.
static func note_disposition(npc: Actor, player_id: StringName, state: StringName) -> Dictionary:
	if npc == null or player_id == &"":
		return {"ok": false, "reason": "no_actor"}
	var ledger := PursuitLedger.for_actor(npc)
	var written := ledger.set_disposition(player_id, {"state": String(state)})
	if not bool(written.get("ok", false)):
		return {"ok": false, "reason": String(written.get("reason", PursuitLedger.AT_LIMIT))}
	ledger.persist(npc)
	return {"ok": true, "reason": ""}


## ## Compose a pursuit stance for an UNTRACKED npc, at the moment of interaction.
##
## ## Why this writes nothing at all
##
## **A transient NPC's interest costs nothing when unobserved because it is not stored
## when observed either.** `compose_transient` reads the two inputs, returns the word and
## the repertoire, and calls no `set_*` — there is no row to leave behind. A minor npc
## gets the same composed answer plus an OPTIONAL seed, which is the only difference
## between the two untracked tiers here (see `PERSISTENT_TIERS`).
##
## It returns the same `read` shape, so a panel cannot tell which tier it is talking to
## except through what it is allowed to do with the answer.
static func compose_transient(
	npc: Actor, player: Actor, npc_key: StringName, tier: StringName, debug: bool = false
) -> Dictionary:
	# ## Composed, so the seed a minor carries is derived from THIS instant and written
	# once. `apply_once` is the same call the meeting path makes, so the anti-farm rule is
	# not a second implementation with its own bug.
	if PERSISTENT_TIERS.has(tier):
		var seeded := SocialAttractionSeed.apply_once(
			npc, player, {"race_tags": [], "bloodline_tags": [], "sect_tags": []}
		)
		if (
			not bool(seeded.get("applied", false))
			and String(seeded.get("reason", "")) == "already_seeded"
		):
			# Already seeded: fall through and read what is there, which is the
			# `already_seeded` contract rather than a second write.
			pass
	return read(npc, player, npc_key, debug)


## ## What an untracked NPC CANNOT do here, stated so it cannot drift
##
## ## The list, and each item's reason
##
##  - **It cannot hold a claim.** `CLAIMS` is only reachable when `disposition ==
##   CLAIMED`, and a disposition is only written by `note_disposition`, which
##   `accept_claim` — which refuses an untracked tier — is the only production caller of.
##   A shopkeeper cannot propose marriage to a stranger who will not be there next season.
##  - **It cannot refuse a player**, so it cannot cost anything. `answer_claim` refuses
##   `not_pursuing` for anyone without a `SEEKS` action. A transient's interest is real
##   for the length of the conversation and is never a thing the player spent something
##   on, so there is nothing for a refusal to be a cost against.
##  - **It cannot appear as a pursued party tomorrow**, because nothing about it persists.
##   Re-encountering is a NEW impression, composed fresh.
##  - **It cannot move the player's ledger.** This whole file writes only to the npc's own
##   `PursuitLedger` and, through `SocialApi.apply_cause`, to the npc's own bond.
##  - **It is not scanned for.** Nothing here enumerates NPCs; a caller that wants
##   "who wants me" must read a LIST the caller already holds. `PursuitStance` provides
##   no "scan the world" verb, deliberately — that is the shape that crashes the machine.
static func untracked_limits() -> Array[String]:
	return [
		"holds_no_claim",
		"cannot_refuse",
		"persists_nothing",
		"writes_no_player_ledger",
		"never_scanned_for",
	]


## ## The player-facing word for a disposition, with no number in it.
static func word_for(npc: Actor, player: Actor) -> StringName:
	if npc == null or player == null:
		return NONE
	var state := String(PursuitLedger.for_actor(npc).disposition_for(player.id).get("state", ""))
	match state:
		IMPRESSION:
			return TAKEN
		BOND:
			return PLEASED
		CLAIMED:
			return DEVOTED
		DECLINED:
			return DECLINED
	return SocialAttractionSeed.word(npc, player)
