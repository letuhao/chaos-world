class_name DomainBoot
extends DomainWorldBoot

## The composition root's domain wiring (ADR 0072-0075). Wiring, not rules: `app/`
## injects the constructor; the `domain` module owns what a map, a room and an inhabitant
## mean.
##
## The domain twin of `NpcBoot`, and it exists for the same reason. An audit measured
## **13 of 13 domain source files with zero production call sites**: `install` was never
## called, `spawn_map` never ran and `EnvironmentField.apply` never applied, so the module
## was a library nothing could reach — a feature nobody can start is decoration, which is
## the failure ADR 0089 measured for statuses. All three are now on a production path.
##
## Deliberately wiring-only: no rules, no state of its own, **nothing that ticks**.
## Severe environments resolve through `EnvironmentField` on the same `StatusLoop` tick
## every other status uses (ADR 0089); a second `_process` would be the stateful-`app/`
## shape `tools/arch/rules.py` rejects.

const KEY_REACH := &"key_reach"

## The source tag on the `Stat.MAX_HEALTH` offset a placed creature's authored
## `blows_to_survive` buys. DISTINCT from `FightLoop.FIGHT_POOL_SOURCE` and from
## `RealmScaling.SOURCE`, because `remove_modifiers_from` wipes a source wholesale: a
## shared tag would let the next breakthrough erase the pool a spawn just priced, and
## the creature would be back to one-press.
const INHABITANT_POOL_SOURCE := &"inhabitant_pool"

## The interval a boss announces on when its spec authors none — `FightLoop`'s own neutral
## blow interval, read rather than restated. Spelled here as a FORWARD because a static
## constant may not be initialised from another class's constant at parse time on this
## engine; the value is `FightLoop.BASE_BLOW_INTERVAL` and the test that proves the two
## agree is in `game/tests/modules/domain/test_domain_run_boss.gd`.
const NEUTRAL_BLOW_INTERVAL := 2.380952380952381

## The realized world, by name. [method realize_world] builds a `Node2D` under a parent the
## CALLER chose, so the composition root owns the node that draws the world and the world
## goes away with it; these four names are how anyone finds it afterwards.
##
## Declared HERE rather than beside the world section because `class-definitions-order`
## (gdlint) puts every `const` before every `func`, and a const declared mid-file is an
## ordering error rather than a local convenience.
const WORLD_NODE := &"DomainWorld"
const WORLD_SCENE_NODE := &"DomainScene"
const WORLD_PLAYER_NODE := &"DomainPlayer"
const WORLD_INHABITANTS_NODE := &"DomainInhabitants"

## Every node a realized world creates, so [method release_world] frees the subtree by name
## rather than by walking it — and so a caller can see exactly what it now owes the process.
##
## An ENGINE element type (`StringName`), never a repo type, which is what keeps this out of
## the `app/` state-table heuristic — see [method _last_inhabitants].
const WORLD_BORN: Array[StringName] = [
	WORLD_PLAYER_NODE,
	WORLD_INHABITANTS_NODE,
	WORLD_SCENE_NODE,
]

## ## The run's three statics, and WHY they are declared here rather than on the base
##
## `_run`, `_layout` and `_roster` outlive every `Node`, so what clears them is neither a
## free nor a `teardown()`: it is [method reset]. `leave_domain` covers the path a PLAYER
## takes; `reset` covers a run that ended without the player asking.
##
## They were cut into `DomainWorldBoot` with the WORLD half and had to come back,
## because **GDScript inherits neither `static var` nor `static func`**: every write and
## most of the reads are in THIS file (`enter_domain` assigns `_run` and `_layout`,
## `leave_domain` clears all three), and a bare `_run` here cannot see a `static var`
## declared on a base. The compiler's own words for the sibling case were
## `Static function "has_world_observer()" not found in base "DomainBoot"`. One owner,
## one name, no second copy — the base reaches them through `_run_state()`, `_layout_state()`
## and `_roster_state()`.
static var _layout: Dictionary = {}
static var _run: DomainMap = null

## The bodies [method enter_domain] minted for `_run`, as `instance id -> Actor` — a
## handle, not a table, and NOT keyed by `actor id`, which is the SPECIES
## (`spawn_inhabitant` hands `def.inhabitant_id` to `Actor.new` unchanged, so every
## `cinder_hound` shares one id). Keying by id collapsed a `count: 2` room to ONE entry.
static var _roster: Dictionary = {}

## This file passed the thousand-line ceiling, and the section that moved is the one whose
## own banner drew the cut: "the two facts a domain run needs from outside its own module"
## — the authored template weather, the wardrobe / codex / bag ward tags, the inhabitant
## catalogue, and the two closed vocabularies they are filtered by. All of it now lives on
## `DomainWards`, which this class EXTENDS. **No public method was renamed, no signature
## changed and no body was re-derived:** `DomainBoot.publish_ward_tags`,
## `DomainBoot._template_weather` and `DomainBoot._map_accepts` all still answer under the
## names `tests/modules/domain/test_domain_weather.gd` and `EnvironmentField`'s docblock
## already use. GDScript cannot alias a static from one script onto another and cannot
## extend two classes, so inheritance is the only shape that keeps both spellings
## compiling — the same arrangement `ItemWorkbenchApp` -> `ItemWorkbenchBody` uses, and
## unlike a delegation it leaves the entry point where the callers found it.
##
## The element and consumable vocabularies are declared ONCE, on `DomainWards`, which
## this class extends — so `DomainBoot.ELEMENT_TAGS` and `DomainBoot.CONSUMABLE_SUBTYPES`
## still answer under those spellings for every reader that used them.
##
## **They were declared on BOTH sides, and that was a parse error, not a mirror.** The
## mirror existed while the two files were SIBLINGS under `app/`, which cannot read one
## another's constants. The split that made `DomainWards` this class's BASE removed the
## reason for it: GDScript rejects a redeclared member outright ("The member
## `ELEMENT_TAGS` already exists in parent class DomainWards"), so `domain_boot.gd` failed
## to parse, `DomainBoot` stopped resolving for every file that names it —
## `item_workbench_body.gd` included — and `ItemWorkbenchBody` with it. One unresolved
## class cascaded into `ItemWorkbenchApp`, which is what left the `tests/ui` domain suites
## booting a bare `Control` and the module suite calling a function that was never there.
## One declaration per name is also what makes the "each side can drift" argument moot:
## there is no second list to drift from.
##
## ## The chain this class EXTENDS, top to bottom
##
## `DomainBoot` -> `DomainWorldBoot` -> `DomainWards`. `DomainWards` holds the contacts a
## domain run needs from outside its own module; `DomainWorldBoot` holds the statics a
## realized world is built FROM — the run itself and the optional observer that stands it
## up — plus every verb that answers a question about a NODE in the tree rather than about
## the run. Both are bases rather than delegates for the reason `DomainWards`' own
## docblock gives: GDScript cannot alias a static from one script onto another and cannot
## extend two classes, so **DELEGATION** is the shape that keeps `DomainBoot.<name>`
## resolving for every caller that already spells it that way. Every name declared on
## either base is declared ONCE, there — a redeclared member is a hard parse error in
## GDScript, and one unresolved class cascades into everything naming it.
##
## ## Why DELEGATION and not INHERITANCE — measured, not assumed
##
## This file `extends DomainWorldBoot`, and that was the first attempt. **GDScript does
## not inherit `static` members.** The compiler says so directly:
## `Static function "has_world_observer()" not found in base "DomainBoot".` Every one of
## the 23 `DomainBoot.<static>` call sites across `item_workbench_app.gd`,
## `item_workbench_body.gd`, `domain_world.gd`, `domain_scene.gd`, `domain_fight.gd` and
## two suites stopped resolving at once. The wrappers below are what makes `extends` +
## delegation correct: `DomainBoot` owns the public name, and each wrapper hands the call
## to the one definition on the base.
##
## ## The run's own three statics moved down that chain, with the section that reads them
##
## `_run`, `_layout` and `_roster` are declared on `DomainWorldBoot`, which is why the
## note in [method reset] about outliving every `Node` sits there. `DomainBoot` reads and
## writes all three by their own spellings, and `DomainBoot._run` is the same member — one
## run, one layout, one roster, exactly as before the cut.

## ## The WORLD half, delegated to [class DomainWorldBoot]
##
## GDScript cannot inherit a static, so each verb the world half owns is re-spelled here
## as a one-line forward. These are not second implementations: every body below is a
## call, and the definition it reaches is the ONLY one. The docblock on each forward lives
## on `DomainWorldBoot` beside the body it forwards to.

## ## The `DomainWards` half, forwarded
##
## `DomainWards` is the BASE of this class, and **GDScript inherits neither
## `static func` nor `static var`**. Every body below is reached by a bare name
## from this file, and a bare name resolves against THIS class only — the
## compiler's words for the sibling case were `Static function
## "has_world_observer()" not found in base "DomainBoot"`. So each verb the wards
## half owns is re-spelled here as a one-line forward. Not a second
## implementation: each body is a call, and the definition it reaches is the only
## one.


static func _template_weather(template_id: StringName) -> StringName:
	return DomainWards._template_weather(template_id)


static func publish_ward_tags(player: Actor) -> Dictionary:
	return DomainWards.publish_ward_tags(player)


static func _inhabitant_catalogue() -> Dictionary:
	return DomainWards._inhabitant_catalogue()


static func realize_world(parent: Node, player: Actor) -> Dictionary:
	return DomainWorldBoot.realize_world(parent, player)


static func register_targets(parent: Node) -> Dictionary:
	return DomainWorldBoot.register_targets(parent)


static func release_world(parent: Node) -> Dictionary:
	return DomainWorldBoot.release_world(parent)


static func world_realized(parent: Node) -> bool:
	return DomainWorldBoot.world_realized(parent)


static func has_run() -> bool:
	return DomainWorldBoot.has_run()


static func world_summary(parent: Node) -> Dictionary:
	return DomainWorldBoot.world_summary(parent)


static func placed_inhabitants() -> Array:
	return DomainWorldBoot.placed_inhabitants()


static func set_world_observer(observer: Callable) -> void:
	DomainWorldBoot.set_world_observer(observer)


static func has_world_observer() -> bool:
	return DomainWorldBoot.has_world_observer()


## The private half of the WORLD cut, forwarded for the same reason: GDScript inherits
## neither `static` functions nor `static var`, so every private the cut moved down is
## re-spelled here. `enter_domain` (line ~343/346) and `leave_domain` (line ~379) reach
## these by bare name, and a bare name resolves against THIS class only.
static func _announce_run() -> Dictionary:
	return DomainWorldBoot._announce_run()


static func _tear_down_run() -> Dictionary:
	return DomainWorldBoot._tear_down_run()


static func _last_inhabitants() -> Array:
	return DomainWorldBoot._last_inhabitants()


static func _remember_inhabitants(inhabitants: Array) -> void:
	DomainWorldBoot._remember_inhabitants(inhabitants)


static func _world_of(parent: Node) -> Node2D:
	return DomainWorldBoot._world_of(parent)


## FORGET the current run: clear `_run`, `_layout` and `_roster`, and answer what was
## discarded. Idempotent — a second call reports nothing forgotten rather than pretending
## it cleared something.
##
## `leave_domain` is the path a PLAYER takes and is correct there; this is the rest, which
## is where the leak is. A root torn down mid-run, an aborted test, a save loaded over the
## top, a second mount in one process — each drops the `Actor` that owned the run while
## `_run` points on at that hero's discarded map, and nothing frees a static. So the next
## run starts from the previous run's floor and `realize_world` answers `no_map` while the
## player is demonstrably inside a domain. `test_domain_playable.teardown()` calls this
## after the root's own: that frees the TREE, this frees the STATE the tree was drawing.
##
## `_world_observer` is deliberately NOT cleared: it is a SEAM, not a run. Dropping it
## would uninstall a live observer and make the next `enter_domain` report `no_observer`
## for a run that should have been drawn. `set_world_observer` replaces it, exactly as
## `_tear_down_run`'s note says. The minter `install` puts in place is a seam too.
static func reset() -> Dictionary:
	return DomainWorldBoot.reset()


## Install the inhabitant constructor AND the fixtures' two contacts with the items
## module. Idempotent, so calling it on boot and again after a load is the intended
## usage rather than a mistake.
##
## ## Why the fixture seam belongs in `install` and not beside its callers
##
## `DomainFixtures` gates a treasure behind a key and pays a puzzle's reward through
## an injected granter, and BOTH contact points default to refusing
## (`domain_fixtures.gd:118`). So a domain whose fixtures are wired by nobody answers
## `no_inventory_bridge` to every treasure and every formation — a treasure that reads
## as sealed and is in fact unreachable content, which is the exact failure
## `_realm_gate`'s own docblock calls out. `install` is the one place that already
## resolves the concrete constructor `domain/` may not name, so the items side belongs
## here beside it; both seams are then installed by the SAME call a boot makes, and a
## screen that wants to generate a run cannot get a half-wired one.
##
## `items` is not a declared `domain` dependency (`registry.json` gives it `core` +
## `contracts` only), which is the reason these are `Callable`s and not direct calls.
static func install() -> void:
	# The one place that knows the concrete constructor. Handing the module the static
	# function itself, rather than a lambda that forwards to it, is what keeps `domain/`
	# free of any reference to `ActorFactory` (ADR 0002) — and it is also the only form the
	# engine boots: a typed lambda whose body calls another script's static function killed
	# the process with an access violation on the shell's first frame, with nothing logged.
	# `spawn_inhabitant` takes the minter's two arguments positionally.
	#
	# It is ALSO the enroller, because a species that declares `cultivates` is enrolled and
	# mounted in the same breath. Before this second contact existed, `domain/` wrote a
	# `PathState` and nothing ever mounted behind it, so six of the nine shipped species
	# were realm-scaled rivals who could not cultivate (BL-0753). Two functions rather than
	# one, because the two seams have incompatible signatures: the minter builds an actor
	# from an id, the enroller takes an ALREADY-BUILT one plus a realm.
	DomainSpawner.set_minter(ActorFactory.spawn_inhabitant, ActorFactory.enrol_inhabitant_qi)
	DomainFixtures.set_minter(
		Callable(DomainBoot, "key_reach_of"), Callable(DomainBoot, "grant_item")
	)


## The `key_reach` the actor's whole carried inventory is worth, through the items
## module's own property reader — so a fixture's key is measured by exactly the rule a
## loot encounter's entry gate uses (`loot/api.gd:_key_reach`), and `key_reach` keeps
## ONE meaning in the game. 0.0 when nothing carried answers, which is the honest
## "this actor opens nothing".
##
## The `item_id` is part of the published shape `DomainFixtures.set_minter` installs and
## is deliberately unused here: the answer is "what is this actor carrying", not "what is
## this one item worth", so the whole inventory is measured and the per-item argument
## exists only because the fixture seam answers a per-fixture question.
static func key_reach_of(player: Actor, _item_id: StringName) -> float:
	var inventory := ItemsApi.inventory(player)
	if inventory == null:
		return 0.0
	var best := 0.0
	for batch in inventory.stacks():
		var def := batch.def_ref
		if def != null:
			best = maxf(best, float(def.property_total(inventory.sample(batch.def_id), KEY_REACH)))
	for instance in inventory.instances():
		var def := instance.def_ref
		if def != null:
			best = maxf(best, float(def.property_total(instance, KEY_REACH)))
	return best


## Hand ONE REALIZED instance of `item_id` to the actor, seeded from `seed` (ADR 0216 §4):
## the fixture's relic is the SAME relic on every replay of that fixture, so the roll
## belongs to the fixture, not to the bag, and it rides `ItemsApi.generate` — the one
## realization path the game owns (ADR 0025) — rather than a bare `inventory.add(def)`.
## Answers the dictionary seam `DomainFixtures.set_minter` reads
## (`{leftover, reason, instance_id}`): leftover 1 means nothing was handed over —
## an id the corpus cannot resolve, or a bag that cannot hold the piece — so the claim
## is left untouched rather than consumed over a delivery that did not happen.
##
## `Crafting.resolve` is `items` internals that only `app/` may name, and `ItemsApi` is
## at its twelve-method cap so no def-resolution verb could be added to it. This adapter
## is the whole reason the seam is legal where it is.
static func grant_item(player: Actor, item_id: StringName, seed: int) -> Dictionary:
	var def := Crafting.resolve(item_id)
	if def == null:
		# Nothing handed over, and the reason is REPORTED: a reward for an undefined
		# item is a content defect, not a full bag (ADR 0216's consequences).
		return {"leftover": 1, "reason": "unknown_item", "instance_id": ""}
	if ItemsApi.inventory(player) == null:
		return {"leftover": 1, "reason": "no_inventory", "instance_id": ""}
	var instance := ItemsApi.generate(player, def, seed)
	if instance == null:
		return {"leftover": 1, "reason": "inventory_full", "instance_id": ""}
	return {"leftover": 0, "reason": "", "instance_id": String(instance.instance_id)}


## The whole domain read model for one screen or the headless driver (BL-0220): which
## domains are authored, what is in the active one, and who is standing there.
##
## Deliberately does NOT call `install` on a read path beyond the constructor injection,
## because installing is idempotent and a read must never mint anything.
static func read_model(player: Actor) -> Dictionary:
	return {
		"has_actor": player != null,
		"templates": DomainApi.templates(),
		"active": DomainApi.summary(player),
	}


## Generate and enter an authored domain in one call, then report what the player is
## standing in. This is the production entry point that closes the chain the audit found
## severed: a template is loaded, a map is generated, the contract is enforced, and the
## run becomes the actor's active domain.
##
## A template that cannot produce a contract-valid map is refused BY NAME. A run that
## begins in a broken map is a run the player cannot finish, and the generator has already
## reported exactly why.
##
## ## The run is POPULATED, which is what `population` alone never was
##
## `DomainApi.population` answers with the map's spawn REFS — dictionaries. A screen that
## renders those describes creatures that do not exist, and nothing in `src/` ever called
## `DomainSpawner.spawn_map`, so the roster a player read was an inventory of intentions.
## So the spawner runs HERE, over the map that was just entered: every authored ref mints a
## real `Actor` through the minter `install` put in place, and the minted bodies are
## RETURNED so a screen or a probe can see that they are bodies rather than rows.
##
## The severe zones are applied here too, to the same hero, at the entry point of the run
## rather than on some later tick — see [method _apply_zones] for why the zones are resolved
## per room and why the player's own path is the one they resolve against.
static func enter_domain(player: Actor, template_id: StringName, seed_value: int = 0) -> Dictionary:
	install()
	var entered := DomainApi.generate_and_enter(player, template_id, seed_value)
	if not entered.get("ok", false):
		return entered
	var map := _active_map(player)
	_run = map
	_layout = DomainPaths.layout(map)
	# The run's weather is PUBLISHED, not guessed. `DomainGenerator` never copies the
	# template's weather onto the map it builds, so without this line every production
	# run enters with no weather and every authored weather is a `.tres` row only a test
	# ever reads. It goes through the facade's own `visit_room` — the one verb that
	# already owns the weather write — against the entry room, so the discovery ledger
	# is not disturbed and the run is not re-entered.
	var weather := _template_weather(template_id)
	if weather != DomainMap.WEATHER_NONE and map != null:
		DomainApi.visit_room(player, map.entry_room, weather)
		map = _active_map(player)
		_run = map
		_layout = DomainPaths.layout(map)
	var inhabitants := DomainSpawner.spawn_map(
		map, _inhabitant_catalogue(), Callable(DomainBoot, "_spawn_point")
	)
	# **Every minted body is made FIGHTABLE here, and nowhere else** (ADR 0228, 0230,
	# 0235). `spawn_map` mints `Actor`s through `ActorFactory`, which builds the same
	# provider spine the player gets but does NOT bind a `DamageMechanism` — and
	# `MechanismSlot.of` ASSERTS when nothing is bound (`spine.gd:139`), so an
	# un-installed creature is a crash at the first blow rather than a chip. So the
	# spawn seam installs it, which is a line in `app/` and not a new module: the same
	# `mint -> enrol -> install -> begin` order `FightLoop.start_fight` already
	# documents (`fight_loop.gd:206-222`).
	for inhabitant in inhabitants:
		_prepare_inhabitant(inhabitant as Actor, player)
	# **The world is realized HERE, at the moment a run exists.** Before this the run was
	# a `Vector2` per inhabitant in `module_data` that nothing outside a test ever read, and
	# `DomainScene` was a walkable tile scene with no production caller at all. The seam is
	# optional and its refusal is REPORTED: a caller that entered with nothing listening
	# still has a real run, and a world is a view of a run rather than a condition of one.
	_remember_inhabitants(inhabitants)
	publish_ward_tags(player)
	var applied := _apply_zones(player, map, map.entry_room if map != null else &"")
	var realized := _announce_run()
	return {
		"ok": true,
		"domain_id": entered.get("domain_id", ""),
		"room_count": entered.get("room_count", 0),
		"map": DomainApi.map_summary(player),
		"population": DomainApi.population(player),
		"zones": DomainApi.environment_zones(player),
		# The inhabitants as ACTORS, not as rows. `inhabitants` is what the player is
		# actually standing among; `population` stays the map's own authored refs.
		"inhabitants": inhabitants,
		"inhabitant_count": inhabitants.size(),
		# Every severe zone in the ENTRY room, applied on arrival. `{}` outside a run or
		# when the entry room authors none, which is authored content rather than a defect.
		"applied_zones": applied,
		# What the world observer answered. `{"ok": false, "reason": "no_observer"}` when
		# nothing was listening — which is the case every existing caller gets, because
		# the observer is installed by the composition root's domain route and a probe
		# driving `enter` directly may never have opened it. The run is real either way;
		# what is not real is the FLOOR under it, and this says so by name.
		"world": realized,
	}


## Leave the domain. The run is discarded; the discovered set is KEPT, because the map
## remembers where you have been even though the inhabitants do not (BL-0252).
static func leave_domain(player: Actor) -> Dictionary:
	var left := DomainApi.leave(player)
	# The place goes with the run. A hero who leaves a rich room and cultivates in the
	# overworld must not keep the room's density — the same publish-don't-skip rule
	# `_apply_zones` states (ADR 0214/0926).
	CultivationGain.publish_density(player, CultivationGain.NEUTRAL)
	# **The floor goes before the run does.** A world realized from this run's map is
	# still standing its tiles under whoever opened the screen, and the map those tiles
	# were stamped from is about to stop existing. Detached and freed here rather than
	# left to the screen's own free: leaving is a verb a player can press without ever
	# navigating away, so the screen may well still be mounted afterwards.
	var torn := _tear_down_run()
	# The inhabitants went with the run, so the placement cache must go with them: a
	# static left pointing at a discarded map's layout is a stale answer waiting for the
	# next run to read it. `enter_domain` rebuilds both on every entry, so clearing is enough.
	# `_roster` goes with them for the same reason: a body from a discarded run has a
	# placement into a map nobody is standing in, and realizing a world from it would draw
	# this run's creatures under the NEXT run's floor tiles.
	_layout = {}
	_run = null
	_roster = {}
	# The world is reported, not just freed: a caller needs to be able to say whether the
	# floor it was standing on is gone. `{"ok": true, "freed": 0}` when nothing was
	# realized, which is the honest answer for a run entered through a headless probe
	# rather than through the screen.
	left["world"] = torn
	return left


## Record that the player walked into `room_id`. Thin on purpose: the facade owns the
## discovery ledger and the weather bias, and this exists only so a screen asks one
## verb of `app/` instead of naming `DomainApi`.
##
## Walking into a room is also WHEN its hazards reach you (ADR 0075: telegraph before
## damage, and the boundary is drawn a room at a time), so the severe zones belonging to
## the room just reached are applied to the actor here. The facade's own answer is passed
## back untouched, with the applied zones alongside it — the discovery ledger stays the
## module's, and only the environment is wired here.
static func visit_room(player: Actor, room_id: StringName, weather: StringName = &"") -> Dictionary:
	var reached := DomainApi.visit_room(player, room_id, weather)
	if not bool(reached.get("ok", false)):
		return reached
	var map := _active_map(player)
	_run = map
	_layout = DomainPaths.layout(map)
	# Re-published on EVERY room entry, not only at run start: a ward is something the
	# player equips, learns or picks up WHILE exploring, so a snapshot taken once on
	# arrival would be stale by the time the player walks into the room that needs it.
	publish_ward_tags(player)
	reached["applied_zones"] = _apply_zones(player, map, room_id)
	return reached


# ── the two facts a domain run needs from outside its own module ──────────────
#
# Both used to live here and now live on `DomainWards`, which this class EXTENDS, so
# `DomainBoot.publish_ward_tags`, `DomainBoot._template_weather` and
# `DomainBoot._map_accepts` keep answering under the names every caller already uses.
# Both are CONTACTS with a module `domain` may not depend on: `domain` declares `core` +
# `contracts` only (tools/arch/registry.json), so it cannot name `items`, `techniques` or
# a `.tres` template without breaking that edge. `app/` is the composition root and is
# allowed to depend on anything, so the two reads happen in `app/` and are handed to the
# module as PLAIN DATA — the same reason `install` hands the spawner a `Callable` instead
# of letting `domain/` name `ActorFactory`.

# ── the population and the environment. Both are wiring, neither is a rule ──────


## Make one minted inhabitant FIGHTABLE, and report what it now carries.
##
## ## Why this is the whole of "a domain creature can be fought"
##
## The audit ADR 0228 measured found a domain inhabitant **unkillable**: `PlayerAdapter`
## is the only thing that mounts it, nothing ever published a target, and nothing routed a
## spine outcome back into a run. Three pieces were missing and all three live here,
## because `app/` is the composition root and is the only layer allowed to name a concrete
## `CombatSpine`, a `StatModifier` and a `BossEncounter` at once:
##
## 1. **`CombatBoot.install`** — binds the `DamageMechanism` and the wound ledger. Without
##    it `MechanismSlot.of` asserts at S4 and a creature is a crash, not a chip.
## 2. **the survivability offset** — `Stat.MAX_HEALTH` FLAT, sized in BLOWs read off the
##    def (`DomainSpawner.blows_to_survive_of`). A FLAT offset rather than an assignment, so
##    it COMPOSES with `RealmScaling`'s realm MULT and both sides move together up the
##    ladder (ADR 0230). `FightLoop._size_opponent` does exactly this and says it is for
##    MINTED opponents only; this is that line moved to where authored content is read.
## 3. **the boss component** — only for a species that AUTHORS a spec. A `boss` role with
##    no spec gets nothing and fights arithmetically like a mob, which is ADR 0235's own
##    fail-safe.
##
## ## The order is not negotiable
##
## `install` reads `acupoints` / `sea_of_consciousness` to CHOOSE a mechanism, and
## `DomainSpawner` enrols BEFORE it hands the actor back — so install-after-enrol is the
## only order in which a cultivator's body or mind path can be measured as present.
## Sizing comes LAST, because it reads the installed actor's own blow price.
##
## `player` is the hero the pool is priced AGAINST, and it is the parameter rather than a
## static so a headless probe can price a creature against a body of its own instead of
## against whatever hero happens to be in `app/`.
static func _prepare_inhabitant(inhabitant: Actor, player: Actor = null) -> Dictionary:
	if inhabitant == null:
		return {"ok": false, "reason": "no_actor"}
	var installed := CombatBoot.install(inhabitant)
	var sized := _size_inhabitant(inhabitant, player)
	var boss := _bind_boss(inhabitant)
	inhabitant.mark_stats_dirty()
	return {
		"ok": bool(installed.get("ok", false)),
		"reason": String(installed.get("reason", "")),
		"mechanism": String(installed.get("mechanism", "")),
		"blows_to_survive": float(sized.get("blows_to_survive", 0.0)),
		"health_max": float(sized.get("health_max", 0.0)),
		"boss": bool(boss.get("ok", false)),
		"punish_window_blows": int(boss.get("punish_window_blows", 0)),
	}


## The `Stat.MAX_HEALTH` offset a placed creature's authored blows_to_survive buys,
## applied once. `0.0` authored means UNSIZED and the pool is left exactly as minted.
##
## **The blow is priced against the hero, and against a CLONE of the creature.** The clone
## is `to_dict`/`from_dict` rather than `duplicate()` for `FightLoop._price_blow`'s reason:
## `Actor` is `RefCounted` and has no `duplicate`, and its own save round-trip is the copy
## already specified to carry every stat-bearing surface the spine reads — which is exactly
## the set a body blow prices off (`BodyDamage.breakdown`). Pricing against the live
## creature would measure a different body than the first blow actually hits.
##
## Bounded by no loop at all: one sample, one offset, one `set_maximum`. A hero who cannot
## be priced leaves the pool alone rather than guessing at a magnitude, for
## `FightLoop._size_opponent`'s reason — a pool of `0.0` is a fight that is over before it
## opens.
static func _size_inhabitant(inhabitant: Actor, player: Actor = null) -> Dictionary:
	var authored := DomainSpawner.blows_to_survive_of(inhabitant)
	if authored <= 0.0:
		var pool := inhabitant.resource(&"health") as ResourcePool
		return {
			"ok": true,
			"reason": "unsized",
			"blows_to_survive": 0.0,
			"health_max": 0.0 if pool == null else pool.maximum,
		}
	var blow := _price_inhabitant_blow(inhabitant, player)
	if blow <= 0.0:
		return {"ok": false, "reason": "no_blow_to_price", "blows_to_survive": authored}
	inhabitant.stats.add_modifier(
		StatModifier.new(Stat.MAX_HEALTH, Stat.Op.FLAT, blow * authored, INHABITANT_POOL_SOURCE)
	)
	var pool := inhabitant.resource(&"health") as ResourcePool
	if pool == null:
		inhabitant.attach_core_resources()
		pool = inhabitant.resource(&"health") as ResourcePool
	if pool != null:
		pool.set_maximum(inhabitant.stats.derived(Stat.MAX_HEALTH))
	return {
		"ok": true,
		"reason": "",
		"blows_to_survive": authored,
		"health_max": 0.0 if pool == null else pool.maximum,
	}


## What one hero blow is worth against an un-sized body like this creature's, or `0.0`
## when there is nothing to price. `player` may be null, in which case the creature is
## priced against ITSELF — which is the honest degenerate case a headless probe gets, and
## a weaker answer than a real comparison rather than a fabricated one.
static func _price_inhabitant_blow(inhabitant: Actor, player: Actor) -> float:
	var attacker := player if player != null else inhabitant
	var sample := Actor.from_dict(inhabitant.to_dict())
	if sample == null:
		return 0.0
	var technique := TechniqueDef.new()
	technique.path = PathState.QI
	technique.magnitude = CombatBoot.BARE_SWING_MAGNITUDE
	technique.element_share = CombatBoot.BARE_SWING_SHARE
	# A NULL generator, so the spine's S2 band lands every strike and S3's crit never
	# fires (ADR 0087's S12) — the blow's NORMAL value rather than one sample of a roll.
	var outcome := CombatBoot.resolve_hit(
		attacker, sample, technique, CombatEngineApi.tuning(), null
	)
	return maxf(0.0, float(outcome.amount))


## Bind the authored boss turn to a creature that authors one, and report it. `{}`-spec
## species are left ALONE: ADR 0235's fail-safe is that an absent spec means no component
## is installed and the actor is a mob with a big pool, so this is a no-op on the majority
## of a domain's roster.
##
## The component's interval defaults to the NEUTRAL blow interval rather than the hero's
## own: a boss announces on the rate gate ADR 0197's anchor is built on, and a boss that
## inherited the hero's `attack_speed` would be a second rate this file invented.
static func _bind_boss(inhabitant: Actor) -> Dictionary:
	var spec := DomainSpawner.boss_spec_of(inhabitant)
	if spec.is_empty():
		return {"ok": false, "reason": "no_boss_spec", "punish_window_blows": 0}
	var answer := BossEncounter.bind(
		inhabitant,
		float(spec.get("interval", NEUTRAL_BLOW_INTERVAL)),
		int(spec.get("punish_window_blows", 0))
	)
	answer["punish_window_blows"] = int(spec.get("punish_window_blows", 0))
	return answer


## Where [method DomainSpawner.spawn_map] puts instance `index` of `ref_id` in `room_id`.
##
## A pure function of the map's OWN layout and of the ref's canonical slot: the same map,
## the same ref and the same index always answer the same tile, on every machine and every
## run. The room's laid-out rect is the floor, the ref's canonical slot walks the MAJOR axis
## so two refs in one room never stack, and the instance index walks the MINOR axis so three
## mobs of one ref are three mobs a player can tell apart.
##
## Not a closure over a run: the note on `install` records that a typed lambda whose body
## calls another script's static function killed the process on the shell's first frame, so
## this is a static method reached through `Callable(DomainBoot, "_spawn_point")` for the
## same reason every other seam in this file is.
static func _spawn_point(room_id: StringName, ref_id: String, index: int) -> Vector2:
	var rect: Rect2i = _layout.get(String(room_id), Rect2i())
	if rect.size.x <= 0 or rect.size.y <= 0:
		# A room the layout does not place is a map defect, and `DomainMapContract`
		# reports it separately. Returning the origin rather than a guess keeps the
		# spawner's own loud refusal the only thing a reader has to react to.
		return Vector2.ZERO
	var slot := maxi(0, _ref_slot(room_id, ref_id))
	var refs := maxi(1, _ref_count(room_id))
	# The slot walks the room's MAJOR axis and the instance walks its MINOR one, so two
	# refs never land on one tile and the instances of one ref are still inside the room.
	var along_x := rect.size.x >= rect.size.y
	var major := rect.size.x if along_x else rect.size.y
	var minor := rect.size.y if along_x else rect.size.x
	# Clamped into the room: a room smaller than its ref count wraps rather than placing
	# an inhabitant in a wall past its own edge. The clamp is on the CELL, so the answer
	# is always a tile the room owns — a spawn outside its room is a spawn in scenery.
	var cell := Vector2i(
		rect.position.x + clampi(major * slot / refs, 0, maxi(0, major - 1)),
		rect.position.y + clampi(minor * index / maxi(1, index + 1), 0, maxi(0, minor - 1))
	)
	return Vector2(cell)


## The canonical index of `ref_id` among `room_id`'s refs, or 0. Read from the MAP rather
## than from the call order so a placement is a function of the authored content and not of
## which ref happened to be walked first.
static func _ref_slot(room_id: StringName, ref_id: String) -> int:
	var ids := _ref_ids(room_id)
	var index := ids.find(ref_id)
	return maxi(0, index)


## How many refs `room_id` authors. At least 1, so the slot arithmetic below can never
## divide by zero on a room whose refs have already been walked.
static func _ref_count(room_id: StringName) -> int:
	return maxi(1, _ref_ids(room_id).size())


## `room_id`'s spawn ref ids, sorted so the slot a ref occupies is a property of the
## content rather than of dictionary order. Bounded by the room's own authored refs.
static func _ref_ids(room_id: StringName) -> Array[String]:
	var ids: Array[String] = []
	for row in _refs_of(room_id):
		ids.append(String(row.get("ref_id", "")))
	ids.sort()
	return ids


## Every authored `actor_spawn_ref` in the active run, canonical order, as the map holds
## them. `[]` outside a run — the repo's does-not-exist vocabulary, never a fabricated row.
static func _refs_of(room_id: StringName) -> Array:
	var out: Array = []
	if _run == null or not _run.has_room(room_id):
		return out
	var room := _run.room(room_id)
	if room == null:
		return out
	out.append_array(room.actor_spawn_refs)
	return out


## The severe zones `room_id` authors, applied to `player`, as
## `{zone_id: EnvironmentField.apply`'s answer}. `{}` outside a run, for a room the map
## does not hold, and for a room that authors none.
##
## ## Why the zones are resolved against the PLAYER and not the room
##
## `EnvironmentField.apply` takes the actor and the cultivation path: qi, body and mind
## share ONE status id and resolve to three structurally different substrates off that one
## branch (ADR 0075). So "what standing here does" is a question about WHO is standing
## there, and the one actor a run's environment acts on at its entry point is the hero who
## entered it. The inhabitants standing in the same volume take the same hazard through
## combat resolution, which is the module's business and not this file's.
##
## ## And the run's WEATHER is published here, which is what makes it cost health
##
## The measured defect ADR 0213 closed was `calm 0.700000 == weathered 0.700000`: the
## weather was resolved by `DomainMap` and read by the minimap, and the hazard read the
## AUTHORED band because `EnvironmentField` holds no map. So the one composition-root
## line that owns both the map and the hero publishes the weather element onto the hero
## immediately before the zones resolve against it — a domain's storm now makes its
## furnace's band-2 residual into a band-3 one, and the minimap's `intensity` and the
## health the player loses are the same number.
static func _apply_zones(player: Actor, map: DomainMap, room_id: StringName) -> Dictionary:
	var out: Dictionary = {}
	if player == null:
		return out
	if map == null or room_id == &"" or not map.has_room(room_id):
		# No room is a place with no density, and NEUTRAL is PUBLISHED rather than
		# skipped: a hero who leaves a rich room must not keep its number through a key
		# nobody cleared (`CultivationGain.publish_density`'s own contract, ADR 0214/0926).
		CultivationGain.publish_density(player, CultivationGain.NEUTRAL)
		return out
	var room := map.room(room_id)
	if room == null:
		CultivationGain.publish_density(player, CultivationGain.NEUTRAL)
		return out
	# The room's ambient richness, published BEFORE the hazard loop and BEFORE the path
	# check below: density is a fact about the ROOM, not about which of its zones the
	# actor stands in or which path they cultivate (ADR 0214/0926).
	CultivationGain.publish_density(player, _room_density(room))
	# The weather is a property of the RUN, so it is published from here rather than
	# from a per-room verb — and `bind_shift_holder` does the publish AND the binding the
	# map's own `zones()` read model needs, so the minimap and the hazard cannot disagree
	# about the band (ADR 0213). `DomainMap` is re-derived from the player's state on
	# every `visit_room`, so this republishes on every room reached, which is correct:
	# a hero who walks into a second domain must not keep the first one's weather.
	map.bind_shift_holder(player)
	var path_id := EnvironmentField.primary_path(player)
	if not EnvironmentField.PATHS.has(path_id):
		# A hero who cultivates nothing cannot be taxed by a hazard, and `apply` refuses
		# an unknown path by name — so the refusal is RECORDED rather than swallowed.
		out[&"__no_path__"] = {"applied": false, "reason": "hero cultivates no path"}
		return out
	for zone in room.environment_zones:
		out[zone.zone_id] = EnvironmentField.apply(player, zone, path_id)
	return out


## The richest authored density in `room`, or `CultivationGain.NEUTRAL` when it authors
## no zone. A room is ONE place: the zones inside it are volumes of the same place, so
## the richest one answers for the room rather than an iteration order.
static func _room_density(room: RoomDef) -> float:
	var zones := room.environment_zones
	if zones.is_empty():
		return CultivationGain.NEUTRAL
	var density := zones[0].qi_density
	# Bounded `for` from the second zone: the first already seeded the answer.
	for index in range(1, zones.size()):
		density = maxf(density, zones[index].qi_density)
	return density


## The room graph the map screen's minimap draws: the laid-out rects, the corridor
## polylines, the POI markers derived from authored room tags, the severe zones with
## their mitigation levers, and the tier each discovered room promises (ADR 0073).
##
## `{}` outside a run — the repo's does-not-exist vocabulary, and a minimap of nothing
## must not read like a minimap of a room with no markers.
##
## ## Why this is a single read and not five
##
## `DomainMinimap.render` needs a `DomainMap`, which is a module type `ui/` may not
## name, and the facade caps at twelve verbs with no room for a thirteenth (api.gd
## says so). So the five reads a floor plan needs travel through here, and they travel
## TOGETHER because `DomainMinimap.render` is the one call that already produces all of
## them: asking it once and handing the payload over means this screen and the headless
## driver read the SAME dictionary, which is the contract `DomainMinimap`'s own docblock
## is written around.
static func minimap(player: Actor) -> Dictionary:
	var state := _active_map(player)
	if state == null:
		return {}
	return DomainMinimap.render(player, state)


## The active domain's rooms as primitives, canonical order, each carrying the tags its
## POI markers are derived from and the authored fixtures it holds — the room LIST, as
## distinct from the room GRAPH [method minimap] draws. Also `{}` outside a run.
static func rooms(player: Actor) -> Array[Dictionary]:
	if _active_map(player) == null:
		return [] as Array[Dictionary]
	return DomainApi.rooms(player)


## The seams the UI program gets, as plain callables.
##
## ## Why this exists rather than a direct `DomainApi` call
##
## `ui/` is a pure consumer (AGENTS.md, `tools/arch/rules.py`): it may reach a module
## only through that module's facade AND only if the module is declared in
## `rules.UI_MODULES`. `domain` is NOT, and `app/` is a private unit no screen may
## reference at all — so a screen calling `DomainBoot.enter_domain` directly is an
## arch violation on two counts, not a style preference. This is therefore the same
## shape `LootBridge` and `WorldPulseBridge` already established (ADR 0143): the
## composition root hands over verbs as `Callable`s and every module type stays on this
## side of the boundary. A screen bound to nothing reads empty rather than crashing.
##
## One bridge per screen instance and no state of its own: a field on the screen that
## the shell sets once is the whole contract, and `bind_bridge` is idempotent so the
## shell may call it after every navigation without stacking handlers.
static func bridge() -> DomainBridge:
	var seam := DomainBridge.new()
	seam.list_templates = Callable(DomainBoot, "_templates")
	seam.read_active = Callable(DomainBoot, "read_model")
	seam.enter = Callable(DomainBoot, "enter_domain")
	seam.leave = Callable(DomainBoot, "leave_domain")
	seam.visit = Callable(DomainBoot, "visit_room")
	seam.minimap = Callable(DomainBoot, "minimap")
	seam.rooms = Callable(DomainBoot, "rooms")
	seam.arm_fixture = Callable(DomainBoot, "arm_fixture")
	seam.inspect_fixture = Callable(DomainBoot, "inspect_fixture")
	seam.presence_fixture = Callable(DomainBoot, "presence_fixture")
	seam.attempt_fixture = Callable(DomainBoot, "attempt_fixture")
	seam.claim_fixture = Callable(DomainBoot, "claim_fixture")
	return seam


## The authored template catalogue, as primitives. A one-line forwarder so the bridge
## above binds a bare static function — the same "no typed lambda" rule `install`
## documents — rather than a closure.
static func _templates() -> Array[Dictionary]:
	return DomainApi.templates()


## Start a trap's telegraph, or fire it when the authored window has already elapsed.
##
## `delta` is the caller's, never a wall-clock read, because the module keeps no clock
## of its own (ADR 0089). A screen drives it with an explicit tick; a headless test
## drives it with the number it means.
##
## **NOT a UI verb any more.** ADR 0211 makes PRESENCE the only thing that may arm a
## trap; this stays because [method presence_fixture] ends in exactly this call, and a
## second time machine beside it is how the old `Arm` button became reachable.
static func arm_fixture(
	player: Actor, room_id: StringName, fixture_id: StringName, delta: float = 0.0
) -> Dictionary:
	return DomainFixtures.arm(player, room_id, fixture_id, delta)


## Read one fixture WITHOUT touching it: exactly what its telegraph publishes, and not
## one byte more. Free and non-mutating by construction (ADR 0211).
##
## This is what the screen's `Arm` button BECAME. A trap is worth reading before it is
## worth crossing, and reading it costs nothing — so the button is no longer a way to
## pay for having noticed a hazard.
static func inspect_fixture(
	player: Actor, room_id: StringName, fixture_id: StringName
) -> Dictionary:
	return DomainFixtures.inspect(player, room_id, fixture_id)


## The ONLY thing that may arm or fire a trap (ADR 0211): the caller passes where the
## actor IS and how long a frame was, never a verb.
##
## ## Why `at` is this method's parameter and not the module's to find
##
## `DomainFixtures._placed_tile` reads the tile `DomainSpawner` recorded, and the
## PLAYER is never spawned by `spawn_map` — so that record is empty for the hero and
## the position is the caller's to pass. A screen does not track one (the module
## publishes no intra-room position, ADR 0206), so the composition root does.
##
## ## Why the composition root owns the call
##
## A trap fires on a MOVEMENT STEP, so it must be called per-frame from the ONE tick
## caller, never from a screen's draw path: a `_process` in `ui/` would be a second
## clock, which is exactly what [method item_workbench_app.gd:_process]'s own docblock
## refuses. `delta` stays a parameter so a replay fires exactly as it was driven,
## matching `StatusRegistry.tick`.
static func presence_fixture(
	player: Actor, room_id: StringName, fixture_id: StringName, at: Vector2i, delta: float = 0.0
) -> Dictionary:
	return DomainFixtures.presence(player, room_id, fixture_id, at, delta)


## Every trap in the room the actor is standing in, offered to `presence` in turn.
##
## The TICK half of ADR 0211, and the seam the composition root actually calls: one
## call per frame from the one `_process` in the game, feeding every authored trap its
## `Vector2i` so a caller never has to know which room holds one. Each fixture is
## answered by its OWN `presence` call, so a trap outside the actor's tile refuses by
## name (`outside_the_footprint`) and contributes nothing — the loop is over the
## room's AUTHORED fixtures and terminates on that list, never on a countdown.
##
## Results are keyed by fixture id and carry only what a screen can render as
## primitives, so a caller can show a telegraph without naming a domain type.
static func tick_presence(
	player: Actor, room_id: StringName, at: Vector2i, delta: float = 0.0
) -> Dictionary:
	var out: Dictionary = {}
	if player == null or room_id == &"":
		return out
	for room in DomainApi.rooms(player):
		if StringName(room.get("room_id", "")) != room_id:
			continue
		for entry in room.get("fixtures", []):
			var fixture := entry as Dictionary
			var fixture_id := StringName(fixture.get("fixture_id", ""))
			if fixture_id == &"" or StringName(fixture.get("kind", "")) != DomainFixtures.KIND_TRAP:
				continue
			out[String(fixture_id)] = DomainFixtures.presence(
				player, room_id, fixture_id, at, delta
			)
		break
	return out


## Strike one node of a formation puzzle.
static func attempt_fixture(
	player: Actor, room_id: StringName, fixture_id: StringName, node_id: StringName
) -> Dictionary:
	return DomainFixtures.attempt(player, room_id, fixture_id, node_id)


## Open a treasure. Refused by name at every gate, in the order a player meets them.
static func claim_fixture(player: Actor, room_id: StringName, fixture_id: StringName) -> Dictionary:
	return DomainFixtures.claim(player, room_id, fixture_id)


## The active run's map, or null outside one. Private, so a caller can never hold a
## `DomainMap` past the run that produced it.
static func _active_map(player: Actor) -> DomainMap:
	if player == null:
		return null
	var state := player.get_module_data(DomainApi.MODULE_KEY)
	if not state is Dictionary or not (state as Dictionary).has("map"):
		return null
	return DomainMap.from_dict((state as Dictionary)["map"])
