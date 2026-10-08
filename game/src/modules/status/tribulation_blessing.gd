class_name TribulationBlessing
extends RefCounted

## Who is ENTITLED to a permanent cultivation blessing, and which authored def carries it.
##
## ## The reachability defect this file exists to close
##
## `earth_bulwark`, `light_halo` and `wood_bloom` are `scope = cultivation`,
## `duration = -1.0` defs in `res://data/statuses/`, and ADR 0089 writes `DURATION_FOREVER`
## out as the "restated as a duration a designer can author" for a CULTIVATION gift with no
## expiry. They were UNREACHABLE. `StatusApi.apply` had exactly one caller —
## `modules/combat/exchange.gd` — and that caller only ever asks `status_for_element`,
## which by ADR 0105 answers only an `on_landed_blow` id, and every such id is COMBAT
## scope. So three authored defs had no producer and no path could ever apply them.
##
## ## Why a SURVIVED TRIBULATION is the honest payer
##
## Two independent facts say so rather than invention. `core/tribulation.gd` already pays a
## permanent blessing for a survived fight (`_apply_rewards`, `tribulation.gd:341-352`) —
## core's OWN reward table, the closest existing precedent in the repo for "a permanent
## blessing paid for something", and one that already reaches `Actor.add_status`. And ADR
## 0089 names the trigger for promoting a status out of session-only: persistence becomes a
## decision *"once the catalogue ships (ADR 0090) and a cultivation outcome can read a status
## across a save — a burn that damages a dantian, a blessing that persists"*. A survived
## tribulation IS a cultivation outcome and a blessing that persists IS the second clause,
## so ADR 0089's own trigger has fired.
##
## ## Why the TRIAL TYPE chooses the element, and not the spirit root
##
## The obvious alternative was ADR 0075's spirit-root affinity — the strongest affinity on
## the actor picks the element, reusing `CombatExchange._element_of`'s rule. That was
## rejected for two measured reasons. It couples the reward to the ACTOR (`actor.affinities`,
## a value the player builds), so two players surviving the same trial would earn different
## blessings, and a blessing is a reward for an EVENT. And it puts a combat-shaped read in a
## module with no edge to it: `_element_of` lives in `combat`, `status` declares `core` +
## `contracts` alone, and a bare cross-module call is an edge `tools arch` cannot see
## (AGENTS.md:140). The trial type is core's OWN authored rating — ADR 0050 makes difficulty
## "Tribulation's OWN rating, not a read of any shared power scale" — so keying on it keeps
## the reward a function of the event, of authored numbers core already owns, and of nothing
## the player happens to have trained.
##
## ## Why the REST of the pair is refused BY NAME
##
## Every element ships TWO defs plus, where the pair's second member is not already the
## blessing, a THIRD cultivation def (twenty-seven defs: the closed pair content plus
## the ten blessings — ADR 0920). The blessing is taken off the element by SCOPE — the
## CULTIVATION-scope member is what a fight or a cleared domain can pay — so a fight
## never hands out a burn AND its brace for one survived bout.
##
## An element with no CULTIVATION-scope def pays nothing. That is a NORMAL answer with a
## named reason, never a guess. Since ADR 0920 all ten elements ship one, so the
## refusal is a broken-authoring case rather than a shipped state; it is kept because a
## row pointed at an element nobody authored a blessing for must still SAY SO.

# --- the six authored trial types ------------------------------------------------

## One row per authored `Tribulation.TYPE_PRESSURE` entry, `type -> element`. The type
## chooses the ELEMENT and the element's CULTIVATION-scope def is the blessing, so this
## table is six authored numbers rather than twenty-seven.
##
## Together with [constant DOMAIN_TABLE] this covers all TEN elements: the rows pay
## metal, wood, ice, dark, earth and lightning, and the six elemental domains pay fire,
## water, wind, earth, lightning and light — so every element has at least one producer
## and no blessing is orphaned (asserted by `test_status_cultivation_reach.gd`).
const REWARD_TABLE: Dictionary = {
	Tribulation.LIGHTNING: &"lightning",
	Tribulation.HEART_DEMON: &"wood",
	Tribulation.KARMIC: &"earth",
	Tribulation.ELEMENTAL: &"metal",
	Tribulation.SPATIAL: &"ice",
	Tribulation.TEMPORAL: &"dark",
}

## One row per elemental DOMAIN, `domain -> element`: the SECOND producer (ADR 0920).
## A cleared elemental domain pays its element's blessing through [method award_domain],
## so the domains that already drop the element's mastery elixir also bless the body that
## survived them. Keyed by the domain id the run reports.
##
## Six domains cover six elements and the trial rows cover metal, wood, ice and dark, so
## every element has at least one producer and no element depends on one alone.
const DOMAIN_TABLE: Dictionary = {
	&"elemental_mortal_domain": &"fire",
	&"elemental_spirit_domain": &"water",
	&"elemental_immortal_domain": &"wind",
	&"elemental_earth_domain": &"earth",
	&"elemental_heaven_domain": &"lightning",
	&"elemental_transcendent_domain": &"light",
}

## The refusal reasons, named rather than inferred from an empty id. Every one is an
## ordinary state, and a caller that pays a status reports which.
const NO_SURVIVOR := &"not_a_survivor"
const NO_RECORD := &"no_tribulation"
const UNKNOWN_TYPE := &"unauthored_trial_type"
const UNKNOWN_DOMAIN := &"unknown_domain"
const NO_ACTOR := &"no_actor"
const NO_BLESSING := &"no_cultivation_blessing_for_element"
const NOT_APPLIED := &"LOC_STATUS_8B6951B755"
const ALREADY_REWARDED := &"already_rewarded"

## Marks a blessing already paid, WITHIN THIS SESSION.
##
## ## Why it does NOT ride `actor.module_data` (ADR 0186)
##
## It used to, and `module_data` IS serialized (`core/actor.gd:344`) and restored
## (`core/actor.gd:397-398`) — but `Actor.to_dict()` emits no `statuses` key (ADR 0089), so
## the guard survived a save the PERMANENT reward it was guarding did not. Save & reload and
## the actor was `ALREADY_REWARDED` on a blessing it no longer carried, which
## `core/tribulation.gd:156,193` would never re-open: a permanent reward silently deleted by
## an autosave and never re-earnable — the ADR 0140 wound defect under a status's name.
##
## `module_data` is the right home for a guard over something that ITSELF survives the save.
## A session-scoped guard is not that, and parking it there made it a persistent fact about a
## session-only reward. So it is session-only here: within one session a repeated observation of
## the same decided record still cannot double-pay (this marker plus the record's own `outcome`
## guard, ADR 0061); across a load the restored SURVIVED outcome is re-payable, which is what
## "nothing is silently lost" means.
const REWARDED_KEY := &"tribulation_blessing_paid"

## Session-only once-guard store, keyed by actor instance id.
##
## ## Why its OWN table rather than `StatusRuntime._by_actor`
##
## `StatusApi._prune` erases every runtime key whose status the actor no longer carries, so a
## marker parked in the runtime map would be swept the moment the blessing left the actor — the
## guard would evaporate with the thing it was guarding. This guard's lifetime is the ACTOR's
## (the session), not a status's, so it needs its own table.
##
## `WeakRef`-keyed through the actor's `get_instance_id()` exactly as `StatusRuntime` does, so a
## discarded actor does not pin itself: the map holds an id and a payload, never the actor.
static var _rewarded: Dictionary = {}


## Hand the blessing this actor's survived tribulation earned. Returns the
## `StatusApi.apply_cultivation` answer, or a named refusal — never null and never a
## half-applied status.
##
## ## Why it is called from the module that OBSERVES the decision
##
## Core's `Tribulation.apply_result` already pays essence, insight and `heavenly_blessing`,
## and it is once-guarded. This is NOT that award and does not touch it: core cannot name
## `StatusApi` (it declares `core` + `contracts`, and a catalogue id is authored content the
## status module owns). So the award is made where a fight is OBSERVED to be decided —
## `TribulationFight.fight_wave` — and paid at most once BECAUSE the record's own `outcome`
## guard means a decided fight cannot be re-decided, plus the session-only [constant
## REWARDED_KEY] marks the actor so a second observation of the same record cannot pay twice
## (ADR 0186).
static func award(actor: Actor) -> Dictionary:
	if actor == null:
		return _refused(NO_RECORD)
	if actor.tribulation == null:
		return _refused(NO_RECORD)
	if not actor.tribulation.survived():
		return _refused(NO_SURVIVOR)
	if _rewarded_this_session(actor):
		return _refused(ALREADY_REWARDED)
	var element := _reward_element(StringName(actor.tribulation.type))
	if element == &"":
		return _refused(UNKNOWN_TYPE)
	var status_id := blessing_for(element)
	if status_id == &"":
		return _refused(NO_BLESSING)
	var applied := StatusApi.apply_cultivation(actor, status_id, 1.0)
	if not bool(applied.get("ok", false)):
		applied["reason"] = NOT_APPLIED
		applied["id"] = status_id
		return applied
	_mark_rewarded(actor, status_id)
	return applied


## Hand the blessing a CLEARED elemental domain pays, keyed by the domain id (ADR 0920).
##
## No session once-guard here, unlike [method award]: the loot module's own rule E2
## refuses a re-entered cleared band, so a clear is already once-only — and a second BAND
## of the same domain re-paying is a REFRESH of the same permanent status, not a second
## blessing. The refusal reasons are named: `no_actor`, `unknown_domain`, `no_blessing`.
static func award_domain(actor: Actor, domain_id: StringName) -> Dictionary:
	if actor == null:
		return _refused(NO_ACTOR)
	var element := StringName(DOMAIN_TABLE.get(domain_id, &""))
	if element == &"":
		return _refused(UNKNOWN_DOMAIN)
	var status_id := blessing_for(element)
	if status_id == &"":
		return _refused(NO_BLESSING)
	var applied := StatusApi.apply_cultivation(actor, status_id, 1.0)
	if not bool(applied.get("ok", false)):
		applied["reason"] = NOT_APPLIED
		applied["id"] = status_id
		return applied
	return applied


## Whether this actor's blessing was already paid, WITHIN THIS SESSION.
##
## ## Why the lookup is on the actor and not on the record
##
## The guard has to survive the blessing LEAVING the actor — it is what stops a second
## observation of the same decided record from paying again — so it is keyed by the actor, which
## outlives any one status on it. A guard keyed by the status id would be erased by the same
## `_prune` that drops the runtime, and the next observation would pay a second time.
static func _rewarded_this_session(actor: Actor) -> bool:
	return _rewarded.has(actor.get_instance_id())


## Mark this actor's blessing paid for the rest of the session.
##
## `status_id` is recorded so a caller reading the session store can tell WHAT was paid; it is
## session scratch, never written to a payload, and so never reaches a save (`Actor.to_dict`
## reaches neither this table nor `StatusRuntime`'s, ADR 0089).
static func _mark_rewarded(actor: Actor, status_id: StringName) -> void:
	_rewarded[actor.get_instance_id()] = {"status_id": String(status_id)}


## Forget an actor's once-guard. Called by the composition root when an actor leaves the
## session, exactly as [method StatusRuntime.forget] releases that actor's live records — an
## actor discarded and re-entered is a NEW session for its rewards, and a stale marker would
## refuse a blessing the player has not yet earned on the re-entered actor.
static func forget(actor: Actor) -> void:
	if actor != null:
		_rewarded.erase(actor.get_instance_id())


## The authored CULTIVATION-scope status on `element`, or `&""` when it ships none.
##
## Read off the CATALOGUE rather than a restated id list, so a `.tres` that is refused at
## load cannot be handed out here: `StatusApi.status_ids()` only ever returns what
## `StatusDef.problems()` admitted. The scope filter is `!is_combat_scope()` — the same
## axis `StatusApi.apply_cultivation` enforces — so this and the verb can never disagree
## about which def is the blessing.
static func blessing_for(element: StringName) -> StringName:
	if element == &"":
		return &""
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		if def != null and def.element == element and not def.is_combat_scope():
			return status_id
	return &""


## The element this trial type pays out, or `&""` for a type nothing authored.
##
## An unrecognised type is refused rather than defaulted: the table is CLOSED, and a typo
## inheriting a neighbouring row is the "free heavenly tribulation" mistake
## `Tribulation._pressure` already refuses for its own table.
static func _reward_element(trial_type: StringName) -> StringName:
	if not REWARD_TABLE.has(trial_type):
		return &""
	return REWARD_TABLE[trial_type] as StringName


static func _refused(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": String(reason), "id": ""}
