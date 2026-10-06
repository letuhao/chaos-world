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
	# Nation is the tier ABOVE both (ADR 0083): a polity outlives the people who hold
	# its offices, and it is the one tier whose `attach` also mints a state component —
	# `NationApi._mirror` writes `NationStateComponent` onto the actor — so an actor
	# without it has no board for `institution_resolver.gd:179-180` to gate the period
	# settler on, and that gate reads a `founded` that `attach` cannot answer. Same
	# reasoning as the two above, for the same reason it is safe: **attaching is not
	# living under a polity.** It normalizes an empty ledger, mirrors it and rebuilds the
	# bounded PERCENT recognition — and recognition from an empty board is zero, so
	# wiring it cannot hand a new actor an edge. Only `found` / `join` puts a hero UNDER
	# a nation, exactly as only `join` / `found` puts one under a sect or a clan.
	#
	# It was missing while `SectApi.attach` and `ClanApi.attach` were both here, so the
	# nation screen rendered "You live under no nation" for every player and the nation's
	# period settler was gated behind an always-false check.
	NationApi.attach(actor)
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
	_attach_founding_fund(actor)
	return actor


## ## The sect founding fund: a pool mounted for EVERY actor, and a purse bridge
##
## ## Why the pool is mounted here and not by the verb that spends it
##
## `SectFounding.funds` reads `actor.resource(&"sect_founding_funds")` and returns
## **0.0 for an actor with no such pool** — which is not an error, it is the ordinary
## answer. So the pool has to EXIST on the actor or `SectApi.found` can never succeed:
## `found` compares `funds(actor)` against the authored `founding_cost.outstanding`
## (900 for `iron_vine`, 400 for `jade_court`) and refuses `founding_cost_unmet` with
## nothing written. Before this line the pool was created in exactly one place — a test
## helper — so `found` was dead in play and only green in the suite. A pool the player
## cannot fill is a price nobody can pay, and BL-0174 prices an institution's existence
## ON PURPOSE, so the price being unreachable deleted the feature rather than
## debalancing it.
##
## ## Why it is EMPTY on mount, and the bridge is a separate verb
##
## `ResourcePool.new(id, 0.0)` is mounted deliberately at **zero**: `ResourcePool._init`
## sets `current = maximum`, so a non-zero maximum here would GRANT the authored price
## to every hero in the game, which is exactly the free founding BL-0174 rules out.
## Mounting at zero makes "you have funded nothing" a real, readable zero instead of a
## missing key — ADR 0058's "no X yet is a value, not a hole", applied to money.
##
## ## Why the bridge is NOT done here
##
## The authored cost is `{"currency": "silver", ...}` and the game's only priced money
## is `EconomyApi`'s numéraire (`curr_spirit_coin`, priced at exactly 1 — ADR 0094), which
## is an INVENTORY ITEM and not a `ResourcePool`. Those are two currencies, and nothing
## in `sect` may convert between them: `sect_founding.gd:26-30` says the module "never
## charges an inventory and never settles a debt... Anything past that price belongs to
## the economy verb that will own it", and `sect` declares no `items` or `economy`
## dependency on purpose. So the conversion is [method fund_sect_from_purse] below —
## an EXPLICIT, caller-driven act, in the one layer that is allowed to know both
## vocabularies (ADR 0002, dependency inversion). Nothing here ticks, so it cannot
## become a faucet: a player converts their own coins, and the sect's own price is what
## they convert.
##
## Idempotent in the same way every other attach here is: it mounts the pool only when
## the actor has none, so a restored actor keeps its saved balance rather than having it
## overwritten by a fresh zero.
static func _attach_founding_fund(actor: Actor) -> void:
	if actor == null or actor.resource(SectFounding.FUNDING_POOL) != null:
		return
	actor.add_resource(ResourcePool.new(SectFounding.FUNDING_POOL, 0.0))


## Move `coins` worth of the economy's numéraire into the sect founding fund, and
## report what actually landed.
##
## ## This is the acquisition path BL-0174's price was waiting for
##
## Returns `{ok, moved, purse, funds, reason}`. It is a ONE-WAY conversion at the
## numéraire's own authored price of exactly 1 (`EconomyValuation.NUMERAIRE_WORTH`), so
## a coin in is one unit of founding fund out and no exchange rate is invented here —
## the rate is the economy's, and `EconomyApi.validate` asserts the numéraire prices at 1
## rather than this file restating it.
##
## ## It is ATOMIC, and that is a property of control flow rather than a discipline
##
## The purse is measured and the fund is grown FIRST; only a non-zero `moved` draws the
## coins. So a refusal — no actor, no coin, nothing priced — leaves BOTH ledgers exactly
## as found, the same guarantee every `SectApi` refusal makes (ADR 0044). A partial
## conversion cannot leave the two ledgers disagreeing about what was paid.
##
## ## Why it is a public verb on the factory rather than an `attach` side effect
##
## An `attach` that CONVERTED money would make every factory-built actor — every npc,
## every mob, every test — spend its purse into a pool nobody can read. A conversion is
## an act with a cost, so it stays an act a caller asks for.
##
## ## AND IT IS REACHABLE: the audit found it with ZERO callers
##
## An independent re-audit measured this verb shipping with no production call path at
## all, which is what left founding doubly unwired: `SectApi.found` had no caller either,
## so a player who could afford a sect could not found one at any price. A pool the
## player cannot fill is a price nobody can pay, and BL-0174 prices an institution's
## existence ON PURPOSE, so an unreachable price deleted the feature rather than
## debalancing it.
static func fund_sect_from_purse(actor: Actor, coins: int) -> Dictionary:
	if actor == null:
		return {"ok": false, "moved": 0, "purse": 0, "funds": 0.0, "reason": "no_actor"}
	if coins <= 0:
		return {
			"ok": false,
			"moved": 0,
			"purse": EconomyApi.purse(actor),
			"funds": SectFounding.funds(actor),
			"reason": "no_coins",
		}
	_attach_founding_fund(actor)
	var purse := EconomyApi.purse(actor)
	var moved := mini(coins, purse)
	if moved <= 0:
		return {
			"ok": false,
			"moved": 0,
			"purse": purse,
			"funds": SectFounding.funds(actor),
			"reason": "insufficient_funds",
		}
	var fund := actor.resource(SectFounding.FUNDING_POOL) as ResourcePool
	# `ResourcePool.change` clamps to `maximum`, and the pool is mounted at 0.0, so the
	# cap is lifted to the new balance before the change rather than after: growing the
	# pool first and charging second means the fund can never be silently truncated by a
	# cap nobody authored.
	#
	# The coins are SPENT here, by CONSUMING them — not by calling `EconomyApi.trade`
	# with a null counterparty and discarding the result, which is what this did.
	# `EconomyExchange.exchange` refuses a null `to_actor`
	# (`economy_exchange.gd:47-48`) and refuses self-trade outright as a money printer
	# (`:49-51`), so that call ALWAYS failed while the verb went on reporting
	# `ok: true, moved: 900`: the founding pool grew, the purse never shrank, and the
	# docstring promised a conversion that was atomic.
	#
	# `consume_item` is all-or-nothing, so the debit either happens in full or not at
	# all — which is what "atomic" has to mean for a conversion between two resources.
	# The pool is credited only after it, so a short purse leaves both sides untouched.
	if not ItemsApi.consume_item(actor, EconomyValuation.numeraire_id(), moved):
		return {
			"ok": false,
			"moved": 0,
			"purse": EconomyApi.purse(actor),
			"funds": SectFounding.funds(actor),
			"reason": "purse_short",
		}
	fund.set_maximum(fund.maximum + float(moved))
	fund.change(float(moved))
	return {
		"ok": true,
		"moved": moved,
		"purse": EconomyApi.purse(actor),
		"funds": SectFounding.funds(actor),
		"reason": "",
	}


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


## The founding-fund conversion, as a `Callable`, for a screen that may not name `app/`.
##
## ## Why this exists rather than a screen calling the verb itself
##
## `SectScreen` is a pure consumer and `app/` is a `PRIVATE_UNIT`, so a screen can
## neither reach `ActorFactory` nor convert between the economy's numéraire and
## `sect`'s own funding pool — the two modules each deliberately refuse to know the
## other's currency. Handing the FUNCTION OBJECT over is ADR 0143's bridge and the same
## shape `install_fertility_actor_builder` uses, so the conversion keeps exactly one
## implementation and a screen can only ever reach the one that pays the authored price.
##
## ## It is a plain accessor, not a stored seam, and that is deliberate
##
## A `static var` holding a `Callable` would be process-wide state in a factory that is
## otherwise pure, would be counted as state by `app_state_warnings`, and would make
## "is this bridge installed?" a second question the screen had to ask. Returning it on
## demand means there is nothing to install, nothing to go stale, and nothing to leak
## across a save restore.
static func sect_funding_bridge() -> Callable:
	return Callable(ActorFactory, "fund_sect_from_purse")


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
	# ADR 0888: the tail every restore funnels through re-derives the BUILD — realm
	# multiplier, element halves and the aptitude points — so no mount path can forget
	# one of the three. Before this, nothing on the restore path called
	# `RealmScaling.apply` at all: a loaded body read the eight realm-scaled stats at R1
	# strength and folded its MAGNITUDE aptitude edges at ladder 1.0 until its next
	# breakthrough.
	refresh_build(actor)
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


## Re-derive everything a body's BUILD owns, in one verb (ADR 0888): the realm multiplier
## on the shared stats — which is also the only push of the aptitude LADDER — the element
## halves, and the aptitude points themselves.
##
## This is what a restore was missing. `restore_cultivation` re-mounted providers and the
## element halves, but nothing on the load path ever called `RealmScaling.apply`, so a
## loaded body read the eight realm-scaled stats at R1 strength and folded its MAGNITUDE
## aptitude edges at ladder 1.0 from the same omission. Idempotent by construction:
## `RealmScaling.apply` strips its own source before writing, `_refresh_element_realm`
## does the same for the element source, and `AptitudeGrant.apply` REPLACES the store.
static func refresh_build(actor: Actor) -> Actor:
	if actor == null:
		return null
	RealmScaling.apply(actor)
	_refresh_element_realm(actor)
	var grant := AptitudeGrant.shipped()
	if grant != null:
		grant.apply(actor)
	return actor


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
	# Through the shared attach verb, never a bare `QiCultivationApi.attach`. `attach`
	# mints the reservoir at a flat 100.0 and the dantian at the actor's (unset)
	# base capacity, so calling it alone left every npc at seed defaults: an EMPTY
	# meridian network, a `lower` tier and a pool ceiling nothing to do with its realm.
	# `_attach_qi` is where `QiTraining.synchronize` reconciles all four to the realm —
	# BL-0696. It also refreshes the element realm LAST, which is why there is no
	# `_refresh_element_realm` call here any more: without that refresh a boss born at
	# Foundation Establishment keeps its R1 element multiplier, and the elemental term —
	# now the status potency term too (ADR 0088) — is realm-FLAT on exactly the units
	# that were authored high.
	_attach_qi(actor)
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
## `domain_spawner.gd:220` passes, and nothing else: this is a CONSTRUCTOR and it enrols
## nobody. `DomainSpawner` mints first and only then asks `def.cultivates`, so a species
## that cultivates is enrolled by [method enrol_inhabitant_qi] immediately afterwards, over
## the actor this returned — attaching here unconditionally would make a rat a qi
## cultivator, and "does this creature cultivate" stays an AUTHORED decision on the def.
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


## Enrol an ALREADY-MINTED domain inhabitant on the qi path at `realm_id`, and mount the rig
## behind the path.
##
## ## Why this is a second public verb and not a branch inside `spawn_inhabitant`
## ## A path and the machinery that mounts it are two different questions, asked at two
## different moments: `DomainSpawner` has to mint before it can read `def.cultivates`, and
## only then does it know a realm. `spawn_inhabitant` cannot attach on its own without
## either attaching to every species on earth or attaching before any path exists — which is
## nothing `QiTraining.synchronize` can reconcile. So the constructor stays a constructor
## and this answers the second question.
##
## ## Why the mount is `_attach_qi` and not a bare `QiCultivationApi.attach`
## `attach` mints the reservoir at a flat 100.0 and the dantian at the actor's unset base
## capacity, so calling it alone leaves a rival with an EMPTY meridian network, a `lower`
## tier and a pool ceiling unrelated to its realm — BL-0753's sibling BL-0696, which was
## the same bug on `spawn_npc`. `_attach_qi` is where `QiTraining.synchronize` reconciles
## all four to the realm, and it refreshes the element realm LAST so a boss born at
## Foundation Establishment keeps neither its R1 element multiplier nor the elemental term.
##
## Exactly one attach per actor: `spawn` calls the enroller once per instance and this is
## the only caller of the seam. That matters because `QiCultivationApi.attach` appends a
## `QiProvider` UNGUARDED (`api.gd:32`) — the one step that is NOT idempotent, where
## `QiTraining.synchronize` and `attach_dantian` both are.
static func enrol_inhabitant_qi(actor: Actor, realm_id: StringName) -> void:
	if actor == null or realm_id.is_empty():
		return
	actor.set_path(PathState.new(QiPath.PATH_ID, realm_id))
	_attach_qi(actor)
