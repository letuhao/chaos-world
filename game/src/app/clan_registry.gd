class_name ClanRegistry
extends RefCounted

## The `app/` seam a house's register is reached through, and **the honest report that
## it has no caller yet** (ADR 0083, ADR 0113, ADR 0137).
##
## ## What this file is for
##
## `ClanHeir.register` records `household_heir_registered` — a fact watched by four
## authored quests (`the_account_left_open`, `the_station_you_held`,
## `the_severed_calling`, `the_terms_you_drafted`) and mapped onto the fate counter
## `oaths_sworn`. It shipped with **ZERO production callers**, exactly as
## `CombatApi.spare` did for `third_man_spared`. That sibling was fixed with this same
## two-piece shape — a RefCounted in `app/` holding the rule, installed by the boot
## path, called by the one player action that owns the moment — and this file is the
## `clan` half of it.
##
##
## ## CLOSED. Both halves now have an owner, and neither of them is a timer.
##
## The three gaps the paragraphs below record as measured are all gone, and none of them
## was closed with a sweep - ADR 0113's rule is that the OWNER OF THE MOMENT writes, and a
## timer that manufactured the appointment would be the political layer deciding its own
## outcomes:
##
## - `ClanScreen` (ADR 0239) is the page, and `act_join` on it is the ONLY production caller
##   of `ClanApi.join`. A player can therefore be a member, and [method available] below
##   stops refusing `not_a_member` for every real actor.
## - The `ROUTE_CLAN` arm of `item_workbench_app.gd` installs this seam at route mount and
##   hands the page BOTH halves (`commit` and `available`) - ADR 0239's rule 1, because a
##   screen given only `commit` would have to re-derive the gate to decide whether to OFFER
##   the press, which is a second authority on who may be heir.
##
## `game/tests/app/test_clan_join_production_path.gd` drives the whole thing through the real
## mounted app, so the claim above is MEASURED rather than asserted, and
## `game/tests/modules/clan/test_clan_heir_registry_seam.gd` pins the caller count at ONE
## file, so a sweep can never be added beside the page.
##
## ## The moment, and why no caller existed yet (CLOSED - see the note below)
##
## `ClanHeir`'s own docstring names it: *"Entering a member in their household's
## register as its heir"*, and *"Registration is a political act, not an earned one."*
## A house ENTERS a member. So the owner of the moment is the house — an appointment a
## player either receives or does not — and not anything the player's own hands can do.
##
## Read the shipped tree and there is no such moment to attach to:
##
## - **`ClanApi.join` has ZERO production callers.** A grep for `ClanApi\.` across
##   `game/src` returns `actor_factory.gd:25` (`ClanApi.attach`) and two doc sentences.
##   `ClanApi.attach` normalises an EMPTY ledger and projects it; it admits nobody. So
##   no player is ever a member of a house in the shipped game, and `register` is
##   defined only over members (`not_a_member` is its second refusal).
## - **There is no clan screen.** `ui/` ships `sect_screen.gd`, which calls
##   `SectApi.promote` — that press is `sect`'s appointment moment and the exact
##   analogue of what `clan` is missing. `game/src/ui/screens/` has no clan screen at
##   all, and `ui/` is outside this slice's files.
## - **`clan` has no periodic cadence either.** `InstitutionBudget.TIERS` is settled by
##   `institution_resolver.gd:_apply_tier`, which dispatches `NationApi.act` and
##   `SectApi`'s proposal and has no clan arm. Nothing sweeps the ladder.
##
## So the wiring that is missing is a **clan surface**, not a seam. A seam that some
## timer or an ambient pass drove would manufacture the appointment — ADR 0113's rule
## is that the OWNER OF THE MOMENT writes, and the owner here is a house that has not
## been given a way to speak. Recorded as **DEF-0000's successor entry in
## `docs/deferred.jsonl`** rather than wired to an invented caller.
##
## ## What IS built here, and why it is not a fabricated consumer
##
## The seam itself, in the exact shape `CombatMercy` uses: [method install] binds the
## `clan` verb, [method installed] reports the binding as ONE conjunct, [method
## available] refuses on the module's own grounds BEFORE `clan` is asked, and [method
## commit] delegates and passes the module's answer through unchanged. There is no
## fallback path, no `else` that writes the fact, and no caller: a house that cannot
## reach this file gets a named refusal, never a silent success.
##
## ## The ONE call the next owner makes
##
## In `app/item_workbench_app.gd`'s boot install path, beside
## `var mercy: Dictionary = CombatMercy.install()` (`:519`):
##
## [codeblock]
## var registry: Dictionary = ClanRegistry.install()
## [/codeblock]
##
## and in whatever player-facing surface names a member of the house, at the moment
## the house enters them:
##
## [codeblock]
## var entered: Variant = ClanRegistry.commit(member)
## [/codeblock]
##
## Neither line is in this slice: that boot file has another agent's EXCLUSIVE
## ownership, and the surface does not exist. The seam is here so the moment one does
## exist has exactly one honest call to make, and so the refusal vocabulary is already
## written in one place.

## The `clan` verb a registration is committed through. `ClanRegistry.install`
## installs `Callable(ClanHeir, "register")`; `app/` outside this file never names a
## module facade directly, so the door is this seam's alone (ADR 0002, ADR 0083).
const CLAN_VERB := "register"

## ## The refusals, ALIASED rather than restated
##
## `CombatMercy` spelled its four refusals out as its own strings and answered "in this
## file's own words". That is wrong for `clan`, because the module already publishes
## these four BY NAME (`ClanHeir.R_NO_ACTOR` and its three siblings) and a panel
## rendering them must not have to learn a second set of words for the same four
## outcomes. Aliasing makes drift between the two vocabularies impossible to express.
const R_NO_ACTOR := ClanHeir.R_NO_ACTOR
const R_NOT_A_MEMBER := ClanHeir.R_NOT_A_MEMBER
const R_NO_HEIR_RANK := ClanHeir.R_NO_HEIR_RANK
const R_ALREADY_HEIR := ClanHeir.R_ALREADY_HEIR
## Nothing is installed, so there is no verb to commit the registration through. A
## wiring gap rather than a player outcome, and REPORTED rather than guessed around —
## the same name `CombatMercy` keeps for the same shape.
const R_NO_RESOLVER := "no_resolver"

## The installed seam. Process-wide, exactly as `CombatMercy._verb` is, because an
## appointment is reached from a body and a screen with nowhere to keep one: a
## registration that only landed while somebody happened to remember a callable would
## be an heir that stopped existing on the next mount. `install` is idempotent and
## `Callable()` restores the unbound state, so a test uninstalls deterministically
## rather than only overwriting — the `CombatBoot.set_attack_resolver` shape.
static var _verb: Callable = Callable()


## Install `ClanHeir.register` as the verb [method commit] delegates to, and report the
## install. Passing an empty Callable clears the binding.
static func install(verb: Callable = Callable(ClanHeir, CLAN_VERB)) -> Dictionary:
	_verb = verb
	return {"ok": _verb.is_valid(), "reason": "" if _verb.is_valid() else R_NO_RESOLVER}


## Whether a registration seam is installed. The same ONE-conjunct read
## `CombatMercy.installed` documents: `is_valid()` is false for a null callable AND for
## one naming an object that no longer exists, so a disjunction here would answer
## "yes" before anything had been installed.
static func installed() -> bool:
	return _verb.is_valid()


## Whether `actor` is somebody a house could honestly enter in its register RIGHT NOW.
##
## `{ok, reason}` where `ok` is the one bit a caller branches on. Every refusal is
## checked **before** `clan` is asked, so the module is never handed a question it
## would have to refuse — and so a press that cannot mean anything is refused rather
## than silently doing nothing.
##
## ## The house's own ladder decides, and the refusal says so
##
## The last two refusals are read from the AUTHORED house, not from the ledger's rung:
## a ladder that stops at `core` publishes no such office, so `no_heir_rank` is a
## statement about content rather than about anybody's standing. The first two are
## statements about the member. All four are the module's own words, aliased above.
static func available(actor: Actor) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	var ledger := ClanApi.state(actor)
	if String(ledger.get("clan", "")) == "":
		return {"ok": false, "reason": R_NOT_A_MEMBER}
	var def := ClanCatalog.instance().clan_definition(StringName(ledger["clan"]))
	if def == null or not def.has_rank(ClanHeir.HEIR_RANK):
		return {"ok": false, "reason": R_NO_HEIR_RANK}
	if String(ledger.get("rank", "")) == String(ClanHeir.HEIR_RANK):
		return {"ok": false, "reason": R_ALREADY_HEIR}
	return {"ok": true, "reason": ""}


## The registration itself: hand `actor` to `clan` and pass the answer back UNCHANGED,
## exactly as `CombatMercy.commit` does with `CombatApi.spare` — the module answers for
## `clan` and this file only injects.
##
## `ok` is the module's own verdict and never a decision of this file's: a house that
## declines to enter a member is not a failure of the seam.
static func commit(actor: Actor) -> Dictionary:
	var gate := available(actor)
	if not bool(gate["ok"]):
		return {"ok": false, "reason": String(gate["reason"]), "registered": false}
	if not installed():
		return {"ok": false, "reason": R_NO_RESOLVER, "registered": false}
	var called: Variant = _verb.call(actor)
	var answer: Dictionary = called if called is Dictionary else {}
	return {
		"ok": bool(answer.get("ok", false)),
		"reason": String(answer.get("reason", "")),
		"registered": bool(answer.get("registered", false)),
		"rank": String(answer.get("rank", "")),
		"standing": int(answer.get("standing", 0)),
	}
