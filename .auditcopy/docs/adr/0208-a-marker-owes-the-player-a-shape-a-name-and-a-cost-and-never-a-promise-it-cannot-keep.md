# 0208 A marker owes the player a shape, a name and a cost, and never a promise it cannot keep

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0846 (the marker half)
- Builds on: ADR 0206, ADR 0207

## Context

A POI marker is a **deferred assertion**: it claims "there is something here worth
crossing a room for" before the player has seen it. In a room list that promise is
cheap — one line of text, dismissed on sight. On a floor plan it is expensive, because a
glyph placed at a room's centre anchor is read as *that is the thing*, at a distance,
before the player can resolve it. A marker that overstates costs the player a walk they
did not choose to spend.

The repo has already fixed the marker set and, crucially, its **source**:

- `POI_BY_TAG` (`domain_minimap.gd:39-45`) is a closed five-entry table — `boss`,
  `elite_guard`, `puzzle`, `refuge`, `treasure` — keyed by authored room tags, and
  `POI_TAGS:49-55` publishes the set so a consumer enumerates it without a room.
- ADR 0073: tags drive "the minimap POI layer **from one source** — never a post-hoc
  heuristic". A tag absent from `POI_BY_TAG` marks nothing (`:38`): an unknown tag is
  "content this build has not learned to draw, not a reason to invent a marker".
- `_pois` (`:147-175`) emits one marker per (room, tag) pair at `rect.get_center()`,
  canonical tag order so a room's POIs read the same on every render.
- `tier` rides every marker (`:172`) and is derived by `_tier_of` (`:246-256`), which
  prefers the authored tag, then the spawn role (ADR 0074), then the kind's default band.

The invariant this ADR protects is therefore not "markers are consistent" but
**"a marker's glyph may only be as strong as the authored tag behind it."**

## Decision

**Every marker glyph is a fixed promise bound to its `POI_BY_TAG` key, drawn from a
CLOSED `MARKER_GLYPHS` table. No glyph is chosen by rank, by distance, by room size, or
by anything the UI can compute — only by the tag. A marker never implies a number,
a difficulty or a reward that the payload does not publish.**

### Glyph vocabulary — shape carries the promise

The five keys get five distinguishable silhouettes, because at minimap scale colour alone
is unreadable and shape is what survives. None of them is a bar, a number, or a bar-with-
a-number, and none implies "this is hard":

| marker | glyph | the promise | what it must never imply |
| --- | --- | --- | --- |
| `refuge` | open circle | somewhere safe to stand | that it is *available* — a refuge that does not open is content's refusal, named in the room list |
| `treasure` | diamond | something is here to open | its value, or its key |
| `puzzle` | nested squares | something must be solved | how many nodes, or that a wrong strike is cheap |
| `elite_guard` | chevron | something is guarded | the guard's strength, or how many |
| `boss` | filled disc with a ring | the run's climax | that it is beatable now — `tier_rank` is a label, not a licence |

`tier` (`room`/`miniboss`/`boss`, ADR 0073) renders as a **text chip beside the room
label**, never as a glyph upgrade: a room that is `miniboss` because a spawn role says so
and carries no POI tag must not gain a glyph, or the marker set stops being tag-derived.

### What a marker owes

1. **Position from the payload.** `pois[].anchor` verbatim. A marker the drawing moved
   is a second description of the place.
2. **A name in the legend.** Five glyphs, five legend rows, keyed by the same strings. A
   marker shape a player cannot decode is a lie about discoverability.
3. **A cost.** The corridors that reach it — drawn, already in `routes[]`. A marker two
   corridors deep is visibly further, which is the whole "spend a step" idea from ADR 0207.
4. **A resolution on arrival.** The room is remembered: the marker draws at full strength
   and the room list names what the fixture actually is. A marker still vague after the
   player is standing in the room has failed to keep its half.

### What a marker must never do

- **Never appear on a frontier room** (ADR 0207) — an unfilled outline carries no marker.
- **Never be synthesised for a tag `POI_BY_TAG` does not name.** `domain_minimap.gd:160-162`
  already skips unknown tags; the drawing must not have a fallback glyph, or the skip
  becomes invisible.
- **Never render a count or a severity as its own glyph.** The zone layer owns severity
  (`domain_minimap.gd:183-201`) and the population readout owns roles
  (`domain_explore_model.gd:676-683`); a number on a marker duplicates a fact in a place
  that cannot be read precisely.

## Consequences

- `MARKER_GLYPHS` is a `const` dictionary in the panel keyed by the same five strings;
  `summary()` publishes `markers_drawn: int` and `marker_kinds: Array[String]` so a test
  asserts the glyph table and the payload agree — a test never counts pixels.
- **Trade-off rejected:** colour-coding markers by `tier_rank`. Cheapest to implement, and
  exactly the ADR 0073 heuristic — a visual channel reading a derived number, unreadable
  at minimap scale, unlabelled for colour-blind players.
- **Trade-off rejected:** a `boss` marker scaled or pulsing by `tier_rank`. Size and motion
  read as intensity, so the map would claim a difficulty gradient the tags never stated.
- **What would change my mind:** authored content shipping a sixth `POI_BY_TAG` key that
  cannot be distinguished at 32 px — a content + table change, not an architecture change.

### `summary()`

`markers_drawn: int`, `marker_kinds: Array[String]` (sorted, from `MARKER_GLYPHS` keys),
`legend_rows: int`. All primitives; the panel asserts `marker_kinds` is a subset of
`POI_TAGS`, which is the testable form of the one-source invariant.