extends TestCase

## That the SPINE is reachable from PRODUCTION — the three gaps between "the engine is
## green" and "the game can feel it" (ADR 0154).
##
## ## What this file is evidence for
##
## `uv run python -m tools test --suite combat_engine` was 5561 passing with three
## mechanisms fully built. None of them could fire in the shipped app:
##
##   - `CombatBoot.install` was never called from `_build_actor`, so
##     `PlayerAdapter.attack` refused every blow with "no attack resolver is installed";
##   - `CombatBoot._mechanism_for` resolved the both-paths case to qi, and the shipped
##     player is on THREE paths, so `QiDamage` was bound for every player actor and body
##     and mind could never fire at all;
##   - `CombatSpine.resolve_hit`'s `ctx_builder` defaulted to empty and the only
##     production caller passed five arguments, so `QiDamage.builder` /
##     `BodyDamage.builder` / `MindDamage.builder` were never called from `src/` and
##     `element_share` / `aim_meridian` were inert.
##
## Each section below is one of those, asserted against the PRODUCTION entry point
## rather than against a hand-wired one. A test that binds a mechanism itself proves the
## mechanism works; only a test that goes through `CombatBoot` proves the game can reach
## it, and that is the gap this file exists to close.
##
## ## Every actor here is built the way PRODUCTION builds it
##
## `ActorFactory.build` plus the enrolment verbs — the same rule
## `test_combat_boot.gd` states at length. A fixture that hand-attaches an acupoint set
## would hide the very hole this file is measuring.

const ELEMENT := &"fire"

## `CombatCatalog` is process-wide, so a suite that registered the same id twice would
## have its second def silently replace the first. A serial keeps every fixture id in
## this file unique, exactly as `test_technique_active.gd` does.
static var _technique_serial: int = 0
var _harness: SeamHarness = null

# --- The shipped player --------------------------------------------------------


## The player exactly as `ItemWorkbenchApp._build_actor` builds one: body, qi and mind
## enrolled, in that order. This is the ACTOR the whole file is about, and the one the
## audit said could only ever fight through qi.
func _player() -> Actor:
	var actor := ActorFactory.build(&"player")
	ActorFactory.with_body_cultivation(actor)
	ActorFactory.with_qi_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	return actor


## A defender with the same three paths, so a body hit has a location axis to land on
## and a mind hit a sea to erode. Built through the same verbs, never by hand.
func _tri_path_defender(id: StringName = &"ward") -> Actor:
	var actor := ActorFactory.build(id)
	ActorFactory.with_body_cultivation(actor)
	ActorFactory.with_qi_cultivation(actor)
	ActorFactory.with_mind_cultivation(actor)
	return actor


## An `ActorFactory.build` actor with nothing but the element provider — what every npc
## and mob is, and the shape that must keep working untouched.
func _bare(id: StringName = &"mob") -> Actor:
	return ActorFactory.build(id)


## A technique on `path_id` with the authored qi fields set. In-memory, because
## `TechniqueDef` is a `Resource` and the point is the PATH the def declares, not which
## `.tres` declared it.
func _technique(
	path_id: StringName, share: float = 0.0, meridian: StringName = &""
) -> TechniqueDef:
	var def := TechniqueDef.new()
	def.path = path_id
	def.magnitude = 100.0
	def.element = ELEMENT
	def.element_share = share
	def.aim_meridian = meridian
	return def


## Install the composition root's whole combat stack on `actor`, exactly as
## `_build_actor` does.
func _installed(actor: Actor) -> Dictionary:
	return CombatBoot.install(actor)


# --- GAP A: the attack resolver is actually installed --------------------------


## The premise. `has_attack_resolver` used to read
## `_resolver.is_null() or _resolver.is_valid()`, which is `true` in EVERY case — so it
## reported "installed" on a process that had installed nothing, and `PlayerAdapter
## .attack`'s only gate could never close. Asserted BEFORE anything installs one, so the
## "after" assertion below is a real transition and not a tautology.
func test_no_resolver_is_reported_before_anything_installs_one() -> void:
	CombatBoot.set_attack_resolver(Callable())
	assert_eq(CombatBoot.has_attack_resolver(), false, "an empty install is not an install")
	assert_eq(
		String(CombatBoot.set_attack_resolver(Callable())["reason"]),
		"no_resolver",
		"and it names itself rather than reporting success"
	)


## `install` closes the gap: the resolver is installed, the read agrees with the report,
## and a blow actually lands through it. The third assertion is the one that matters —
## `has_attack_resolver()` being true while `strike` refuses would mean the two guards
## disagree, which is precisely the state this file was written to rule out.
func test_install_leaves_an_attack_resolver_that_strike_actually_uses() -> void:
	var attacker := _player()
	var defender := _tri_path_defender()
	_installed(attacker)
	assert_eq(CombatBoot.has_attack_resolver(), true, "install wires the attack resolver")
	var report := CombatBoot.strike(attacker, defender, 7)
	assert_eq(String(report["reason"]), "", "and a blow through it is not refused as unresolvable")
	assert_eq(bool(report["ok"]), true, "so the blow was actually attempted")
	assert_eq(
		CombatBoot.has_attack_resolver(),
		bool(report["ok"]),
		"the guard `PlayerAdapter.attack` reads agrees with what `strike` did"
	)


## Un-installing is deterministic, because a test on this box has to be able to restore
## the process-wide seam it borrowed. An empty Callable clears it and the read drops —
## which is only observable if `is_valid()` is the whole answer.
func test_an_empty_callable_unsinstalls_rather_than_silently_keeping_the_old_one() -> void:
	_installed(_player())
	assert_eq(CombatBoot.has_attack_resolver(), true, "installed")
	CombatBoot.set_attack_resolver(Callable())
	assert_eq(CombatBoot.has_attack_resolver(), false, "and an empty Callable clears it")
	assert_eq(
		String(CombatBoot.strike(_player(), _tri_path_defender(), 1)["reason"]),
		"no_resolver",
		"so `strike` refuses by name instead of calling a dead Callable"
	)
	# Restore, so this suite leaves the process as it found it.
	_installed(_player())


# --- GAP B: the technique's path selects the mechanism ------------------------


## The measurement the audit made, asserted as a test. A tri-path actor IS the shipped
## player, so under the old rule `has_body == has_mind` held and every one of them got
## qi. This asserts the tri-path actor is STILL qi when bound — the rule above did not
## change — so a reader can see the fix is not "body wins".
func test_the_installed_binding_for_a_tri_path_actor_is_still_qi() -> void:
	assert_eq(
		String(_installed(_player())["mechanism"]),
		"QiDamage",
		"the neutral binding is unchanged: a dual-cultivator still binds qi"
	)


## The fix itself, one technique at a time, on the SHIPPED PLAYER. Before this, both of
## these were `QiDamage`; a body technique landed as an elemental share and never
## subtracted from a meridian.
func test_the_technique_path_selects_the_mechanism_on_the_shipped_player() -> void:
	var player := _player()
	_installed(player)
	assert_eq(
		String(CombatBoot.mechanism_for_hit(player, _technique(PathState.BODY))),
		"BodyDamage",
		"a body technique on a tri-path player selects BodyDamage"
	)
	assert_eq(
		String(CombatBoot.mechanism_for_hit(player, _technique(PathState.QI))),
		"QiDamage",
		"and a qi technique on the SAME actor selects QiDamage"
	)
	assert_eq(
		String(CombatBoot.mechanism_for_hit(player, _technique(PathState.MIND))),
		"MindDamage",
		"so all three are reachable from one actor, which was the whole point"
	)


## The selection is scoped to the hit and the attacker's binding is RESTORED, which is
## the property that lets a per-hit switch exist without editing the spine. Observed
## through the CONCRETE object rather than the name, because a rename that changed the
## class without changing the string would pass the assertions above.
func test_the_selection_binds_the_concrete_mechanism_and_then_restores_it() -> void:
	var player := _player()
	_installed(player)
	var before: DamageMechanism = CombatEngineApi.mechanism_of(player)
	assert_eq(before is QiDamage, true, "the shipped player is bound to qi to begin with")
	assert_eq(
		String(CombatBoot.mechanism_for_hit(player, _technique(PathState.BODY))),
		"BodyDamage",
		"and a body technique selects body for the duration of the hit"
	)
	var during := CombatBoot.resolve_hit(
		player, _tri_path_defender(&"ward_a"), _technique(PathState.BODY)
	)
	assert_eq(float(during.base) > 0.0, true, "and the body hit resolved through the spine")
	assert_eq(
		CombatEngineApi.mechanism_of(player),
		before,
		"the attacker is left bound to the mechanism it had, not the one the hit used"
	)


## A technique the ATTACKER cannot produce falls back to the installed mechanism rather
## than binding one whose inputs read `0.0`. A bare mob has no acupoint set and no sea, so
## asking it for a body strike must not produce a body mechanism: that is the failure
## mode that would make every hit collapse to the chip floor.
func test_a_mechanism_the_attacker_lacks_the_inputs_for_is_not_selected() -> void:
	var bare := _bare(&"drone")
	_installed(bare)
	assert_eq(bare.component(&"acupoints"), null, "the premise: no acupoint set is mounted")
	assert_eq(
		String(CombatBoot.mechanism_for_hit(bare, _technique(PathState.BODY))),
		"QiDamage",
		"so a body technique falls back to what this actor can actually run"
	)
	assert_eq(
		String(CombatBoot.mechanism_for_hit(bare, _technique(PathState.MIND))),
		"QiDamage",
		"and so does a mind one, for the same reason"
	)


## The two shapes that name no single path, which must not become a coin flip.
##
## A SHARED technique takes the INSTALLED mechanism — the qi fallback a pathless technique
## wants, and what all six `shared_*.tres` shipped with. A DUAL takes the first it can
## produce in AUTHORED order, so `qi_cultivation+body_cultivation` prefers qi and the
## choice is the author's rather than this file's. Both are pinned because "deterministic
## but arbitrary" is the shape a later edit silently turns into a coin flip.
func test_a_shared_technique_takes_the_installed_one_and_a_dual_takes_its_first_path() -> void:
	var player := _player()
	_installed(player)
	assert_eq(
		String(CombatBoot.mechanism_for_hit(player, _technique(TechniquePolicy.SHARED))),
		"QiDamage",
		"a SHARED technique names no path and takes the installed mechanism"
	)
	assert_eq(
		String(
			CombatBoot.mechanism_for_hit(
				player, _technique(PathState.QI + TechniquePolicy.DUAL_SEPARATOR + PathState.BODY)
			)
		),
		"QiDamage",
		"a dual qi+body technique prefers qi, which is the authored order"
	)
	assert_eq(
		String(
			CombatBoot.mechanism_for_hit(
				player, _technique(PathState.BODY + TechniquePolicy.DUAL_SEPARATOR + PathState.MIND)
			)
		),
		"BodyDamage",
		"and a dual body+mind one prefers body, so body is reachable through a dual too"
	)


## The degenerate inputs must not raise. This runs per hit on whatever a caller hands
## in, so a null technique, an unbound actor and a def that cannot answer `path_ids` all
## have to degrade to the qi fallback rather than assert — `MechanismSlot.of` asserts and
## this must never reach it.
func test_degenerate_selection_inputs_degrade_instead_of_raising() -> void:
	var bare := _bare(&"nothing")
	assert_eq(String(CombatBoot.mechanism_for_hit(bare, null)), "QiDamage", "a null technique")
	assert_eq(
		String(CombatBoot.mechanism_for_hit(null, _technique(PathState.BODY))),
		"QiDamage",
		"a null attacker"
	)
	assert_eq(
		String(CombatBoot.mechanism_for_hit(bare, RefCounted.new())),
		"QiDamage",
		"and a def that cannot answer its own paths"
	)


# --- GAP C: the authored fields reach the mechanism ---------------------------


## The hole, measured: with no `ctx_builder` the authored `element_share` never arrives,
## so `QiDamage._share_of` falls to `default_element_share` and every one of the 55
## authored `.tres` — 0.1 through 1.0 — was inert. Two different authored shares are
## pushed through the SPINE and read back from the mechanism the spine actually ran, so
## this asserts the production path rather than a hand-built `AttackContext`.
##
## The read is `QiDamage.breakdown`, because `CombatOutcome.to_dict` is the SPINE's
## descriptor and deliberately says nothing about which mechanism produced it — the
## readout that knows is the mechanism's own, which is also what a damage panel would be
## handed. `CombatEngineApi.mechanism_of(attacker)` is read AFTER `resolve_hit`, which
## restores the attacker, so this observes the mechanism the hit used rather than the one
## it left bound.
func test_the_authored_element_share_reaches_the_mechanism_through_the_spine() -> void:
	var player := _player()
	var defender := _tri_path_defender()
	var tuning := CombatEngineApi.tuning()
	var high := clampf(tuning.default_element_share + 0.37, 0.0, 1.0)
	var low := maxf(high - 0.2, 0.0)
	assert_eq(high > low, true, "the two probes are genuinely different shares")

	var high_read := _share_of_resolved_hit(
		player, defender, _technique(PathState.QI, high), tuning
	)
	var low_read := _share_of_resolved_hit(player, defender, _technique(PathState.QI, low), tuning)
	assert_almost_eq(high_read, high, "the authored share is what the hit was worth")
	assert_almost_eq(low_read, low, "and a second, different share is read as ITS OWN")
	assert_eq(
		high_read != low_read,
		true,
		"so the two hits differ — the field is read, not clamped to the default"
	)


## One hit through the spine, then the mechanism's own readout for the share it saw.
## The context is rebuilt with the production `ctx_builder` — the same thing the spine
## did inside the call — because `CombatEngineApi.mechanism_of` after the call returns the
## mechanism the attacker was RESTORED to, not the one the hit ran.
func _share_of_resolved_hit(
	player: Actor, defender: Actor, technique: TechniqueDef, tuning: CombatTuning
) -> float:
	var installed := CombatBoot.install(player)
	assert_eq(bool(installed["ok"]), true, "the combat stack installed for the hit")
	var selected := CombatBoot.mechanism_for_hit(player, technique)
	var outcome := CombatBoot.resolve_hit(player, defender, technique, tuning, null)
	assert_eq(outcome.missed, false, "a null rng lands every strike, so this one reached S4")
	assert_eq(String(selected), "QiDamage", "a qi technique ran the qi mechanism")
	assert_eq(
		String(CombatBoot.mechanism_for_hit(player, technique)),
		"QiDamage",
		"and the selection is stable across calls, so the restore restored the same one"
	)
	var ctx := _context_for(player, defender, technique, tuning)
	return float(QiDamage.new().breakdown(ctx)["share"])


## The context the spine would build for this hit, with the production `ctx_builder`
## applied — the same two lines `CombatSpine._context` runs, so the read observes what
## the mechanism saw rather than re-deriving it.
func _context_for(
	attacker: Actor, defender: Actor, technique: TechniqueDef, tuning: CombatTuning
) -> AttackContext:
	var ctx := AttackContext.new(attacker, defender, technique, tuning)
	ctx.set(&"base", CombatSpine.base_damage(attacker, technique))
	ctx.set(&"magnitude", ctx.base)
	ctx.set(&"rolled", true)
	ctx.set(&"crit", false)
	return CombatBoot.ctx_builder_for(attacker, defender, technique).call(ctx) as AttackContext


## The production descriptor carries the authored element — not just the share. The
## element was equally inert before this wiring, and without it `element_power_<e>` never
## reaches the formula at all, so a share that "worked" on an `&""` element would prove
## nothing.
func test_the_production_context_carries_the_authored_element_too() -> void:
	var player := _player()
	var defender := _tri_path_defender()
	var authored := 0.62
	var ctx := _context_for(
		player, defender, _technique(PathState.QI, authored), CombatEngineApi.tuning()
	)
	assert_almost_eq(
		float(ctx.data_value(QiDamage.ELEMENT_SHARE_KEY, 0.0)),
		authored,
		"the authored share rides `ctx.data` verbatim"
	)
	assert_eq(
		String(ctx.data_value(QiDamage.ELEMENT_KEY, &"")),
		String(ELEMENT),
		"and so does the authored element"
	)
	assert_eq(
		ctx.data_value(QiDamage.ELEMENT_RULES_KEY, null) == null,
		false,
		"with a rules table injected, so the matchup graph is live in production"
	)


## The body half of the same hole. `BodyDamage._mode_of` reads the authored
## `aim_meridian` off `ctx.data` and resolves an authored `&""` as `random`, so a body
## technique that names a meridian can only take the `named` branch if the builder ran.
## `BodyDamage.breakdown` reports the resolved `mode` and the `sites[]` it landed on.
func test_the_authored_aim_meridian_reaches_the_body_mechanism() -> void:
	var player := _player()
	var defender := _tri_path_defender()
	var meridian := _an_unlocked_meridian(defender)
	assert_ne(meridian, &"", "the defender really has an unlocked meridian to aim at")
	var ctx := _context_for(
		player, defender, _technique(PathState.BODY, 0.0, meridian), CombatEngineApi.tuning()
	)
	assert_eq(
		StringName(ctx.data_value(BodyDamage.AIM_MERIDIAN_KEY, &"")),
		meridian,
		"the authored meridian rides `ctx.data` verbatim"
	)
	var body := BodyDamage.new()
	var parts := body.breakdown(ctx)
	assert_eq(
		String(parts.get("mode", "")),
		String(BodyLocation.MODE_NAMED),
		"so the strike is NAMED, which the empty `ctx_builder` made a rolled one"
	)
	assert_eq(
		StringName((parts.get("sites", [{}]) as Array)[0].get("meridian_id", &"")),
		meridian,
		"and it landed on the meridian the author named"
	)


## One unread meridian, taken from the defender's own network rather than named here, so
## this test cannot break because a meridian id was renamed in the authored data.
func _an_unlocked_meridian(defender: Actor) -> StringName:
	var ctx := AttackContext.new(defender, defender, null, CombatEngineApi.tuning())
	# `meridian_network()` is a `StatContext` accessor — `ctx` is an `AttackContext`, so
	# it is read off `ctx.target`. Calling it on the context itself is a nonexistent-
	# function error, which aborts the caller and reports no assertion at all.
	# `Variant`, never `:=`: the accessor answers whatever the defender carries, so
	# there is no set type to infer and an inferred `null` comparison is a parse error.
	var network: Variant = ctx.target.meridian_network()
	if network == null:
		return &""
	var state: Variant = network.call(&"get_meridian", &"lung")
	if state != null:
		return &"lung"
	for id in [&"hand", &"foot", &"heart", &"kidney"]:
		if network.call(&"get_meridian", StringName(id)) != null:
			return StringName(id)
	return &""


# --- The three together, through the app's OWN seam -----------------------------
#
# Everything above this line calls `CombatBoot.resolve_hit` DIRECTLY. Those are
# correct unit assertions and they stay — but a direct call is not evidence that
# PRODUCTION routes there, and this file used to be exactly that: every case green
# while `ItemWorkbenchApp._resolve_technique_hit` went straight to
# `CombatEngineApi.breakdown`, so the spine read `MechanismSlot.of(attacker)` — always
# `QiDamage` on a tri-path player — and a body technique ran as an elemental share with
# `aim_meridian` riding in `ctx.data` unread. `CombatBoot._hit_resolver` had zero callers
# in `src/`, so ADR 0161's "body and mind could never fire at all" was still true with
# this suite at 100% green.
#
# So the cases below drive the SEAM (`SeamHarness` mounts the shipped
# `ItemWorkbenchApp.tscn` and drives its `_ready`, which is what installs
# `TechniqueCasting.set_resolver`) and fire through `TechniqueCasting.activate` — the
# call `technique_loadout.gd:182` makes when a player presses the button. Deleting the
# production routing turn now fails these and leaves every unit case above green, which
# is the whole point of having both.


## The integration assertion: the seam `TechniqueCasting` is handed is the one that
## reaches the mechanism AND carries the authored inputs. This resolves exactly as
## `ItemWorkbenchApp._resolve_technique_hit` does and checks the spine spent real damage
## on a BODY strike — a claim no amount of unit testing the three pieces separately could
## make, and the one that was impossible before this change because the shipped player's
## only mechanism was qi.
func test_a_body_technique_on_the_shipped_player_spends_damage_as_a_body_hit() -> void:
	var player := _player()
	var defender := _tri_path_defender()
	var meridian := _an_unlocked_meridian(defender)
	assert_ne(meridian, &"", "the defender really has an unlocked meridian to aim at")
	CombatBoot.install(player)
	var technique := _technique(PathState.BODY, 0.0, meridian)
	assert_eq(
		String(CombatBoot.mechanism_for_hit(player, technique)),
		"BodyDamage",
		"and the shipped player really does select it for a body technique"
	)
	var outcome := CombatBoot.resolve_hit(
		player, defender, technique, CombatEngineApi.tuning(), null
	)
	assert_eq(outcome.missed, false, "the strike landed rather than missing")
	assert_eq(float(outcome.amount) > 0.0, true, "and it spent real damage on the target")
	assert_eq(
		float(outcome.base) > 0.0,
		true,
		"from S1's rate-gated magnitude, so the spine really ran rather than short-circuiting"
	)


# --- PRODUCTION ROUTING: the two that could never fire -------------------------


## The harness mounts the shipped scene and drives `_ready`, which is what installs
## `TechniqueCasting.set_resolver` and binds `CombatBoot` on the app's own hero. Mounted
## once per test and torn down after, because the seams it installs are process-wide.
func setup() -> void:
	_harness = SeamHarness.mount_new()


func teardown() -> void:
	if _harness != null:
		_harness.teardown()
	_harness = null


## The def an `activate` call must find, on `path_id`, learned and EQUIPPED on
## `actor` — `TechniqueCasting.activate` refuses with `not_equipped` otherwise, and a
## refusal would prove nothing about the mechanism. `codex.learn` then the real `equip`
## facade verb, never `TechniquesApi.learn`: `learn` is paid for out of cultivation
## progress, and the study price is not what this section is about.
func _equipped(actor: Actor, path_id: StringName, meridian: StringName = &"") -> TechniqueDef:
	_technique_serial += 1
	var def := TechniqueDef.new()
	def.id = StringName("reachability_production_%d" % _technique_serial)
	def.display_name = "Strike"
	def.grade = ItemGrade.MORTAL
	def.active = true
	def.path = path_id
	def.magnitude = 100.0
	def.element = ELEMENT
	def.aim_meridian = meridian
	TechniqueCatalog.instance().register(def)
	TechniquesApi.codex(actor).learn(def.id)
	var equipped: Dictionary = TechniquesApi.equip(actor, def)
	assert_eq(
		bool(equipped.get("ok", false)),
		true,
		"the fixture def is bound into a real slot (%s)" % String(equipped.get("reason", ""))
	)
	return def


## The `TechniqueCasting` component the app's own `_ready` mounted on `actor`, which
## is what `technique_loadout.gd:_casting` reads before it calls `activate`.
func _casting_of(actor: Actor) -> TechniqueCasting:
	var casting: Variant = actor.component(TechniquesApi.CASTING_COMPONENT)
	assert_ne(casting, null, "the composition root attached the casting table")
	return casting as TechniqueCasting


## Fire `def` from `player` at `defender` through the PRODUCTION seam and return the
## descriptor `activate` handed back. No resolver argument: `_seam_for` then falls
## through to the one `ItemWorkbenchApp._bind_technique_seams` installed, which is the
## whole subject of this section.
func _fire_through_production(player: Actor, defender: Actor, def: TechniqueDef) -> Dictionary:
	var fired: Dictionary = _casting_of(player).activate(player, def, defender)
	assert_eq(
		String(fired.get("reason", "")),
		"",
		"the activation was refused, so nothing below is evidence of anything"
	)
	assert_eq(bool(fired.get("resolved", false)), true, "and it produced a damage descriptor")
	return fired.get("damage", {}) as Dictionary


## **BODY fires in production.** This is the case the old suite hid. It fires a BODY
## technique through `activate` on the app's own tri-path hero and asserts the damage
## was priced by a MERIDIAN — `BodyDamage.resolve` emits one `body.wound` effect per
## struck site carrying that meridian id, and `QiDamage.resolve` emits NO effects at
## all — so the effects array is the discriminator between the two mechanisms, not a
## proxy for it. The qi contrast is asserted in the same breath: the same hero, the same
## cast path, a QI technique, and NO wound.
##
## Under the old routing this failed with `effects == []`, which is the exact symptom
## `test_a_body_technique_on_the_shipped_player_spends_damage_as_a_body_hit` above could
## not see: it called `CombatBoot.resolve_hit` itself and so got the mechanism selection
## for free.
func test_a_body_technique_fired_through_production_lands_at_a_meridian() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted, or nothing below is proven")
	var player := _harness.actor
	var defender := _tri_path_defender()
	var meridian := _an_unlocked_meridian(defender)
	assert_ne(meridian, &"", "the defender really has an unlocked meridian to aim at")
	# The premise, stated so the contrast below is not vacuous. This hero was built and
	# installed by the app's own `_ready`, so its BOUND mechanism is qi — the both-paths
	# case `CombatBoot.bind_mechanisms` takes on purpose, and exactly the state the
	# per-hit switch has to override.
	assert_eq(
		CombatEngineApi.mechanism_of(player) is QiDamage, true, "the shipped hero is BOUND to qi"
	)
	assert_eq(
		String(CombatBoot.mechanism_for_hit(player, _technique(PathState.BODY))),
		"BodyDamage",
		"and a body technique on it selects body anyway — the per-hit switch, not the slot"
	)

	var damage := _fire_through_production(
		player, defender, _equipped(player, PathState.BODY, meridian)
	)
	assert_eq(float(damage.get("amount", 0.0)) > 0.0, true, "the strike spent real damage")
	var wounds := _effects_of_kind(damage, BodyWounds.EFFECT_KIND)
	assert_eq(wounds.size() > 0, true, "and it produced a wound — only BodyDamage emits one")
	assert_eq(
		StringName((wounds[0] as Dictionary).get(BodyWounds.KEY_MERIDIAN, &"")),
		meridian,
		"on the meridian the AUTHOR named, so `aim_meridian` was read and not just carried"
	)
	assert_eq(
		float((wounds[0] as Dictionary).get(BodyWounds.KEY_SEVERITY, 0.0)) > 0.0,
		true,
		"with a real severity, so the flat subtraction produced damage at that location"
	)

	# The contrast. Same hero, same seam, same install, a QI technique: no wound at all,
	# which is what makes the two assertions above evidence about the mechanism rather
	# than about the plumbing.
	var qi_damage := _fire_through_production(player, defender, _equipped(player, PathState.QI))
	assert_eq(
		_effects_of_kind(qi_damage, BodyWounds.EFFECT_KIND).is_empty(),
		true,
		"a qi technique through the SAME path produces no meridian damage"
	)
	assert_eq(float(qi_damage.get("amount", 0.0)) > 0.0, true, "it spends its own damage instead")


## **MIND fires in production**, and by the one effect qi and body cannot write: ADR
## 0071 says mind never subtracts health, it erodes the sea, so the assertion is that
## the descriptor's `amount` is `0.0` while a `mind.erosion` effect carrying turbulence
## and clarity was produced AND settled. `CombatEffectApply.apply` runs inside the spine
## at `spine.gd:185`, so the sea's own readings move — the strongest statement available
## that the erosion was produced rather than merely computed.
func test_a_mind_technique_fired_through_production_erodes_the_sea() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted, or nothing below is proven")
	var player := _harness.actor
	var defender := _tri_path_defender()
	var sea: Variant = MindCultivationApi.sea(defender)
	assert_ne(sea, null, "the defender carries a sea to erode")
	var turbulence_before := float((sea as SeaOfConsciousness).turbulence)
	var clarity_before := float((sea as SeaOfConsciousness).clarity)

	var damage := _fire_through_production(player, defender, _equipped(player, PathState.MIND))
	# ADR 0071's own invariant, asserted rather than assumed: mind costs NO health.
	assert_eq(float(damage.get("amount", 0.0)), 0.0, "mind never subtracts health directly")
	var erosions := _effects_of_kind(damage, MindDamage.EFFECT_KIND)
	assert_eq(erosions.size() > 0, true, "and it produced a sea erosion instead")
	var entry := erosions[0] as Dictionary
	assert_eq(
		float(entry.get(MindDamage.KEY_TURBULENCE, 0.0)) > 0.0,
		true,
		"carrying turbulence to add to the sea"
	)
	assert_eq(float(entry.get(MindDamage.KEY_CLARITY, 0.0)) < 0.0, true, "and the clarity it costs")
	# The settlement, read off the sea itself rather than off the payload: `effect_apply`
	# runs last in the spine, so these moved by the hit and by nothing else.
	var sea_after: Variant = MindCultivationApi.sea(defender)
	assert_eq(
		float((sea_after as SeaOfConsciousness).turbulence) > turbulence_before,
		true,
		"and the defender's sea really did go turbulent"
	)
	assert_eq(
		float((sea_after as SeaOfConsciousness).clarity) < clarity_before,
		true,
		"paying clarity for it — so the erosion landed, not merely travelled"
	)


## The routing claim itself, as its own test rather than only as a property of the two
## above: the resolver `TechniqueCasting` is holding IS the mounted root's
## `_resolve_technique_hit`, and calling it through the casting table is what reaches
## `CombatBoot.resolve_hit`.
##
## The first two assertions are the seam. The rest is the CONSEQUENCE, observed and not
## inferred from source: if `_resolve_technique_hit` went back to a bare
## `CombatEngineApi.breakdown`, every number here would still look like damage while the
## mechanism that produced it was the installed qi — which is a different defect from
## either mechanism being wrong, and invisible to every unit case above.
func test_the_cast_seam_is_the_apps_own_resolver_and_reaches_the_per_hit_switch() -> void:
	assert_eq(_harness.boot_error, "", "the shipped app booted")
	var app := _harness.app as ItemWorkbenchApp
	assert_ne(app, null, "the mounted root is the composition root")
	assert_eq(
		app.has_method(&"_resolve_technique_hit"),
		true,
		"the root exposes the resolver it handed `TechniqueCasting`"
	)
	assert_eq(
		TechniqueCasting.has_resolver(),
		true,
		"_bind_technique_seams installed one, so a cast reaches a spine at all"
	)

	var player := _harness.actor
	var defender := _tri_path_defender()
	var meridian := _an_unlocked_meridian(defender)
	# The premise, so the contrast below cannot be vacuous: this is the shipped tri-path
	# hero, and its INSTALLED mechanism really is qi (GAP B's both-paths case).
	assert_eq(
		CombatEngineApi.mechanism_of(player) is QiDamage,
		true,
		"the hero is BOUND to qi, which is the state the per-hit switch exists to override"
	)
	var damage := _fire_through_production(
		player, defender, _equipped(player, PathState.BODY, meridian)
	)
	# The consequence. `QiDamage.resolve` returns `DamageProposal.new(subtotal)` with no
	# effects, so an empty effects list on a cast that spent damage can only mean the
	# body mechanism did not run — which is precisely what the old routing produced.
	assert_eq(
		float(damage.get("amount", 0.0)) > 0.0,
		true,
		"a body cast through the shipped seam spends damage at all"
	)
	assert_eq(
		_effects_of_kind(damage, BodyWounds.EFFECT_KIND).size() > 0,
		true,
		"and it is a BODY damage: qi alone produces no effects on this spine"
	)


## The effects of `kind` in a `CombatOutcome.to_dict()` descriptor. Read through the
## spine's own accessor, so a proposal shape change is visible here rather than as a
## silent empty array.
func _effects_of_kind(damage: Dictionary, kind: StringName) -> Array:
	var out: Array = []
	for entry in damage.get("effects", []) as Array:
		if (
			entry is Dictionary
			and StringName((entry as Dictionary).get(DamageProposal.KIND, &"")) == kind
		):
			out.append(entry)
	return out
