class_name ClanGate
extends RefCounted

## Evaluates authored gate requirements against an actor's clan membership, and answers
## the two questions a clan exists to ask: *may this actor be admitted* and *may this
## gated content open for them*.
##
## A requirement is **data, never code**: either an empty dictionary — ungated, always
## open — or a map naming exactly one verb. No GDScript is authored per gate, so
## clan-restricted content is a content edit, not a code change.
##
## Verbs (a closed set — an unknown verb is refused, never silently true):
##   `{verb: &"is_clan",           id: &"ironpact"}`
##   `{verb: &"has_rank",          id: &"core"}`
##   `{verb: &"standing_at_least", at: 40}`
##   `{verb: &"recognised_at_least", at: 30}`
##   `{verb: &"has_trait",         id: &"clan:ironpact"}`
##   `{verb: &"all_of",            of: [ ...requirements ]}`
##   `{verb: &"any_of",            of: [ ...requirements ]}`
##   `{verb: &"none_of",           of: [ ...requirements ]}`
##
## `recognised_at_least` is the eighth and is the only one that reads the hinge rather
## than the ledger's raw numbers — see `recognised_of`.
##
## A requirement with no verb, or a verb that is not one of the eight, refuses closed
## and names itself. Refuse-with-cause is the house rule: content that is malformed must
## fail loudly and locally, never open a door it cannot read.

## Unmet-entry kinds.
const KIND_CLAN := &"clan"
const KIND_RANK := &"rank"
const KIND_STANDING := &"standing"
const KIND_PURITY := &"purity"
const KIND_REALM := &"realm"
const KIND_BODY := &"body"
const KIND_TRAIT := &"trait"
const KIND_RECOGNITION := &"recognition"
const KIND_GATE := &"gate"

## ## The hinge: recognition scales with what a member actually IS (ADR 0064)
##
## A house's standing multiplier reads the member's purity in the house's founding
## bloodline, so the recognition a carrier carries is worth more than the recognition
## an admitted diluted member carries — the clan recognises them both, and the LINEAGE
## decides how much the recognition is worth. That gap is ADR 0064's whole point:
## "the clan recognises them, the lineage does not empower them."
##
## ## It is a READ MODEL over the ledger, never a stored number and never a stat
##
## `recognised_of` is computed from `standing` and the actor's bloodline every time it
## is asked. Nothing persists it, so a save cannot hold a recognition that disagrees
## with the lineage the actor currently carries, and a purity change re-scales it on
## the next read with no migration. It is also NOT a `StatModifier` and NOT published
## through `ClanProvider`: ADR 0064 says a clan grants recognition and never power, and
## a stat is exactly the buyable thing that rule forbids. `test_clan_grants_no_power.gd`
## reads the derived combat stats across a join, and a riser in standing, to hold it.
##
## ## The range is `[UNSCALED, 1.0]` and both ends are deliberate
##
## 1.0 is a pure carrier. `UNSCALED` is the floor, not zero: a member who carries none
## of the founder's line has still been admitted and the act still happened, so their
## recognition is recorded rather than erased — and a gate at `at: 0` is satisfiable by
## any member, which is what makes `at: 0` mean "is a member" without saying so.
## Nothing here can exceed 1.0, so the ledger's own `standing` remains the ceiling and
## a house cannot multiply its way past the number the clan published.
##
## A member of a house that claims no founding line reads at `UNSCALED`: with no line
## to be pure in there is nothing to scale by, and silently reading 1.0 would hand every
## line-less house the carrier's recognition for free.
const UNSCALED := 0.25


## The full verdict, always this shape:
## `{ok: bool, reason: String, unmet: Array[Dictionary]}` where every unmet entry is
## `{kind, id, required, actual, label}` — the shape `ItemRequirement.unmet()` already
## produces, so a panel renders a reason it did not have to invent.
static func evaluate(actor: Actor, requirement: Dictionary) -> Dictionary:
	if requirement.is_empty():
		return _pass()
	var verb := StringName(requirement.get("verb", ""))
	if verb == &"":
		return _refuse("malformed", "A gate names no verb.")
	match verb:
		&"is_clan":
			return _is_clan(actor, requirement)
		&"has_rank":
			return _has_rank(actor, requirement)
		&"standing_at_least":
			return _standing_at_least(actor, requirement)
		&"recognised_at_least":
			return _recognised_at_least(actor, requirement)
		&"has_trait":
			return _has_trait(actor, requirement)
		&"all_of":
			return _composite(actor, requirement, true, false)
		&"any_of":
			return _composite(actor, requirement, false, false)
		&"none_of":
			return _composite(actor, requirement, false, true)
		_:
			return _refuse("unknown_verb", "Gate verb '%s' is not one this module reads." % verb)


## "May this actor be admitted to `clan_id`", as a list of complaints. Empty means the
## admission is open. The array is a list of complaints, never a count — a consumer
## asks "is this array empty" and nothing more.
##
## This gate is the ONLY place `clan` reads the two modules beneath it, and it is a
## gate over RECOGNITION rather than a grant:
##   - `min_purity` is read through `BloodlineApi.purity_of` on the clan's
##     `founding_bloodline`. Passing it recognises a lineage the member already has;
##     it never raises purity and never grants the line (ADR 0063/0064).
##   - `required_race` / `min_realm` are read through `RaceApi`, and narrow who may
##     vouch for whom. Neither changes what the body can do.
##
## An unknown clan refuses with cause rather than admitting everyone: content nothing
## defines must not gate content, and a typo'd id is a content bug.
##
## A null actor has **no opinion** and returns empty rather than a refusal: there is no
## person to admit, so this is not a statement about anyone's eligibility. `join` is the
## verb that refuses a null actor, and it does so with an `ok: false` verdict.
static func admission_unmet(actor: Actor, clan_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null:
		return out
	var def := ClanCatalog.instance().clan_definition(clan_id)
	if def == null:
		out.append(
			_entry(
				KIND_CLAN,
				clan_id,
				true,
				false,
				"The clan '%s' is not one this build ships." % clan_id
			)
		)
		return out
	if def.min_purity > 0.0 and def.founding_bloodline != &"":
		var purity := BloodlineApi.purity_of(actor, def.founding_bloodline)
		if purity < def.min_purity:
			out.append(
				_entry(
					KIND_PURITY,
					def.founding_bloodline,
					def.min_purity,
					purity,
					(
						"%s admits only those already carrying the %s line at %.2f "
						% [def.display_name, def.founding_bloodline, def.min_purity]
					)
				)
			)
	if def.required_race != &"":
		var race_id := RaceApi.race_of(actor)
		if race_id != def.required_race:
			out.append(
				_entry(
					KIND_BODY,
					def.required_race,
					String(def.required_race),
					String(race_id),
					"%s recognises only the %s line" % [def.display_name, def.required_race]
				)
			)
	if def.min_realm > 0:
		var reached := _actor_realm_index(actor)
		if reached < def.min_realm:
			out.append(
				_entry(
					KIND_REALM,
					def.id,
					def.min_realm,
					reached,
					(
						"%s admits only those who have reached realm ordinal %d"
						% [def.display_name, def.min_realm]
					)
				)
			)
	return out


## The actor's clan id, or `&""`. Read from the ledger rather than the trait mirror,
## because the mirror is derived and the ledger is the truth.
static func clan_of(actor: Actor) -> StringName:
	return ClanState.clan_id(_ledger(actor))


## The position the ledger records, or `&""`. Never recomputed from standing.
static func rank_of(actor: Actor) -> StringName:
	return ClanState.rank(_ledger(actor))


## The earned standing the ledger records, or 0.
static func standing_of(actor: Actor) -> int:
	return ClanState.standing(_ledger(actor))


## What the actor's house actually recognises them for: their earned standing as
## ADR 0064's hinge re-reads it, scaled by the member's purity in the house's founding
## bloodline.
##
## **This is the read `ClanStats.STANDING` never had.** The stat published the raw
## integer and nothing in the codebase read it, so a clan conferred no advantage a
## reputation system could compose against. This is the answer a consumer asks instead,
## and it is COMPUTED rather than stored — see the note on the hinge above.
##
## 0 for a non-member, for the same reason `standing_of` is 0: absence is zero
## recognition, not a missing key. So a gate at `at: 0` is satisfiable by any member —
## which is what `recognised_at_least` reads, and why it takes the membership arm
## `standing_at_least` does not. See `_recognised_at_least`.
static func recognised_of(actor: Actor) -> float:
	var standing := standing_of(actor)
	if standing <= 0:
		return 0.0
	return float(standing) * recognition_scale(actor)


## The factor the hinge scales by: `[UNSCALED, 1.0]`, read from the member's purity in
## their own house's founding bloodline.
##
## Published as its own verb because it is the number `ClanApi._regard` hands
## `SocialApi.apply_cause` as `scale`, so the standing multiplier is observable from
## both ends — in the regard `social` projects, and here.
##
## **No house** — an actor who belongs to none, or to a house this build no longer ships —
## reads 1.0 rather than crashing, because there is no house whose opinion is being
## weighted and no line that could be carried. `ClanApi` only ever asks past its own
## refusals, so that reading is unreachable on the production path — and it is the safe
## direction anyway, since the only thing a larger factor ever multiplies is a
## recognition.
##
## **A house that CLAIMS no founding line is a different question** and reads
## `UNSCALED`, not 1.0. There is nothing to be pure in, so there is nothing to scale by,
## and reading 1.0 would hand every line-less house the carrier's recognition for free —
## the one branch where "no opinion" and "perfect opinion" are the same number. The
## member is still recognised: the act happened, and the floor records it.
static func recognition_scale(actor: Actor) -> float:
	if actor == null:
		return 1.0
	# ## Two different questions, and they do NOT share a branch
	#
	# **No house at all** reads 1.0: there is no house whose opinion is being weighted
	# and no line that could be carried, so there is nothing to scale and nothing to
	# scale BY. `ClanApi` only ever asks past its own refusals, so that reading is
	# unreachable on the production path — and it is the safe direction anyway, since
	# the only thing a larger factor ever multiplies is a recognition.
	#
	# **A house that CLAIMS no founding line** reads `UNSCALED`, not 1.0. There IS a
	# house, and it has an opinion; there is simply nothing to be pure in, so reading
	# 1.0 would hand every line-less house the carrier's recognition for free. The
	# member is still recognised — the act happened, and the floor records it.
	var clan_id := clan_of(actor)
	if clan_id == &"":
		return 1.0
	var def := ClanCatalog.instance().clan_definition(clan_id)
	if def == null or def.founding_bloodline == &"":
		return UNSCALED
	var purity := BloodlineApi.purity_of(actor, def.founding_bloodline)
	return UNSCALED + (1.0 - UNSCALED) * clampf(purity, 0.0, 1.0)


## Whether the actor belongs to `clan_id`. False for the empty id, so `is_clan: ""` can
## never be satisfied by an actor who is a member of something.
static func is_member_of(actor: Actor, clan_id: StringName) -> bool:
	return clan_id != &"" and clan_of(actor) == clan_id


# --- Internals ---------------------------------------------------------------


static func _is_clan(actor: Actor, requirement: Dictionary) -> Dictionary:
	var clan_id := StringName(requirement.get("id", ""))
	if clan_id == &"":
		return _refuse("malformed", "An is_clan gate names no clan id.")
	if is_member_of(actor, clan_id):
		return _pass()
	return _fail(KIND_CLAN, clan_id, true, false, "Requires membership of the clan '%s'" % clan_id)


static func _has_rank(actor: Actor, requirement: Dictionary) -> Dictionary:
	var rank := StringName(requirement.get("id", ""))
	if rank == &"":
		return _refuse("malformed", "A has_rank gate names no rank.")
	if rank_of(actor) == rank:
		return _pass()
	return _fail(
		KIND_RANK, rank, String(rank), String(rank_of(actor)), "Requires the position '%s'" % rank
	)


static func _standing_at_least(actor: Actor, requirement: Dictionary) -> Dictionary:
	var at = requirement.get("at", null)
	if not (at is float or at is int):
		return _refuse("malformed", "A standing_at_least gate needs a numeric `at`.")
	var required := maxi(0, int(at))
	var standing := standing_of(actor)
	if standing >= required:
		return _pass()
	return _fail(
		KIND_STANDING,
		clan_of(actor),
		required,
		standing,
		"Requires standing of %d (you hold %d)" % [required, standing]
	)


## ## `recognised_at_least` reads the LEDGER, never a stat — and it is the whole point
##
## `standing_at_least` above gates on the raw integer, which is right for the house's
## own internal ladder. This verb gates on the number ADR 0064 calls the hinge: earned
## standing re-read through the member's founding-bloodline purity. So content can say
## "this room is for the people the house actually recognises" and be *right* about a
## diluted member who has earned a great deal — which is the character ADR 0064 exists
## to make representable.
##
## ## The bar is a FLOAT, unlike `standing_at_least`'s integer
##
## Recognition is a scaled figure, so truncating the bar to an int would either round a
## gate up into a door it should stay shut behind, or hide the multiplier that made the
## difference. A negative `at` is clamped to zero, which is the same reading
## `standing_at_least` gives it: a bar below zero is zero, which is satisfiable, and not
## a content bug.
##
## ## It DOES check membership, and only `standing_at_least` does not
##
## `recognised_of` answers 0 for a non-member exactly as `standing_of` does — absence is
## zero, not a missing key — so a bare comparison could not tell a member nobody respects
## from nobody at all at a bar of zero. This verb therefore takes the membership arm its
## sibling does not, and that is what makes **`at: 0` mean "belongs to a house"** without
## content having to say so in two verbs. The docstrings above claim exactly that, and
## `test_a_zero_bar_means_belongs_to_a_house_and_nothing_further` is what holds them to it.
##
## The change is confined to this verb. `standing_at_least` already answered `true` at
## zero for an actor belonging to no clan, and it stays that way: it gates the house's own
## internal ladder and has no business testing membership, so widening the oldest verb to
## fix a new one would be the larger behaviour change for no expressive gain —
## `all_of {is_clan, standing_at_least 0}` reads as one gate either way, and `is_clan`
## remains the verb that answers "do they belong".
##
## **A stat is buyable, a ledger is not** (ADR 0076, ADR 0062). Nothing in this module
## publishes recognition as a derived stat, so there is no `ClanStats` id this gate
## could be reading even if it wanted to: the only inputs are `ClanState.standing` and
## `BloodlineApi.purity_of`, both of which are ledgers rather than modifier stacks.
static func _recognised_at_least(actor: Actor, requirement: Dictionary) -> Dictionary:
	var at = requirement.get("at", null)
	if not (at is float or at is int):
		return _refuse("malformed", "A recognised_at_least gate needs a numeric `at`.")
	var required := maxf(0.0, float(at))
	var recognised := recognised_of(actor)
	# ## The membership arm, and what it deliberately does not buy
	#
	# `is_clan &""` is false for every actor by construction — `ClanGate.is_member_of`
	# refuses the empty id on purpose — so a member never fails this and a non-member
	# never passes it, whatever the bar.
	#
	# It buys EXACTLY one thing: that `at: 0` means "belongs to a house". It cannot give
	# a non-member a recognition, because `recognised_of` still answers 0 for one, so
	# every bar above zero was already refusing them. And it does not put `is_clan` into
	# `standing_at_least` — that verb already answers `true` at zero for an actor
	# belonging to no clan, and that has always been true of it; widening the OLDEST
	# verb to fix a NEW one would be the larger behaviour change, and it would leave
	# `all_of {is_clan, standing_at_least 0}` no more expressive than `is_clan` alone.
	# `is_clan` stays the membership verb and the two compose.
	if not is_member_of(actor, clan_of(actor)):
		return _fail(
			KIND_RECOGNITION,
			clan_of(actor),
			required,
			recognised,
			"Requires membership of a house, recognised at %.2f (you belong to none)" % required
		)
	if recognised >= required:
		return _pass()
	return _fail(
		KIND_RECOGNITION,
		clan_of(actor),
		required,
		recognised,
		"Requires recognition of %.2f (you hold %.2f)" % [required, recognised]
	)


static func _has_trait(actor: Actor, requirement: Dictionary) -> Dictionary:
	var trait_id := StringName(requirement.get("id", ""))
	if trait_id == &"":
		return _refuse("malformed", "A has_trait gate names no trait id.")
	if actor != null and actor.traits.has(trait_id):
		return _pass()
	return _fail(KIND_TRAIT, trait_id, true, false, "Requires the trait '%s'" % trait_id)


static func _composite(
	actor: Actor, requirement: Dictionary, require_all: bool, refuse_when_any: bool
) -> Dictionary:
	var children = requirement.get("of", [])
	if not (children is Array) or (children as Array).is_empty():
		return _refuse("malformed", "A composite gate names no children.")
	var unmet: Array[Dictionary] = []
	var passed := 0
	for child in children as Array:
		var verdict := evaluate(actor, child as Dictionary)
		if bool(verdict.get("ok", false)):
			passed += 1
			continue
		# A malformed child poisons the whole composite: refuse-with-cause means a
		# nested gate that cannot be read is never treated as satisfied.
		var nested_reason := String(verdict.get("reason", ""))
		if nested_reason == "malformed" or nested_reason == "unknown_verb":
			return verdict
		for entry in verdict.get("unmet", []) as Array:
			unmet.append(entry)
	var total := (children as Array).size()
	var ok := passed >= total if require_all else passed > 0
	if refuse_when_any:
		ok = passed == 0
	if ok:
		return _pass()
	return {"ok": false, "reason": "unmet", "unmet": unmet}


## The actor's highest realm ordinal across every cultivation path, mirroring
## `RaceGate.actor_realm_index` so an admission floor never demands one specific path.
## An unstarted or unknown path counts as 0 rather than "no opinion".
static func _actor_realm_index(actor: Actor) -> int:
	if actor == null:
		return 0
	var best := 0
	for path_id in PathState.ALL:
		var state := actor.path(path_id)
		if state == null:
			continue
		best = maxi(best, maxi(0, RealmDefaults.ladder().index_of(state.rank_id)))
	return best


static func _ledger(actor: Actor) -> Dictionary:
	if actor == null:
		return ClanState.empty()
	return ClanState.normalize(actor.get_module_data(ClanState.MODULE_KEY))


static func _pass() -> Dictionary:
	return {"ok": true, "reason": "", "unmet": []}


static func _fail(kind: StringName, id: StringName, required, actual, label: String) -> Dictionary:
	return {"ok": false, "reason": "unmet", "unmet": [_entry(kind, id, required, actual, label)]}


static func _entry(kind: StringName, id: StringName, required, actual, label: String) -> Dictionary:
	return {
		"kind": String(kind),
		"id": String(id),
		"required": required,
		"actual": actual,
		"label": label,
	}


## A refusal is distinct from a normal failure: the requirement itself is unreadable,
## which is a content bug rather than a player being told no.
static func _refuse(reason: String, label: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"unmet": [_entry(KIND_GATE, &"", true, false, label)],
	}
