class_name SocialFavour
extends RefCounted

## The personal acts a PLAYER performs on another PERSON, each an authored cause applied
## to BOTH ledgers (ADR 0091, closing the mirror defect).
##
## ## What this file is, and what it is not
##
## It is a COMPONENT beside `api.gd`, not facade methods. `SocialApi` publishes exactly
## twelve public methods and `rules.MAX_FACADE_PUBLIC_METHODS` caps it at twelve, so
## nothing here may become a thirteenth — the `BrotherhoodOath` / `Seduction` shape, and
## for the same reason those two are components too.
##
## ## ## The gap this closes
##
## Seven POSITIVE PERSONAL causes shipped in `SocialCauseCatalog` with no production
## applier: `gifted_item`, `helped_in_combat`, `spared_in_combat`, `protected_from_death`,
## `taught_technique`, `honoured_a_debt`, `shared_brotherhood`. Only the last had a
## producer (`BrotherhoodOath`). The other six were inert vocabulary: the code read
## correctly and the act could never happen.
##
## That was not cosmetic. `Seduction.REQUIRED_STANDING` is **6.0**, read through
## `SocialApi.gate` as a PERSONAL standing, and every production caller of `apply_cause`
## (`sect/api.gd:820`, `nation/api.gd:664`, `clan/api.gd:411`) passes an INSTITUTION id.
## So no personal bond row was ever written, `can_meet` refused `no_bond` forever, and no
## pregnancy could ever begin — the lineage producer was unreachable behind a number
## nothing could reach.
##
## ## ## Both ledgers move, and that is the module's own contract
##
## `SocialApi.apply_cause`'s docstring leaves the MIRROR to the caller's transaction, and
## this file is that transaction. **Every act here writes twice**: the player's bond
## records the act they did and the partner's bond records what it was to receive. One
## act, two `Actor`s, two ledgers — the `BrotherhoodOath.swear_brotherhood` shape, which
## is why both sides resolve the counterparty through [method bond_key].
##
## ## ## Four SEAMS, and two DECLARED edges
##
## `social` declares `["contracts", "core"]`. Everything below reaches a sibling module
## through a bound `Callable` installed by `app/`, which `LAYER_DEPS["app"] == "*"`
## permits by construction — the `CombatMercy` / `CustodyApi.set_resolver` shape. A bare
## `NpcApi.` or `TechniquesApi.` here would be an **undeclared and invisible** edge,
## because `BARE_REF_UNITS` excludes `modules/*` (rules.py): the graph would report no
## violation while a cycle written that way is exactly the `nation -> sect` trap ADR 0083
## names. `items` and `economy` are the two this module genuinely spends objects through,
## so they are `preload`ed facades and registered in `registry.json` in this same change.
##
## ## ## No rng is DRAWN here, and `rng` is still a parameter
##
## An act is not a lottery. `teach` threads an optional `rng` through to the learner
## exactly as `TechniquesApi.learn` documents its own — `rng` is a SEED SOURCE, null takes
## the engine's entropy — and nothing else in this file takes one, because nothing else has
## a draw. There is no `randf()` anywhere in this file: a component that rolled its own
## number would be untestable headlessly, which is the rule `Seduction` states for its own
## roll and the reason it takes one as a parameter instead.
##
## ## ## Nothing here moves a STAT
##
## ADR 0064: a clan grants recognition and access, never power. Nothing in this file
## writes a combat stat, a pool or a resource. The costs charged are CARRIED OBJECTS and
## the partner's own recorded state — things a player spends, never numbers a
## relationship grants.

## The four causes this component applies, named at the call site. Reused verbatim from
## `SocialCauseCatalog`; nothing here authors a parallel id, because `apply_cause` refuses
## `unknown_cause` and a bridge built on unauthored vocabulary refuses at play time.
const CAUSE_GIFTED := &"gifted_item"
const CAUSE_HELPED := &"helped_in_combat"
const CAUSE_SPARED := &"spared_in_combat"
const CAUSE_TAUGHT := &"taught_technique"
const CAUSE_DEBT := &"honoured_a_debt"

## The one positive personal cause with NO verb here, declared so a content audit reads all
## seven ids from one place and finds the unwired one by name.
##
## **6.0 standing, `persistent`, and still unreachable** — see [method fight_alongside].
## It needs a combat mechanic this program does not have: `Shield` was deleted by ADR
## 0076 and `combat_engine` names a `SHIELD_COMPONENT` slot nothing binds, so "a person
## who took a blow meant for someone else" has no event to hang on. Authoring a verb would
## mean inventing the act.
const CAUSE_UNWIRED := &"protected_from_death"

## ## The refusals. Every one names itself, and each is a RULE rather than input
## validation (ADR 0083) — a panel renders the constant instead of inventing prose.
##
## `no_partner` and `no_resolver` are deliberately distinct: the first is "there is nobody
## here to do this to", and the second is "this build never installed the seam". Neither
## is fixable by a player, and collapsing them into one string would report a wiring gap as
## an outcome.
const R_NO_ACTOR := "no_actor"
const R_NO_PARTNER := "no_partner"
const R_SAME_ACTOR := "same_actor"
const R_NOT_CARRIED := "not_carried"
const R_NOT_GIFTABLE := "not_giftable"
const R_NOT_A_MANUAL := "not_a_manual"
const R_NO_DEBT := "no_debt"
## Nothing to spare the end of: the bond carries no `helped_in_combat`, so no fight
## happened and there is no mercy to record. Deliberately distinct from `R_NO_MERCY`,
## which is the probe's answer about the WORLD rather than this verb's answer about its
## own history.
const R_NO_FIGHT := "no_fight"
const R_NO_RESOLVER := "no_resolver"
const R_LEARN_REFUSED := "learn_refused"
const R_NO_MERCY := "no_mercy"

## The `technique` category, as its wire value rather than as `ItemCategory.TECHNIQUE`. See
## [method _is_manual] for why it is not that constant.
const MANUAL_CATEGORY := &"technique"

## ## The TWO declared sibling edges this module owns.
##
## `social` declares `["contracts", "core"]` in `tools/arch/registry.json` and this change
## registers `items` and `economy` beside them, because a gift and a manual are objects this
## module genuinely spends. Both are reached by `preload` of the FACADE — `BARE_REF_UNITS`
## excludes `modules/*`, so a bare `ItemsApi.` here would report zero violations while
## carrying the same real edge, and `_find_cycle` would never see it (the `nation -> sect`
## trap ADR 0083 insists on a `preload` for).
const ITEMS_FACADE := preload("res://src/modules/items/api.gd")
const ECONOMY_FACADE := preload("res://src/modules/economy/api.gd")

# --- The bound seams ----------------------------------------------------------

## ## `func(actor: Actor) -> StringName` — the bond key an actor is known by.
##
## Installed as `BrotherhoodOath.bond_key`. **This is not simply `actor.id`**: an npc's
## ledger is keyed by whoever stands on the other side of it, and for another npc that id
## is the DEF id — `ActorFactory.spawn_npc` mints `npc_elder_wei` for `elder_wei`, so keying
## a mirror on `actor.id` filed it under a row no authored gate, consent row or panel will
## ever ask for. `BrotherhoodOath.bond_key` already owns that resolution and this file
## reuses it rather than growing a second copy.
##
## Process-wide, exactly as `CombatMercy._verb` is: there is nowhere else for it to live,
## and a half-bound resolution would file every mirror under an id nothing reads. Unbound
## degrades to `actor.id` rather than to a refused verb — a mirror under a wrong id is a
## cosmetic defect, while refusing the act would break a player path over wiring.
static var _key_resolver: Callable = Callable()

## ## `func(npc_id: StringName, debt_id: StringName) -> int` — what that individual is owed.
##
## Installed by `app/` as `SocialFavourApp.owed_by`, which reads
## `NpcApi.summary(npc_id)["tally"]` — `npc`'s own primitives-only read model — so the
## verb's gate and a panel's row cannot disagree.
##
## **It takes the npc id, not the `Actor`.** `NpcApi.summary` is keyed on the roster's
## stable id and refuses anything else, and passing the actor id `npc_elder_wei` is the
## precise id error `BrotherhoodOath._bond_key` exists to prevent. `bond_key` below is what
## resolves the actor to that id, and it is applied at the call so the seam has one honest
## signature rather than two that disagree.
static var _debt_reader: Callable = Callable()

## ## `func(player: Actor, partner: Actor) -> Dictionary` — `CombatMercy.available`.
##
## The gate on "is there somebody a mercy could honestly be shown to right now": a live
## opponent, not a corpse, not one already spared. `spared_in_combat` is +4.0 against
## `helped_in_combat`'s +3.0, so without this a caller could pass `spared: true` and mint
## the larger number with no opponent and no mercy at all.
static var _mercy_probe: Callable = Callable()

## ## `func(learner: Actor, manual_id: StringName, rng: RandomNumberGenerator) -> Dictionary`
## — teach one manual to one actor.
##
## A seam rather than a call because a `TechniqueDef` is not reachable from `social`:
## `TechniquesApi.learn` needs the def object, the catalog is internal to `techniques`, and
## naming either from here is a bare reference this module may not declare. The caller owns
## the resolution and the learn; this file owns the CAUSE and the mirror.
static var _teacher: Callable = Callable()

## Every cause id this component can apply, sorted. `app/SocialFavourApp` republishes it so
## a content audit reads the wired vocabulary from one place, and the suite pins every
## entry against the shipped catalog.
static func cause_ids() -> Array[StringName]:
	var out: Array[StringName] = [
		CAUSE_GIFTED, CAUSE_HELPED, CAUSE_SPARED, CAUSE_TAUGHT, CAUSE_DEBT
	]
	out.sort()
	return out

static func install_key_resolver(resolver: Callable) -> void:
	_key_resolver = resolver if _usable(resolver) else Callable()

static func install_debt_reader(reader: Callable) -> void:
	_debt_reader = reader if _usable(reader) else Callable()

static func install_mercy_probe(probe: Callable) -> void:
	_mercy_probe = probe if _usable(probe) else Callable()

static func install_teacher(teacher: Callable) -> void:
	_teacher = teacher if _usable(teacher) else Callable()

## `is_valid()` is false for a null callable AND for one naming an object that no longer
## exists, so a disjunction here would answer "installed" before anything was bound — the
## ONE-conjunct read `CombatMercy.installed` documents.
static func _usable(candidate: Callable) -> bool:
	return not candidate.is_null() and candidate.is_valid()

static func seams_installed() -> Dictionary:
	return {
		"key_resolver": _usable(_key_resolver),
		"debt_reader": _usable(_debt_reader),
		"mercy_probe": _usable(_mercy_probe),
		"teacher": _usable(_teacher),
	}

## The bond key `other` is written under. Degrades to `other.id` when nothing is bound;
## see the note on [member _key_resolver].
static func bond_key(other: Actor) -> StringName:
	if other == null:
		return &""
	if not _usable(_key_resolver):
		return other.id
	var resolved: Variant = _key_resolver.call(other)
	return resolved if resolved is StringName else other.id

# --- The verbs ----------------------------------------------------------------

## ## Give `rows` — `{def_id, quantity}` primitives — to `partner`.
##
## The cost is REAL: the goods LEAVE the player's inventory through the one transfer
## primitive in the program (`EconomyApi.trade`), which is the same atomic path a shop sale
## settles through. That is deliberate twice over. A gift that costs nothing is a faucet,
## and ADR 0091's gift-spam guard only means anything while giving spends something. And
## this is exactly the case `EconomyExchange` refuses when the OFFERING side has nothing of
## price — "a one-sided give is a gift, and a gift belongs to `SocialApi.apply_cause`" — so
## the goods move through the primitive rather than beside it.
##
## `EconomyExchange`'s rule is `received <= offered`, so an EMPTY `want` leg is a legal
## one-sided give and the partner needs no purse. What it DOES require is room: the delivery
## is refused `no_room` for a full inventory, and that reason arrives verbatim below so a
## panel shows what is still missing rather than "not carried".
##
## Returns `{ok, reason, cause, partner, standing_before, standing_after,
## partner_standing, detail}`. **Every refusal is before the first mutation**, so a refused
## gift moves no goods and writes no cause (ADR 0044).
static func give(player: Actor, partner: Actor, rows: Array) -> Dictionary:
	var gate := _gate(player, partner)
	if not bool(gate["ok"]):
		return _refuse(String(gate["reason"]))
	var priced := _price(player, rows)
	if not bool(priced["ok"]):
		return _refuse(String(priced["reason"]))
	var moved := ECONOMY_FACADE.trade(player, partner, rows, [], player.id)
	if not bool(moved.get("ok", false)):
		# The transfer's own refusal, VERBATIM and unflattened: `no_room` and `not_carried`
		# are different facts, and a caller given one string for both could not tell a full
		# bag from an empty one.
		return _refuse(String(moved.get("reason", R_NOT_CARRIED)))
	return _settle(player, partner, CAUSE_GIFTED, {"price": int(priced["price"])})

## ## Settle a debt the partner is owed.
##
## **Gated on a RECORDED debt rather than freely repeatable**, and that gate is the
## anti-farm rule rather than a courtesy. `honoured_a_debt` is +3.0 and `persistent`, so an
## ungated verb would be a +3.0 faucet pressed forever against one partner.
##
## `debt_id` is verified against the partner's own tally through the seam, so a caller cannot
## assert a debt into existence to mint standing: the partner's record of what they have
## been given is what "owed" means, and it is their number rather than ours.
##
## The settle does NOT clear the tally — clearing it writes `npc`'s ledger, which this module
## does not own — so the act is recorded on the bond's cause ledger instead, which is
## monotone and survives a save. That is why `settle_debt` is safe to call for a debt the
## caller has already paid: the bond's own `causes` count shows the history, and
## `SocialBondClass`'s distinct-KIND rule is what stops the repetition mattering.
static func settle_debt(player: Actor, partner: Actor, debt_id: StringName = &"debt") -> Dictionary:
	var gate := _gate(player, partner)
	if not bool(gate["ok"]):
		return _refuse(String(gate["reason"]))
	if debt_id == &"":
		return _refuse(R_NO_DEBT)
	if not _usable(_debt_reader):
		return _refuse(R_NO_RESOLVER)
	var called: Variant = _debt_reader.call(bond_key(partner), debt_id)
	var owed := 0 if not (called is int or called is float) else int(called)
	if owed <= 0:
		return _refuse(R_NO_DEBT)
	return _settle(player, partner, CAUSE_DEBT, {"owed": owed, "debt_id": String(debt_id)})

## ## Teach `partner` the technique the player carries the manual for.
##
## The cost is the MANUAL, consumed from the player's bag with `ItemsApi.consume_item` —
## all-or-nothing, so a short stack teaches nothing. A teaching verb that charged no manual
## would be a technique faucet; one that charges the teacher a manual and the learner the
## authored learn price is a real act with two real costs.
##
## The LEARN itself is the seam's, and its refusal is returned **verbatim** so a panel
## renders the learner's own `unmet` list rather than a flattened reason: `realm_unmet` is a
## gate the learner may go and satisfy, and flattening it to a string loses the only
## actionable part of it.
##
## **The cause is written only after the learn succeeds, and the manual consumed only after
## that.** A codex row the partner did not gain, recorded as a favour earned, is the mirror
## defect in its most insulting form — the world believing something that did not happen.
static func teach(
	player: Actor, partner: Actor, manual_id: StringName, rng: RandomNumberGenerator = null
) -> Dictionary:
	var gate := _gate(player, partner)
	if not bool(gate["ok"]):
		return _refuse(String(gate["reason"]))
	if manual_id == &"":
		return _refuse(R_NOT_CARRIED)
	# ## Carrying is asked BEFORE category, and the order is the answer
	#
	# `_is_manual` reads the def off the player's own inventory, so an item the player does
	# not carry has no def to classify and would be refused `not_a_manual` — which is a LIE:
	# the player did not carry it, which is `not_carried`, and a panel printing "that is not
	# a manual" for an empty bag sends the player looking in the wrong place. So the more
	# specific and more actionable question is asked first.
	if not ITEMS_FACADE.has_item(player, manual_id, 1):
		return _refuse(R_NOT_CARRIED)
	if not _is_manual(player, manual_id):
		return _refuse(R_NOT_A_MANUAL)
	if not _usable(_teacher):
		return _refuse(R_NO_RESOLVER)
	var taught: Variant = _teacher.call(partner, manual_id, rng)
	var outcome: Dictionary = taught if taught is Dictionary else {}
	if not bool(outcome.get("ok", false)):
		return _refuse(String(outcome.get("reason", R_LEARN_REFUSED)))
	if not ITEMS_FACADE.consume_item(player, manual_id, 1):
		return _refuse(R_NOT_CARRIED)
	return _settle(
		player, partner, CAUSE_TAUGHT, {"manual": String(manual_id), "technique": outcome}
	)

## ## Record that `player` fought beside `partner` — or let them walk.
##
## `helped_in_combat` and `spared_in_combat` are ONE verb with an authored choice, and both
## are `kind: combat`, so a pair whose whole history is combat tops out at an acquaintance
## however large the total. The anti-farm rule, applied to this file's own vocabulary rather
## than asserted about it.
##
## ## ## `spared` is NOT self-declared, and it is checked against the LEDGER first
##
## `spared_in_combat` is the largest cause this file can mint, so a verb that took the
## flag on trust would be a +4.0 faucet: any caller passing `spared: true` would earn the
## bigger number with no opponent and no mercy at all. Two gates stand in the way, in this
## order, and both are RULES rather than input validation.
##
## ## ## ## 1. A mercy is only a mercy against a fight that happened
##
## The probe seam answers "is there somebody a mercy could honestly be shown to RIGHT
## NOW", and on a fresh, unfought individual it answers TRUE — the loser is alive, not a
## corpse and not already spared, which is the whole of `CombatMercy.available`'s own
## contract. So the probe alone cannot refuse this verb, and a `spared: true` press on
## somebody the player never fought would have been recorded as a fact that never
## occurred: exactly the unearned cause ADR 0091's ledger exists to prevent.
##
## **So the verb reads its OWN cause ledger first.** `spared_in_combat` requires the bond
## to already carry `helped_in_combat`: you cannot spare somebody you have not fought.
## The check is `SocialApi.bond_entry(...)["causes"]`, the recorded ledger rather than a
## counter this file keeps — one source of truth, no second writer, and a gift or a debt
## can never stand in for a fight. This is the anti-farm rule applied to this file's own
## vocabulary, in the same way `helped_in_combat` shares `kind: combat` with it.
##
## ## ## #### Why the REFUSAL names itself rather than silently doing nothing
##
## `R_NO_FIGHT` is deliberately distinct from `R_NO_MERCY`: the first is "there was no
## fight to spare the end of", the second is "the fight is over, or the other party cannot
## be shown mercy". A panel says different things about them, and collapsing them would
## report a missing history as an outcome.
##
## ## ## ## 2. The probe still gates the WORLD
##
## `CombatMercy.available` is asked as well, so a corpse is never recorded as spared and
## an already-spared opponent is not spared twice. The ledger gate is what makes the verb
## refuse in the state a player is actually in when they have not fought; the probe is
## what keeps it honest once they have.
##
## ## ## And `protected_from_death` is deliberately NOT here
##
## It is the sixth of the seven and the largest at +6.0, so it is the one a reader looks for
## first, and writing a verb for it would mean inventing a mechanic — standing between
## somebody and a blow — that `combat_engine` has a named but unbound `SHIELD_COMPONENT` for
## and no event for. It stays unwired and reported rather than faked.
static func fight_alongside(player: Actor, partner: Actor, spared: bool = false) -> Dictionary:
	var gate := _gate(player, partner)
	if not bool(gate["ok"]):
		return _refuse(String(gate["reason"]))
	var cause := CAUSE_HELPED
	if spared:
		# ## The fight comes FIRST, and it is read off the ledger rather than a flag.
		if not _fought_alongside(player, partner):
			return _refuse(R_NO_FIGHT)
		if not _usable(_mercy_probe):
			return _refuse(R_NO_RESOLVER)
		var probed: Variant = _mercy_probe.call(player, partner)
		var answered: Dictionary = probed if probed is Dictionary else {}
		if not bool(answered.get("ok", false)):
			return _refuse(String(answered.get("reason", R_NO_MERCY)))
		cause = CAUSE_SPARED
	return _settle(player, partner, cause, {"spared": spared})

## Whether a player may act on `partner` right now, and what the ledger says about them. The
## read model a screen greys an affordance out against, so no verb refuses at the press.
## `{ok, reason, partner, standing, class, label, causes}` — deliberately carrying no `cost`
## key, because each verb's cost is its own thing and one number here would be a guess
## rather than a rule.
static func read(player: Actor, partner: Actor) -> Dictionary:
	var gate := _gate(player, partner)
	if not bool(gate["ok"]):
		return {
			"ok": false,
			"reason": String(gate["reason"]),
			"partner": "",
			"standing": 0.0,
			"class": "",
			"label": "",
			"causes": [],
		}
	var key := bond_key(partner)
	var entry := SocialApi.bond_entry(player, key)
	return {
		"ok": true,
		"reason": "",
		"partner": String(key),
		"standing": float(entry.get("standing", 0.0)),
		"class": String(entry.get("bond", "")),
		"label": String(entry.get("label", "")),
		"causes": entry.get("causes", []),
	}

# --- internals ----------------------------------------------------------------

## ## The ONE place both ledgers are written.
##
## ## ## The mirror is not optional and not a second scale
##
## `_settle` writes the player's bond with the cause, and then the partner's bond with the
## SAME cause under [method bond_key]. "You helped me" and "I helped you" are one act on two
## ledgers; a mirror at a different magnitude would make the relationship disagree with
## itself, which is the exact failure `SocialApi.apply_cause`'s docstring warns about
## ("writing both directions from one call is how a merchant ends up grateful for a gift
## they never received").
##
## ## ## ## AND the pair is filed under BOTH keys, which is a load-bearing fix
##
## The ladder and the producer do not agree on what a partner is called.
## `BrotherhoodOath` — and `bond_key` with it — writes `elder_wei`, the DEF id, because
## `NpcRosterEntry` is keyed on the def id and every gate, consent row and panel names it.
## **`Seduction.can_meet` asks the gate for `String(partner.id)`** — `seduction.gd:165` —
## which is the ACTOR id `npc_elder_wei`. Those are different rows.
##
## So a single-keyed write produces a bond that is fully formed, correctly mirrored, and
## still invisible to the one gate that was blocked behind it. That is a second, INDEPENDENT
## blocker hidden behind the first, and no amount of authoring a producer fixes it.
##
## `_settle` therefore writes the actor-id row **whenever the two keys differ**, so the
## def-id row the rest of the game reads and the actor-id row the lineage producer reads
## are both on file. **It is not a second copy of the fact in the ADR 0066 sense**: both are
## the same `SocialBond` machinery over the same cause ledger, written in one call, and the
## actor-id row is a key alias rather than a second opinion — nothing derives a number from
## it that the def-id row does not also carry.
##
## ## ## Both answers are read, and neither is allowed to lie
##
## Past every refusal of this file's own rules nothing can refuse, because `apply_cause`
## refuses only `no_partner`, `unknown_cause` and `no_social_state`. An actor with no social
## state at all is the one state a caller cannot fix, and it must NOT be reported as a
## success — so `ok` is the AND of every answer and a caller can see a false.
static func _settle(
	player: Actor, partner: Actor, cause_id: StringName, detail: Dictionary
) -> Dictionary:
	var partner_key := bond_key(partner)
	var player_key := bond_key(player)
	var before := float(SocialApi.bond_entry(player, partner_key).get("standing", 0.0))
	var mine := SocialApi.apply_cause(player, partner_key, cause_id)
	var theirs := SocialApi.apply_cause(partner, player_key, cause_id)
	## ## ## The alias is written only where it is genuinely a SECOND ROW
	##
	## ## ### The bug this replaces
	##
	## The alias legs used to be written under `partner_key != partner.id` alone. For a
	## pair whose ids do NOT both resolve to def ids, that is true, and the partner leg
	## then wrote `player.id` onto the partner's ledger — **which is already the row
	## `player_key` names**, because `bond_key(player)` degrades to `player.id` for a
	## player and the registry cannot resolve them to a roster def at all. The mirror was
	## therefore applied TWICE on the partner's side and once on the player's, so the two
	## ledgers disagreed about the same single act: the player's read +1.0 and the
	## partner's read +2.0, from one gift. That is the exact failure
	## `SocialApi.apply_cause`'s own docstring warns about, reproduced by this file.
	##
	## ## ### The rule, and why it is written this way
	##
	## **An alias is written when it names a row that does not exist yet.** The partner
	## leg needs `player.id` written as an alias only when `player_key` names something
	## else; when the two are the same string the leg above already moved that row and a
	## second `apply_cause` is a second copy of one fact. The player's leg is the mirror
	## image of the same rule, keyed on `partner_key != partner.id`.
	##
	## So the two legs are written under two independent conditions rather than one
	## shared flag, because they are two DIFFERENT conditions: the player's partner may be
	## an npc whose engine id differs from its roster def id, while the player's own id is
	## normally the very thing `bond_key` already returns. Coupling them is what made the
	## mirror land twice.
	var agreed := true
	if partner_key != partner.id:
		agreed = bool(SocialApi.apply_cause(player, partner.id, cause_id).get("ok", false))
	if player_key != player.id:
		agreed = (
			agreed and bool(SocialApi.apply_cause(partner, player.id, cause_id).get("ok", false))
		)
	return {
		"ok": bool(mine.get("ok", false)) and bool(theirs.get("ok", false)) and agreed,
		"reason": "",
		"cause": String(cause_id),
		"partner": String(partner_key),
		"actor_partner": String(partner.id),
		"standing_before": before,
		"standing_after": float(SocialApi.bond_entry(player, partner_key).get("standing", 0.0)),
		"actor_standing": float(SocialApi.bond_entry(player, partner.id).get("standing", 0.0)),
		"partner_standing": float(SocialApi.bond_entry(partner, player_key).get("standing", 0.0)),
		"detail": detail.duplicate(),
	}

## The gate every verb shares: two actors, and they are not the same one. Checked FIRST in
## every verb, before a single price is quoted or an item counted.
static func _gate(player: Actor, partner: Actor) -> Dictionary:
	if player == null:
		return {"ok": false, "reason": R_NO_ACTOR}
	if partner == null:
		return {"ok": false, "reason": R_NO_PARTNER}
	if partner == player:
		return {"ok": false, "reason": R_SAME_ACTOR}
	return {"ok": true, "reason": ""}

## ## Whether `player` has already fought beside `partner`, read off the CAUSE LEDGER.
##
## **The ledger, not a flag and not a counter this file keeps.** `SocialApi.bond_entry`
## publishes the causes that have moved this bond, and `helped_in_combat` appearing in
## that set IS the record that a fight happened — the same fact a save would restore and
## the same fact an authored `caused_by` gate reads. A separate counter here would be a
## second writer of a thing `SocialBond` already owns, and would be lost on reload while
## the cause it duplicated survived.
##
## ## ## Both keys are asked, because `_settle` writes both
##
## The verb's own ledger holds `helped_in_combat` under the def-keyed row AND the
## actor-keyed alias. A caller that reaches `fight_alongside` through one key must find
## the fight it recorded through either, or the alias would make a recorded fight
## invisible and the mercy would refuse for a fight that plainly happened. The question
## is "has this PAIR fought", so it is answered over the same key pair `_settle` writes.
static func _fought_alongside(player: Actor, partner: Actor) -> bool:
	var partner_key := bond_key(partner)
	var player_key := bond_key(player)
	if _carries(player, partner_key):
		return true
	# The actor-id alias is a second key onto ONE bond, so it answers the same question
	# about the same pair. See `_settle` for why both rows exist at all.
	if partner_key != partner.id and _carries(player, partner.id):
		return true
	return partner_key != player_key and _carries(partner, player_key)

## Whether `actor`'s bond with `other_id` carries `CAUSE_HELPED` at least once.
static func _carries(actor: Actor, other_id: StringName) -> bool:
	if actor == null or other_id == &"":
		return false
	var causes: Array = SocialApi.bond_entry(actor, other_id).get("causes", [])
	return causes.has(String(CAUSE_HELPED))

## ## Price the goods through the ONE price path, before anything moves.
##
## `EconomyApi.quote` is `economy`'s own row reader — the same one `ShopCounter` prices a
## shelf through, so a gift and a shelf cannot disagree about what a thing is worth. The four
## counts below name WHICH way `quote` failed, because `not_carried` is a player who is short
## and `not_giftable` is an object that cannot be given at all, and a panel says different
## things about them.
static func _price(player: Actor, rows: Array) -> Dictionary:
	if rows.is_empty():
		return {"ok": false, "reason": R_NOT_CARRIED}
	var quoted := ECONOMY_FACADE.quote(player, rows, &"", player.id)
	if int(quoted.get("unpriced", 0)) > 0:
		return {"ok": false, "reason": R_NOT_CARRIED}
	if int(quoted.get("uncarried", 0)) > 0:
		return {"ok": false, "reason": R_NOT_CARRIED}
	if int(quoted.get("untradeable", 0)) > 0:
		return {"ok": false, "reason": R_NOT_GIFTABLE}
	if int(quoted.get("rolled_worth", 0)) > 0:
		# ADR 0094: a rolled worth is an rng draw, so it is refused by name rather than
		# priced. Giving it would be a gift whose worth is a second roll.
		return {"ok": false, "reason": R_NOT_GIFTABLE}
	return {"ok": true, "reason": "", "price": int(quoted.get("total", 0))}

## Whether `manual_id` names a technique MANUAL the player is carrying.
##
## ## The def is resolved through `Crafting.resolve`, not `Inventory.definition_of`
##
## `definition_of` returns the def **a carried stack kept a reference to** and falls back
## to nothing when the reference is null, so a stack added without one reads as "no such
## item" — and the verb then refuses `not_a_manual` for a manual the player is plainly
## holding. `Crafting.resolve` is `items`' own id→def resolver and is what
## `EconomyApi.validate` uses to ask whether an id ships, so the two agree.
##
## Duck-typed on purpose: `ItemCategory` is an `items` class and naming it from here is a
## bare reference out of `modules/*` that `BARE_REF_UNITS` cannot see. The category is
## compared against the wire string — the shape `TechniqueDelivery._field` uses for exactly
## this reason.
static func _is_manual(player: Actor, manual_id: StringName) -> bool:
	var def: Variant = Crafting.resolve(manual_id)
	if def == null:
		return false
	return StringName(def.get("category")) == MANUAL_CATEGORY

static func _refuse(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"cause": "",
		"partner": "",
		"standing_before": 0.0,
		"standing_after": 0.0,
		"partner_standing": 0.0,
		"detail": {},
	}
