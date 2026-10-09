class_name SocialMasterSacrifice
extends RefCounted

## The `foundation` module's facade, preloaded for the reason `DomainSecretRealm` states:
## a bare `FoundationApi.` out of `modules/*` is invisible to `tools arch`
## (`rules.BARE_REF_UNITS`), and the `res://` reference below is what makes the
## `social -> foundation` edge both legal and counted.
const FoundationApi := preload("res://src/modules/foundation/api.gd")

## The master's sacrifice (BL-0951 / ADR 0939, S10): the fifth of the eight mending
## avenues. A mentor spends their OWN cultivation so a disciple's scarred past may mend.
##
## ## The relationship IS the avenue
##
## The genre shape is a master burning his cultivation for a disciple — and the thing that
## makes it that, and not a shop, is the RELATIONSHIP. So the gate is the bond the two
## already have: a stranger cannot be asked, and a bond below `confidant` is not a
## mentorship. It is read through `SocialApi.bond_entry`, the module's own read, never a
## second copy of the ledger — the social ladder (ADR 0076) is the one place a bond's depth
## is decided.
##
## ## The price is the mentor's PERMANENT decline
##
## The mentor's own perfection in the transferred realm is SCARRED by `MENTOR_SCAR`
## through `FoundationApi.scar` (S8). A snapshot is never rebuildable (ADR 0939), so the
## mentor's decline is permanent — which is what a sacrifice is, and what separates it from
## the dual-cultivation aid (S13), where a partner's loss equals the actor's gain. Here the
## mentor pays MORE than the disciple receives: `MENTOR_SCAR > DISCIPLE_MEND`.
##
## ## Bounded, priced, refusing by name
##
## The gift is `FoundationApi.mend`, which caps at `MEND_CAP`; the decline is
## `FoundationApi.scar`, which floors at zero. Both sides' capacity is read BEFORE either
## write, so a refusal costs nothing (ADR 0044) and there is never a half-transfer. The act
## also costs TIME (AGENTS.md): the disciple spends `SACRIFICE_PERIODS` of their own life
## through `FoundationApi.spend_periods`, the same currency every foundation verb prices in.

## The authored bounds (goal decision 4: authored defaults, tunable at content time). The
## avenue owns these; the foundation module owns the ceiling and no avenue raises it. The
## mentor's scar exceeds the disciple's mend because a sacrifice LOSES in transit.
const DISCIPLE_MEND := 0.15
const MENTOR_SCAR := 0.25
const SACRIFICE_PERIODS := 12
const SOURCE := "master_sacrifice"

## The relationship floor: a bond must be at least this rung of the POSITIVE ladder before
## either party may ask for a sacrifice. `confidant` (standing 14, trust 0.5) is where
## ADR 0076 puts trust deep enough to entrust one's cultivation.
const MIN_BOND_CLASS := SocialBondClass.CONFIDANT

# --- reasons. Every refusal has a stable id a reader can show. ---------------

const OK_SACRIFICED := "sacrificed"
const R_NO_DISCIPLE := "no_disciple"
const R_NO_MENTOR := "no_mentor"
const R_SAME_ACTOR := "same_actor"
const R_NO_MENTORSHIP := "no_mentorship"
const R_NO_SNAPSHOT := "no_snapshot_to_mend"
const R_MEND_CAPPED := "mend_capped"
const R_MENTOR_NO_SNAPSHOT := "mentor_never_left_that_realm"
const R_MENTOR_RUINED := "mentor_has_nothing_left_to_give"
const R_MEND_REFUSED := "mend_refused"
const R_SCAR_REFUSED := "scar_refused"


## A mentor spends their own cultivation in `realm_id` so `disciple`'s scar there may mend
## — the one verb this avenue publishes (BL-0951 / ADR 0939, S10).
##
## Answers `{"ok": true, "reason": "sacrificed", "realm", "mended", "scarred", "years",
## "mentor"}` on success and `{"ok": false, "reason": <named>}` on every refusal, never a
## bare `{}` — a caller cannot tell "no mentorship" from "nothing to mend" from a mentor
## with nothing left to give.
##
## ## The order of the gates is the order a player meets them
##
## the relationship, then the disciple's realm, then the mentor's capacity, then the
## transfer — and **a refusal costs nothing** (ADR 0044): nothing is written until every
## gate has passed, so a mentor who cannot pay does not age the disciple who asked.
##
## ## Which realm it lands on
##
## The caller's `realm_id` if it named one, else the disciple's WEAKEST scar
## (`FoundationApi.mend_target`) — the same default the elixir and the site use, for the
## same reason: lifting the worst scar raises the carried mean fastest. The mentor gives in
## that SAME realm: a mentor far enough along to be one has left every realm the disciple
## has, so the transfer is coherent, and a mentor who never left it is refused by name.
static func sacrifice(disciple: Actor, mentor: Actor, realm_id: StringName = &"") -> Dictionary:
	if disciple == null:
		return _answer(false, R_NO_DISCIPLE, {})
	if mentor == null:
		return _answer(false, R_NO_MENTOR, {})
	if disciple == mentor:
		return _answer(false, R_SAME_ACTOR, {})
	# The relationship first: a stranger cannot be asked, whatever either party's record.
	var bond := SocialApi.bond_entry(disciple, mentor.id)
	if not _is_mentor(bond):
		return _answer(
			false,
			R_NO_MENTORSHIP,
			{"mentor": String(mentor.id), "bond": String(bond.get("bond", ""))}
		)
	var target := realm_id
	if target == &"":
		target = FoundationApi.mend_target(disciple)
	if target == &"":
		return _answer(false, R_NO_SNAPSHOT, {})
	var standing := FoundationApi.snapshot_for(disciple, target)
	if standing < 0.0:
		return _answer(false, R_NO_SNAPSHOT, {"realm": String(target)})
	if standing >= FoundationApi.MEND_CAP:
		return _answer(false, R_MEND_CAPPED, {"realm": String(target)})
	# The mentor's capacity, BEFORE any write, so a refusal costs nothing.
	var given := FoundationApi.snapshot_for(mentor, target)
	if given < 0.0:
		return _answer(false, R_MENTOR_NO_SNAPSHOT, {"realm": String(target)})
	if given <= 0.0:
		return _answer(false, R_MENTOR_RUINED, {"realm": String(target)})
	var mended := FoundationApi.mend(disciple, target, DISCIPLE_MEND, SOURCE)
	if not bool(mended.get("ok", false)):
		return _answer(
			false,
			R_MEND_REFUSED,
			{"realm": String(target), "mend_reason": String(mended.get("reason", ""))}
		)
	var scarred := FoundationApi.scar(mentor, target, MENTOR_SCAR, SOURCE)
	if not bool(scarred.get("ok", false)):
		return _answer(
			false,
			R_SCAR_REFUSED,
			{"realm": String(target), "scar_reason": String(scarred.get("reason", ""))}
		)
	var years := FoundationApi.spend_periods(disciple, SACRIFICE_PERIODS)
	return _answer(
		true,
		OK_SACRIFICED,
		{
			"realm": String(target),
			"mended": mended,
			"scarred": scarred,
			"years": years,
			"mentor": String(mentor.id),
		}
	)


## Whether a bond is deep enough to be a mentorship: present, and at or above
## [constant MIN_BOND_CLASS] on the POSITIVE ladder. A negative rung (a grudge) is never a
## mentor, whatever its magnitude, so the comparison is by LADDER POSITION and not by a
## numeric threshold a hostile bond could satisfy.
static func _is_mentor(bond: Dictionary) -> bool:
	if not bool(bond.get("present", false)):
		return false
	var rank := SocialBondClass.POSITIVE.find(StringName(bond.get("bond", "")))
	return rank >= 0 and rank >= SocialBondClass.POSITIVE.find(MIN_BOND_CLASS)


static func _answer(ok: bool, reason: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": ok, "reason": reason}
	out.merge(extra, true)
	return out
