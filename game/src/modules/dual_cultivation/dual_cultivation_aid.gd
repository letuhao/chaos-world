class_name DualCultivationAid
extends RefCounted

## The `foundation` module's facade, preloaded for the reason `DomainSecretRealm` states:
## a bare `FoundationApi.` out of `modules/*` is invisible to `tools arch`
## (`rules.BARE_REF_UNITS`), and the `res://` reference below is what makes the
## `dual_cultivation -> foundation` edge both legal and counted.
const FoundationApi := preload("res://src/modules/foundation/api.gd")

## The dual-cultivation aid (BL-0951 / ADR 0939, S13): the seventh of the eight mending
## avenues. Two cultivators exchange — the actor's scarred past is mended, and the partner's
## perfection in the SAME realm is drawn down by EXACTLY the amount the actor gains.
##
## ## The transfer is EQUAL, and that is what makes it this avenue
##
## "The partner loses what the actor gains" is the whole rule: the partner is not a
## sacrifice (the master's sacrifice, S10, pays MORE than the disciple receives) but an
## exchange. So the amount moved is computed ONCE, before either write, as the smallest of
## three bounds — the authored `AID_STEP`, the actor's remaining headroom under `MEND_CAP`,
## and the partner's remaining reserve above zero — and the SAME number drives both the mend
## and the scar. Neither side can be pushed past its own bound, and neither gains more than
## the other loses.
##
## ## The price is the pair's own currency, and time
##
## Dual cultivation runs on ESSENCE, the module's own resource: the ritual spends
## `AID_ESSENCE` of it, so a body that is not a dual cultivator cannot work the exchange.
## The act also costs TIME (AGENTS.md): the actor spends `AID_PERIODS` of their own life
## through `FoundationApi.spend_periods`.
##
## ## Bounded, refusing by name
##
## The mend caps at `MEND_CAP` and the scar floors at zero, both inside `FoundationApi`.
## Every gate is read before anything is written, so a refusal costs nothing (ADR 0044) and
## there is never a half-exchange.

## The authored bounds (goal decision 4: authored defaults, tunable at content time). The
## avenue owns these; the foundation module owns the ceiling and no avenue raises it.
const AID_STEP := 0.15
const AID_ESSENCE := 10.0
const AID_PERIODS := 12
const SOURCE := "dual_cultivation_aid"

# --- reasons. Every refusal has a stable id a reader can show. ---------------

const OK_AIDED := "dual_aid"
const R_NO_ACTOR := "no_actor"
const R_NO_PARTNER := "no_partner"
const R_SAME_ACTOR := "same_actor"
const R_NO_ESSENCE := "not_enough_essence"
const R_NO_SNAPSHOT := "no_snapshot_to_mend"
const R_MEND_CAPPED := "mend_capped"
const R_PARTNER_NO_SNAPSHOT := "partner_never_left_that_realm"
const R_PARTNER_RUINED := "partner_has_nothing_to_give"
const R_MEND_REFUSED := "mend_refused"
const R_SCAR_REFUSED := "scar_refused"


## Exchange cultivation with `partner` in `realm_id`: the actor's scar there is mended by
## exactly what the partner's perfection there loses — the one verb this avenue publishes
## (BL-0951 / ADR 0939, S13).
##
## Answers `{"ok": true, "reason": "dual_aid", "realm", "transfer", "mended", "scarred",
## "essence", "years", "partner"}` on success and `{"ok": false, "reason": <named>}` on every
## refusal, never a bare `{}`.
##
## The realm is the caller's `realm_id` if it named one, else the actor's WEAKEST scar
## (`FoundationApi.mend_target`) — the same default every other avenue uses.
static func aid(actor: Actor, partner: Actor, realm_id: StringName = &"") -> Dictionary:
	if actor == null:
		return _answer(false, R_NO_ACTOR, {})
	if partner == null:
		return _answer(false, R_NO_PARTNER, {})
	if actor == partner:
		return _answer(false, R_SAME_ACTOR, {})
	var essence := actor.resource(DualCultivationStats.ESSENCE)
	var held := 0.0 if essence == null else essence.current
	if essence == null or held < AID_ESSENCE:
		return _answer(false, R_NO_ESSENCE, {"needed": AID_ESSENCE, "held": held})
	var target := realm_id
	if target == &"":
		target = FoundationApi.mend_target(actor)
	if target == &"":
		return _answer(false, R_NO_SNAPSHOT, {})
	var standing := FoundationApi.snapshot_for(actor, target)
	if standing < 0.0:
		return _answer(false, R_NO_SNAPSHOT, {"realm": String(target)})
	if standing >= FoundationApi.MEND_CAP:
		return _answer(false, R_MEND_CAPPED, {"realm": String(target)})
	var reserve := FoundationApi.snapshot_for(partner, target)
	if reserve < 0.0:
		return _answer(false, R_PARTNER_NO_SNAPSHOT, {"realm": String(target)})
	if reserve <= 0.0:
		return _answer(false, R_PARTNER_RUINED, {"realm": String(target)})
	# ONE number, computed before either write: the smallest of the authored step, the
	# actor's headroom under the cap, and the partner's reserve above zero. The same number
	# drives both halves, so the transfer is exactly equal and neither bound is crossed.
	var transfer := minf(AID_STEP, minf(FoundationApi.MEND_CAP - standing, reserve))
	var mended := FoundationApi.mend(actor, target, transfer, SOURCE)
	if not bool(mended.get("ok", false)):
		return _answer(
			false,
			R_MEND_REFUSED,
			{"realm": String(target), "mend_reason": String(mended.get("reason", ""))}
		)
	var scarred := FoundationApi.scar(partner, target, transfer, SOURCE)
	if not bool(scarred.get("ok", false)):
		return _answer(
			false,
			R_SCAR_REFUSED,
			{"realm": String(target), "scar_reason": String(scarred.get("reason", ""))}
		)
	essence.change(-AID_ESSENCE)
	var years := FoundationApi.spend_periods(actor, AID_PERIODS)
	return _answer(
		true,
		OK_AIDED,
		{
			"realm": String(target),
			"transfer": transfer,
			"mended": mended,
			"scarred": scarred,
			"essence": AID_ESSENCE,
			"years": years,
			"partner": String(partner.id),
		}
	)


static func _answer(ok: bool, reason: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": ok, "reason": reason}
	out.merge(extra, true)
	return out
