# 0095 Qi gates on channel depth, and its facade publishes verbs only

- Status: Accepted
- Date: 2026-10-03
- Amends: ADR 0024 (qi realm contracts), ADR 0036 (reachable gates), ADR 0044 (preview and execute)
- Extends: ADR 0035 (anchors committed, never required), ADR 0051 (the roll reads no gate input)

## Context

Four defects, all in the qi path, none visible to a green suite.

1. **The channel ladder was flat.** All 30 seeds under `game/data/qi_cultivation/realms/`
   carried `required_channel_state = &"open"`, so `expand_meridian`, `strengthen_meridian`
   and `refine_meridian` were required by no gate. `QiTraining.train_channel` reached its
   `refine_meridian` branch only on a channel already `strengthened`, so the branch was
   unreachable and `channel_refinement_cap` was read by nothing that could run. The
   capacity and power bonuses behind `expanded`/`strengthened` (`core/meridian_network.gd:130`,
   `:138`) were unreachable content on this path.
2. **Nothing attached the dantian.** `QiCultivationApi.attach_dantian` existed and no
   production path called it: `app/actor_factory.gd:85` calls `attach` only. Every actor
   the game built had `dantian == null`, so `QiAdvancement.preview` answered `no_dantian`,
   `QiBreakthroughCondition.can_breakthrough` refused, and `QiTraining.cultivate` /
   `recover` returned false. **The whole qi path was inert in play** while every test,
   having built its actor by hand, passed.
3. **The facade was full.** `api.gd` sat at the 12-method ISP cap (`tools/arch/rules.py:112`)
   with five of its twelve being accessors nothing outside the module called: `provider`,
   `path_def`, `meridians`, `dantian`, `attach_dantian`. There was no room for the one line
   that fixes (2), which is why it was never written.
4. **The roll read its own gate.** `QiAdvancement` and `QiBreakthroughTransaction` both read
   `Stat.BREAKTHROUGH_CHANCE`, which core derives as `0.1 + comprehension * 0.01 + will * 0.005`
   (`core/actor_stats.gd:166`). Comprehension IS this path's gate (`comprehension_required`,
   authored to 66), so the gate's own floor plus dantian quality passed the 0.95 clamp from
   the Immortal tier on: `_deviate` stopped firing, `QiTraining.recover` and all thirty
   authored `recovery_item`s became unspendable, and the deviation loop was dead content on
   most of the ladder. ADR 0051 named qi as this shape and left it unfixed.

Also closed here: the two files carried their own copies of the gate and the roll, which
ADR 0036 recorded as still open.

## Decision

- **The channel gate is a gate/ceiling pair, as `BodyRealmSeed` already authors it**
  (`body_cultivation/realm_seed.gd:21-22`). Qi gains `required_channel_refinement`;
  `channel_refinement_cap` keeps rising one per realm, which Wave 1 had already authored.
  Across the 30 seeds: demanded state climbs `open` (R1-R2) -> `expanded` (R3-R4) ->
  `strengthened` (R5-R30), the cap is `index + 1`, and the demanded depth is
  `max(0, index - 3)`. Every boundary satisfies `next.required_channel_refinement <=
  this.channel_refinement_cap` — the rule ADR 0036 exists for — and every required channel
  unlocks at or before the realm the actor is leaving.
- **`QiRealmSeed.channel_met` is the one definition** of that gate; the condition enforces it
  and both previews report it. `QiAdvancement` now delegates `preview`, `try_breakthrough`
  and `cancel_attempt` to `QiBreakthroughTransaction`, so the module holds one gate and one
  roll (ADR 0044).
- **`QiCultivationApi.attach` attaches the dantian.** It is part of the path, not an optional
  extra, so the composition root's single call leaves the actor ready. The five internal
  accessors moved to `QiAccess`, which `tools arch` does not count, taking the facade from
  **12 public methods to 7** — the verbs `app/` and `ui/` actually call. `for_realm` caches,
  as `MindRealmSeed` does, because `train_channel` reads a profile per elixir spent.
- **`QiChance` is the whole roll**: `clamp(MIN + quality * QUALITY_TO_CHANCE, MIN, MAX)`,
  reading the dantian and nothing else (ADR 0051). Dantian quality is bounded twice —
  `Dantian.set_quality` clamps to 1.0, and `cultivate` stops at the next realm's floor — so
  the sum cannot reach `MAX_CHANCE`. The clamp is not the binding constraint at any quality.
- **`train_channel` refuses at the cap without spending the elixir**, and publishes
  `can_train_channel` / `elixirs_to_gate` so a caller budgets a walk instead of counting.

Rejected: *a rising `required_channel_state` with no depth gate.* Depth only increments on a
strengthened channel (`core/meridian_network.gd:77`), so any seed below `strengthened` asking
for depth would be unsatisfiable by construction — ADR 0036's failure class in new clothes.
Rejected: *a second facade file.* `tools/arch/enforce.py:77` treats `api.gd` and nothing else
as a facade, so a second published surface is a cross-module violation, not a split. Rejected:
*delete `attach_dantian` and let `app/` call `QiAccess`* — `app/` may only reach a module
through its facade, so the composition root would have had no legal way to create the dantian.
Rejected: *keep `Stat.BREAKTHROUGH_CHANCE` and cap the sum instead.* The clamp is what hid the
defect; the input is the defect.

## Consequences

- `expand`, `strengthen` and `refine` are reachable and required; the network's capacity and
  power bonuses are live content on this path for the first time.
- R1-R30 is walkable in play, not only in tests: the missing line was the one the cap had no
  room for.
- Every one of the 29 boundaries is rollable again, so the deviation and recovery loops are
  live and the thirty authored `recovery_item`s are spendable.
- `test_qi_channel_ladder.gd` asserts both directions at all 29 boundaries — reachable through
  public actions, and failing for a bare actor — plus the cap refusing without cost.
  `test_qi_breakthrough_chance.gd` pins the roll at every boundary and against a saturated
  `Stat.BREAKTHROUGH_CHANCE`. `test_full_traversal.gd` resolves authored items through
  `Crafting.resolve` and trains only through the facade.
- **Stays dead, deliberately:** qi has no world creation, so `WorldAnchor.inside_tier` and
  `WorldState.pay_upkeep`'s payer stay absent; `QiAdvancement.chance` is published and only
  tests read it; nothing in `src/` calls `WorldAnchor.ascend`, so the Transcendent ascent is
  walkable only from `core` (ADR 0058 records that gap as its own). **Deferred (DEF-0132..0135):**
  the `required_meridians` tier rule belongs in `tools cultivation validate`, not only in the
  suite; `tools/generate_qi_items.py` still emits the catalysts ADR 0096 deleted; the qi
  transaction still does not call `Breakthrough.face_tribulation`, so a player must fight the
  tribulation through core's entry points before the gate opens.
- The duplicate gate copy is gone; `QiAdvancement` and `QiBreakthroughTransaction` can no longer
  disagree about whether a realm is enterable.