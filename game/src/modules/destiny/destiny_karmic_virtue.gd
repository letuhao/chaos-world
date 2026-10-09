class_name DestinyKarmicVirtue
extends RefCounted

## The `foundation` module's facade, preloaded for the reason `DomainSecretRealm` states:
## a bare `FoundationApi.` out of `modules/*` is invisible to `tools arch`
## (`rules.BARE_REF_UNITS`), and the `res://` reference below is what makes the
## `destiny -> foundation` edge both legal and counted.
const FoundationApi := preload("res://src/modules/foundation/api.gd")

## The karmic virtue avenue (BL-0951 / ADR 0939, S12): the sixth of the eight mending
## avenues. Deeds the world REMEMBERS are spent to mend a scarred past realm.
##
## ## The price is a DEED, and a deed cannot be bought
##
## The virtue is read from the shared `WorldFact` ledger (ADR 0113), the ONE monotone
## record of "a thing happened". The two facts this avenue counts are acts the world
## remembers and no item grants: `third_man_spared` (mercy at killing distance, written by
## `CombatFacts.record_spared`) and `oaths_discharged` (a sworn term brought to zero,
## written by `SectFacts`). The ids are authored here as STRINGS in the flat world-fact
## namespace — the same way `DestinyProjection` already names the facts it derives its
## counters from — so this file names no sibling module and no second ledger is kept.
##
## ## Spending is tracked, because a fact only ever rises
##
## `WorldFact` is monotone (ADR 0113): a deed cannot be un-done, so the avenue cannot lower
## the ledger it reads. What it tracks instead is how many deeds it has already SPENT, in a
## small ledger of its own under [constant STATE_KEY] (ADR 0027). Available virtue is the
## recorded deeds MINUS the spent ones, and a mend costs `VIRTUE_PER_MEND` of them — which
## is what makes the avenue PRICED rather than a one-time unlock, and what stops a single
## good deed from mending forever.
##
## ## Bounded, refusing by name
##
## The gift is `FoundationApi.mend`, which caps at `MEND_CAP`. Every gate is read before
## anything is written, so a refusal costs nothing (ADR 0044).

## The authored bounds (goal decision 4: authored defaults, tunable at content time). The
## avenue owns these; the foundation module owns the ceiling and no avenue raises it.
const VIRTUE_PER_MEND := 2
const VIRTUE_MEND := 0.2

## The world facts that are virtuous DEEDS. Flat ids in `WorldFact`'s namespace, authored as
## strings so this module names no sibling's class.
const VIRTUE_FACTS: Array[StringName] = [&"third_man_spared", &"oaths_discharged"]

## Where the spent-deed ledger lives in `actor.module_data` (ADR 0027). A key this file
## owns, distinct from `DestinyState.MODULE_KEY`, so the avenue's bookkeeping and the
## module's fate/counter ledger never share a row.
const STATE_KEY := &"destiny_karmic_virtue"

# --- reasons. Every refusal has a stable id a reader can show. ---------------

const OK_MENDED := "karmic_virtue"
const R_NO_ACTOR := "no_actor"
const R_NO_VIRTUE := "no_virtue_to_spend"
const R_NO_SNAPSHOT := "no_snapshot_to_mend"
const R_MEND_CAPPED := "mend_capped"
const R_MEND_REFUSED := "mend_refused"


## The actor's total virtuous deeds, read from the shared world-fact ledger.
static func virtue(actor: Actor) -> int:
	if actor == null:
		return 0
	var total := 0
	for fact in VIRTUE_FACTS:
		total += WorldFact.count(actor, fact)
	return total


## The deeds not yet spent: what one more mend can draw on.
static func available(actor: Actor) -> int:
	return virtue(actor) - spent(actor)


## The deeds this avenue has already spent, so a reader can see why a mend is refused.
static func spent(actor: Actor) -> int:
	if actor == null:
		return 0
	var state := actor.get_module_data(STATE_KEY)
	return int(state.get("spent", 0))


## Spend `VIRTUE_PER_MEND` deeds the world remembers to mend a scarred past realm
## (BL-0951 / ADR 0939, S12).
##
## Answers `{"ok": true, "reason": "karmic_virtue", "realm", "mended", "spent", "available"}`
## on success and `{"ok": false, "reason": <named>}` on every refusal, never a bare `{}`.
##
## The realm is the caller's `realm_id` if it named one, else the WEAKEST scar
## (`FoundationApi.mend_target`) — the same default every other avenue uses.
static func mend_via_virtue(actor: Actor, realm_id: StringName = &"") -> Dictionary:
	if actor == null:
		return _answer(false, R_NO_ACTOR, {})
	var owed := available(actor)
	if owed < VIRTUE_PER_MEND:
		return _answer(false, R_NO_VIRTUE, {"available": owed, "cost": VIRTUE_PER_MEND})
	var target := realm_id
	if target == &"":
		target = FoundationApi.mend_target(actor)
	if target == &"":
		return _answer(false, R_NO_SNAPSHOT, {})
	var existing := FoundationApi.snapshot_for(actor, target)
	if existing < 0.0:
		return _answer(false, R_NO_SNAPSHOT, {"realm": String(target)})
	if existing >= FoundationApi.MEND_CAP:
		return _answer(false, R_MEND_CAPPED, {"realm": String(target)})
	var mended := FoundationApi.mend(actor, target, VIRTUE_MEND, "karmic_virtue")
	if not bool(mended.get("ok", false)):
		return _answer(
			false,
			R_MEND_REFUSED,
			{"realm": String(target), "mend_reason": String(mended.get("reason", ""))}
		)
	var now := spent(actor) + VIRTUE_PER_MEND
	actor.set_module_data(STATE_KEY, {"spent": now})
	return _answer(
		true,
		OK_MENDED,
		{
			"realm": String(target),
			"mended": mended,
			"spent": now,
			"available": available(actor),
		}
	)


static func _answer(ok: bool, reason: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": ok, "reason": reason}
	out.merge(extra, true)
	return out
