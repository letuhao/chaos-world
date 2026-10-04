class_name BrotherhoodOathApp
extends RefCounted

## **The verb a player presses, and the only place `npc` and `social` are allowed to
## meet** (ADR 0196, closing BL-0745).
##
## ## Why this is in `app/` and not on either facade
##
## `NpcApi` publishes exactly twelve public methods and `SocialApi` sits at its cap, so
## **neither may grow a thirteenth** — `tools arch` fails the build on it
## (`rules.MAX_FACADE_PUBLIC_METHODS`). Worse, a verb that swears one person to another
## needs BOTH modules: it resolves the npc's `Actor` through `NpcApi` and writes two
## bonds through `SocialApi`. `social/` declares `["contracts", "core"]` and may not name
## `npc/`; `npc/` declares `social` for exactly one verb (`forget`) and must not name
## `social_brotherhood` either. So the only legal home for the exchange is the layer that
## is exempt from the graph — `LAYER_DEPS["app"] == {"*"}`.
##
## This is the shape ADR 0190 already set with `SoulArrivalMarks`: a plain `RefCounted`
## in `app/` that reaches its collaborators through facades, holds no state of its own,
## and is drivable by a headless test with no scene tree. **It keeps no ledger, no roster
## and no cache** — the consent ledger rides the player's `module_data` and the truth
## about regard is the bond, so this file is wiring and translation, nothing else.
##
## ## What it adds over the collaborator, and why
##
## Only two things, both of them translation a player-facing caller needs:
## 1. **An npc id instead of an `Actor`.** A panel holds `&"elder_wei"`, not a body.
##    Resolution goes through `NpcApi.resident`, which is the off-stage mechanism ADR
##    0074 already provides, and refuses with `unknown_npc` when this process holds none.
## 2. **A read model for the affordance** — `read`, so a screen greys the oath out and
##    prints the reason rather than letting the verb refuse at the player.


## Every cause id this verb can apply, sorted. The vocabulary a content audit reads to
## answer "is anything unwired here" — and what `tests/app/test_brotherhood_oath.gd` pins
## against the authored catalog, so a bridge built on an unauthored id fails at test
## time rather than refusing silently at play time.
static func cause_ids() -> Array[StringName]:
	var out: Array[StringName] = [
		BrotherhoodOath.CAUSE_ACCEPTED,
		BrotherhoodOath.CAUSE_REFUSED,
		BrotherhoodOath.CAUSE_SWORN,
		BrotherhoodOath.CAUSE_WITNESSED,
	]
	out.sort()
	return out


## The player-facing verb: put the oath to `npc_id`.
##
## Returns `{ok, outcome, cost, witnessed}` on an answer, or `{ok: false, reason, unmet}`
## when the act was refused before it started. **A refusal of the ACT names its reason
## and writes nothing**; a refusal of the ANSWER is a different thing entirely and is
## what costs.
static func offer(
	player: Actor, npc_id: StringName, witness_id: StringName = &"", witnessed: bool = false
) -> Dictionary:
	var partner := NpcApi.resident(npc_id)
	if partner == null:
		return {"ok": false, "reason": "unknown_npc", "unmet": []}
	var accepted := BrotherhoodOath.offer_brotherhood(player, partner, witness_id, witnessed)
	if not bool(accepted.get("ok", false)):
		return accepted
	# ## Both beats are keyed on the id the CALLER held, not on `partner.id`.
	#
	# `npc_id` is a def id and `partner.id` is the actor id the minter minted for it
	# (`npc_elder_wei`), and the two are what a consent row, an authored gate and a panel
	# each mean. The collaborator resolves it itself; this file passes the id the caller
	# already typed so both beats address the same row instead of one of them naming a
	# ledger entry nothing will ever read.
	var answered := BrotherhoodOath.answer_offer(player, partner)
	answered["offered"] = true
	return answered


## ## Swear it outright, without offering first.
##
## **This exists for authored beats, not for the button.** The fiction is an OFFER the
## player makes and an ANSWER they give, and this skips the first half — so a panel
## must not call it, and a suite that asserts the production path must call `offer`.
## It is here because a scripted story beat sometimes needs to land an oath without a
## player present to ask, and it still runs every gate: it cannot buy a top rung, it
## only lets content reach the one the player's own history has already earned.
static func swear(player: Actor, npc_id: StringName, witness_id: StringName = &"") -> Dictionary:
	var partner := NpcApi.resident(npc_id)
	if partner == null:
		return {"ok": false, "reason": "unknown_npc", "unmet": []}
	return BrotherhoodOath.swear_brotherhood(player, partner, witness_id)


## Whether the player may put the oath to `npc_id` right now, and what the answer would
## be. `{ok, reason, unmet, will_swear, partner, class}` — `will_swear` is the
## reckoning, published so an affordance can show that asking now would be declined.
static func read(player: Actor, npc_id: StringName) -> Dictionary:
	var partner := NpcApi.resident(npc_id)
	if partner == null:
		return {
			"ok": false,
			"reason": "unknown_npc",
			"unmet": [],
			"will_swear": false,
			"partner": String(npc_id),
			"class": "",
		}
	var verdict := BrotherhoodOath.eligibility(player, partner)
	var bond := SocialApi.bond_entry(player, partner.id)
	var row := BrotherhoodOath.consent(player).row(npc_id)
	return {
		"ok": bool(verdict.get("ok", false)),
		"reason": String(verdict.get("reason", "")),
		"unmet": verdict.get("unmet", []),
		"will_swear": bool(verdict.get("will_swear", false)),
		"partner": String(npc_id),
		"class": String(bond.get("bond", "")),
		"label": String(bond.get("label", "")),
		"outcome": String(row.get("outcome", "")),
	}


## ## The consent ledger for one npc, as a panel prints it.
##
## A pure read of `BrotherhoodOath.consent` — which is on the PLAYER's `module_data`,
## so it survives a save with no persistence of its own. Deliberately carries no
## standing value: the cost of a refusal is a line in the BOND's cause ledger, and
## printing a second copy of it here would be the ADR 0066 failure with a new name.
static func consent_read(player: Actor, npc_id: StringName) -> Dictionary:
	if player == null:
		return {}
	return BrotherhoodOath.consent(player).row(npc_id).duplicate(true)
