# 0176 A bundle tier comes from the character's role and gates rendering, never authoring

- Status: Proposed
- Date: 2026-10-04
- Extends: ADR 0153 (the nine required prompts are a canon gate counted on distinct expressions), ADR 0155 (completion target 1000 characters), ADR 0138 (`draft` and `canon` are different promises)
- Depends on: ADR 0175 (the second asset index this reads)

## Context

ADR 0153 requires all **nine** prompt slots on every canon character, with `expression_set` counted on 9 distinct `expression` strings and `pose_set` on 6 distinct `pose` strings. The catalog measures exactly that: **207 records, 184 canon, and every canon row carries 22 shots** (7 single-shot + 9 + 6). Scaled to ADR 0155's 1000-character target at the observed role mix, that is **~13,600 images**.

The instinct is to make the tier relax the canon gate per role. That is wrong, and ADR 0153 already recorded why: *"a canon character missing its map token is one the exploration map cannot place"* and *"a prompt set that passes while saying the same thing twice is worse than one that fails, because it looks complete."* An `npc` promoted to canon without a pose set would look complete and not be.

The cost is not in authoring, though. It is in **rendering**, and the cut there is decidable on evidence: which slots have a named consumer in the game today.

| slot | consumer | status |
|---|---|---|
| `map_sprite` | `world_map_screen.gd:259-283` builds a `Button` with `text` and no `icon` | live, text-only |
| `dialogue_portrait` | `portrait_panel.gd:146-167` — **the only image-loading path in `game/src`** | live |
| `character_portrait` | the same panel at a different crop | live |
| `expression_set` | needs variant selection | ADR 0177 |
| `pose_set` | same | ADR 0177 |
| `concept_art`, `environmental_concept`, `combat_concept`, `relationship_scene` | none | absent |

## Decision

**Tier gates what gets rendered. It never relaxes what must be authored.**

- **Every canon character still authors all nine prompt slots, at every tier, with ADR 0153's distinct-text counting unchanged.** `SET_SLOT_MINIMUMS` and `_prompt_set_gaps` are not touched. Authoring cost is flat per character; only the render queue is tiered.
- **Three tiers, derived from `identity.role`, named for what they render:**

| tier | role | slots rendered | images |
|---|---|---|---|
| `standard` | `npc` | `map_sprite`, `dialogue_portrait`, `character_portrait`, `expression_set`(9) | **12** |
| `extended` | `boss` | the above + `pose_set`(6), `combat_concept`, `relationship_scene` | **20** |
| `full` | `pc` | the above + `concept_art`, `environmental_concept` | **22** |

  The ordering is the point: a boss is seen in combat and in a relationship scene, a lead is the only character worth a reference plate. `map_sprite` is in `standard` because ADR 0153's own argument makes it load-bearing for every canon character.

- **A rendered-art gate is added, and it is new: a canon character's `standard` slots must reach `generated` or `approved` before `sync` will publish it.** Today's canon gate counts *prompts* (authoring) and never art (rendering), so a canon character whose map token is still `planned` is a character the exploration map cannot place — ADR 0153's argument applied one layer down. This is the first gate that distinguishes the two.
- **`bundle_tier` is a top-level field defaulting to `""`, and it can only make a bundle CHEAPER: `tier = min(derived, override)`.** It is **not** added to `published_as`, whose key set is asserted exactly (ADR 0175). A missing key and `""` are identical, so **no existing row needs migration**. "The game spent more art than `role` implies" is then not representable — which is the answer to a second field that can disagree with `role`.
- **`next` gains `--tier` and `--family`; `--kind` is unchanged and still routes on `SHOT_KINDS`.** `family` is a crop and `kind` is a render graph; keeping both is what stops `--family` from silently changing `--kind` semantics.
- **Tier cost enters the `next` priority tuple at index 2** — after *canon first* and *fewest shots already made*, before the kind histogram. Cost should only break **ties** between equally useful shots, so an author is never handed 12 cameos while a lead's map token sits unrendered. First would starve the cast; last would make it noise.

## Consequences

- **The render queue drops ~41% with no row rewritten and no canon rule weakened.** Measured today: `168×12 + 24×20 + 15×22 = 2,826` against 4,554 unrendered-by-tier.
- **A `standard` bundle is still a complete character.** Deleting the tier concept costs render budget, never correctness — the same property ADR 0138 bought for the catalog by keeping generation optional.
- **The `optional` flag and the rendered-art gate must not contradict each other.** `optional: true` on a slot the character's tier requires is a **failure** (ADR 0175), or the gate is defeatable by marking everything optional.
- **`--tier` and `--family` filter during snapshot construction and must never append inside the drain.** `_next`'s existing drain already removes from a snapshot taken before the loop; that is the guard, and it must survive the new filters.
- **`sync` publishes only a character whose `standard` slots are installed**, so a half-rendered boss is authorable and previewable but not loadable. That is the honest state, and it should be reported per character rather than hidden behind a placeholder.
- **Owed, not decided here:** what raises a character out of `standard` later (a stage transition, a quest outcome), and whether a `retired` character drops to a cheaper tier or to none.
