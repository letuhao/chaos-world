# 0209 A settlement is shown through the same room surface every other room uses

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0847 (the install-or-retire question)
- Presentation only. ADR 0163's **data model and seam stand and are not re-litigated**;
  this decides how the thing is *shown*, and what the unwired class is for.

## Context

ADR 0163 decided the data model (a settlement is a `RoomDef` of `kind = settlement`
carrying a `fixtures` entry `kind=settlement_ref, ref_kind=sect`, referencing a
`SectDef.id`) and the seam (`DomainSettlement.summary` / `.resident`, read-only,
`domain_settlement.gd:111,167`). It also decided the `DomainSettlement` class is a
read-only lookup, not a system (`:74-76`) — **which BL-0847's "install or retire" must not
overturn.**

What is unwired is narrower than BL-0847's wording: the class is never *called*. The
question "install or retire" is therefore really **"who reads it"**, and the answer must
be a UI surface that shows a settlement room differently from an ordinary room — while
using the same surface, because:

- A settlement is a `RoomDef.kind` (ADR 0073), not a screen. It arrives in
  `rooms[]` with `kind = "settlement"` and needs no new route, no new nav action and no
  second binding arm. The `NpcRosterPanel` precedent (`npc_roster_panel.gd:6-12`) is
  exact: a panel, not a route of its own, precisely so nothing ships-but-dead.
- The domain explore screen already selects a room and reads that room's fixtures
  (`domain_explore.gd:837-847` `_fill_fixtures`). A settlement is a room whose *fixture*
  happens to be an institution ref — so the settlement readout belongs on the existing
  room surface, not on a new page.
- The UI standard's three-state vocabulary (ADR 0083) applies: `{}` = no settlement,
  `authors_no_settlement_ref` = a building that names no sect, `unknown_settlement_ref` =
  it names one that does not resolve. These are **three different facts** and
  `DomainSettlement` already returns them as named refusals
  (`domain_settlement.gd:104-110,232`). A settlement panel that collapsed them to
  "empty" would make "there is a castle here" indistinguishable from "this room is empty".

## Decision

**A settlement is presented as the room you selected, with one extra row-block — a
`SettlementPanel` in `ui/panels/` — keyed on the SELECTED room, exactly as
`NpcRosterPanel` is keyed on the current location. `DomainSettlement` is INSTALLED behind
the existing `DomainBridge`, not retired.**

### What the settlement view shows

One `SettlementPanel` in `ui/panels/`, rendered in the existing `MapPanel` column beside
the room list (taking the fixture row's place when the selected room is
`kind = settlement`), fed by ONE door `show_settlement(summary, residents) -> void`:

- **The building's own name and kind** — `room_id` + `display_name` from the payload
  (`domain_settlement.gd:152-153`). A castle is a settlement with nothing named, and it
  reads as a building, not as a broken sect.
- **The institution it names, or the named refusal.** `ref_kind` + `ref_id` + the
  catalog's `display_name` (`domain_settlement.gd:154-159`). When the lookup refuses the
  panel shows **the refusal id verbatim** — `authors_no_settlement_ref` /
  `unknown_settlement_ref` / `no_institution_lookup` — never a blank. This is the
  `NpcRosterPanel.UNWIRED_TEXT` move (`npc_roster_panel.gd:43`).
- **Who stands here** — `residents[].{ref_id, inhabitant_id, role, count}`
  (`domain_settlement.gd:237-243`), capped and truncated like every panel. Residents come
  from the room's own `actor_spawn_refs`; the panel **never reads a sect roster** — that
  is `sect`'s ledger and a second copy is the ADR 0066 failure mode (ADR 0163:86).
- **It writes nothing.** No admit, expel, found or schedule: a ref names, it does not act.

### Installing the seam

`DomainBridge` already has the `Callable` seam shape (`domain_bridge.gd:80-81` for
`minimap`, `:160,175` for its action list), and `DomainSettlement` reaches `sect` through
its own injected `Callable` (`set_institution_lookup`, `domain_settlement.gd:99`), the
`DomainSpawner.set_minter` precedent. So installation is: **the bridge gains a
`settlement` action calling `DomainSettlement.summary` / `.resident`; `app/` supplies the
`Callable`.** No facade change (`DomainApi` is at its 12-method cap), no new module
dependency, no `registry.json` change.

## Consequences

- **BL-0847 resolves by INSTALL, because the class IS the seam ADR 0163 promised and
  retiring it would silently invalidate an accepted ADR's consequences.** Unwired was a
  wiring gap, not a design error.
- **Never a new screen or route.** A settlement is reached by selecting it in the room
  list the player already uses; a route of its own would ship-but-dead (DEF-0261).
- **The panel must NOT derive the institution from the minimap payload.** The minimap
  publishes `kind` and `tags` (`domain_minimap.gd:132,168`) but `settlement_ref` is a
  *fixture* (ADR 0163:41); reading a sect id out of tags is exactly the post-hoc heuristic
  ADR 0073 forbids. It comes only from `DomainSettlement`, which resolves the ref properly
  and refuses it by name.
- **Trade-off rejected:** folding the readout into the `FixtureRow` as a `settlement_ref`
  row beside trap/puzzle/treasure — `DomainFixtures` has its own closed `KINDS` and
  hard-refuses `settlement_ref` (`domain_settlement.gd:59-63`), so that row would show a
  verb the arm/attempt/claim buttons cannot take.
- **Trade-off rejected:** reading the sect's roster/treasure via `SectApi.summary()` —
  out of ADR 0163's scope, and merging the two is the ADR 0066 double-copy.
- **What would change my mind:** the sect simulator shipping first, which would give the
  settlement something to *do* and change what this panel is for.

### `summary()`

Nested under the screen's `settlement` key, primitives only:
`{"shown": bool, "room_id": String, "ok": bool, "reason": String, "ref_kind": String,
"ref_id": String, "institution": String, "resident_count": int, "residents": Array,
"truncated": bool, "line": String}`. `shown: false` outside a run — the empty vocabulary,
so a headless test drives the panel through the bridge like any other caller and asserts
words, not pixels (`npc_roster_panel.gd:35-36`).