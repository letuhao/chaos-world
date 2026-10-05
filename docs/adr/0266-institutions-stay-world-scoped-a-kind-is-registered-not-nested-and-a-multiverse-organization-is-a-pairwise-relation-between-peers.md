# 0266 Institutions stay world-scoped, a kind is registered not nested, and a multiverse organization is a pairwise relation between peers

- Status: Proposed
- Date: 2026-10-05
- Depends on: ADR 0064 (a clan is a standing with obligations), ADR 0066 (one shared curve
  in core, never a per-module copy), ADR 0083 (three tiers, one vocabulary, NOT nested),
  ADR 0084 (recognition, access and transmission, never power), ADR 0085 (a conflict is a
  declaration, never a formula), ADR 0184 (mods register through a locked context)
- Amends: nothing. Supersedes nothing.
- Resolves: the multiverse half of BL-0169/BL-0172, and the "a fourth kind" question
  ADR 0083 left open

## Context

ADR 0083 built three tiers and said, in its own Consequences, that they are "**not**
nested in a containment tree" — a clan exists without a sect, and `nation → sect` exists
only "because a nation's offices are filled from sects, never because a nation contains
them". The MODULE GRAPH says otherwise, and measured today it reads `clan → bloodline/race/
social`, `sect → clan/social`, `nation → sect/social`: a literal nesting chain in which
`nation` is effectively the cap. Nothing contradicts ADR 0083's prose; the graph simply
never got the shape the prose describes.

Two more measured facts set the context for what is being built here:

- **`WorldPolityLedger` is built, mounted, tested and EMPTY.** `item_workbench_app.gd`
  installs it as the `world.polity` slot, `save/api.gd` stamps its version, and its
  containers `["institutions", "debts"]` are read by `save_migrate.gd` — yet nothing in
  `game/src` writes an institution or a debt row. It is the exact DEF-0151 "built and
  unwired" shape, and it is where an inter-institution fact has nowhere else to go.
- **A kind could not be added without editing a module.** `clan`, `sect` and `nation`
  each own a def type whose shape the others do not share, and nothing anywhere maps a
  `kind` to what that kind may DO. `_wire_content_roots` in `app/item_workbench_body.gd`
  hardcodes eight families and its `_:` branch records a family and `push_warning`s —
  `sect`/`nation`/`clan` are absent, so a mod shipping an institution is skipped, which is
  the silent skip ADR 0184's own acceptance criterion ("an unrecognized family fails
  loudly") forbids.

## Decision

**1. A `kind` is REGISTERED, in `core/institution_registry.gd`, and it carries capability
FLAGS rather than a place in a hierarchy.** One row per kind: `{def_type, def_script,
capabilities}`. The flags are `teaches`, `has_territory`, `has_offices`, `is_born_to` —
a CLOSED set checked at registration, so a typo fails where it was written rather than at
the gate that would silently never fire.

**`nation` is a PEER kind, not the cap, and the row shape is what makes that structural.**
A row has nowhere to put a parent, so "nests inside a nation" is not a thing the data can
express; `test_a_kind_row_carries_no_parent_no_tier_and_no_containment_of_any_kind` asserts
the row is exactly those three keys. The module graph still nests, and closing that is the
sect/nation migration's job; this ADR makes the target shape reachable rather than claiming
the graph already has it.

**A duplicate kind is REFUSED (`duplicate_kind`), never idempotent and never overwritten.**
Idempotence would have to guess that two rows agree, and a registry that guesses on a mod's
behalf is the silent id collision ADR 0184 §5 forbids.

**An unknown kind REFUSES BY NAME (`unknown_kind`) and a known kind lacking a flag is a
separate answer.** `has_capability` returns `{ok:false, reason:"unknown_kind"}` for a kind
that does not exist and `{ok:true, has:false}` for one that exists and cannot teach. A bare
`false` would collapse "no such kind" and "this kind does not teach", and a caller would
pick between two opposite actions by accident.

**`is_born_to` is the ONLY place the foundable answer is written.** A second `can_found`
flag is two fields that can disagree about one fact, which is ADR 0066's failure mode.

**2. The generic `found` is `core/institution_founding.gd`; the TIER supplies a PROFILE.**
`core/` may not name `SectDef`, so the verb reads a plain `Dictionary` of primitives the
tier assembles from its own defs — the injection seam `WorldFact` uses for its post-write
hook. `teaches`, `has_offices` and `is_born_to` come from the REGISTRY, never the profile,
so a profile cannot smuggle transmission onto a kind that has none.

**A kind without `teaches` gets NO `fit` KEY AT ALL.** Not `fit: 0`, not `fit: {}` — the
absence is the authored state. ADR 0084's fit is a GATE projecting zero stat modifiers, and
a gate reading a zero it was handed answers from a default rather than from what the kind
IS. `has_fit_axis` tells "no fit axis" apart from "nothing granted yet".

**Every refusal returns ABOVE the point at which the pool is touched or the ledger is
built**, so ADR 0044 is a property of the control flow rather than a discipline each facade
must remember — and the facades are written by different sessions.

**3. `core/institution_ledger.gd` holds only what is GENUINELY shared**, and its class note
names what is not, so the next migration does not finish the job wrongly:

- SHARED, and consolidated: the `_text` coercion (three copies measured — `ClanState`,
  `SectState` and `WorldPolityLedger`, the first documenting itself as the second), the
  paired `is_text` ask, the canonically `String`-sorted key walk, the `{"ok", "reason"}`
  refusal shape, and the `id -> positive count` obligation-line shape.
- NOT shared: **`SCHEMA_VERSION`** (four ledgers, four migration histories; one constant
  would make a bump in one silently re-stamp the others), **`MODULE_KEY`** (each names its
  own save slot, and `modules/save` may not name a core class's internals),
  **`SOURCE_PREFIX` and friends** (the SHAPE is shared via `source_tagged`, the NAMESPACE is
  not — a `sect:` modifier reaching a `clan` strip half is the bug the namespace exists to
  prevent), **the per-tier `normalize()` bodies** (clan discards the WHOLE record on a
  wrong-typed id, sect drops entries naming unshipped content, polity folds pair keys —
  three different corruption policies under one name), and **the gate files** (469 and 407
  lines; the verb sets genuinely differ, so the shared half is a RULE, not a function).

**`is_save_safe` is a callable, and it is RED on each hazard.** `Actor.to_dict` copies
`module_data` VERBATIM and converts only the OUTER key, so an inner `StringName` key, a
`Resource`, an `Actor` or a `Vector2` reaches the save untouched — and **no checker in this
repo can see it**. It walks to `SAVE_SAFE_MAX_DEPTH` because a recursive walk is a `while`
in disguise and `test_no_unbounded_wait.gd` cannot see it (the `ContentScan.MAX_DEPTH`
reasoning).

**4. Organizations stay WORLD-SCOPED. A multiverse organization is a PAIRWISE RELATION
between peers, never a tier above them.** A compact, an alliance or a syndicate is a row in
`WorldPolityLedger.debts` keyed by `pair_key` with a `term_id` — the shape already built and
already tested, and the reason an obligation between two institutions has a home at all
(DEF-0119). **NOTHING NESTS**, so there is no fourth kind to register for it and no tier
that contains another.

**5. The generic mod content family is named `institutions`**: one directory, each `.tres`
declares its `kind`, and the catalog dispatches on it. DECISION ONLY — a later slice wires
it into `families.json` and `_wire_content_roots`, which today skips `sect`/`nation`/`clan`.

## Consequences

- **`world_id` addressing is DEFERRED, not implemented.** Three rows in
  `docs/deferred.jsonl`: `world_id` on `SaveSlot` (ADR 0261 is **Proposed**, and
  `SaveSlot` has no `world_id` field today), `world_id` on `WorldPolityLedger.institutions`
  rows, and scoping the flat unqualified `NationTerritoryDef.location_ids`. Addressing a
  world before `world_id` exists would be a second guess at a field ADR 0261 still owns.
- **The sect migration is the next slice** and is blocked on `sect-duty-def0196` releasing
  `modules/sect`. `sect_founding.gd` is READ ONLY until then. The migration replaces
  `SectApi.found`'s body with a profile assembly plus this verb, asserts
  `SectState.FIT_CAP == 100` against the founding cap rather than restating it, and routes
  `ClanState._text` / `SectState._text` / `WorldPolityLedger._text` through
  `InstitutionLedger.text`.
- **A registry is process state and is NEVER serialized.** The rows hold `Script` values, so
  a save carries `kind` as a plain `String` and nothing else — the same discipline
  `WorldPolityLedger._institution_row` follows.
- **A kind is per-boot, so the registry is an INSTANCE with a `shared` accessor and a
  `clear()`, not a static table.** `tests/run_tests.gd` drives every suite in ONE process;
  a registration a suite forgot to clear would be handed to every suite after it. `found`
  takes the registry as a parameter, so a test's isolation is a constructor call.
- **A kind WITHOUT the `teaches` flag having no fit axis is a legitimate state, and the
  three-state vocabulary still holds**: `{}` does not exist, `{"ok": false, "reason": R}` is
  refused, and an absent fit axis is a THIRD thing — the shape, not a value.
- **A new institution kind is now a content-and-one-call change**, and `tools arch` cannot
  see a stat grant made through it, so `test_no_institution_foundation_verb_can_touch_a_stat`
  pins the published surface of all four foundation classes the way
  `test_sect_no_power.gd` pins `SectApi`.
