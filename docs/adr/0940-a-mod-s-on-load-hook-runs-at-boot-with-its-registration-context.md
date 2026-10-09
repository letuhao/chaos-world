# 0940 A mod's on_load hook runs at boot with its registration context

- Status: Accepted
- Date: 2026-10-09
- Amends: ADR 0184 §6 (the registration surface; its eighth seam was inert)
- Extends: ADR 0275 (the sixth seam — this closes the mirror: load-time CODE, not only declarations)

## Context

The eighth seam shipped as infrastructure and was never fired. `ModsApi.fire_lifecycle_event` had no
production caller, so a mod could declare `lifecycle_hooks: [{"event": "on_load", "callable":
"…/api.gd:boot"}]` and its `boot(ctx)` never ran — the doctrine template proved its System only by
calling `boot(ctx)` from its own test, which is DEF-0333 verbatim: a mod author writes `boot(ctx)`,
sees it pass, and ships a System that never loads.

Two measured defects had to be fixed for the seam to be real at all:

- `fire_lifecycle_event` called hooks with NO arguments, so a load-time hook could not receive its
  `RegistrationContext` — and `boot(ctx)` reads `declared_resource_ids()` off it.
- `ModLoader._resolve_callable` had two bugs, both measured: `spec.split(":")` split `res://` at its
  own colon (three parts, so EVERY manifest callable resolved to an empty Callable), and a plain
  `Callable(obj, method)` does not keep a RefCounted target alive, so the hook was invalid the
  moment the resolver returned. Both callable suites were red on this.

## Decision

1. **`on_load` fires once per successful boot pass**, at the end of `ModBoot.run`, AFTER
   `ModsApi.set_active` — a hook that reads config or queries its own context finds the boot already
   published. A failed pass fires nothing. A second successful pass fires again: a pass is the unit
   of firing and stamps fresh contexts.
2. **A lifecycle hook is called with ITS OWN mod's RegistrationContext** — `callable.call(ctx)` —
   one contract for manifest-resolved and seam-registered hooks alike. It is the same context
   `ModRuntime.finalize` played the mod's declarations through, so the pools `declare_stats`
   accepted are readable at load time.
3. **`ModsApi.FIRED_EVENTS` names what this build fires: `["on_load"]`.** `ModManifest.LIFECYCLE_EVENTS`
   stays the declared vocabulary a manifest may use; an event with no firer is recorded and NEVER
   called, and the docs at the seam, the facade and here say so. Refusing unfired events at parse
   time was considered and rejected: the vocabulary is part of manifest API 1, the events have real
   future firing points, and a forward-authored mod would have to re-author its manifest. The list
   is a const with a test, so the truth is one edit away rather than prose that decays.
4. **The doctrine template is reachable from its `mod.json` alone**: its `lifecycle_hooks` names
   `api.gd:boot`, and its suite drives `ModBoot.run` — the production path — going red if the firing
   is removed. The direct `boot(ctx)` call survives as a unit leg.
5. **`ModLifecycle` is deleted.** It was a second, unreferenced lifecycle registry whose docblock
   promised all seven events fire — the duplicate this decision removes (ADR 0066).
6. **`_resolve_callable` splits at the LAST colon and returns a lambda that OWNS its target**, so a
   resolved hook is valid at its call site. It forwards both call shapes the seams use (no argument,
   and the one-argument actor/context).

## Consequences

- A mod's `boot(ctx)` now runs in production; the docblocks that promised an "entry point … in W3+"
  are corrected to the seam that exists.
- `on_unload`, `on_enable`, `on_disable`, `on_update`, `on_save` and `on_load_save` have no
  production firer in this build. Wiring one means adding a firing point, the event to
  `FIRED_EVENTS`, and the test that pins the list.
- A hook whose `callable` spec does not resolve is still skipped silently (the stub-tolerant policy
  attach hooks already had); a typo'd spec is not loud yet.
- No new seam: the fix makes the eighth seam real rather than adding a tenth.

## Acceptance criteria

- `ModBoot.run` over a mod declaring an `on_load` hook fires it exactly once with that mod's
  context; removing the firing line reds the doctrine suite and the mods-suite guard.
- `ModsApi.FIRED_EVENTS` is `["on_load"]`, a subset of `ModManifest.LIFECYCLE_EVENTS`, pinned by test.
- The doctrine template's Systems attach with no direct `boot()` call in the production leg.
- `_resolve_callable` resolves a `res://` spec to a VALID Callable that fires for both call shapes
  (the regression the two callable suites were red on).
