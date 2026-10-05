# 0244 Screen registry integration for mods

- Status: Proposed
- Date: 2026-10-05
- Extends: ADR 0184 (mods are first-class content)

## Context

Mods can register screens via the `screens` manifest field, but the `ScreenStack` had no way to mount a screen by id — it only accepted an already-instantiated `Control` via `push()`. A mod screen was therefore undiscoverable at runtime: the scene existed but no code could navigate to it.

## Decision

1. **Static registry:** `ScreenRegistry` holds a process-wide `id → {scene_path, label}` table. Mods register through `RegistrationContext.register_screen`; the composition root folds all mod registrations into the registry via `register_from_contexts`.
2. **Mount by id:** `ScreenStack.push_registered(id)` resolves the scene path through `ScreenRegistry.path_of`, loads and instantiates the `PackedScene`, and pushes the resulting `Control` through the same `push()` path as base screens.
3. **Loud refusal:** a duplicate id, empty id, or empty scene path is a named `push_error` and the row is refused — never overwritten silently. An unknown id passed to `push_registered` is a named error, not a silent null.

## Consequences

- A mod screen is mountable by id through the same `ScreenStack` as base screens — no separate navigation path.
- The registry is static (per-process state, like `ModBoot`'s stored order), so a screen registered at boot is available to any caller.
- Duplicate ids are refused loudly, mirroring ADR 0184's catalog-merge collision policy.
- `ui/` never names the module that owns the `RegistrationContext` — the registry is duck-typed on the `screens` property, preserving the facade-only rule.
