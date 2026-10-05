# 0398 Fate-gated dialogue and quests

- Status: Proposed
- Date: 2026-10-06
- Depends on: ADR 0065 (fate is earned, never chosen, never removed), ADR 0113 (a fact ledger is the world's memory), ADR 0134 (destiny is a hub), ADR 0189 (a fate tag is a closed lineage vocabulary)

## Context

NPCs currently have no dialogue system. Quests are gated through `DestinyApi.gate` (ADR 0065/0134), which already supports `has_fate` — but there is no dialog content model and no way for a fate to change what an NPC says. The destiny module is the hub for fate-held content (ADR 0134), so fate-driven dialogue belongs here.

## Decision

### 1. FateDef.dialog_modifiers

`FateDef` gains `dialog_modifiers: Dictionary` — maps a `dialog_id` (String) to a text override (String). When the player holds this fate, the dialog generator replaces the base text for that dialog_id with the override. Empty = this fate modifies no dialogue.

### 2. Dialog generation engine

Three new files in `game/src/modules/destiny/`:

- **`DialogDef`** — base dialog content: `id`, `npc_id`, `base_text`. Authored in `game/data/dialog/dialogues/*.tres`.
- **`DialogCatalog`** — loads `DialogDef` from the content tree, mirroring `FateCatalog`'s scan pattern.
- **`DialogGenerator`** — assembles NPC dialogue: looks up the `DialogDef`, then for each fate the player holds, checks `dialog_modifiers` for a matching `dialog_id`. The override replaces the base text. Returns `{dialog_id, npc_id, base_text, final_text, modifiers_applied}`.

The engine is template + modifiers, not NLP. One dialog_id has one base text; each held fate may override it. If multiple fates modify the same dialog_id, the last one in canonical fate-id order wins (deterministic).

### 3. QuestDef.fate_gate

`QuestDef` gains `fate_gate: Array[StringName]` — a list of fate ids. When non-empty, the quest only appears if the player holds ALL listed fates. This is a convenience over `requirement` for the common case; it is checked alongside `requirement` in `QuestApi.offered` and `QuestApi.accept`. Internally it is evaluated as `{verb: "all_of", of: [{verb: "has_fate", id: f} for f in fate_gate]}`.

### 4. DestinyDef.character_dialog (data model only, implementation deferred)

`DestinyDef` gains `character_dialog: Array[Dictionary]` — each entry `{dialog_id, text}`. This is the data model for unique per-destiny-path character dialog. Implementation is deferred until the destiny path feature is built. The field is authored but not yet read by any system.

### 5. Two dialog plans

**General dialog generation (implemented now):** NPCs react to fates held. The `DialogGenerator` assembles dialogue from `DialogDef.base_text` + `FateDef.dialog_modifiers`. Any NPC can have fate-reactive dialogue by authoring `dialog_modifiers` on the relevant fates.

**Unique character dialog (deferred):** Each destiny path has unique character dialog. When the destiny path feature is built, `DestinyDef.character_dialog` will be read by the dialog generator to produce destiny-specific dialogue. The data model ships now; the reader ships with the feature.

## Consequences

- The destiny module grows three files (`dialog_def.gd`, `dialog_catalog.gd`, `dialog_generator.gd`) and one facade method (`dialog`). The facade is at its twelve-method cap, so the dialog read folds into `summary()` rather than a thirteenth method.
- Fate-gated quests work through the existing `DestinyApi.gate` mechanism. `fate_gate` is a convenience wrapper, not a second gate system.
- Dialog content is data-driven: `.tres` files in `game/data/dialog/dialogues/`.
- The earn-only invariant (ADR 0065) is preserved: dialog modifiers are read from held fates, never purchased or chosen.
- `DestinyDef.character_dialog` is authored but unread until the destiny path feature lands.
