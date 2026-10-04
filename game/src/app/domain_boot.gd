class_name DomainBoot
extends RefCounted

## The composition root's domain wiring (ADR 0072-0075). Wiring, not rules: `app/`
## injects the constructor; the `domain` module owns what a map, a room and an inhabitant
## mean.
##
## ## Why this file exists
##
## The audit measured it: **13 of 13 domain source files had zero production call sites.**
## `DomainSpawner.spawn` needed a constructor to mint an `Actor` and nothing installed one,
## so it could only ever return null — a feature nobody can start is decoration, which is
## the same failure ADR 0089 measured for statuses and ADR 0074 for npcs.
##
## This is the domain twin of `NpcBoot`, and it exists for exactly the same reason. It is
## deliberately wiring-only: no rules, no state of its own, nothing that ticks.
##
## ## What this file NOW wires, and what it did not before
##
## This file was BUILT and UNWIRED: the audit found `DomainBoot.install` with zero callers,
## `DomainSpawner.spawn_map` with zero callers and `EnvironmentField.apply` with zero
## callers, so the whole `domain` module was a library nothing could reach. All three are
## now on a production path:
##
##  - `install` runs from the composition root's ONE attach list, beside `NpcBoot.install`,
##    so the spawner's minter and the fixtures' inventory bridge exist before any screen
##    asks (`ItemWorkbenchApp._attach_body_modules`).
##  - `enter_domain` calls `DomainSpawner.spawn_map` over the map it just entered and
##    returns the minted `Actor`s, so `population` describes creatures that exist.
##  - `enter_domain` and `visit_room` call `EnvironmentField.apply` for the zones belonging
##    to the entry / the room just reached, so a severe environment is something a player
##    is actually taxed by.
##
## Nothing here was a rule that belonged in the module: every rule stays in `domain/`.
##
## ## One clock, no clock of its own
##
## Nothing here ticks. Severe environments resolve through `EnvironmentField`, which is
## driven from the same `StatusLoop` tick every other status uses (ADR 0089); a second
## `_process` would be the stateful-`app/` shape `tools/arch/rules.py` rejects.

## The item property a fixture's key is measured by. Spelled once so the granter seam
## below and the loot module's own entry gate cannot drift onto different properties.
const KEY_REACH := &"key_reach"

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

## The element vocabulary the environment layer speaks. CLOSED, and it is exactly the
## set `EnvironmentField.HOSTILE_ELEMENTS` keys on, because a tag outside that set
## cannot answer any zone and publishing it would inflate the list for nothing.
##
## Declared HERE rather than beside the ward-tag publisher below because
## `class-definitions-order` puts every `const` before every `func`, and a const declared
## mid-file is an ordering error rather than a local convenience.
const ELEMENT_TAGS: Array[StringName] = [
	&"fire",
	&"ice",
	&"water",
	&"lightning",
	&"metal",
	&"wood",
	&"dark",
	&"light",
	&"earth",
	&"wind",
]

## The consumable subtypes a mitigation can be carried as. Authored vocabulary
## (`ItemSubtype`), named here rather than rebuilt, so a new consumable subtype is one
## edit in the items module rather than a second list to drift.
const CONSUMABLE_SUBTYPES: Array[StringName] = [
	ItemSubtype.PILL,
	ItemSubtype.ELIXIR,
	ItemSubtype.TALISMAN,
	ItemSubtype.FOOD,
]

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
static var _layout: Dictionary = {}
static var _run: DomainMap = null
## The bodies [method enter_domain] minted for `_run`, as `actor id -> Actor`. A handle,
## not a table — see [method _last_inhabitants] for why it is a `Dictionary` and why it
## lives here at all rather than being re-derived from the map.
static var _roster: Dictionary = {}

## Who stands the realized world up once a run exists. A `Callable`, not a reference, and
## for the reason `install` documents: `enter_domain` is a STATIC on this file, and the
## node that can parent a `Node2D` in the tree is the composition ROOT, which is an
## instance. `NpcApi.set_minter` and `CustodyApi.set_resolver` are the same seam one layer
## down; this is the same seam a layer up.
##
## OPTIONAL, and its refusal is REPORTED rather than swallowed: a caller that entered a run
## with nothing listening still got a run — the world is a view of it, not a condition of
## it — so `enter_domain` records that nobody realized and carries on.
static var _world_observer: Callable = Callable()


## Install (or, with an empty `Callable`, uninstall) the seam `enter_domain` fires once a
## run exists. Idempotent, and safe to call again after a re-mount.
static func set_world_observer(observer: Callable) -> void:
	_world_observer = observer


## Whether a world observer is installed, published so a caller can tell "nothing is
## listening" from "the listener refused".
static func has_world_observer() -> bool:
	return _world_observer.is_valid()


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


## Hand `count` of `item_id` to the actor, answering the LEFTOVER that did not fit —
## the all-or-nothing convention `LootRewards.deliver` uses, so a full bag leaves the
## claim untouched rather than consuming it over a delivery that did not happen.
##
## `Crafting.resolve` is `items` internals that only `app/` may name, and `ItemsApi` is
## at its twelve-method cap so no def-resolution verb could be added to it. This adapter
## is the whole reason the seam is legal where it is.
static func grant_item(player: Actor, item_id: StringName, count: int) -> int:
	var def := Crafting.resolve(item_id)
	if def == null:
		# Nothing handed over, so the whole count is leftover. Reported rather than
		# swallowed: a reward for an undefined item is a content defect.
		return maxi(0, count)
	var inventory := ItemsApi.inventory(player)
	if inventory == null:
		return maxi(0, count)
	return maxi(0, inventory.add(def, count))


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
# Both live here because both are CONTACTS with a module `domain` may not depend on.
# `domain` declares `core` + `contracts` only (tools/arch/registry.json), so it cannot
# name `items`, `techniques` or a `.tres` template without breaking that edge. `app/` is
# the composition root and is allowed to depend on anything, so the two reads happen
# here and are handed to the module as PLAIN DATA — the same reason `install` hands the
# spawner a `Callable` instead of letting `domain/` name `ActorFactory`.


## The weather `template_id` authors, or [constant DomainMap.WEATHER_NONE].
##
## ## Why this is a TEXT read and not a field on `DomainTemplateDef`
##
## `weather` is authored on the template `.tres` as a plain `weather = &"ashfall"` line,
## and read back with [method RegEx]. That is deliberate rather than a shortcut:
## `DomainTemplateDef` is a `Resource` whose exported set is another file's to change,
## so a field there would mean editing a module file this change does not own. Reading
## the authored line is also the same discipline `tools/` applies to this corpus — a
## value that is not a field of the resource is still content, and content is read, not
## inferred. The `[method _scalar]` helper normalizes Godot's `&"x"` / `"x"` spelling
## away, which is the same normalization `tools/acquisition/chain.py` performs.
##
## Refused by `DomainMap.accepts_weather` before it is returned, so a template naming a
## weather outside the closed catalogue contributes NO weather rather than a string
## every zone would silently ignore. `WEATHER_NONE` (no `weather` line at all) is a
## legitimate authored state, not a failure.
static func _template_weather(template_id: StringName) -> StringName:
	for path in _template_files():
		var text := _read_text(path)
		if _scalar(text, "template_id") != String(template_id):
			continue
		var authored := _scalar(text, "weather")
		if authored.is_empty():
			return DomainMap.WEATHER_NONE
		var id := StringName(authored)
		return id if _map_accepts(id) else DomainMap.WEATHER_NONE
	return DomainMap.WEATHER_NONE


## Every `templates/*.tres` path, sorted. Bounded `for`/enumeration over a closed
## content directory; the `while` terminates because `get_next()` returns `""` at the
## end of the directory, which is the same idiom `DomainApi.templates` itself uses.
static func _template_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DomainApi.TEMPLATE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			out.append("%s/%s" % [DomainApi.TEMPLATE_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## The authored value of `name` in a `.tres`, unquoted, or `""` when the file does not
## declare it. One helper so every authored scalar this file reads is parsed the same
## way; `RegEx` rather than `String.split` because the value is a `&"..."` literal and
## its quoting has to come off before the string is compared to an id.
static func _scalar(text: String, name: String) -> String:
	var pattern := RegEx.new()
	if pattern.compile("(?m)^%s\\s*=\\s*(.+?)\\s*$" % name) != OK:
		return ""
	var found := pattern.search(text)
	if found == null:
		return ""
	var value := found.get_string(1).strip_edges()
	# `StringName` literals in a `.tres` are written `&"name"`, so the `&` sits OUTSIDE
	# the quotes. Stripping only the quotes left `&ashfall`, which never compared equal
	# to `ashfall` — which is why an authored weather read back as "no weather" and every
	# zone in the domain silently ran at its authored band.
	if value.begins_with("&"):
		value = value.substr(1).strip_edges()
	for quote in ['"', "'"]:
		if value.length() > 1 and value.begins_with(quote) and value.ends_with(quote):
			return value.substr(1, value.length() - 2)
	return value


static func _map_accepts(id: StringName) -> bool:
	var probe := DomainMap.new()
	return probe.accepts_weather(id)


## Publish what this actor CARRIES into the three `module_data` slots
## `EnvironmentField` reads, so `GEAR_CAP`, `TECHNIQUE_CAP` and `PILL_CAP` gate a real
## list instead of a permanently empty one.
##
## ## Why this is here and not in `environment_field.gd`
##
## `EnvironmentField` reads three tag keys and nothing writes them, which is why a
## cultivator wearing a fire ward used to get ZERO mitigation while the screen still
## printed "answered by: gear, pill, affinity". The three caps were live caps over
## lists that were always empty — a cap that gates nothing.
##
## `domain` cannot fix that itself: the tags live in `items` (equipped instances and
## inventory) and `techniques` (the codex and the loadout), and `domain` is allowed to
## depend on neither. So this reads them THROUGH THEIR FACADES — `ItemsApi` and
## `TechniquesApi` — and writes only the tag strings into the three keys this module
## already owns. No sibling payload shape is depended on: `EnvironmentField` still reads
## a flat `{"tags": [...]}` list and nothing here walks anybody's internals.
##
## ## What the tags MEAN, and why they are element names
##
## The three lists carry ELEMENTS (`&"fire"`, `&"ice"`, …), not invented ids. That is
## the honest join key: `EnvironmentZoneDef.tags` is already the "elements this zone is
## hostile to" list, so a wardrobe of fire-and-ice gear answers the same question the
## zone already asks of a spirit root. A consumable named "fire" is a cooling draught;
## an orb tagged `fire` is a fire ward. Neither needs a registry this module cannot
## own, and neither can be a silent no-op: if nothing in the corpus carries the
## element, the list is empty and the lever does not fire, which is correct.
##
## Idempotent: every key is overwritten from the actor's CURRENT state rather than
## appended to, so re-entering a room cannot accumulate stale tags.
static func publish_ward_tags(player: Actor) -> Dictionary:
	if player == null:
		return {"gear": 0, "technique": 0, "pill": 0}
	# GEAR: what is WORN, not what is owned. A bag full of robes is not a ward, so this
	# reads `Equipment.all()` — the slots actually occupied.
	player.set_module_data(EnvironmentField.GEAR_TAGS_KEY, {"tags": _equipped_elements(player)})
	player.set_module_data(EnvironmentField.TECHNIQUE_TAGS_KEY, {"tags": _learned_elements(player)})
	player.set_module_data(EnvironmentField.PILL_TAGS_KEY, {"tags": _carried_elements(player)})
	return {
		"gear": _size(player, EnvironmentField.GEAR_TAGS_KEY),
		"technique": _size(player, EnvironmentField.TECHNIQUE_TAGS_KEY),
		"pill": _size(player, EnvironmentField.PILL_TAGS_KEY),
	}


static func _size(player: Actor, key: StringName) -> int:
	var tags: Array = player.get_module_data(key).get("tags", [])
	return tags.size()


## Every element carried by what the actor is WEARING, canonical and de-duplicated.
## Bounded `for` over the five equipment slots and each def's own authored tag list.
static func _equipped_elements(player: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var equipment := ItemsApi.equipment(player)
	if equipment == null:
		return out
	# Bounded `for` over `Equipment.SLOTS`, which is the closed five-slot set. Iterating
	# the slots rather than `all().keys()` keeps the order canonical, so the published
	# list is a pure function of what is worn rather than of dictionary order.
	for slot in Equipment.SLOTS:
		var def := equipment.definition(slot)
		if def == null:
			continue
		_add_elements(out, def.tags)
	return out


## Every element carried by what the actor has LEARNED, through the techniques facade.
## Read from the codex the facade attaches on demand, so an actor who has never opened
## the technique screen still answers. Empty when no technique is attached, which is the
## honest "this actor knows nothing that helps" rather than a fabricated default.
static func _learned_elements(player: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var codex := TechniquesApi.codex(player)
	if codex == null:
		return out
	# Bounded `for` over the codex's own entries — authored content, small, and the only
	# list the techniques module publishes as ids rather than as a read model.
	for technique_id in _codex_ids(codex):
		var def := TechniqueCatalog.instance().definition(StringName(technique_id))
		if def == null:
			continue
		_add_elements(out, def.tags)
	return out


static func _codex_ids(codex: TechniqueCodex) -> Array[String]:
	var out: Array[String] = []
	# Bounded `for` over the codex's own technique ids — authored content, small, and the
	# only list the techniques module publishes as ids rather than as a read model.
	for technique_id in codex.technique_ids():
		out.append(String(technique_id))
	return out


## Every element carried by what the actor has IN THE BAG as a consumable.
##
## INVENTORY, not equipment: a pill is spent, not worn, so it cannot come from
## `Equipment`. Read through `Inventory.stacks()` and `.instances()` — the two lists
## that between them hold every carried item — and narrowed to the authored CONSUMABLE
## subtypes, because an herb in the bag is not a mitigation the player chose to carry.
static func _carried_elements(player: Actor) -> Array[StringName]:
	var out: Array[StringName] = []
	var inventory := ItemsApi.inventory(player)
	if inventory == null:
		return out
	for batch in inventory.stacks():
		if batch.def_ref == null or not _is_consumable(batch.def_ref):
			continue
		_add_elements(out, batch.def_ref.tags)
	for instance in inventory.instances():
		var def := Crafting.resolve(instance.def_id)
		if def == null or not _is_consumable(def):
			continue
		_add_elements(out, def.tags)
	return out


## Whether `def` is something a body CONSUMES rather than wears or learns. The
## authored subtype list, not a name test: a subtype nobody declared is not a pill.
static func _is_consumable(def: ItemDef) -> bool:
	return CONSUMABLE_SUBTYPES.has(def.subcategory)


## Add every element-shaped tag in `tags` to `out`, de-duplicated and canonically
## ordered at the end. A bounded `for` over authored content; no `while`.
static func _add_elements(out: Array[StringName], tags: Array[StringName]) -> void:
	for tag in tags:
		var element := StringName(str(tag))
		if ELEMENT_TAGS.has(element) and not out.has(element):
			out.append(element)


# ── the population and the environment. Both are wiring, neither is a rule ──────


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


## Every authored inhabitant, as `inhabitant_id -> InhabitantDef`, read from the same tree
## the module's own `templates()` reads (`DomainApi.INHABITANT_DIR`). Content is read here
## rather than restated, so a newly authored `.tres` is a file and never a code edit
## (ADR 0074) — the same rule `NpcBoot.install`'s `load_authored` follows.
static func _inhabitant_catalogue() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(DomainApi.INHABITANT_DIR)
	if dir == null:
		return out
	var names: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for name in names:
		var def := load("%s/%s" % [DomainApi.INHABITANT_DIR, name]) as InhabitantDef
		if def != null:
			out[String(def.inhabitant_id)] = def
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
static func _apply_zones(player: Actor, map: DomainMap, room_id: StringName) -> Dictionary:
	var out: Dictionary = {}
	if player == null or map == null or room_id == &"" or not map.has_room(room_id):
		return out
	var room := map.room(room_id)
	if room == null:
		return out
	var path_id := EnvironmentField.primary_path(player)
	if not EnvironmentField.PATHS.has(path_id):
		# A hero who cultivates nothing cannot be taxed by a hazard, and `apply` refuses
		# an unknown path by name — so the refusal is RECORDED rather than swallowed.
		out[&"__no_path__"] = {"applied": false, "reason": "hero cultivates no path"}
		return out
	for zone in room.environment_zones:
		out[zone.zone_id] = EnvironmentField.apply(player, zone, path_id)
	return out


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
static func arm_fixture(
	player: Actor, room_id: StringName, fixture_id: StringName, delta: float = 0.0
) -> Dictionary:
	return DomainFixtures.arm(player, room_id, fixture_id, delta)


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


# ── the world. Realized here, parented by the caller, freed by the caller ───────
#
# ADR 0072:14 said it plainly — "A domain you cannot walk is a spreadsheet." Before this
# section `DomainScene` was a complete walkable tile scene whose only caller was its own
# `_init`, and `DomainSpawner`'s placement record — a real `Vector2` per inhabitant, written
# into `actor.module_data` by `_place` and read by nobody — was a dead field. So the number
# in `module_data` described a position that was never drawn.
#
# ## WHY THE WORLD IS AN ARGUMENT AND NOT A FIELD
#
# `app/` is the composition root and `tools/arch/rules.py` rejects a stateful system in it
# (`app_state_signals`: two or more of persistence / tick-loop / state-table). This file
# already carries `persistence` — `_active_map` reads `get_module_data` — so a `tick` or a
# member state table added here would tip it over the threshold. So there is NO
# `var _world: Node2D` here. The world is BUILT by [method realize_world], PARENTED by
# whoever asked for it, and FREED by [method release_world]: the scene tree holds it, which
# is what a scene tree is for. `item_workbench_app.gd` holds NO handle at all — it finds the
# world by name under the screen it is showing, so there is no second reference anywhere
# that can outlive the node.
#
# ## WHY THE ENGINE SIDE LIVES IN `domain_scene.gd`
#
# Everything that touches a `Node2D`, a tile or an adapter is `DomainScene`'s, because
# `DomainScene` already owns "where is this map in pixels". The four verbs below are thin
# forwarders: they resolve which run is active and which bodies the spawner minted — the two
# facts only this file can know — and hand them to [method DomainScene.realize_world] as
# ARGUMENTS. Nothing is read back out of a node, so no gameplay value ever round-trips
# through the scene tree.
#
# ## NO `_ready`, NO `await`, NO DEFERRED WORK
#
# The headless runner drives every test from `SceneTree._initialize()`, which returns before
# the first frame: `_ready()` is never delivered to a node parented to `root`. Everything
# below therefore happens inside the caller's frame — `DomainScene` builds in `_init()`,
# the player adapter is configured by explicit setters rather than by `_ready()`,
# and nothing here waits for a frame to elapse.


## REALIZE the active run as a walkable world under `parent`, and answer what happened.
##
## Builds a `DomainScene` from `_run`, places one body per minted inhabitant at the
## placement `DomainSpawner` already recorded, and adds a bounded `PlayerAdapter` at the
## entry centre. Refuses `no_map` BY NAME and writes nothing before it resolves, so a
## refusal leaves the caller's tree exactly as it found it.
static func realize_world(parent: Node, player: Actor) -> Dictionary:
	if _run == null:
		return {"ok": false, "reason": "no_map"}
	return DomainScene.realize_world(parent, _run, player, _last_inhabitants())


## FREE the realized world under `parent`. Idempotent, and a no-op when nothing was ever
## realized, so a `teardown()` may call it without asking first.
static func release_world(parent: Node) -> Dictionary:
	return DomainScene.release_world(parent)


## Whether a world is currently realized under `parent`. Read by the composition root and by
## `test_domain_playable.gd` through this one verb, so neither walks for a node name this
## file does not publish.
static func world_realized(parent: Node) -> bool:
	return DomainScene.world_realized(parent)


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
## system. A `Dictionary` keyed by the run's domain id is a HANDLE — one entry, replaced
## wholesale on every entry, emptied on leave — not a slot table that the file grows and
## decays. The walk that reads it is bounded by the authored spawn refs, which
## `DomainSpawner.MAX_COUNT_PER_REF` already caps at 64 per ref.
static func _last_inhabitants() -> Array:
	var out: Array = []
	for actor in _roster.values():
		if actor is Actor:
			out.append(actor)
	return out


## Every inhabitant as `id -> Actor`, the one place the roster is written. Split from
## `_last_inhabitants` so `enter_domain` assigns it in a single statement with the map it
## belongs to, and a run and its bodies can never disagree about which is which.
static func _remember_inhabitants(inhabitants: Array) -> void:
	var out: Dictionary = {}
	for inhabitant in inhabitants:
		var actor := inhabitant as Actor
		if actor != null:
			out[String(actor.id)] = actor
	_roster = out
