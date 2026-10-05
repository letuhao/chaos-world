class_name DomainWorldBoot
extends DomainWards

## ## Why this is not code in `domain_boot.gd`
##
## Extracted because `domain_boot.gd` passed the thousand-line ceiling. The cut is
## the section that is about the WORLD rather than about the run: realizing a run as
## a walkable `Node2D`, registering the hostiles it holds, releasing it, and the
## OPTIONAL observer seam that lets the composition root stand that world up under
## whichever screen it is showing.
##
## Every one of those verbs belongs to a different question from the run itself —
## "which map is active and what is standing in it" is `DomainBoot`'s, "is a floor
## standing under that parent right now" is this file's — and every one of them is
## called by a caller that may never ask the other. Splitting on that seam means a
## headless probe drives `enter_domain` with no world at all and pays nothing for
## this file, and a screen asks only the tree questions.
##
## ## INHERITANCE, and that is the whole reason it works
##
## `DomainBoot` extends this class, so every name below is reached by its UNCHANGED
## spelling: `DomainBoot.realize_world`, `DomainBoot.register_targets`,
## `DomainBoot.release_world`, `DomainBoot.world_realized`, `DomainBoot.has_run`,
## `DomainBoot.world_summary`, `DomainBoot.set_world_observer`,
## `DomainBoot.has_world_observer`, `DomainBoot._world_of`, `DomainBoot._announce_run`,
## `DomainBoot._tear_down_run`, `DomainBoot.placed_inhabitants` and
## `DomainBoot._last_inhabitants` all still resolve, and `tests/ui/test_domain_playable.gd`
## calls four of them without knowing this file exists. GDScript cannot alias a
## static from one script onto another and cannot extend two classes, so the base is
## the only shape that keeps both spellings compiling. That is the same arrangement
## `DomainBoot` -> `DomainWards` already uses one file over, and unlike a delegation
## it leaves the entry point where every caller already found it.
##
## **No public method was renamed, no signature changed and no body was re-derived**:
## every function below moved with its docblock, character for character. The TWO
## statics it needed from the run moved with the run: `_run` and `_world_observer`
## are declared HERE once, and `DomainBoot` reads them through this base, so there is
## still one run and one seam. (Declaring them on BOTH sides was a hard parse error
## before — "The member `_run` already exists in parent class DomainWorldBoot" — and
## one unresolved class cascaded into every file naming `DomainBoot`.)
##
## ## The loops below stay BOUNDED
##
## `_last_inhabitants` walks `_roster`'s OWN entries and `_remember_inhabitants`
## builds it from the bodies `spawn_map` returned; neither grows the container its
## own condition tests. No `while` moved here.

static var _world_observer: Callable = Callable()


## The run being populated: its laid-out rects, keyed by room id as a `String` — exactly
## what `DomainPaths.layout` publishes, which is the ONE layout in the repo
## (`domain_paths.gd:182`) — and the map itself.
##
## Both are statics because the spawner hands `position_of` a room id, a ref id and an
## index and nothing else (`domain_spawner.gd:116`), so the map those are read out of has
## to be reachable without an actor in hand. They are set immediately before a
## `spawn_map` and on every room visit, and cleared on `leave_domain`, so a discarded run
## is never read by the next one. `_layout` is `{}` outside a run, which is what makes an
## unplaced spawn read as `Vector2.ZERO` rather than as a position in some other domain.
##
## ## WHY THEY SURVIVE A `teardown()`, AND WHY THAT IS A LEAK
##
## These three outlive every `Node`, so what clears them is neither a free nor a
## `teardown()`: it is [method reset]. `leave_domain` covers the path a PLAYER takes;
## `reset` covers the ones where a run ended without the player asking.
##
## ## WHY THEY ARE NOT DECLARED HERE
##
## They were cut into this class with the WORLD half, and every one of them is written
## and read by `DomainBoot`'s own bodies (`enter_domain` assigns `_run`, `visit_room`
## reads `_layout`, `leave_domain` clears all three). **GDScript inherits neither
## `static var` nor `static func`**, so a bare `_run` inside `DomainBoot` cannot see a
## `static var` declared here — the compiler's words were
## `Static function "has_world_observer()" not found in base "DomainBoot"`, and the same
## rule governs variables. The state therefore lives on `DomainBoot`, which is also where
## the majority of the reads and ALL of the writes already are, and the accessors below
## are what this half uses to reach it. One owner, one name, no second copy.
static func _layout_state() -> Dictionary:
	return DomainBoot._layout


static func _run_state() -> DomainMap:
	return DomainBoot._run


static func _roster_state() -> Dictionary:
	return DomainBoot._roster


## Who stands the realized world up once a run exists. A `Callable`, not a reference, and
## for the reason `install` documents: `enter_domain` is a STATIC on that file, and the
## node that can parent a `Node2D` in the tree is the composition ROOT, which is an
## instance. `NpcApi.set_minter` and `CustodyApi.set_resolver` are the same seam one layer
## down; this is the same seam a layer up.
##
## OPTIONAL, and its refusal is REPORTED rather than swallowed: a caller that entered a run
## with nothing listening still got a run — the world is a view of it, not a condition of
## it — so `enter_domain` records that nobody realized and carries on.


## Install the optional observer that stands the realized world up under whichever screen
## is showing.
##
## Declared HERE because `_world_observer` lives here, and `DomainBoot` cannot reach a
## base's member — GDScript inherits neither `static` functions nor `static var`. The
## forwarding pair on `DomainBoot` exists for the same reason and calls these.
static func set_world_observer(observer: Callable) -> void:
	_world_observer = observer


## Whether an observer is installed, so a caller can say "nobody is listening" and "the
## observer refused" as two different messages rather than one empty descriptor.
static func has_world_observer() -> bool:
	return _world_observer.is_valid()


## FORGET the current run: clear `_run`, `_layout` and `_roster`, and answer what was
## discarded. Idempotent — a second call reports nothing forgotten rather than pretending
## it cleared something.
##
## ## Why the BODY lives here and `DomainBoot.reset` forwards to it
##
## `_run`, `_layout` and `_roster` are declared on THIS class — they are the world half's
## own state — and **GDScript inherits neither `static var` nor `static func`**, so a
## bare `_run = null` inside `DomainBoot.reset` would not compile. The clearing body is
## therefore here, beside the three statics it clears, and `DomainBoot.reset` is the
## forward every existing caller already spells.
static func reset() -> Dictionary:
	var forgotten := {"had_run": _run_state() != null, "inhabitants": _roster_state().size()}
	DomainBoot._run = null
	DomainBoot._layout = {}
	DomainBoot._roster = {}
	return forgotten


# ── the world. Built here, parented by the caller, freed by the caller ────────
#
# ADR 0072:14 said it plainly — "A domain you cannot walk is a spreadsheet." Before this
# section `DomainScene` was a complete walkable tile scene whose only caller was its own
# `_init`, and `DomainSpawner`'s placement record — a real `Vector2` per inhabitant, written
# into `actor.module_data` by `_place` and read by nobody — was a dead field.
#
# ## WHY THE WORLD IS AN ARGUMENT AND NOT A FIELD
#
# `tools/arch/rules.py` rejects a stateful system in `app/` (`app_state_signals`). This file
# already carries `persistence`, so there is NO `var _world: Node2D` here: the world is
# BUILT by [method realize_world], PARENTED by whoever asked, FREED by
# [method release_world]. `item_workbench_app.gd` holds no handle — it finds the world by
# name under the screen it is showing, so no second reference can outlive the node.
#
# Everything touching a `Node2D`, a tile or an adapter stays in `DomainScene`, which already
# owns "where is this map in pixels". The verbs below resolve the two facts only this file
# knows — which run is active, which bodies were minted — and pass them as ARGUMENTS;
# nothing is read back out of a node.
#
# ## NO `_ready`, NO `await`, NO DEFERRED WORK
#
# The headless runner drives tests from `SceneTree._initialize()`, which returns before the
# first frame: `_ready()` is never delivered to a node parented to `root`. So the build
# happens in the caller's frame — `DomainScene` builds in `_init()` and the adapter is
# configured by explicit setters.


## REALIZE the active run as a walkable world under `parent`, and answer what happened.
##
## Builds a `DomainScene` from `_run`, places one body per minted inhabitant at the
## placement `DomainSpawner` already recorded, and adds a bounded `PlayerAdapter` at the
## entry centre. Refuses `no_map` BY NAME and writes nothing before it resolves, so a
## refusal leaves the caller's tree exactly as it found it.
##
## ## And registers the hostile targets, which is the `intent` stage
##
## A creature node that exists but is on nobody's list is the shape the ADR 0228 audit
## measured as "nothing the player does in a domain resolves": `PlayerAdapter.attack`
## reads a list the `InteractionArea` fills, a placed creature is a bare `Node2D` no
## physics body ever enters, and so the list was empty on every real run. Registration
## happens HERE rather than in `place_inhabitants` because the adapter does not exist until
## `place_player` has run — so the two must be joined by the caller that owns both, which
## is this one.
static func realize_world(parent: Node, player: Actor) -> Dictionary:
	if _run_state() == null:
		return {"ok": false, "reason": "no_map"}
	var realized := DomainScene.realize_world(parent, _run_state(), player, _last_inhabitants())
	if not bool(realized.get("ok", false)):
		return realized
	var world := realized.get("world") as Node2D
	var adapter := realized.get("player") as PlayerAdapter
	if adapter != null:
		adapter.clear_targets()
	realized["targets"] = DomainScene.register_targets(world)
	return realized


## The realized world standing under `parent`, or `null`. Every verb below that answers a
## question about a NODE in the tree reaches it through here, so the node name is spelled
## once (`DomainWorld.WORLD_NODE`) rather than per caller.
static func _world_of(parent: Node) -> Node2D:
	if parent == null:
		return null
	if parent is Node2D and (parent as Node2D).name == DomainWorld.WORLD_NODE:
		return parent as Node2D
	return parent.get_node_or_null(NodePath(DomainWorld.WORLD_NODE)) as Node2D


## Register the placed hostiles the player's next press can reach under `parent`, and
## answer how many. The `intent` READ, callable on its own so a probe or a screen can
## refresh the list after a move without rebuilding the world.
static func register_targets(parent: Node) -> Dictionary:
	var world := _world_of(parent)
	if world == null:
		return {"ok": false, "reason": "no_world", "registered": 0}
	var registered := DomainScene.register_targets(world)
	return {
		"ok": true,
		"reason": "",
		"registered": registered,
		"in_reach": DomainScene.targets_in_reach(world),
	}


## FREE the realized world under `parent`. Idempotent, and a no-op when nothing was ever
## realized, so a `teardown()` may call it without asking first.
static func release_world(parent: Node) -> Dictionary:
	return DomainScene.release_world(parent)


## Whether a world is currently realized under `parent`. Read by the composition root and by
## `test_domain_playable.gd` through this one verb, so neither walks for a node name this
## file does not publish.
static func world_realized(parent: Node) -> bool:
	return DomainScene.world_realized(parent)


## Whether a run is active right now.
##
## The half of "is there a domain" that does NOT depend on a scene tree. `world_realized`
## answers whether a world is STANDING, which is false for a run entered headlessly or on
## a screen that realizes nothing — so a caller asking "is the player inside a domain?"
## and getting `false` from that verb would be told the run does not exist when it does.
## Reads the same `_run` every other verb here does, so it cannot disagree with them.
static func has_run() -> bool:
	return _run_state() != null


## The realized world's read model, primitives only, or `{}` when nothing is realized.
static func world_summary(parent: Node) -> Dictionary:
	return DomainScene.world_summary(parent)


## TELL the installed observer that a run now exists, and answer what it did with it.
##
## ## Why the seam is optional and its refusal is REPORTED
##
## The world is a VIEW of a run, not a condition of one. A caller that entered a run with
## nothing listening still has a real map, a real roster and real hazards — so this returns
## `{"ok": false, "reason": "no_observer"}` rather than refusing the run, and the reason is
## NAMED so a caller can tell "nobody is listening" from "the listener refused". That
## distinction is the whole reason this returns a dictionary instead of a bool: an
## unobserved run is a legitimate state (every headless probe that drives `enter_domain`
## directly gets one) and it must be distinguishable from a failure.
##
## `_world_observer` is a `Callable`, never a reference, because `enter_domain` is a STATIC
## on this file and the node that can parent a `Node2D` is the composition ROOT, which is an
## instance. `NpcApi.set_minter` and `CustodyApi.set_resolver` are the same seam one layer
## down; this is the same seam a layer up.
##
## The observer's own answer is passed back UNTOUCHED, because a listener that reports
## `no_surface` (the run exists but nothing is showing the domain) has said something the
## composition root needs to see and this file cannot improve on it.
static func _announce_run() -> Dictionary:
	if not _world_observer.is_valid():
		return {"ok": false, "reason": "no_observer"}
	return _world_observer.call(&"realize") as Dictionary


## TELL the installed observer that the run has ended, and answer what it freed.
##
## Called BEFORE `_run` / `_layout` / `_roster` are cleared, so a listener that still wants
## the floor's geometry can still reach the map this run realized from. Clearing first
## would hand the teardown a map that has already stopped existing.
##
## The observer is NOT installed-over here: leaving a stale observer would let a run entered
## later be realized under a screen the composition root has since navigated away from.
## `set_world_observer` is what replaces it, and `_install_domain_world_observer` calls it
## on every mount of the domain route.
##
## Same optional-seam contract as [method _announce_run]: no observer is
## `{"ok": true, "freed": 0}` — "nothing was realized" is the honest answer for a run
## entered through a headless probe rather than through the screen, and it is reported as a
## success because nothing had to be undone.
static func _tear_down_run() -> Dictionary:
	if not _world_observer.is_valid():
		return {"ok": true, "reason": "no_observer", "freed": 0}
	var answer: Dictionary = _world_observer.call(&"release") as Dictionary
	if answer.is_empty():
		# The listener had no screen standing a world under. That is a no-op rather than a
		# failure, and a fabricated `freed` count would be a number nobody could check.
		return {"ok": true, "reason": "no_surface", "freed": 0}
	return answer


## Every inhabitant the LAST `enter_domain` minted, as `Actor`s.
##
## Published rather than kept private because the fight seam has to answer "which band
## entry does this fallen body belong to", and a fallen body is identified by its species
## id — which is NOT unique inside a run (`spawn_inhabitant` hands `def.inhabitant_id` to
## `Actor.new` unchanged, so every `cinder_hound` shares one). The roster is the only
## place a placed body's room and role are both on hand, so `DomainFight` asks here rather
## than re-deriving provenance the spawner already recorded.
static func placed_inhabitants() -> Array:
	return _last_inhabitants()


## Every inhabitant the LAST `enter_domain` minted, as `Actor`s.
##
## ## Why a handle and not a re-derivation
##
## `spawn_map` RETURNS the bodies it minted and leaves no index behind: it stamps
## `role` / `inhabitant_id` / `room_id` / `ref_id` / `position` onto each `Actor`'s own
## `module_data`, but nothing on the module can be walked to FIND them, because an
## `Actor` is not enumerable from the run. So the roster is held here, beside `_run` and
## `_layout`, and is written in the same statement that assigns them.
##
## ## Why this is a `Dictionary` and NOT an `Array`
##
## `tools/arch/rules.py`'s `APP_UNSHAPED_ARRAY_RE` and `APP_CONTENT_ARRAY_RE` read a
## member `Array` (untyped, or typed by a repo class) as a `state-table` signal, and
## `app_state_warnings` fires at two signals. This file already carries `persistence`
## (`_active_map` calls `get_module_data`), so an `Array[Actor]` member here would be the
## second signal and would turn this composition-root wiring into a flagged stateful
## system. A `Dictionary` is a HANDLE — one entry, replaced wholesale on every entry,
## emptied on leave — not a slot table that the file grows and decays. The walk that
## reads it is bounded by the authored spawn refs, which
## `DomainSpawner.MAX_COUNT_PER_REF` already caps at 64 per ref.
static func _last_inhabitants() -> Array:
	var out: Array = []
	for actor in _roster_state().values():
		if actor is Actor:
			out.append(actor)
	return out


## Every inhabitant as `instance id -> Actor`, the one place the roster is written. Split
## from `_last_inhabitants` so `enter_domain` assigns it in a single statement with the
## map it belongs to. **The key is `get_instance_id()`, NOT `String(actor.id)`** — see the
## note on `_roster`, and [method _forget] for the silence that hid that mistake.
static func _remember_inhabitants(inhabitants: Array) -> void:
	var out: Dictionary = {}
	for inhabitant in inhabitants:
		var actor := inhabitant as Actor
		if actor == null:
			continue
		out[actor.get_instance_id()] = actor
	DomainBoot._roster = out
	_forget(inhabitants.size())


## REPORT the bodies a roster handle did not keep, by name. A handle is lossy the moment
## its key is not unique, so "how many did this run mint?" can only be answered HERE,
## where the minted count and the stored size are both in hand. Reported, never repaired:
## a roster quietly holding fewer bodies than the map authored is exactly the "the roster
## reads 6 and the world holds 0" failure this program exists to prevent.
static func _forget(minted: int) -> void:
	var held := _roster_state().size()
	if held == minted:
		return
	push_error(
		(
			(
				"DomainBoot: a run minted %d inhabitant(s) and the roster kept %d; %d were dropped "
				% [minted, held, maxi(0, minted - held)]
			)
			+ " rather than realized. A world drawing fewer creatures than the map authored is a "
			+ "silent shortfall, so it is named here."
		)
	)
