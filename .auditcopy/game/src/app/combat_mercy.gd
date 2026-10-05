class_name CombatMercy
extends RefCounted

## The player's CHOICE not to kill, and the seam it reaches `combat` through.
##
## ## What this is
##
## `CombatApi.spare` records `third_man_spared`, a fact watched by
## `the_tally_of_a_man_who_kept_count` (need **2**), `what_the_rotation_cost`, and an
## AUTHORED fate literally named `the_third_man_spared` in `game/data/destiny/fates/`. It
## shipped with **zero production callers**: the fact existed and nothing in the shipped
## game could ever write it, so every one of those gates looked reachable on the board and
## could not be cleared. ADR 0137 splits that by cause — a fact whose real owner exists is
## a *missing caller*, not a content defect — and the owner here is `combat`.
##
## ## The moment, read off the fate's own description
##
## `the_third_man_spared` says, verbatim: *"Stood at killing distance with the advantage
## held and did not close. The sect files this as an incomplete hunt, not as mercy."* So it
## is not a surrender (no surrender system exists in this program) and not a duel
## resolution (ADR 0076 makes an encounter a stat-resolved exchange in which **either side
## can win**). It is a player, holding the advantage, choosing to stop.
##
## ## Where that choice is available
##
## `PlayerAdapter` is the shipped player's body and `attack` is already the one place it
## lands a blow. Its `interact` press is the other action on the same target, and for a
## combatant that press could only ever be filed as a look at a thing. So a press while
## `State.COMBAT` means *show mercy*: it resolves nothing, spends no health, and hands the
## decision here.
##
## ## The OWNER writes (ADR 0113), and nothing polls
##
## There is no timer, no sweep, and no "has anybody shown mercy yet" pass anywhere on this
## path. `available` below REFUSES on the same grounds the module itself refuses on, and
## `commit` delegates, so `CombatApi.spare` remains the one writer of both the terminal
## mercy state (`CombatDuel.record_spare`) and the fact.
##
## ## Why this is a file and not more of `combat_boot.gd`
##
## `CombatBoot` is at `gdlintrc`'s `max-file-lines` ceiling, and this seam is a separable
## concern with a separable name. ADR 0083's answer to a full file is a component named
## beside it — which is what `ClanHeir` is to `ClanApi` on the other half of this same
## ticket.

## The `combat` verb a mercy is committed through. `CombatBoot.install` installs
## `Callable(CombatMercy, "commit")`, and `CombatBoot` is the only layer allowed to name a
## module facade (ADR 0002), so `app/` outside this file never references `CombatApi`.
const COMBAT_VERB := "spare"

## Nobody to spare, or to spare them from.
const R_NO_ACTOR := "no_actor"
## A mercy cannot be shown to yourself.
const R_SAME_ACTOR := "same_actor"
## A corpse spends nothing and can be shown no mercy.
const R_LOSER_SLAIN := "loser_slain"
## The duel is already over with them; a second mercy is the first one written twice.
const R_ALREADY_SPARED := "already_spared"
## Nothing is installed, so there is no verb to commit the mercy through. A wiring gap
## rather than a player outcome, and REPORTED rather than guessed around.
const R_NO_RESOLVER := "no_resolver"

## The installed seam. Process-wide, exactly as `CombatBoot._resolver` is, because the
## press is a body method with nowhere to keep one: a body that only spared opponents while
## it happened to remember a callable would be a mercy that silently stopped existing on
## the next mount. `install` is idempotent and `Callable()` restores the unbound state.
static var _verb: Callable = Callable()


## Install `CombatApi.spare` as the verb `commit` delegates to, and report the install.
## Passing an empty Callable clears the binding, so a test can uninstall deterministically
## rather than only overwrite — the `CombatBoot.set_attack_resolver` shape.
static func install(verb: Callable = Callable(CombatApi, COMBAT_VERB)) -> Dictionary:
	_verb = verb
	return {"ok": _verb.is_valid(), "reason": "" if _verb.is_valid() else R_NO_RESOLVER}


## Whether a mercy seam is installed. The same ONE-conjunct read `CombatBoot
## .has_attack_resolver` documents: `is_valid()` is false for a null callable AND for one
## naming an object that no longer exists, so a disjunction here would answer "yes" before
## anything had been installed.
static func installed() -> bool:
	return _verb.is_valid()


## Whether `loser` is somebody a mercy could honestly be shown to RIGHT NOW.
##
## `{ok, reason}` where `ok` is the one bit a caller branches on. Every refusal here is
## checked **before** `combat` is asked, so the module is never handed a question it would
## have to refuse — and so a press that cannot mean anything is refused rather than
## silently doing nothing.
##
## ## This is what keeps the press NON-TRIVIAL
##
## An actor who has never fought cannot spend a mercy: there is no live opponent to
## release, and a fresh ledger reads `spared_by == ""`. So the fact is never already true
## for a bare actor, and half (b) of the gate-soundness rule holds by construction rather
## than by test.
static func available(winner: Actor, loser: Actor) -> Dictionary:
	if winner == null or loser == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	if winner == loser:
		return {"ok": false, "reason": R_SAME_ACTOR}
	if not bool(CombatDuelHit.alive(loser)["ok"]):
		return {"ok": false, "reason": R_LOSER_SLAIN}
	var duel := CombatDuel.normalize(loser.get_module_data(CombatDuel.MODULE_KEY))
	if CombatDuel.spared(duel):
		return {"ok": false, "reason": R_ALREADY_SPARED}
	return {"ok": true, "reason": ""}


## The mercy itself: hand `winner` and `loser` to `combat` and pass its answer back
## UNCHANGED, exactly as `CombatBoot.strike` does with the blow resolver — the module
## answers for `combat` and this file only injects.
##
## The refusals of [method available] are answered here in this file's own words, so a
## caller gets one vocabulary whether the gate or the module said no.
static func commit(winner: Actor, loser: Actor) -> Dictionary:
	var gate := available(winner, loser)
	if not bool(gate["ok"]):
		return {"ok": false, "reason": String(gate["reason"]), "spared": false}
	if not installed():
		return {"ok": false, "reason": "no_resolver", "spared": false}
	var called: Variant = _verb.call(winner, loser)
	var answer: Dictionary = called if called is Dictionary else {}
	return {
		"ok": bool(answer.get("ok", false)),
		"reason": String(answer.get("reason", "")),
		"spared": bool(answer.get("spared", false)),
		"loser_id": String(answer.get("loser_id", "")),
		"winner_id": String(answer.get("winner_id", "")),
	}
