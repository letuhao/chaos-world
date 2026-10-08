# 0936 The world polity store is injected into the relation graph and both writer facades

- Status: Proposed
- Date: 2026-10-09
- Answers: DEF-0179
- Builds on: ADR 0931 (the world polity ledger and its stance verbs)

## Context

ADR 0931 gave `InstitutionRelation` the stance verbs over `WorldPolityLedger`, and the
graph a `world_polity` argument, but nothing wrote the ledger in production and nothing
passed it to the graph: a declared schism or war stayed on the declaring actor's ledger
and was invisible to `graph()`, `stance()` and `hostile_to()` (DEF-0179). ADR 0931
recorded wiring the store as needing a `save` dependency on `relations` — which would
make `relations` read the persistence root it is supposed to merely consume.

## Decision

**The store is INJECTED, the same seam `holdings` already uses.** `RelationsApi` gains
`set_store`, `SectApi`/`NationApi` gain `set_world_store`, and
`InstitutionBoot.install()` reads `SaveApi.store_for(WorldPolityLedger.WORLD_KEY)` and
installs THAT ONE instance into all three, so the save and the graph cannot drift into
two worlds. The graph reads the store for a bare call; an explicitly handed ledger
always wins; a store-backed build is never memoized, so the memo covers the pure
authored catalog alone (`_store == null and world_polity.is_empty()`).

`declare_schism` and `declare_war` run the world leg after every actor-side check and
before any actor mutation. `already_declared` is a world NO-OP — a declaration is a
fact, not a counter — and any other refusal refuses the whole verb and writes nothing
anywhere. The actor line stays the member's fact (cost, bill, standoff); the pair flag
is the world's fact, written where its subject lives (ADR 0931's boundary rule).

`SaveApi.install_store(key, null)` now CLEARS the entry instead of refusing
`not_a_store`, which is the uninstall path three teardowns already used; a non-null
object without `read_ledger` is still refused by name.

## Consequences

- DEF-0179 closed: a declared schism/war reaches the bare graph with `polity`
  provenance. Guards: `test_relations_world_store.gd`, `test_sect_world_stance.gd`,
  `test_nation_world_stance.gd`, the wiring case in `test_institution_wiring.gd`, and
  `test_save_store_clear.gd` for the uninstall path.
- `sect`/`nation` facades grow one public seam each, so the pinned surface lists move
  12 → 13 (sect) and 11 → 12 (nation); the seams grant no power and stay off the
  forbidden lists.
- A resolved war keeps its world flag: the actor side never closes a `war` stance row
  either (`nation_resolve.gd` has no stance closure), and the world ledger's own
  `reconcile` is not called by any production path. Closing is future work, recorded
  as DEF-0386.
- The seams are process state, so a suite that mounts the app leaves them installed;
  suites whose contracts depend on their absence reset them in `setup()`.
