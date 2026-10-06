class_name RegistrationContext
extends RefCounted

## The locked registration surface a mod's entry point calls (ADR 0184 §6).
## `ModLoader` hands one context per discovered mod to that mod, and the seams
## are the ONLY way a mod can touch the game: a mod cannot grow this interface
## and cannot reach a boot phase outside of it.
##
## W3 wiring: each seam now calls the real engine. `add_content_root` stores a
## CatalogOverlay-shaped row per family; `register_module` forwards to the
## shared ModuleRegistry the loader injects; `register_screen` forwards to the
## static ScreenRegistry route table; `add_attach_hook` and `subscribe` store
## for the app to fold into the AttachPipeline and the events bus after
## `ModRuntime.finalize`. The ctx never names the pipeline or the bus — those
## are app-owned, and the layer rules keep `modules/mods` off both.
##
## ## The SIXTH seam, and the hole it closes (ADR 0275)
##
## §6 locked this surface at five seams, and a mod's STAT and RESOURCE vocabulary
## was not one of them. That is the hole the doctrine contract names in its own
## docstring: `DoctrineRule.resource_ids` reads pool ids nothing validates, and
## `CultivationPathDef.ensure_resources` mints a pool for ANY id, so a typo'd pool
## reaches its read site as a silent `0.0`. `UNDECLARED_POOL` does not close it —
## that reason catches a System spending a pool it did not itself DECLARE, which is
## a different question from "does this id exist at all".
##
## [method declare_stats] is the sixth seam: ONE block carrying a mod's stat rows
## and the pools they read. A seam rather than a manifest field because the ids
## have to be refusable at the point they enter the game, and the locked surface
## is the only point a mod cannot route around. See ADR 0275.

## The file a mod's stat/resource declarations live in, beside its `mod.json`.
const DECLARATION_FILE := "stats.json"
##
## ## It RECORDS; [class DeclarationBlock] DECIDES
##
## The seam hands the block to `DeclarationBlock.parse` and stores what comes back
## accepted. A refused block leaves NO partial state, because nothing is written
## until every row has passed — and a locked surface has no rollback verb, so a
## seam that recorded-as-it-validated would leave half a mod registered.

## ## The one reason the SEAM adds, and why the parser cannot have it
##
## `DeclarationBlock` validates a block against ONE mod's `resources[]`, so it
## cannot see that a DIFFERENT mod already declared the same pool — a single-mod
## pure function has no cross-mod view. Ownership is a property of the whole boot,
## so it is settled in `ModRuntime.finalize`, which knows load order. It is
## deliberately NOT in [constant DeclarationBlock.REASONS]: a caller validating a
## refusal against that set would treat a cross-mod collision as impossible.
const DUPLICATE_RESOURCE := "duplicate_resource"

## Mod-registered custom events buses (ADR 0184 §6). A mod that ships its own
## events bus class registers it here so `_resolve_events_bus` can find it
## without a hardcoded factory dict. The callable returns the bus instance.
static var _custom_buses: Dictionary = {}

## Which mod this context belongs to. Set by the loader, read by the record.
var mod_id: String = ""

## Per-family content roots: {family: Array[{dir, owner, declared_overrides}]}.
## The row shape is CatalogOverlay's stack row, so `ModRuntime.finalize` merges
## ctxs in load order without re-shaping.
var content_roots: Dictionary = {}

## Module declarations recorded through `register_module`, with the registry's
## verdict appended so a caller can see what the runtime accepted.
var modules: Array[Dictionary] = []

## Attach hooks staked by phase name; the app folds them into the AttachPipeline
## after finalize (the pipeline is app-owned, so the ctx never names it).
var attach_hooks: Array[Dictionary] = []

## Screen rows recorded through `register_screen` (also forwarded to the static
## ScreenRegistry, which is the route table the ScreenStack mounts by).
var screens: Array[Dictionary] = []

## Event subscriptions declared by the mod; the app folds them onto the bus.
var subscriptions: Array = []

## Accepted stat rows from [method declare_stats]. Replaced, never appended to, on
## a second call — one block per mod is the contract, and the replace is what makes
## the seam idempotent: `ModBoot.run()` calls `ModRuntime.finalize` on every boot,
## so an appending seam would double every row on the second pass and report the
## mod's own declarations back to it as collisions.
var stat_declarations: Array[Dictionary] = []

## The pools this mod brought in its own `resources[]`. The JSON answer to
## `CultivationPathDef.resource_ids`, and what `ensure_resources` mints from.
var declared_resources: Array[StringName] = []

## Every named refusal [method declare_stats] recorded. A first-class list rather
## than a log line because GDScript cannot intercept `push_error`, and a refusal
## nobody can read back is a refusal nobody can test.
var declaration_refusals: Array[Dictionary] = []

## The manifest this context was stamped from, so a seam can read the mod's
## declared overrides without the loader re-passing them per call.
var _manifest: Dictionary = {}

## The runtime module registry every mod in one boot shares. Injected by the
## loader; a context made outside a loader pass (tests) builds its own.
var _registry: ModuleRegistry = null

## Shared mod-to-mod API registry: {mod_id: {api_name: api_object}}. Injected
## by the loader so one mod's context can resolve another mod's registered API.
var _api_registry: Dictionary = {}


func _init(
	id: String = "",
	manifest: Dictionary = {},
	registry: ModuleRegistry = null,
	api_registry: Dictionary = {}
) -> void:
	mod_id = id
	_manifest = manifest
	_registry = registry if registry != null else ModuleRegistry.new()
	_api_registry = api_registry


## Declare one content family rooted at `dir` (e.g. items, recipes). The row
## is stored per family in CatalogOverlay's stack shape so finalize merges ctxs
## in load order without re-shaping. A mod may not register content outside its
## declared roots — enforced when the seams are wired.
##
## `id_field` names the def property holding this family's id when it is not
## "id" (e.g. WorldLocationDef's "location_id", NpcDef's "npc_id"). The value
## is carried on the stack row so CatalogOverlay.merge and the catalog's own
## scan read the correct property per root.
func add_content_root(family: String, dir: String, id_field: String = "id") -> Array[Dictionary]:
	var row := {
		"dir": dir,
		"owner": mod_id,
		"declared_overrides": _manifest.get("overrides", []),
		"id_field": id_field,
	}
	if not content_roots.has(family):
		content_roots[family] = []
	var list: Array = content_roots[family]
	list.append(row)
	# A Dictionary value reads back as an untyped Array, so the typed return is
	# built as a copy — the seam's contract is Array[Dictionary], not Variant.
	var out: Array[Dictionary] = []
	for entry in list:
		out.append(entry)
	return out


## Register one module facade: the `api.gd` a sibling module may reference,
## with the module ids it depends on. `provides` declares what the module
## offers (e.g. ["cultivation_path"]); `seed_dir` overrides the default seed
## directory for a cultivation path. Forwards to the shared ModuleRegistry and
## records the declaration with the registry's verdict.
func register_module(
	name: String,
	api_gd_path: String,
	deps: Array,
	provides: Array[String] = [],
	seed_dir: String = ""
) -> Array[Dictionary]:
	var verdict := _registry.register(name, api_gd_path, deps, provides, seed_dir)
	(
		modules
		. append(
			{
				"name": name,
				"api_gd": api_gd_path,
				"deps": deps,
				"provides": provides,
				"seed_dir": seed_dir,
				"ok": verdict.get("ok", false),
				"reason": verdict.get("reason", ""),
			}
		)
	)
	return modules


## Hook a boot phase. The ctx stores the phase name and Callable; the app
## registers them into the AttachPipeline after finalize (the pipeline is
## app-owned, so the ctx never names it).
func add_attach_hook(phase: String, hook: Callable) -> Array[Dictionary]:
	attach_hooks.append({"phase": phase, "hook": hook})
	return attach_hooks


## Register one screen route. Forwards to the static ScreenRegistry (the route
## table the ScreenStack mounts by) and records the row.
func register_screen(id: String, scene: String, label: String) -> Array[Dictionary]:
	ScreenRegistry.register(id, scene, label)
	screens.append({"id": id, "scene": scene, "label": label})
	return screens


## Subscribe to an events bus. The subscription shape is
## `{event_bus: String, event_name: String, callable: Callable}` where
## `event_bus` names the bus class (e.g. "NpcEvents"), `event_name` is the
## signal to connect, and `callable` is the handler. The app folds the
## declaration onto the bus after finalize; the ctx never names the bus.
func subscribe(subscription: Dictionary) -> Array:
	subscriptions.append(subscription)
	return subscriptions


## Register a custom events bus type (ADR 0184 §6). A mod that ships its own
## events bus class registers it here so `_resolve_events_bus` can find it
## without a hardcoded factory dict. The callable returns the bus instance
## (e.g. `func(): return MyEvents.shared()`). Later registrations overwrite
## earlier ones, so the last mod to register a name wins.
static func register_events_bus(name: String, factory: Callable) -> void:
	_custom_buses[name] = factory


## Whether a custom events bus is registered under `name`.
static func has_custom_bus(name: String) -> bool:
	return _custom_buses.has(name)


## The factory callable registered for `name`, or null when none is registered.
static func get_custom_bus(name: String) -> Callable:
	return _custom_buses.get(name, Callable())


## THE SIXTH SEAM (ADR 0275). Declare this mod's stat rows and the pools they
## read, in ONE `block`:
## `{stats: [{id, op, resource, zero_baseline}], resources: [{id}]}`.
##
## Returns `DeclarationBlock.parse`'s `{ok, reason, detail, stats, resource_ids,
## refusals}`. `ok` is true only when NOTHING was refused, and `refusals` names
## every offender rather than the first — a mod with three typos is one author, and
## telling them about one of them costs a round trip.
##
## REPLACES this mod's declarations rather than appending; see the note on
## [member stat_declarations] for why that is load-bearing rather than cosmetic.
func declare_stats(block: Dictionary) -> Dictionary:
	var parsed := DeclarationBlock.parse(block, mod_id)
	# Each list is copied into a TYPED local and then assigned, because a Dictionary
	# value reads back as an untyped `Array` — the same trap `add_content_root` records
	# — and assigning that to `Array[Dictionary]` is a runtime error, not a warning.
	# The consequence is that `DeclarationBlock` cannot hand over typed arrays at all:
	# anything it returned inside a Dictionary would arrive untyped, so the conversion
	# has to happen here where the destination types are known.
	var rows: Array[Dictionary] = []
	var pools: Array[StringName] = []
	if bool(parsed["ok"]):
		# ONLY on a clean parse. The parser reports every good row alongside every bad
		# one so the author sees all of them at once, and taking the good rows would
		# leave half a mod registered behind a refused block — which is the partial
		# write the class docblock claims cannot happen, and which a locked surface has
		# no verb to undo. So a refusal records nothing at all, and the refusals below
		# are the whole of what the mod leaves behind.
		for row in parsed["stats"] as Array:
			rows.append(row)
		for pool_id in parsed["resource_ids"] as Array:
			pools.append(StringName(pool_id))
	stat_declarations = rows
	declared_resources = pools
	# The refusals need the same copy: `parsed["refusals"]` is an untyped `Array` and
	# assigning it straight to `Array[Dictionary]` is a runtime error. Every one of
	# these three reads out of the returned Dictionary needs it — that is the whole
	# cost of returning through a Dictionary, and it is paid three times here.
	var refusals: Array[Dictionary] = []
	for refusal in parsed["refusals"] as Array:
		refusals.append(refusal)
	declaration_refusals = refusals
	return parsed


## Expose this mod's API object under `api_name` so other mods can find it
## through [method get_mod_api]. The api_object is any RefCounted or Object the
## mod wants to share (e.g. a facade, a data table). Later registrations by the
## same mod overwrite earlier ones under the same name.
func register_mod_api(api_name: String, api_object: Object) -> void:
	if not _api_registry.has(mod_id):
		_api_registry[mod_id] = {}
	(_api_registry[mod_id] as Dictionary)[api_name] = api_object


## Resolve another mod's registered API. Returns the api_object the target mod
## registered under `api_name`, or null when the target mod is not loaded, has
## not registered that api_name, or the target mod's version is below the
## `min_version` declared in this mod's `integrations[]` manifest entry.
func get_mod_api(mod_id: String, api_name: String) -> Object:
	if not _api_registry.has(mod_id):
		return null
	var apis: Dictionary = _api_registry[mod_id]
	if not apis.has(api_name):
		return null
	return apis.get(api_name)


## Check whether a newer version of this mod is available. Returns
## `{has_update: bool, latest_version: String, download_url: String}`.
## Currently a stub: the HTTP check is deferred, so this always reports
## `{has_update: false, latest_version: "", download_url: ""}`.
func check_for_update() -> Dictionary:
	return {"has_update": false, "latest_version": "", "download_url": ""}


## The pools this mod declared, in DECLARATION order. Hand this to a
## `CultivationPathDef.resource_ids` and `ensure_resources` mints the pool — which
## is what makes the vocabulary genuinely CLOSED rather than merely narrowed: an id
## is legal because a declaration introduced it, and a typo introduced nothing.
func declared_resource_ids() -> Array[StringName]:
	return declared_resources


## The directory this mod's `mod.json` was found in, or `""` for a context built
## outside a loader pass (a test, a direct `ModsApi.build_context`). `""` is what
## makes [method declaration_path] a no-op rather than a read of the working
## directory, so a hand-built context cannot pick up a file it did not ask for.
func mod_root() -> String:
	return String(_manifest.get("root", ""))


## Where this mod's declaration block lives — a `stats.json` SIBLING of its
## `mod.json`, not a manifest field. `ModManifest.parse` normalises a fixed key set,
## and a mod's own numbers belong in the mod's own directory where the Python gates
## can find them without a loader pass.
func declaration_path() -> String:
	if mod_root().is_empty():
		return ""
	return mod_root().path_join(DECLARATION_FILE)


## The whole record as primitives-friendly rows, keyed by seam family. Tests
## and `ModRuntime.finalize` read THROUGH this, never around the seams.
func registrations() -> Dictionary:
	return {
		"mod_id": mod_id,
		"content_roots": content_roots,
		"modules": modules,
		"attach_hooks": attach_hooks,
		"screens": screens,
		"subscriptions": subscriptions,
		"stat_declarations": stat_declarations,
		"declared_resource_ids": declared_resources,
		"declaration_refusals": declaration_refusals,
		"integrations": _manifest.get("integrations", []),
		"update_url": _manifest.get("update_url", ""),
		"incompatible_with": _manifest.get("incompatible_with", []),
		"conflicts_with": _manifest.get("conflicts_with", []),
	}
