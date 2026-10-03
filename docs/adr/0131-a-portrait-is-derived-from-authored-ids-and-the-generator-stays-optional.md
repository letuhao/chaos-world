# 0131 A portrait is derived from authored ids and the generator stays optional

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0050 (keyed by authored id, never by position), ADR 0062 (a race is a body
  plan, not a stat stick), ADR 0130 (a returning soul creates again)

## Context

Characters need faces. The generator that will produce them is deferred, and the item asset
tool in this repo generates thousands of icons — so the tempting path is to author a tool
first and let the game read whatever it wrote.

That makes the tool load-bearing for correctness. Deleting the index then deletes every face,
and a rendering step becomes a runtime dependency of a save's identity.

The existing rule to follow is already written down: the realm power table is keyed by realm
id and never by position, precisely so an inserted entry cannot shift everything else onto
the wrong number. A portrait follows the same rule for the same reason.

## Decision

**A portrait is authored data keyed by id. The resolver reads authored resources and never
reads the asset index, so the generator stays optional.**

- **`PortraitDef` is an authored resource carrying an id, a race, a set of layer paths and a
  palette key — keyed by id, never by an array position.** `core/` is its home because an
  identity keyed by authored ids is foundation, and `core` is a layer so the facade rule never
  applies to it. It is not in `contracts/`, because authored resources do not live there.
- **Resolution is total and ordered, with every step named.** A stored portrait id wins; then
  the actor's race resolves to a family; then a placeholder that always exists. The resolver
  can never return null, which is what lets an NPC that never went through creation have a
  face without any special case — and NPCs are the common case, not the exception.
- **Resolution is a pure function of actor state.** The same actor resolves to the same
  portrait every time, with no randomness and no index position, so a save reloads with the
  face it was created with.
- **The resolver reads the authored resource, never the index.** The generator writes a PNG
  and an index row; a separate sync step turns index rows into authored resources. Delete the
  whole index and every actor still resolves. A test asserts the resolver's source contains no
  filesystem access, which is what keeps the tool optional.
- **A portrait grants no stat, ever.** Appearance is pixels. If it granted numbers it would
  become a balance surface, which is exactly what ADR 0062 forbids a race from being. A test
  asserts two actors differing only in portrait have identical base stats and identical open
  paths.
- **The index is a separate file from the item asset index**, because the item audit hard
  requires the item icon type and would fail every portrait row. It follows the item index
  conventions exactly — one JSON object per line, an id, a `res://assets/` path that exists on
  disk, namespaced visual traits, and single-value form and palette axes.
- **`ui/` never calls the resolver.** A screen receives a primitives-only dictionary through
  the same injected seam the creation screen already uses, and a panel applies the path
  strings. `ui/` gains no edge the gate has not granted.

## Consequences

- **A placeholder row is mandatory**, and the asset audit fails without it. A missing face must
  be a visible placeholder, never a null that a panel has to defend against.
- **The generator lands later without a refactor.** Its contract is `register` plus `run`,
  deterministic, non-interactive, non-zero on failure, writing only under the generated art
  directory and never into `src/`. It appends the index atomically and re-reads it after a long
  render, because a concurrent edit may have landed while it was rendering.
- **One authored asset family per race is the minimum**, and the audit fails when a race has
  none — otherwise the placeholder silently becomes the face for a whole body plan.
- **The creation flow gains a presentation step that grants nothing.** It writes a display name
  and a portrait id, both of which already round-trip through `Actor.to_dict`. It must not gain
  an earn verb: the structural guard that pins exactly one origin earn in the creation flow
  exists precisely to stop this becoming a picker through the back door.
