# 0003 Cultivation paths and pluggable progression

- Status: Accepted
- Date: 2026-10-01

## Context

ADR 0001 models a single `realm_id` plus one `spirit_roots` vector — one ladder per actor. The game needs multiple cultivation systems (qi, body, soul, sword, demonic, Buddhist; plus collection- and sequence-style systems), coexisting on one actor and added as data. The current shape blocks this.

## Decision

- Replace `realm_id` with **`paths: {path_id: PathState}`**; generalize `spirit_roots` to `affinities`.
- `PathState`: `path_id`, `rank_id`, `stage`, `progress`, `unlocked`, per-path resources.
- `CultivationPathDef` (Godot `Resource`) defines a system: ladder, gating, resources, stat provider, progression model. A system is authored as a `.tres`.
- `contracts/progression_model.gd` exposes `can_advance`, `advance`, `on_event`. Ship `Ladder` first; add `Collection` (spirit rings / Gu), `Sequence` (pathways + acting), or `Node` only when a system needs them.
- Derived stats aggregate contributions from every path via stat providers (ADR 0002).
- Cross-path synergy/conflict goes through stat providers or `SynergyDef`, wired in `app/`.
- Single-path actors have one entry; a `realm` accessor returns the primary path for compatibility.

## Consequences

- Supersedes ADR 0001's single-`realm_id` decision; the rest of ADR 0001 stands.
- Adding a cultivation system = author a `.tres` (plus an optional progression model, stat provider, and resources); no core change.
- Adding a new *kind* of progression model touches `contracts` and needs an ADR.
- `paths` must be versioned in saves; cross-path power scaling is gated by `CultivationPathDef`.
- Derived stats recompute on a dirty flag; paths are read-heavy.
