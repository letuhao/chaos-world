# 0916 Localization keys with the source English at the call site

- Status: Accepted
- Date: 2026-10-07

## Context

The game ships English only and has no localization at all: player-facing text is hardcoded
in UI scripts, in `.tscn` scenes, and in authored content under `game/data/`. The new
requirement is English by default, a deterministic extractor that assigns each string a
stable id, and catalogs a translator can manage in one place.

The engine's obvious path does not survive measurement. On Godot 4.7.2 headless, a
translation listed in `project.godot`'s `locale/translations` is loaded before the resource
loaders exist and does not resolve (`No loader found`); the CSV translation importer emits a
binary `OptimizedTranslation` that cannot be diffed or hand-edited; and `Label.text` stores
and returns the RAW key, not the resolved string — so a panel's `summary()` (the repo's whole
UI test contract) would read a slug instead of English.

## Decision

- **One resolver: `L.t(key, source)`** (`game/src/core/localize.gd`). Source carries the
  English at the call site — `label.text = L.t("LOC_UI_AB12CD34", "Wait a season")` — and
  `L.t` returns the catalog translation when one resolves, else the call-site English. English
  is the default by construction, not by a special case.
- **The key is a stable slug:** `LOC_<AREA>_<sha1(english)[:10]>`. The area prefix is
  readable; the hash keeps the id stable across file moves and stops an English edit from
  silently re-pointing an old translation.
- **Catalogs are text `Translation` resources** at `game/locale/<stem>.tres` (`ui`,
  `content`), written only by `tools i18n extract` and registered by `L.install()` — never by
  `project.godot`, whose startup load is unreliable.
- **One tool, three jobs:** `tools i18n report|extract|check`. `check` runs in `tools check`
  and fails on any catalog/source disagreement, a reused slug, an orphan row, or a literal
  left in a file that already adopted `L.t`.
- **Scope for the first wave:** `.gd` display sinks. Display `const`s, `.tscn` literal
  `text`, and authored content (`.tres`) are inventoried by `report` and migrate later.

## Consequences

- English needs no catalog and tests need no registration; an English edit produces a new
  slug rather than orphaning a translation.
- A display `const` cannot hold `L.t(...)` (no function calls in a constant expression), so
  consts and scenes/content are a later wave, not silently half-done.
- The `en` catalog restates the source English; it is a generated artifact whose equality
  with source is enforced by `i18n check`, not a second source of truth.
