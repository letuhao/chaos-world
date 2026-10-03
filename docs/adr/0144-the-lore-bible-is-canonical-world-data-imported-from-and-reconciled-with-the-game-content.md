# 0144 The Lore Bible is canonical world data, imported from and reconciled with the game content

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0050 (keyed by authored id, never by position), ADR 0131 (a portrait is
  authored data, the generator stays optional)

## Context

Character generation needs background to inherit. The tempting shortcut is to ask the
character generator for lore, which makes an art tool load-bearing for correctness: delete
its index and every character's history is gone, and a save's identity now depends on a
rendering step. That is ADR 0131's exact failure, one layer up.

The second risk is the opposite one. The repository already ships 15,002 authored `.tres`
records, and a "Lore Bible" authored beside them will drift, because nothing reconciles the
two and nothing notices when they disagree. Worse, 506 of those records are content-free: a
boss is a name and a loot table, a domain is a name and a boss list. They look like a
catalogue and are actually 506 holes.

## Decision

**The Lore Bible is a separate canonical index in JSONL. The authored game content is
imported into it as external references, and stubs stay visible as stubs.**

- **`lore/bible/<domain>.jsonl` is canonical and is NOT shaped like the engine.** The brief
  says "what exists, where it came from, why, what it is connected to"; a `.tres` says what
  the engine needs. Keeping them separate is what allows lore to be richer than the schema
  and lets game data be generated from lore later, deterministically, rather than lore being
  squeezed into what the engine already models.
- **Ids are namespaced `<domain>.<slug>`** and never collide with game ids. `races.emberblood`
  and the `RaceDef` at `game/data/races/emberblood.tres` are two records with an explicit
  link, so a rename in either place is detectable instead of silent.
- **`lore ingest` imports the authored tree and is deterministic and idempotent.** Re-running
  it produces byte-identical records, asserted by a self-test, because an importer that
  churns on re-run destroys the history of who wrote what.
- **A content-free authored record imports as an explicit stub, not as invented prose.** Its
  summary says it is a gap and `lore_depth` is `stub`, so `lore gaps` counts 506 real holes
  on day one. An importer that wrote plausible fiction for 331 bosses would leave the bible
  looking authored where nothing is authored.
- **Entities are sharded by domain, edges by batch.** One agent owns one domain file and
  appends to its own edge shard, so parallel authoring cannot lose a write. One shared index
  rewritten by twenty agents silently drops half a wave, and a bible that silently lost half
  a wave looks complete.
- **Relationships are first-class data in a separate file**, not embedded in entities, so
  traversal, density and contradiction checks read one structure and an entity record stays
  a small greppable line.
- **`lore brief` embeds the live state into every agent's task** - what exists, the type
  distribution, the detected gaps, and the authored constraints read from `game/data/world/`.
  This is how "search before you create" is made enforceable rather than aspirational: a
  stale hand-written task list sends an agent to build the fifth sect that already exists.
- **Validation fails on defects in a line somebody wrote** (dangling ids, exclusive-relation
  clashes, bad slugs, self-reference, missing authored counterparts) and **reports isolation
  and shared labels without failing.** An island is something the next wave connects, and the
  game itself ships four distinct "Storm Phoenix Domain" trials. A guard that fires on the
  starting state is a guard people route around within one run.

## Consequences

- **`game/data` is a projection of the bible, not its source.** The direction is intentional
  and may be reversed later by a generator; the bible does not depend on the game existing.
- **The four authored tiers are a hard constraint, not a starting suggestion.** 3/6/10/15 law
  slots against 6 authored laws means a mortal world can hold half of them, which is a
  constraint on what can be cultivated there. The briefs state it so no agent invents a
  cosmology the engine contradicts.
- **Character readiness is measurable.** `lore readiness character` reports each hop of
  `race → culture → family → settlement → region → world` with the number of edges crossing
  it, so "the bible is thin somewhere" becomes a named missing link.
- **Diversity is structural.** Scaled type and tag entropy per domain, plus edge density,
  because 500 differently named identical sects is the monoculture this must not produce; a
  name-similarity test scores that as perfect diversity.
- **Every Python guard needs a red-path self-test** (INC-0016), since the GDScript suite
  cannot reach them.
