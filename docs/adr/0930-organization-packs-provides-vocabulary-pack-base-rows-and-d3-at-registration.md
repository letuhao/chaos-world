# 0930 organization packs: provides vocabulary, pack base rows, and D3 at registration

- Status: Accepted
- Date: 2026-10-08

## Context

`core/institution_*` is the organization standard; sect/clan/nation become
built-in packs. A pack needs a shape the existing loader already reads
(D6: a pack IS a mod), a place in the family merge, and D3 enforcement
(a pack failing its claimed contract suite is refused at load).

## Decision

- Layout: `game/data/packs/<pack_id>/organizations/*.tres` plus a `mod.json`
  with `provides: ["organization_pack"]`, one `modules[]` entry carrying
  `provides: ["organization_pack"]` and `seed_dir` naming the pack's
  `organizations/` dir, and `content_roots: [{family: "institutions",
  dir: "./organizations"}]`. `ModManifest.parse`, `ModLoader._stamp_context`
  and `RegistrationContext.register_module` play this through untouched:
  `provides` is open vocabulary and `seed_dir` is the existing pipeline key,
  so no manifest, loader or seam edit exists.
- `ModuleRegistry.register` grades `provides: ["organization_pack"]` exactly
  like `provides: ["cultivation_path"]`: every `.tres` must load as an
  `InstitutionDef` whose `check_content` passes, else
  `invalid_organization_pack`. Kinds handed capability instances are graded
  through `InstitutionContract.register` on a throwaway dispatcher, so the
  refusal (`contract_failed` with findings) travels by name, never re-derived.
- `InstitutionDefCatalog` merges shipped pack rows as BASE rows (owner
  `base`), in sorted pack order, between the base root and the mod overlays.
  A pack is shipped content, so it layers where shipped content layers; an
  undeclared id collision refuses the whole family.
- Cost/counter/scarcity (D8): a failing pack costs its load (refused at
  registration; a refused merge registers nothing); capabilities are the
  counter; declared-override roots are the scarce good.
- The tier moves (`sect`, `nation`, `clans`, `institutions` into pack dirs)
  are NOT this change: path-pinned suites and untouchable catalog base roots
  forbid them here. They land with their owning slices and tests.

## Consequences

- A modder ships a whole new organization kind with `.tres` files plus
  optional capability scripts and zero base-game edits.
- `families.json` is unchanged: the family root did not move, and the
  `institutions` row stays core-owned without a module.
- Follow-up: feeding pack capability instances in production needs the
  context seam to carry them (`RegistrationContext.register_module` has no
  such parameter); until then D3 at pack registration is caller-fed and
  test-proven.
