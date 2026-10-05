# 0275 A mod declares its stats and resources in one block and an undeclared id is refused by name

- Status: Accepted
- Date: 2026-10-06
- Amends ADR 0184 (decision 6: the locked registration surface had exactly five seams)
- Extends ADR 0267 (`DoctrineRule.resource_ids`, which reads pool ids nothing validates)

## Context

There is no list of valid resource ids anywhere in the tree. `CultivationPathDef.resource_ids`
declares them and `ensure_resources` mints a `ResourcePool` for **any** id it is handed, so a
System declaring `raeg` gets a pool called `raeg` and reads it as `0.0` forever. A System
whose entire economy is one pool pays nothing and grants nothing, with nothing in the log.

`DoctrineRule.UNDECLARED_POOL` does not close this. It catches a System spending a pool it did
not itself **declare**, which is a different question from whether the id **exists**. A System
that declares `raeg` passes it.

`tools/data.py` learns GDScript ids by regex (`_valid_stats`, `_resolve_rate_stats`), so a mod
declaring its numbers in GDScript is invisible to every Python gate. The numbers must be JSON.

## Decision

1. **One block, two arrays.** `stats.json`, a sibling of `mod.json`:
   `{stats: [{id, op, resource, zero_baseline}], resources: [{id}]}`. Stats and resources
   travel together because a stat row's `resource` is meaningless without the pool list beside it.
2. **The split is not taste.** A `resource` field is a REFERENCE. With one array, naming `raeg`
   in a `resource` field would *declare* it and the typo would pass. With two, the closed set is
   `resources[]` ∪ `ActorPools.CORE_POOL_STATS`.
3. **JSON, read by both.** `mods/declaration_block.gd` and `tools/data.py` read the same file.
   One file, two readers, one answer — the reason the numbers are not in GDScript.
4. **The sixth seam.** `RegistrationContext.declare_stats`. A seam rather than a manifest field
   because the ids must be refusable at the point they enter the game, and the locked surface is
   the only point a mod cannot route around.
5. **Closed key sets.** An unknown key is refused. `resorce` is a declaration that reads as
   working and governs nothing — the same defect as a typo'd pool id, one level down.
6. **UNKNOWN is not EMPTY.** If the stat vocabulary cannot be read, the seam refuses everything.
   A reader answering "nothing is legal" for a present file is a gate reporting ok on a tree it
   never checked (`tools/data.py:_read_fate_tags` draws the same line).
7. **Every vocabulary is READ, never restated.** `Stat`'s constants via
   `get_script_constant_map()` (array constants expanded — `RATE_STATS` and `MIND_CONTROL_RATES`
   are where the ids a gate most needs live), `Stat.Op` for ops, `ActorPools.CORE_POOL_STATS` for
   core pools, `declaration_block.gd` for the key sets and reason names. ADR 0066 forbids a
   second literal.
8. **A refused block registers nothing.** No partial write: a locked surface has no rollback verb.
   The split is deliberate — `DeclarationBlock.parse` still RETURNS its good rows so an author
   fixing one typo can see which of their other four rows were fine, and `declare_stats` is what
   withholds them. A gate that hides them makes the author re-derive it.
9. **Ownership is the runtime's, and it is read off the DECLARATIONS.** The first mod in load
   order owns a pool; a second mod's declaration of the same id is refused naming both
   (`DUPLICATE_RESOURCE`, deliberately not in `DeclarationBlock.REASONS` — a single-mod pure
   function cannot see a cross-mod collision). Ownership comes from `resources[]`, NOT from the
   stat rows referencing them: those are different lists, and a pool no stat row reads would
   otherwise be owned by nobody — the one case the collision pass exists to catch.
10. **A refusal is a CHANNEL, not a log line.** `ModRuntime.finalize` returns
    `declaration_refusals` because GDScript cannot intercept `push_error`, so a log line alone is
    not assertable. What the composition root does with it is app-owned and is not decided here.
11. **The vocabularies are read, never mirrored, and reading them has a shape.** `Stat`'s
    constants are unreachable by reflection as written: `Stat.get_script_constant_map()` and
    `preload(...).get_script_constant_map()` are both rejected by the ANALYZER, so the reader
    goes through an instance (`Stat.new().get_script()`), memoised. `Stat.Op`, the core pool table,
    the key sets and the reason names are read the same way on the Python side.

## Consequences

- `declared_resource_ids()` is the JSON spelling of `CultivationPathDef.resource_ids`: hand it to
  a path def and `ensure_resources` mints the pool, so the closure is over the game's own pool
  creation rather than a table this change invented.
- The `stats.json` file is read by the mod's entry point through the seam, not by
  `ModLoader.discover`. ADR 0184 decision 7 locks the loader, and a bad declaration must not
  abort discovery the way a bad manifest does — it is reported and the boot continues.
- `data audit` walks mods the way `ModLoader.discover` finds them: WALK FOR `mod.json`. **No
  `families.json` entry**, deliberately. The family registry keys a fixed `data_dir` under a
  declared root and parses `.tres` against a `def_class`; a declaration block is JSON, beside a
  `mod.json`, in a directory a third-party mod does not have. A family entry would claim a
  directory that does not exist.
- `user://mods` is still unaudited from a checkout. The audit's warning now says precisely that,
  rather than implying coverage.
- `_valid_stats()` accepts `slow`, a shape name that appears in `stat.gd`'s prose. The GDScript
  reader is therefore one id STRICTER. Recorded, not silently reconciled: `_valid_stats` is the
  fate gate's reader and narrowing it is a separate change with its own blast radius.

## Consequences

- `declared_resource_ids()` is the JSON spelling of `CultivationPathDef.resource_ids`: hand it to
  a path def and `ensure_resources` mints the pool, so the closure is over the game's own pool
  creation rather than a table this change invented.
- The `stats.json` file is read by `ModRuntime.finalize`, not by `ModLoader.discover`. ADR 0184
  decision 7 locks the loader and decision 8 makes a bad manifest abort the boot; a bad
  DECLARATION is a different failure — the mod's identity, version and dependency graph are sound
  and its other content still loads — so discovery must not fail on it. A read step the
  composition root had to call instead would have no caller, and a validated list nothing consults
  on the boot path is the "narrowed, not closed" outcome this ADR refuses.
- `data audit` walks mods the way `ModLoader.discover` finds them: WALK FOR `mod.json`. **No
  `families.json` entry**, deliberately. The family registry keys a fixed `data_dir` under a
  declared root and parses `.tres` against a `def_class`; a declaration block is JSON, beside a
  `mod.json`, in a directory a third-party mod does not have. A family entry would claim a
  directory that does not exist.
- `user://mods` is still unaudited from a checkout. The audit's warning now says precisely that,
  rather than implying coverage.
- `_valid_stats()` accepts `slow`, a shape name that appears in `stat.gd`'s prose. The GDScript
  reader is therefore one id STRICTER. Recorded, not silently reconciled: `_valid_stats` is the
  fate gate's reader and narrowing it is a separate change with its own blast radius.
- `Actor extends RefCounted`, so a test holding one frees nothing — `free()` is a runtime error on
  it and `queue_free()` is banned. Noted because the instinct on reading a test is to free the
  fixture.

## Acceptance criteria

- A mod's JSON block reaches `ModRuntime.finalize`, and a bad stat id and a bad resource id each
  produce a refusal naming the mod and the bad id.
- A pool named only in a `stats[]` row's `resource` field is refused; the same id in
  `resources[]` is accepted.
- `data audit` is red on an unknown stat id, an unknown resource id, an unknown key, an unknown op
  and a non-boolean `zero_baseline` in any in-repo mod's block — and on the three
  `resources[]`-row defects the GDScript parser also refuses, because a gate that says OK where a
  boot says no is worse than no gate.
- A declared pool is spendable through `CultivationPathDef.ensure_resources`; a pool nobody
  declared resolves to no pool at all.