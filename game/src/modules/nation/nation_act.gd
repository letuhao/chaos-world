class_name NationAct
extends RefCounted

## **What a nation PROPOSES to do this period, and the only verbs it may ever name**
## (BL-0198).
##
## ## Why this is an internal script and not a `NationApi` method
##
## `NationApi` has exactly one slot left of ADR 0084's twelve-method cap, and a
## facade that grows past its cap is the ISP failure `tools/arch/rules.py` fails the
## build for. Spending the last slot on a verb a background tick calls once a period
## — while the same reasoning put `SectApi.act` in `sect_act.gd` because that facade
## was already full — would leave the two tiers shaped differently for no reason a
## caller could see.
##
## So both tiers propose through a component, and `NationApi` keeps its slot free.
## `app/institution_resolver.gd` is the one place that calls either.
##
## ## Propose, never resolve
##
## The institution module **proposes**; `app/` **resolves**. This is ADR 0085's rule
## applied one layer up — "the conflict module never calls combat, never reads a
## combat stat, and never owns an `rng`" — and ADR 0114's handler shape: a handler
## never mutates, it returns a proposal, and the director applies. Nothing here
## writes a ledger, moves a claim or declares a war; it names the verb and the ids,
## and the resolver calls the verb that does the work.
##
## ADR 0085 also decides which verbs are even reachable: **a clock may not choose a
## war.** `declare_war` fixes a prize up front and `resolve_conflict` counts verdicts
## already decided in combat, so neither is a thing elapsed time may propose — only a
## caller with an opinion to state and a prize to declare. `claim_territory` and
## `accrue_territory` are the two verbs that describe the polity's own housekeeping
## and own no number the module did not already author.
##
## ## No `rng`, no `randi`, no `RandomNumberGenerator`, no seed
##
## The choice is a pure function of the ledger. Candidates are ordered by
## `(act_priority, institution_id)` and `institution_id` is a `StringName`, so the
## second key is lexicographic and **total** — two candidates cannot compare equal on
## both keys unless they are the same polity, so ties are impossible BY CONSTRUCTION
## and no tie-break rule and no generator exist. ADR 0102's "there is no tie-break
## rule and no seeded generator to break one", stated as the design rather than as an
## absence.
##
## ## The cap is a COUNT read from `InstitutionBudget`, never a multiplier
##
## The tier buys FREQUENCY of action and never SIZE of effect: nothing below scales a
## verb, a yield or a period by a cap (ADR 0097's refusal, ADR 0050's second-ladder
## rule). A `for` over an array sized by the candidate list and a `break` on the cap
## is the shape `test_no_unbounded_wait.gd` accepts, and there is no `while` anywhere
## on this path.

## The closed intent set, and **the only names this file may ever produce**. A sect
## proposes through `SectAct`; neither module ever names a verb the other owns,
## because ADR 0083 makes the tiers peers rather than a containment tree.
const VERB_ACCRUE := "accrue_territory"
const VERB_CLAIM := "claim_territory"

const VERBS: Array[StringName] = [VERB_ACCRUE, VERB_CLAIM]


## Whether `verb` is one a nation may propose. An unknown name refuses closed rather
## than defaulting, because a default branch in the resolver would silently execute a
## different verb than the one the module named.
static func is_verb(verb: StringName) -> bool:
	return VERBS.has(verb)


## `act` with nothing to propose: `ok: true` and `acted: 0`. **A silent period is an
## ordinary outcome, not a refusal** — returning `ok: false` would make a quiet world
## look broken to every caller reading the flag.
static func empty(periods: int, tier: StringName, cap: int) -> Dictionary:
	return report(periods, tier, cap, [])


## The `act` success shape: `{ok, periods, tier, acted, intents, cap}`.
##
## `acted` is a COUNT so a caller can assert the budget was respected rather than
## trusting it — `SocialApi.tick`'s contract ("returns the number of bonds that
## actually moved, so a caller can assert the tick is bounded") applied to an
## institution budget instead of a decay. `cap` is carried beside it so a caller can
## check the bound it was promised without knowing what the shipped `.tres` says.
static func report(
	periods: int, tier: StringName, cap: int, intents: Array[Dictionary]
) -> Dictionary:
	return {
		"ok": true,
		"reason": "",
		"periods": periods,
		"tier": String(tier),
		"acted": intents.size(),
		"intents": intents,
		"cap": cap,
	}


## A refusal, and **nothing written** — nothing here ever called a verb, so a refused
## decision cannot have touched a ledger (ADR 0044).
static func refuse(reason: String, detail: String) -> Dictionary:
	return {"ok": false, "reason": reason, "detail": detail, "acted": 0, "intents": []}


## What this polity proposes for `periods` at `tier`.
##
## ## Every branch is a refusal that names itself
##
## `no_actor` is the only `ok: false`. `unknown_tier` is deliberately its own reason
## rather than a silent fallback to `near`: a caller inventing a tier should fail
## loudly instead of quietly spending somebody else's budget. `periods <= 0` and an
## unfounded ledger are `ok: true, acted: 0` — a frame in which the world did not
## move, and a polity that lives under no nation, which is ADR 0083's first state
## rather than a failure.
static func propose(
	actor: Actor, periods: int, tier: StringName = &"near", budget: InstitutionBudget = null
) -> Dictionary:
	if actor == null:
		return NationState.refuse(NationState.R_NO_ACTOR)
	var costs := budget if budget != null else InstitutionBudget.shipped()
	if costs == null or not costs.knows_tier(tier):
		return refuse("unknown_tier", String(tier))
	var cap := costs.cap_for(tier)
	if periods <= 0:
		return empty(periods, tier, cap)
	var ledger := NationState.normalize(
		actor.get_module_data(NationState.MODULE_KEY), NationCatalog.instance().known_ids()
	)
	if not NationState.founded(ledger):
		return empty(periods, tier, cap)
	var def := NationCatalog.instance().nation_definition(NationState.nation_id(ledger))
	# A tier whose cap is zero means "nobody at this distance acts", and the honest
	# report of that is `acted: 0` — never a fallback to a nearer tier, which would
	# make the cap decorative.
	if cap <= 0 or def == null:
		return empty(periods, tier, cap)
	var intent := _intent(ledger, def)
	if intent.is_empty():
		return empty(periods, tier, cap)
	return report(periods, tier, cap, [intent])


## The one intent this polity would act on this period.
##
## `accrue_territory` is the module's only per-period income and it is already
## clamped to `standing_cap` after the net, so it is the one verb a background tick
## may propose without inventing a number: there is **no arithmetic here at all**, and
## therefore nowhere for a magnitude ladder to hide (ADR 0050).
##
## ## Why holding ground and holding nothing propose DIFFERENT verbs
##
## `accrue_territory` settles claims **this polity holds**. A polity holding nothing
## has nothing to accrue, so proposing the verb anyway would be a proposal the
## resolver must refuse every period — a named refusal per period forever is a busy
## signal, not an honest one. So the branch is real: held ground pays, ground nobody
## holds is opened with a claim, and ground this polity already CONTESTS has nothing
## to do at all and is reported `do_nothing`.
##
## `claim_territory` reads take-or-challenge from the ledger, never from an argument,
## and refuses a claim the polity already holds as `territory_already_held` — which is
## why the held case is never proposed here.
static func _intent(ledger: Dictionary, def: NationDef) -> Dictionary:
	var nation_id := String(NationState.nation_id(ledger))
	var held := 0
	var contested := 0
	# One pass over the claims the ledger already holds. The bound is the dictionary
	# as it was handed in and the body mutates nothing, so this loop cannot grow what
	# it walks: the INC-0002 shape is structurally absent rather than guarded against.
	for territory_id in (ledger["claims"] as Dictionary).keys():
		var entry = (ledger["claims"] as Dictionary)[territory_id]
		if not (entry is Dictionary):
			continue
		var row := entry as Dictionary
		if String(row.get("holder_id", "")) == nation_id:
			held += 1
		if String(row.get("challenger_id", "")) == nation_id:
			contested += 1
	if held > 0:
		return {
			"verb": VERB_ACCRUE,
			"institution_id": nation_id,
			"institution_kind": "nation",
			"target": "",
			"act_priority": def.act_priority,
		}
	# Ground this polity CONTESTS is ground somebody ELSE holds, so opening a claim
	# over it again would propose a refusal. It is the one state with genuinely
	# nothing to do, and it is the only route to `do_nothing` here.
	if contested > 0:
		return {}
	return {
		"verb": VERB_CLAIM,
		"institution_id": nation_id,
		"institution_kind": "nation",
		"target": "",
		"act_priority": def.act_priority,
	}
