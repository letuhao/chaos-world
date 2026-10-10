class_name ItemWorkbenchWiring
extends RefCounted

## The composition root's WIRING: the attach pipeline's phase list, the content and
## locale root overlays, the mod modules and the mod event subscriptions.
##
## Extracted from [ItemWorkbenchBody] when that half outgrew gdlint's `max-file-lines`
## ceiling. Every verb is static and holds no screen state. The arrays the body keeps
## for observation arrive as ARGUMENTS — an Array is a reference, so a skip recorded
## here is the same array a test reads off the app — and the one array the body
## ASSIGNS (`_mod_subscriptions`) is RETURNED instead, because a callee cannot
## reassign its caller's field.


## The attach steps as pipeline phases, in the EXACT order the hardcoded list
## produced: one phase per attach call, each `run` the call itself wrapped so the
## pipeline can invoke it with the actor. The phase NAME is the contract — a mod's
## attach hook is staked to it (ADR 0184 §6) — so the names are module ids, never
## positions.
##
## ## Why the order is load-bearing
##
##   - `soul`, `anchor`, `socket`, `loot`, `difficulty` FIRST: a soul and an anchor
##     live in an injected store rather than on the actor (ADR 0127, ADR 0146), so
##     these are READS of that store — which `_ready` has already published by the
##     time any of the three callers reaches this list.
##   - `race`, `bloodline` next: `Actor.from_dict` restores `module_data` but NEVER
##     a `StatProvider`, so the stat modifiers, base-attribute grants, affinities and
##     trait mirrors a race and an awakened lineage contribute are rebuilt only by the
##     attach. Nothing on the old list called it, so after ONE reload a stoneborn lost
##     its +15% `max_health` and a tideborn at 0.72 read awake while `bloodline_power`
##     answered 0.0 — with no error anywhere, because every reader that mattered was
##     reading the ledger (BL-0746). Both are idempotent BY CONSTRUCTION (each strips
##     its own prior contribution, then rebuilds from the ledger), so a fresh body the
##     creation flow already raced is net-zero. Early because every ledger below can
##     read a body plan, and `FertilityApi`'s gestation step does.
##   - `elements` after the enrolments: `attach` reads the highest realm off the
##     cultivation paths to write each element's multiplier, so refreshing it before
##     a path exists writes nothing — the silent realm degression ADR 0069 records.
##     `attach`, not the bare refresh: `Actor.from_dict` restores no provider at all,
##     and `attach` mounts it when absent and refreshes either way.
##   - `dual_cultivation` then `fertility` — fertility adds to bases dual cultivation owns.
##   - `items` before `set_bonus` — the projection is derived from equipment, so it must
##     never run before items.
##   - `techniques` after the items family — it resolves authored options through the
##     items vocabulary (ADR 0056).
##   - `social`, `destiny`, `event`, `quest` — ledgers. Destiny before event, because
##     an event's prize is a `DestinyApi.earn_fate` and that must land in a key that
##     exists.
##   - `npc` — injects the npc constructor and binds the roster to THIS actor.
##   - `domain` — the idempotent twin. `DomainBoot.install` injects `DomainSpawner`'s
##     actor constructor and the two items contacts `DomainFixtures` needs; both
##     default to refusing, so without this line a domain answers `no_inventory_bridge`
##     to every treasure and `spawn` can only return null.
##   - `combat`, then `technique_seams` — a seam is only correct once the module it
##     wires is complete, and `TechniquesApi.attach` is what makes the codex exist for
##     `TechniqueDelivery` to write into.
##   - `economy` LAST — the last thing installed is the most recently written, which
##     makes a failure here the newest thing a reader sees.
static func steps(bind_seams: Callable) -> Array[Dictionary]:
	return [
		{"name": &"soul", "run": func(a): SoulApi.attach(a)},
		{"name": &"anchor", "run": func(a): AnchorApi.attach(a)},
		{"name": &"socket", "run": func(a): SocketApi.attach(a)},
		{"name": &"loot", "run": func(a): LootApi.attach(a)},
		{"name": &"difficulty", "run": func(a): DifficultyApi.attach(a)},
		{"name": &"race", "run": func(a): RaceApi.attach(a)},
		{"name": &"bloodline", "run": func(a): BloodlineApi.attach(a)},
		{"name": &"elements", "run": func(a): ElementsApi.attach(a)},
		{"name": &"dual_cultivation", "run": func(a): DualCultivationApi.attach(a)},
		{"name": &"fertility", "run": func(a): FertilityApi.attach(a)},
		{"name": &"items", "run": func(a): ItemsApi.attach(a)},
		{"name": &"set_bonus", "run": func(a): SetBonusApi.attach(a)},
		{"name": &"techniques", "run": func(a): TechniquesApi.attach(a)},
		{"name": &"social", "run": func(a): SocialApi.attach(a)},
		{"name": &"destiny", "run": func(a): DestinyApi.attach(a)},
		{"name": &"event", "run": func(a): EventApi.attach(a)},
		{"name": &"quest", "run": func(a): QuestApi.attach(a)},
		# The conversation module (ADR 0862). Beside the other ledgers, and last of them:
		# it reads only its own `module_data` row and its own catalog, so it has no
		# ordering dependency on any of the above. It shipped with ZERO production
		# callers, so an actor never carried a dialogue row and `DialogueApi.start`
		# could not be reached from the shipped program at all - the shape BL-0663
		# closed for `quest`.
		{"name": &"dialogue", "run": func(a): DialogueApi.attach(a)},
		{"name": &"npc", "run": func(a): NpcBoot.install(a)},
		{"name": &"domain", "run": func(_a): DomainBoot.install()},
		{"name": &"combat", "run": func(a): CombatBoot.install(a)},
		{"name": &"technique_seams", "run": func(_a): bind_seams.call()},
		# Every organization of ANY kind (ADR 0271 / 0278). Beside `economy` and BEFORE
		# it, because the institution family is CONTENT plus REGISTRY rows and neither
		# depends on the economy's stores: `InstitutionBoot.install` discovers the
		# authored organizations and registers each KIND it finds. It shipped with
		# zero production callers, so a guild `.tres` a modder dropped into the family
		# was never read by anything the player runs.
		{"name": &"institutions", "run": func(_a): InstitutionBoot.install()},
		{"name": &"economy", "run": func(a): EconomyBoot.install(a)},
	]


## Build the boot's attach pipeline: one phase per attach step, in the order
## [method _attach_steps] declares. The pipeline holds no game state — only the order
## and the hook slots — so `app/`'s state scanners read it as wiring (ADR 0002). Hooks
## are added by the caller, AFTER the phases exist, so a hook staked to an unknown
## phase meets the pipeline's loud refusal rather than a silent skip.
static func pipeline(bind_seams: Callable) -> AttachPipeline:
	var pipeline := AttachPipeline.new()
	for step in steps(bind_seams):
		pipeline.add_phase(step["name"], step["run"])
	return pipeline


## Push content roots to their family catalogs (ADR 0184 §5). Each catalog
## scans its base root first, then the overlay roots in order, so mod content
## is visible. The `id_field` on each stack row is carried through to the
## catalog's scan. Families without overlay support are skipped — never a boot
## failure — but each is recorded in the caller's `unwired` list and announced with a
## `push_warning`, so the skip is never silent (audit Gap 5).
static func wire_content_roots(content_roots: Dictionary, unwired: Array[StringName]) -> void:
	unwired.clear()
	for family in content_roots:
		var stack: Array = content_roots[family]
		match String(family):
			&"items":
				Crafting.set_overlay_roots(stack)
			&"quest":
				QuestCatalog.set_overlay_roots(stack)
			&"event":
				EventCatalog.set_overlay_roots(stack)
			&"world":
				WorldLocationCatalog.set_overlay_roots(stack)
			&"npc":
				NpcCatalog.set_overlay_roots(stack)
			&"race":
				RaceCatalog.set_overlay_roots(stack)
			&"techniques":
				TechniqueCatalog.set_overlay_roots(stack)
			&"elements":
				ElementCatalog.set_overlay_roots(stack)
			&"item_options":
				OptionCatalog.set_overlay_roots(stack)
			&"sects":
				SectCatalog.set_overlay_roots(stack)
			&"sect_doctrines":
				SectDoctrineCatalog.set_overlay_roots(stack)
			&"fates":
				FateCatalog.set_overlay_roots(stack)
			&"destinies":
				FateCatalog.set_overlay_roots(stack)
			# Every organization of ANY kind, base and mod overlay together (ADR 0184 §5).
			# This is the ONE family row that declares no module, because its machinery is
			# `core`-owned and a module facade for a core type would be an indirection with no
			# second owner. Unwired, a mod's `content_roots: [{family: "institutions"}]` fell
			# to the `:` arm below: recorded in the caller's `unwired` list, announced, and ignored —
			# the silent skip ADR 0184's own acceptance criterion forbids (DEF-0326).
			&"institutions":
				InstitutionDefCatalog.set_overlay_roots(stack)
			&"statuses":
				StatusCatalog.set_overlay_roots(stack)
			&"soul_arrivals":
				SoulCatalog.set_overlay_roots(stack)
			&"sets":
				SetCatalog.set_overlay_roots(stack)
			&"nations":
				NationCatalog.set_overlay_roots(stack)
			&"nation_territories":
				NationCatalog.set_overlay_roots(stack)
			&"market_shops":
				ShopCatalog.set_overlay_roots(stack)
			&"clans":
				ClanCatalog.set_overlay_roots(stack)
			&"holdings":
				ResourceNodeCatalog.set_overlay_roots(stack)
			&"body_weapons":
				WeaponKindCatalog.set_overlay_roots(stack)
			&"body_material_arts":
				MaterialArtCatalog.set_overlay_roots(stack)
			&"body_injury_tuning":
				InjuryCatalog.set_overlay_roots(stack)
			&"bloodlines":
				BloodlineCatalog.set_overlay_roots(stack)
			&"anchors":
				AnchorCatalog.set_overlay_roots(stack)
			&"difficulty":
				DifficultyCatalog.set_overlay_roots(stack)
			_:
				# Family has no overlay-capable catalog — warn and record, never
				# skip silently (audit Gap 5).
				var family_name := StringName(family)
				unwired.append(family_name)
				push_warning(
					(
						"ItemWorkbenchBody: content family '%s' has no overlay catalog — skipped"
						% String(family_name)
					)
				)


## Layer every mod's string catalogs over the base ones (ADR 0918). Roots arrive in mod load
## order, so a later mod overrides an earlier one, and any of them overrides a core key — the
## only way a mod changes core wording is by shipping the same key, never by editing `src/`.
## Idempotent: `L.install_roots` records each root once, and a re-run of the boot pass is a
## no-op rather than a doubled translation.
static func wire_locale_roots(locale_roots: Array) -> void:
	L.install_roots(locale_roots)


## Attach mod modules after all base phases (ADR 0184). Each module name is
## looked up in the registry for its api path, then attached through the
## pipeline. Bounded by the module count — one pass, no loops.
static func attach_mod_modules(pipeline: AttachPipeline, actor: Actor, modules: Dictionary) -> void:
	if not bool(modules.get("ok", false)):
		return
	var registry: ModuleRegistry = modules.get("registry", null)
	if registry == null:
		return
	for name in modules.get("order", []):
		var module_name := String(name)
		var api_path := registry.api_path_of(module_name)
		if api_path != "":
			pipeline.attach_module(module_name, api_path, actor)


## Wire mod event subscriptions onto the events buses (ADR 0184). Each
## subscription is `{event_bus: String, event_name: String, callable: Callable,
## mod_id: String}`. The bus is resolved by class name — buses with a `shared()`
## accessor (NpcEvents, AuctionEvents, QuestEvents) use it; others get a fresh
## instance. Connections are guarded by `is_connected` so a repeated boot never
## double-connects (AGENTS.md).
##
## ## An unknown bus WARNS, and it stays a warning (ADR 0269)
##
## ADR 0242 decision 4 said an unknown bus "is skipped without crashing", which is
## still the BEHAVIOUR: a mod with one bad subscription must not take a boot down
## with it, and the tolerance is deliberate. What was missing is the other half of
## ADR 0184 decision 8 — never skip SILENTLY. A bus name that resolves to nothing
## means that mod's handler will never run, and until now nothing said so: a System
## whose entire economy is one subscription failed invisibly while every other
## subscription loaded cleanly.
##
## So each unresolvable bus is `push_warning`-ed NAMING both the bus and the mod
## that asked for it (stamped onto the row by `ModRuntime.finalize`, which is the
## only place that knows which mod a row came from), and recorded in
## the caller's `unresolved` list so the skip is observable from a test and not only from a log.
## One row is one pass — the loop drains the array it was handed, so it terminates.
static func wire_subscriptions(subscriptions: Array, unresolved: Array[Dictionary]) -> Array:
	register_shipped_buses()
	unresolved.clear()
	for sub in subscriptions:
		if not (sub is Dictionary):
			continue
		var bus_name := String(sub.get("event_bus", ""))
		var event_name := StringName(sub.get("event_name", ""))
		var callable: Callable = sub.get("callable", Callable())
		if bus_name == "" or event_name == &"" or not callable.is_valid():
			continue
		var bus := resolve_events_bus(bus_name)
		if bus == null:
			(
				unresolved
				. append(
					{
						"mod_id": String(sub.get("mod_id", "")),
						"event_bus": bus_name,
						"event_name": String(event_name),
					}
				)
			)
			push_warning(
				(
					"ItemWorkbenchBody: mod '%s' subscribed to unknown events bus '%s' (signal '%s')"
					% [String(sub.get("mod_id", "")), bus_name, String(event_name)]
				)
			)
			continue
		if not bus.is_connected(event_name, callable):
			bus.connect(event_name, callable)
	return subscriptions


## Resolve an events bus by class name. The factory is OPEN — no hardcoded
## dict. Resolution order:
##   1. Mod-registered custom buses (via `RegistrationContext.register_events_bus`)
##   2. `ClassDB.class_exists(bus_name)` — if the class exists, check for a
##      static `events()` or `shared()` accessor and call it; otherwise instantiate.
##   3. Return null for an unknown bus name (the caller skips it).
##
## ## A fresh instance is a DEAD subscription
##
## A bus handed out as `SomeEvents.new()` is a brand-new object per lookup: nothing
## holds the one a subscriber connects to and nothing emits on it, so `is_connected`
## reports the subscription connected FOREVER while no signal ever fires.
## Buses with a `shared()` accessor (NpcEvents, AuctionEvents, QuestEvents) return
## the process-wide instance a subscriber must reach.
static func resolve_events_bus(bus_name: String) -> RefCounted:
	# 1. Mod-registered custom buses take priority.
	if RegistrationContext.has_custom_bus(bus_name):
		return RegistrationContext.get_custom_bus(bus_name).call()
	# 2. Resolve by class name.
	if not ClassDB.class_exists(bus_name):
		return null
	# Check for a static events() or shared() accessor. `ClassDB` exposes no
	# `class_call`: the static-call spelling is `class_call_static` (boot repair).
	if ClassDB.class_has_method(bus_name, &"events"):
		return ClassDB.class_call_static(bus_name, &"events")
	if ClassDB.class_has_method(bus_name, &"shared"):
		return ClassDB.class_call_static(bus_name, &"shared")
	# 3. Otherwise instantiate.
	return ClassDB.instantiate(bus_name)


## Register the SHIPPED event buses with `RegistrationContext` by name, so a mod's
## subscription (`{event_bus: "NpcEvents"}`) reaches the process-wide bus it names.
##
## ## Why this is needed at all
##
## [method resolve_events_bus]'s fallback is `ClassDB.class_exists`, and that is FALSE
## for every GDScript global class — the engine's class database holds native classes
## only. So every shipped bus resolved to null, every subscription to one was skipped,
## and the boot warned `mod '…' subscribed to unknown events bus 'NpcEvents'` while
## doing exactly what it was told. This table is the ONE place that says which name
## reaches which accessor; `contracts/*_events.gd` owns the buses themselves.
##
## A mod's own registration WINS: it happens first, during that mod's manifest pass, and
## the `has_custom_bus` check is what keeps a shipped default from clobbering it.
##
## `Callable(Class, "static")` and never a lambda wrapping the call — a lambda over
## another script's static function is the access-violation shape `EconomyBoot.install`
## documents.
static func register_shipped_buses() -> void:
	var shipped := {
		"NpcEvents": Callable(NpcEvents, "shared"),
		"AuctionEvents": Callable(AuctionEvents, "shared"),
		"QuestEvents": Callable(QuestEvents, "shared"),
		"ConflictEvents": Callable(ConflictApi, "events"),
		"WorldEvents": Callable(EventApi, "events"),
		"DestinyEvents": Callable(DestinyApi, "events"),
		"NationEvents": Callable(NationApi, "events"),
		"SectEvents": Callable(SectApi, "events"),
		"HoldingsEvents": Callable(HoldingsApi, "events"),
	}
	for bus_name in shipped:
		if not RegistrationContext.has_custom_bus(String(bus_name)):
			RegistrationContext.register_events_bus(String(bus_name), shipped[bus_name])
