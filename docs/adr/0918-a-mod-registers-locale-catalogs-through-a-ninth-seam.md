# 0918 A mod registers locale catalogs through a ninth seam

- Status: Accepted
- Date: 2026-10-08

## Context

Strings are content, and content is per-owner: an item's name lives in the item's own
`.tres`, and a mod ships an item by shipping that file. Localization had no equivalent. It
shipped as a single flat scan of `res://locale`, so a mod's own screen — which `mod.json`
can register through the `screens` seam — had **nowhere to put its own wording**, and every
core UI string shared one file, so any two changes to wording collided in it.

`RegistrationContext` is the locked seam surface (ADR 0184 §6: "a mod cannot grow this
interface"), so this is a reviewed change to that surface, not an ad-hoc read.

## Decision

- **A ninth seam, `add_locale_root(dir)`**, reached from a manifest `locale_roots` array the
  same way `content_roots` is. `ModRuntime.finalize` collects the roots **in load order**.
- **`L.install_roots(roots)` layers them over the base catalogs**, later-wins. One mod
  therefore overrides an earlier mod, and any of them overrides a core key by shipping the
  same key — never by editing `src/`.
- **Catalogs are per OWNER, not one file:** `game/locale/<owner>.tres`, where the owner is the
  path area (`ui_panels`, `ui_screens`, `items`, …). A key names its owner, so the file a row
  belongs in is recoverable from the key and `tools i18n check` can require it there.
- **The base load is recursive** (`ContentScan.files_under`), so an owner is a file, not a
  directory registration the app has to enumerate.
- **The English lives in the catalog, not at the call site** (supersedes ADR 0916's call-site
  English): a text change is then a DATA change, which is what makes the split meaningful and
  what a mod can override. `L.t(key, source)` keeps the optional `source` for a caller that
  genuinely has the English in hand; core UI passes none.
- **The key is STABLE and opaque once assigned.** `assign_key` mints it once — content hash,
  with a deterministic nonce when that hash is already taken by edited text — and never
  re-derives it, so `check` requires a row to EXIST, not to hash to its key. Editing the
  English is therefore a one-row data edit that leaves every other locale's translation in
  place; a content hash that `check` re-verified would have made every copy edit a re-key.
- **Authored content holds KEYS, like every other string.** `extract --scope content` rewrites
  a `.tres` display field to a readable key derived from the def's own `id` + field name
  (`LOC_DESTINY_OATH_BREAKER_DISPLAY_NAME`) and fills that owner's en catalog — so the key is
  stable across an English edit, one def is defined once for every language, and no per-language
  copy of the content exists.
- **A composed sentence resolves its keys too.** `L.t` replaces every embedded `LOC_…` token,
  so `"%s x%d" % [display_name, n]` reads correctly without every composition site resolving its
  own parts; a token with no row is left visible rather than blanked.
- **A scene's text is resolved by its SCREEN or its PANEL.** A `.tscn` literal has no call
  site, so `L.localize_tree` walks the subtree from `_bind_nodes()` — before any `summary()`
  reads a label. A panel has no shared base, so each panel calls the pass itself; the screen
  pass covers the panels nested under it. It is depth-capped and idempotent, so it is a `while`
  the arch rule can see and a repaint is free. An app scene under `game/scenes/` has no script
  at all: its literals are inventoried (`tscn_app_lit`) and NOT rewritten, because nothing would
  resolve them — the rewrite target is a scene whose owner runs the pass.
- **A display field may be a LIST.** `names = Array[String](["a", "b"])` keys each ELEMENT
  (`LOC_NPC_QI_DAO_NAMES_1`), because a composed persona picks one row and a whole-array key
  would have no reader. A code array (`plausible_tiers`) is not a display field and is left.
- **A `%`-format expression keys its message AND its argument wording.**
  `"%s - %s" % [fact, "heard" if ok else "not yet"]` holds three messages; keying only the
  leading literal would ship English inside a translated line. The template keys as a whole
  (`L.t(key) % [name, n]`) so the message translates and the data stays data.
- **A `const` in a static-only file keeps `const` and holds the bare KEY.** A `var` is
  unreachable from a `static func`, so `L.t` at the declaration would not compile; the reader
  resolves the key at the sink instead, exactly as it resolves a `.tres` field.
- **The scope is every layer that composes wording**: `.gd` in `ui/`, `modules/` and `core/`
  (a persona composer's default manner, a realm name), plus `data/`, plus the `src/ui` scenes.
  `app/` and `contracts/` compose no wording and stay out.
- **Counted text is `L.tn(key, count)`**, which takes the singular row and the locale's `key_1`.
  A text `.tres` `Translation` carries no CLDR rule, so the form COUNT lives in an explicit
  table and an unlisted locale is refused loudly rather than given an English-shaped plural;
  a locale needing more than two forms must wait for a catalog format that can hold them.
- **`L.set_locale(code)` switches and returns false when no catalog is loaded**, so a caller
  can refuse rather than half-switch. A non-Latin locale additionally needs a font with its
  glyphs, and the theme declares none today — so no such locale ships until that asset lands.

## Consequences

- A mod localizes or overrides without touching core; two mods never share a catalog file.
- A key with no row resolves to the key, so a missing row would show a slug. `tools i18n
  check` (in `tools check`) is what refuses to ship one — the gate, not the runtime, is the
  guard.
- `L.install()` stays lazy (the first `t()` installs the base), so a headless test needs no
  harness hook; mod roots are layered only after the app wires them at boot.
- ADR 0184 §6's seam count moves from eight to nine; the vocabulary is otherwise unchanged.
