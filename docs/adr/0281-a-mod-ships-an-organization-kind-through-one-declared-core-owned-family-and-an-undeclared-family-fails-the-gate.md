# 0281 A mod ships an organization kind through one declared core-owned family, and an undeclared family fails the gate

- Status: Accepted
- Date: 2026-10-06
- Depends on: ADR 0066 (one shared shape, never a per-module copy), ADR 0083 (three tiers,
  one vocabulary), ADR 0184 (mods register through a locked context; an unrecognized family
  fails loudly), ADR 0271 (a kind is registered, not nested; the family is named `institutions`),
  ADR 0278 (one generic def in `core`, automatic discovery, no code)
- Amends: nothing. Supersedes: nothing. Resolves: DEF-0326, DEF-0334.

## Context

ADR 0271 named the family and deferred the wiring. ADR 0278 shipped the generic def and
recorded three things it did not do: the family was not in `families.json`, the boot had no
overlay seam, and the registry's capability order did not match its own docstring (DEF-0334).
Each was deferred because the file that would fix it was committed foundation or under
another session's claim. This is the wiring slice.

## Decision

**1. THE FAMILY ROW OMITS `module`, and the key is VERIFIED WHEN PRESENT.**
`"institutions": {"data_dir": "institutions", "def_class": "InstitutionDef"}`.

Measured, `module` is read in exactly ONE place — `tools/cultivation/audit.py:389`, only
for a row carrying `path`, where it resolves `game/src/modules/<module>/provider.gd`. It is
not an owner field; it names a module directory, and only for a cultivation path's provider.
`institutions` declares no `path`, so the key would never be read. `"module": "core"` would
lie twice: `core` is a **layer**, and `game/src/modules/core` does not exist.

So the key is omitted, and `tools/institution_family.py` refuses a `module` that names no
directory under `game/src/modules/` (`unknown_module`). That turns an unchecked comment into
a verified claim, which dissolves the question: with the key verified, `"module": "core"` is
now REFUSED, so the honest row and the lying row are distinguishable by the gate.

**This fired on the shipped tree.** `portraits` declared `"module": "unique_characters"` —
`PortraitDef` lives in `core/portrait_def.gd` and no `modules/unique_characters/` has ever
existed. Corrected to omit the key: a `core`-owned family, the second instance of this rule.

**2. THE OVERLAY SEAM IS `core/institution_def_catalog.gd`, and it LOADS WITHOUT REGISTERING.**
`set_overlay_roots(stack)` plus `ids` / `definition` / `owner_of` / `path_of` / `summary`,
routing the stack through `CatalogOverlay.merge` exactly as `RaceCatalog` does. `core/` is
where the precedents already are: `core/catalog_overlay.gd` is the merger and
`core/portrait_catalog.gd` is a content catalog; `core` is a layer, so this adds zero edges.

**It answers "which defs exist, from where, in what order" and nothing else.** The boot's four
named causes live in `app/`, which `core/` may not name, so restating them here would be a
second copy of one refusal vocabulary — the ADR 0066 shape inside the file that exists to
prevent it. `InstitutionBoot` should delegate its scan here; that edit is `app/`-only and is
recorded as a deferred entry, not hidden.

`set_overlay_roots` DROPS the cached tree, because a catalog serving a tree merged from the
PREVIOUS stack reports content the new stack does not contain.

**3. DEF-0334: THE DOCSTRING WAS AUTHORITATIVE; THE CODE WAS THE DEFECT.**
`register` and `capabilities_of` both sorted an `Array[StringName]`, and this engine does
not order interned ids by string value — measured, `[has_offices, has_territory]` read back
reversed. Three reasons the docstring wins: the same rule was already implemented correctly
twice in the same layer (`InstitutionDef.authored_capabilities`,
`InstitutionLedger.sorted_keys`); a documented order a reader relies on is a contract, while
interned order is an engine artefact that can change between versions; and the failure had
teeth — the boot's agreement check refused the SECOND `.tres` a modder dropped, which is the
exact failure this programme exists to prevent.

Fixed with ONE helper, `InstitutionRegistry._canonical`, that both ends route through — so a
row cannot be written under one rule and read under another. `kinds()` was **already**
correct (it routes through `_sorted_keys`), which DEF-0334's title overstates; pinned so the
distinction survives.

**4. THE LOUD-FAIL GATE, and the vocabulary split it found.**
`tools/institution_family.py`, run in-process from `tools check` above `fmt --check`.
It now REFUSES, with a named cause and a non-zero exit, four things that passed silently:

| reason | what passed silently before |
|---|---|
| `unknown_family` | a mod declaring content in a family no gate grades |
| `undeclared_root` | a manifest claiming a tree that is not its own |
| `unknown_module` | a family row naming a module that does not exist |
| `missing_data_dir` | a family no gate can walk |

**It found a pre-existing split on first run: the runtime seam vocabulary and
`families.json` are two different languages.** `_wire_content_roots` matches `quest`, `event`,
`world`, `npc`, `race`; `families.json` declares `quests`, `events`, `world_locations`,
`npcs`, `races`. Only `items`, `techniques` and `elements` agree — which is why the split
went unnoticed. The shipped fixture `w8_third_party_data` ships a `world` root and is a live
instance, not a hypothetical.

Reconciling it needs either an `app/` edit or a rename `tools/data.py` and
`tools/cultivation/audit.py` both key off. So ADR 0184's own alternative applies: **loudly
exempt**. `SEAM_ALIASES` maps each seam name to the family it stands for and **every
exemption spent is printed on every run**; an exemption applies only while the family it
names is itself declared, so it dies with a rename. A bare allowlist would have hidden the
correspondence that is the whole finding. Everything else still refuses.

**5. THE GATE'S RED PATHS LIVE IN THE GATE MODULE.** A Python guard is unreachable from the
GDScript suite, and the repo's own answer for a busy shared case file is a separate module
something must import. `tools/check.py` imports this one to run the gate, so the nine `@case`
blocks register on the same import that makes the gate reachable — a gate and its proof
cannot drift apart in the loader (INC-0016). Ran and asserted: all nine fire.

## Consequences

- **A mod ships a new organization kind with no base-game edit.** Proven, not asserted:
  a def declaring a kind nothing has seen is visible in the catalog, passes `check_content`,
  is refused by `check` until registered, and `InstitutionBoot.register_def` then registers
  it — `institution_def_catalog.gd::test_a_mod_ships_a_brand_new_kind_...`.
- **The base directory is named twice** — this catalog's `INSTITUTIONS_ROOT` and
  `InstitutionBoot.CONTENT_ROOT`. One-directional and asserted equal by a case, so it cannot
  rot silently; the boot's constant and walk both go when it delegates.
- **A `.tres` authored on a SUBCLASS of `InstitutionDef` is not merged.** `CatalogOverlay`
  selects by a text scan for `script_class="InstitutionDef"`. Acceptable — ADR 0278 ships one
  authored type, so a mod authors a `kind`, not a def class — and pinned by a case so it
  cannot decay into a silent skip. Such a def still registers when handed straight to the
  boot, so the boundary is "not discovered", never "invalid".
- **The gate is reachable from `tools check` but NOT as a subcommand.** `__main__.py` was
  dirty (another session's line) and a STEPS entry naming an unregistered command exits 2 —
  a permanently red gate (INC-0017). Wiring one `_load` line plus one `COMMANDS` entry makes
  it a first-class command; recorded, not hidden.
- **The registry is process state and is never serialized** (ADR 0271): a save carries `kind`
  as a plain `String`.
