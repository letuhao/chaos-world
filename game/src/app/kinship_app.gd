class_name KinshipApp
extends RefCounted

## The player-facing kinship verbs, and the composition-root seam that makes the lineage
## producer reachable (ADR 0108, ADR 0091; closing BL-0717 / BL-0751).
##
## ## The gap this closes, and it is TWO gaps, not one
##
## Conception is gated on a PERSONAL social standing of at least `Seduction.REQUIRED_STANDING`
## (6.0), read off the bond's cause ledger through `SocialApi.gate`. Both halves that
## could ever satisfy that were unreachable, and closing only one opens nothing:
##
## 1. **`Seduction.attempt` had ZERO production callers.** A grep of `game/src` for
##    `Seduction` returned exactly one hit, and it was the *string* `"Seduction"` in a
##    stage-name array (`dual_cultivation/succubus_path.gd:26`). A pregnancy could be
##    started by nothing a player can press.
## 2. **The personal-cause verbs had no production caller either.** `SocialFavourApp`
##    shipped `give`, `fight_alongside`, `settle_debt` and `teach`, and
##    `BrotherhoodOathApp` shipped `offer` — all of which apply an AUTHORED cause to a
##    personal bond, which is the only writer of a bond's axes (ADR 0091). Grepping
##    `SocialFavourApp.` outside `game/tests` returned only the definition file itself.
##
## The second gap is the sharper one, because it made the first one *unfixable*: the
## only production writer of the row `can_meet` reads was
## `SOCIAL_FACADE.apply_cause` on the SUCCESS PATH of the attempt the gate refuses
## (`seduction.gd:137`). A gate that only its own success can open is a gate that is
## always shut, so no amount of wiring the attempt alone would have opened it.
##
## ## 6.0 is genuinely reachable with AUTHORED magnitudes, and this file does not move it
##
## `Seduction.REQUIRED_STANDING` stays at 6.0. From `SocialCauseCatalog` as shipped:
##
## [codeblock]
## helped_in_combat  3.0     +  spared_in_combat  4.0   =  7.0   one fight, one mercy
## gifted_item       1.0     +  taught_technique   3.0   =  4.0
## gifted_item       1.0     +  honoured_a_debt    3.0   =  4.0
## taught_technique  3.0     +  honoured_a_debt    3.0   =  6.0   exactly the floor
## gifted_item       1.0     +  spared_in_combat   4.0   =  5.0   (short, deliberately)
## shared_brotherhood        5.0                    =  5.0   (short on its own)
## protected_from_death      6.0                    =  6.0   exactly the floor, UNWIRED
## [/codeblock]
##
## **The cheapest honest route is the fight: 7.0 in two presses of ONE verb.**
## `fight_alongside(player, npc, spared: false)` records `helped_in_combat`, and a second
## press with `spared: true` records `spared_in_combat` — the larger of the two, because
## `SocialFavour` gates it on the bond already carrying `helped_in_combat` and on a live
## opponent (`R_NO_FIGHT` / `R_NO_MERCY` otherwise). That gate is the anti-farm rule and it
## is why the route is 7.0 rather than 4.0: a caller cannot mint the mercy it never showed.
##
## A second floor-clearer exists for a hero with no fight: `taught_technique` (3.0) plus
## `honoured_a_debt` (3.0) is exactly 6.0, on two different KINDS, which is what
## `SocialBondClass`'s distinct-cause rule asks for. `shared_brotherhood` (5.0) alone is
## SHORT — deliberately, since it also has to promote to `sworn` before the ladder honours
## it (BL-0659), so a brotherhood cannot be the shortcut to conception.
##
## `protected_from_death` (6.0) would clear the floor alone, and `SocialFavour` names it
## `CAUSE_UNWIRED` for a real reason: `Shield` was deleted by ADR 0076 and
## `combat_engine` has a named-but-unbound `SHIELD_COMPONENT`, so "a person who took a
## blow meant for someone else" has no EVENT to hang on. Authoring a verb for it would
## mean inventing the act, and this file does not do that — the route below needs none of it.
##
## ## ## The one file that had to change for the fight route to be honest
##
## `fight_alongside`'s mercy probe defaults to `CombatMercy.available`, which answers
## against a live opponent in the COMBAT root. That probe is already installed by
## `CombatBoot.install`, so the shipped boot needs nothing new for it — but a build that
## installs nothing would answer `no_resolver` BY NAME rather than degrading quietly,
## which is the discipline `CombatMercy.install` sets and [method install] preserves.
##
## ## ## And why `Seduction.attempt` is still NOT in this file
##
## It is called by [method attempt_conception] and by nothing else in `game/src`. That is
## deliberate: `attempt` takes the roll as a PARAMETER (`rng == null` means NO draw, never
## a `randf()` fallback), so a caller that owns the rng compares its own roll against
## `Seduction.chance`. This file threads the caller's rng through untouched and never draws
## one itself, so a conception is reproducible headlessly — which is exactly what ADR 0108's
## determinism rule requires and what a component that rolled its own number could not give.
##
## ## ## ADR 0108 — lineage snapshots at CONCEPTION, and the child is born into NO clan
##
## This file adds nothing to the pregnancy. `FertilityApi.try_conceive` captures the
## partner's race, purity and both rolls ONTO the status at the moment of conception, so a
## later world or partner change cannot rewrite the child. `resolve_offspring` births into
## no house: admission is a gate with its own rules (ADR 0064), and a caller that means it
## calls `ClanApi.join` afterwards. Neither is touched here.
##
## ## ## Why this is `app/` and not on a facade
##
## `SocialApi` publishes exactly twelve public methods and `rules.MAX_FACADE_PUBLIC_METHODS`
## caps it at twelve, so it may not grow a thirteenth. Worse, a conception verb needs BOTH
## `fertility` and `social`, and the partner is an `Actor` this layer resolves through
## `NpcApi.resident` rather than an id the panel happened to hold. So the only legal home
## is the layer exempt from the graph — `LAYER_DEPS["app"] == "*"` — which is the
## `BrotherhoodOathApp` / `PursuitApp` / `QuestProgram` shape exactly.
##
## It keeps no ledger, no roster and no cache: the regard lives on the bond, the pregnancy
## on the actor's status, and the child in the composition root's own `_born` registry. This
## is wiring and translation and nothing else.

## Nobody to act towards.
const R_NO_ACTOR := "no_actor"
## The id names nobody this process has met. Alias of `SocialFavourApp`'s own word, so the
## two vocabularies cannot drift apart.
const R_UNKNOWN_NPC := "unknown_npc"
## Nothing was installed, so a verb that needs a seam has nothing to call. REPORTED rather
## than guessed around — the same name `CombatMercy` and `ClanRegistry` keep.
const R_NO_RESOLVER := "no_resolver"
## A bond does not carry the cause the verb's own rule requires. The mirror of
## `SocialFavour.R_NO_FIGHT`, aliased so the two vocabularies cannot drift.
const R_MISSING_HISTORY := SocialFavour.R_NO_FIGHT


## Bind every seam the personal-cause verbs may not resolve for themselves.
##
## ## Why this is a separate call at all, when `SocialFavourApp.install` already defaults
##
## It does default each seam, and that is what makes "reachable in production" a true
## claim rather than an aspiration — a verb behind four `Callable`s that a caller must
## construct is a verb nobody wires, which is the exact shape of defect this file closes.
## **This wrapper exists so the composition root has ONE call to make**, and so the boot
## order is stated in one place rather than inferred from four default bodies: the
## partner resolver needs `npc` bound, and `BrotherhoodOath.bond_key` needs a live roster.
##
## **Idempotent**, and it is safe to call before `npc` is attached — every seam here is a
## static function over a facade, so an early install binds the same callables a late one
## would. Returns the same report `SocialFavourApp.install` returns, so a probe can assert
## the bindings by name rather than infer them.
static func install() -> Dictionary:
	return SocialFavourApp.install()


## Uninstall every seam. Separate from `install()` for the same reason
## `SocialFavourApp.uninstall` is: a suite that asserts the UNBOUND behaviour needs to
## state "nothing bound" explicitly rather than passing a bare default and trusting it.
static func uninstall() -> void:
	SocialFavourApp.uninstall()


## Whether every seam the personal-cause verbs need is installed. One conjunction over the
## component's own report rather than a second set of names, so a seam added there is
## covered here without this file knowing its name.
static func installed() -> bool:
	var seams := SocialFavour.seams_installed()
	for key in seams.keys():
		if not bool(seams[key]):
			return false
	return true


# --- The personal-cause verbs ----------------------------------------------------
#
# Every one of these delegates to `SocialFavourApp`, which owns the partner resolution
# and the module call. Nothing here re-derives a cause, re-ranks a bond, or touches a
# standing directly — ADR 0091's rule is that the ONLY writer of a bond's axes is an
# authored `SocialCauseDef`, and these are three-line forwards that keep the app layer
# translation-only.


## Give `rows` — `{def_id, quantity}` primitives — to `npc_id`.
##
## `gifted_item`, +1.0. The cost is REAL: the goods LEAVE the player's inventory through
## the one transfer primitive in the program (`EconomyApi.trade`), so this is a faucet
## only in the sense that it costs something to press.
static func give(player: Actor, npc_id: StringName, rows: Array) -> Dictionary:
	if player == null:
		return _no_actor()
	return SocialFavourApp.give(player, npc_id, rows)


## Record that the player fought beside `npc_id` — or let them walk.
##
## ## THIS IS THE ROUTE TO THE FLOOR, and both presses are ONE verb
##
## `helped_in_combat` is +3.0 and `spared_in_combat` is +4.0, so the pair is 7.0 against
## a 6.0 floor. **`spared` is VERIFIED, not trusted**: `SocialFavour` refuses `no_fight`
## unless the bond already carries `helped_in_combat`, and refuses `no_mercy` unless the
## bound probe finds a live opponent. A caller cannot mint the larger cause by setting a
## flag, which is the whole reason this is a safe door to stand on.
##
## `CombatMercy.installed` is asked first so a build that never installed the combat
## seam refuses `no_resolver` BY NAME instead of pressing a mercy it cannot show.
static func fight_alongside(player: Actor, npc_id: StringName, spared: bool = false) -> Dictionary:
	if player == null:
		return _no_actor()
	if spared and not CombatMercy.installed():
		return _no_resolver()
	return SocialFavourApp.fight_alongside(player, npc_id, spared)


## Settle the debt `npc_id` is owed under `debt_id`. `honoured_a_debt`, +3.0.
##
## The debt is read from the partner's OWN roster tally, so a caller cannot assert one
## into existence to mint standing — a refusal here is `no_debt`, and it is the partner's
## answer rather than the caller's claim.
static func settle_debt(
	player: Actor, npc_id: StringName, debt_id: StringName = &"debt"
) -> Dictionary:
	if player == null:
		return _no_actor()
	return SocialFavourApp.settle_debt(player, npc_id, debt_id)


## Teach `npc_id` the technique the player carries the manual for. `taught_technique`, +3.0.
##
## The manual is CONSUMED from the player's bag and the cause is written only after the
## learn succeeds — a codex row the partner did not gain, recorded as a favour earned, is
## the mirror defect in its most insulting form.
##
## `rng` is threaded to the learner's own `TechniquesApi.learn`, where it is a SEED
## SOURCE and `null` takes the engine's entropy, exactly as production does. **No
## `randf()` appears in any path here**, so a headless suite reproduces an outcome by
## seeding.
static func teach(
	player: Actor,
	npc_id: StringName,
	manual_id: StringName,
	rng: RandomNumberGenerator = null,
) -> Dictionary:
	if player == null:
		return _no_actor()
	return SocialFavourApp.teach(player, npc_id, manual_id, rng)


## Every cause id these verbs can apply, sorted. Republished from the component so a
## content audit reads the wired vocabulary from ONE place, and so a bridge built on an
## unauthored id fails at test time rather than refusing silently at play time.
static func cause_ids() -> Array[StringName]:
	return SocialFavourApp.cause_ids()


# --- The lineage producer --------------------------------------------------------


## Whether the player may attempt a conception with `npc_id` RIGHT NOW, and why not if
## they may not. `{ok, reason, standing, chance}` — the read model an affordance greys
## its control out against, so no press refuses.
##
## ## The gate and the roll are SEPARATE keys, on purpose
##
## `can_meet` answers the SOCIAL floor only. `chance` answers the stat read, and it is
## already `0.0` whenever the floor is unmet — so a panel can print an odds line beside a
## roll it does not own without this file having to reconcile the two. `reason` names the
## floor's own refusal verbatim, which is `Seduction`'s vocabulary rather than this file's.
static func read_conception(player: Actor, npc_id: StringName) -> Dictionary:
	if player == null:
		return {"ok": false, "reason": R_NO_ACTOR, "standing": 0.0, "chance": 0.0}
	var partner := _partner(npc_id)
	if partner == null:
		return {"ok": false, "reason": R_UNKNOWN_NPC, "standing": 0.0, "chance": 0.0}
	# Asked ONCE and carried into both keys. `can_meet` is a pure read, so calling it twice
	# would cost nothing today — but a panel POLLS this row and a second gate call per poll
	# is a second gate evaluation a future writer could make disagree with the first.
	var met := Seduction.can_meet(player, partner)
	return {
		"ok": met,
		"reason": "" if met else Seduction.R_NO_BOND,
		"standing": _standing_of(player, partner),
		"chance": Seduction.chance(player, partner),
	}


## Attempt a conception between `player` and `npc_id`, measured by `roll`.
##
## ## This is the ONE production caller of `Seduction.attempt` in the whole tree
##
## It was zero before this line existed. The producer is a component beside the facade
## rather than a thirteenth `FertilityApi` method, precisely so that a caller like this one
## could exist without the facade losing its headroom.
##
## ## `roll` is ALWAYS a parameter and `rng == null` means NO DRAW
##
## `rng` is an OPTIONAL SEED SOURCE, carried as a PARAMETER and deliberately not read:
## the roll that decides the attempt is the one the CALLER already owns, exactly as
## `SectSuccession.step` reads no clock and rolls nothing. A caller that owns an rng calls
## `rng.randf()` itself and hands the number in; this file never calls `randf()`, so a
## conception suite is reproducible headlessly (ADR 0108's determinism rule). Keeping the
## parameter means a caller can thread its generator through without this file becoming a
## second place a draw happens — hence the underscore, not its removal.
##
## ## Every refusal names itself, and the ORDER is part of the contract
##
## `no_actor` / `unknown_npc` are this file's translation refusals and happen BEFORE
## `Seduction` is asked anything. Past them the reason is `Seduction`'s own — one of
## `no_bond`, `already_pregnant` or `roll_failed` — and the caller can tell "the social
## floor is not met" from "this outcome did not occur" without parsing prose.
##
## On success the authored cause `bound_in_intimacy` lands on the bond (ADR 0091: the only
## writer of a bond's axes is an authored `SocialCauseDef`) and the pregnancy status
## carries the CONCEPTION-TIME lineage snapshot (ADR 0108). Gestation then rides
## `StatusLoop.tick`, which is the clock the composition root already owns.
static func attempt_conception(
	player: Actor, npc_id: StringName, roll: float, _rng: RandomNumberGenerator = null
) -> Dictionary:
	if player == null:
		return _no_actor()
	var partner := _partner(npc_id)
	if partner == null:
		return _refuse(R_UNKNOWN_NPC, "")
	var answered := Seduction.attempt(player, partner, roll)
	return {
		"ok": bool(answered.get("ok", false)),
		"reason": String(answered.get("reason", "")),
		"partner": String(partner.id),
		"npc_id": String(npc_id),
		"chance": Seduction.chance(player, partner),
		"standing": _standing_of(player, partner),
		"pregnant": FertilityApi.pregnancy(player) != null,
	}


## Every cause id the lineage producer records, sorted. `bound_in_intimacy` is authored by
## `social`'s catalog and read by `Seduction` rather than reimplemented; republishing it
## here is what lets a content audit read BOTH vocabularies from one place.
static func conception_cause_ids() -> Array[StringName]:
	var out: Array[StringName] = [Seduction.CAUSE]
	out.sort()
	return out


# --- Internals -------------------------------------------------------------------


## The live `Actor` for `npc_id`, or null.
##
## Delegates to `SocialFavourApp`'s own resolution rather than repeating it, because that
## resolution is two steps deep and both steps matter: `NpcApi.resident` for a roster id,
## and a scan of the ids this process minted for an ENGINE id — and `Seduction.can_meet`
## asks its gate for `String(partner.id)`, the ENGINE id. A second resolution here would be
## a second thing to drift from the row the write path files.
static func _partner(npc_id: StringName) -> Actor:
	if npc_id == &"":
		return null
	return SocialFavourApp.partner_of(npc_id)


## The personal standing the ledger reads for this pair, or 0.0.
##
## ## BOTH keys are asked, because `_settle` writes BOTH
##
## The row the rest of the game reads is keyed on the roster DEF id and the row
## `Seduction.can_meet` gates on is keyed on the ENGINE id. They are two keys onto ONE
## bond, not two opinions — but a read model that reported only one of them would
## disagree with whichever half the player is about to act through, so the higher of the
## two is reported and the gate remains `Seduction`'s own verdict rather than a second
## authority here.
static func _standing_of(player: Actor, partner: Actor) -> float:
	if player == null or partner == null:
		return 0.0
	var def_key := BrotherhoodOath.bond_key(partner)
	return maxf(
		float(SocialApi.bond_entry(player, def_key).get("standing", 0.0)),
		float(SocialApi.bond_entry(player, partner.id).get("standing", 0.0))
	)


static func _no_actor() -> Dictionary:
	return {"ok": false, "reason": R_NO_ACTOR, "cause": "", "partner": ""}


static func _no_resolver() -> Dictionary:
	return {"ok": false, "reason": R_NO_RESOLVER, "cause": "", "partner": ""}


## A refusal in the shape the personal-cause verbs answer in, so a caller can read one
## dictionary shape across the whole kinship surface rather than two.
static func _refuse(reason: String, cause: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"cause": cause,
		"partner": "",
		"npc_id": "",
		"chance": 0.0,
		"standing": 0.0,
		"pregnant": false,
	}
