# 0862 NPC dialogue is a data-driven node graph

- Status: Accepted
- Date: 2026-10-06
- Supersedes nothing. Closes BL-0032 / DEF-0014's "no dialogue tree".

## Context

`npc` ships 21 files and none of them is a conversation. What it ships instead is
adjacent and was measured before anything was built:

- `npc_tell_def.gd` is ONE authored body reaction, `{trigger, verb, body,
  consequence}`, matched against the cause ledger / bond class / daypart. It is
  fire-and-forget on APPROACH: no player input, no target, no memory.
- `npc_place_voice.gd` is the per-location authored face — names, manners,
  activities, opinions, tells — composed for an UNTRACKED minor. One file per
  place, not per person.
- `npc_def.gd` owns the tier, the stage ladder, the daily round, the opinions,
  the recalls and the tells. The roster remembers a person; it cannot hold a
  conversation with one.

`destiny/dialog_def.gd` + `DialogGenerator` (ADR 0398) is the closest thing to
dialogue in the tree and it is one flat `base_text` per `dialog_id` with fate
modifiers overriding it. **A line, not a graph**: no choices, no targets, no
conditions, no variables, and `game/data/dialog/` does not exist.

## Decision

**A custom data-driven node graph in a new `dialogue` module. Not Ink, not Yarn
Spinner, no third-party runtime.**

- `DialogueDef` (`.tres`, `res://data/dialogue/`) holds nodes; `DialogueNodeDef`
  holds a speaker, ordered lines and choices; `DialogueChoiceDef` holds a label,
  a target node, an optional `condition` and an optional `effect` that writes the
  variable store.
- Variables are a small typed primitive store (`bool` / `int` / `float` / `String`)
  on the player actor's `module_data` under `dialogue_state`, so `Actor.to_dict`
  is the whole save and there is no bespoke path (ADR 0027, ADR 0074's rule).
- Conditions are a CLOSED verb set over those variables plus the actor's realm,
  and an unmet condition returns a NAMED refusal. A locked choice is published
  as locked-with-a-reason, never silently hidden.
- Traversal is one step at a time: `start` → node view, `choose` → next node
  view, `end`. Nothing in the module loops over the graph.

## Why not Ink, not Yarn Spinner

- **Both are third-party runtimes**, and this repo has no external runtime
  dependency: GDScript-only, no C#, no vendored engine extension, headless-tested
  through `tools test`. An Ink runtime would be either a C# addon (banned) or a
  hand-ported interpreter, and a hand-ported interpreter is a module nobody in
  this tree can fix.
- **The domain model is already authored.** `NpcDef` tiers, `NpcStageDef`
  ladders, `SocialGate` requirement dictionaries and `FateDef.dialog_modifiers`
  are all `.tres` with a content guard. Ink's `.ink` would be a SECOND authoring
  format beside them, and the fate modifier path (ADR 0398) would have to be
  re-expressed in it — the same duplication DEF-0330 records for the word
  "doctrine".
- **The requirement is narrow.** Branching, conditions, variables, named
  refusals and a save round trip is one graph walk. It does not need a language
  with functions, threads, tunnels, lists and a compiler.

## Consequences

- `dialogue` declares `core` + `contracts` and reaches `npc` only through an
  INJECTED `Callable` (`DialogueApi.set_npc_reader`), so the seam a settlement
  panel needs is the same shape as `DomainFixtures.set_minter`. `npc` is
  unchanged: this is a module that reads an npc, never one that edits it.
- **Cycles terminate by refusing.** `choose` records every visited node and a
  target already visited returns `already_visited` BY NAME, so an authored cycle
  is a content error a test can see rather than a walk that never converges. A
  separate `MAX_STEPS` snapshot bounds the driver's loop.
- `DialogGenerator` (ADR 0398) is untouched. It still assembles a single line's
  text; a `dialogue` node may NAME a `dialog_id` and resolve it through that
  generator, so fate modifiers keep working inside a node without `dialogue`
  declaring a `destiny` dependency.
- Cost this ADR accepts: no Ink features (no tunnels, no inline conditionals, no
  `<<set>>`). If a future author needs one, the graph is the wrong tool and this
  ADR is what gets superseded.