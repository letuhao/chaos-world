class_name FightLoop
extends RefCounted

## The composition root's half of a FIGHT (ADR 0197). Wiring, not rules: this decides
## WHEN a blow is available, WHO the other side is, and WHAT a decided fight writes.
## Every number is somebody else's — `CombatBoot.resolve_hit` prices a blow,
## `StatusLoop` ages a body, `CombatDuel` records a verdict.
##
## ## What this is, and what it deliberately is not
##
## The engine was complete and reachable while a player could still not FIGHT: the only
## place combat happened was `combat_readout.tscn`, one blow at a stationary drill body.
## This is the loop around it — two sides, alternating blows, a verdict, a record.
##
## **It is an EXCHANGE, not a real-time action loop.** `CombatExchange.exchange` (ADR
## 0076) already models one turn as one call — the player's blow then the opponent's
## answer — and ADR 0126 settled that combat is "a headless exchange over the existing
## share model and the spatial layer does not block it". ADR 0173 removed every real-time
## clock from the world and left one turn tier, and `tests/app/test_status_clock.gd`
## pins the frame drivers in `res://src` to an exact three-name allowlist. Building a
## second clock or a second driver was therefore not an option that needed weighing.
##
## ## The clock is the one that already exists, and NOTHING here ticks
##
## `tools/arch`'s `APP_STATE_MARKERS` reads `set_module_data`/`get_module_data` and a
## `func tick` DECLARATION, and `APP_STATE_MIN_SIGNALS` is 2 — so a `tick` beside a
## `get_module_data` would flag this file as a feature system living in the composition
## root. There is no `tick` here for that reason AND for the substantive one: ADR 0106
## gives the game exactly one clock. Elapsed time arrives as an ARGUMENT from whoever
## calls [method age], exactly as `StatusLoop.tick(delta)` does.
##
## ## `attack_speed` is the rate, and it is a GATE on the press
##
## The owner's anchor is about LENGTH: a same-realm, no-heal, no-dodge fight resolves in
## about 60 s, offence shortens it and defence/heal/shield lengthen it.
## `Stat.ATTACK_SPEED` (baseline 1.0, cap 2.5) already exists for that and is the only
## rate lever this file has. It is applied by ACCUMULATING elapsed seconds rather than by
## a `while` over a countdown, so a caller may hand this any `delta` and the same total
## always produces the same number of blows — which is the property the anchor is stated
## in, and the reason a frame rate cannot change how long a fight lasts.
##
## ## Why the opponent is a real `Actor`
##
## Because ADR 0070/0071's wound and erosion are things a BODY accumulates, and a
## dictionary pool cannot accumulate either. An opponent built by `ActorFactory` and
## installed by `CombatBoot` can be struck at a meridian, have its sea eroded, and take a
## status — so a fight's consequences outlive the blow that made them.
##
## ## Why this file holds no generator
##
## `rng` is a PARAMETER on every blow, never a member. A live fight passes `null` (every
## strike lands, the readout's own choice) or a seeded generator for a reproducible run;
## both are the caller's decision, and this file holds neither.

## Blows a fighter lands per second at `attack_speed` 1.0, from the owner's anchor:
## "~25 landed blows in 60 s ~ 0.42 blows/s". A fighter's own `Stat.ATTACK_SPEED`
## divides it.
##
## Authored here rather than in a `.tres` because it is a LOOP constant, not a damage
## constant — `combat_damage.tres` owns every number the spine reads, and nothing in the
## spine reads this. `Stat.ATTACK_SPEED`'s own cap of 2.5 (`actor_stats.gd:181`) bounds
## the fast end, so the fastest fighter blows 2.5x as often and a 60-second anchor fight
## is over in 24 seconds — which is the anchor's "offence shortens it", falling out
## rather than being a separate rule.
const BASE_BLOWS_PER_SECOND := 0.42

## The seconds one blow costs at `attack_speed` 1.0. Derived from the anchor constant
## above rather than retyped, so the rate and the interval cannot disagree.
const BASE_BLOW_INTERVAL := 1.0 / BASE_BLOWS_PER_SECOND

## The component id `BodyCultivationApi.attach_acupoints` writes and `BodyLocation`
## reads. Spelled here rather than reached into the body module's own `_`-private
## constant, because a private constant is a private detail — and this file asks the
## SAME question `CombatBoot._mechanism_for` asks, so the two must share one spelling.
const ACUPOINTS_COMPONENT := &"acupoints"

## The pool id a body's health lives in, and the one the spine spends at S9. Read here
## rather than retyped, because a fight that spent a different pool than the engine does
## would report health the engine never touched.
const HEALTH_POOL := &"health"

## The realm a minted opponent is enrolled at when the caller names none. The gate band
## of the shipped ladder, which is what every other root-built inhabitant starts on
## (`ActorFactory.with_body_cultivation`'s own default) — so an opponent's numbers are
## the numbers the player's own first-realm numbers are, which is what makes a
## same-realm comparison the anchor describes.
const OPPONENT_REALM := &"qi_refining"

## The landed blows a same-power, no-heal, no-dodge fight lasts before the verdict.
## `BALANCE-ANCHOR.md`: "`hits_to_kill` is ~25 at EVERY realm", against the owner's
## "~25 blows in 60 s". [constant BASE_BLOWS_PER_SECOND] is the RATE half of that
## sentence; this is the LENGTH half, and the two are the same anchor read twice.
##
## Authored here rather than in a `.tres` for the reason [constant
## BASE_BLOWS_PER_SECOND] gives: it is a LOOP constant, and nothing in the spine
## reads it.
const ANCHOR_BLOWS_TO_KILL := 25.0

## The source tag on the `Stat.MAX_HEALTH` offset [method _size_opponent] writes.
## `RealmScaling`'s own tag is `&"realm"` and `remove_modifiers_from` wipes that
## one wholesale — so a fight's sizing cannot share it, or the next breakthrough
## would silently erase the pool it had just re-derived.
const FIGHT_POOL_SOURCE := &"fight_pool"

## Every refusal, named. A press that quietly does nothing is the shape a player cannot
## act on (ADR 0150), so each of these is a distinct reason rather than a bare false.
const R_NO_HERO := "no_hero"
const R_NO_OPPONENT := "no_opponent"
const R_NOT_FIGHTING := "not_fighting"
const R_FIGHT_OVER := "fight_over"
const R_NO_HEALTH_POOL := "no_health_pool"
const R_SAME_ACTOR := "same_actor"
## The rate gate, not an error: the blow is not ready yet, and the seconds left are
## reported so a reader can see the lever rather than guess at it.
const R_NOT_READY := "not_ready"

## ## And the outcome words
##
## `CombatExchange`'s own vocabulary, reused verbatim rather than restated: a caller that
## already branches on `boss_defeated`/`player_lost` (ADR 0076's exchange, and
## `LootEncounterScreen.act_strike`) keeps working against a fight that never entered a
## domain. `&"ongoing"` is the only addition and is the honest word for a blow in a fight
## nobody has won yet.
const OUTCOME_ONGOING := "ongoing"
const OUTCOME_HERO_WON := "hero_won"
const OUTCOME_HERO_LOST := "hero_lost"

## Which pool ended the fight (ADR 0236). A `FightLoop` fight is a fight between two
## BODIES, so its only pool is health and `DECIDED_BY_HEALTH` is the whole vocabulary here:
## `sea` and `rupture` are the mind path's pools and belong to `CombatBoot.duel_blow`, which
## resolves a mind hit. Publishing them from a body fight would fabricate a pool that was
## never spent — which is the same class of defect as re-deriving the verdict.
const DECIDED_BY_HEALTH := "health"

## The hero this fight is FOR, and the body they are trading blows with. Both are
## `Actor`s, never dictionaries — the whole reason a wound accumulates (see the class
## docblock).
var _hero: Actor = null
var _opponent: Actor = null
## Whether a fight is live. Distinct from "an opponent exists": a decided fight keeps its
## opponent so the page can render the corpse, and `begin_fight` is what opens a new one.
var _fighting: bool = false
var _outcome: String = ""
## Seconds until this fighter's next blow is available. Accumulates DOWN from
## `BASE_BLOW_INTERVAL / attack_speed`, so a bigger speed grants a SMALLER interval.
var _cooldown: float = 0.0
## How many blows each side has landed. The anchor is stated in blows, so the loop
## publishes the count rather than only the health figures — this is what makes "about 25"
## checkable instead of asserted.
var _hero_blows: int = 0
var _opponent_blows: int = 0
## Seconds of fight time elapsed, and the seed every blow is drawn from. The seed is a
## CONSTANT here so a fight is reproducible; it is what makes a headless drive print the
## same fight twice.
var _elapsed: float = 0.0
var _seed: int = 0


func _init(hero: Actor = null, opponent: Actor = null) -> void:
	_hero = hero
	if opponent != null:
		_opponent = opponent


## Adopt a different hero, for the composition root's own rebirth path. The fight is
## CLOSED rather than re-pointed: a loop holding a body's collapse window or its blow
## count must never be carried onto a body that earned none of them.
func adopt_hero(hero: Actor) -> void:
	_hero = hero
	clear()


## Mint an opponent and open a fight against it. The convenience door a screen and a
## headless probe both call, so neither has to know how a foe is built.
##
## ## Why `_opponent` is assigned BEFORE the sizing
##
## [method _price_blow] prices the hero's blow at THIS loop's opponent, and `begin_fight`
## — which is where the field would otherwise be set — runs after. Assigning here is what
## makes the order `mint -> enrol -> install -> size -> begin` rather than a sizing step
## that silently has nothing to measure. `begin_fight` assigns the same reference again,
## which is a no-op rather than a second opponent.
##
## ## Why the opponent is built HERE rather than in `ui/`
##
## `ui/` may not name `ActorFactory` — `app/` is a `PRIVATE_UNIT` (`tools/arch/rules.py`)
## — which is the same reason `ItemWorkbenchBody._build_readout_target` exists. Minting
## is therefore a composition-root verb and this is it.
##
## ## The build order is the one `CombatBoot.install` documents, and it is not optional
##
## `bind_mechanisms` reads `acupoints` and `sea_of_consciousness` off the actor to
## CHOOSE a mechanism, and `ActorFactory`'s enrolment verbs run only after `build`
## returns — so installing first measures every path's inputs as absent and binds the qi
## fallback. Enrol, THEN install. Same order, same reason, and it is why the opponent can
## be wounded at all.
##
## ## `unlock_for_realm` is what makes an authored aim land
##
## ADR 0070 is explicit that a `named` aim at a meridian the target has never unlocked is
## NOT struck at all — "there is no channel there to subtract from" — so a freshly
## enrolled body is a sheet of twenty closed channels and a body blow would resolve to
## the empty site. This is the same call `_build_readout_target` makes and the same
## defect `body_damage_fixture.gd` documents.
##
## ## Three paths, so all three are reachable
##
## Body and mind each need their input on BOTH ends: `CombatBoot._runs_for` gates
## `MindDamage` on the ATTACKER carrying a sea and `MindDamage` divides by the
## DEFENDER's, so an opponent with neither makes the mind path silently fall back to the
## installed mechanism. The enrolment order matches the shipped player's
## (`_build_actor`) so a fight's opponent is built the way the hero is.
func start_fight(
	actor_id: StringName = &"fight_opponent", realm_id: StringName = &""
) -> Dictionary:
	if _hero == null:
		return _refuse(R_NO_HERO)
	var realm := realm_id if realm_id != &"" else OPPONENT_REALM
	var opponent := ActorFactory.spawn_inhabitant(actor_id)
	ActorFactory.with_body_cultivation(opponent, realm)
	ActorFactory.with_qi_cultivation(opponent, realm)
	ActorFactory.with_mind_cultivation(opponent, realm)
	MindCultivationApi.attach_sea(opponent)
	MindTraining.synchronize(opponent)
	opponent.meridians.unlock_for_realm(realm)
	CombatBoot.install(opponent)
	_opponent = opponent
	_size_opponent(opponent)
	return begin_fight(opponent)


## The actor this fight is for, or null.
func hero() -> Actor:
	return _hero


## The body standing across from the hero, or null when none has been named.
func opponent() -> Actor:
	return _opponent


## Whether a fight is live. A decided fight answers `false` and keeps its opponent, so a
## page can render the end of a fight rather than blanking at the moment it finishes.
func fighting() -> bool:
	return _fighting


## The fight's verdict, or `&""` before one has been decided.
func outcome() -> StringName:
	return StringName(_outcome)


## Open a fight with `opponent` and report what it started from.
##
## The blow counter starts at FULL INTERVAL rather than zero, so the first press is
## available immediately — a fight whose first blow is refused for being "not ready yet"
## is a fight that reads as broken on the first press, and the anchor is about how long
## a fight lasts, not about taxing the swing that opens it.
##
## Both sides' health is read as the fight opens, so `summary()` is a complete picture
## before anything has been thrown and a player can see what they are fighting.
func begin_fight(opponent: Actor) -> Dictionary:
	if _hero == null:
		return _refuse(R_NO_HERO)
	if opponent == null:
		return _refuse(R_NO_OPPONENT)
	if opponent == _hero:
		return _refuse(R_SAME_ACTOR)
	_opponent = opponent
	_fighting = true
	_outcome = ""
	_hero_blows = 0
	_opponent_blows = 0
	_elapsed = 0.0
	_cooldown = _interval_of(_hero)
	return {
		"ok": true,
		"reason": "",
		"outcome": OUTCOME_ONGOING,
		"hero_health": _health_of(_hero),
		"hero_health_max": _maximum_of(_hero),
		"opponent_health": _health_of(_opponent),
		"opponent_health_max": _maximum_of(_opponent),
		"blows_remaining": _cooldown,
	}


## Age the fight by `delta` seconds and report whether the hero's next blow is ready.
##
## The delta is NOT clamped to a frame: a caller hands down the time that passed, and a
## fight that accumulated 600 seconds in one call has had 600 seconds of blows come due.
## That is what makes the anchor a property of the LOOP rather than of a frame rate, and
## it is the same rule `StatusLoop.tick(delta)` follows for the same reason.
##
## **Negative and non-finite deltas are refused by name** rather than being clamped to
## zero silently: a caller with a bad clock should learn its clock is bad. A zero delta
## is legitimate and simply means nothing came due.
func age(delta: float) -> Dictionary:
	if _hero == null:
		return _refuse(R_NO_HERO)
	if not is_finite(delta):
		return _refuse(R_NOT_READY)
	if delta < 0.0:
		return _refuse(R_NOT_READY)
	if not _fighting:
		return {"ok": true, "reason": "", "ready": true, "blows_remaining": 0.0}
	_elapsed += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	return {
		"ok": true,
		"reason": "",
		"ready": _cooldown <= 0.0,
		"blows_remaining": _cooldown,
		"elapsed": _elapsed,
	}


## Throw one blow and take the answer, in one exchange. This is the whole verb.
##
## ## Why the opponent answers in the SAME call
##
## `CombatExchange.exchange` models a turn as both sides' contributions resolved from one
## set of rolls (ADR 0076), and ADR 0126 settled that the encounter layer does not block
## the spine. Splitting it into "my turn" and "their turn" would make the opponent's
## blow a second press a player could decline — which is a dodge mechanic no ADR describes
## and the anchor explicitly excludes ("no dodging").
##
## ## Both blows go through `CombatBoot.resolve_hit`
##
## The same entry point `_resolve_technique_hit` and `_readout_blow` use, so a body
## technique wounds at a meridian in a fight exactly as it does on the readout, and the
## per-hit mechanism switch (ADR 0161) applies to both sides. **This is not the share
## model**: ADR 0123/0126 keep `CombatApi.exchange` resolving authored boss encounters,
## and nothing here changes that. A fight between two `Actor`s spends the defender's own
## health pool, which is the pool that scales with realm — the thing the share model
## cannot do and does not need to do for authored content.
##
## ## The RATE is applied to the hero only
##
## The hero's interval is `BASE_BLOW_INTERVAL / attack_speed` and the opponent gets the
## neutral one. A fighter who has built offence lands more blows in the same sixty
## seconds and the fight is shorter; that is the anchor's whole lever, and it is a stat
## the player already owns rather than a rule this file adds.
func exchange(seed_value: int = 0) -> Dictionary:
	# Every refusal is decided BEFORE the roll, in one pass, so this verb carries exactly
	# two exits: a refusal or the exchange itself. The named reasons are unchanged and are
	# the same list `begin_fight` and `age` publish.
	var refusal := _refusal_for_exchange()
	if not refusal.is_empty():
		return _refuse(String(refusal.get("reason", R_NOT_FIGHTING)))
	var blow := _strike(_hero, _opponent, seed_value)
	_hero_blows += 1
	# The rate gate RESETS on a blow that was actually thrown. An unanswered blow does not
	# recharge the hand: a fight whose rate depended on how long the last animation took
	# would be a real-time loop wearing an exchange's clothes.
	_cooldown = _interval_of(_hero)
	var answer := {"ok": false, "reason": "no_opponent", "amount": 0.0, "crit": false}
	if _health_of(_opponent) > 0.0:
		answer = _strike(_opponent, _hero, seed_value + 1)
		_opponent_blows += 1
	var result := {
		"ok": true,
		"reason": "",
		"outcome": OUTCOME_ONGOING,
		"model": &"combat_engine",
		"hero_blow": blow,
		"opponent_blow": answer,
		"hero_health": _health_of(_hero),
		"hero_health_max": _maximum_of(_hero),
		"opponent_health": _health_of(_opponent),
		"opponent_health_max": _maximum_of(_opponent),
		"hero_blows": _hero_blows,
		"opponent_blows": _opponent_blows,
		"elapsed": _elapsed,
		"wounds": _wounds_of(_opponent),
		"blows_remaining": _cooldown,
	}
	# ## And the verdict, from the health pools alone
	#
	# A decided fight is reported by whichever pool reached zero, and the DECISION is
	# made here rather than inferred by the caller. A caller that re-derived it would have
	# two rules about when a fight ends, and they would drift on a corpse-with-health-left.
	#
	# `_decide` writes the duel ledger and the fate through `CombatDuel`, which is the
	# module that owns a fight's record (ADR 0076), and then CLOSES the loop, so a second
	# exchange is refused by name rather than throwing blows at a corpse.
	if _health_of(_opponent) <= 0.0:
		return _decide(OUTCOME_HERO_WON, result)
	if _health_of(_hero) <= 0.0:
		return _decide(OUTCOME_HERO_LOST, result)
	return result


## The reason this exchange may not be thrown, as `{"reason": ...}`, or `{}` when it may.
## Every check is a GUARD on state, in the order a caller would reason about them, and a
## corpse spends nothing — refused before the roll, exactly as `CombatDuelHit` refuses
## `defender_slain`.
##
## Returned as a dictionary rather than as a bare reason string so this stays a predicate:
## `is_empty()` is the question "may I throw?", and the reason travels with the answer.
func _refusal_for_exchange() -> Dictionary:
	if _hero == null:
		return {"reason": R_NO_HERO}
	if _opponent == null:
		return {"reason": R_NO_OPPONENT}
	if not _fighting:
		return {"reason": R_NOT_FIGHTING}
	if _health_pool(_hero) == null or _health_pool(_opponent) == null:
		return {"reason": R_NO_HEALTH_POOL}
	if _health_of(_opponent) <= 0.0 or _health_of(_hero) <= 0.0:
		return {"reason": R_FIGHT_OVER}
	return {}


## End the fight without a verdict — walking away from a live fight. The combat-scope
## purge (ADR 0089) belongs to the caller, because ADR 0106 gives `StatusLoop.exit_combat`
## the verb and this file holds no clock to purge from.
func disengage() -> Dictionary:
	var was_fighting := _fighting
	_fighting = false
	_cooldown = 0.0
	_outcome = ""
	return {"ok": true, "reason": "", "was_fighting": was_fighting}


## Drop the fight entirely: no opponent, no verdict, no counters. The composition root's
## rebirth path calls this beside `adopt_hero`, because a loop's counters belong to the
## body that earned them.
func clear() -> void:
	_opponent = null
	_fighting = false
	_outcome = ""
	_hero_blows = 0
	_opponent_blows = 0
	_elapsed = 0.0
	_cooldown = 0.0


## The fight as primitives, so a screen renders it without naming anything this file
## owns. This is the read model every panel and every headless probe reads, and it is
## REPUBLISHED on each call rather than cached, so a report can never be older than the
## fight it describes.
func summary() -> Dictionary:
	if _hero == null:
		return {}
	var ledger := _wounds_of(_opponent)
	return {
		"hero_id": String(_hero.id),
		"opponent_id": "" if _opponent == null else String(_opponent.id),
		"fighting": _fighting,
		"outcome": _outcome,
		"elapsed": _elapsed,
		"hero_health": _health_of(_hero),
		"hero_health_max": _maximum_of(_hero),
		"opponent_health": _health_of(_opponent),
		"opponent_health_max": _maximum_of(_opponent),
		"hero_blows": _hero_blows,
		"opponent_blows": _opponent_blows,
		"blows_remaining": _cooldown,
		"attack_speed": _attack_speed(_hero),
		"blow_interval": _interval_of(_hero),
		"wound_count": (ledger.get("severity", {}) as Dictionary).size(),
		"wounds": ledger,
		"duel": _duel_view(),
	}


# --- Plumbing ---------------------------------------------------------------


## One blow through the SPINE, as primitives. This is the composition root's whole
## contribution to a fight's arithmetic: it chooses no number, it routes the hit to the
## engine that owns the number and hands back what that engine published.
##
## `rng` is null when the caller passed no seed, which the spine reads as "nothing
## random happens and every attack lands" (ADR 0087's S12). That is the honest default
## for a headless drive: a whiff and a gut-punch are different events, and a fight whose
## ledger depends on the frame's RNG cannot be asserted on.
func _strike(attacker: Actor, defender: Actor, seed_value: int) -> Dictionary:
	var technique := _swing()
	var rng: Variant = null
	if seed_value != 0:
		rng = RandomNumberGenerator.new()
		rng.seed = (seed_value * 2654435761 + absi(hash(String(attacker.id)))) & 0x7FFFFFFF
	var outcome := CombatBoot.resolve_hit(
		attacker, defender, technique, CombatEngineApi.tuning(), rng
	)
	return outcome.to_dict()


## The authored inputs a bare blow carries, and why they are in-memory rather than a
## `.tres`. There is no authored "fight swing" in `game/data/techniques/` and inventing
## one would be authoring content the design does not have; the readout's own
## `_readout_technique` sets the same three fields in memory for the same reason. A swing
## leaves no record, so a def that could be saved would be a lie about the shape.
##
## **The path follows the OPPONENT, not the attacker.** A fight in which the hero is a
## body cultivator and the opponent is not would resolve a body blow at an actor with no
## `acupoints` component, and `CombatBoot.mechanism_for_hit` refuses that mechanism and
## falls back — so the blow silently becomes qi. Reading the defender's own enrolment is
## what makes "wound the body you are fighting" mean anything.
func _swing() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.path = _path_of(_opponent)
	def.magnitude = CombatBoot.BARE_SWING_MAGNITUDE
	def.element_share = CombatBoot.BARE_SWING_SHARE
	def.element = ElementStats.FIRE
	return def


## The mechanism path `actor` can actually produce, asked of the composition root's own
## named answer rather than re-derived. An opponent with no path of its own falls back to
## qi, which is the same neutral answer `CombatBoot.bind_mechanisms` documents for an
## actor whose inputs are absent.
func _path_of(actor: Actor) -> StringName:
	if actor == null:
		return PathState.QI
	var body := actor.component(ACUPOINTS_COMPONENT) != null
	var mind := MindCultivationApi.sea(actor) != null
	if body and actor.path(PathState.BODY) != null:
		return PathState.BODY
	if mind and actor.path(PathState.MIND) != null:
		return PathState.MIND
	return PathState.QI


## The seconds between this actor's blows: the anchor's neutral interval divided by the
## actor's own `Stat.ATTACK_SPEED`.
##
## A zero or non-finite speed is the NEUTRAL interval, never a zero one: a division by
## zero would be an infinite rate and a fight that ends in a single frame, which is the
## one way this loop could contradict the anchor.
func _interval_of(actor: Actor) -> float:
	if actor == null:
		return BASE_BLOW_INTERVAL
	var speed := actor.stats.derived(Stat.ATTACK_SPEED)
	if not is_finite(speed) or speed <= 0.0:
		return BASE_BLOW_INTERVAL
	return BASE_BLOW_INTERVAL / speed


## The actor's `attack_speed` as the page shows it — the same derivation [method
## _interval_of] uses, so the figure a player reads and the rate the fight runs on cannot
## disagree.
func _attack_speed(actor: Actor) -> float:
	if actor == null:
		return 1.0
	return actor.stats.derived(Stat.ATTACK_SPEED)


## Size `opponent`'s health to the anchor, once, when this loop MINTS it.
##
## ## Why a minted opponent is re-derived and an authored one is not
##
## The anchor is a statement about a POOL relative to the hero's own blow: roughly
## [constant ANCHOR_BLOWS_TO_KILL] landed blows, at whatever realm either side stands
## on. An opponent handed in through [method begin_fight] is an AUTHORED actor whose
## vitality content owns (ADR 0199), so this never touches one -- `start_fight` is the
## only caller, and it mints. Re-deriving a boss's pool here would contradict the
## 5552 content files the owner just rescaled to this same anchor.
##
## ## Why it read a bare 50, and what that measured
##
## `spawn_inhabitant` mints an inhabitant with NO base attributes, so its derived
## `MAX_HEALTH` is core's `50.0 + physique * 10.0` at `physique == 0` -- a literal
## 50 that never met the ladder, against a hero who pools 250. One blow spent it, so
## the readout fight was a ONE-PRESS WIN: the exact inversion the anchor exists to
## prevent.
##
## ## The pool is a FUNCTION of the hero's blow, not a constant
##
## An anchor in BLOWS is only expressible as a pool by multiplying by a blow, and the
## blow is the SPINE's own answer -- `CombatBoot.resolve_hit`'s `amount`, priced
## against a clone so the measurement wounds nothing and records nothing. The result
## is written as a `FLAT` offset on `Stat.MAX_HEALTH` rather than assigned to the
## pool, so it COMPOSES with `RealmScaling`'s realm `MULT` instead of replacing it:
## both sides then scale together up the ladder, which is what keeps `hits_to_kill`
## near the anchor at every realm instead of only at R1.
##
## ## And the clone exists because the target's state is an INPUT to its own damage
##
## A body blow prices off the defender's meridians and tissue (`BodyDamage.breakdown`),
## so pricing against the live opponent would measure a different body than the first
## blow actually hits. The duplicate carries the same enrolment, components and stats
## and none of the consequences, so the figure stays the same figure as the fight wears
## on.
##
## ## And a blow that prices at zero leaves the pool alone
##
## A hero whose mechanism declines every strike has no blow to divide the anchor by,
## and a pool of `0.0` is a fight that is over before it opens. The authored pool is
## left exactly as minted in that case rather than guessed at.
##
## ## And the pool is then FILLED, which is the half that was missing
##
## The sizing was written as if `set_maximum` sized the pool's contents with it. It
## does not, and that is deliberate on its own side: [method
## ResourcePool.set_maximum] CLAMPS `current` into the new range so a breakthrough
## that raises `MAX_HEALTH` cannot heal the cultivator, and two callers say so in
## their own words -- `Actor.attach_core_resources` ("later capacity changes never
## refill") and `MindTraining` ("never grants energy"). Sizing the fight's opponent
## is the one place where a raise is meant to be a new body, so the FILL is written
## here rather than changed there: `set_maximum` is shared by cultivation, essence
## and item code, and making it refill would hand every one of those a heal.
##
## What it measured: the cap was `2050.0` while `current` stayed the bare minted
## `50.0`, so the anchor arithmetic was right and the live fight was still a
## ONE-PRESS WIN -- `hits_to_kill` near 1, not the owner's ~25. A newly minted
## opponent has never been struck, so at full health is the only honest reading of
## it; `pool.current` is assigned rather than filled via `change` so it cannot
## re-enter the pool's `changed` -> `mark_stats_dirty` -> `_sync_core_resources`
## cycle a second time.
func _size_opponent(opponent: Actor) -> void:
	var blow := _price_blow()
	if blow <= 0.0:
		return
	var pool := _health_pool(opponent)
	if pool == null:
		return
	opponent.stats.add_modifier(
		StatModifier.new(
			Stat.MAX_HEALTH, Stat.Op.FLAT, blow * ANCHOR_BLOWS_TO_KILL, FIGHT_POOL_SOURCE
		)
	)
	# `set_maximum` re-reads the stat the modifier just moved and clamps the CURRENT
	# value DOWN into the new range, so it caps the pool without disturbing a body
	# that is already in it.
	pool.set_maximum(opponent.stats.derived(Stat.MAX_HEALTH))
	pool.current = pool.maximum


## What one hero blow is worth against an unmarked body like this opponent's, or `0.0`
## when there is nothing to price.
##
## ## The clone is `to_dict`/`from_dict`, not `duplicate()`
##
## `Actor` extends `RefCounted`, so it has no `duplicate()` -- calling one aborts the
## test that reaches it. Its own save round-trip is the copy that is already specified
## to carry every stat-bearing surface the spine reads: base attributes, paths, the
## meridian network, the acupoint set, the sea and the pools. That is exactly the set
## `BodyDamage.breakdown` prices off, which is why the clone and the live opponent
## answer the same question -- and why a clone restored from a save is a correct one.
##
## A `null` generator is passed so the spine's S2 band lands every strike and S3's crit
## never fires (ADR 0087's S12), making this the blow's NORMAL value rather than one
## sample of a roll.
func _price_blow() -> float:
	if _hero == null or _opponent == null:
		return 0.0
	var sample := Actor.from_dict(_opponent.to_dict())
	if sample == null:
		return 0.0
	var outcome := CombatBoot.resolve_hit(_hero, sample, _swing(), CombatEngineApi.tuning(), null)
	return maxf(0.0, float(outcome.amount))


## The health pool, or null. `attach_core_resources` sizes it from the derived
## `MAX_HEALTH`, so an actor nobody attached pools to can still be hit — and an actor
## with no pool at all is REFUSED by name rather than silently treated as a corpse.
func _health_pool(actor: Actor) -> ResourcePool:
	if actor == null:
		return null
	var pool := actor.resource(HEALTH_POOL) as ResourcePool
	if pool == null:
		actor.attach_core_resources()
		pool = actor.resource(HEALTH_POOL) as ResourcePool
	return pool


## An actor's current health, or `0.0` for an actor with none. Zero is the honest answer
## for "no pool" because a body with no health cannot be fought, and every caller of this
## reads it as "can this blow matter".
func _health_of(actor: Actor) -> float:
	var pool := _health_pool(actor)
	return 0.0 if pool == null else pool.current


## An actor's maximum health, or `0.0`. The denominator of every ratio a page draws, and
## zero is the honest answer for an actor nobody sized.
func _maximum_of(actor: Actor) -> float:
	var pool := _health_pool(actor)
	return 0.0 if pool == null else pool.maximum


## The opponent's wound ledger as the primitives a save carries, or `{}`. Read through
## `CombatEngineApi.wounds_of`, so this file names no wound type and the ledger a fight
## writes is the ledger `CombatBoot.install` bound (ADR 0140).
func _wounds_of(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var ledger := CombatEngineApi.wounds_of(actor)
	if ledger == null:
		return {}
	return ledger.to_dict()


## The hero's duel record as primitives, so a page shows the fight it is in beside the
## fights already on the ledger without reaching into `combat`.
func _duel_view() -> Dictionary:
	if _hero == null:
		return {}
	return CombatDuel.view(CombatDuel.normalize(_hero.get_module_data(CombatDuel.MODULE_KEY)))


## Write the verdict and close the fight.
##
## The write goes to `CombatDuel`, which owns a fight's record (ADR 0076), through the
## SAME two verbs `CombatBoot._record_win` and `CombatExchange._record_defeat` already
## call. The loop therefore does not have its own ledger, and a duel won in a fight and a
## duel won through `PlayerAdapter.attack` land on the same record — which is what
## `CombatDuel`'s docblock claims and what a second ledger would quietly break.
func _decide(outcome: String, result: Dictionary) -> Dictionary:
	_fighting = false
	_outcome = outcome
	var duel := CombatDuel.normalize(_hero.get_module_data(CombatDuel.MODULE_KEY))
	var entry := {
		"outcome": outcome,
		"opponent_id": String(_opponent.id) if _opponent != null else "",
		"wins": int(duel.get("wins", 0)) + (1 if outcome == OUTCOME_HERO_WON else 0),
		"defeats": int(duel.get("defeats", 0)) + (1 if outcome == OUTCOME_HERO_LOST else 0),
		"blows": _hero_blows,
	}
	if outcome == OUTCOME_HERO_WON:
		CombatDuel.record_win(duel, entry, _hero)
	else:
		CombatDuel.record_defeat(duel, entry, _hero)
	_hero.set_module_data(CombatDuel.MODULE_KEY, duel)
	result["outcome"] = outcome
	result["duel"] = CombatDuel.view(duel)
	# ## `decided_by`, published and NEVER re-derived (ADR 0236)
	#
	# Which pool ended it. A body fight's only pool is health, so `""` is the honest
	# answer here and `sea` / `rupture` are the mind path's — a body fight must not
	# fabricate a pool it did not spend. A caller branches on `outcome` and reads this to
	# know WHY the fight stopped, never on a number.
	result["decided_by"] = DECIDED_BY_HEALTH
	# ## The zero crossing, and the ONLY death seam (ADR 0236)
	#
	# `DomainFight.cross_zero` is the one registered callable in the game that fires on an
	# actor's health crossing zero, and `app/` is the only layer allowed to hold it. This
	# is the layer that SPENT the pool, so this is where it fires — and it fires on the
	# LOSER, because a win is a counter and a loss is a history with a body attached.
	#
	# The hero losing is NOT fired here. `SoulDeath` already polls the PLAYER's health
	# every frame and owns that resolution (ADR 0130), so a second firing would resolve
	# one death twice.
	if outcome == OUTCOME_HERO_WON and _opponent != null:
		DomainFight.cross_zero(_opponent, DECIDED_BY_HEALTH, String(_hero.id))
	# **The fact ledger is written HERE and not only through `CombatDuel`.**
	# `record_defeat`/`record_win` earn a FATE; `CombatFacts` is the world-facing ledger
	# `what_the_rotation_cost.tres` gates on (ADR 0137), and `CombatBoot._record_win`
	# makes the same second write for the same reason — routing a fight through a
	# different model must not silently retire a quest gate.
	if outcome == OUTCOME_HERO_WON:
		CombatFacts.record_duel_won(_hero)
	return result


## One refusal in the shape [method exchange] returns, so a caller branches on `ok` and
## reads a reason rather than inspecting a half-built dictionary. `model` names the engine
## anyway: a refusal is a refusal to SPEND, never a refusal to resolve through the spine.
func _refuse(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"outcome": _outcome,
		"model": &"combat_engine",
		"hero_blow": {},
		"opponent_blow": {},
		"hero_health": _health_of(_hero),
		"hero_health_max": _maximum_of(_hero),
		"opponent_health": _health_of(_opponent),
		"opponent_health_max": _maximum_of(_opponent),
		"hero_blows": _hero_blows,
		"opponent_blows": _opponent_blows,
		"elapsed": _elapsed,
		"wounds": _wounds_of(_opponent),
		"blows_remaining": _cooldown,
	}
