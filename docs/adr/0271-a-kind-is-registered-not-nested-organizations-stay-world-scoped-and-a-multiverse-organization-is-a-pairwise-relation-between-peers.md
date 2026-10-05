# 0271 A kind is registered not nested, organizations stay world-scoped, and a multiverse organization is a pairwise relation between peers

- Status: Proposed
- Date: 2026-10-05
- Depends on: ADR 0064 (a clan is a standing with obligations), ADR 0066 (one shared curve
  in core, never a per-module copy), ADR 0083 (three tiers, one vocabulary, NOT nested),
  ADR 0084 (recognition, access and transmission, never power), ADR 0085 (a conflict is a
  declaration, never a formula), ADR 0184 (mods register through a locked context)
- Amends: nothing. Supersedes nothing.
- Resolves: the multiverse half of BL-0169/BL-0172, and the "a fourth kind" question
  ADR 0083 left open
- Note: first drafted as 0266, whose number a concurrent session also took. The tombstone at
  `0266-the-rate-span-...` is theirs; this is the same decision at a free number.

## Context

ADR 0083 says in its own Consequences that the three tiers are "**not** nested in a
containment tree" — a clan exists without a sect, and `nation → sect` exists only "because a
nation's offices are filled from sects, never because a nation contains them". The MODULE
GRAPH says otherwise, and measured today it reads `clan → bloodline/race/social`,
`sect → clan/social`, `nation → sect/social`: a literal nesting chain in which `nation` is
effectively the cap. Nothing contradicts ADR 0083's prose; the graph never got the shape
the prose describes.

Two measured facts set the context:

- **`WorldPolityLedger` is built, mounted, tested and EMPTY.** `item_workbench_app.gd`
  installs it as the `world.polity` slot, `save/api.gd` stamps its version, its containers
  `["institutions", "debts"]` are read by `save_migrate.gd` — yet nothing in `game/src`
  writes an institution or a debt row. It is the DEF-0151 "built and unwired" shape, and
  the only place an inter-institution fact has to go (DEF-0119).
- **A kind could not be added without editing a module.** Nothing anywhere maps a `kind`
  to what that kind may DO. `_wire_content_roots` in `app/item_workbench_body.gd`
  hardcodes eight families and its `_:` branch only records and `push_warning`s — so
  `sect`/`nation`/`clan` are absent and a mod shipping an institution is skipped, which is
  the silent skip ADR 0184's own acceptance criterion forbids.

## Decision

**1. A `kind` is REGISTERED, in `core/institution_registry.gd`, with capability FLAGS rather
than a place in a hierarchy.** One row per kind: `{def_type, def_script, capabilities}`.
The flags are `teaches`, `has_territory`, `has_offices`, `is_born_to` — a CLOSED set checked
at registration, so a typo fails where it was written rather than at the gate that would
silently never fire. A def type is registered as a **String label plus an
already-loaded `Script` the caller resolved in its own scope**, never as a path: `core/` may
not depend on `modules/` and the resolver reads a path literal as a real edge.

**`nation` is a PEER kind, not the cap, and the row shape makes that structural.** A row has
nowhere to put a parent, so "nests inside a nation" is not expressible in the data;
`test_a_kind_row_carries_no_parent_no_tier_and_no_containment_of_any_kind` asserts the row is
exactly those three keys. The module graph still nests; closing that is the migration's job.
This ADR makes the target shape reachable rather than claiming the graph already has it.

- **A duplicate kind is REFUSED (`duplicate_kind`)**, never idempotent and never overwritten.
  Idempotence would have to guess that two rows agree, and a registry that guesses on a mod's
  behalf is the silent id collision ADR 0184 §5 forbids.
- **An unknown kind REFUSES BY NAME (`unknown_kind`), and a known kind lacking a flag is a
  separate answer.** `has_capability` returns `{ok:false, reason:"unknown_kind"}` for a kind
  that does not exist and `{ok:true, has:false}` for one that cannot teach. A bare `false`
  collapses two situations that call for opposite actions.
- **`is_born_to` is the ONLY place the foundable answer is written.** A second `can_found`
  flag is two fields that can disagree about one fact — ADR 0066's failure mode.

**2. The generic `found` is `core/institution_founding.gd`; the TIER supplies a PROFILE.** A
plain `Dictionary` of primitives the tier assembles from its own defs, because `core/` may
not name a `SectDef` — the injection seam `WorldFact` uses for its post-write hook.
`teaches`, `has_offices` and `is_born_to` come from the REGISTRY, never the profile, so a
profile cannot smuggle transmission onto a kind that has none. The registry is a **per-boot
instance** with a `clear()`, because `tests/run_tests.gd` drives every suite in ONE process
and a registration a suite forgot is handed to every suite after it.

- **A kind without `teaches` gets NO `fit` KEY AT ALL** — not `fit: 0`, not `fit: {}`. Fit is
  a GATE projecting zero modifiers (ADR 0084), and a gate reading a zero it was handed
  answers from a default rather than from what the kind IS.
- **Every refusal returns ABOVE the point at which the pool is touched or the ledger is
  built**, so ADR 0044 is a property of the control flow rather than a discipline each
  facade must remember — and those facades are written by different sessions.
- **Every writer RETURNS its replacement ledger under `"ledger"` and mutates nothing.** A
  writer that mutates in place and one that discards its copy are indistinguishable from
  outside, and the first version of `promote` was the second: it type-checked and changed
  nothing.
- **The founding cost is read, never authored here, and a shortfall names it.** The treasury
  is a ledger of obligation lines on ids, never a pile of items, and nothing in these files
  reads `Time.get_ticks*`, declares `_process` or calls `get_tree()` (DEF-0111).

**3. `core/institution_ledger.gd` holds only what is GENUINELY shared**, and its class note
names what is not, so the next migration does not finish the job wrongly.

- SHARED and consolidated: the `_text` coercion (three copies measured — `ClanState`,
  `SectState` and `WorldPolityLedger`, the first documenting itself as the second), the
  paired `is_text` ask, the canonically `String`-sorted key walk, the `{ok, reason}` refusal
  shape, and the `id → positive count` obligation-line shape.
- NOT shared: **`SCHEMA_VERSION`** (four ledgers, four migration histories), **`MODULE_KEY`**
  (each names its own save slot, and `modules/save` may not name a core class's internals),
  **`SOURCE_PREFIX` and its verbs** (the SHAPE is shared via `source_tagged`; the NAMESPACE is
  not, because a `sect:` modifier reaching a `clan` strip half is the bug the namespace
  exists to prevent), **the per-tier `normalize()` bodies** (clan discards the WHOLE record
  on a wrong-typed id, sect drops entries naming unshipped content, polity folds pair keys —
  three corruption policies under one name), and **the gate files** (469 and 407 lines
  measured; the verb sets genuinely differ, so the shared half is a RULE, not a function).

**`is_save_safe` is a callable, and it is RED on each hazard.** `Actor.to_dict` copies
`module_data` VERBATIM and converts only the OUTER key, so an inner `StringName` key, a
`Resource`, an `Actor` or a `Vector2` reaches the save untouched — and **no checker in this
repo can see it**. It walks to `SAVE_SAFE_MAX_DEPTH` because a recursive walk is a `while` in
disguise and `test_no_unbounded_wait.gd` cannot see it (the `ContentScan.MAX_DEPTH` reasoning).

**4. Organizations stay WORLD-SCOPED. A multiverse organization is a PAIRWISE RELATION between
peers, never a tier above them.** A compact, an alliance or a syndicate is a row in
`WorldPolityLedger.debts` keyed by `pair_key` with a `term_id` — the shape already built and
tested, and the reason an obligation between two institutions has a home at all (DEF-0119).
**NOTHING NESTS**, so there is no fourth kind to register for it and no tier containing
another.

**5. The generic mod content family is named `institutions`**: one directory, each `.tres`
declares its `kind`, the catalog dispatches on it. DECISION ONLY — a later slice wires it into
`families.json` and `_wire_content_roots`.

## Consequences

- **`world_id` addressing is DEFERRED.** DEF-0323 (`world_id` on `SaveSlot` — ADR 0261 is
  Proposed and the field does not exist), DEF-0324 (`world_id` on
  `WorldPolityLedger.institutions` rows), DEF-0325 (the flat unqualified
  `NationTerritoryDef.location_ids`). Addressing a world before the field exists would be a
  second guess at a field ADR 0261 still owns.
- **The `institutions` family is unwired**: DEF-0326. The registry rows shipped here are what
  a catalog dispatches on, so only the wiring is missing.
- **The sect migration is the next slice**, blocked on `sect-duty-def0196` releasing
  `modules/sect`. `sect_founding.gd` is READ ONLY until then.
- **A registry is process state and is NEVER serialized.** The rows hold `Script` values, so a
  save carries `kind` as a plain `String` and nothing else.
- **An absent fit axis is a THIRD thing** beside `{}` (does not exist) and
  `{"ok": false, "reason": R}` (refused): it is the SHAPE, not a value.
- **A new institution kind is a content-and-one-call change**, and `tools arch` cannot see a
  stat grant made through one, so `test_no_institution_foundation_verb_can_touch_a_stat` pins
  the published surface of all four foundation classes the way `test_sect_no_power.gd` pins
  `SectApi`.
