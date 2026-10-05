# 0188 a published verb is kept by a caller that is not a test and deleted when only tests remain, and a guard reads code lines only

- Status: Accepted
- Date: 2026-10-04
- Closes: BL-0785, BL-0786, BL-0787, BL-0788, DEF-0200 (stale, closed as verified-fixed)
- Amends: ADR 0095 (accessors are internal and now fewer), ADR 0096, ADR 0180

## Context

An audit returned the qi program COMPLETE and recorded four sub-threshold findings.
No feature gap. What it found instead was rot of a kind this project already prices:
a test that could not fail, published verbs only tests call, and prose describing a
deleted field.

One of the four was worth more than the brief credited. `test_qi_training.gd` asserted
`dantian.tier` on a field **ADR 0180 deleted**. A live read of a missing property raises
`Invalid access to property or key 'tier'` and **aborts the enclosing function**, so the
capacity assertion on the next line never ran, the aborted test reported no failure, and
the suite printed `6687 passed, 0 failed` while a test verified nothing. The runner says
so in one line (`1 script error(s) aborted a test mid-function; those tests reported no
failure, so the run above is incomplete`) and that line was in the audit's own output.
The ADR 0180 guard was green throughout: it greps `src/`, and this read was in `tests/`.

## Decision

**The rule.** A published member is KEPT when a caller exists that is not a test, when
it is the unique seam a committed guard needs, or when it computes something no other
published surface computes. Otherwise it is DELETED. Facade-ISP pressure applies only to
`api.gd`; internal classes cost nothing against the cap (ADR 0095), so internal rot is
lower stakes than facade rot and is not worth a cross-session rewrite.

**Applied per member, not in bulk.** `QiAccess.path_def` and `QiAccess.meridians` had
**zero callers in `src/`, `tests/` or `tools/`** and were pure pass-throughs: deleted.
`QiAccess.provider` had zero production callers and is discussed below: deleted.

**`QiAccess.provider()` is unfishable by deletion, not by assertion.** It ended with
`return QiProvider.new()` when no provider was registered — an UNATTACHED provider,
contributing nothing, handed back with full confidence. Its one caller asserted
`!= null`, which that fallback makes unconditionally true, so the trap's only test could
not fail. Making the absence loud was rejected as the same defect in a new coat: a loud
version is a guard with no caller. The trap is unfishable because the trapdoor is gone.
Its caller now asserts on the composer (`derived_all()` carries the key) rather than on
the accessor, which catches "registered but contributes nothing" — the trap's exact
shape — and cannot be satisfied by a fallback.

**A guard greps CODE LINES ONLY.** The first version of the new guard fired on its own
file's documentation, which is the general failure: prose must stay free to say what was
deleted and why (`dantian.gd:9-20` and ADR 0180's own `historic` map depend on it). The
defect is an EXECUTED read, so comment lines are stripped before matching.

**Not deleted, on purpose.** `QiCultivationApi.train_channel` has 19 test call sites across
six files in four path groups that other live sessions own. `QiAdvancement.preview`,
`chance` and `try_breakthrough` likewise have test-only callers. Each deletion is a
two-sided change, and landing half of it turns the tree red. They are recorded in
`docs/deferred.jsonl` with the exact repoint, not half-removed here.

## Consequence

The qi suite is `6714 passed, 0 failed (23 suites)` and, for the first time since ADR
0180, **complete**: the aborted-test line is gone. The deleted field can no longer be
read from a test, and `QiStats` — the one file in the module the ADR 0180 guard never
opened — is now scanned for a `DANTIAN_TIER` constant, which is the shape that would
survive every other assertion in that suite.
