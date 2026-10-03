class_name SocialApi
extends RefCounted

## Public facade for the `social` module (ADR 0076). Other modules may reference ONLY
## this file (`api.gd`).
##
## **The player and every npc carry the identical social type.** There is no second
## relationship structure and no player-only branch, so an npc can be handed to a combat
## formula and the player to the same one, and both answer from the same ledger.
##
## **A relationship is a cause ledger, not a score.** The only writer of a bond's axes is
## an authored `SocialCauseDef`; the class is derived, never stored. So "why do these two
## hate each other" survives a save, and gift-spamming a merchant cannot buy a friend.
##
## **Gates read the ledger, never a stat.** A stat can be satisfied by an item, so a gate
## that read one would be a gate the player could buy (ADR 0062's rule, applied here).

## The `actor.components` slot holding the ledger.
const STATE_COMPONENT := SocialProvider.STATE_COMPONENT
## The `actor.module_data` key the versioned ledger persists under.
const MODULE_KEY := SocialState.MODULE_KEY

const _PROVIDER_COMPONENT := &"social_provider"


## Attach the module to `actor`: restore any ledger a prior `Actor.from_dict` carried,
## normalize it, expose it as the state component and register the provider. Idempotent,
## and safe on an actor that has met nobody.
static func attach(actor: Actor) -> void:
	if actor == null:
		return
	var provider := actor.component(_PROVIDER_COMPONENT) as SocialProvider
	if provider == null:
		provider = SocialProvider.new()
		actor.set_component(_PROVIDER_COMPONENT, provider)
		actor.stats.add_provider(provider)
	var state := social_state(actor)
	actor.set_component(STATE_COMPONENT, state)
	if not state.changed.is_connected(actor.mark_stats_dirty):
		state.changed.connect(actor.mark_stats_dirty)


## The actor's ledger, restoring one from `module_data` on first read.
static func social_state(actor: Actor) -> SocialState:
	if actor == null:
		return null
	var state := actor.component(STATE_COMPONENT) as SocialState
	if state != null:
		return state
	state = SocialState.from_dict(actor.get_module_data(MODULE_KEY))
	actor.set_component(STATE_COMPONENT, state)
	return state


## Apply an authored cause to the bond between `actor` and `partner_id`.
## Returns `{ok, reason}`; an unknown cause is refused rather than silently moving nothing.
##
## **`partner_id` is an INSTITUTION id as often as it is a person.** A sect, a nation or
## a clan is a legal partner (`SocialBond.partner_id` is a `StringName` and this call
## performs no actor-identity check), and a cause marked `SocialCauseDef.institutional`
## is what makes the row an entry in `SocialState.regard`. That is the whole of BL-0200:
## sect and nation membership moves regard through THIS call, so no module keeps a second
## number and no cause is a raw write (ADR 0091).
##
## The mirror is left to the caller's transaction, not written here: a bond is a fact
## between two actors, and the module that owns an interaction (combat, a gift, an oath)
## is the one that knows whether the other party felt it. Writing both directions from one
## call is how a merchant ends up grateful for a gift they never received.
static func apply_cause(
	actor: Actor, partner_id: StringName, cause_id: StringName, scale: float = 1.0
) -> Dictionary:
	if actor == null or partner_id == &"":
		return {"ok": false, "reason": "no_partner"}
	var cause := SocialCauseCatalog.instance().cause_definition(cause_id)
	if cause == null:
		return {"ok": false, "reason": "unknown_cause"}
	var state := social_state(actor)
	if state == null:
		return {"ok": false, "reason": "no_social_state"}
	state.ensure_bond(partner_id).apply(cause, scale)
	state.mark_changed()
	return {"ok": true, "reason": ""}


## Move every bond's transient part toward its floor. Call from the same tick that drives
## `Actor.tick_statuses`. Returns the number of bonds that actually moved, so a caller can
## assert the tick is bounded rather than trusting it.
static func tick(actor: Actor, delta: float) -> int:
	var state := social_state(actor)
	if state == null or delta <= 0.0:
		return 0
	var moved := 0
	for partner_id in state.partner_ids():
		var bond := state.bond(partner_id)
		if bond == null:
			continue
		var before := bond.standing
		bond.decay(delta)
		if not is_equal_approx(before, bond.standing):
			moved += 1
	if moved > 0:
		state.mark_changed()
	return moved


## The full primitive snapshot of one bond, for a panel or a gate that wants one call.
## `present` is false and every axis is zero when the two have never met.
static func bond_entry(actor: Actor, partner_id: StringName) -> Dictionary:
	var state := social_state(actor)
	var bond := state.bond(partner_id) if state != null else null
	if bond == null:
		return {
			"present": false,
			"partner": String(partner_id),
			"bond": SocialBondClass.STRANGER,
			"label": SocialBondClass.label(SocialBondClass.STRANGER),
			"standing": 0.0,
			"trust": 0.0,
			"causes": [],
			"last_cause": "",
		}
	return {
		"present": true,
		"partner": String(partner_id),
		"bond": String(bond.bond_class()),
		"label": SocialBondClass.label(bond.bond_class()),
		"standing": bond.standing,
		"trust": bond.trust,
		"causes": _sorted_cause_ids(bond),
		"last_cause": String(bond.last_cause),
	}


## Evaluate an authored requirement against the ledger. `{ok, reason, unmet}` — the same
## shape the race gate returns, so a panel renders a reason it did not have to invent.
static func gate(actor: Actor, requirement: Dictionary) -> Dictionary:
	return SocialGate.evaluate(social_state(actor), requirement)


## How well this actor is regarded, aggregated. The single number a karmic gate reads.
static func reputation(actor: Actor) -> float:
	if actor == null:
		return 0.0
	return actor.stats.derived(SocialStats.REPUTATION)


## The whole read model for a social panel: the three stats, every bond, and the standing
## with each institution. `{}` when there is no actor, which is the contract a panel tests
## instead of pixels.
##
## `regard` is keyed by INSTITUTION id and is derived from the institutional bonds, so
## `bond_entry(actor, sect_id)["standing"]` and `regard[sect_id]` are the same number by
## construction rather than by two writers agreeing to.
static func summary(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var state := social_state(actor)
	var bonds: Dictionary = {}
	for partner_id in state.partner_ids():
		bonds[String(partner_id)] = bond_entry(actor, partner_id)
	return {
		"actor_id": String(actor.id),
		"reputation": actor.stats.derived(SocialStats.REPUTATION),
		"trust": actor.stats.derived(SocialStats.TRUST),
		"reach": actor.stats.derived(SocialStats.REACH),
		"bond_count": state.bond_count(),
		"bonds": bonds,
		"regard": state.regard.duplicate(),
	}


## The ledger exactly as it persists, after folding the live state back into
## `module_data`. The payload a save carries, so a caller never reaches into
## `actor.module_data` — the same contract `RaceApi.state` holds to.
static func state(actor: Actor) -> Dictionary:
	if actor == null:
		return SocialState.empty()
	var ledger := social_state(actor)
	if ledger == null:
		return SocialState.empty()
	actor.set_module_data(MODULE_KEY, ledger.to_dict())
	return ledger.to_dict()


## Forget a bond entirely, for a retired npc. Returns false when they were never met.
static func forget(actor: Actor, partner_id: StringName) -> bool:
	var state := social_state(actor)
	if state == null:
		return false
	return state.forget(partner_id)


static func _sorted_cause_ids(bond: SocialBond) -> Array:
	var out: Array = []
	for key in bond.causes.keys():
		out.append(String(key))
	out.sort()
	return out
