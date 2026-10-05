extends TestCase

## ADR 0258 §5: "Reaching the lifespan ends the body."
##
## ## What this suite is FOR, given `soul_death_loop.gd` already drives the loop
##
## The other suite proves the wound path end to end. This one drives the OTHER cause and pins
## the decisions that are not derivable from reading the code:
##
##   1. **A guardian beats age.** The two causes may not both apply, and this says which wins.
##   2. **A missing seam expires nobody.** `age_years` does not exist on `Actor` yet and the
##      parallel age agent owns `core/actor.gd`, so the first block of cases is about the
##      REFUSALS — and a refusal that read as "infinitely old" would kill every hero in the game
##      on the first frame. That is the hazard those assertions exist to catch, and they are
##      written so they go RED the moment the seam lands wired to the wrong zero.
##   3. **Out of bodies is named.** A run that ended is still a run that happened.
##
## ## Why the age cases set the field on a PLAIN actor rather than on a subclass
##
## ADR 0258 §2's field landed on `core/actor.gd` (`var age_years: float`, defaulting to
## `Actor.STARTING_AGE_YEARS`) while this file was being written, so the aged body is an ordinary
## `_hero` with the field assigned through `Object.set` — which is the same seam `SoulAge` reads
## it through, and which keeps this file PARSING whether or not that field is present.
##
## ## What "the field is missing" is tested with instead, and why not a subclass
##
## The absent-field refusal needs a body with no `age_years`, and a subclass cannot produce one
## now that `Actor` declares it (a diamond cannot remove an inherited member). `test_an_age_that_is_
## not_a_number_is_refused_by_name_and_expires_nobody` therefore drives the same guard through the
## other branch of `SoulAge.age_years` — a field present and unreadable — which is the refusal that
## survives on every tree. The production rule the absent-field case would have pinned is that
## `age_years < 0.0` is a REFUSAL rather than an age, and that rule is live in `SoulAge.age_years`
## and asserted through the non-numeric case.

## The full verdict key set, every branch of which must carry all of them.
const VERDICT_KEYS: Array[String] = [
	"ok",
	"reason",
	"cause",
	"died",
	"guardian",
	"damage",
	"soul",
	"arrival",
	"body_id",
	"incarnated",
	"fact",
	"fact_count",
	"marks",
	"ungranted_marks",
]

var _actor: Actor
var _soul_store: SoulWorldLedger
var _death: SoulDeath
var _clock: WorldClock
var _minted: Array = []
var _born: Array = []
var _aged: Array = []


func setup() -> void:
	_soul_store = SoulWorldLedger.new()
	SoulApi.set_store(_soul_store)
	_clock = WorldClock.new()
	SaveApi.install_store(WorldClock.WORLD_KEY, _clock)
	_minted.clear()
	_born.clear()
	_aged.clear()
	_actor = _hero(&"age_death_hero")
	_death = SoulDeath.new(_mint, _adopt)


## Every process-wide static this suite installs, released on the way out. `SaveApi._stores` is
## process-wide and the runner shares one process across every suite, so a clock left installed
## here is the next suite's world. Idempotent, and safe after an early return — which is why
## the bookkeeping arrays are emptied HERE rather than at each call site.
func teardown() -> void:
	for born in _born:
		(born as Actor).resources.clear()
	_born.clear()
	# NO `free()` ON AN AGED BODY, and the reason is the diamond rather than the age.
	# Everything a diamond does runs before `Actor._init`, so `NOTIFICATION_PREDELETE` never
	# fired on these instances and their own base is still `RefCounted` — and Godot REFUSES to
	# free a `RefCounted` outright. The `_born` bodies end their life through `resources.clear()`,
	# which fires the notification properly, and an aged body that reached it has nothing further
	# to hold, so releasing the arrays is the whole of the teardown (ADR 0076's `Shield` shape).
	_aged.clear()
	_minted.clear()
	_actor = null
	SoulApi.set_store(null)
	SaveApi._stores.erase(WorldClock.WORLD_KEY)


# --- The refusals: the half that matters whenever a seam is missing or mis-wired ----------


func test_an_age_that_is_not_a_number_is_refused_by_name_and_expires_nobody() -> void:
	# The refusal half of `SoulAge.age_years`, and the half that stays testable on every tree.
	# A body can carry an `age_years` that is not an age — a hand-edited save, a payload restored
	# from a build that wrote something else — and `0` or "infinitely old" would both be a claim
	# about a body nobody has said anything true of. A refusal is the only honest answer, and it
	# expires nobody.
	var broken := _hero(&"not_an_age")
	broken.set(SoulAge.AGE_FIELD, "a long time")
	assert_eq(SoulAge.age_years(broken) < 0.0, true, "a non-numeric age is a negative sentinel")
	var answer := SoulAge.answer_for(broken)
	assert_eq(bool(answer["expired"]), false, "so nobody has expired")
	assert_eq(bool(answer["ok"]), false, "and the read refuses rather than answering")
	assert_eq(String(answer["reason"]), SoulAge.REASON_NO_AGE_FIELD, "by name")
	assert_eq(_death.is_dead(broken), false, "and the poll predicate expires nobody either")


func test_a_missing_clock_is_refused_by_name_and_is_never_read_as_zero() -> void:
	# The other half of the same hazard, and the one the brief names explicitly. A clock that
	# is not wired has NOT said the world is new: answering `0` would make every body eternal
	# and answering "infinite" would kill them all. Both are refusals, and the refusal has to be
	# the same one.
	# `install_store(key, null)` REFUSES a null store and leaves the previous entry in place
	# (`save/api.gd:105`), so the clock has to come out of `_stores` the way ADR 0259's own suite
	# takes it out. That is not a test convenience: it is the only way a clock leaves this
	# process, and pretending otherwise would leave every LATER suite reading this suite's world.
	SaveApi._stores.erase(WorldClock.WORLD_KEY)
	assert_eq(SoulAge.world_periods(), -1, "an unwired clock is -1, never 0")
	var aged := _aged_hero(&"no_clock", 10_000.0)
	assert_eq(SoulAge.age_years(aged) >= 0.0, true, "this body DOES carry an age")
	var answer := SoulAge.answer_for(aged)
	assert_eq(bool(answer["ok"]), false, "so the read refuses")
	assert_eq(String(answer["reason"]), SoulAge.REASON_NO_CLOCK, "by name")
	assert_eq(bool(answer["expired"]), false, "and expires nobody")
	# The same refusal through the resolver's own predicate, which is what `poll_death` asks.
	assert_eq(_death.is_dead(aged), false, "and the poll predicate agrees")


func test_a_store_that_is_not_a_clock_is_refused_rather_than_assumed_to_be_the_world() -> void:
	# A store installed under `world_time` that cannot report a count. `install_store` accepts
	# anything with `read_ledger`, so a wrong wiring is installable and only the READ catches it.
	SaveApi.install_store(WorldClock.WORLD_KEY, CountlessStore.new())
	assert_eq(SoulAge.world_periods() < 0, true, "an object with no count reads as absent")
	assert_eq(SoulAge.has_expired(_hero(&"broken_clock")), false, "and nobody expires")
	assert_eq(
		String(SoulAge.answer_for(_aged_hero(&"broken_clock_body", 10_000.0))["reason"]),
		SoulAge.REASON_NO_CLOCK,
		"an aged body is refused by name rather than believed either way"
	)


func test_a_body_with_no_body_plan_reads_a_zero_lifespan_and_expires_nobody() -> void:
	# `RealmLifespan` answers `0.0` for an actor with no `race_def` component, and comparing an
	# age against zero would expire every unplanned actor in the game. The zero is refused.
	var planned := _aged_hero(&"planned", 10_000.0)
	assert_eq(SoulAge.lifespan_days(planned) > 0.0, true, "a planned body has a lifespan")
	var bare := ActorFactory.build(&"bare")
	bare.age_years = 10_000.0
	_born.append(bare)
	var answer := SoulAge.answer_for(bare)
	assert_eq(String(answer["reason"]), SoulAge.REASON_NO_LIFESPAN, "an unplanned body is named")
	assert_eq(bool(answer["expired"]), false, "and never expires on a zero lifespan")


func test_a_body_whose_lifespan_it_has_not_reached_is_not_dead_on_account_of_age() -> void:
	# The negative of the whole feature, and the case a coarse `is_dead` would get wrong. A body
	# is dead on account of AGE only once `age_days >= lifespan_days`; at the authored starting
	# age against a stoneborn lifespan it is young, and the answer has to be false.
	var young := _aged_hero(&"young_hero", 0.0)
	var answer := SoulAge.answer_for(young)
	assert_eq(bool(answer["ok"]), true, "age field, body plan and clock: the read is answerable")
	assert_eq(bool(answer["expired"]), false, "and a newborn has not reached its lifespan")
	assert_eq(_death.is_dead(young), false, "so the poll predicate says the body stands")


func test_the_calendar_is_derived_from_the_ladder_and_never_typed_in_a_second_time() -> void:
	# `TimeLadder` measures every ratio from the BASE, so days-per-year is `year / day`. Pinned
	# to what the shipped `.tres` authors rather than to a literal in this file, so a retune of
	# either row moves the answer and this assertion follows it.
	assert_eq(TimeLadder.ratio_for(&"year"), 4380, "the ladder authors a year")
	assert_eq(TimeLadder.ratio_for(&"day"), 12, "and a day")
	assert_eq(SoulAge.days_per_year(), 365, "so a year is 365 of them, derived")


# --- The age cause itself -----------------------------------------------------------------


func test_a_body_that_reached_its_lifespan_is_dead_and_the_cause_is_named() -> void:
	var aged := _aged_hero(&"the_lived_out", 10_000.0)
	assert_eq(bool(SoulAge.answer_for(aged)["expired"]), true, "the lifespan has been reached")
	assert_eq(_death.is_dead(aged), true, "so an aged body at FULL HEALTH reads dead")
	# Not derived from `reason`, and present on every branch — ADR 0190's rule.
	var outcome := _death.resolve(aged)
	assert_eq(String(outcome["cause"]), SoulAge.CAUSE_AGE, "the cause is named, not inferred")
	assert_eq(bool(outcome["died"]), true, "the body ended")
	assert_ne(String(outcome["reason"]), "", "and the verdict names what happened")


func test_a_wound_death_still_reports_the_wound_cause() -> void:
	# The other half of the cause vocabulary: the age key did not swallow the case that shipped
	# before it, and `cause` is `death` rather than age for a body that was killed.
	var outcome := _death.resolve(_kill(_hero(&"a_wound_hero")))
	assert_eq(String(outcome["cause"]), SoulAge.CAUSE_DEATH, "a wound is a wound")
	assert_eq(bool(outcome["died"]), true, "and the body still ends")


func test_every_branch_publishes_every_key_and_none_of_them_makes_one_conditional() -> void:
	# ADR 0190's rule as CODE: a consumer reading a verdict must never have to ask which branch
	# produced it. Every branch below is reachable through the shipped code, and each carries the
	# WHOLE key set — not just `cause`, which is why the expected list is a constant.
	assert_eq(VERDICT_KEYS.size(), 14, "the key set is the size this suite says it is")
	assert_eq(_missing_from(_verdict(SoulDeath.new().resolve(null))), [], "the refusal")
	assert_eq(_missing_from(_verdict(_guardian_verdict())), [], "a guardian death")
	assert_eq(_missing_from(_verdict(_wound_verdict())), [], "a wound death")
	assert_eq(_missing_from(_verdict(_age_verdict())), [], "an age death")
	assert_eq(_missing_from(_verdict(_out_of_bodies_verdict())), [], "and the last life")


# --- The decisions this suite exists to pin ------------------------------------------------


func test_a_guardian_beats_the_lifespan_because_a_guardian_is_one_more_body() -> void:
	# THE precedence claim, and the argument it rests on: a guardian is an ordinary consumable
	# that stands in for a body the player would otherwise have lost, and nothing in ADR 0130
	# narrows that to wounds. So the item buys one more body, whatever ended the last one, and
	# the verdict says so rather than letting both causes apply.
	var aged := _aged_hero(&"the_saved_elder", 10_000.0)
	_give_guardian(aged)
	var lives := int(SoulApi.soul(aged)["lives"])
	var integrity := int(SoulApi.soul(aged)["integrity"])
	var outcome := _death.resolve(aged)
	assert_eq(String(outcome["reason"]), "guardian_spent", "the guardian was spent first")
	assert_eq(bool(outcome["died"]), false, "so the lifespan ended nothing")
	assert_eq(String(outcome["cause"]), SoulAge.CAUSE_DEATH, "and the age cause did not apply")
	assert_eq(int(outcome["damage"]), 0, "the soul paid nothing")
	assert_eq(int(SoulApi.soul(aged)["integrity"]), integrity, "integrity is untouched")
	assert_eq(int(SoulApi.soul(aged)["lives"]), lives, "and no life was spent")
	assert_eq(bool(outcome["incarnated"]), false, "no new body")
	assert_eq(String(outcome["fact"]), "", "no arrival was earned, so no mark either")


func test_an_age_death_is_the_authored_cost_and_not_a_free_expiry() -> void:
	# `damage` has ONE meaning on this verdict — integrity the soul lost — so a second reading
	# here would make the key branch-dependent, which is the hole ADR 0190's rule closes. It
	# also prints through the panel's own "Cost %d integrity" template, so a zero would be a lie
	# the UI told on the panel's behalf.
	var aged := _aged_hero(&"the_toll", 10_000.0)
	var integrity := int(SoulApi.soul(aged)["integrity"])
	var outcome := _death.resolve(aged)
	assert_eq(int(outcome["damage"]), int(SoulDeath.BASE_DEATH_COST), "the authored cost, unscaled")
	assert_eq(
		int(SoulApi.soul(aged)["integrity"]),
		integrity - int(outcome["damage"]),
		"and the soul paid exactly what the verdict reported"
	)
	assert_eq(
		int(SoulApi.soul(aged)["damage_count"]) > 0,
		true,
		"and the soul's own trail records that the death happened"
	)


func test_an_age_death_shares_the_one_fact_id_rather_than_inventing_a_second() -> void:
	# ADR 0130's count is "how many bodies has this soul ended", and a body that reached the
	# end of its authored life ended. A second code-owned id would make every quest asking the
	# counting question read TWO ids, put a row in the ledger with nothing demanding it
	# (ADR 0137), and leave `fact_count` unable to say which cause ended a body — which is why
	# `cause` is on the verdict instead.
	var aged := _aged_hero(&"the_counted", 10_000.0)
	var outcome := _death.resolve(aged)
	assert_eq(String(outcome["fact"]), String(SoulDeath.FACT_ID), "the same code-owned id")
	assert_eq(int(outcome["fact_count"]), 1, "and it accrues one death")
	assert_eq(WorldFact.count(aged, SoulDeath.FACT_ID), 1, "the ledger itself carries the count")


func test_a_soul_out_of_bodies_is_named_when_age_ends_it_rather_than_stopping_silently() -> void:
	# ADR 0258 §5's own sentence: "A soul that has run out of bodies is the one case where
	# age-death cannot re-body, and it is reported by name rather than as a silent end." The age
	# check sits ABOVE the gate precisely so the verdict names the CAUSE as well as the refusal —
	# an age death reporting a bare `soul_spent` would be a run that ended for a reason no caller
	# could read.
	var aged := _aged_hero(&"the_last_of_the_lived", 10_000.0)
	# Each death RE-CARRIES the world fact onto whatever body now stands (`_carry_facts`), and
	# `_reincarnate` is handed a deliberately UNKNOWN body id so this helper's answer is a
	# `no_arrival` refusal and the body is never swapped. So `aged` holds every death of the run
	# rather than only its first — which is what makes this `before + 1` rather than `1`.
	for _i in range(SoulState.DEFAULT_LIVES):
		_die_away(aged)
	var before := WorldFact.count(aged, SoulDeath.FACT_ID)
	var outcome := _death.resolve(aged)
	assert_eq(String(outcome["reason"]), "soul_spent", "the refusal is named")
	assert_eq(String(outcome["cause"]), SoulAge.CAUSE_AGE, "and the CAUSE is named with it")
	assert_eq(bool(outcome["died"]), true, "on a death")
	assert_eq(bool(outcome["incarnated"]), false, "nothing re-embodied")
	assert_eq(String(outcome["body_id"]), "", "no body was handed back")
	assert_eq(WorldFact.count(aged, SoulDeath.FACT_ID), before + 1, "and the world heard about it")


func test_an_age_death_re_bodies_into_the_gate_s_answer_and_keeps_the_run() -> void:
	# The whole of ADR 0258's payoff: reaching the lifespan ends a BODY, not a run. The soul
	# persists, the incarnation advances, and the arrival is the gate's answer rather than the
	# answer of a second path.
	var aged := _aged_hero(&"the_re_bodied", 10_000.0)
	var incarnation := int(SoulApi.soul(aged)["incarnation"])
	var outcome := _death.resolve(aged)
	assert_eq(bool(outcome["incarnated"]), true, "the soul re-embodied")
	assert_eq(String(outcome["cause"]), SoulAge.CAUSE_AGE, "on the age cause")
	assert_ne(String(outcome["body_id"]), "", "into a real body")
	assert_ne(String(outcome["body_id"]), String(aged.id), "and a different one")
	assert_eq(int(SoulApi.soul(aged)["incarnation"]), incarnation + 1, "the incarnation advanced")
	assert_eq(String(outcome["arrival"]), String(SoulApi.soul(aged)["arrival"]), "gate's arrival")


# --- Internals ----------------------------------------------------------------------------


## One real verdict per branch, so the key-set case walks the shipped code and not a fixture.
func _guardian_verdict() -> Dictionary:
	var body := _hero(&"keys_guardian")
	_give_guardian(body)
	return _death.resolve(_kill(body))


func _wound_verdict() -> Dictionary:
	return _death.resolve(_kill(_hero(&"keys_wound")))


func _age_verdict() -> Dictionary:
	return _death.resolve(_kill(_aged_hero(&"keys_age", 10_000.0)))


func _out_of_bodies_verdict() -> Dictionary:
	var body := _hero(&"keys_spent")
	for _i in range(SoulState.DEFAULT_LIVES):
		_die_away(body)
	return _death.resolve(_kill(body))


## Every key of `verdict`, so two branches can be compared by value.
func _verdict(outcome: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in outcome.keys():
		keys.append(String(key))
	keys.sort()
	return keys


## Which of [constant VERDICT_KEYS] `keys` does not carry.
func _missing_from(keys: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for key in VERDICT_KEYS:
		if not keys.has(key):
			out.append(key)
	return out


## Resolve a death for `body` without adopting, so a loop of deaths does not walk the
## composition root's swap and leave this suite holding a chain of bodies.
##
## ## `no_rebind`, because a swap is a JUMP here
##
## `_mint_body` is left INVALID, so `_rebody` returns at its `no_body_mint` exit before the
## carry, before the marks window and before `reincarnate` — and the only thing it did to the
## soul was the damage. Each pass therefore costs exactly one life, which is what makes
## `range(SoulState.DEFAULT_LIVES)` the right number of passes and what lets the out-of-bodies
## case spend the whole ledger and stop on a `no_lives` gate rather than on a mint failure.
## The exit is also an honest one to pass through: it is the real branch a composition root with
## no builder installed takes.
func _die_away(body: Actor) -> Dictionary:
	var pool := body.resource(&"health")
	if pool != null:
		pool.change(-pool.maximum)
	return SoulDeath.new().resolve(body)


## Take the body to zero health, through the pool's own `change` so the signal fires.
func _kill(body: Actor) -> Actor:
	var pool := body.resource(&"health")
	if pool != null:
		pool.change(-pool.maximum)
	return body


## An actor with a body plan, core pools and both module mirrors attached.
func _hero(actor_id: StringName) -> Actor:
	var body := ActorFactory.build(actor_id)
	RaceApi.attach(body)
	RaceApi.set_race(body, &"stoneborn")
	DifficultyApi.attach(body)
	SoulApi.attach(body)
	_born.append(body)
	return body


## A hero carrying `age_years` — ADR 0258 §2's body field, owned by the age agent and declared
## on `core/actor.gd` as `var age_years: float`.
##
## Assigned DYNAMICALLY through `Object.set` rather than as `body.age_years = years`, for one
## reason: this file must PARSE on a tree where that field has not landed, and a member access
## to a member `Actor` does not declare is a parse error rather than a runtime one. The seam the
## game writes through is the same one, so the seam the tests write through is the same one.
func _aged_hero(actor_id: StringName, years: float) -> Actor:
	var body := _hero(actor_id)
	body.set(SoulAge.AGE_FIELD, years)
	_aged.append(body)
	return body


## The composition root's mint callback: a real body, tracked so teardown can release it.
func _mint(arrival_id: String, incarnation: int) -> Dictionary:
	var built := CharacterCreationFlow.build_forced(StringName(arrival_id), incarnation)
	if not bool(built.get("ok", false)):
		return {"ok": false, "reason": String(built.get("reason", ""))}
	_minted.append(built["actor"])
	return built


## The composition root's adopt callback: the new body becomes the one every read answers from.
func _adopt(body: Actor) -> void:
	if body != null:
		_actor = body


## Put the consumable guardian in `actor`'s bag, attaching an inventory only when there is none.
##
## **`ActorFactory.build` DOES NOT give an aged body a bag, and `_hero` does not attach one
## either**, so this is the only place a bag comes into existence. Without it the spend is
## refused with `not_carried` (`items/api.gd:211`), the guardian branch is never taken, and the
## precedence case fails with an empty `reason` — which is what it did before this note.
func _give_guardian(actor: Actor) -> void:
	if ItemsApi.inventory(actor) == null:
		ItemsApi.attach(actor)
	var bag := ItemsApi.inventory(actor)
	var def := Crafting.resolve(&"guardian_vigil_ash")
	if def != null and not bag.has(&"guardian_vigil_ash", 1):
		bag.add(def, 1)


## A store that answers `read_ledger` — all `install_store` checks for — but cannot report a
## period count, which is what a clock installed under the wrong key would be.
class CountlessStore:
	extends RefCounted

	func read_ledger() -> Dictionary:
		return {}
