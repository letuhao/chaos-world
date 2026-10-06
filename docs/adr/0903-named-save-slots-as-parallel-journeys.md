# 0903 Named save slots as parallel journeys

- Status: Accepted
- Date: 2026-10-07

## Context

ADR 0128 fixed single-slot autosave with no player choice: one primary file,
one invisible backup, no slot list. That rule outlived its reason. Players
asked for Minecraft-style parallel journeys ("multiverse slots"), and the
menu goal needs a save/load surface. The single slot is still the default —
autosave keeps writing it, boot keeps continuing it — but it can no longer be
the only slot.

## Decision

Named slots beside primary, not instead of it:

- The roster is fixed: `primary` (the legacy slot, unchanged paths) plus
  `first`, `second`, `third`. A fixed roster means the menu is four static
  rows rather than a dynamic list, and no slot id ever comes from player
  text (path traversal by construction, not by validation).
- Every `SaveStore`/`SaveApi` verb takes an optional slot defaulting to the
  installed live slot, which defaults to `primary`. All existing callers keep
  their signatures and their behavior; the autosave still lands on primary
  unless the player loaded another journey, which moves the live slot.
- Per-slot rotation: each slot owns its primary, backup and temp files, so a
  failed write to one journey can never touch another. The temp file is never
  readable, in every slot.
- The live slot cannot be erased. A menu that deletes the journey being
  played is refused by name (`live_erase_refused`), not by crashing later.
- The menu reads `slot_summary(slot)` — `{exists, generation, difficulty,
  actor_id, display_name}` straight off the envelope, never a restore. A slot
  list that restored every journey to describe it would be a load screen
  wearing a menu's clothes.

## Consequences

- ADR 0128's "no slot list" clause is superseded; its autosave schedule,
  backup discipline and envelope shape stand unchanged.
- `SaveApi.set_live_slot` is root-owned state like the installed stores: a
  suite that sets it without restoring pollutes every suite after it, so the
  save suites reset it in teardown (same rule as the ledger stores).
- What this ADR does NOT do: free-text world names, more than three named
  slots, per-slot difficulty rules, or cloud sync. A fourth journey is a new
  ADR, not a constant edit — the roster size is the design.
