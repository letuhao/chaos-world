# Every authored portrait ships a committed fallback face, so an untracked art supply is a visible gap and never an empty box

Status: accepted

## Decision

Every `PortraitDef` under `res://data/portraits/` names a layer that **exists in the repository**.
Where the real render is not tracked, that layer is a **committed fallback face**: a small,
unmistakably-placeholder silhouette on a transparent ground, 384x512 — the `dialogue_portrait`
install canvas from `character_assets.py:268` — tinted from the body's dominant `affinities`
entry.

`game/assets/characters/portraits/` is the one subdirectory under `game/assets/characters/` that
is **not** gitignored. Everything else there stays private and regenerable.

## Why

Measured 2026-10-05: `git ls-files 'game/assets/characters/**/*.png'` returns **zero**. The art
supply is entirely untracked while the 21 `.tres` files that declare those paths are tracked. On a
clean clone every portrait is therefore an empty box — including the seventeen that resolve on the
developer's machine, which is the worst kind of gap: it looks finished locally and is blank
everywhere else.

Three options existed: track all ~51 MB of art, make the missing state visible in the UI, or commit
a small fallback per authored body plan. **Tracking everything was rejected** because the art lives
inside another repository and 51 MB per character is not a game asset. **Making the gap visible in
the UI was rejected as the sole answer** because it tells the player something is wrong without
giving them a face, and because `ui/` may not reach module internals to do it cheaply.

A fallback silhouette is the smallest thing that makes the authored `.tres` files *true*. It also
makes the remaining gap legible: a silhouette reads as "no portrait yet" in a way an empty box does
not, so the difference between a fallback and real art is visible rather than inferred.

## Consequences

- **A fallback never claims to be art.** It is a flat silhouette with no face, so it cannot be
  mistaken for a render, and no gate treats it as fidelity-passing. `art_fidelity` reads only the
  private art folder, so a committed fallback is never measured against a palette and never fails.
- **The tint is derived, not authored.** Dominant affinity decides the hue: `fire` warm,
  `earth` brown, `water`/`ice` cool, and a body with no dominant affinity (`commonborn`, all
  affinities 2.0) is neutral grey. Two bodies that share a dominant affinity share a tint, which
  is correct — the fallback identifies the *body plan*, not the individual.
- **Replacing a fallback with real art is a one-line change** to the `layer_paths` entry and
  nothing else. The fallback is not a separate resource the game must know to bypass.
- **`PortraitResolver.validate()` now passes for every authored portrait**, so the missing-file
  guard added in `50bd6d51` reports zero problems on a clean clone. That is the point of the
  commit: the guard stays useful because a genuinely missing layer is still reported, and it stops
  firing on a gap that was never going to be fixed here.
- **`emberblood_touched` has no `PortraitDef` at all**, so it resolved through
  `PortraitIndex.character_for_race`, which cannot match (no index row carries an authored race
  id). Giving it a fallback file does NOT make it reachable — it needs an authored `.tres`. That is
  tracked separately and this ADR does not claim to have fixed it.
- The art itself remains untracked and regenerable. This ADR changes what is *committed*, not what
  is *generated*.