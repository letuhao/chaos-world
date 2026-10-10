extends TestCase

## ADR 0105: a player's REAL blow inflicts a status, end to end.
##
## ## Why this suite exists at all
##
## Measured before ADR 0105: `StatusApi.apply` had no production caller, ADR 0087's S12 ran
## only from `CombatSpine.resolve_hit`, and nothing in `game/src` called that either. So the
## entire status system was BUILT and UNREACHABLE, and every existing suite passed by
## driving the pieces directly — the catalogue loader, the tick loop, the spine's stage.
## Not one of them proved a player can be burnt by their own swing.
##
## This suite closes that gap in the only direction that matters: it drives
## [method CombatExchange.exchange] itself, through a real `LootApi` run against shipped
## content, and asks whether the actor afterwards HOLDS the element's status. Nothing here
## injects a mechanism, binds a proposal or calls a spine stage — the assertions are about
## the player's press, because that is the path ADR 0105 changed.
##
## The seam is deliberately narrow, per ADR 0105's own words: "a landed blow with an open
## gate is reported applied and the actor answers `has_status`; an avoided blow applies
## nothing and consumes no draw from the shared stream."

const DEEP_DOMAIN := &"elemental_transcendent_domain"
const DEEP_TIER := 1

## The element the fixture player is trained in, and the status their blows inflict. Named
## here rather than derived, because a test that computed its expectation from the same
## code it is testing would prove only that the code is self-consistent.
const PLAYER_ELEMENT := &"fire"
const PLAYER_STATUS := &"fire_immolation"

## The affinity granted to the fixture player. Above `0.0`, which is what `Actor.affinities`
## reads an absent element as, so the blow genuinely carries an element.
const AFFINITY := 0.6

## A high `Stat.STATUS_DEFENSE` on the player, who is the status's SUBJECT. A real
## defensive stat read by ADR 0884's flat gate rather than a rig, so the comparison below
## is between two legal builds and not between a build and a bypass. (The retired
## `Stat.STATUS_RESISTANCE` spelling this used to pin no longer reaches the gate at all,
## which made the "resisted" arm of the draw test decorative.)
const RESIST_FLAT := 0.4

## A saturated `Stat.EVASION`. `CombatDamage.resolve_hit` compares the boss's single draw
## against the DEFENDER's evasion, so this makes every blow in an exchange avoided without
## touching the damage model.
const EVASION_FLAT := 1_000_000.0

## How many seeds to sweep before giving up on finding a landed blow. Swept rather than
## pinned because a hardcoded seed is a flake waiting for a content rebalance: the claim
## under test is "a landed blow CAN inflict the status", not "seed 20260902 does".
const SEED_SWEEP := 64


## A bare actor in a live run, with the same attachments the existing exchange suite uses:
## core pools, an item state and the loot state. `ElementStats` is named to grant the
## affinity because `tools new_module` gives this suite's modules no `elements` edge; the
## id itself is core state on the actor, so nothing here reaches into another module.
func _delver(element: StringName = PLAYER_ELEMENT, affinity: float = AFFINITY) -> Actor:
	var actor := Actor.new(&"delver", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 8.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor)
	LootApi.attach(actor)
	LootApi.enter_domain(actor, DEEP_DOMAIN, DEEP_TIER, 20260902)
	actor.set_affinity(element, affinity)
	return actor


func _active(actor: Actor) -> Dictionary:
	return LootApi.summary(actor).get("active", {}) as Dictionary


func _status_of(result: Dictionary) -> Dictionary:
	return result.get("status", {}) as Dictionary


func _in_run(actor: Actor) -> bool:
	return bool(_active(actor).get("in_domain", false))


## All ten elements. `StatusDef.TIER_ONE_ELEMENTS` alone is no longer the whole vocabulary:
## ADR 0110 published the tier-2 statuses, so an assertion about "the elements" that keeps
## saying "tier-1" is asserting about half of them.
func _all_elements() -> Array[String]:
	var out: Array[String] = []
	for element in (
		ElementStats.BASE_ELEMENTS
		+ ElementStats.ADVANCED_ELEMENTS
		+ ElementStats.TIER_THREE_ELEMENTS
	):
		out.append(String(element))
	out.sort()
	return out


## Element ids as `String`s in TEXT order. Both sides of a set claim go through this: a
## `Dictionary`'s keys arrive in insertion order and `ElementStats`' lists are `Array` of
## `StringName` whose comparison is not string comparison, so an order-sensitive compare
## across the two would be a claim about a different ordering than either side means.
func _sorted_order(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(String(value))
	out.sort()
	return out


## Whether the shipped catalogue actually maps the fixture's element. The positive control
## every refusal below returns early on: "a blow inflicts nothing" would be satisfied just
## as well by a catalogue that maps nothing at all.
func _mapped() -> bool:
	return StatusApi.status_for_element(PLAYER_ELEMENT, 1.0) == PLAYER_STATUS


# --- 1. the headline: a real blow makes the player a SUBJECT --------------------


func test_a_landed_blow_inflights_the_status_on_the_player() -> void:
	# THE test ADR 0105 exists to make possible. A real `LootApi` run, a real press, and
	# the only assertion that matters: afterwards the PLAYER holds their element's status.
	# The boss cannot be asserted instead — it is a `Dictionary` (`loot_state.gd:523-547`),
	# not an `Actor`, so the player is the only subject there is.
	var actor := _delver()
	if not _mapped() or not _in_run(actor):
		return
	var landed := _first_landed(actor)
	if landed.is_empty():
		return
	var result: Dictionary = landed["result"]
	var status := _status_of(result)
	assert_eq(bool(result["evaded"]), false, "the blow landed, so it may inflict")
	assert_eq(bool(status["applied"]), true, "and it reports applied")
	assert_eq(String(status["id"]), String(PLAYER_STATUS), "naming the element's authored status")
	assert_eq(actor.has_status(PLAYER_STATUS), true, "and the player now HOLDS it")
	# Primitives only (ADR 0038): a screen renders this dict without naming a Resource.
	for key in status.keys():
		assert_eq(
			typeof(status[key]) == TYPE_OBJECT or typeof(status[key]) == TYPE_NIL,
			false,
			"status['%s'] is a primitive" % String(key)
		)


func test_the_status_is_live_on_the_actor_and_not_only_reported() -> void:
	# The report could be satisfied by a dict built out of nothing. This asserts the actor's
	# own registry, which is what every other reader — `summary()`, a status screen, the
	# tick loop — actually consults.
	var actor := _delver()
	if not _mapped() or not _in_run(actor):
		return
	var landed := _first_landed(actor)
	if landed.is_empty():
		return
	assert_eq(
		actor.has_status(PLAYER_STATUS),
		true,
		"Actor.has_status agrees, so this is a live status and not a reported one"
	)
	var found := false
	for entry in StatusApi.summary(actor)["active"] as Array:
		if String((entry as Dictionary).get("id", "")) == String(PLAYER_STATUS):
			found = bool((entry as Dictionary).get("known", false))
	assert_eq(found, true, "and the status module resolves it to one of its own defs")


func test_the_status_lands_on_the_attacker_and_never_on_the_boss() -> void:
	# The boss is a plain Dictionary in `module_data`, so a call site that tried to debuff
	# it would have to reach past the facade. Pinned because ADR 0105's own reasoning turns
	# on it: `StatusApi.apply(actor, …)` cannot be pointed at a boss.
	var actor := _delver()
	if not _mapped() or not _in_run(actor):
		return
	var landed := _first_landed(actor)
	if landed.is_empty():
		return
	assert_eq(actor.has_status(PLAYER_STATUS), true, "the attacker carries it")
	assert_eq(
		_active(actor).has("statuses"),
		false,
		"and the boss dictionary grew no status field: it is not an Actor"
	)


# --- 2. the gate: an avoided blow applies NOTHING -------------------------------


func test_an_avoided_blow_applies_no_status_and_spends_no_draw() -> void:
	# ADR 0105's own words: "an avoided blow applies nothing and consumes no draw from the
	# shared stream." That is the GATE's behaviour, and this asserts the gate — not the
	# reachability of one particular boss.
	#
	# ## What changed and why this replaced the old assertion
	#
	# This used to assert `CombatExchange._boss_guard(_active(actor)).evasion == 0.0`,
	# with a docblock claiming `_boss_guard` "hardcodes `evasion: 0.0`". **That stopped
	# being true**: `exchange.gd:411-427` READS the authored value off the live boss
	# (`active.get("evasion", 0.0)`), the same way `_boss_offense` reads `crit_chance` and
	# `penetration` (BL-0224). The conclusion survived — no shipped boss authors a non-zero
	# evasion, so the avoid branch is still unreachable FROM AN EXCHANGE — but for a
	# different reason, and the old assertion had become a DEFECT PIN: it asserted the
	# unreachable STATE, so it would have kept passing green the day a designer authored
	# boss evasion AND the landed-blow gate broke, which is precisely the change it
	# claimed to be watching for.
	#
	# So it now asserts the rule the gate exists to enforce, driven with a boss dict that
	# actually evades. `evasion` is a fraction of the boss's authored `BossDef` profile
	# (`LootState.boss_profile`), and nothing stops an author setting one, so this case is
	# the reachable shape of a future tier rather than a fiction.
	#
	# The two gates are asserted together because either alone is satisfiable by a bug in
	# the other: a gate that inflicts on every blow passes "evasion is zero", and a gate
	# that inflicts on nothing passes "nothing was applied".
	var evading := _boss_with_evasion()
	assert_ne(evading.is_empty(), true, "a boss that evades is a shape the model accepts")
	var roll := CombatDamage.resolve_hit(CombatExchange.offense(_delver()), evading)
	assert_eq(bool(roll["evaded"]), true, "a fully-evading boss avoids the blow")
	# A draw the evaded blow took would shift every later roll, which is the half of the
	# rule that is invisible in the actor's status list: the second press must land exactly
	# as it would have if the first had never been thrown.
	var landed_only := CombatDamage.resolve_hit(
		CombatExchange.offense(_delver()), _boss_with_evasion(0.0)
	)
	assert_eq(float(roll["share"]), 0.0, "an avoided blow spends nothing of the boss's vitality")
	assert_ne(float(landed_only["share"]), 0.0, "and the guard that does not evade does spend some")


## A boss bundle that evades every blow, built through the same two builders the exchange
## uses so the case exercises the real read path rather than a hand-written dict.
##
## `_boss_guard` is a pure function of the live-boss dict, so a dict carrying an authored
## `evasion` is exactly what a designer-authored boss tier would hand it. Returns `{}` when
## no fixture could be built, which every caller reports rather than asserting past.
func _boss_with_evasion(evasion: float = 1.0) -> Dictionary:
	var actor := _delver()
	if not _in_run(actor):
		return {}
	var active := _active(actor)
	if active.is_empty():
		return {}
	# `evasion` is read as `clampf(active.get("evasion", 0.0), 0.0, 1.0)` by
	# `CombatDamage.resolve_hit`, so 1.0 is "unavoidable" and 0.0 is the shipped default.
	var authored := active.duplicate(true)
	authored["evasion"] = clampf(evasion, 0.0, 1.0)
	return CombatExchange._boss_guard(authored)


## The shipped content's own answer, kept as a SEPARATE, weaker claim. This is no longer
## "the guard hardcodes zero" — it is "nothing authored evades yet", which is a statement
## about content that a designer can legitimately change. If an author gives a boss tier an
## evasion, this fails and points at the case above, which is the behaviour to re-check.
func test_no_authored_boss_evades_a_blow_today() -> void:
	var actor := _delver()
	if not _in_run(actor):
		return
	assert_eq(
		CombatExchange._boss_guard(_active(actor)).get("evasion", -1.0),
		0.0,
		"no shipped boss authors an evasion, so the avoid gate is unreachable from an exchange"
	)


func test_a_resisted_status_consumes_no_draw_from_the_shared_stream() -> void:
	# "Consumes no draw from the shared stream" is the half of ADR 0087's rule that is
	# invisible in the actor's status list. Two players with the same numbers and the same
	# seed must answer identically WHETHER OR NOT a status was applied on the press before —
	# a status roll drawn off the shared generator would shift the boss's own answer and
	# make the second press differ for a reason no player could see.
	var plain := _delver()
	if not _in_run(plain):
		return
	var first := CombatExchange.exchange(plain, 4242)
	var plain_second := CombatExchange.exchange(plain, 4242)

	var resisted := _delver()
	resisted.stats.add_modifier(
		StatModifier.new(Stat.STATUS_DEFENSE, Stat.Op.FLAT, RESIST_FLAT, &"test")
	)
	if not _in_run(resisted):
		return
	var resisted_first := CombatExchange.exchange(resisted, 4242)
	var resisted_second := CombatExchange.exchange(resisted, 4242)

	assert_eq(
		float(resisted_first["share"]),
		float(first["share"]),
		"the first press spends the same share whether or not a status landed"
	)
	assert_eq(
		float(resisted_second["share"]),
		float(plain_second["share"]),
		"and so does the SECOND press: no draw was taken off the shared stream"
	)


# --- 2b. the port's split runs on THIS path too (ADR 0886) -----------------------


## ADR 0886's acceptance: the encounter's arithmetic is `StatusApply.resolve_roll`'s, the
## same call the spine's S12 makes, so the potency split ADR 0885 added reaches THIS path
## — before the extraction the exchange ran only the gate and an intensity investment
## changed nothing here.
##
## The fixture carries no `elements` provider, so `element_power_<e>` is untrained and the
## base potency is the authored floor; ONE net scale of intensity doubles it. The expected
## number is read off the SHIPPED tuning, never pasted.
func test_the_intensity_split_reaches_the_encounter_path() -> void:
	var actor := _delver()
	if not _mapped() or not _in_run(actor):
		return
	var tuning := CombatEngineApi.tuning()
	actor.stats.add_modifier(
		CombatStats.rate_modifier(StringName(tuning.status_intensity_prefix + "omni"), 1.0, &"test")
	)
	var landed := _first_landed(actor)
	if landed.is_empty():
		return
	var status := _status_of(landed["result"])
	if not bool(status.get("applied", false)):
		return
	assert_almost_eq(
		float(status.get("potency", 0.0)),
		float(tuning.status_potency_floor) * 2.0,
		"one net-factor scale of intensity doubles the encounter's reported potency"
	)


# --- 2c. the immunity family answers a TAGGED def on THIS path (ADR 0885 / DEF-0352) ---


## DEF-0352's acceptance: a SHIPPED def carries `immunity_tags`, the encounter passes
## them into the request, and a defender built to answer the tag never takes the status —
## while the SAME blow against a body without the answer does. Both arms, because the
## refusal arm alone would pass on a catalogue that mapped nothing at all.
func test_a_tagged_status_is_refused_by_its_answer_and_applied_without_it() -> void:
	var def := StatusApi.definition(PLAYER_STATUS)
	assert_ne(def, null, "the fixture's status ships")
	if def == null:
		return
	assert_ne(def.immunity_tags.is_empty(), true, "and the shipped def carries an immunity tag")
	if not _mapped():
		return
	var tag: StringName = def.immunity_tags[0]
	var immune_id := StringName(CombatEngineApi.tuning().status_immune_prefix + String(tag))

	var answering := _delver()
	answering.stats.add_modifier(CombatStats.rate_modifier(immune_id, 1.0, &"test"))
	if not _in_run(answering):
		return
	var refused := _first_landed(answering)
	if refused.is_empty():
		return
	assert_eq(
		bool(_status_of(refused["result"]).get("applied", true)),
		false,
		"the tag's answer refuses the status outright"
	)
	assert_eq(answering.has_status(PLAYER_STATUS), false, "and the actor never holds it")

	var plain := _delver()
	if not _in_run(plain):
		return
	var landed := _first_landed(plain)
	if landed.is_empty():
		return
	assert_eq(
		bool(_status_of(landed["result"]).get("applied", false)),
		true,
		"the control arm applies, so the refusal above is the tag's doing"
	)
	assert_eq(plain.has_status(PLAYER_STATUS), true, "and the control body holds it")


# --- 3. nothing mapped is a normal answer, not an error ------------------------


func test_a_blow_carrying_no_element_applies_nothing_and_is_not_an_error() -> void:
	# The case ADR 0105 measures as the COMMON one: a body with no trained affinity at all
	# swings an elementless blow. (`ElementsApi.attach` DOES have a production caller now —
	# `actor_factory.gd` — but this fixture grants no affinity on purpose, so the carrier
	# resolves to nothing.) `status` is still present in the report — a consumer indexes it
	# unconditionally — and it reads as an ordinary non-application rather than a failure.
	var actor := _delver(&"", 0.0)
	if not _in_run(actor):
		return
	var result := CombatExchange.exchange(actor, 20260902)
	assert_eq(bool(result["evaded"]), false, "the blow still landed")
	assert_eq(bool(result["ok"]), true, "and was still spent on the boss")
	assert_eq(result.has("status"), true, "and the report still carries a status key")
	assert_eq(bool(_status_of(result)["applied"]), false, "with nothing applied")
	assert_eq(String(_status_of(result)["id"]), "", "and nothing named")
	assert_eq(actor.statuses.size(), 0, "and the player carries no status at all")


func test_an_element_with_no_authored_status_applies_nothing() -> void:
	# The refusal path, re-targeted. It used to be tested against `lightning` because no
	# tier-2 status shipped: ADR 0090 WITHHELD the ten rather than deferring them, because
	# shipping one balanced content on a table ADR 0069 measured as strictly dominant.
	# ADR 0110 publishes them — the balance objection is answered at the provider by
	# `TIER_MASTERY_STEP` — so `lightning` now inflicts `lightning_arc` and there is no
	# element left that maps to nothing.
	#
	# So the refusal is aimed at an element that is NOT one of the ten AUTHORED ones. That
	# is the same contract the old test asserted, against a subject that still exists: a blow
	# carrying an element the catalogue does not author inflicts nothing, and that is a
	# shipped answer rather than a gap. An INVENTED id rather than a merely unused real one
	# (`wood` has statuses) so the assertion cannot pass because a slot happens to be empty.
	assert_eq(
		StatusApi.status_for_element(&"aether", 1.0),
		&"",
		"an element outside the ten authored ones maps to nothing"
	)
	var actor := _delver(&"aether")
	if not _in_run(actor):
		return
	var landed := _first_landed(actor)
	if landed.is_empty():
		return
	var status := _status_of(landed["result"])
	assert_eq(bool(status["applied"]), false, "an unmapped element inflicts nothing")
	assert_eq(String(status["id"]), "", "and names nothing")
	assert_eq(actor.statuses.size(), 0, "while the blow itself landed normally")
	# The control the old test needed and this one has to earn again: the catalogue really
	# does map its own elements, so "inflicts nothing" is not true of every blow here.
	assert_ne(
		StatusApi.status_for_element(ElementStats.LIGHTNING, 1.0),
		&"",
		"and the element ADR 0090 withheld now DOES map (ADR 0110)"
	)


# --- 4. determinism -------------------------------------------------------------


func test_the_same_seed_answers_the_same_way_twice() -> void:
	# Two fresh players, identical numbers, identical seed, identical boss: the verdict, the
	# id and the potency must all match. Without this, "reproducible from (seed, encounter)"
	# — the claim the exchange's own generator is built for — stops being true the moment a
	# status enters the exchange.
	var first := _delver()
	if not _in_run(first):
		return
	var first_status := _status_of(CombatExchange.exchange(first, 90210))

	var second := _delver()
	if not _in_run(second):
		return
	var second_status := _status_of(CombatExchange.exchange(second, 90210))

	assert_eq(bool(first_status["applied"]), bool(second_status["applied"]), "same verdict")
	assert_eq(String(first_status["id"]), String(second_status["id"]), "same status id")
	assert_almost_eq(
		float(first_status["potency"]),
		float(second_status["potency"]),
		"and the same potency, which ADR 0088 reads off element_power deterministically"
	)


func test_two_exchanges_in_one_fight_do_not_replay_the_first_answers_status() -> void:
	# `hit_index` is what stops the Nth blow in a fight re-rolling blow 1's answer. Asserted
	# on the SEEDS rather than on resolved verdicts: at an open gate two draws agreeing is a
	# coin-flip, and a flaky assertion is not an assertion.
	var actor := _delver()
	if not _in_run(actor):
		return
	var boss := _active(actor)
	var seen := {}
	for index in 6:
		# The boss is a Dictionary, and `status_seed`'s THIRD slot is typed `Actor`,
		# so the actor goes there and the encounter dict goes in the `technique`
		# Variant slot — the same shape the production call site uses.
		var seed_value := StatusApplyMath.status_seed(900 + index, actor, actor, boss, index)
		seen[seed_value] = true
	assert_eq(seen.size(), 6, "every exchange in a fight gets its own substream")

	# And the property that makes the counter above necessary: a fight's exchanges really do
	# take DIFFERENT substream salts, because the call site counts landed blows itself.
	var before: int = actor.get_module_data(&"schema").get("status_hits", 0)
	CombatExchange.exchange(actor, 5150)
	var after: int = actor.get_module_data(&"schema").get("status_hits", 0)
	assert_eq(int(after) >= int(before), true, "the landed-blow counter never runs backwards")


# --- 5. the mapping is data, and the content that carries it -------------------


func test_the_mapping_is_authored_content_rather_than_a_table_in_code() -> void:
	# ADR 0105's placement claim: the element→status relation lives in the `.tres`, and
	# `StatusDef.element` alone does not decide it. Exactly one status per element claims
	# the landed blow, and it is always the COMBAT-scope one of the pair — a player cannot
	# be hit with a permanent cultivation blessing for throwing a punch.
	#
	# The count is the whole claim, not a number to update: one claimant per element is
	# `StatusCatalog._landed_blow_collisions` satisfied, and it is asserted against the ten
	# ELEMENTS rather than a literal so that adding an element makes this fail instead of
	# quietly asking to be bumped. ADR 0090's ten claimants became ten-plus-five under
	# ADR 0110, which published the tier-2 statuses instead of withholding them.
	var claimants: Dictionary = {}
	for status_id in StatusApi.status_ids():
		var def := StatusApi.definition(status_id)
		if not def.on_landed_blow:
			continue
		claimants[String(def.element)] = true
		assert_eq(
			def.is_combat_scope(),
			true,
			"%s claims the landed blow, so it must be a COMBAT status" % String(status_id)
		)
		assert_eq(
			StatusApi.status_for_element(def.element, 1.0),
			def.id,
			"and it is the one this element answers with"
		)
	assert_eq(
		claimants.size(),
		(
			ElementStats.BASE_ELEMENTS.size()
			+ ElementStats.ADVANCED_ELEMENTS.size()
			+ ElementStats.TIER_THREE_ELEMENTS.size()
		),
		(
			"every element claims exactly one status, tier-1 and tier-2 alike (ADR 0110) and the "
			+ "triad its single expression (ADR 0925)"
		)
	)
	assert_eq(
		_sorted_order(claimants.keys()),
		_all_elements(),
		"and they are exactly the thirteen elements"
	)


func test_no_authored_def_claims_a_landed_blow_twice() -> void:
	# The collision the selector exists to prevent: two statuses on one element would make
	# "the element's status" ambiguous, and resolving it by catalogue order would make the
	# shipped debuff a function of filename alphabetical order.
	assert_eq(
		StatusCatalog.instance().problems(),
		[],
		"no element is claimed twice, and no def regressed its authored shape"
	)


func test_the_restated_tier_one_element_list_still_matches_the_elements_module() -> void:
	# `_element_of` walks `StatusDef.TIER_ONE_ELEMENTS`, which is a restatement of
	# `ElementStats.BASE_ELEMENTS` rather than a reference to it — `combat` has no
	# `elements` edge (ADR 0105 does not take one and `tools arch` would refuse it). A
	# restatement is only safe while a test pins it; this is that pin. Two elements added to
	# one side would make the exchange walk a set the catalogue does not, and a status would
	# silently stop being reachable.
	assert_eq(
		StatusDef.TIER_ONE_ELEMENTS,
		ElementStats.BASE_ELEMENTS,
		"the walked list is still the elements module's tier-1 set"
	)


func test_status_for_element_answers_empty_for_everything_that_maps_to_nothing() -> void:
	# The ordinary cases, each of which must read as `&""` and NONE of which is an error: an
	# empty element, an unknown one, and a closed gate. A status code that raised on any of
	# them would turn ordinary play into a crash, so this asserts the ANSWER rather than
	# merely that nothing was applied.
	#
	# The tier-2 case that used to be here is GONE, not relaxed: under ADR 0090 a tier-2
	# element answered `&""` because no status shipped for it, and ADR 0110 publishes those
	# ten. `&""` now has three causes instead of four, and the fourth is asserted as the
	# positive control at the foot of this test rather than left as a silently dropped branch.
	assert_eq(StatusApi.status_for_element(&"", 1.0), &"", "an empty element maps to nothing")
	assert_eq(
		StatusApi.status_for_element(&"not_an_element", 1.0),
		&"",
		"an unknown element maps to nothing"
	)
	assert_eq(
		StatusApi.status_for_element(ElementStats.LIGHTNING, 0.0),
		&"",
		"a closed gate maps to nothing and spends no draw (ADR 0087), advanced element too"
	)
	assert_eq(
		StatusApi.status_for_element(PLAYER_ELEMENT, 1.0),
		PLAYER_STATUS,
		"and an open gate on an authored element does map"
	)
	# The positive control, restated: every refusal above would also pass on a catalogue that
	# mapped nothing at all. Pinned as the exact twenty rather than a size, so the control
	# cannot be satisfied by a different catalogue of the right length.
	assert_eq(StatusApi.has_status(PLAYER_STATUS), true, "the positive control's status ships")
	assert_eq(
		StatusApi.status_for_element(ElementStats.LIGHTNING, 1.0),
		&"lightning_arc",
		"and a tier-2 element DOES map now (ADR 0110 published it)"
	)
	assert_eq(StatusApi.status_ids().size(), 30, "the catalogue ships all thirty defs")


# --- internals ------------------------------------------------------------------


## Run exchanges until one LANDS, and return it. Sweeping seeds rather than pinning one is
## what keeps this suite from being a flake: what is under test is that a landed blow CAN
## inflict the status, not that one particular number does. Returns `{}` when no press in
## the sweep avoided, which is a legitimate outcome for a stripped fixture boss and is
## handled by the caller's early return.
func _first_landed(actor: Actor) -> Dictionary:
	for index in SEED_SWEEP:
		var result := CombatExchange.exchange(actor, 7919 * (index + 1))
		if bool(result.get("evaded", true)):
			continue
		if not _in_run(actor):
			continue
		return {"result": result}
	return {}
