# 0916 Localization keys with the source English at the call site

- Status: Accepted. The **call-site English is superseded by ADR 0918** — the English now
  lives in a per-owner catalog, so a text change is a data change. The resolver, the slug
  shape and the measured engine facts below still stand.
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
- **Catalogs are text `Translation` resources** at `game/locale/<stem>.tres`, written only by
  `tools i18n extract` and registered by `L.install()` — never by `project.godot`, whose
  startup load is unreliable. **Only `en` ships; any other locale is owner-demand work** (a
  `<stem>.<locale>.tres` appears only when the owner asks for that locale), never
  machine-authored.
- **One tool:** `tools i18n report|extract|baseline|check`; `check` runs in `tools check`.
- **Every `.gd` sink is rewritten:** a literal to `L.t(slug, "literal")`, an expression to
  `L.t(expr)` (a no-op unless it is a content slug), and a display `const` to
  `var NAME := L.t(...)` — a `const` cannot hold a function call, so the keyword changes.
- **Enforcement is a growth baseline, not a big bang.** `game/locale/gaps.json` records each
  UI script's sink count, and `check` fails a script that GAINED a sink — so new text must use
  `L.t` while the existing sinks migrate in later waves.

## Consequences

- English needs no catalog and tests need no registration; an English edit produces a new
  slug rather than orphaning a translation.
- A display `const` becomes `var`, which is why a prose `const` is not left as a constant.
- `.tscn` literal `text` and authored `.tres` content cannot call a helper; they are
  inventoried by `report` and remain a later wave, not silently half-done.
- The `en` catalog restates the source English; it is a generated artifact whose equality
  with source is enforced by `check`, not a second source of truth.
