# 0257 A hero chooses a face at creation, and one asset set serves every character

- Status: Accepted
- Date: 2026-10-05

## Context

`PortraitResolver` is total and deterministic (ADR 0131): `resolve` falls back through a
variant, then the race, then a placeholder, so every actor has a face. The soul/hearth
screen renders it at `soul_hearth_screen.gd:531`.

**Choosing is a separate verb and nothing calls it.** `PortraitResolver.choose` (line 124)
has zero production callers — verified by grep over `game/src`, which returns three hits for
`PortraitResolver.` and none of them `choose`. The screen calls `resolve` directly. So
`chosen_portrait_id` (line 116) always answers `""`, nothing is ever written to
`module_data`, and a player's face is recomputed from their race every time rather than
being theirs. `BL-0882` tracks it.

Meanwhile the asset pipeline has produced a large body of character art —
`game/data/portraits/` holds a base portrait per race plus hundreds of `unique-NNNN`
portraits with expression and pose variants, and `tools/unique_characters.py` is still
adding to it. That art is currently reachable only by an NPC's authored traits. A hero
cannot look at it and say "that one".

Two facts constrain the answer. `PortraitResolver.choose` writes to `module_data`, which
`Actor.to_dict` copies verbatim, so a chosen face already survives a save — the transport
exists. And BL-0883 measured that ~90 portraits currently declare a variant another
portrait already owns, which matters here because a picker makes shadowing *visible*: two
options that look identical are a worse bug when a player chose between them.

## Decision

### 1. The player picks a face at creation, from the authored catalogue

A creation-screen control offers faces the player can actually choose between, and the
choice is recorded through `PortraitResolver.choose` — the existing verb, unchanged. No new
persistence path, no second copy of the field.

**This is not the forbidden picker.** ADR 0065 forbids a picker over *fates and destinies*,
because the destiny decides the story and a player who picks their own story trivialises the
run. A face decides nothing: it changes no gate, no arrival, no stat, no fate. The rule
protects the run's structure and appearance is not structure.

### 2. The SAME assets serve player characters and NPCs

One catalogue, one resolver, one set of `.tres`. A player-chosen face and an NPC's
trait-resolved face come from the same pool and obey the same fallback chain, so an NPC can
never be drawn with art a player could not have chosen and vice versa.

This is the composition move rather than the duplication move: a second asset path for
heroes would drift from the NPC one within one content wave, and the existing
`tools/character_bundle_sync.py` and `portrait_fallback.py` tooling already treat the tree as
one corpus.

### 3. Options are filtered to what the hero may have, then presented

The picker offers portraits the hero's race may wear, and every option is one that
`resolve` would honour — so choosing can never produce a face the resolver would then
override. The list is bounded and deterministic in sorted id order, like every other
catalogue read in the tree.

**The bound is a hard requirement, not a nicety.** A list built by walking the catalogue is a
`for` over a data-derived row count with one live control per row, which is the shape
`AGENTS.md` and the recorded 67 GB incident are about. Bound it through the existing
`RowBudget.cap()` — one shared number, because six independently-chosen caps would drift and
the one that matters is the smallest — and say so in a comment at the call site.

### 4. Shadowed variants are resolved BEFORE a picker ships

BL-0883 is a prerequisite, not a follow-up. A picker over a catalogue where ~90 entries
render identically presents the player a choice that is not one, and the loser's art is
unreachable for an NPC too. Fix the shadowing first — by disambiguating the generated
traits, widening `for_variant`, or cutting the duplicates — and the last of those three
decisions wants its own ADR if `for_variant` is widened, because it changes ADR 0177's
"first in sorted id order".

### 5. Choosing is optional and never blocks creation

A hero with no chosen face resolves exactly as they do today: race, then placeholder. The
picker is an offer, not a gate, so a creation flow must not be able to fail because the
portrait catalogue is empty or a fetch failed.

## Consequences

- `character_creation.tscn` gains a face control; `character_creation_flow.gd` calls
  `PortraitResolver.choose` on commit.
- `PortraitResolver.choose` gains its first production caller and stops being an unused API.
- BL-0882 is answered. BL-0883 becomes a blocker for it rather than a parallel content chore.
- `portrait_panel.gd` can show a chosen face distinctly from a resolved one.
- The soul/hearth screen's direct `resolve` call stays correct — it renders whatever the
  hero has, chosen or derived.

## Rejected

- **No picker; derive the face from creation answers.** Cheaper, and it keeps the surface
  small, but it leaves a large authored asset corpus visible in the repository and
  unreachable by the person it was made for.
- **A separate hero-only asset path.** Two corpora drift, and the existing tooling already
  assumes one.
- **Letting the player pick a destiny at the same time.** That is ADR 0065's picker, one
  screen away.
