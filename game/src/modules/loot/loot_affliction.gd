class_name LootAffliction
extends RefCounted

## What a boss INFICTS on the player, and which authored status it is.
##
## ## The defect this file exists to close
##
## Every element ships a PAIR of statuses (twenty defs against a closed ten-name
## `StatusDef.MECHANICS` vocabulary), and ADR 0105's selector answers exactly ONE id per
## element: `on_landed_blow`, which only `CombatExchange._status_on_landing` ever asks.
## So the other member of seven pairs — `fire_pyre`, `metal_sunder`, `water_deluge`,
## `ice_shatter`, `lightning_surge`, `wind_spread`, `dark_wane` — had NO producer at all.
## They were reachable only from a test that called `StatusApi.apply` by hand, which is
## exactly the "the mechanic exists and nothing can reach it" shape the whole status
## catalogue was audited for.
##
## The two amplifiers made it worse than seven dead rows. `StatusApi._amplifier_gain` /
## `_amplifier_cap` (`api.gd:464-502`) count amplifiers present ON THE ACTOR, and with no
## producer for `fire_pyre` or `wind_spread` nothing ever put one there — so the whole
## amplifier CHANNEL was structurally inert in production while its arithmetic and its
## tests were green. That is why this file is a producer and not a refactor.
##
## ## Why a BOSS is the inflictor
##
## Not invention: ADR 0076 already made this the encounter's shape ("a boss can win"),
## and `CombatExchange._answer` is already the one place a boss acts on the player — it
## spends its share of the player's pool. A boss inflicting a status is the same sentence
## with the same subject; it is not a new system.
##
## The alternative inflictor — the player's own landed blow — is ADR 0105's rule and it is
## already paid. Re-pointing it would mean one blow inflicting both members of an element's
## pair, which would erase the pair as a choice.
##
## ## Why the boss names a STATUS ID and not an ELEMENT
##
## The boss is a `Dictionary` in `actor.module_data` (`loot_state.gd:613-653`) with no
## `affinities` and no `Actor`, so the strongest-affinity rule `CombatExchange._element_of`
## uses has nothing to read and could not break a pair's tie anyway: both members of a pair
## share the one element that rule can name. So `BossDef.affliction` is the id outright,
## which is the same authored-selector move `on_landed_blow` already makes.
##
## ## Why it is paid from `strike`, the verb a press already reaches
##
## Because that is the only honest place. `LootApi.strike` is the encounter's damage
## primitive and the one `loot` verb `CombatExchange.exchange` calls on every blow
## (`exchange.gd:88`) — so a producer bolted onto any other verb would be a producer
## nothing calls, which is the defect being fixed. A blow that lands in a boss's band is
## answered with that creature's authored affliction, which is what "a boss can act"
## (BL-0224) means taken one step past crit and pierce.
##
## ## Why the CHANCE and the POTENCY are arguments
##
## Both are the CALLER's, exactly as they are on `StatusApi.apply_cultivation` — "magnitude
## stays the CALLER'S potency — the same contract `apply` has, one layer up". `chance` is
## ADR 0087's gate resolved through the multiplicative resist formula, and potency is ADR
## 0088's `element_power_<e>` term. Both live in `combat_engine`, and reading either here
## would be a second cross-module edge (`loot -> combat_engine`) to reach one function, for
## a number this module has no use for. A value at or below `0.0` on `chance` is the CLOSED
## gate, which spends no draw at all, so it is answered here rather than at a roll that
## will not happen.
##
## ## Why COMBAT scope is required, and refused by name
##
## The load-bearing half of the boundary, for the reason `StatusApi.apply_cultivation`
## gives: a CULTIVATION def is a permanent blessing (`duration = -1.0`) the game PAYS OUT,
## and a boss handing one out would install `earth_bulwark` as a permanent debuff that
## ADR 0089's purge never touches, so it would outlive the fight that inflicted it.
## `TribulationBlessing` owns that half of the vocabulary; this verb refuses it.
##
## ## Every refusal is NAMED
##
## No actor, no authored id, an id the catalogue refuses, and a COMBAT-scope refusal are
## four different facts a balance pass needs to tell apart, so each has its own constant.
## An empty authored id is not among them: it is not a refusal, it is a boss nobody
## authored an affliction for, and it returns the SAME `{applied: false, id: ""}` the
## landed-blow report uses for an element nothing maps — an ordinary answer, not an error.

# --- refusal reasons. Named rather than inferred from an empty id. -------------------

const NO_ACTOR := &"no_actor"
const UNKNOWN_STATUS := &"the_authored_affliction_is_not_in_the_catalogue"
const NOT_COMBAT_SCOPE := &"not_combat_scope"
## ADR 0087's closed gate, refused here so a caller that resolved a chance of `0.0` never
## pays for a draw that cannot change the answer.
const CLOSED_GATE := &"closed_gate"

## The report shape every caller reads, and the one `LootApi.strike` hands on. Identical
## to `CombatExchange`'s landed-blow `status` report (`exchange.gd:266`) so a screen that
## already renders one renders the other without knowing which module produced it.
const APPLIED := &"applied"
const REFUSED := &"refused"


## The status id a live boss afflicts, as `StatusApi` names it, or `&""`.
##
## This is the READ half and it is deliberately permissive: it answers what the FROZEN
## boss record carries and nothing about whether the id means anything. A caller that
## wants the refusal reasons asks [method inflict]; one that only wants to show a fight
## screen what it is up against reads this and never has to interpret a refusal.
##
## `active` is the spawned-boss dictionary — `LootApi.summary(actor)["active"]` — passed
## in rather than read back through the facade, because this runs INSIDE `LootApi.strike`
## and a facade call from inside another facade's own state transition would normalize the
## same state a second time mid-write.
static func affliction_of(active: Dictionary) -> StringName:
	if active == null:
		return &""
	return StringName(active.get("affliction", ""))


## Inflict `active`'s boss authored affliction on `actor`. Returns the [constant APPLIED]
## report, never null and never a half-applied status.
static func inflict(
	actor: Actor, active: Dictionary, chance: float = 1.0, magnitude: float = 1.0
) -> Dictionary:
	var none := {APPLIED: false, &"id": "", &"reason": ""}
	if actor == null:
		return _refused(none, NO_ACTOR)
	var status_id := affliction_of(active)
	if status_id == &"":
		return none
	var def := StatusApi.definition(status_id)
	if def == null:
		return _refused(none, UNKNOWN_STATUS, status_id)
	if not def.is_combat_scope():
		# See the docblock: a permanent blessing reached through a boss would outlive the
		# fight, because ADR 0089's purge clears COMBAT scope and only COMBAT scope.
		return _refused(none, NOT_COMBAT_SCOPE, status_id)
	# ADR 0087's closed gate, answered before the apply so a refused gate spends no more
	# work than it does draws.
	if chance <= 0.0:
		return _refused(none, CLOSED_GATE, status_id)
	var applied := StatusApi.apply(actor, status_id, magnitude)
	return {
		APPLIED: bool(applied.get("ok", false)),
		&"id": String(status_id),
		&"reason": "" if bool(applied.get("ok", false)) else String(applied.get("reason", "")),
	}


static func _refused(
	none: Dictionary, reason: StringName, status_id: StringName = &""
) -> Dictionary:
	var out: Dictionary = none.duplicate()
	out[REFUSED] = String(reason)
	out[&"id"] = String(status_id)
	return out
