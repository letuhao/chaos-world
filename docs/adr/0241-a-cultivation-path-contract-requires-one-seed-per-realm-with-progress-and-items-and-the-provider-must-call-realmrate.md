# 0241 A cultivation path contract requires one seed per realm with progress and items and the provider must call RealmRate

- Status: Proposed
- Date: 2026-10-05
- Extends: ADR 0184 (mods are first-class content), ADR 0116 (RealmRate is the single rate curve), ADR 0066 (no second rate)

## Context

A mod can declare a new cultivation path via `provides: ["cultivation_path"]` and a `seed_dir`. The path must integrate with the shared realm ladder and the single rate curve. Without a contract, a mod could declare a path with missing seeds, invalid fields, or a private rate constant — producing a path that is invisible, broken, or desynchronised from the shared ladder.

## Decision

1. **Seed schema.** Each seed `.tres` must carry `progress_required` (a positive number), `breakthrough_item` (a non-empty StringName), and `recovery_item` (a non-empty StringName). These are the intersection of the three exemplar paths (qi, body, mind).
2. **Provider rate.** The path's StatProvider MUST call `RealmRate.factor(rank_id)` for the per-realm factor. It MUST NOT declare its own `RATE_STEP` or `NEUTRAL` constant, and MUST NOT read `RealmDefaults.ladder()` for a per-realm factor. The only per-realm factor is `RealmRate.factor` (ADR 0116, ADR 0066).
3. **Validation.** `ModuleRegistry.register` validates seeds when `provides` contains `"cultivation_path"`. A mod with invalid seeds is refused with named cause `invalid_cultivation_seeds` naming each finding.

## Consequences

- A mod with a seed missing `progress_required`, `breakthrough_item`, or `recovery_item` is refused at registration with `invalid_cultivation_seeds`.
- A provider that declares its own `RATE_STEP` or reads `RealmDefaults.ladder()` is refused — the single rate curve cannot be forked.
- A mod with a partial ladder (seeds for some realms but not all) can still register; the content audit (`tools/cultivation/audit.py`) separately requires full ladder coverage.
- The contract is enforced by `CultivationPathContract.validate_seed` and `validate_provider_source`, called by both the registry and the audit tool.
