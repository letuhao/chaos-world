# 0914 Launch gaps: returns survive scenes, position persists (playable)

- Status: Accepted
- Date: 2026-10-07

## Context

Two facts stopped play: the descent return lived on the scene, so
navigating away freed the way back while the run stayed active; and no
production code installed the worldmap ledger, so mutations never reached
disk in-game and no position was remembered at all.

## Decision

- The return stack moves to `WorldmapApi` (push/pop/peek/depth/clear). A
  fresh scene over a standing descent reads the same truth and refuses
  above-ground verbs until the return; a domain-route Leave orphans the top
  entry, and LIFO still returns the newest first.
- `WorldmapLedger` gains the `position` container (`{node, cell}`, repaired
  or absent-never-wrong); the store routes both containers; the root
  installs the ledger in `_ready` beside the other world stores.
- The boot stages overlay + position into the ledger on destroy/close, the
  resume point on every step/return, and restores both on open (mutations
  first, then `warp` with entry fallback). No ledger installed (headless
  probes) skips silently.

## Consequences

- Quit/resume keeps holes and position; navigation mid-descent is safe.
- What this ADR does NOT do: encounter triggering (no surface resolves;
  DEF-0375), toll spending (DEF-0372), or a nav-bar button (16 slots cover
  the first 16 routes; Venture rides hotkey `p` like every late route).
