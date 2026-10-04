# 0175 A character's assets are a second index keyed by shot, and the game reads only authored resources

- Status: Proposed
- Date: 2026-10-04
- Extends: ADR 0138 (the named cast is a separate catalog; `published_as` is the only field pointing at game content), ADR 0153 (`kind` is how to render, `slot` is why the shot exists), ADR 0155 (uniqueness judged on prose), ADR 0144 (the Lore Bible is canonical)
- Precedent copied: `tools/character_assets.py:269-309` (`_atomic_write`), `:219-238` (`_shard_is_complete`), `:172-191` (`_catalog_paths`), `:241-266` (`readable_catalog`)

## Context

The named cast holds one JSONL line per character with `art.shots[]` inlined. Every canon row carries **22 shots** (7 single-shot slots + 9 `expression_set` + 6 `pose_set`), so one hand-editable prose line is now also a 22-row machine-written block — inside a file **eight agent sessions are appending to right now** (`unique-index-wave-11a..f`, heartbeats minutes old).

Measured, and load-bearing:

- **Nothing in `game/src` reads this catalog.** `published_as` has zero readers; there is no `unique-index` reader; `PortraitResolver` resolves only from five authored `res://data/portraits/*.tres`. `game/assets/asset-index.jsonl` — the item program — also has **zero** readers. Asset programs here are green and unwired by default, and this is not a defect unique to characters.
- **The one sanctioned bridge already exists and is unused.** ADR 0138:40-45 promises `published_as` "stays empty until a deliberate sync step writes an authored resource". `PortraitCatalog` (`core/portrait_catalog.gd:76-87`) already scans `res://data/portraits`, text-scans for `script_class="PortraitDef"` before `load()`, and keys by `def.id`.
- **Two traps that make the obvious implementation fail loudly.** `_catalog_paths()` globs `unique-index-*.jsonl`, so an asset file named `unique-index-assets.jsonl` is read as a **character** file and every asset line fails `ID_RE` — breaking `check` for all eight writers. And `published_as` is asserted with an **exact** key set (`unique_characters.py:637`), so adding a key is a hard failure for all 207 rows.
- **`layer_paths` compositing is declared and deliberately not performed** (`core/portrait_panel.gd:146-154` loads the first loadable path and returns). A bundle of layered art has no renderer today. ADR 0177 owns that; this ADR owns the indexing that feeds it.

## Decision

**Assets live in a second index, keyed by shot. The game reads authored resources and never the JSONL.**

- **A second file beside the catalog: `game/assets/characters/unique-assets.jsonl`, shards `unique-assets-<shard>.jsonl`.** Never `unique-index-*` — the character glob would read it. Both stay tracked: `.gitignore`'s `game/assets/characters/*/` is a *directory* rule, verified with `git check-ignore`.
- **Primary key is `(character_id, shot_id)`; the sort key is that TUPLE, never a bare string.** `ID_RE` allows ≥4 digits, so `unique-10000` sorts before `unique-9999`; a bare `sorted()` reorders shards at 10,000 characters silently. `_atomic_write` gains `path=` and `key=` as keyword-with-default arguments — strictly additive, every existing call site untouched — because a second writer would be the ADR 0066 failure mode.
- **A line's own fields win; the character line keeps the prose.** The union overlays asset-owned fields (`kind`, `slot`, `family`, `canvas`, `anchor`, `path`, `status`, `optional`, `reuse`, provenance) onto the shot, while `pose`/`expression`/`framing`/`scene` stay on the character line — because `_brief` (`unique_characters.py:1082-1144`) assembles the art brief from that prose, and an installed shot's brief must not change under it.
- **`family` is DERIVED from `slot` via `SLOT_FAMILY`, never authored.** A closed set beside the existing `SLOT_KIND`, with the same treatment: a disagreement is a **failure**, not a note. This is what extends ADR 0153 rather than amending it — the nine required prompts and their distinct-text counting are untouched.
- **`reuse` may only name ids that ALREADY EXIST.** Verified present: a `WorldFact` fact id (flat, unprefixed), the catalog's own lore ids (`races.*`, `geography.*`, `organizations.*`), a `RealmDef.id`, a cultivation path, a status/element/technique id, an `NpcDef.npc_id`, an `NpcStageDef.stage_id`. Explicitly **not** added: a day-part axis (0178), a combat phase (no such vocabulary exists — the S1–S12 list is prose in `combat_engine/spine.gd` comments), and a closed emotion enum (ADR 0153 requires expression prose and counts it on *distinct text*; an enum re-opens exactly that hole).
- **`optional` defaults to `false`.** A field whose default grants an exemption is an exemption nobody earned. `optional: true` on a family the tier requires is a **failure**, or the gate is defeatable by marking everything optional.
- **Migration is additive in two releases, and the order is the safety.** Release 1 reads the **union** and writes nothing: an agent may keep authoring `art.shots` exactly as today and be fully correct, because every consumer reads the union. Release 2 migrates **one shard at a time**, refusing on a torn shard (`_shard_is_complete`), reading strictly rather than `readable_catalog`, writing the asset lines durably *before* emptying `art.shots`, then re-reading strictly and refusing if anything moved. A character still holding `art.shots` is valid and complete, so there is never a window where a partially migrated character is wrong.
- **`published_as` becomes a required-SUBSET check and a receipt, never a key.** `{"portrait_id", "def_path"} - set(published)` replaces the exact-set assertion. But the game must not depend on it: the `.tres` **filename is the id**, and a field duplicating the id is a second source of truth (the ADR 0050 keyed-by-id argument). A missing receipt is not a content gap.
- **`sync` writes text and never starts Godot.** Every file goes through the existing `NamedTemporaryFile` → `os.replace` → `finally: unlink` pattern. The `--import` pass belongs to `install`, which already writes PNGs, and goes through `tools.godot.run_godot` (`character_assets.py:1426-1438`); a subprocess call inside `sync` is what `tools godot_bypass` exists to catch.

## Consequences

- **The feature needs no new module, no registry entry, and no `ui/` permission change.** `core/` may read authored `.tres` and `ui/` may reference `core`; the catalog's JSONL stays outside `res://src` entirely. ADR 0138's "no tool adds an edge from `res://src` to either catalog" **holds as written** — this ADR fulfils its promise rather than superseding it.
- **An install writes one ~600-byte line instead of rewriting a multi-kilobyte character record**, which is what shrinks the write-collision blast radius the shard machinery exists to survive.
- **Two agents can render two shots of one character without touching one another's lines.** A writer must be told which shard it owns, and must refuse if the row exists in a shard it was not told to own — `_atomic_write` is last-write-wins per key and will otherwise drop a write with no error.
- **Every new invariant needs a red-path case in `tools/selftest_cases.py`** (INC-0016). The tuple sort, the glob-collision name, the subset check and the `optional` refusal each need a fixture that fails when the guard is removed.
- **A character line stops being a one-line-per-character document.** Accepted: the prose contract that justified inlining (ADR 0138:97) is preserved for the fields an author edits, and the machine-written half moves out.
- **Owed, not decided here:** the renderer's per-family graph (ADR 0177), the tier that decides what gets rendered at all (ADR 0176), and the activity vocabulary a daily schedule draws on.
