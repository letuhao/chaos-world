# 0138 The named cast is a separate catalog with prose stats and free-form shots

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0131 (a portrait is authored data, the generator stays optional), ADR 0064
  (position and standing never derive from each other)

## Context

`tools/character_assets.py` generates the anonymous cast: 2,000 balanced
`character-NNNN` profiles whose whole identity is twelve `axis:value` tags, one
PNG per fixed slot, and one shared style string. That is the right shape for a
crowd and it is now producing art.

It is the wrong shape for a named character. A boss the player remembers needs
lore, an ordered history, a personality with flaws and a voice, and several
images at different poses — not one sprite and one portrait derived from a trait
string. Forcing that into the existing record means either twelve more closed
axes or a prose field on every one of the 2,000 rows, both of which weaken the
balance guarantee the crowd catalog exists to provide.

Two decisions are also load-bearing and easy to reverse by accident. "Initial
stats" is a number-shaped field, and this repo has already been bitten by an
added power curve that no gate could see. And the art needs a ComfyUI workflow
that does not exist yet, so the deterministic half has to stand on its own.

## Decision

**The named cast is its own catalog, its own id namespace, and its own folder.
Stats are prose. Shots are free-form. Generation lands separately.**

- **`game/assets/characters/unique-index.jsonl` is a separate index, keyed by
  `unique-NNNN`.** Nothing links it to `character-index.jsonl`, in either
  direction. A named character is not a promoted `character-NNNN`, so authoring
  one cannot perturb the 2,000-row balance, and deleting this catalog cannot
  delete a face. The art folder is `game/assets/characters/unique/<id>/`, which
  the existing `.gitignore` rule `game/assets/characters/*/` already excludes —
  so the catalog and its prose stay tracked while every PNG stays local, with no
  new ignore rule.
- **This is reference data and the game never reads it.** `PortraitResolver`
  resolves from authored `res://data/portraits` resources and
  `tests/core/test_portrait_resolver.gd` asserts the resolver's source names
  neither index (ADR 0131). `published_as` is the only field pointing at game
  content; it stays empty until a deliberate sync step writes an authored
  resource. No tool adds an edge from `res://src` to either catalog.
- **`reference_stats` is prose, and a guard enforces it.** It says how a
  character fights, not what it computes. A number there is the exact shape a
  balance surface takes, and a balance surface reached by editing a reference
  document is invisible to every guard that exists: `realm_power check` reads the
  authored power table, `tools arch` reads the module graph, neither sees a JSONL
  row. `unique_characters check` therefore rejects a bare JSON number anywhere in
  the block, and a number assigned to one of the authored stat ids — in a key or
  in prose (`physique: 40`). The id set is read from `contracts/stat.gd`, so a
  stat added to the game is covered without editing the tool. A digit that is part
  of a name is not a stat and still passes, which is why the match is on stat ids
  rather than on any digit.
- **Shots are free-form; kind is a routing vocabulary.** A shot carries its own
  `id`, `kind`, `pose`, `expression`, `framing`, `scene`, and `canvas`, so one
  character can hold a concept sheet, five portraits, and three scenes without the
  schema changing. `kind` is the one closed set — `concept`, `portrait`,
  `dialogue` — because it selects the generation workflow, and those three need
  different graphs. Adding a kind is one line.
- **Per-character canvas, not a fixed slot size.** A scene illustration and a
  concept sheet are not square, so `canvas` belongs to the shot and the installed
  PNG must match it exactly. A fixed 512×512 is what makes a crowd cheap and a
  named character look wrong.
- **`art.style` is a free-form slug, not yet an enum.** The art direction has not
  settled the style vocabulary, so guessing one here would only produce values
  that have to be corrected when the ComfyUI workflow arrives. `report` prints
  the inventory with counts so a typo is visible; the closed vocabulary is added
  when the backend that routes on it exists.
- **Tag axes are free-form; shape is gated.** A named character carries axes the
  crowd catalog has no slot for. A typo'd axis is caught by reading `report`,
  which prints every axis and value with counts — cheaper than failing a record
  for inventing one.
- **`draft` and `canon` are different promises.** A draft may be unfinished, so
  `add` creates a whole record in one command. Promoting to `canon` is the gate:
  lore, a personality summary, a prose stat summary, an art style, and every
  appearance key must be written, because `canon` claims the narrative exists.
- **The stat guard has a self-test that proves it discriminates.**
  `tools/selftest` asserts a number is refused AND that ordinary prose containing a
  numeral ("the 9th Brother", "three gates") still passes. A suite asserting only
  the first would also stay green under a guard that rejected every digit, which
  would make the block unwriteable and drive an author to worse lore to satisfy the
  linter.
- **Generation is deliberately absent.** `plan` renders the art brief — identity,
  appearance, pose, framing, canon, and the standing content constraints — which
  is the deterministic half and the part that can be reviewed and refined now. The
  ComfyUI half lands separately. A generate path that cannot run would be a
  generate path that rots unobserved.
- **`unique_characters check` runs in `tools check`.** It is the shape of every
  other content guard here, and it is what keeps the stat rule and the provenance
  fields from eroding between balance passes.

## Consequences

- **The catalog is authored by hand, one line per character.** The record is
  small and single-line, the same contract as a hand-authored `.tres`, and `check`
  is what verifies it. `add` scaffolds; it does not generate prose.
- **A style vocabulary and a fourth shot kind are both additive.** Neither needs a
  migration: a new kind is a constant, and a style only becomes checked once a
  backend routes on it.
- **The renderer must consume `plan` output unchanged.** The brief is assembled
  from canon rather than typed per shot, so a portrait and a concept sheet of one
  character cannot disagree about who they are — the failure the crowd catalog
  avoids with a shared seed and a trait string, and which prose makes much easier
  to reintroduce.
- **`build/unique-character-preview/` holds contact sheets** for visual review,
  gitignored with the rest of `build/`.
