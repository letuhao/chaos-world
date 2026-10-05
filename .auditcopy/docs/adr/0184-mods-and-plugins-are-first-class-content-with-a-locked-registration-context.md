# 0184 Mods and plugins are first-class content with a locked registration context

- Status: Proposed
- Date: 2026-10-04
- Extends: ADR 0002 (composition root), ADR 0030 (ui is a separate program), ADR 0138 (asset programs stay optional)
- Amends boot order: `app/item_workbench_app.gd::_attach_body_modules` becomes one registrant, not the hand-written list

## Context

No mod infrastructure exists. Boot is a hand-ordered `_attach_body_modules` list; catalogs scan authored `.tres` through one shared `ContentScan` (`core/content_scan.gd`); `tools/arch/registry.json` knows modules and deps but no mods. `tools check` content gates (data audit, cultivation validate, options parity, acquisition, `UI_MODULES`, selftest) key off fixed lists, so unknown content today passes silently or fails open.

Goal: mods from one item to a full DLC, first-party in-repo and third-party external, without forking the layer rules.

## Decision

1. **Mechanism:** both loose directories (dev) and packed `.pck` (distribution), same manifest schema, same loader path.
2. **Scope:** full plugins — new world, cultivation system, destiny path, items, map, characters, elements. Mod almost everything EXCEPT the locked skeleton: change the shape, not the skeleton.
3. **Load order:** `depends_on` graph, topological; cycles are a hard fail; explicit `priority` breaks same-depth ties.
4. **Ship:** both in-repo optional modules (first-party) and an external mods directory (third-party), equal citizens.
5. **Catalog merge:** overlay stack, base first, later wins; an id collision requires an explicit `overrides:` declaration or it is a loud load error, never silent (ADR 0066's duplicated-constant trap).
6. **Registration seams:** a `RegistrationContext` exposes exactly `add_content_root(family, dir)`, `register_module(name, api_gd_path, deps)`, `add_attach_hook(phase, callable)`, `register_screen(id, scene, label)`, `subscribe(events_bus)`. Nothing else is reachable.
7. **Locked surface:** layer rules, facade-only rule, `ContentScan`, `RealmRate` single curve (ADR 0116, ADR 0066), `StatProvider` composition (ADR 0026), `InstitutionClaim` vocabulary (ADR 0064/0083), magnitude ladders authored and bounded (ADR 0050/0055), authored-resource-only reads (ADR 0131/0175), resource ceilings, resource/actor schemas, test crash backstop, the loader itself.
8. **Failure policy:** any manifest error, dependency cycle, version mismatch, or id collision aborts boot with a named cause. Never skip silently.
9. **tools check inheritance:** data audit, cultivation validate, options parity, acquisition, `UI_MODULES`, and selftest key off the module+family registry, or loudly exempt — never silently pass unknown content.

## Registration context contract

- Loader calls each mod entry once with a `RegistrationContext`; that context is the whole extension surface. First-party modules register through the same context, so in-repo mods get no privileged API.
- Manifest: `id`, `version`, `engine_version` range, `depends_on[]`, `priority`, `overrides[]`, content roots, module `api.gd` path, attach hooks, screens, event subscriptions.
- A mod registering content outside its declared family roots is refused.

## Load order

- Topological over `depends_on`; a cycle or a missing dep names the offender and aborts.
- Same depth: explicit `priority`, then `id` as the stable tiebreak.

## Catalog merge

- Base game first, then mods in load order; later overlays earlier within a family.
- Keyed by authored id, never by array position (ADR 0050).
- Collision without `overrides:` = loud boot error. Declared override wins and is named in the boot log.

## Consequences

- `_attach_body_modules` stops being the source of truth; the composition root assembles the same list from registrations (ADR 0002 keeps app the only place that knows concrete types).
- The loader is locked (decision 7): a mod can never replace it, so boot policy is uniform.
- A modded game still satisfies the same contract tests, facade cap (12 public methods), and line budget as first-party modules.
- `tools check` gates that cannot see a family fail loudly, mirroring claim_guard overlapping-claim failure.

## Acceptance criteria (initial, for the completeness audit)

- One manifest schema loads identically from a loose directory and a packed `.pck`.
- Boot order is computed from `depends_on` + `priority`; a cycle aborts with a named cause.
- An undeclared id collision aborts boot; a declared `overrides:` entry wins and is logged.
- Missing dep, version mismatch, and malformed manifest each abort boot with a named cause — no silent skips.
- A mod registering content outside its declared family root is refused.
- In-repo and external mods pass through the same loader path and the same registration seams.
- `tools check` content gates iterate the module+family registry; an unrecognized family fails loudly.
