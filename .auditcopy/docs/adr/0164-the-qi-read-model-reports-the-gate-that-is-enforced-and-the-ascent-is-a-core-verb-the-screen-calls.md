# 0164 the qi read model reports the gate that is enforced, and the ascent is a core verb the screen calls

- Status: Accepted
- Date: 2026-10-04
- Amends: ADR 0158 (closes its HANDOFF: the screen no longer selects its own channel)
- Amends: ADR 0141 / ADR 0150 (their price naming is preserved, on the read model)

## Context

ADR 0158 made qi channel depth selectable through one facade verb and left a HANDOFF:
`qi_cultivation_screen.gd` still carried its own selection loop. Two further gaps sat
beside it, and all three share one cause.

1. **The screen still selected for itself.** It walked the gate's channels and skipped
   on `channel.meets(required_channel_state)`, which is state-only BY DESIGN
   (`game/src/core/meridian_state.gd:39`). From the first realm whose demand is pure
   depth, every candidate was skipped, every press did nothing, and
   `QiTraining.refine_meridian` (`training.gd:176`) was never reached. The depth half
   of the gate was reachable in tests and dead in play.
2. **The read model reported a gate nothing enforces.** `QiCultivationApi.panel_state`
   read `QiRealmSeed.for_realm(state.rank_id)` — the STANDING realm — while
   `QiBreakthroughCondition.can_breakthrough` enforces `RealmDefaults.ladder().next(...)`
   — the NEXT realm (`breakthrough_condition.gd:10-11`). One dictionary therefore
   described two realms: `target`, `can_attempt` and `unmet` named the next realm's gate
   and `required_channel_state` / `required_channel_depth` / `required_channels` named the
   one behind it. Since the demand rises one step of depth per realm from
   `spirit_transformation` on, the panel under-reported by one whole step at 26 of the 29
   boundaries, and the screen acted on that stale gate. This is the same class as
   BL-0694 (`required_channel_depth` was write-only).
3. **The qi screen had no ascent action.** `Breakthrough.ascension_ok`
   (`core/breakthrough.gd:244`) demands a WALKED ascent above `WorldAnchor.COMMIT_MICRO`,
   and the only thing that produces one is `WorldAnchor.ascend` (`core/world_anchor.gd:125`).
   Body and mind each had a screen action; qi had none. `ascend` was implemented and
   proven by a dozen suites, and had no production caller on this path — so
   `actor.ascension` stayed at the zero steps entering R28 commits, and R29 and R30 were
   unreachable by play while every ladder suite stayed green (BL-0693). Each of those
   walked the ascent through a test helper, which proves the ascent is SATISFIABLE, never
   that a player can satisfy it.

## Decision

**The read model reports the gate that is enforced.** `panel_state`'s channel block reads
the NEXT realm's seed through one helper (`api.gd:_gate_for_next_realm`), so state, depth,
channel list, owed count and price cannot describe two realms, and they agree with the
`target` / `can_attempt` / `unmet` already in the same dictionary. `QiTraining.synchronize`
keeps reading the STANDING realm's seed: capacity, tier and `channel_refinement_cap` are
the realm the actor is in, and what it may train to.

**Selection is the facade's; the refusal is the read model's.** The screen calls
`QiCultivationApi.train_next_channel` and names the id it returns. What the press would
REFUSE is published as data — `owed_channels` and `training_price`, both computed through
`QiRealmSeed.channel_met` — so the screen assembles ADR 0150's two sentences without
reassembling the gate. Facade: 8 public methods, unchanged, against a cap of 12; the
helpers are private.

**The ascent is a core verb the screen calls, and its gate is published as data.**
`panel_state` gains the same `ascent` block body and mind publish (`required`, `steps`,
`steps_total`, `met`, `outstanding`), and the screen adds `act_ascend` calling
`WorldAnchor.ascend` directly, offered on the same `required and steps > 0` conjunction
all three screens use. No new verb, and the facade does not grow: `world_anchor.gd:120-124`
already places the ascent in `core` because it belongs to no single path (ADR 0041).

Rejected: *read the standing realm's gate and label it as such* (publish it under a second
key). Then the screen would render a gate that is behind the player next to one that is
ahead, and the channel list's `required` marks would point at the wrong four meridians.
The player's next question is "what does the realm I am entering want", never "what did the
one I am in want".

Rejected: *let the screen reassemble `channel_met` from `required_channel_state` and
`required_channel_depth`.* It is one line and it is the ADR 0044 defect ADR 0158 rejected
— a preview and the action it previews disagreeing — written a second time in the UI. It
also cannot see injury, which is half of what `channel_met` requires.

Rejected: *add `ascend` to the qi facade.* The ascent is not qi's: every path carries the
same `AscensionState`, so a facade verb would imply an ownership `core` deliberately does
not have, and would grow a surface ADR 0041 kept out of all three paths.

## Consequences

- `tests/modules/qi_cultivation/test_qi_gate_reported_is_gate_enforced.gd` drives the real
  screen at `spirit_transformation` with every channel already at `strengthened`, so only
  DEPTH is owed; a press must spend an elixir into depth. It also asserts the reported
  gate is the next realm's at all 29 boundaries, and that R30 reports none.
- `tests/modules/qi_cultivation/test_qi_ascent_reaches_r30.gd` walks the ascent by pressing
  and asserts `ascension_ok` opens for R29 and R30; the control dies at the top and is
  never offered below the tier.
- `tests/modules/qi_cultivation/test_qi_screen_traverses_to_r30.gd` then enters R29 and R30
  by pressing Breakthrough, fighting each tribulation ONCE — `tribulation_ok` reads a
  decided survivor, so `face_tribulation` returns early on every later press. Re-fighting
  per attempt is what made an earlier draft expensive enough to trip a runner ceiling.
- The peer's ADR 0150 price naming survives unchanged, now assembled from published data.
- **Stays deferred:** `cultivate` (`training.gd:31`) still spends no qi, no time and no
  item, so the ladder is free work and only the three consumables are priced (DEF-0214).
- **Stays deferred:** `training_price` names a ROLE, so a realm whose channel elixir and
  recovery elixir resolve to one authored item cannot be distinguished by the message. The
  ids are per-realm seed data no screen may read.
- **HANDOFF to the UI owner:** `qi_cultivation_screen.gd` is 559 lines against a 400
  `LINE_BUDGET` (`tools arch` warns). It was already 494; the ascent block took it over.
  Splitting the screen needs a UI-owner decision about which panel owns the vitals.
