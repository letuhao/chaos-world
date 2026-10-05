# 0243 engine_version validation for mods

- Status: Proposed
- Date: 2026-10-05
- Extends: ADR 0184 (mods are first-class content)

## Context

Mods declare `engine_version` in their manifest to state which Godot version they target. Without validation, a mod built for 4.7 could load on 4.6 and fail at runtime with undefined behavior — a missing API, a changed signal signature, a renamed method — far from the manifest that caused it.

## Decision

1. **Semantic version comparison:** the loader compares the manifest's `engine_version` against `Engine.get_version_info()` using `ModManifest.version_lt`, a dotted-integer comparison that treats `"4.7"` and `"4.7.0"` as equal.
2. **Refuse on mismatch:** when the running engine is older than the declared minimum, the loader aborts with `engine_version_mismatch` and a named detail string — never a silent skip.
3. **Optional field:** `engine_version` is optional. An absent or empty value skips validation entirely, so a mod that does not care about engine version loads on any build.

## Consequences

- A mod declaring `engine_version: "4.7"` loads on 4.7.x but is refused on 4.6.x with a named cause.
- The comparison lives in `ModManifest.version_lt`, so dependency `min_version` checks reuse the same logic.
- An absent `engine_version` means "no constraint" — the mod loads on any engine version.
- The failure is a boot abort with a named reason, consistent with ADR 0184's failure policy.
