class_name ClanHeir
extends RefCounted

## Entering a member in their household's register as its heir (ADR 0064).
##
## ## The rung every house publishes and nothing could reach
##
## Every shipped `ClanDef.ranks` carries `heir`, and `ClanGate` can gate content on it
## (`{verb: &"has_rank", id: &"heir"}`). Nothing could ever put a member ON it:
## `ClanState.with_rank` writes whatever it is told and `ClanApi` had no verb that told
## it anything, so the rung was reachable from a test and from nowhere else. That is the
## whole of ADR 0064's authored-position half sitting in the content tree with no verb
## behind it.
##
## ## Registration is a political act, not an earned one
##
## It writes the position and **nothing else** — the same one-way split `SectApi.promote`
## keeps (ADR 0064). A member registered as heir on no standing at all is a legitimate
## character, and a registration that also moved standing would collapse the two numbers
## this module exists to keep apart.
##
## ## Reached by name, the way `ClanGate` is
##
## The facade is held to its fan-in budget rather than grown verb by verb, so a new
## membership-adjacent rule does not become a newly published method. ADR 0083's
## answer — a component holding the rule, named beside the facade — is the one used
## here, which is also what `ClanGate` and `ClanCatalog` already are.
##
## ## `heir` is named here and refused against, never derived
##
## The id is a constant because there is nothing to derive it from: `ranks` is an
## authored list of ids with no distinguished member, and picking "the one above core"
## would make a house's succession policy a function of array order. So the term is
## named once here and the registration is REFUSED against a house that does not publish
## it — a house with no `heir` rung never gets a fact saying one exists.

## The rank a registered heir holds. Named once; see the class note on why it is not
## derived from the ladder.
const HEIR_RANK := &"heir"

## Nobody to register. A caller in mid-wiring rather than a player being told no.
const R_NO_ACTOR := "no_actor"
## The actor belongs to no house, so there is no register to enter them in. The same
## statement `ClanGate`'s `is_clan` makes, reached through the verb instead of the gate.
const R_NOT_A_MEMBER := "not_a_member"
## This house publishes no `heir` rung. Content, not a player outcome: a ladder that
## stops at `core` has no such office for anybody to fill.
const R_NO_HEIR_RANK := "no_heir_rank"
## The member is already in the register. A second registration is the same one written
## twice, and the ledger is monotone.
const R_ALREADY_HEIR := "already_heir"


## Enter `actor` in their own house's register as its heir. Returns
## `{ok, reason, rank, standing}`.
##
## Refuses, writing nothing at all, for a null actor, a member of no house, a house that
## publishes no `heir` rung, and a member already entered (ADR 0064's refusal rule, the
## same one `ClanApi.join` keeps). `standing` is published on every path so a caller can
## check for itself that registration moved the position and NOT the earned number —
## the split is observable rather than merely asserted in a comment.
static func register(actor: Actor) -> Dictionary:
	if actor == null:
		return _report(false, R_NO_ACTOR, &"", 0)
	var ledger := ClanState.normalize(actor.get_module_data(ClanState.MODULE_KEY))
	if not ClanState.is_member(ledger):
		return _report(false, R_NOT_A_MEMBER, &"", ClanState.standing(ledger))
	var def := ClanCatalog.instance().clan_definition(ClanState.clan_id(ledger))
	if def == null or not def.has_rank(HEIR_RANK):
		return _report(false, R_NO_HEIR_RANK, ClanState.rank(ledger), ClanState.standing(ledger))
	if ClanState.rank(ledger) == HEIR_RANK:
		return _report(false, R_ALREADY_HEIR, HEIR_RANK, ClanState.standing(ledger))
	# The ONE rank writer, unchanged: it checks the house publishes the rung and never
	# consults standing, which is exactly the property a registration must keep.
	var registered := ClanState.with_rank(ledger, HEIR_RANK)
	if ClanState.rank(registered) != HEIR_RANK:
		# Unreachable while `has_rank` above agreed, and refused rather than assumed:
		# a rank writer that declined must not leave a fact claiming a registration
		# that did not happen.
		return _report(false, R_NO_HEIR_RANK, ClanState.rank(ledger), ClanState.standing(ledger))
	actor.set_module_data(ClanState.MODULE_KEY, registered)
	ClanProjection.apply(actor, registered)
	# LAST, once the rank it describes is on the ledger (ADR 0137).
	ClanFacts.record_heir_registered(actor)
	return _report(true, "", HEIR_RANK, ClanState.standing(registered))


## One shape on both paths, so a caller reads `rank` without asking which one it holds.
static func _report(ok: bool, reason: String, rank: StringName, standing: int) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"rank": String(rank),
		"registered": ok,
		"standing": standing,
	}
