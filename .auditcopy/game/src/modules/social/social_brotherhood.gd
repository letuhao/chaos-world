class_name BrotherhoodOath
extends RefCounted

## **The offer / answer / refusal exchange that makes `sworn` a thing a player does**
## (ADR 0196, closing BL-0745).
##
## ## The one cause whose content is that someone AGREED
##
## Every other cause in the catalog is an act a *system observes*: you joined, you were
## promoted, you conceived, you won the lot. `shared_brotherhood` is the first one whose
## whole content is that **two people agreed**, so it cannot be a repeatable tally: a
## button that grants the top of the ladder is precisely what ADR 0091 exists to refuse.
##
## ## ## What the player does
##
## `offer_brotherhood` is the verb, and it is two beats — an **offer** and an **answer**.
## The offer is free and records itself. The answer is read off **the bond the two of
## them have actually built**: no dialogue tree (DEF-0014) and none is invented here.
## Standing and trust ARE the answer, read through `SocialGate` rather than compared
## inline, so the only statement of "who may be sworn to" is an authored requirement.
##
## ## ## Why the offer and the answer are gated at DIFFERENT rungs — this is the design
##
## **A friend may be PUT TO the oath. Only a confidant may SWEAR it.**
##
## That gap is the entire feature. It is what makes the exchange an exchange rather than
## a formality: the player can ask a friend, and the friend will **decline**, and the
## asking is a small wound — because a friendship is not yet the weight a person will
## bind a life to. So the refusal is the DEFAULT for anyone who offers early, it is
## reachable by any player without authoring anything, and it is reached by exactly the
## act the ruling names. The cost is not an optional garnish on a rare outcome.
##
## Both rungs are the module's own ladder (`SocialBondClass.CONFIDANT` and `.FRIEND`) and
## both are read through the ONE gate system. There is no second gate here, which is the
## defect BL-0690 was about (`SocialGate._aggregate` once read children under
## `"requirements"` while ten other modules use `"of"`, so an authored aggregate gate
## opened itself).
##
## ## ## What refusal costs
##
## A refusal that costs nothing means the offer is spam. So refusal is an ACT and it is
## written to the same ledger every other act is: `refused_the_oath` is an authored cause
## charged against the player's bond with them. **The cost is on the PLAYER's ledger,
## not on theirs** — being put to an oath and declined is something that happened to you,
## and it is your regard that the world records differently afterwards. It is a
## `kind: oath` cause like the acceptance, so a pair whose whole history is oaths made
## and broken still tops out below a friendship and cannot farm anything out of refusing.
##
## ## ## What is MUTUAL, precisely
##
## ADR 0091 leaves the mirror of `apply_cause` to the caller's transaction, and this file
## IS that transaction. **Both ledgers move in the same call**: the player writes
## `shared_brotherhood` against the npc, and the npc writes `accepted_the_oath` back
## against the player. One agreement, two `Actor`s, two ledgers — which is only possible
## because ADR 0091 made the ledger symmetric by TYPE, and which the suite asserts from
## both sides rather than assumes.
##
## ## ## And why none of this is a facade method
##
## `NpcApi` is at 12/12 and `SocialApi` is at the cap, so neither may grow. This file
## lives beside them, is reached from `app/`, and calls the two facades as a caller —
## exactly the `SoulArrivalMarks` shape (ADR 0190): `app/` is exempt from `LAYER_DEPS`,
## so no `npc -> social` edge is invented to carry it.

## The cause that promises the top rung. Authored in `SocialCauseCatalog`, never written
## as a number here — a cause is the only writer of a bond (ADR 0091).
const CAUSE_SWORN := &"shared_brotherhood"
## The MIRROR: what the elder's own ledger records when the elder says yes. A different
## id from `CAUSE_SWORN` on purpose — "I swore with him" and "he swore with me" are two
## entries in two ledgers, not one entry written twice.
const CAUSE_ACCEPTED := &"accepted_the_oath"
## What a refusal charges the player. Authored in `SocialCauseCatalog._add_oath`.
const CAUSE_REFUSED := &"refused_the_oath"
## What a WITNESSED oath binds the player to. Written on the player↔witness bond, so an
## author's `caused_by: witnessed_an_oath` gate opens on it and on nothing else.
const CAUSE_WITNESSED := &"witnessed_an_oath"


## ## Offer the oath to `partner`, on behalf of `player`.
##
## Returns `{ok, reason, unmet}`. **Every refusal names itself**: no gate closes silently,
## so a panel can print what the player is missing instead of greying a button. An
## offer costs nothing — the price is charged on the ANSWER, which is what makes it safe
## to leave the affordance enabled.
static func offer_brotherhood(
	player: Actor, partner: Actor, witness_id: StringName = &"", witnessed: bool = false
) -> Dictionary:
	if player == null or partner == null:
		return {"ok": false, "reason": "no_actor", "unmet": []}
	# ## Every read and write below is keyed on `key`, never on `partner.id`.
	#
	# They are not the same string: the actor `ActorFactory.spawn_npc` mints for
	# `elder_wei` is `npc_elder_wei`, while the roster, the consent ledger, every authored
	# gate and every panel name the DEF id. Mixing them is not a cosmetic bug — it is what
	# made the verb report `no_bond` against a bond the player had plainly earned, because
	# the gate read a row nobody had written. One resolution per call, and every path
	# through the exchange agrees on it.
	var key := _bond_key(partner)
	var ledger := consent(player)
	if ledger.answered(key):
		# The anti-repeat rule, and it is the load-bearing half of the design. An offer
		# that has already been ANSWERED is not a second offer, so the button cannot be
		# pressed twice to reach the top of a ladder — which is the exact hole ADR 0091
		# describes and refuses.
		return {"ok": false, "reason": "already_answered", "unmet": []}
	var eligible := can_be_asked(player, partner)
	if not bool(eligible.get("ok", false)):
		return {
			"ok": false,
			"reason": String(eligible.get("reason", "ineligible")),
			"unmet": eligible.get("unmet", []),
		}
	var recorded := ledger.offer(key, witness_id, witnessed)
	if not bool(recorded.get("ok", false)):
		return {"ok": false, "reason": String(recorded.get("reason", "no_partner")), "unmet": []}
	_persist(ledger, player)
	return {"ok": true, "reason": "", "unmet": [], "witnessed": witnessed}


## ## The answer, read off the bond the two of them have actually built.
##
## **Accept iff the bond has earned a confidant; otherwise they decline and it costs.**
## There is no RNG and no mood, so an answer is reproducible from a save and a player
## cannot re-roll a refusal — which is the only way an answer can be *consent* rather
## than a slot machine.
##
## The consent ledger records that an offer happened and what it was answered with. It
## records **no standing value** — the cost rides `CAUSE_REFUSED` on the bond, so there
## is exactly one copy of every number.
static func answer_offer(player: Actor, partner: Actor) -> Dictionary:
	if player == null or partner == null:
		return {"ok": false, "reason": "no_actor"}
	var key := _bond_key(partner)
	var ledger := consent(player)
	if ledger.row(key).is_empty():
		return {"ok": false, "reason": "no_offer"}
	if ledger.answered(key):
		return {"ok": false, "reason": "already_answered"}
	var reckoning := _reckoning(player, partner)
	if not bool(reckoning.get("sworn", false)):
		# ## THE REFUSAL, and what it costs.
		#
		# Charged to the PLAYER'S bond against them. `refused_the_oath` is an authored
		# cause, so the standing that leaves is a line a reader can find in the cause
		# ledger rather than an unexplained delta — which is what ADR 0091 means by
		# "a refusal must be a fact the world can explain".
		var charged := SocialApi.apply_cause(player, key, CAUSE_REFUSED)
		ledger.answer(key, ConsentLedger.OUTCOME_REFUSED, CAUSE_REFUSED)
		_persist(ledger, player)
		return {
			"ok": true,
			"outcome": String(ConsentLedger.OUTCOME_REFUSED),
			"cost": String(CAUSE_REFUSED),
			"charged": bool(charged.get("ok", false)),
			"witnessed": bool(ledger.row(key).get("witnessed", false)),
			"held_class": String(SocialApi.bond_entry(player, key).get("bond", "")),
		}
	return swear_brotherhood(player, partner)


## ## Swear it, when the reckoning says the bond can carry the weight.
##
## Split from `answer_offer` so that refusing is a legitimate ANSWER to an offer rather
## than a private path onto the top of the ladder: the two are different verbs in the
## fiction, and only one of them is an oath.
##
## `witness_id` is for the DIRECT beat (`BrotherhoodOathApp.swear`), which never offered.
## **On the offered path the witness is read off the consent row**, because that is where
## `offer_brotherhood` recorded it and `answer_offer` does not thread it through. A
## `witnessed: true` oath therefore always writes the `CAUSE_WITNESSED` bond — the flag on
## the consent row is never the only record that a witness stood there.
static func swear_brotherhood(
	player: Actor, partner: Actor, witness_id: StringName = &""
) -> Dictionary:
	var reckoning := _reckoning(player, partner)
	if not bool(reckoning.get("sworn", false)):
		return {
			"ok": false,
			"reason": String(reckoning.get("reason", "not_confidant")),
			"unmet": reckoning.get("unmet", []),
		}
	var ledger := consent(player)
	var key := _bond_key(partner)
	var row := ledger.row(key)
	var witnessed := bool(row.get("witnessed", false))
	# ## The witness is resolved from the CONSENT ROW, not from the caller's argument
	#
	# `offer_brotherhood` records `witness_id` on the row at OFFER time — that is the whole
	# point of recording it there, since the answer happens in a different call. The
	# argument below is for the direct `BrotherhoodOathApp.swear` beat, which never offered
	# and therefore has no row to read. **When the caller passes nothing and the row knows
	# who stood there, the row wins.**
	#
	# This is a real bug that was live in the production path, not a test artefact:
	# `answer_offer` calls `swear_brotherhood(player, partner)` with no witness argument, so
	# `witness_id` was `&""` at exactly the moment the witness leg should have been written.
	# `BrotherhoodOathApp.offer(player, elder, witness, true)` therefore returned
	# `"witnessed": true`, wrote it to the consent row, and left **no bond at all** against
	# the witness — the ceremony was recorded as a flag on a consent row and never as a
	# fact in the world, which is the precise defect this function's docstring refuses. An
	# authored `caused_by: witnessed_an_oath` gate could not open on it.
	var named_witness := witness_id
	if named_witness == &"":
		named_witness = StringName(String(row.get("witness_id", "")))
	# ## BOTH SIDES MOVE. This is the whole mutuality contract.
	#
	# The player's bond records `shared_brotherhood`, whose `promotes_to: SWORN` is the
	# promise the ladder decides on. The partner's bond records `accepted_the_oath` —
	# the mirror, on THEIR ledger, naming the player. Two `apply_cause` calls, two
	# actors, one agreement. A one-sided version would leave the elder's regard
	# untouched while the player's read `Sworn`, which is the shape the ADR 0091 design
	# question named and refused.
	#
	# **Both are keyed through `_bond_key`, which is the load-bearing half of mutuality.**
	# An npc's counterparty id is the DEF id and the player's is their actor id, so
	# writing `partner.id` put the player's promise on a `npc_elder_wei` row while every
	# reader asked about `elder_wei` — the pact existed and nothing could see it.
	var player_side := SocialApi.apply_cause(player, key, CAUSE_SWORN)
	var partner_side := SocialApi.apply_cause(partner, _bond_key(player), CAUSE_ACCEPTED)
	if witnessed and named_witness != &"":
		# The witness stands surety, so the player holds a real bond against THEM for
		# having vouched — the third leg, and the one an authored gate can name. Keyed on
		# the resolved id, which is either what the caller named (the direct `swear` beat) or
		# what the consent row recorded at offer time. Both are def ids off the roster.
		SocialApi.apply_cause(player, named_witness, CAUSE_WITNESSED)
	ledger.answer(key, ConsentLedger.OUTCOME_ACCEPTED, CAUSE_SWORN, witnessed)
	_persist(ledger, player)
	return {
		"ok": bool(player_side.get("ok", false)) and bool(partner_side.get("ok", false)),
		"outcome": String(ConsentLedger.OUTCOME_ACCEPTED),
		"cost": String(CAUSE_SWORN),
		"witnessed": witnessed,
		"witness_id": String(named_witness),
		"player_class": String(SocialApi.bond_entry(player, key).get("bond", "")),
		"partner_class": String(SocialApi.bond_entry(partner, _bond_key(player)).get("bond", "")),
	}


## ## May the player put the oath to this person AT ALL?
##
## The OFFER gate, and it is the weaker of the two on purpose: a friend may be asked.
## Three named refusals, because "you have never met" and "they are not yet a friend" are
## different things to a player and only the second is something they can go and fix.
static func can_be_asked(player: Actor, partner: Actor) -> Dictionary:
	if player == null or partner == null:
		return {"ok": false, "reason": "no_actor", "unmet": []}
	var key := _bond_key(partner)
	var entry := SocialApi.bond_entry(player, key)
	if not bool(entry.get("present", false)):
		return {"ok": false, "reason": "no_bond", "unmet": []}
	return _gate(player, key, SocialBondClass.FRIEND, "not_friend")


## ## May they ANSWER yes? The stricter of the two, and the one the refusal names.
##
## `CONFIDANT` is `SocialBondClass.PROMOTION_MIN_CLASS` — the same rung the promotion
## itself requires — so this is not a rule invented beside the ladder, it is the ladder's
## own bar read BEFORE the act rather than after it.
static func can_be_sworn(player: Actor, partner: Actor) -> Dictionary:
	if player == null or partner == null:
		return {"ok": false, "reason": "no_actor", "unmet": []}
	var key := _bond_key(partner)
	var entry := SocialApi.bond_entry(player, key)
	if not bool(entry.get("present", false)):
		return {"ok": false, "reason": "no_bond", "unmet": []}
	return _gate(player, key, SocialBondClass.CONFIDANT, "not_confidant")


## The whole eligibility question in one read, for a panel that greys an affordance out
## rather than letting the verb refuse later. Same `{ok, reason}` shape as the gate.
static func eligibility(player: Actor, partner: Actor) -> Dictionary:
	if player == null or partner == null:
		return {"ok": false, "reason": "no_actor", "unmet": []}
	var key := _bond_key(partner)
	var asked := can_be_asked(player, partner)
	if not bool(asked.get("ok", false)):
		return asked
	if consent(player).answered(key):
		return {"ok": false, "reason": "already_answered", "unmet": []}
	var sworn := can_be_sworn(player, partner)
	return {
		"ok": true,
		"reason": "",
		"unmet": [],
		"will_swear": bool(sworn.get("ok", false)),
		"partner": String(key),
	}


## ## The answer itself: `{sworn, reason, unmet, held_class}`.
##
## Read only, so `eligibility` can publish what the answer WILL be before the player
## commits to asking — which is the whole point of an authored refusal cost. A player
## can see the elder is not yet ready and choose to spend the season on the bond instead.
static func _reckoning(player: Actor, partner: Actor) -> Dictionary:
	var verdict := can_be_sworn(player, partner)
	verdict["sworn"] = bool(verdict.get("ok", false))
	verdict["held_class"] = String(SocialApi.bond_entry(player, _bond_key(partner)).get("bond", ""))
	return verdict


## The ONE place a ladder rung becomes a requirement, so eligibility and the answer can
## never drift apart. Reuses `SocialGate.evaluate` through the facade — a gate reads the
## LEDGER, never a stat, so no item and no pill can satisfy it (ADR 0062's rule).
static func _gate(
	player: Actor, partner_id: StringName, rung: StringName, reason: String
) -> Dictionary:
	var verdict := SocialApi.gate(
		player, {"verb": &"bond_at_least", "partner": partner_id, "at_least": rung}
	)
	if bool(verdict.get("ok", false)):
		return {"ok": true, "reason": "", "unmet": []}
	# The gate's own `unmet` is carried through verbatim, so a panel renders
	# "Confidant, not Friend" without this file inventing a word of it.
	return {
		"ok": false,
		"reason": reason,
		"unmet": verdict.get("unmet", []),
		"gate_reason": String(verdict.get("reason", "")),
	}


## ## The key the MIRROR side of the pact is written under.
##
## ## Why this is not simply `player.id`
##
## An npc's ledger is keyed by whoever stands on the other side of it, and **for another
## npc that id is the DEF id, not the actor id.** `ActorFactory.spawn_npc` mints
## `npc_elder_wei`, so `apply_cause(partner, player.id, …)` on an npc partner filed
## `accepted_the_oath` under `npc_hero` — a row on the elder's ledger naming an actor id
## no reader anywhere in the game will ask for. `app/auction_standing.gd` already
## resolves its counterparty this way for the same reason, and the rule is what makes both
## ledgers readable from a save: `NpcRosterEntry` is keyed on the def id (`elder_wei`), so
## that is the id an authored gate, a consent row and a panel all use — and it is what
## `SocialApi.bond_entry(elder, ELDER)` is asking about.
##
## ## No thirteenth facade verb
##
## `NpcApi` is at 12/12, so this cannot ask for a `def_id_of` the way the roster asks for
## one — and it must not, because `npc/`'s own `_def_id_of` is exactly the shape this
## needs and it is deliberately private. The live registry's keys ARE the def ids, so the
## fact is read from them rather than reverse-engineered: `NpcRegistry.present_ids()` is
## sorted, and every def id is a prefix of its own instance keys (`elder_wei` /
## `elder_wei#1`), so the **prefix match is tried before the exact match** and the first
## def whose live body IS this actor wins. Bounded by the registry, which is bounded by
## the room.
static func bond_key(other: Actor) -> StringName:
	if other == null:
		return &""
	for key in NpcRegistry.instance().present_ids():
		if NpcRegistry.instance().present(key) != other:
			continue
		var text := String(key)
		var hash_at := text.rfind("#")
		if hash_at >= 0:
			return StringName(text.substr(0, hash_at))
	return other.id


## The private spelling of [method bond_key], used by every verb in this file. One name,
## one behaviour: a public alias that could drift from the private one would reintroduce
## exactly the split-brain this function exists to close.
static func _bond_key(other: Actor) -> StringName:
	return bond_key(other)


## The player's consent ledger, restored from `module_data` on first read.
##
## Both keys belong to `ConsentLedger` and are read off it rather than restated here, so
## the slot and the save key cannot drift apart — which is the same discipline
## `SocialApi.STATE_COMPONENT` holds to for its own ledger.
static func consent(player: Actor) -> ConsentLedger:
	if player == null:
		return null
	var slot: StringName = ConsentLedger.STATE_COMPONENT
	var key: StringName = ConsentLedger.MODULE_KEY
	var ledger := player.component(slot) as ConsentLedger
	if ledger != null:
		return ledger
	ledger = ConsentLedger.from_dict(player.get_module_data(key))
	player.set_component(slot, ledger)
	return ledger


## Fold the ledger into `module_data`, so `Actor.to_dict` alone is a complete save — the
## same reason `SocialApi._persist` and `NpcApi._persist` both flush on change.
static func _persist(ledger: ConsentLedger, player: Actor) -> void:
	if ledger == null or player == null:
		return
	player.set_module_data(ConsentLedger.MODULE_KEY, ledger.to_dict())
