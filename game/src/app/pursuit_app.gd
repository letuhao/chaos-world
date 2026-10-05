class_name PursuitApp
extends RefCounted

## **The verb a player presses, and the boot seam that makes pursuit real** (ADR 0256).
##
## ## Why this is in `app/` and not on either facade
##
## `NpcApi` publishes exactly twelve public methods and `SocialApi` sits at its cap, so
## **neither may grow a thirteenth** — `tools arch` fails the build on it
## (`rules.MAX_FACADE_PUBLIC_METHODS`). And a pursuit verb needs BOTH modules: it resolves
## the npc's `Actor` through `NpcApi`, writes their own `PursuitLedger`, and applies
## authored causes through `SocialApi`. `social/` declares `["contracts", "core", "economy",
## "items"]` and may not name `npc/`; `npc/` declares `social` for exactly one verb and
## must not name a pursuit file either.
##
## So the only legal home is the layer exempt from the graph — `LAYER_DEPS["app"] ==
## {"*"}` — which is exactly the `BrotherhoodOathApp` precedent (ADR 0196) and the
## `SoulArrivalMarks` shape (ADR 0190). **This file keeps no ledger, no roster and no
## cache**: the NPC's disposition lives on the NPC's own `module_data` and the regard
## lives on the bond, so this is wiring and translation and nothing else.
##
## ## And no facade grew, so no peer was collided with
##
## Everything here is a static function on a plain `RefCounted`. `SocialApi` is untouched
## at 12/12 and `NpcApi` is untouched at 12/12; the pursuit read model is reached through
## `PursuitStance`, a collaborator in `social/`, which is ADR 0196's shape rather than a
## thirteenth verb.


## ## Every cause id this verb can apply, sorted — the vocabulary a content audit reads
## to answer "is anything unwired here", pinned by
## `tests/modules/social/test_pursuit.gd` against the authored catalog so a bridge built on
## an unauthored id fails at test time rather than refusing silently at play time.
static func cause_ids() -> Array[StringName]:
	var out: Array[StringName] = [
		PursuitClaim.CAUSE_ACCEPTED,
		PursuitClaim.CAUSE_PLEDGED,
		PursuitClaim.CAUSE_REFUSED,
	]
	out.sort()
	return out


## ## Seed the impression when the player first meets `npc_id`, and return the word.
##
## ## THE MEETING HOOK, and it is idempotent by construction
##
## `SocialAttractionSeed.apply_once` refuses to write when a seed exists, so this can be
## called from any meeting path, any number of times, for any NPC — **including a
## transient one that will be a different individual next visit**, which costs exactly one
## dictionary row and is forgotten with them. That is how "costs nothing when unobserved"
## is kept honest: the composition is lazy (ADR 0173(c)) and the row dies with the npc.
##
## `player_row` is the projection the seed is allowed to read: `race_tags`,
## `bloodline_tags`, `clan_standing`, `sect_tags`. Passing a wider dictionary is safe —
## the seed ignores everything not on `SocialAttractionSeed.READ_KEYS`.
static func meet(player: Actor, npc_id: StringName, player_row: Dictionary = {}) -> Dictionary:
	var npc := NpcApi.resident(npc_id)
	if npc == null:
		return {"ok": false, "reason": "unknown_npc", "word": ""}
	var key := PursuitApp.bond_key(npc)
	var seeded := SocialAttractionSeed.apply_once(npc, player, player_row, {"npc": String(npc_id)})
	return {
		"ok": true,
		"applied": bool(seeded.get("applied", false)),
		"reason": String(seeded.get("reason", "")),
		"word": String(SocialAttractionSeed.word(npc, player)),
		"partner": String(npc_id),
		"key": String(key),
	}


## ## The NPC's whole pursuit read for `npc_id`, as the player may see it.
##
## ## THE PLAYER-FACING CONTRACT, and it is the word-only one
##
## Returns `{word, actions, may_court, reason, numbers}` where **`numbers` is `{}` unless
## `debug` is passed explicitly** — the full debug read hidden by default behind a user
## setting (decision 3). Every other key is a `String`, a `bool` or an array of
## `StringName`, so a panel can render this and **no float reaches it**.
static func read(player: Actor, npc_id: StringName, debug: bool = false) -> Dictionary:
	var npc := NpcApi.resident(npc_id)
	if npc == null:
		return {
			"word": "",
			"actions": [] as Array[StringName],
			"may_court": false,
			"reason": "unknown_npc",
			"numbers": {},
		}
	return PursuitStance.read(npc, player, PursuitApp.bond_key(npc), debug)


## ## The verb: an NPC makes a claim, and the player answers it.
##
## Two beats, exactly as `BrotherhoodOathApp.offer` has two beats. Returns
## `{ok, outcome, cost, word}` on an answer, or `{ok: false, reason, unmet}` when the act
## was refused before it started. **A refusal of the ACT names its reason and writes
## nothing; a refusal of the ANSWER is what costs.**
static func offer_claim(player: Actor, npc_id: StringName) -> Dictionary:
	var npc := NpcApi.resident(npc_id)
	if npc == null:
		return {"ok": false, "reason": "unknown_npc", "unmet": []}
	var key := PursuitApp.bond_key(npc)
	var offered := PursuitClaim.offer_claim(npc, player.id, key)
	if not bool(offered.get("ok", false)):
		return offered
	var answered := PursuitClaim.answer_claim(npc, player, key)
	answered["offered"] = true
	return answered


## ## Whether the player may answer a claim from `npc_id` right now.
##
## `{ok, reason, will_accept, word}` — `will_accept` is published so an affordance can
## say "asking now would be declined" BEFORE the player commits, which is what makes a
## refusal a decision rather than a gotcha.
static func eligibility(player: Actor, npc_id: StringName) -> Dictionary:
	var npc := NpcApi.resident(npc_id)
	if npc == null:
		return {"ok": false, "reason": "unknown_npc", "will_accept": false, "word": ""}
	return PursuitClaim.eligibility(npc, player, PursuitApp.bond_key(npc))


## ## Compose a stance for an UNTRACKED npc at the moment of interaction.
##
## **The transient path, and the reason it is cheap.** `PursuitStance.compose_transient`
## reads, returns the word and the repertoire, and — for `transient` — writes NOTHING.
## There is no row to leave behind, so an unobserved transient's interest is not merely
## free but genuinely absent, which is stronger than a row nobody reads.
static func compose(
	player: Actor, npc_id: StringName, tier: StringName, debug: bool = false
) -> Dictionary:
	var npc := NpcApi.resident(npc_id)
	if npc == null:
		return {
			"word": "",
			"actions": [] as Array[StringName],
			"may_court": false,
			"reason": "unknown_npc",
			"numbers": {},
		}
	return PursuitStance.compose_transient(npc, player, PursuitApp.bond_key(npc), tier, debug)


## ## The key the MIRROR side of every pursuit row is written under.
##
## ## Why this is not simply `npc.id`
##
## An npc's ledger is keyed by whoever stands on the other side of it, and for another npc
## that id is the DEF id, not the actor id the minter minted (`npc_elder_wei`). This is
## `BrotherhoodOath.bond_key`'s rule verbatim, and it is reached here rather than
## re-derived because a second resolution is a second thing to drift.
static func bond_key(npc: Actor) -> StringName:
	return BrotherhoodOath.bond_key(npc)


## ## The projection the seed reads, built from whatever the caller can supply.
##
## **A pure assembler with no knowledge of any module's types**, so this file needs no
## dependency it does not have and a caller can hand it a partial projection without the
## seed refusing. Keys not on `SocialAttractionSeed.READ_KEYS` are ignored by the seed, so
## this function passing extra keys is safe by construction.
static func player_projection(
	race_tags: Array = [],
	bloodline_tags: Array = [],
	clan_standing: float = 0.0,
	sect_tags: Array = []
) -> Dictionary:
	return {
		"race_tags": race_tags,
		"bloodline_tags": bloodline_tags,
		"clan_standing": clan_standing,
		"sect_tags": sect_tags,
	}
