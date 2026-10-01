# 0010 Item generation batches

- Status: Accepted
- Date: 2026-10-01

## Context

The game needs many items across all categories, generated in bulk. Breakthrough bundles (ADR 0009) cover one need; the rest needs a repeatable batch process that keeps the data audit green.

## Decision

- Item generation runs in **batches**. A batch owns one namespace prefix (`<batch>_*`) and creates a **self-contained pack** under `game/data/`: any recipe, boss, or domain its items reference is created in the same batch.
- Every item has at least one acquisition source (`ItemDef.sources`). `gather`/`starter` are base; `craft`/`boss`/`domain` must resolve within the batch; `quest`/`vendor`/`drop` are external and not audited.
- A batch targets roughly 8-16 items and uses ADR 0007 categories/subtypes and the grade -> realm tier mapping.
- Batches are deployed as background sub-agents in **waves of 3-4 concurrent agents** with disjoint prefixes. After each wave the orchestrator runs `uv run python -m tools data audit`, fixes cross-batch gaps, and commits.
- Constraints: English; clinical, non-sexual naming; pure gameplay mechanics. Agents write only under `game/data/` and never commit or run `tools check`/`git`/Godot.

## Consequences

- Content scales in auditable increments; the global audit is the gate, so a batch is done only when the audit is clean.
- Disjoint prefixes make concurrent generation safe; self-contained packs avoid cross-batch dangling references.
- Adding a new batch category is just a new prefix plus the same workflow.
