extends TestCase

## **THE RULE: a boss fight is not a wound that persists.** ADR 0236 §4 — *"The loser is
## walked out whole. `exchange._answer` restores the player to full vitality at the end of
## the file (`exchange.gd:659`) and `FightLoop` carries no wound forward. A boss fight is not
## a wound that persists — **this is a disclosed thinness, not a rule**"* — closed on the
## `FightLoop` path.
##
## ## Why this suite exists at all
##
## The thinness was measured, not inferred. A previous agent's instrumented run in the
## Domain program produced:
##
## ```
## ZZDIAG room='ash_heart#10'  blows=2  hero=118.765182/170.0  outcome='hero_won'
## ZZDIAG room='ash_heart#17'  blows=2  hero= 67.530364/170.0  outcome='hero_won'
## ZZDIAG room='ash_heart#23'  blows=2  hero= 16.295546/170.0  outcome='hero_won'
## ZZDIAG room='ash_heart#3'   blows=60  hero=  0.000000/170.0  outcome='hero_lost'
## ```
##
## `170 -> 118.8 -> 67.5 -> 16.3 -> 0`: the hero carried door one's damage into door four and
## died there. A boss blow is spent as `share * defender_pool.maximum` (`duel_hit.gd:82`) — an
## ABSOLUTE number off the hero's own maximum, not a percentage of what is left — so a wounded
## body takes a full-size hit and the walk never gets better. `DomainFight.record_verdict`'s
## loss branch then called `abandon_band`, wiping `open_index` and `kills`: a player clearing a
## band of bosses died by attrition, which is not what ADR 0236 decided.
##
## **Every one of those three doors was a `hero_won`.** That is what decides the shape of this
## rule, and it is the question the task posed: the door fight the hero SURVIVES is the one
## that must leave the body whole, because the door after it is fought from that pool.
##
## ## What is asserted, and what is deliberately NOT
##
## **A pool's `current` at its `maximum`, on the hero, after a decided WIN — and, on a LOSS,
## that the body is still at zero.** Every assertion is a STATE (a pool), never a signal and
## never a count of calls: the repo's rule is that consequence is observable, and a
## call-count assertion would pass on a restore that fired for the wrong body.
##
## ## And what this file must NOT become
##
## It must not become a second copy of the rule. The restore lives ONCE, in
## `FightLoop._decide` (`fight_loop.gd`), matching `CombatExchange._record_defeat`
## (`exchange.gd:655-659`) — the reference ADR 0236 names. The value the two copies share is
## pinned ONCE here, at [method test_the_walk_out_lands_on_the_reference_implementations_own_value],
## rather than restated in each place, so the two definitions cannot drift apart silently.

## The realm both sides stand on — the same band `FightLoop.OPPONENT_REALM` names, so a
## case's fight is a real fight and not a one-press win against a bare `50.0`.
const REALM := &"qi_refining"

## How many presses a case may throw before it declares the fight never ended.
##
## **A bound, not a hope.** Every `while` below advances `presses` on each pass against this
## CONSTANT, which is the AGENTS.md rule inverted: the counter is one this body moves, not a
## container size it grows. There is no other `while` in this file.
const MAX_PRESSES := 80

## The seed every press in this file uses. A CONSTANT, so a failure is reproducible.
const SEED := 7

## The fraction of a full pool the hero carries INTO a won fight in the win cases.
##
## ## Why NOT a tenth, and why not a rounding error
##
## A hero entering badly wounded may DIE before the fight is won — and it must, because that
## is the rule's own point. So the wound is set deep enough that the restore is unmistakable
## (`0.60`, a third of the pool missing) and shallow enough that one boss blow cannot end the
## fight: a blow is `share * maximum` with `share` well under a third at this realm, so
## `0.60 -> 1.0` is a band walk that a single exchange cannot cross.
const WOUNDED_TO := 0.60

## The fraction of its own pool a one-blow opponent is FILLED to, so the hero's blow kills it
## in one press. Not a `set_maximum`: `ActorPools.sync_core` rewrites `maximum` from the
## derived stats whenever they are read, and a fixture that set it measured nothing. The
## ceiling is `1.0`, so a pool already below this is left alone and a big hero blow still
## takes it.
const ONE_BLOW_TO := 0.02


func setup() -> void:
	pass


func teardown() -> void:
	pass


# ── the rule ────────────────────────────────────────────────────────────────


## ## A WON fight walks the hero out whole
##
## The first half of the rule, and the half the measured attrition broke: the hero who WINS
## the band is the hero who has to survive the whole band, so this is where attrition
## actually costs a player their run.
##
## The hero enters the fight already wounded — a hero who enters whole and leaves whole
## proves nothing, and the defect being closed is precisely a carry-ACROSS. The measured run
## was `170 -> 118.8 -> 67.5 -> 16.3`, so the case reproduces that shape rather than
## asserting against it.
func test_a_won_fight_walks_the_hero_out_whole_and_not_worse() -> void:
	expect_assertions(3)
	var hero := _hero()
	var opponent := _one_blow_opponent()
	var loop := _loop(hero, opponent)
	var pool := _resynced_health(hero)
	pool.change(pool.maximum * WOUNDED_TO - pool.current)
	assert_eq(pool.current, pool.maximum * WOUNDED_TO, "the hero entered the fight wounded")

	_win(loop)

	assert_eq(String(loop.outcome()), FightLoop.OUTCOME_HERO_WON, "the fight was won outright")
	# The rule, as a STATE: the hero's pool is whole after a decided fight, so the NEXT door
	# of the band is fought from a full body rather than on the last of the last.
	assert_eq(
		pool.current,
		pool.maximum,
		"the hero is walked out whole, so a band is not cleared by attrition"
	)


## ## A LOST fight is NOT walked out whole, and that is the settled reading
##
## **This is the half of the rule the first measurement read backwards, and this case is
## where that is pinned.** "The loser is walked out whole" applied to the `FightLoop` path
## would heal the PLAYER's pool the instant it crossed zero — and `SoulDeath.is_dead`
## (`soul_death.gd:312`) polls `health <= 0.0` every frame, with
## `item_workbench_play.poll_death` armed on it. A heal in the same call would resolve no
## death at all: ADR 0130's re-embodiment, the guardian spend and the `soul_died` fact would
## all stop firing, silently, for the player.
##
## So the two losers ADR 0236's sentence names are DIFFERENT losers, and the sentence was
## written about one of them:
##
## - **`CombatExchange._record_defeat`'s loser** is the loser of an ENCOUNTER. Their loss is
##   a RUN that stops (`LootApi.abandon`, rule E4), the reward is never minted, and the body
##   that walks away is a player resuming — so carrying it out is right, and
##   `exchange.gd:655-659` does it.
## - **This path's loser is the PLAYER**, and the player's zero crossing is a `soul`
##   resolution, not a carry-out. `FightLoop._decide` already says so in its own words: *"The
##   hero losing is NOT fired here. `SoulDeath` already polls the PLAYER's health every frame
##   and owns that resolution."*
##
## If a future change heals the loser, this case goes red, and the ADR recorded with that
## change is the thing to read.
func test_a_lost_fight_is_not_walked_out_whole_and_the_death_stays_observable() -> void:
	expect_assertions(4)
	var hero := _hero()
	# **The opponent is minted and sized BEFORE the hero is shrunk.** `_surviving_opponent`
	# sizes it from the hero's OWN pool, so a hero already at one point produced an opponent
	# with one point — which died to the hero's first press and decided the fight `hero_won`
	# instead of the loss this case exists to pin.
	var opponent := _surviving_opponent(hero)
	# A hero with ONE point, sized through the `MAX_HEALTH` STAT rather than through
	# `pool.maximum`, because `ActorPools.sync_core` rewrites `maximum` from the derived
	# stats whenever they are read — so a hand-set `maximum` is overwritten before the blow is
	# spent and the hero survives what the case meant to kill them with. The opponent is one
	# that OUTLASTS the hero, so the fight is still running when the hero's point goes.
	var pool := _hero_pools_at(hero, 1.0)
	pool.change(1.0 - pool.current)

	var loop := _loop(hero, opponent)
	# Seed zero so the exchange is actually thrown rather than missed: the hero's blow lands
	# on a pool that outlives it, and the always-landing answer takes the hero's one point.
	loop.exchange(0)

	assert_eq(String(loop.outcome()), FightLoop.OUTCOME_HERO_LOST, "the fight was lost outright")
	# **The death is still a death.** This is the load-bearing assertion: a restore on the
	# loss would put the pool back above zero inside `exchange`, and `SoulDeath`'s poll would
	# then never see a body at zero.
	assert_eq(pool.current, 0.0, "the player is NOT carried out — the death seam still has a body")
	assert_eq(
		int(
			CombatDuel.view(CombatDuel.normalize(hero.get_module_data(CombatDuel.MODULE_KEY))).get(
				"defeats", 0
			)
		),
		1,
		"the loss is on the loser's own ledger, exactly as before"
	)
	# And the fight stays CLOSED: a restore that made the loser whole would leave a loop that
	# can be pressed into a second exchange against a corpse, which is the defect `_decide`'s
	# docblock gives for closing it.
	assert_eq(
		bool(loop.exchange(0).get("ok", true)),
		false,
		"and the decided fight stays closed, so a healed loser is never pressed again"
	)


## ## The restore lands on the value the REFERENCE lands on
##
## ADR 0236 names `exchange.gd:655-659` as the reference implementation and this file as
## the thinness beside it, so the risk is not "is there a restore" but "do the two copies
## agree". "Two copies of a rule that can disagree is the failure mode this repo's ADRs
## repeatedly name" — so this case pins the figure the two copies are MEANT to share, stated
## once HERE rather than restated in each place:
##
## **`change(maximum - current)`, spent through `change` and never assigned to `current`.**
##
## The value is asserted as the pool's OWN maximum rather than a literal, because that is
## what makes the two paths interchangeable: a body is carried out to ITS full pool, and a
## hero whose `MAX_HEALTH` moved with a breakthrough is carried out to the new one. The pool
## is deliberately NOT the hero's own authored one — the case sizes it itself, so the restore
## is measured against a pool the fight actually spent.
func test_the_walk_out_lands_on_the_reference_implementations_own_value() -> void:
	expect_assertions(2)
	var hero := _hero()
	# **Sized through the STAT, not through `pool.maximum`.** `ActorPools.sync_core` writes
	# `pool.set_maximum(stats.derived(Stat.MAX_HEALTH))` whenever the derived stats are read,
	# so a hand-set `maximum` is overwritten mid-fight and a case that sized the pool that
	# way measures nothing — which is what the first version of this case did, and why it
	# reported a hero at `170.0` it had just set to `12.0`. A FLAT `MAX_HEALTH` modifier is
	# the idiom `test_core_resources.gd:29` uses, and it survives because the pool is then
	# resized FROM the stat rather than against it.
	var pool := _hero_pools_at(hero, 12.0)
	pool.change(4.0 - pool.current)
	var loop := _loop(hero, _one_blow_opponent())

	_win(loop)

	assert_eq(String(loop.outcome()), FightLoop.OUTCOME_HERO_WON, "the fight was decided a win")
	assert_eq(
		pool.current,
		pool.maximum,
		"carried out to the pool's OWN maximum — `change(maximum - current)`, the reference's value"
	)


## ## And it is spent through `change`, so the pool's `changed` edge still fires
##
## The half a restore written the obvious way gets wrong. Assigning
## `pool.current = pool.maximum` heals the body and leaves every stat cache watching the pool
## holding pre-heal figures — the reason `exchange.gd:656` gives for spending a difference
## instead. A screen reading a healed hero through a stale cache is the defect this asserts
## against.
##
## **The count is DIFFERENTIAL, and an absolute would be wrong.** A `FightLoop` exchange is
## `CombatBoot.resolve_hit` on both sides, and the spine spends the defender's pool through
## several `change` calls of its own — so an absolute edge count measures the SPINE and
## breaks the moment a mechanism writes one more. What this compares is the edges the hero's
## pool emitted while the fight was LIVE against the edges it has emitted by the verdict, and
## the walk-out is the difference. A restore written as an assignment to `current` emits
## nothing at all, so the difference is zero and the case goes red.
func test_the_walk_out_spends_through_change_so_the_pool_still_signals() -> void:
	expect_assertions(4)
	var hero := _hero()
	var opponent := _one_blow_opponent()
	# The pool is read AFTER the loop opens it, so it is the LIVE pool the fight spends and
	# the one the walk-out spends — not a reference captured before a sync swapped it.
	var loop := _loop(hero, opponent)
	var pool := _resynced_health(hero)
	pool.change(pool.maximum * WOUNDED_TO - pool.current)

	var edges := [0]
	pool.changed.connect(func() -> void: edges[0] = int(edges[0]) + 1)
	# The edges the LIVE fight spends, measured on the press before the deciding one: the
	# opponent answers only while it is standing (`fight_loop.gd:358`).
	loop.exchange(SEED)
	var while_live := int(edges[0])
	assert_eq(String(loop.outcome()), "", "the fight is still live after one press")

	_win(loop)

	assert_eq(String(loop.outcome()), FightLoop.OUTCOME_HERO_WON, "the fight was decided a win")
	assert_eq(
		int(edges[0]) > while_live,
		true,
		"the verdict spent an edge `change` emits and an assignment to `current` does not"
	)
	assert_eq(pool.current, pool.maximum, "and the body it healed is whole")


## ## A restore is a POOL write and nothing else
##
## The half a walk-out must NOT do. ADR 0236 §4 puts what a fight pays on the RUN ("The run
## is abandoned, and its reward is never minted") and on the loser's ledger, and a heal that
## also rewrote either would be a second rule about what a verdict pays. So the ledger is
## asserted exactly as the win wrote it, and the walk-out is asserted not to have touched it.
func test_the_walk_out_touches_the_pool_and_not_the_ledger() -> void:
	expect_assertions(3)
	var hero := _hero()
	var loop := _loop(hero, _one_blow_opponent())
	_win(loop)

	var duel := CombatDuel.view(CombatDuel.normalize(hero.get_module_data(CombatDuel.MODULE_KEY)))
	# ADR 0236 §4: "A win is a counter" — and the restore must not have rolled the counter
	# back or converted the win into something the fight did not decide.
	assert_eq(int(duel.get("wins", 0)), 1, "the win is on the hero's own ledger")
	assert_eq(
		String((duel.get("last_defeat", {}) as Dictionary).get("outcome", "")),
		"",
		"and the restore wrote no defeat the fight never decided"
	)
	assert_eq(
		int((duel.get("history", []) as Array).size()),
		1,
		"one decided fight, one history row — the restore added none"
	)


## ## And a fight nobody decided carries NO restore
##
## The negative half, and the half a heuristic cannot pass by accident. `disengage` is a walk
## away from a LIVE fight, not a verdict, so it is not an ending a body is carried out of —
## and a walk-out wired to "the fight stopped" rather than to "a fight was decided" would
## fire here, healing a hero who merely put the fight down.
func test_a_fight_that_was_never_decided_restores_nothing() -> void:
	expect_assertions(3)
	var hero := _hero()
	var loop := _loop(hero, _surviving_opponent(hero))
	var pool := _resynced_health(hero)
	# Trade one blow so the hero is genuinely hurt, and the fight is genuinely still live —
	# the first version of this case fought a bare `50.0` opponent, which died on the press
	# and decided the fight, so "nothing was restored" was true for the wrong reason. Seed
	# zero here for the opposite reason to `SEED`: this case needs the exchange to SPEND, and
	# a seeded double miss spent nothing.
	loop.exchange(0)
	var wounded := pool.current
	assert_eq(wounded < pool.maximum, true, "the exchange spent the hero's own pool")
	assert_eq(String(loop.outcome()), "", "and the fight is still live to walk away from")

	loop.disengage()

	assert_eq(pool.current, wounded, "walking away is not an ending, so nothing is restored")


# --- Fixtures ----------------------------------------------------------------


## The hero exactly as `ItemWorkbenchBody._build_actor` and `test_fight_anchor_and_tone`
## build one: body, qi and mind enrolled, meridians unlocked, then `CombatBoot.install`.
func _hero() -> Actor:
	var actor := ActorFactory.build(&"player", {Stat.PHYSIQUE: 12.0, Stat.SPIRIT: 8.0})
	ActorFactory.with_body_cultivation(actor, REALM)
	ActorFactory.with_qi_cultivation(actor, REALM)
	ActorFactory.with_mind_cultivation(actor, REALM)
	MindCultivationApi.attach_sea(actor)
	MindTraining.synchronize(actor)
	actor.meridians.unlock_for_realm(REALM)
	CombatBoot.install(actor)
	return actor


## An opponent minted the way `FightLoop.start_fight` mints one, so a case is not balancing
## its own fixture. `start_fight` also SIZES it and this does not: `begin_fight` adopts an
## AUTHORED body and must never overwrite its vitality (ADR 0199), so a case that wanted the
## anchor's figure would call `start_fight` instead.
##
## **As minted this pools at the bare `50.0`** — `spawn_inhabitant` gives an inhabitant no
## base attributes, so its derived `MAX_HEALTH` is core's `50.0 + physique * 10.0` at
## `physique == 0` — which is why no case fights it bare: one hero blow kills it, and a corpse
## never answers (`fight_loop.gd:358`). The two helpers below size it deliberately.
func _opponent() -> Actor:
	var opponent := ActorFactory.spawn_inhabitant(&"walk_out_reference")
	ActorFactory.with_body_cultivation(opponent, REALM)
	ActorFactory.with_qi_cultivation(opponent, REALM)
	ActorFactory.with_mind_cultivation(opponent, REALM)
	MindCultivationApi.attach_sea(opponent)
	MindTraining.synchronize(opponent)
	opponent.meridians.unlock_for_realm(REALM)
	CombatBoot.install(opponent)
	return opponent


## An opponent the hero's blow finishes in ONE exchange, so a case about the hero's walk-out
## is decided in the press the case expects rather than in arithmetic it did not set.
##
## **A pool FILL, never a `set_maximum`** — the same rule `test_domain_run_chain.gd` gives
## (`_size_for_a_bare_hero`), and for the same reason: `ActorPools.sync_core` writes
## `pool.set_maximum(stats.derived(Stat.MAX_HEALTH))` whenever the derived stats are read, so
## a hand-set `maximum` is overwritten mid-fight and a case that sized the pool that way
## measured nothing. `ResourcePool.change` clamps into `[0, maximum]`, so filling `current`
## is the one field a fixture may set.
##
## One press and no answer: the opponent is down before its turn comes, which is what
## `fight_loop.gd:358` guards with `if _health_of(_opponent) > 0.0`. So the hero's own pool
## is spent by NOTHING but the walk-out, and the edges below are the restore's alone.
func _one_blow_opponent() -> Actor:
	var opponent := _opponent()
	var pool := opponent.resource(&"health") as ResourcePool
	pool.change(maxf(1.0, pool.maximum * ONE_BLOW_TO) - pool.current)
	return opponent


## An opponent at FULL pool, which outlives the hero for the presses a case throws and is
## what the loss and the walk-away cases need: a fight still running when the hero's own
## point is spent.
##
## Not the bare `50.0` a `spawn_inhabitant` mints as a case fixture on purpose — a case that
## fought it unsized died on the first exchange and decided the fight the wrong way round,
## which is how the first version of the loss case reported `hero_won`.
func _surviving_opponent(hero: Actor) -> Actor:
	var opponent := _opponent()
	# **Sized through the STAT**, for the reason `_hero_pools_at` gives: a hand-set
	# `pool.maximum` is overwritten by `ActorPools.sync_core` before the first blow. The
	# figure wanted is the hero's own pool, so the two sides trade on comparable numbers and
	# the hero's point is what ends the fight rather than the fixture's.
	var pool := _hero_pools_at(opponent, _resynced_health(hero).maximum)
	pool.change(pool.maximum - pool.current)
	return opponent


## `actor`'s health pool, RE-SIZED through the `MAX_HEALTH` stat and returned.
##
## ## Why the stat and not the pool
##
## `ActorPools.sync_core` (`actor_pools.gd:91`) writes
## `pool.set_maximum(stats.derived(Stat.MAX_HEALTH))` whenever the derived stats are read, so
## a fixture that assigns `pool.maximum` has its figure overwritten before the first blow —
## which is how this suite's first loss case reported a `hero_won` from a hero it had set to
## one health. A FLAT `StatModifier` on `MAX_HEALTH` is the idiom `test_core_resources.gd:29`
## already uses, and it survives because the pool is then resized FROM the stat.
##
## `set_maximum` CLAMPS `current` into the new range, so the pool is re-filled after the sync
## and the caller is handed the live pool rather than a stale reference.
func _hero_pools_at(actor: Actor, maximum: float) -> ResourcePool:
	var before := actor.resource(&"health") as ResourcePool
	var current := 0.0 if before == null else before.maximum
	actor.stats.add_modifier(
		StatModifier.new(Stat.MAX_HEALTH, Stat.Op.FLAT, -current + maximum, &"walk_out_fixture")
	)
	return _resynced_health(actor)


## `actor`'s health pool, read AFTER the stat change has been pushed into it. A one-line
## forward so the two fixtures above do not each re-derive when a derived read is what
## triggers the sync — the one question this file has to ask about `sync_core`.
func _resynced_health(actor: Actor) -> ResourcePool:
	# Reading the derived stat is what makes `ActorPools` push the new capacity into the
	# pool; the read is the mechanism, which is why it is here rather than inline.
	actor.stats.derived(Stat.MAX_HEALTH)
	return actor.resource(&"health") as ResourcePool


## A loop holding `hero`, opened against `opponent`, which is exactly what
## `DomainFight.engage` builds for a placed body.
func _loop(hero: Actor, opponent: Actor) -> FightLoop:
	var loop := FightLoop.new(hero, opponent)
	loop.begin_fight(opponent)
	return loop


## Press until a verdict is decided, and stop. The counter moves on every pass against
## [constant MAX_PRESSES], so this terminates by construction.
##
## ## Why the deciding presses are seed ZERO and not [constant SEED]
##
## `SEED` is 7, and at this realm two stock builds contest at `p_hit = 0.5` exactly
## (`(accuracy - evasion) / rate_scale`): the draws `(7, attacker.id)` produces land on the
## MISS side for BOTH fixtures' ids. `_strike` also rebuilds its generator from the same
## seed on every press, so all 80 presses threw the identical miss, `outcome()` stayed empty
## and no verdict was ever reached — that is the shape that left this suite red. Seed zero is
## the spine's documented "nothing random happens and every attack lands" path
## (`CombatBand.roll` takes no draw for a certain hit), which is what a case that presses
## until a verdict means to ask for. `SEED` keeps its job in the case that needs a MISS.
func _win(loop: FightLoop) -> int:
	var presses := 0
	while presses < MAX_PRESSES and String(loop.outcome()) == "":
		loop.exchange(0)
		presses += 1
	return presses
