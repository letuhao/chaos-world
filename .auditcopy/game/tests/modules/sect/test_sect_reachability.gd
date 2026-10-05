extends TestCase

## **Founding and teaching are REACHABLE from play, and the teaching ladder has a
## first rung.**
##
## An independent re-audit found two features that shipped, were tested, and could not
## be reached by a player:
##
##   - `SectApi.found` had NO production caller, and `ActorFactory.fund_sect_from_purse`
##     — the verb that exists to give an actor the founding funds — had ZERO callers, so
##     founding was doubly unwired: the verb was unreachable AND its price was
##     unpayable. BL-0174 prices an institution's existence on purpose, so an
##     unreachable price deleted the feature rather than debalancing it.
##   - `SectApi.teach` was the ONLY writer of `fit` and nothing called it, and it
##     refuses a teacher below the doctrine's `affinity_floor` while fit starts at 0 —
##     so the ladder had no rung a player could stand on. `teacher_unfit` was the only
##     reachable verdict of the only verb that can move fit.
##
## ## This suite is the REACHABILITY measurement, and it is deliberately not a unit test
##
## Every case below drives the SHIPPED path — `SectApi` and `ActorFactory` — and then
## proves the same verb is reachable from a screen a player opens. A case that only
## called `SectApi.found` would pass on the pre-fix tree: the verb worked, it was simply
## that nothing in `src/` ever called it. That is the whole defect, and a test that
## cannot tell "works" from "reachable" is what let it ship.

const SCREEN_SCRIPT := "res://src/ui/screens/sect_screen.gd"
const SCREEN_SCENE := "res://src/ui/screens/sect_screen.tscn"
const IRON_VINE := &"iron_vine"
const JADE_COURT := &"jade_court"
## The Iron Vine is the shipped sect whose teaching gate really refuses: its doctrine
## authors `affinity_floor = 35` (`game/data/sect/doctrines/iron_vine.tres:14`) and a
## fit-zero founder would read `teacher_unfit` on every single press.
const SHIPPED_DOCTRINE := &"iron_vine"

# --- Finding 1: founding is reachable, and its price is payable -----------------


## ## `found` is called by something a player triggers, from a screen
##
## The pre-fix tree failed this on both halves: `found` appeared nowhere in `src/`, and
## the only place its price could have been met — `fund_sect_from_purse` — was a verb
## with zero callers of its own. Both are asserted against the SHIPPED SOURCE, because a
## test that drove the verbs itself would have stayed green throughout.
func test_founding_is_called_by_a_screen_a_player_opens_and_its_price_is_payable() -> void:
	var source := FileAccess.get_file_as_string(SCREEN_SCRIPT)
	assert_ne(source.is_empty(), true, "%s is readable" % SCREEN_SCRIPT)
	assert_eq(source.contains("SectApi.found("), true, "the screen calls the founding verb by name")
	# And the price is reachable from the same place, so "a hero who can afford a sect
	# must be able to found one" is a whole claim rather than half of one.
	assert_eq(source.contains("act_fund("), true, "the screen offers the funding beat beside it")


## The bridge the screen funds through is the composition root's own verb, not a second
## implementation: `ui/` may not name `app/` at all, so the conversion has to be handed
## over as a `Callable`, and the one it is handed is `fund_sect_from_purse`.
##
## Asserted by BEHAVIOUR (the callable moves real coins into the real pool) rather than
## by source, because a bridge that points somewhere else and happens to be named
## correctly would pass a source check.
func test_the_funding_bridge_is_the_composition_roots_conversion_and_it_actually_pays() -> void:
	var bridge := ActorFactory.sect_funding_bridge()
	assert_eq(bridge.is_valid(), true, "the bridge is a callable")
	var funded := _funded_hero(1200)
	var purse_before := EconomyApi.purse(funded)
	assert_ne(purse_before, 0, "the hero really holds numeraire to convert")
	var funds_before := SectFounding.funds(funded)
	var verdict: Dictionary = _fund(funded, 900)
	assert_eq(bool(verdict["ok"]), true, "the conversion ran")
	assert_eq(int(verdict["moved"]), 900, "and moved exactly what was asked for")
	assert_eq(
		SectFounding.funds(funded),
		funds_before + 900.0,
		"the founding fund grew by the authored price"
	)
	assert_eq(
		EconomyApi.purse(funded), purse_before - 900, "and the purse paid for every point of it"
	)


## ## The whole beat end to end, at the SHIPPED prices
##
## This is the acceptance case for finding 1: fund the authored price out of the
## player's own purse, then found. Both numbers are read off the shipped `.tres` rather
## than typed here, so a retune of `founding_cost` cannot make this case lie — and the
## assertion is that the author's own price is affordable, because an unaffordable price
## is the defect.
func test_a_hero_can_fund_the_authored_price_and_found_the_sect_thereby_making_it_reachable(
) -> void:
	var cost := int(
		(
			SectReadModel
			. sect_view(SectCatalog.instance().sect_definition(IRON_VINE))
			. get("founding_cost", {})
			. get("outstanding", 0)
		)
	)
	assert_ne(cost, 0, "the shipped Iron Vine really charges to exist (BL-0174)")
	var hero := _funded_hero(cost + 100)
	# Step one: the price, paid for out of the player's own money.
	assert_eq(bool(_fund(hero, cost)["ok"]), true, "the player can fund the authored price")
	assert_eq(SectFounding.funds(hero), float(cost), "and the fund holds exactly the price")
	# Step two: the founding itself, which the pre-fix tree refused for every actor.
	var verdict := SectApi.found(hero, IRON_VINE, SHIPPED_DOCTRINE, String(hero.id))
	assert_eq(bool(verdict["ok"]), true, "a funded hero may found the sect")
	assert_eq(
		String(hero.get_module_data(SectState.MODULE_KEY)["institution"]),
		"iron_vine",
		"and is sworn to the house they made"
	)
	assert_eq(SectFounding.funds(hero), 0.0, "with the price consumed rather than merely met")


## A hero who has NOT funded the price is refused by name, with both numbers published,
## and pays nothing — the refusal contract founding already had, kept intact by the
## wiring (the wiring changed who can reach the verb, not what an unreachable price
## costs).
func test_a_hero_who_has_not_funded_the_price_is_refused_and_writes_nothing() -> void:
	var hero := _funded_hero(0)
	var before := SectApi.state(hero)
	var verdict := SectApi.found(hero, IRON_VINE, SHIPPED_DOCTRINE, String(hero.id))
	assert_eq(bool(verdict["ok"]), false, "an unfunded hero cannot found")
	assert_eq(
		String(verdict["reason"]),
		SectApi.FOUNDING_COST_UNMET,
		"and it names the authored rule rather than a screen-composed one"
	)
	assert_eq(int(verdict["required"]), int(verdict["actual"]), "reporting the shortfall")
	assert_eq(SectApi.state(hero), before, "and the ledger is byte-for-byte as found")


# --- Finding 2: the teaching ladder has a first rung ---------------------------


## ## A founder holds the FIRST RUNG, so the ladder is standable
##
## This is the case the audit's correction turned on: the defect is not that the gate
## refuses its own teacher, it is that NO shipped verb wrote `fit` at all, so fixing the
## refusal would change nothing. The fix is a grant at founding — and the measurement
## here is that a FRESH founder, with fit seeded at zero by `SectState.normalize`, is
## above the shipped doctrine's floor and can therefore teach somebody.
func test_a_fresh_founder_holds_the_first_rung_of_their_own_schools_doctrine() -> void:
	var hero := _founding_hero(1000)
	SectApi.found(hero, IRON_VINE, SHIPPED_DOCTRINE, String(hero.id))
	var fit := SectState.fit(SectApi.state(hero), SHIPPED_DOCTRINE)
	var floor: int = SectDoctrineCatalog.instance().doctrine(SHIPPED_DOCTRINE).floor_fit()
	assert_ne(floor, 0, "the shipped doctrine authors a real teaching floor")
	assert_ne(fit, 0, "so a fit of zero was the unreachable state the audit found")
	assert_eq(fit >= floor, true, "and a founder stands ABOVE it without any lesson")
	# The grant is capped at the floor: a founder may teach their own school and is not
	# handed a head start above the bar the content authored. This is the property that
	# keeps it a first rung rather than a weakening of the gate (ADR 0084).
	assert_eq(fit <= floor, true, "and never above the floor the content authored")


## ## And the rung is load-bearing: a JOINED member still has none
##
## Without this the grant would not be a first rung at all but a blanket lowering of the
## bar — every member of the house would be a teacher, which is exactly "weaken a gate to
## make this pass". `join` writes no fit, so an ordinary member reads zero, and the
## doctrine's own floor is what stops them teaching anybody.
##
## ## The JOINER is the TEACHER, and the FOUNDER is the pupil
##
## "An ordinary joiner holds no rung" is only a measurement if the joiner is the one
## refused. As first written this case had the founder teaching the joiner, which cannot
## produce `teacher_unfit` at all: the founder holds the granted 35 (see the case above),
## so the gate has no reason to refuse the teacher and the only refusal on offer was the
## STUDENT's — and once the pupil door is cleared, as it must be for this to measure
## anything, the verb simply succeeds. The assertion was named for the joiner's rung and
## measured the founder's.
##
## So the roles are as the name says: the joiner tries to teach the founder. The founder
## is already past the sect's door, because their grant is 35 and `min_purity` is 30
## (`iron_vine.tres:76`), so the pupil's door is open and the joiner's own fit of **zero**
## is the only thing left that can refuse. That is what makes it an anti-weakening
## measurement: with an admissible pupil, the sole reason for a refusal is the rung that
## was never granted.
func test_an_ordinary_joiner_holds_no_rung_and_is_still_refused_by_name() -> void:
	var founder := _founding_hero(1000)
	SectApi.found(founder, IRON_VINE, SHIPPED_DOCTRINE, String(founder.id))
	var joiner := _sworn_hero(&"joiner")
	assert_eq(
		SectState.fit(SectApi.state(joiner), SHIPPED_DOCTRINE),
		0,
		"a member who joined holds no fit at all"
	)
	assert_eq(
		(
			SectState.fit(SectApi.state(founder), SHIPPED_DOCTRINE)
			>= SectCatalog.instance().sect_definition(IRON_VINE).min_purity
		),
		true,
		"while the founder's own grant leaves them past the sect's door as a pupil"
	)
	var verdict := SectApi.teach(joiner, founder, SHIPPED_DOCTRINE)
	assert_eq(bool(verdict["ok"]), false, "and is refused")
	assert_eq(
		String(verdict["reason"]),
		SectApi.TEACHER_UNFIT,
		"by the doctrine's own floor — the gate still refuses an unfit teacher"
	)


## ## A real lesson lands, end to end, at the shipped authored numbers
##
## The refusal above is `teacher_unfit` about the TEACHER; this is the other half — that
## the same verb, once the teacher is on the rung, moves the STUDENT's fit by the
## authored rate and spends the teacher's stamina. Without this the first-rung grant
## would have been a number nothing could spend.
func test_a_lesson_from_a_founder_moves_the_pupils_fit_and_costs_the_teacher() -> void:
	var founder := _founding_hero(1000)
	SectApi.found(founder, IRON_VINE, SHIPPED_DOCTRINE, String(founder.id))
	var pupil := _sworn_hero(&"pupil")
	# Past the sect's own door, so the lesson reaches the band rather than stopping at the
	# gate in front of it — the same honest seeding the teaching suite does, and the same
	# one `_past_the_door` gives the joiner case above.
	_past_the_door(pupil)
	var before := SectState.fit(SectApi.state(pupil), SHIPPED_DOCTRINE)
	var stamina := founder.resource(&"stamina").current
	var tax := SectTeaching.tax_for(
		SectDoctrineCatalog.instance().doctrine(SHIPPED_DOCTRINE),
		SectCatalog.instance().sect_definition(IRON_VINE).position(&"iron_root")
	)
	var verdict := SectApi.teach(founder, pupil, SHIPPED_DOCTRINE)
	assert_eq(bool(verdict["ok"]), true, "a founder on the rung teaches")
	assert_ne(before, 0, "the pupil's pre-existing fit is a real starting point")
	assert_eq(
		SectState.fit(SectApi.state(pupil), SHIPPED_DOCTRINE),
		before + SectDoctrineCatalog.instance().doctrine(SHIPPED_DOCTRINE).fit_per_period,
		"and the lesson moved it by the doctrine's authored rate"
	)
	assert_eq(int(verdict["standing_delta"]), 0, "with no standing moved on either side")
	assert_eq(
		founder.resource(&"stamina").current,
		stamina - tax,
		"and the teacher paid the office's tax plus the doctrine's"
	)


## ## The first rung is the school's OWN doctrine and nothing else
##
## A grant keyed to the sect would have handed the founder fit with every rival school,
## which is a currency: fit is transmission and projects no stat (ADR 0084). The Jade
## Court is the shipped rival and the case reads its floor rather than typing it.
func test_the_founding_grant_is_scoped_to_the_schools_own_doctrine() -> void:
	var hero := _founding_hero(1000)
	SectApi.found(hero, IRON_VINE, SHIPPED_DOCTRINE, String(hero.id))
	var rival: StringName = SectCatalog.instance().sect_definition(JADE_COURT).doctrine_id
	assert_ne(String(rival), String(SHIPPED_DOCTRINE), "the two shipped schools differ")
	assert_eq(
		SectState.fit(SectApi.state(hero), rival),
		0,
		"founding the Vine gives no fit with the Jade Court's doctrine"
	)


## ## The refusal logic was NOT touched: it still refuses an unfit teacher
##
## The audit's correction is explicit that this is not "the ladder refuses its own
## teacher", and the fix had to be a rung rather than a loosened gate. So the gate is
## re-asserted on a member who was NOT granted anything, at the shipped floor minus one.
func test_the_gate_still_refuses_a_teacher_one_point_below_its_floor() -> void:
	var founder := _founding_hero(1000)
	SectApi.found(founder, IRON_VINE, SHIPPED_DOCTRINE, String(_hero_id(founder)))
	# Move the founder DOWN below the floor by hand, which is what a save, a rival house,
	# or a hand-edited ledger can do — and what makes the refusal a property of the gate
	# rather than of how this hero happened to be built.
	var ledger := SectApi.state(founder)
	(ledger["fit"] as Dictionary)[String(SHIPPED_DOCTRINE)] = (
		SectDoctrineCatalog.instance().doctrine(SHIPPED_DOCTRINE).floor_fit() - 1
	)
	founder.set_module_data(SectState.MODULE_KEY, ledger)
	SectApi.attach(founder)
	var pupil := _sworn_hero(&"pupil")
	var verdict := SectApi.teach(founder, pupil, SHIPPED_DOCTRINE)
	assert_eq(bool(verdict["ok"]), false, "one point under the floor is still refused")
	assert_eq(
		String(verdict["reason"]),
		SectApi.TEACHER_UNFIT,
		"and the gate — not the grant — is what refused"
	)


# --- Plumbing ----------------------------------------------------------------


## The bridge this suite funds through. One definition so no case and no comment
## disagrees about which conversion is under test. Named `_purse_bridge` rather than
## `bridge` because `TestCase` already publishes a member by that name, and shadowing a
## framework member from a test is how a case ends up asserting against the wrong thing.
func _purse_bridge() -> Callable:
	return ActorFactory.sect_funding_bridge()


## The founding fund bridge is a `Callable(actor, coins)`. A free function rather than
## `Callable(...)` at each call site so the two-argument contract is declared once.
func _fund(actor: Actor, coins: int) -> Dictionary:
	return _purse_bridge().call(actor, coins) as Dictionary


func _hero_id(actor: Actor) -> StringName:
	return actor.id


## ## Put a SWORN member exactly one point past the sect's own door, and nothing further
##
## `teach` asks the teacher's fit and then the student's `min_purity` (`api.gd:602-605`),
## so a pupil at fit 0 is refused at the student's door before the teacher's own gate is
## ever reached — which makes `min_purity + 1` the smallest state in which a refusal can be
## attributed to the teacher instead.
##
## Written through `set_module_data` + `attach` rather than through a verb because there IS
## no verb for it, and inventing one inside a test would assert a grant the player does not
## have. This is fixture seeding, exactly as `SectState.normalize` seeding fit to zero is:
## it states where the pupil starts, and every assertion after it is about what `teach`
## does with that starting point.
func _past_the_door(actor: Actor) -> void:
	var ledger := SectApi.state(actor)
	(ledger["fit"] as Dictionary)[String(SHIPPED_DOCTRINE)] = (
		SectCatalog.instance().sect_definition(IRON_VINE).min_purity + 1
	)
	actor.set_module_data(SectState.MODULE_KEY, ledger)
	SectApi.attach(actor)


## ## A hero who can ACTUALLY found a house, because the pool is paid before the verb
##
## `_funded_hero` fills the PURSE, and the two are different money. `_attach_founding_fund`
## mounts `sect_founding_funds` at **zero** on purpose (`actor_factory.gd:94-99`): a
## non-zero mount would hand BL-0174's authored price to every hero in the game, which is
## exactly the free founding it rules out. So `found` compares that pool against
## `founding_cost.outstanding` — 900 for the Iron Vine (`iron_vine.tres:78`) — and refuses
## `founding_cost_unmet` with nothing written.
##
## This helper is the step every founding case below was missing. Without it the founder is
## never sworn, `SectState.institution` reads empty, and every assertion about the founder
## measures a hero that was never founded: `teach` then refused `unknown_sect` (the
## teacher's ledger named no house at all) rather than `teacher_unfit`, and `fit` read the
## zero `SectState.normalize` seeds.
##
## It pays from the PURSE through the composition root's own bridge, so a case that uses it
## is still driving the shipped conversion rather than writing the pool by hand — which
## would have measured a grant the player cannot make.
func _founding_hero(coins: int) -> Actor:
	var hero := _funded_hero(coins)
	_fund(hero, coins)
	return hero


## A hero holding numéraire. Built through `ActorFactory` and then GIVEN coins, because
## a drive or a test cannot spend hours earning them and the case under test is the
## conversion, not the earning.
func _funded_hero(coins: int) -> Actor:
	var actor := ActorFactory.build(&"founder", {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 30.0})
	EconomyBoot.install(actor)
	_grant_coins(actor, coins)
	return actor


## A hero sworn to the Iron Vine with the core pools a lesson spends. `attach_core_
## resources` gives health and stamina, and the stamina is what teaching draws on, so a
## hero without it would be refused `nothing_to_teach` for a reason unrelated to the
## case.
func _sworn_hero(actor_id: StringName) -> Actor:
	var actor := ActorFactory.build(actor_id, {Stat.PHYSIQUE: 10.0, Stat.COMPREHENSION: 30.0})
	SectApi.attach(actor)
	SectApi.join(actor, IRON_VINE)
	return actor


## Put `count` of the economy's numéraire in `actor`'s inventory, through the item
## catalog rather than a bare `ItemDef` — the precedent `ui_driver._run_grant` sets,
## and the reason a grant here is indistinguishable from a real drop.
func _grant_coins(actor: Actor, count: int) -> void:
	if count <= 0:
		return
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		ItemsApi.attach(actor, 64)
		inventory = ItemsApi.inventory(actor)
	var def := Crafting.resolve(EconomyValuation.numeraire_id())
	assert_ne(def, null, "the economy's numeraire is an item this build ships")
	if def == null:
		return
	inventory.add(def, count)
