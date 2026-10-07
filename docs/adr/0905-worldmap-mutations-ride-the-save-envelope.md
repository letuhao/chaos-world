# 0905 Worldmap mutations ride the save envelope

- Status: Accepted
- Date: 2026-10-07

## Context

ADR 0904 left mutations in-session: unload/reload kept them, but quit
forgot them. The generator reproduces every untouched chunk from its seed,
so persisting whole chunks would be a second copy of the world that could
disagree with the first.

## Decision

- `core/worldmap_ledger.gd` owns the persisted shape: `WORLD_KEY =
  "worldmap"`, one container `mutations` (`chunk id -> "x,y" ->
  `{"blocked": bool}`). Instance store with `read_ledger`/`write_ledger`,
  total normalization (bad keys dropped, caps `MAX_CHUNKS 256` /
  `MAX_CELLS_PER_CHUNK 1024` in sorted order), following the `WorldClock`
  precedent exactly.
- `SaveSlot.WORLD_KEYS` and `app/world_ledger_store.gd` each gain the key
  by authored agreement asserted in test, not by import (same layer rule as
  `world_time`/`polity`). `ENVELOPE_VERSION` stays 1.
- `WorldmapStreamer.export_mutations`/`import_mutations` move the overlay;
  import drops the data cache so no stale chunk disagrees with the restored
  overlay.

## Consequences

- Destroy -> save -> quit -> restore -> import keeps exactly the changed
  cells; untouched chunks regenerate and are never stored.
- What this ADR does NOT do: route the scene in-game (no `ScreenRoutes`
  entry yet — the scene is reachable headless and by address, not by play),
  or replicate streamed state for multiplayer.
