# Modding Guide

A mod is a directory or `.pck` with a `mod.json` manifest. It can add content (items, worlds, characters, elements), register modules, add cultivation paths, register screens, subscribe to events, and hook boot phases. Mods cannot change layer rules, the loader, or the locked skeleton (ADR 0184).

For the quest / event / story content schemas, the shared gate grammar, and how a mod adds or overrides progression content, see [`content-definitions.md`](content-definitions.md).

## Manifest

Required fields:

- `id` — non-empty string, unique across all mods
- `version` — dot-separated numbers (e.g. `"1.0.0"`)
- `priority` — integer; breaks same-depth load-order ties (higher loads later, wins overlay)
- `requires_api` — integer; must be ≤ `1` (the loader's `API_VERSION`)

Optional fields:

- `engine_version` — dot-separated numbers; mod refused if running engine is older
- `depends_on` — array of `{id, min_version?}`; topological load order
- `provides` — string array (e.g. `["cultivation_path"]`)
- `overrides` — string array of content ids this mod may replace
- `content_roots` — array of `{family, dir, id_field?}`
- `modules` — array of `{name, api_gd, deps?, provides?, seed_dir?}`
- `attach_hooks` — array of `{phase, callable?}`
- `screens` — array of `{id, scene, label?}`
- `events` — string array of event names

## Content roots

- Base game scans first; mods overlay in load order; later roots win by default.
- An id collision requires the later mod to declare that id in `overrides` or boot aborts.
- `id_field` names the def property holding the id when it is not `"id"` (e.g. `"location_id"` for `WorldLocationDef`, `"npc_id"` for `NpcDef`).
- Without the correct `id_field`, content is silently invisible (ADR 0240).

## Modules

- Each module entry points to an `api.gd` facade — the only file other modules may reference.
- `deps` lists module ids this one depends on (facade-only references).
- `provides` declares what the module offers (e.g. `["cultivation_path"]`).
- No facade width cap. `tools arch` measures facade FAN-IN instead (`rules.MAX_FACADE_FAN_IN`): a facade imported by many units warns, because that is the coupling. Publish the verbs your module needs; if callers start needing a *class* you own, expose the class by name rather than re-exporting it as a verb.

## Cultivation paths

- Declare `provides: ["cultivation_path"]` and a `seed_dir`.
- Each seed `.tres` must carry: `progress_required` (positive number), `breakthrough_item` (non-empty StringName), `recovery_item` (non-empty StringName).
- The provider MUST call `RealmRate.factor(rank_id)` for the per-realm factor.
- The provider MUST NOT declare `RATE_STEP` or `NEUTRAL`, and MUST NOT read `RealmDefaults.ladder()`.
- The `api.gd` facade needs at least `attach(actor)` and `panel_state(actor) -> Dictionary` (ADR 0241).

## Screens

- Each screen entry: `{id, scene, label?}`.
- Registered screens are mountable by id via `ScreenStack.push_registered(id)`.
- Duplicate ids are refused loudly (ADR 0244).

## Events

- 7 bus types: `NpcEvents`, `AuctionEvents`, `WorldEvents`, `DestinyEvents`, `NationEvents`, `SectEvents`, `HoldingsEvents`.
- Each `events` entry is a string event name; the mod's entry point binds the callable.
- The bus is named by class name, not node path.
- Connections are guarded by `is_connected` to prevent double-connect (ADR 0242).

## Attach hooks

- Each hook: `{phase, callable?}`.
- `callable` is a `"path/to/script.gd:method_name"` string resolved at load time.
- The app folds hooks into the AttachPipeline after finalize.

## Load order

- Topological over `depends_on`; a dependent always loads after its dependency.
- A cycle aborts boot naming every member.
- Same depth: higher `priority` loads later (wins overlay); `id` is the stable tiebreak.
- A missing dep or unmet `min_version` aborts with a named cause.

## PCK packaging

- Place a `.pck` in the mod root; the loader mounts it and adds `res://` to the scan roots.
- Same manifest schema, same loader path as a loose directory.
- A failed mount aborts with `pck_mount_failed`.

## Failure modes

- `bad_manifest` — malformed JSON or missing required field; fix the named field.
- `duplicate_mod_id` — two mods declare the same id; rename one.
- `engine_version_mismatch` — mod requires a newer engine; lower `engine_version` or upgrade.
- `api_version_mismatch` — mod requires a newer loader API; lower `requires_api`.
- `missing_dependency` — a `depends_on` id is not discovered; add the dep or remove the entry.
- `version_mismatch` — a dep's `min_version` is unmet; bump the dep or lower the floor.
- `dependency_cycle` — a cycle in `depends_on`; break it.
- `undeclared_override` — a content id collides without being in `overrides`; declare it or rename.
- `invalid_cultivation_seeds` — a seed is missing a required field; fix the named seed.
- `duplicate_module` — a module name is already registered; rename it.
- `bad_api_path` — the `api_gd` file does not exist; fix the path.
- `unknown_dependency` — a module dep is not provided by any base or registered module; fix the dep name.
