# 0177 A portrait variant is chosen by a key the game already publishes, and its layers compose back to front

- Status: Proposed
- Date: 2026-10-04
- Extends: ADR 0131 (a portrait is authored data keyed by id), ADR 0138, ADR 0153
- Depends on: ADR 0175 (the asset index that feeds the layers)

## Context

A bundle of layered art has nowhere to go, and the reason is one function. Measured across all of `game/src`:

- **There is exactly one image-loading path**: `core/../ui/panels/portrait_panel.gd:146-167`. `grep` for `TextureRect|Sprite2D|ImageTexture|ResourceLoader` finds 24 matches; the only `Texture2D` *assignments* are that panel's `:153` and `:167`.
- **That panel has one production caller, keyed by RACE, for the PLAYER only** — `soul_hearth_screen.gd:496` → `PortraitResolver.resolve(_actor, RaceApi.race_of(_actor))`. `PortraitResolver.resolve` has **no `npc_id` parameter and no path that reaches a named character**. Two NPCs of one race get one face.
- **`layer_paths` compositing is declared and deliberately not performed.** The field is documented as "the composable layers, back to front... which is what lets the same body plan read differently per occasion" (`core/portrait_def.gd:37-39`), and `_paint` loads the **first** loadable path and returns (`:146-154`, `:137-138`). A regalia overlay, an expression frame and a faction variant are all structurally addressable and visually discarded.
- **Two live defects in the template this extends.** `PortraitIndex.portrait_path` accepts `status == "generated"` only (`:88`) and refuses `"approved"` — and shipped crowd portraits **are** approved. And `PortraitResolver.validate()` (`:119`) checks `layer_paths.is_empty()` but never file existence, while `game/assets/characters/portraits/` **does not exist** and all four non-placeholder `.tres` name a PNG inside it. The gate is green on portraits that cannot load.
- **Combat can compute a variant but cannot announce one.** `modules/combat/` and `modules/combat_engine/` declare **zero signals**; `contracts/` has seven event buses and no `combat_events.gd`. `CombatSpine.resolve_hit` is one synchronous call with no pre- or post-hook, so *"the actor is about to act"* is unknowable from outside. There is also **no animation system at all** — no `AnimationPlayer`, `AnimationTree`, `AnimatedSprite` or `Skeleton2D` anywhere in `src`; `Actor` is a `RefCounted`, not a `Node2D`.
- **The facades are nearly full.** `NpcApi` is at **12/12** (`rules.MAX_FACADE_PUBLIC_METHODS`, `tools/arch/rules.py:163`); `combat_engine` has exactly one free slot and `combat` three. A thirteenth method on `NpcApi` is a hard `tools arch` failure.

## Decision

**A variant is a key the game already publishes, read through a trait that already exists. Layers compose. The one new hook lives in `app/`.**

- **Compose every layer, back to front, in `_paint`.** The first layer still identifies the face; the rest are the finish. No new field: `layer_paths` is already an ordered array. This changes what `summary()["layer_count"]` means, so the panel's contract test moves with it.
- **A variant is an `axis:value` entry in `visual_traits`,** parsed by the existing `trait_value()` (`core/portrait_def.gd:66`). No new field, no new reader, and it is the same grammar `tools/assets.py:21` validates for item art. **The closed axis vocabulary, and what each axis names:**

| axis | names | exists? |
|---|---|---|
| `action` | a pose chosen from published `CombatOutcome` fields + `TechniqueDef.path_ids()`/`mind_kind`/`aim_meridian` | derived from existing state |
| `stage` | `NpcStageDef.stage_id` (`gatekeeper` → `sworn_servant` → `retired`) | **existing** |
| `role` | `NpcApi.ROLE_*` on `Actor.tags` | **existing**, and never branched on in damage (ADR 0074) — so a reader is free |
| `beat` | a `WorldFact` fact id | **existing**, flat and unprefixed |
| `place` | `WorldLocationDef.location_id` | **existing**, 4 shipped |
| `form` | already read at `portrait_resolver.gd:159` | **existing** |

  **Three names are forbidden**, each for a measured reason: `phase` is `Tribulation.phase` (`core/tribulation.gd:89`, vocabulary `WARNING/TRIAL/CLIMAX/AFTERMATH`) and already renders as a `"phase"` key in two UI surfaces; `location` is `contracts/location_resolver.gd:4`, the **BODY path's meridian/acupoint contract** returning `{meridian_id, point_id, multiplier}`; and a closed `emotion` enum would re-open ADR 0153's hole, because the gate counts expression **prose** on distinct text and an enum cannot satisfy that without collapsing to one value.

- **Selection is computable from existing state; only timing needs a hook, and it goes in `app/`.** `app/` is the only layer allowed to know both `core` and `combat` (`rules.py:28`, `LAYER_DEPS["app"] == {"*"}`). The emitter fires from inside the existing `resolve_hit` body (`app/combat_boot.gd:769-806`) and `duel_blow` (`:584-644`) — **which grows no facade at all**, the reason this is preferred over a `set_pose_resolver` that would put `combat_boot` at 12/12. **The boss path is not covered by that and must be:** `CombatExchange.exchange` resolves through the *share* model (`combat/damage.gd:62`), not the spine, so a `Callable` is injected there — the pattern `exchange.gd:439-445` already uses.
- **No animation, and deliberately so.** The game is turn-based (ADR 0167: a round resolves inside one period), so an action "pose" is a **portrait layer swap**, not a frame sequence. Building an animation system would be the larger and wrong answer.
- **Fix the two template defects in the same change:** accept `{generated, approved}` wherever a reader filters on status, and make `validate()` check **file existence**, not just a non-empty array.
- **`ui/` reaching `npc` is a separate decision.** `UI_MODULES` (`rules.py:67-157`) omits `npc`, `social`, `relations`, `event`, `world_spawn`, and `ui/` has zero references to `NpcApi`. Showing a named NPC's face in a UI panel therefore needs a `rules.py` edit plus an ADR, and it is **not** a prerequisite for resolving a variant — `core/` may read authored resources without it.

## Consequences

- **A character bundle becomes reachable without a new module, a registry entry, or a facade method.** The variant rides `visual_traits`; the composition rides `layer_paths`; both are already authored data on a `core/` Resource.
- **Deleting this whole feature leaves the game working.** A `PortraitDef` with no variant composes to itself, and `PortraitResolver`'s three-step chain still ends at `PLACEHOLDER`. That is ADR 0131's property, preserved.
- **A named NPC's face still needs an `npc_id` to reach the resolver,** which is a resolver-signature question and a `ui/` permission question. Both are owed and neither is decided here.
- **The action axis is the only genuinely new vocabulary in this ADR,** and it is derived from published `CombatOutcome` fields rather than authored — so a combat change that adds an outcome shape does not silently invalidate an art set; it makes one variant unreachable, which `report` shows.
- **One guard must fail structurally, not by value:** no file under `res://src` may declare its own action-axis vocabulary, mirroring `tests/core/test_realm_rate.gd:208-224`. `BARE_REF_UNITS` excludes `modules/*` (`rules.py:60`), so `tools arch` cannot see a private copy — ADR 0116's mutation, where a numerically identical copy stayed green under every value assertion.
- **Owed, not decided here:** the `npc_id` → `PortraitDef` route, whether `ui/` gains `npc`, and the boss-path emitter's exact injection point.
