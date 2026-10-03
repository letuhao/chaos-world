extends TestCase

## Which mechanism the composition root binds, and — the reason this suite exists — it
## binds the one whose INPUTS are actually on the actor (ADR 0070, 0071, 0126).
##
## ## What this file is evidence for
##
## `CombatBoot.bind_mechanisms` shipped binding `QiDamage` unconditionally, with a
## docblock arguing that was right: a root-built actor had no `acupoints` component and
## no `sea_of_consciousness` one, so binding either of the other two would have S4 read
## zeros. That argument was TRUE of `ActorFactory.build` and stopped being true of
## `ActorFactory`: BL-0523 put `with_mind_cultivation`'s `attach_sea` into production,
## and `with_body_cultivation` has always called `attach_acupoints`. So body and mind were
## fully built, fully tested, and unreachable — the gap between "three mechanisms exist"
## and "three mechanisms are playable".
##
## ## Every actor here is built the way PRODUCTION builds it
##
## `ActorFactory.build` plus an enrolment verb. No fixture hand-attaches a component, and
## nothing below calls `BodyCultivationApi.attach_acupoints` or
## `MindCultivationApi.attach_sea` directly: `tests/app/test_actor_factory.gd:15-28` names
## exactly why — a fixture that supplies what production withholds hides the hole instead
## of closing it, and that file's comment is about the same class of bug.
##
## ## The negative cases matter as much as the positive ones
##
## The qi default is the only thing standing between a player and an inert fight, so the
## assertions below are as heavy on "does NOT bind BodyDamage without acupoints" as on
## "does bind it with them". A guard that fell through to body on a missing component
## would be invisible to a test that only checked the happy path.

const START_REALM := &"qi_refining"
## The component key `BodyCultivationApi.attach_acupoints` writes and
## `BodyLocation.ACUPOINTS_KEY` reads. Spelled here rather than reached through the module
## because the module's own constant is `_`-private and a private constant is a private
## detail — but this is the one spelling of it, asserted against the real writer below.
const ACUPOINTS_KEY := &"acupoints"

# --- The three paths, reached only through the factory verbs --------------------


## A bare `build` actor: the element provider and nothing else. This is the qi case and
## the shape every npc and mob gets (`ActorFactory.spawn_npc` enrols qi alone).
func _bare() -> Actor:
	return ActorFactory.build(&"bare")


## Enrolled on the body path ONLY, through the verb that also attaches the acupoints.
func _body_only() -> Actor:
	return ActorFactory.with_body_cultivation(ActorFactory.build(&"bruiser"))


## Enrolled on the mind path ONLY. `with_mind_cultivation` reaches `attach_sea` through
## `MindCultivationApi.attach`, which BL-0523 folded in for exactly this reason.
func _mind_only() -> Actor:
	return ActorFactory.with_mind_cultivation(ActorFactory.build(&"seer"))


## Both paths, which is what `ItemWorkbenchApp._build_actor` gives the shipped player:
## three enrolment verbs, body first, mind last.
func _both() -> Actor:
	var actor := _body_only()
	ActorFactory.with_mind_cultivation(actor)
	return actor


## A body-PATH actor with no acupoint set. Constructed rather than enrolled because no
## production verb produces this state — which is precisely why it is worth pinning: it is
## what a save written before the acupoints existed restores to.
func _body_path_without_acupoints() -> Actor:
	var actor := ActorFactory.build(&"hollow")
	actor.set_path(PathState.new(PathState.BODY, START_REALM))
	return actor


## A mind-PATH actor with no sea: the same argument, on the other side.
func _mind_path_without_sea() -> Actor:
	var actor := ActorFactory.build(&"empty")
	actor.set_path(PathState.new(PathState.MIND, START_REALM))
	return actor


func _mechanism_of(actor: Actor) -> String:
	return String(CombatBoot.bind_mechanisms(actor)["mechanism"])


# --- What the factory actually attaches ---------------------------------------


## The premise of the whole file, asserted rather than assumed. If an enrolment verb
## stopped mounting its component, every test below would pass for the WRONG reason — they
## would all be reading "no inputs, therefore qi" — so this pins the inputs themselves.
func test_the_enrolment_verbs_are_what_mount_the_two_components() -> void:
	assert_ne(
		_body_only().component(ACUPOINTS_KEY),
		null,
		"`with_body_cultivation` mounts the acupoint set BodyDamage reads"
	)
	assert_ne(
		_mind_only().component(MindCultivationApi.SEA_COMPONENT),
		null,
		"`with_mind_cultivation` mounts the sea MindDamage reads"
	)
	assert_eq(_bare().component(ACUPOINTS_KEY), null, "and a bare factory actor has neither")
	assert_eq(
		_bare().component(MindCultivationApi.SEA_COMPONENT),
		null,
		"which is why the qi default is the right answer for one"
	)


# --- The rule: one path with its inputs gets its mechanism ----------------------


## Body: an actor on the body path WITH acupoints fights through `BodyDamage`. This is
## the assertion the whole change exists for — before it, this actor got `QiDamage` and a
## body technique hit for an elemental share instead of at a meridian.
func test_a_body_actor_with_acupoints_gets_the_body_mechanism() -> void:
	var actor := _body_only()
	var report := CombatBoot.bind_mechanisms(actor)
	assert_eq(String(report["mechanism"]), "BodyDamage", "the body path fights through body")
	assert_eq(bool(report["ok"]), true, "and the binding succeeded")
	assert_eq(CombatEngineApi.has_mechanism(actor), true, "so the slot really carries one")
	assert_eq(
		CombatEngineApi.mechanism_of(actor) is BodyDamage,
		true,
		"and it is the concrete body mechanism, not the name alone"
	)


## Mind: the same, on the other path. `MindDamage` is the one mechanism whose proposal
## carries `amount == 0.0`, so an actor that was silently on qi was eroding nothing at
## all — this is the assertion that the sea is reachable from a fight.
func test_a_mind_actor_with_a_sea_gets_the_mind_mechanism() -> void:
	var actor := _mind_only()
	var report := CombatBoot.bind_mechanisms(actor)
	assert_eq(String(report["mechanism"]), "MindDamage", "the mind path fights through mind")
	assert_eq(bool(report["ok"]), true, "and the binding succeeded")
	assert_eq(
		CombatEngineApi.mechanism_of(actor) is MindDamage,
		true,
		"so the slot carries the concrete mind mechanism"
	)


## The qi fallback, unchanged, for an actor that started no path. `CombatEngineApi
## .mechanism_of` ASSERTS on an unbound actor and `CombatSpine.resolve_hit` reads it, so
## "some mechanism is always bound" is the property that keeps the spine from killing the
## process on a mob.
func test_an_actor_with_no_path_keeps_the_qi_default() -> void:
	assert_eq(_mechanism_of(_bare()), "QiDamage", "a bare factory actor fights through qi")


# --- The rule's negative cases: inputs missing, path present -------------------


## The guard that is the reason this file may bind body at all. A path flag without the
## acupoint set is the state the old docblock described, and it must fall back to qi
## rather than bind a mechanism whose `BodyLocation` lookup answers nothing — which would
## make every body hit an ungated subtraction rather than a located one.
func test_a_body_path_without_acupoints_keeps_the_qi_default() -> void:
	var actor := _body_path_without_acupoints()
	assert_eq(actor.path(PathState.BODY) != null, true, "the path really is enrolled")
	assert_eq(actor.component(ACUPOINTS_KEY), null, "and the acupoints really are absent")
	assert_eq(_mechanism_of(actor), "QiDamage", "so qi is the only defensible binding")


## The same guard on the mind side. A sea is `MindDamage`'s DENOMINATOR; without one the
## erosion reads `0.0` and the fight is a no-op that still looks like damage resolution.
func test_a_mind_path_without_a_sea_keeps_the_qi_default() -> void:
	var actor := _mind_path_without_sea()
	assert_eq(actor.path(PathState.MIND) != null, true, "the path really is enrolled")
	assert_eq(
		actor.component(MindCultivationApi.SEA_COMPONENT), null, "and the sea really is absent"
	)
	assert_eq(_mechanism_of(actor), "QiDamage", "so qi is the only defensible binding")


## Neither half alone is enough, in EITHER direction, so the rule cannot be satisfied by a
## component check that ignores the path or a path check that ignores the component. This
## is the half of the rule a future edit is most likely to drop, because dropping it
## makes a save-load onto a never-enrolled actor bind the wrong mechanism.
func test_the_path_flag_alone_never_selects_a_mechanism() -> void:
	# Both paths enrolled, but by hand, with neither component mounted.
	var hollow := ActorFactory.build(&"hollow_dual")
	hollow.set_path(PathState.new(PathState.BODY, START_REALM))
	hollow.set_path(PathState.new(PathState.MIND, START_REALM))
	assert_eq(
		_mechanism_of(hollow),
		"QiDamage",
		"two enrolled paths and no inputs is still the qi default"
	)


# --- The both-paths case, decided rather than assumed ---------------------------


## The shipped player has THREE paths (`ItemWorkbenchApp._build_actor:238-243`), so this
## is the case production hits most and it must not be a coin flip. `MechanismSlot` holds
## ONE mechanism, so the root must pick, and it picks qi: the one mechanism whose input
## (the element provider) every root-built actor has, and one that can never be the wrong
## answer for an actor whose `ATTACK_SPIRITUAL` was never built. Asserted explicitly so a
## later "body wins" edit has to change this line and say why.
func test_an_actor_on_both_paths_keeps_the_qi_default() -> void:
	var actor := _both()
	assert_ne(actor.component(ACUPOINTS_KEY), null, "and it really does carry BOTH sets")
	assert_ne(actor.component(MindCultivationApi.SEA_COMPONENT), null, "including the sea")
	assert_eq(
		_mechanism_of(actor),
		"QiDamage",
		"an ambiguous dual-cultivator is the qi fallback, not an arbitrary pick"
	)


## A body-and-mind actor is ambiguous, so it is qi — but a body-and-QI actor is not. The
## qi path carries no component the mechanism reads, so it cannot make an actor ambiguous,
## and a body cultivator who also trained qi must still get the located, refusable strike
## the body path exists for. If this ever fails, the rule has started counting paths
## rather than counting MECHANISM INPUTS.
func test_a_body_and_qi_actor_is_still_the_body_mechanism() -> void:
	var actor := _body_only()
	ActorFactory.with_qi_cultivation(actor)
	assert_eq(
		_mechanism_of(actor),
		"BodyDamage",
		"the qi path is the fallback, not a vote that makes a body actor ambiguous"
	)


# --- Idempotence and the report ------------------------------------------------


## Re-binding is a re-ATTACHMENT, not an accumulation, and it is how a save-load hands an
## actor the mechanism its new path implies. Two calls, one mechanism, and the second
## report says it found the first — which is what makes "call this again after a load"
## the documented usage rather than a hope.
func test_binding_twice_is_idempotent_for_every_path() -> void:
	for pair in [
		[_bare(), "QiDamage"],
		[_body_only(), "BodyDamage"],
		[_mind_only(), "MindDamage"],
		[_both(), "QiDamage"],
	]:
		var actor: Actor = pair[0]
		var first := CombatBoot.bind_mechanisms(actor)
		assert_eq(bool(first["already_bound"]), false, "a first binding found nothing")
		var second := CombatBoot.bind_mechanisms(actor)
		assert_eq(String(second["mechanism"]), String(pair[1]), "and the second agrees")
		assert_eq(bool(second["already_bound"]), true, "and reports the re-attach")
		assert_eq(
			CombatEngineApi.has_mechanism(actor), true, "with exactly one mechanism still bound"
		)


## A save-load is the one sequence where the answer legitimately CHANGES: an actor that
## could not have body inputs when it was first bound gains them, and the documented
## save-load path is the second `bind_mechanisms` call. Before this change both calls
## answered `QiDamage` and the load silently left the actor on the wrong mechanism.
func test_binding_again_after_an_enrolment_switches_the_mechanism() -> void:
	var actor := _bare()
	assert_eq(_mechanism_of(actor), "QiDamage", "a bare actor starts on qi")
	ActorFactory.with_body_cultivation(actor)
	assert_eq(
		_mechanism_of(actor), "BodyDamage", "and gains the body mechanism once its inputs arrive"
	)


## The null guard is the one refusal here and it names itself, because
## `MechanismSlot.of` would otherwise raise three stages later on a null actor.
func test_a_null_actor_is_refused_by_name() -> void:
	var report := CombatBoot.bind_mechanisms(null)
	assert_eq(bool(report["ok"]), false, "a null actor binds nothing")
	assert_eq(String(report["reason"]), "no_actor", "and says so rather than throwing")
