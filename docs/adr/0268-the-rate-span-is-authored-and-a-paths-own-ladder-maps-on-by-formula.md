# 0268 The rate's SPAN is authored and the step is normalised over the ladder, and a path's own ladder maps on by formula

- Status: accepted
- Amends: ADR 0066 and ADR 0116 (both state `RATE_STEP` is the authored balance number and that the span is a consequence of it; the span is now the authored number and the step is derived from it)

## Context

`core/realm_rate.gd` compounded a bare `RATE_STEP := 1.02` over the ladder's **ordinal**, so the total was `RATE_STEP^(size - 1)` — a function of how many realms the ladder happened to have.

| realms | old span | derived step | authored work-step ceiling |
|---|---|---|---|
| 30 (shipped) | 1.775844 | 1.020000 | 1.035714 |
| 36 | 1.999882 | 1.016546 | 1.035714 |
| 37 | 2.039880 | 1.016082 | 1.035714 |
| 100 | — | 1.005819 | 1.035714 |

At 36 realms the margin to the under-2x ceiling a rate is held to was 5e-5. At 37 the assertion went red. **Extending the ladder was therefore a balance decision, arrived at by arithmetic nobody chose** — and ADR 0265 had just removed the cap that forbade a 100-realm expansion, so the expansion this blocked was the one the repo was about to authorise.

Two further defects, both found while fixing this:

- `core/realm_defaults.gd:4` claimed "Append-only; adding a realm is data" while `_all()` returned thirty literal `_make(...)` calls. A mod could not extend it.
- A partial ladder is already **legal** (`modules/mods/module_registry.gd:110-118` validates the seeds it finds and does not require one per ladder realm), yet nothing mapped a path's own step onto a standard realm. `CultivationPathDef.stage_name` indexed `stage_names` by the **standard** ordinal, so a 12-stage path against a 30-realm ladder silently fell through to `realm.display_name`.

## Decision

**1. The SPAN is the authored number; the step is normalised over the ladder.**
`rate_span()` is `RATE_STEP^(AUTHORED_LADDER_SIZE - 1)` = 1.775844, and
`rate_step()` is `rate_span()^(1/(size - 1))`. The top realm is worth `rate_span()` at
**every** ladder length. `RATE_STEP` stays a `const` of exactly `1.02` and keeps its
meaning: the step at the ladder length it was authored for. That matters —
`modules/economy/api.gd:253` publishes it in a facade summary and
`tests/core/test_realm_lifespan_table.gd:333` pins it at **zero tolerance**, so a
literal `RATE_STEP := TARGET_SPAN^(1/(size-1))` would have broken production output and a
foreign guard to buy a name.

**2. The two bounds now AGREE, which is what makes the ceiling safe to extend past.**
`ln(rate_step()) = ln(rate_span()) / (size - 1)` has a positive numerator, so the step is
**strictly decreasing** in ladder length. A longer ladder takes a smaller step and the
margin against the authored work-step ceiling (1.035714, qi `2900/2800`) **grows**:
0.01571 at 30 realms, 0.01917 at 36, 0.01963 at 37, 0.02990 at 100. Only a *shorter*
ladder can walk up onto it, and a 2-realm ladder is a content bug the bound test should
catch rather than absorb. `tests/core/test_realm_rate.gd` asserts this at all four
lengths rather than trusting the derivation.

**3. The ladder is extended through a seam, not by moving the rows.**
`RealmDefaults.register_realms` / `unregister_realms`. The authored `_make(...)` rows
deliberately **stay in `realm_defaults.gd`'s source text**: `tools/realm_power.py`,
`tools/cultivation/seed.py`, `tools/cultivation/seed_systems.py` and
`tools/item_migrate.py` all regex them, so relocating them to a `.tres` — the textbook
"make it data" move — would leave four tools looking at an empty ladder. The call drops
the built ladder so the rebuild re-reads `RealmDef.power` by **id** for appended realms,
exactly as for authored ones.

**4. A path's own ladder maps on by formula** (`core/realm_mapper.gd`, `RealmMapper`).
`standard_ordinal(path_ordinal, path_size)` is proportional with both ends anchored and
is the **identity at equal lengths**, so all five shipped paths are bit-for-bit
unchanged. A shorter path skips standard realms; a longer one holds a realm across
several steps. It lives in `core/` because `CultivationPathContract.validate_provider_source`
and `test_no_path_provider_computes_a_rate_from_the_ladder_itself` both refuse a provider
that reads `RealmDefaults.ladder()` — ADR 0116's pattern exactly. `SuccubusPath` is the
in-tree caller: it owns no realm seeds, so it is the shipped system shaped like a mod's,
and it now *states* its correspondence instead of assuming `30 == 30`.

## Consequences

- **A mapped realm inherits the standard realm's authored `RealmDef.power`,** so
  extending a path adds no fourth magnitude table and needs no ADR for a new
  power-shaped number. `RealmScaling` is untouched.
- **No `while`, no clock, no `get_tree()`.** `rate_step()` caches on ladder **size**, so a
  `register_realms` call is picked up without a reload; `unregister_realms` walks a
  `range` built from a size **snapshot** taken before the body erases from the array it
  walks (INC-0002).
- **Two guards stopped asserting ladder length.** `test_realm_rate.gd` asserted a literal
  `30` twice — the realm count walked and the seed-budget count — so the first realm
  anyone added turned both into no-ops. Both derive from `RealmDefaults.ladder()` now.
- **A new realm on the STANDARD ladder needs a `progress_required` seed on all three
  seed paths.** `_smallest_work_step()` asserts `budgets.size() == ladder.size()` and
  `budget > 0`, so extending the standard ladder without pricing it goes red. That is the
  intended behaviour, not a limitation of the seam: a mod's own realms map onto the
  standard ones and never join the standard ladder.
- **Four foreign assertions are now stale-on-extension, not stale-today.** They assert
  `pow(RealmRate.RATE_STEP, realms.size() - 1)`, true while the ladder is 30 and false
  the day it is not: `tests/modules/body_cultivation/test_realm_profile.gd:41`,
  `tests/modules/qi_cultivation/test_qi_realm_profile.gd:43`,
  `tests/modules/mind_cultivation/test_mind_power_curve.gd:111`, and
  `tests/core/test_realm_lifespan_table.gd:170` (which also hard-codes `29.0`). They
  belong to other slices and were left untouched; re-point them at `RealmRate.rate_span()`
  in the same change that first extends the ladder.
- **`CultivationPathDef.stage_name` was deliberately NOT changed.** Projecting its index
  through `RealmMapper` breaks `test_cultivation_path_def.gd:12-18`, which pins a raw
  two-name index overlay. A path with a short vocabulary keeps the existing safe fallback
  to `realm.display_name`; `SuccubusPath.realm_id_for_stage` is the new, non-breaking way
  to ask.