class_name ActorFactory
extends RefCounted

## Composition root for actors: the only place that knows concrete module providers
## and registers them with an actor (ADR 0002, dependency inversion).


static func build(id: StringName, base: Dictionary = {}) -> Actor:
	var actor := Actor.new(id, base)
	# Core health and stamina pools exist for every actor; capacities follow the
	# derived stats, so an item that raises max_health never refills (ADR 0025).
	actor.attach_core_resources()
	# An actor is born into no sect, but the ledger is written here anyway so the
	# claim is the same shape for a fresh actor and for a restored save: one attach
	# in the composition root, and every later verb has a ledger to read. It
	# projects nothing at all, because an institution grants recognition and access
	# and never power (ADR 0084) — so wiring it cannot hand a new actor an edge.
	SectApi.attach(actor)
	# Clan is the lineage layer above bloodline (ADR 0064). Every actor belongs to no
	# clan — that is the normal state — but the ledger is written here anyway so the
	# claim is the same shape for a fresh actor and for a restored save: one attach in
	# the composition root, and every later verb has a ledger to read. It projects no
	# stat at all, because a clan grants recognition and never power — so wiring it
	# cannot hand a new actor an edge.
	ClanApi.attach(actor)
	# Elements, and WHY here rather than beside the items attach in the player root:
	# `element_power_<e>` is the magnitude channel ADR 0088 makes status potency read,
	# and ADR 0069 names it the realm-INVARIANT elemental term. A provider that only
	# the playable slice mounts is a provider no other actor has, so `element_power_<e>`
	# reads 0.0 for an npc, a mob and every unit a test builds through the factory —
	# and every status lands on `status_potency_floor` instead of on the actor's actual
	# element. That is the vacuous-defect class ADR 0088 measured as "live in authored
	# content and dead in play", one level up from the seam it left unwired.
	#
	# It attaches LAST on purpose: `RealmScaling.highest_realm` reads `actor.paths`, and
	# `build` is the state BEFORE any path is enrolled. So on a bare factory actor this
	# writes the provider and no realm multiplier, which is exactly the fail-safe
	# `apply_realm_modifiers` documents — and `with_body_cultivation` /
	# `with_qi_cultivation` / `with_mind_cultivation` / `spawn_npc` each call
	# `ElementsApi.apply_realm_modifiers` afterwards to pick the realm up. Attaching
	# twice would stack two providers (`ActorStats.add_provider` appends unguarded,
	# ADR 0069), which is why the enrolment verbs refresh and never re-attach.
	ElementsApi.attach(actor)
	# High-tier readouts, for the same reason the element provider is attached
	# here rather than in a cultivation enrolment: a provider mounted only by the
	# paths that reach R19+ is a provider no other actor has, so `inside_world_stability`,
	# `inside_world_size`, `world_stability` and `ascension_complete` read absent
	# instead of 0 on every npc, mob and factory-built test actor. Registering them
	# once, for every actor, is what makes "no inside world yet" a value rather than
	# a missing key (ADR 0058).
	#
	# `ActorStats.add_provider` appends unguarded, so this attaches here and is
	# never repeated in the enrolment verbs — a second copy would double every
	# contribution.
	actor.stats.add_provider(InsideWorldProvider.new())
	actor.stats.add_provider(WorldCreationProvider.new())
	actor.stats.add_provider(AscensionProvider.new())
	return actor


static func with_dual_cultivation(actor: Actor) -> Actor:
	DualCultivationApi.attach(actor)
	return actor


## Attach the fertility module. Reproduction parameters live on the actor's RACE now
## (ADR 0062/0108), so there is no second `species` argument to thread — a body plan is read
## at birth from `RaceApi`, and an actor with none falls back to the published default.
static func with_fertility(actor: Actor) -> Actor:
	FertilityApi.attach(actor)
	return actor


## Enrol an actor in the body path and give it an acupoint layout. The only
## place that knows the attach order (ADR 0002, ADR 0012/0023).
static func with_body_cultivation(actor: Actor, rank_id: StringName = &"qi_refining") -> Actor:
	actor.set_path(PathState.new(BodyPath.PATH_ID, rank_id))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	BodyTraining.synchronize(actor)
	_refresh_element_realm(actor)
	return actor


## Enrol the actor on the qi path, in the same shape as the body enrolment above.
##
## Attaching is not enrolling: `QiCultivationApi.attach` installs the dantian and
## the provider but registers no path, and `panel_state` returns `{}` when
## `actor.path(QiPath.PATH_ID)` is null. Without this, `build_npc`'s enrolment
## makes a rival cultivator a rival *cultivator* while the player is enrolled on
## body alone, and the qi screen mounts bound to an actor it cannot read.
static func with_qi_cultivation(actor: Actor, rank_id: StringName = &"qi_refining") -> Actor:
	actor.set_path(PathState.new(QiPath.PATH_ID, rank_id))
	QiCultivationApi.attach(actor)
	QiTraining.synchronize(actor)
	_refresh_element_realm(actor)
	return actor


## Enrol the actor on the mind path. Same reason as the qi enrolment above, and
## `MindCultivationApi` was never attached to the player at all.
static func with_mind_cultivation(actor: Actor, rank_id: StringName = &"qi_refining") -> Actor:
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	MindCultivationApi.attach(actor)
	MindTraining.synchronize(actor)
	_refresh_element_realm(actor)
	return actor


## Re-write the element provider's realm multiplier after a path enrolment, and NOTHING
## else on the stat stack.
##
## `build` attaches the element provider before any path exists, so the realm half was
## deliberately not written — `RealmScaling.highest_realm` has nothing to read yet. Every
## enrolment verb above therefore calls this. It is `apply_realm_modifiers`, NOT a second
## `attach`: `ActorStats.add_provider` appends unguarded, so re-attaching would stack two
## providers and ADR 0069's realm-invariant fraction would be computed against two
## baselines (its own documented rule is "attach once, then `apply_realm_modifiers`").
##
## Split out as one private verb rather than repeated in four callers: a refresh that
## only one enrolment remembers is a realm-invariance bug that hides in the paths a
## player never walks.
static func _refresh_element_realm(actor: Actor) -> void:
	ElementsApi.apply_realm_modifiers(actor)


## Mint an npc of any role — mob, miniboss, boss, npc or rival cultivator — as an
## `Actor` (ADR 0074). The second constructor this factory publishes, and the reason
## `build` above did not have to grow a second shape for "a thing in the world".
##
## **The role is a tag, never a class.** It is stamped onto `Actor.tags` and read by
## content; nothing branches on it here or in damage resolution, because three
## mechanisms that each branch on a role are three mechanisms that disagree.
##
## `npc_def` is the authored individual: it supplies the realm, the base build, the
## faction and the display name. Passing null mints a plain actor at the supplied realm.
## This method deliberately does not name `WorldInhabitantDef`, so the `app` layer stays
## the only place that resolves a species into an individual.
##
## `NpcApi.set_minter(this callable)` wires this in; the npc module never names this
## factory, which is the inversion the module boundary depends on (ADR 0002).
static func spawn_npc(
	npc_def: NpcDef = null,
	role: StringName = &"npc",
	rank_id: StringName = &"qi_refining",
	base: Dictionary = {}
) -> Actor:
	var actor_base := base
	if actor_base.is_empty() and npc_def != null:
		actor_base = npc_def.base
	var actor_id := &"npc"
	if npc_def != null:
		actor_id = StringName("npc_%s" % String(npc_def.npc_id))
	var actor := build(actor_id, actor_base)
	actor.tags.append(role)
	if npc_def != null:
		actor.display_name = npc_def.display_name
		actor.faction = npc_def.faction
		for tag_id in npc_def.tags:
			actor.tags.append(tag_id)
	# Every inhabitant carries social state, so an npc can hold a bond and be the subject
	# of one exactly as the player can (ADR 0091).
	SocialApi.attach(actor)
	# An npc that cultivates is enrolled on a path exactly as the player is, so a rival
	# cultivator is a rival *cultivator* rather than a mob with a name and a realm.
	var realm := rank_id
	if npc_def != null and npc_def.realm_id != &"":
		realm = npc_def.realm_id
	actor.set_path(PathState.new(QiPath.PATH_ID, realm))
	QiCultivationApi.attach(actor)
	# LAST, because the enrolment above is what gives `apply_realm_modifiers` a realm to
	# read. Without it a boss born at Foundation Establishment keeps its R1 element
	# multiplier, and the elemental term — now the status potency term too (ADR 0088) —
	# is realm-FLAT on exactly the units that were authored high.
	_refresh_element_realm(actor)
	return actor
