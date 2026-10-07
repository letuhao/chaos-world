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
  copy of the content exists. A reader that COMPOSES a sentence from fields must resolve each
  field (`L.t(field)`), because a whole composed string is not a key.

## Consequences

- A mod localizes or overrides without touching core; two mods never share a catalog file.
- A key with no row resolves to the key, so a missing row would show a slug. `tools i18n
  check` (in `tools check`) is what refuses to ship one — the gate, not the runtime, is the
  guard.
- `L.install()` stays lazy (the first `t()` installs the base), so a headless test needs no
  harness hook; mod roots are layered only after the app wires them at boot.
- ADR 0184 §6's seam count moves from eight to nine; the vocabulary is otherwise unchanged.
