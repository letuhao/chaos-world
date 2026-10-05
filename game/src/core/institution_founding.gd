class_name InstitutionFounding
extends RefCounted

## The one place an institution comes into being, for ANY kind: it reads the authored
## cost, seats the founder in the top authored position, and opens the obligation
## lines. A kind-agnostic generalization of `sect_founding.gd`, which is READ ONLY
## until the sect migration.
##
## ## The tier supplies a PROFILE; doctrine / fit / teach are OPTIONAL CAPABILITIES
##
## `core/` may not name a module, so this file cannot ask a `SectDef` for its
## founding cost or a `SectDoctrineDef` for its floor. It asks a **profile** instead:
## a plain `Dictionary` of primitives the tier assembles from its own defs and hands
## in. That is the same injection seam `WorldFact` uses for its post-write hook
## ("the slot is a `Callable` and the composition root fills it"), and the reason it
## is a plain `Dictionary` rather than a new `Resource` is that a profile is a
## transient argument, never authored content and never part of a save.
##
## Which capabilities are consulted is decided by the REGISTRY, not by the profile:
##
##   - `has_offices` — the kind authors positions, so the founder is seated in the
##     top one. **A kind without it is refused `no_top_position`**, because a profile
##     naming a position a kind does not author is a content bug, not a no-op.
##   - `teaches` — the kind HAS a fit axis. Absent, and the ledger gets **no `fit`
##     key at all**: a kind without transmission has no fit axis, which is a
##     legitimate authored state (ADR 0084: fit is a GATE that projects zero stat
##     modifiers) and must not read as a `fit: 0` that looks like a broken gate.
##   - `is_born_to` — the kind is INHERITED, so it cannot be founded by an actor at
##     all. This flag is the only place that answer is written; a second
##     `can_found` flag could disagree with it, and two flags that can disagree are
##     the ADR 0066 failure mode.
##
## ## A treasury is a LEDGER OF OBLIGATION LINES ON IDS, never a pile of items
##
## Founding is the only verb that opens a treasury, and `items` stays the sole
## authority on what anything owns. A treasury that duplicated an inventory would be
## two sources of truth for the same fact. A line is an id and a count, so retuning a
## rate never rewrites a save.
##
## ## Founding is NOT free, and it is NOT a clock
##
## An authored `founding_cost` is read from the profile against the funding pool the
## profile names, and a shortfall is `founding_cost_unmet`. **Nothing here reads
## `Time.get_ticks*`, declares `_process`, or calls `get_tree()`** — every accrual
## takes an explicit `periods` from a caller that owns time (DEF-0111, ADR 0083).
## A ledger whose contents depended on when the save was written is not a ledger.
##
## ## A REFUSED `found` WRITES NOTHING, and that is structural rather than promised
##
## Every refusal returns **above** the point at which the pool is touched and the
## ledger is built, so there is no branch on which a refused verb has already moved a
## number. ADR 0044 is therefore a property of the control flow and not a discipline
## each caller must remember — which matters because the callers are module facades
## written by different sessions.

## The pool a founder funds an institution from when the profile names none. Namespaced
## so it is visibly the institution's own money and can never be confused with
## `health`, `stamina` or any pool an item granted.
const DEFAULT_FUNDING_POOL := &"institution_founding_funds"
## What founding starts a treasury with, in periods. An opening balance is a STARTING
## STATE rather than a grant: the institution owes the world nothing on day one and
## everybody in them something from the day they walk in.
const TREASURY_OPENING_PERIODS := 1
## This file's own ledger version. **Not shared with any other ledger** — four
## ledgers have four migration histories, and one constant would make a schema bump
## in one silently re-stamp the others (`InstitutionLedger` records the full
## reasoning).

## The refusals, ALIASED from `InstitutionLedger` rather than restated.
##
## **Strings and not an `enum`**, because every one of these crosses a facade as a `String`
## and is written into a ledger, a signal and a history record; an enum ordinal in any of
## those places would be a number that changes meaning the moment somebody reorders a file
## (`sect_founding.gd` states the same reason for its own six).
##
## The first version wrote all seven strings out again, which is the ADR 0066 failure mode
## inside the file that exists to stop it: `InstitutionLedger` already owns this exact
## vocabulary, so a reason renamed in one place and not the other leaves a panel rendering
## a string no gate ever returns. These are the SAME constants under a second name, so a
## caller writing `InstitutionFounding.R_NO_TOP_POSITION` and a caller writing
## `InstitutionLedger.R_NO_TOP_POSITION` are holding one value.
const R_NO_ACTOR := InstitutionLedger.R_NO_ACTOR
const R_UNKNOWN_KIND := InstitutionLedger.R_UNKNOWN_KIND
const R_KIND_CANNOT_BE_FOUNDED := InstitutionLedger.R_KIND_CANNOT_BE_FOUNDED
const R_UNKNOWN_INSTITUTION := InstitutionLedger.R_UNKNOWN_INSTITUTION
const R_ALREADY_FOUNDED := InstitutionLedger.R_ALREADY_FOUNDED
const R_NO_TOP_POSITION := InstitutionLedger.R_NO_TOP_POSITION
const R_FOUNDING_COST_UNMET := InstitutionLedger.R_FOUNDING_COST_UNMET

## This file's own ledger version. **Not shared with any other ledger** — four ledgers
## have four migration histories, and one constant would make a schema bump in one
## silently re-stamp the others (`InstitutionLedger` records the full reasoning).
const LEDGER_VERSION := 1

## Every refusal this verb can return, keyed by the name it is written with, so a caller
## can look one up without holding a constant. The SAME TABLE the ledger publishes — not a
## second one filtered to this file's seven, which is a list that has to be kept in step.
const REASONS := InstitutionLedger.REASONS


## Whether `ledger` already names an institution.
##
## `found` is the only verb that may write one, and an actor may found exactly one
## institution: the tiers are peers, not a containment tree (ADR 0083), so founding
## twice is leaving and then founding.
static func founded(ledger: Dictionary) -> bool:
	return InstitutionLedger.text(ledger.get("institution", ""), "") != ""


## What founding one costs, from the profile: `{outstanding, pool}`.
##
## An authored cost with no `outstanding` is a cost nothing has to pay, which is a
## deliberate way to author a free institution rather than an accident this file has
## to guess about. A negative authored cost is clamped to zero, so a hand-edited
## profile cannot make a price pay its holder.
static func cost(profile: Dictionary) -> Dictionary:
	var authored = profile.get("founding_cost", 0)
	var amount := 0 if not (authored is int or authored is float) else int(authored)
	return {
		"outstanding": maxi(0, amount),
		"pool": _pool_id(profile),
	}


## The ledger a founding writes, or a refusal. Nothing outside this function writes
## an institution row, and a refusal writes NOTHING.
##
## The order of the refusals is the order a caller needs them in, and it is load
## bearing: every check comes **before** the pool is touched, so a refusal at any
## step leaves the actor byte-for-byte as found (ADR 0044).
##
## `registry` is INJECTED rather than reached for globally. A global would make this
## verb's answer depend on read order — which kinds exist is a fact about one boot,
## and `InstitutionRegistry` is an instance for exactly that reason.
static func found(
	registry: InstitutionRegistry,
	actor: Actor,
	profile: Dictionary,
	founder_id: String,
	ledger: Dictionary = {}
) -> Dictionary:
	if actor == null:
		return InstitutionLedger.refuse(R_NO_ACTOR)
	if registry == null:
		return InstitutionLedger.refuse(R_UNKNOWN_KIND)
	var kind := StringName(InstitutionLedger.text(profile.get("kind", ""), ""))
	if not registry.knows(kind):
		return InstitutionLedger.refuse(R_UNKNOWN_KIND)
	if _has(registry, kind, InstitutionRegistry.CAP_IS_BORN_TO):
		return InstitutionLedger.refuse(R_KIND_CANNOT_BE_FOUNDED)
	var institution_id := InstitutionLedger.text(profile.get("institution_id", ""), "")
	if institution_id == "":
		return InstitutionLedger.refuse(R_UNKNOWN_INSTITUTION)
	if founded(ledger):
		return InstitutionLedger.refuse(R_ALREADY_FOUNDED)
	var top := InstitutionLedger.text(profile.get("top_position", ""), "")
	# ## The refusal that fires only for a kind that AUTHORS offices
	#
	# A kind without `has_offices` is refused `no_top_position`, and the reason is
	# that a profile naming a position a kind does not author is a content bug. A
	# kind without offices has no such bug to report and `top` is simply `""` — so
	# the founder holds thick standing in NO position at all, which is the state
	# ADR 0064's split exists to make expressible and is never an error.
	if _has(registry, kind, InstitutionRegistry.CAP_HAS_OFFICES) and top == "":
		return InstitutionLedger.refuse(R_NO_TOP_POSITION)
	var price := cost(profile)
	if not _can_pay(actor, price):
		return InstitutionLedger.refuse(R_FOUNDING_COST_UNMET)
	# Everything that can refuse has refused. Past this line the verb COMMITS, so
	# there is no ordering in which a refusal follows a write.
	_draw(actor, price)
	var written := write(registry, profile, founder_id, top)
	return (
		InstitutionLedger
		. ok(
			{
				"ledger": written,
				"kind": String(kind),
				"institution": institution_id,
				"position": top,
				"charged": int(price["outstanding"]),
			}
		)
	)


## The ledger a founding produces, built from a BLANK skeleton rather than from the
## caller's. A founded institution is a NEW claim: nothing about the caller's ledger
## survives into it, because a founder who carried a rival house's office into their
## own house would be seated in two institutions at once.
##
## `standing` comes from the profile's `founder_standing`, which the tier authors, and
## `position` from the profile's `top_position`. **Neither is derived from the other**
## (ADR 0064 carried forward by ADR 0083): a member may hold a high position on thin
## standing and may hold thick standing in no position at all, and that gap is the
## whole politics layer. `test_institution_foundation.gd` asserts a promotion does not
## move standing and a standing change does not move position, in both directions.
static func write(
	registry: InstitutionRegistry,
	profile: Dictionary,
	founder_id: String,
	top_position: String = ""
) -> Dictionary:
	var kind := StringName(InstitutionLedger.text(profile.get("kind", ""), ""))
	var institution_id := InstitutionLedger.text(profile.get("institution_id", ""), "")
	# The CALLER'S top position wins when it names one — `found` resolved it against
	# the registry's `has_offices` flag and had already refused a content bug — and
	# the profile is the fallback for a direct call. Either way the two numbers below
	# are independent, which is the whole point.
	var top := (
		top_position
		if top_position != ""
		else InstitutionLedger.text(profile.get("top_position", ""), "")
	)
	var cap := _standing_cap(profile)
	var out := {
		"version": LEDGER_VERSION,
		"kind": String(kind),
		"institution": institution_id,
		"position": top,
		"standing": clampi(_founder_standing(profile), 0, cap),
		"standing_cap": cap,
		"founder_id": String(founder_id),
		"roster": _roster(top, founder_id),
		"treasury": _treasury(profile),
		"obligation": _obligation(profile, top),
	}
	# ## The fit axis is ABSENT for a kind that does not teach
	#
	# Not `fit: 0` and not an empty dictionary: **the key is not written at all**, so
	# "this kind has no transmission" is a state a reader can tell apart from "this
	# founder has taught nothing". ADR 0084's fit is a GATE projecting zero stat
	# modifiers, and a gate reading a zero it was handed would be a gate answering
	# from a default rather than from what the kind IS. A kind that teaches writes the
	# axis from the profile's own `fit` lines — the tier owns the points, because the
	# floor that caps them is a doctrine's and `core/` may not name a doctrine.
	if registry != null and _has(registry, kind, InstitutionRegistry.CAP_TEACHES):
		var fit := InstitutionLedger.positive_lines(profile.get("fit", {}) as Dictionary)
		if not fit.is_empty():
			out["fit"] = fit
	return out


## What this actor has put into the pool `price` names, read as a plain pool balance.
## Zero for an actor who funded nothing, which is the ordinary case and never an
## error — "this member has no founding fund" and "this member spent it all" are the
## same answer.
static func funds(actor: Actor, pool: StringName) -> float:
	if actor == null:
		return 0.0
	var held = actor.resource(pool)
	return 0.0 if held == null else float(held.current)


## Whether `actor` could pay the price [method cost] reports. The gate [method found]
## reads, published so a caller can show how far short a founder is rather than only
## that they were refused.
static func can_pay(actor: Actor, price: Dictionary) -> bool:
	var outstanding := int(price.get("outstanding", 0))
	if outstanding <= 0:
		return true
	return funds(actor, StringName(price.get("pool", ""))) >= float(outstanding)


## Whether `ledger` carries a fit axis at all — a different question from "has this
## member been taught anything", and the two are told apart by the KEY'S ABSENCE.
##
## A kind without the `teaches` capability has no fit axis, so [method write] does not
## write the key and this reads `false`. A kind that teaches but has granted nothing
## yet also reads `false`, because nothing was written — and the property that matters
## is that NEITHER is a `0` a gate would answer from.
static func has_fit_axis(ledger: Dictionary) -> bool:
	if not (ledger.get("fit", null) is Dictionary):
		return false
	return not (ledger["fit"] as Dictionary).is_empty()


## Take `amount` off `pool`. Zero-or-less takes nothing, so a settlement is never a
## negative accrual. No-op rather than an error for an actor with no pool at all: a
## member who never funded anything has nothing to take.
static func draw(actor: Actor, pool: StringName, amount: float) -> void:
	if actor == null or amount <= 0.0:
		return
	var held = actor.resource(pool)
	if held == null:
		return
	held.change(-amount)


# --- Internals ---------------------------------------------------------------


## Whether `registry` says `kind` carries `capability`. **A `has_capability` refusal
## answers `false`, never `true`**: an unknown kind can do nothing, and a registry
## that defaulted a missing kind to "yes" would let a profile invent an institution
## of a type nothing defines.
static func _has(registry: InstitutionRegistry, kind: StringName, capability: StringName) -> bool:
	return bool(registry.has_capability(kind, capability)["has"])


static func _pool_id(profile: Dictionary) -> StringName:
	var named := StringName(InstitutionLedger.text(profile.get("funding_pool", ""), ""))
	return DEFAULT_FUNDING_POOL if named == &"" else named


static func _can_pay(actor: Actor, price: Dictionary) -> bool:
	var outstanding := int(price["outstanding"])
	if outstanding <= 0:
		return true
	return funds(actor, StringName(price["pool"])) >= float(outstanding)


static func _draw(actor: Actor, price: Dictionary) -> void:
	var outstanding := int(price["outstanding"])
	if outstanding <= 0:
		return
	draw(actor, StringName(price["pool"]), float(outstanding))


## The authored standing cap, repaired to at least 1 for the reason
## `InstitutionClaim.from_dict` and `WorldPolityLedger._institution_row` repair it: a
## cap that cannot be computed would report a normalized ratio of zero and read as an
## institution nobody respects.
static func _standing_cap(profile: Dictionary) -> int:
	var authored = profile.get("standing_cap", 100)
	var cap := 100 if not (authored is int or authored is float) else int(authored)
	return maxi(1, cap)


## The standing a founder starts on, from the profile. **A named authored number and
## never a percent or a multiple of the cap**: founding PRICES an institution, so
## charging the founder again for standing inside their own house makes the price of
## existing an infinite regress — while a floor would make founding a demotion and a
## multiple would make it a grant, and ADR 0064's split says it is neither.
static func _founder_standing(profile: Dictionary) -> int:
	var authored = profile.get("founder_standing", 0)
	return 0 if not (authored is int or authored is float) else int(authored)


## The roster, keyed by position id. Plain actor-id **strings**: a `Resource` or an
## `Actor` in either place would reach the save untouched and no checker in this repo
## can see it. An empty top position yields an empty roster rather than a `"no
## position"` bucket, because a member who holds no position holds no position — that
## is the state, not a missing row (ADR 0083).
static func _roster(top_position: String, founder_id: String) -> Dictionary:
	var out: Dictionary = {}
	if top_position == "" or founder_id == "":
		return out
	out[top_position] = [String(founder_id)]
	return out


## The treasury lines founding opens, ids and counts only. The tier names them — a
## sect namespaces `treasury_<sect_id>_<what>` because its ledger belongs to a person
## and two institutions may both owe the same actor's save — so this file reads the
## profile's `treasury` and opens the opening line rather than inventing a spelling.
static func _treasury(profile: Dictionary) -> Dictionary:
	var out := InstitutionLedger.positive_lines(profile.get("treasury", {}) as Dictionary)
	# `"%shall"` would be `%s` applied to the literal `hall`, NOT `%s` then `all`:
	# GDScript reads the two-character verb and hands it the rest of the string. That
	# shipped a key named `treasury_t_house_hall`, a treasury line nothing can ask for.
	out["%sall" % _treasury_prefix(profile)] = TREASURY_OPENING_PERIODS
	return out


static func _treasury_prefix(profile: Dictionary) -> String:
	var institution_id := InstitutionLedger.text(profile.get("institution_id", ""), "")
	var authored := InstitutionLedger.text(profile.get("treasury_prefix", ""), "")
	if authored != "":
		return authored
	return "treasury_%s_" % institution_id if institution_id != "" else "treasury_"


## What the founder OWES to hold what they hold: the institution's own membership
## lines plus the top position's lines, merged by the LARGER count per term.
##
## The merge is `max`, not `sum`, and the reason is that a position's rate and the
## membership's rate are two authored statements about the SAME term, not two debts.
## Summing them would make a founder's cost depend on how the author split one number
## across two fields, which is a content edit with a mechanical cost.
static func _obligation(profile: Dictionary, top_position: String) -> Dictionary:
	var out := InstitutionLedger.positive_lines(profile.get("obligation", {}) as Dictionary)
	if top_position == "":
		return out
	var office := profile.get("office_obligation", {}) as Dictionary
	# A `for` over a SNAPSHOT of the sorted keys, writing into `out` and not into
	# `office`: the body reads `office` and never grows it, so there is no shape here
	# for a loop to test a size it is itself growing.
	for term_id in InstitutionLedger.sorted_keys(office):
		out[term_id] = maxi(int(out.get(term_id, 0)), int(office[term_id]))
	return out
