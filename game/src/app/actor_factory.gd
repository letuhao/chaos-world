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


## The seam that makes a newborn a whole actor.
##
## `FertilityApi.resolve_offspring` cannot call `build()` — `app/` is private to every
## module — so it mints through a Callable installed here, the same shape as
## `NpcApi.set_minter` / `DomainSpawner.set_minter`. Without it a child is a bare
## `Actor.new()` with **no health pool**: it cannot be damaged or healed, and no existing
## test noticed because they all built children the same way.
##
## Installed once, at load, from the composition root — the only layer allowed to name
## `app/`. The Callable is idempotent and cheap, so re-running it is free.
static func install_fertility_actor_builder() -> void:
	FertilityApi.set_actor_builder(_build_fertility_child)


static func _build_fertility_child(actor_id: StringName, base: Dictionary) -> Actor:
	return build(actor_id, base)


## Enrol an actor in the body path and give it an acupoint layout. The only
## place that knows the attach order (ADR 0002, ADR 0012/0023).
static func with_body_cultivation(actor: Actor, rank_id: StringName = &"qi_refining") -> Actor:
	actor.set_path(PathState.new(BodyPath.PATH_ID, rank_id))
	return _attach_body(actor)


## Enrol the actor on the qi path, in the same shape as the body enrolment above.
##
## Attaching is not enrolling: `QiCultivationApi.attach` installs the dantian and
## the provider but registers no path, and `panel_state` returns `{}` when
## `actor.path(QiPath.PATH_ID)` is null. Without this, `build_npc`'s enrolment
## makes a rival cultivator a rival *cultivator* while the player is enrolled on
## body alone, and the qi screen mounts bound to an actor it cannot read.
static func with_qi_cultivation(actor: Actor, rank_id: StringName = &"qi_refining") -> Actor:
	actor.set_path(PathState.new(QiPath.PATH_ID, rank_id))
	return _attach_qi(actor)


## Enrol the actor on the mind path. Same reason as the qi enrolment above, and
## `MindCultivationApi` was never attached to the player at all.
static func with_mind_cultivation(actor: Actor, rank_id: StringName = &"qi_refining") -> Actor:
	actor.set_path(PathState.new(MindPath.PATH_ID, rank_id))
	return _attach_mind(actor)


## ## Why enrolling and attaching are two verbs and not one
##
## **An enrolment OVERWRITES the path, and on a restored actor the path is the save.**
## `set_path` replaces `paths[path_id]` outright, so calling `with_mind_cultivation`
## over a body built by `Actor.from_dict` replaces a restored `rank_id`, `stage` and
## `progress` with a fresh `qi_refining`/0/0.0 — and `MindTraining.synchronize` then
## reads THAT rank and shrinks the sea back to the R1 seed. So a restore that reused
## the enrolment verbs reset the entire cultivation loop on every boot, which is the
## very gap the save exists to close: the write half would land and the read half
## would erase it again.
##
## The attach half is therefore its own private verb, shared by the fresh boot and
## the restore, so "what mounting the body path means" is written once. Every part of
## it already reads the actor's CURRENT rank and returns early when there is no path —
## `attach_acupoints` restores the saved layout rather than rerolling, and both
## `synchronize` verbs reconcile to `actor.path(...)` — so attaching over a restored
## path is safe. `set_path` is the only destructive step, and it is the enrolment's.
static func _attach_body(actor: Actor) -> Actor:
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	BodyTraining.synchronize(actor)
	_refresh_element_realm(actor)
	return actor


static func _attach_qi(actor: Actor) -> Actor:
	QiCultivationApi.attach(actor)
	QiTraining.synchronize(actor)
	_refresh_element_realm(actor)
	return actor


static func _attach_mind(actor: Actor) -> Actor:
	MindCultivationApi.attach(actor)
	MindTraining.synchronize(actor)
	_refresh_element_realm(actor)
	return actor


## Re-mount the cultivation modules a RESTORED actor needs — and only the ones its own
## payload carried. The second verb a restore needs, beside `_attach_*` above.
##
## ## Why the gate reads the actor's own paths
##
## **An attach is a grant, so an ungated one hands out what the save never earned.**
## `MindCultivationApi.attach` calls `attach_sea`, which mints a `SeaOfConsciousness`
## when the component is absent, and the qi attach installs a dantian on the same
## terms. Running either over a payload with no such path therefore gives a body a sea
## or a dantian regardless of enrolment — BL-0523, which sat behind 10,186 green
## assertions precisely because it looked like ordinary wiring. `core` cannot be the
## place to prevent it: `Actor.from_dict` restores components and never a `StatProvider`,
## and `core` may not name `modules` at all (`tools arch`), so the composition root is
## the only layer that can re-attach *and* the only one that may know a provider exists.
##
## The gate reads `actor.path(...)` rather than re-parsing the payload dictionary, so
## it cannot disagree with what `Actor.from_dict` actually restored — one source of
## truth for "is this body on this path", and an absent path is what a payload without
## one means.
##
## Every `_attach_*` below refreshes the element realm itself, and it is idempotent
## (`apply_realm_modifiers` strips before it applies), so a caller may refresh once more
## afterwards without stacking a second modifier.
static func restore_cultivation(actor: Actor) -> Actor:
	if actor == null:
		return null
	if actor.path(BodyPath.PATH_ID) != null:
		_attach_body(actor)
	if actor.path(QiPath.PATH_ID) != null:
		_attach_qi(actor)
	if actor.path(MindPath.PATH_ID) != null:
		_attach_mind(actor)
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


## Mint one inhabitant of a DOMAIN (ADR 0074) — a mob, a mini-boss, a boss, an npc or a
## rival cultivator.
##
## `DomainSpawner.set_minter(...)` wires this in, exactly as `NpcApi.set_minter` wires
## `spawn_npc`: the domain module names no concrete actor type, so `app/` is the only
## layer that resolves a def into a living actor (dependency inversion, ADR 0002).
##
## **Every inhabitant of this game is an `Actor`** — the project's defining constraint —
## so this builds through `build()` and gets the SAME provider spine the player gets. A
## mini-boss and a mob differ by magnitude and by tag, never by which script they extend.
##
## The signature is `(inhabitant_id, base)` because that is exactly what
## `domain_spawner.gd:220` passes. The cultivation path is attached by `DomainSpawner`
## itself when the def declares it cultivates: enrolling every creature on a path would
## make a rat a qi cultivator, so "does this creature cultivate" is an AUTHORED decision
## and never a default.
static func spawn_inhabitant(
	inhabitant_id: StringName = &"inhabitant", base: Dictionary = {}
) -> Actor:
	var actor := build(inhabitant_id, base)
	# Social state on every inhabitant, so an npc can hold a bond and be the subject of
	# one exactly as the player can (ADR 0091).
	SocialApi.attach(actor)
	# LAST, so a realm-bearing def has already been enrolled by the spawner and
	# `apply_realm_modifiers` has a realm to read.
	_refresh_element_realm(actor)
	return actor
