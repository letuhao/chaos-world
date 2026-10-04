extends TestCase

## Spine stage S12's PRODUCER: `CombatBoot.ctx_builder_for` writes `StatusApply.REQUEST_KEY`.
##
## ## Why this file exists at all
##
## `status_apply.gd` stated the gap in its own docblock, and stated it twice: "it, because
## no shipped `ctx_builder` writes `REQUEST_KEY`" and "Every `set_data(REQUEST_KEY, …)` in
## the tree is under `game/tests/` (three sites), so the spine's S12 was UNWIRED rather than
## rarely-taken". Every readout answered `status withheld: no request`, and the whole status
## system — the authored catalogue (ADR 0090), the element→status mapping (ADR 0105), and
## potency from element power (ADR 0088) — was unreachable from play.
##
## ## ## Why THIS test is not the self-fulfilling one
##
## The three sites that wrote `REQUEST_KEY` were in `game/tests/`, and each wrote it with
## `ctx.set_data(StatusApply.REQUEST_KEY, _request(1.0))` — a hand-built dictionary naming a
## status the test itself chose. **Such a test proves only that `StatusApply.apply` reads a
## dictionary. It passes with no producer in the tree at all**, which is exactly what
## happened. `test_status_application.gd` still does that, and still does it correctly: it is
## the suite for the ARITHMETIC and must stage its own input to test it.
##
## Nothing below ever calls `set_data(REQUEST_KEY, …)`, `StatusApply.apply` or
## `StatusApply.record`. Every request asserted here was produced by
## `CombatBoot.ctx_builder_for` — the only shipped `ctx_builder` — resolving the AUTHORED
## catalogue through `StatusApi.status_for_element`, and every id asserted is one a `.tres`
## under `res://data/statuses/` claims with `on_landed_blow`.
##
## **Measured, not asserted:** disabling the producer (returning the mechanism builder
## unwrapped) fails the five PRODUCER rows below with the producer's own answers —
## `REQUEST_KEY rides ctx.data`: `<null>`, `the first carries the catalogue's earth status`:
## `expected earth_quake, got `, `the qi builder's context carries the request too`:
## `expected true, got false` — while the two NEGATIVE rows stay green, which is what makes
## them negatives rather than assertions that happen to hold. The two ROWS the stage owns
## (`applied`, and the blocked blow that files nothing) are among the failures; they fail
## here on the broken lane described below rather than on a refusal name, so they are not
## claimed as demonstrated negatives here.
##
## ## The path of a blow, end to end, with nothing in the middle stubbed
##
## `CombatBoot.install` → `CombatBoot.resolve_hit` → `CombatEngineApi.resolve_hit` →
## `CombatSpine.resolve_hit` (S1-S11, then S12) → `StatusApply.apply` → `Actor.add_status`.
## The actors are built by `ActorFactory` through the enrolment verbs production uses, the
## techniques are SHIPPED `.tres` files read by id through `TechniqueCatalog`, and the tuning
## and the wound ledger are the shipped ones. A fixture that supplies what production
## withholds hides the hole instead of closing it (`test_combat_boot.gd:17-23`).
##
## ## A KNOWN hazard on this lane: `ActorFactory` is a compile-time dependant
##
## `ActorFactory.build` mounts `ClanGate`'s providers, so a mid-edit `clan/api.gd` that
## fails to compile takes every `_pair()` with it and the row reports an engine error rather
## than its own message. That was observed once, from another lane's file, and the failure
## is unmistakable (`Nonexistent function 'attach' in base 'GDScript'`) — but a RED row here
## with that backtrace is not this suite's assertion failing.

## The element `body_tremor_cadence` is authored with, and the id `earth_quake.tres`
## claims for a landed blow carrying it. Both pinned as literals rather than derived from
## `StatusApi.status_for_element`, because a test that asks the production mapping what the
## production mapping should answer can only ever agree with it.
const EARTH := &"earth"
const EARTH_QUAKE := &"earth_quake"
const FIRE := &"fire"
const FIRE_IMMOLATION := &"fire_immolation"
## The status row's kind, as `StatusApply.EFFECT_KIND` spells it. Spelled here rather than
## named so this suite holds no `combat_engine` constant: it is asserting that PRODUCTION
## filed the row, and reading the id off the constant would make the assertion agree with
## whatever the constant is.
const EFFECT_KIND := &"status_application"
## The two shipped body techniques that are both authored `element = &"earth"`, so the
## element-vs-technique row below is about the MAPPING rather than about one file.
const EARTH_BODY := [&"body_tremor_cadence", &"body_iron_skin"]
## The base attributes `CharacterCreationFlow._body` allocates, handed to
## `ActorFactory.build` exactly as production does.
const HERO_BASE := {Stat.PHYSIQUE: 12.0, Stat.AGILITY: 8.0, Stat.WILL: 8.0}
## `spawn_inhabitant` mounts no offensive or defensive stats, so `CombatStats.BLOCK_RATE`
## reads its table default and nothing else. Multiplying it by this is enough to saturate
## `p_block` against a defender who contests `0.0`, and it is read from the table rather
## than restated so a retune to `combat_damage.tres` cannot silently stop blocking.
const BLOCK_SATURATION := 4.0

# --- the actors production builds -----------------------------------------------


## An attacker who can land a body blow, and a defender whose body is the thing being hit:
## `spawn_inhabitant` mounts the `health` pool, and the meridians are opened because
## `with_body_cultivation` alone does not open a channel — a freshly enrolled body is a
## sheet of twenty CLOSED meridians (`ui_driver.gd:_build_drills`,
## `tests/…/body_damage_fixture.gd:110`).
func _pair() -> Dictionary:
	var attacker := _hero()
	var defender := ActorFactory.spawn_inhabitant(&"status_producer_target")
	ActorFactory.with_body_cultivation(defender)
	defender.meridians.unlock_for_realm(&"qi_refining")
	return {"attacker": attacker, "defender": defender}


## One root-built hero, enrolled on the body path the way the shipped player is, with the
## per-hit resolver installed. `CombatBoot.install` binds the mechanisms AND installs
## [method CombatBoot.resolve_hit], which is the branch of `resolve_hit` that actually
## passes a `ctx_builder` into the spine.
func _hero() -> Actor:
	var actor := ActorFactory.with_body_cultivation(ActorFactory.build(&"bruiser", HERO_BASE))
	CombatBoot.install(actor)
	return actor


## The shipped `.tres` by id, read the way a live cast reads it, and COPIED because the
## catalogue hands back one shared instance per id.
func _authored(technique_id: StringName) -> TechniqueDef:
	var def := TechniqueCatalog.instance().definition(technique_id)
	assert_ne(def, null, "the shipped %s loads" % String(technique_id))
	return null if def == null else def.duplicate(true) as TechniqueDef


## One blow through the shipped entry point, on a seeded generator so the roll is real and
## reproducible. Returns the outcome's primitives-only dict, which is what a screen reads.
func _blow(pair: Dictionary, technique: TechniqueDef, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return (
		CombatBoot
		. resolve_hit(pair["attacker"], pair["defender"], technique, CombatEngineApi.tuning(), rng)
		. to_dict()
	)


## What `CombatBoot.ctx_builder_for` staged, or null. The one place the suite asks the
## production builder for a context, so every row above it cannot diverge from it.
func _staged(pair: Dictionary, technique: Variant) -> AttackContext:
	var ctx := AttackContext.new(
		pair["attacker"], pair["defender"], technique, CombatEngineApi.tuning(), 100.0
	)
	var built: Variant = (
		CombatBoot.ctx_builder_for(pair["attacker"], pair["defender"], technique).call(ctx)
	)
	return built as AttackContext if built != null else null


## `StatusApi.has_status` asks the CATALOGUE whether an id exists, not an actor whether it
## holds one. The actor's own answer is `Actor.has_status`, which is the contract
## `StatusApply.apply` gates on (`status_apply.gd:223`) and the only witness that matters
## here — a status the catalogue knows and the actor does not hold applied nothing.
func _holds(actor: Actor, status_id: StringName) -> bool:
	return actor.has_status(status_id)


## The `status_application` row one outcome carries, or `{}`. Read by kind rather than by
## index, because the body path files its own `body.wound` row first.
func _status_row(outcome: Dictionary) -> Dictionary:
	for entry in outcome.get("effects", []) as Array:
		if (
			entry is Dictionary
			and StringName((entry as Dictionary).get("kind", &"")) == EFFECT_KIND
		):
			return entry as Dictionary
	return {}


# --- 1. the producer writes the key, and a SHIPPED one -------------------------


## THE load-bearing row. The shipped `ctx_builder` writes ADR 0087's request onto `ctx.data`
## under `StatusApply.REQUEST_KEY`, for an AUTHORED element, naming the id the authored
## catalogue claims.
##
## It reads the key back through `AttackContext.data_value` with `StatusApply.REQUEST_KEY`
## itself, so it cannot pass by agreeing with a spelling of its own: a producer that
## invented a different key, or named a status the catalogue does not claim, answers the
## wrong id here.
func test_the_shipped_ctx_builder_writes_the_status_request_for_an_authored_element() -> void:
	var pair := _pair()
	var technique := _authored((EARTH_BODY[0]) as StringName)
	assert_ne(technique, null, "the authored body technique is the subject under test")
	if technique == null:
		return
	var staged := _staged(pair, technique)
	assert_ne(staged, null, "the production builder staged a context")
	if staged == null:
		return
	var raw: Variant = staged.data_value(StatusApply.REQUEST_KEY, null)
	assert_eq(raw is Dictionary, true, "REQUEST_KEY rides ctx.data after the shipped builder")
	if not (raw is Dictionary):
		return
	var request := raw as Dictionary
	assert_eq(
		StringName(request.get("id", &"")),
		EARTH_QUAKE,
		"and the id is the one the authored catalogue claims for a landed earth blow"
	)
	assert_eq(
		StringName(request.get("element", &"")),
		EARTH,
		"carrying the element it was authored from, for ADR 0088's potency read"
	)
	# The gate is DATA and not a literal in `app/` (ADR 0087's `status_chance`, which ADR
	# 0105 moved onto `CombatTuning.status_gate_chance`): a producer that restated `1.0`
	# in `app/` would survive every other row in this file.
	assert_almost_eq(
		float(request.get("chance", -1.0)),
		CombatEngineApi.tuning().status_gate_chance,
		"the gate is the shipped tuning's, not a number the producer chose"
	)


## The carrier is the ELEMENT, not the technique. ADR 0105 decided that shape and ADR 0088
## restated it ("mastery never gates a status by name"), so two techniques carrying one
## element must AGREE — and neither of them names any status at all.
##
## `body_tremor_cadence` and `body_iron_skin` are both authored `element = &"earth"`. A
## producer that keyed on the technique, or that added ADR 0087's per-technique status gate
## as a SECOND condition, answers `&""` for at least one of them: neither `.tres` carries a
## status field, and ADR 0105 refused to give `TechniqueDef` one.
func test_two_authored_body_techniques_of_one_element_agree_on_the_status() -> void:
	var pair := _pair()
	var ids: Array[String] = []
	for technique_id in EARTH_BODY:
		var technique := _authored(technique_id as StringName)
		assert_ne(technique, null, "the authored body technique loads")
		if technique == null:
			return
		assert_eq(
			StringName(technique.element),
			EARTH,
			(
				"%s really is authored as an earth blow, or this row proves nothing"
				% String(technique_id)
			)
		)
		var staged := _staged(pair, technique)
		var raw: Variant = (
			staged.data_value(StatusApply.REQUEST_KEY, null) if staged != null else null
		)
		ids.append(String((raw as Dictionary).get("id", &"")) if raw is Dictionary else "")
	assert_eq(ids.size(), EARTH_BODY.size(), "both techniques were asked")
	assert_eq(ids[0], String(EARTH_QUAKE), "the first carries the catalogue's earth status")
	assert_eq(ids[1], ids[0], "and the second agrees with it: the carrier is the ELEMENT")


## ## And the negative: NO double gate, and no status invented where none is authored
##
## ADR 0105 refused a `TechniqueDef` status field outright, and the reason it gives is that
## the element ALREADY answers the question. A producer that also required the technique to
## name a status would be exactly the second gate ADR names as the failure mode: it would
## answer `&""` for every one of the 52 shipped `.tres`, none of which carries a status
## field, and the whole system would be unreachable again while the element mapping sat
## there working.
##
## So: an elementless blow writes NOTHING, and an element nobody authored writes nothing
## either. Neither is a crash, and neither invents a status.
func test_an_elementless_blow_writes_no_request_and_crashes_nothing() -> void:
	var pair := _pair()
	var technique := _authored(&"body_stone_anchor")
	assert_ne(technique, null, "an authored elementless body technique exists to test with")
	if technique == null:
		return
	assert_eq(StringName(technique.element), &"", "which really does author no element")
	var staged := _staged(pair, technique)
	assert_ne(staged, null, "the builder still staged a context: an elementless blow degrades")
	if staged == null:
		return
	assert_eq(
		staged.data_value(StatusApply.REQUEST_KEY, null),
		null,
		"and carries no request at all, so S12 withholds quietly rather than guessing"
	)


## A blow carrying an element NO def claims writes nothing either. This is the "degrade,
## never throw" half of the contract, and it is checked against the real loader: the shipped
## catalogue admits only `StatusDef.AUTHORED_ELEMENTS`, so the request is refused AT THE
## MAPPING rather than at a roll that will not be taken.
func test_an_element_no_authored_status_claims_produces_no_request() -> void:
	var pair := _pair()
	var technique := _authored((EARTH_BODY[0]) as StringName)
	assert_ne(technique, null, "the earth technique loads")
	if technique == null:
		return
	# Not a `.tres`: this is a hypothetical, and the point is that production REFUSES it.
	technique.element = &"not_an_element"
	var staged := _staged(pair, technique)
	assert_ne(staged, null, "the builder staged a context anyway")
	if staged == null:
		return
	assert_eq(
		staged.data_value(StatusApply.REQUEST_KEY, null),
		null,
		"no authored status claims it, so no request is written and no hit breaks"
	)


# --- 2. the stage actually applies it, through production ----------------------


## The end-to-end row: a clean landed body blow through `CombatBoot.resolve_hit` leaves the
## defender HOLDING the authored status, and the result rides `effects[]` as
## `status_application` for a panel to render.
##
## This is the assertion DEF-0145's measurement made impossible: with no producer the
## outcome carried `status withheld: no request` and the actor held nothing. The `not_clean`
## and `no_request` refusals are both visible in the row, so the assertion below is about
## `applied` and not about the absence of a row.
func test_a_clean_landed_body_blow_applies_the_authored_status_to_the_defender() -> void:
	var pair := _pair()
	var technique := _authored((EARTH_BODY[0]) as StringName)
	assert_ne(technique, null, "the authored body technique loads")
	if technique == null:
		return
	var defender: Actor = pair["defender"]
	assert_eq(_holds(defender, EARTH_QUAKE), false, "the defender starts clean")
	var outcome := _blow(pair, technique, 20251004)
	assert_eq(
		bool(outcome.get("clean", false)), true, "the blow landed clean: S12 gates on is_clean()"
	)
	var row := _status_row(outcome)
	assert_eq(row.is_empty(), false, "and S12 filed a status_application row on effects[]")
	if row.is_empty():
		return
	assert_eq(
		bool(row.get("applied", false)),
		true,
		"the status APPLIED: %s" % String(row.get("refused", ""))
	)
	assert_eq(String(row.get("status_id", "")), String(EARTH_QUAKE), "naming the authored id")
	# ADR 0088's potency is a non-negative element term by construction, so a negative
	# reading would be a sign bug rather than a tuning question.
	assert_eq(
		bool(row.get("potency", 0.0) >= 0.0),
		true,
		"and carrying ADR 0088's potency, which cannot be negative by construction"
	)
	# The actor, not just the report. A row that says applied over an actor holding
	# nothing would be a readout lying, which is the whole defect class ADR 0089 recorded.
	assert_eq(
		_holds(defender, EARTH_QUAKE),
		true,
		"and the DEFENDER really carries it: the report is not the only witness"
	)


## The stage's load-bearing gate, driven through PRODUCTION rather than by staging a
## refusal: a defender whose block rate is saturated answers this blow, and a blow that was
## answered applies nothing and files no row at all — because `StatusApply.record`
## suppresses `not_clean` rather than filling `effects[]` with a row per swing.
##
## Saturated rather than probabilistic so the row cannot pass for the wrong reason: a draw
## that merely MIGHT have blocked would make "no status" unfalsifiable.
func test_a_blocked_blow_applies_nothing_and_files_no_row() -> void:
	var pair := _pair()
	var technique := _authored((EARTH_BODY[0]) as StringName)
	assert_ne(technique, null, "the authored body technique loads")
	if technique == null:
		return
	var defender: Actor = pair["defender"]
	_saturate(defender, CombatStats.BLOCK_RATE)
	var outcome := _blow(pair, technique, 7)
	assert_eq(
		bool(outcome.get("clean", false)),
		false,
		"the blow was BLOCKED, not merely unlucky: p_block is saturated"
	)
	assert_eq(
		bool(outcome.get("blocked", false)),
		true,
		"which is the band that was answered -- so the row below is about the band"
	)
	assert_eq(
		_status_row(outcome).is_empty(), true, "so S12 applied nothing and filed no row to say so"
	)
	assert_eq(
		_holds(defender, EARTH_QUAKE),
		false,
		"and the defender holds nothing: a block is an answer, not a free hit"
	)


## And the mechanism-independent half of ADR 0105's shape: the stage rides on whichever
## builder won, so a QI blow carrying an authored element resolves the SAME catalogue
## relation a body blow does. `qi_cinder_lance` is authored `element = &"fire"`.
##
## This is what makes the producer a property of the BLOW rather than of the mechanism — the
## reason `ctx_builder_for` composes it OVER the builder instead of putting it in one
## `match` arm, which would have made fire-on-qi and earth-on-body two different systems.
func test_the_same_producer_rides_a_qi_blow_for_its_own_element() -> void:
	var attacker := ActorFactory.build(&"seer", HERO_BASE)
	CombatBoot.install(attacker)
	var pair := {"attacker": attacker, "defender": ActorFactory.spawn_inhabitant(&"qi_target")}
	var technique := _authored(&"qi_cinder_lance")
	assert_ne(technique, null, "the authored fire technique loads")
	if technique == null:
		return
	assert_eq(StringName(technique.element), FIRE, "which really is authored as a fire blow")
	var staged := _staged(pair, technique)
	assert_ne(staged, null, "the qi builder staged a context")
	if staged == null:
		return
	var raw: Variant = staged.data_value(StatusApply.REQUEST_KEY, null)
	assert_eq(raw is Dictionary, true, "the qi builder's context carries the request too")
	if raw is Dictionary:
		assert_eq(
			StringName((raw as Dictionary).get("id", &"")),
			FIRE_IMMOLATION,
			"naming the fire element's authored status, not the body's earth one"
		)


# --- internals -----------------------------------------------------------------


## Drive `id` on `actor` to a saturated `p_block`/`p_parry`, so the band's draw is decided
## by the draw rather than by the fixture's luck.
##
## `CombatBand.rate` is `clampf(maxf(0, rate - resist) / rate_scale, 0, 1)`, and both ends
## of the contest are flat rates whose baseline is `CombatStats.default_of` — so a FLAT
## modifier big enough to clear `rate_scale` saturates the band whatever the attacker's own
## stat is. The value is subtracted rather than assigned because `ActorStats` applies a FLAT
## modifier as an OFFSET on a provider's contribution (BRIEF 0a): the number here is
## measured from the actor, not restated, or the row would be testing the fixture's own
## arithmetic.
func _saturate(actor: Actor, id: StringName) -> void:
	var tuning := CombatEngineApi.tuning()
	var now := actor.stats.derived(id)
	var ceiling := CombatStats.default_of(id) + tuning.rate_scale * BLOCK_SATURATION
	actor.stats.add_modifier(
		StatModifier.new(id, Stat.Op.FLAT, ceiling - now, &"status_producer_band_probe")
	)
	actor.mark_stats_dirty()
