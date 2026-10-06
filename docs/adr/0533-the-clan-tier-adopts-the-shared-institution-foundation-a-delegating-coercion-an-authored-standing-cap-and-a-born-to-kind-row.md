# 0533 The clan tier adopts the shared institution foundation: a delegating coercion, an authored standing cap, and a born-to kind row

- Status: Accepted
- Date: 2026-10-06
- Depends on: ADR 0271 (a kind is registered, not nested; the generic path takes a profile),
  ADR 0278 (a new organization kind is a `.tres` drop), ADR 0083 (three tiers, one vocabulary),
  ADR 0084 (recognition, access and transmission, never power), ADR 0064 (position and standing
  never derive from each other), ADR 0066 (one shared curve, never a per-module copy),
  ADR 0399 (the sect tier on the generic founding path)
- Extends: ADR 0399. Amends: nothing. Supersedes: nothing.
- Resolves: the clan half of ADR 0271's "the sect migration is the next slice"
- Note: first drafted as `0513`, whose number a concurrent session also took with a
  `ten-grades` stub (ADR 0337's runaway, since cleaned to one file). This is the same
  decision at a free number, which is what ADR 0271 did for `0266`. The number collisions
  this tree used to carry were repaired 2026-10-06 (DEF-0341): `new_adr` allocates from the
  whole directory, and it now also refuses a title already on disk, so a repeated title
  cannot take a second number.

## Context

ADR 0271 decision 3 measured three copies of one JSON-safe text coercion — `ClanState`,
`SectState` and `WorldPolityLedger` — and left them for the tier migrations. `SectState` went
first (ADR 0399). `ClanState` documented itself as *"`sect_state.gd`'s `_text`, carried over
unchanged"*, so it was a copy by its own admission. Separately `ClanDef` authored no
`standing_cap` at all while `SectDef`, `NationDef` and `InstitutionClaim` all did, and
`ClanFounding` did not exist, so nothing registered the `clan` kind at all.

## Decision

**1. `ClanState._text` and `_is_text` are DELEGATES; the ratchet is at ONE.** The coercion and
its type test are one decision read together, so both halves delegate: `InstitutionLedger.text`
and `InstitutionLedger.is_text`. `LEDGER_COERCION_BASELINE` in `test_sect_migration.gd` went
2 → 1 in the same change, which is what stops the number going stale. **One copy remains —
`core/world_polity_ledger.gd`**, which is outside this slice's claim, so the bound is one and
not zero: a ratchet only another session could clear is a gate nobody clears (INC-0017).

**2. `source_for` / `trait_for` / `is_own_source` also delegate; the namespace stays clan's.**
`InstitutionLedger.source_tagged` and `owns_source` take the prefix as an ARGUMENT, so the
construction is shared and the namespace is not — a `sect:` modifier reaching a `clan` strip
half is the bug the prefix exists to prevent.

**3. `ClanDef.standing_cap` is AUTHORED, and it does NOT clamp `standing`.** `ClanState.
standing_cap(clan_id)` is the one reader and it REPAIRS a zero or negative to at least 1,
because `InstitutionClaim.normalized()` answers `0.0` for an uncomputable cap and a
fully-respected member reading as a ratio of zero is the worst possible read.

**The clamp was the real decision, and it was weighed against the shipped content.** All three
houses publish a top band above 100 — ironpact 120, saltledger 150, quiethouse 160 — so a
clamp at the default would truncate earned standing. Measured in the tree rather than
assumed: `test_clan_grants_no_power.gd` raises standing by 10,000 and asserts
`ClanStats.STANDING` reads 10000, and `test_clan_standing_and_rank.gd` raises a member to 500
precisely to publish them as sitting BELOW what their standing reads as. **Truncating either
deletes ADR 0064's politics.** So the cap bounds the RATIO (`ClanState.claim`) and never the
ledger's number. `ClanState.standing_cap` falls back to `DEFAULT_STANDING_CAP` for an unshipped
house rather than to zero — absence is not a broken cap.

**4. `ClanState.claim` is a delegate to `InstitutionClaim.from_dict`, and the ledger keeps
clan's own keys.** `rank` is handed over as the position and `clan` names the institution —
translated at the READ. Renaming either in `normalize` would be a save-schema break for a
convenience no caller asked for.

**5. `clan` carries `is_born_to` and NOTHING ELSE.** `ClanFounding` is 60 lines rather than
sect's 323 because **a clan cannot be founded**: `InstitutionFounding.found` refuses on the
`is_born_to` flag above the `institution_id` check that would read a profile, so a
`profile()` here would be a dictionary no caller could legally hand the writer. `teaches` is
absent (a clan authors no doctrine and no fit floor — `recognised_at_least` reads the
recognition hinge, which is not transmission); `has_territory` is absent (`rival_clans` is
authored antagonism, not a claim over ground); `has_offices` is absent (`ranks` is a list of
ids, not an `InstitutionPositionDef`, and nothing is ever seated in one).

**6. Registration happens on `ATTACH`, not on founding — and this is where clan IMPROVES on
sect.** `sect` registers lazily from `SectFounding.registry()`, which only `SectApi.found`
reaches, so **a plain `join` there reads an unregistered kind**. That is inherited, not
designed: it works only because nothing in `sect` asks the registry outside founding yet. A
clan has no founding verb to hang it on at all, so `attach` is the seam — the one verb every
actor reaches. Lazy-first-use was kept (as an idempotent re-register-when-absent, because a
suite's `clear()` must not strand the row) but the TRIGGER moved.

## Consequences

- **The observable behaviour changes are THREE, and two are new reads rather than changed
  answers.**
  1. **The `clan` kind row now exists** in the shared registry after any `attach`, so
     `can_found()` answers `{ok: true, can_found: false, reason: ""}` where there was
     previously no row at all. No clan verb's behaviour changed.
  2. **An EMPTY id now names nothing.** `source_for(&"")` was `&"clan:"` and is now `&""`;
     same for `trait_for` and `rank_trait_for`. Unreachable in production — `ClanCatalog`
     only stores defs with a non-empty `id`, and every `ClanProjection` call site is guarded
     — and the new answer is the honest one: a source tag naming no clan is a bucket
     `ClanProjection.contribution` would sum modifiers into and nothing could own.
  3. **`ClanState.claim`, `ClanState.standing_cap` and `ClanApi.can_found` are new reads.**
     Nothing reads them in production yet; they are the seam a later stat-routing slice uses.
     `claim()` having no production caller is honest rather than hidden — routing clan's
     recognition onto `InstitutionClaim.standing_percent` is ADR 0084's work and not this
     slice's.
  Every one of the 13 existing clan suites' 1102 assertions passes untouched, and the
  `standing` clamp that would have been a fourth change is decision 3.
- **`ClanState` does not carry `obligation`, and that is a DECISION, not a gap.** Sect's
  ledger does. A clan's `patronage` and `duty` are authored **prose**
  (`"A reduced stipend is owed to a member the house can no longer call on."`) and
  `InstitutionLedger.positive_lines` keeps only strictly positive INTEGERS — every one of
  those lines would be dropped, so an `obligation` map would persist empty and then read as
  "this member owes nothing" on a house that publishes terms. Clan terms become enforceable
  when the social layer lands and they become period COUNTS; deferred, not faked.
- **`DEFAULT_STANDING_CAP` is a literal, and the FOURTH in the tree.** `InstitutionClaim.
  from_dict`, `InstitutionLedger.read` and `InstitutionFounding._standing_cap` each write the
  same `100` and `core/` publishes no named constant for it. `core/` is outside every module's
  claim, so naming the drift is the honest move rather than a fifth copy.
- **The three shipped `.tres` need no edit, and that is a consequence of decision 3** — a cap
  that clamped would require authoring one per house above its top band. `game/data/clans/`
  was outside this slice's claim and is untouched.
- **`standing_bands` is read by the DISPLAY path only** (`ClanSummary.band_rank`,
  `band_index`, `to_next_band`, `outranks_standing`) and never from a write site. Verified by
  source scan in `test_clan_migration.gd`: `with_rank`, the module's only rank writer, reads
  neither `rank_for_standing` nor `standing_bands` nor `ledger.get("standing"`.
- **DEF-0326 (`InstitutionBoot.install` has no production caller) is NOT closed by this
  slice.** Both peer tiers register themselves for the same reason; wiring the boot is
  `app/`'s and needs no change here.
- **`world_polity_ledger.gd` holds the last coercion copy** and is `core/`.
