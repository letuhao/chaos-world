# 0265 Facade width is uncapped and coupling is measured as fan-in, not as a verb count

- Status: Proposed
- Date: 2026-10-05
- Supersedes: the `MAX_FACADE_PUBLIC_METHODS` ISP cap stated in ADR 0093, ADR 0095 and ~18 others. Those ADRs are immutable and stand as the record of why each split happened at the time; nothing in them is edited.

## Context

`MAX_FACADE_PUBLIC_METHODS = 12` was an ISP proxy for coupling. Measured, it was a bad proxy in both directions.

- **It fired constantly and meant little.** 18 of 41 facades sat at exactly 12, so 44% of the codebase was contorting to satisfy it. A constraint nearly half the tree presses against is not a pressure on the architecture; it is the architecture.
- **It blocked coherent features.** A 100-realm expansion is a *content* change. A 12-verb interface rule answers it either by merging unrelated things or by inventing a split that means nothing.
- **It generated modules.** `domain`, `combat_engine`, `anchor`, `world_spawn` and `socket` exist because the cap forbade a thirteenth verb — each carrying a registry entry, a facade, contract tests and often an ADR. Some of those splits were right on their merits; all five were *required*.
- **It never fired on the real risk.** The god object in this codebase is a facade many units import, and that is invisible to a width count.
- **It had no selftest red path** (`tools/selftest_cases.py` had no ISP case), so it was never proven to fire under selftest — INC-0016.

The cap did produce four good local designs: `MindAccess` (ADR 0095), `MarketFavour` and `AuctionEvents.shared()` as named seams, and `summary()` read keys instead of a thirteenth accessor. **The pattern was worth keeping; the number was what failed.** Those four remain the house style and this ADR does not withdraw them.

## Decision

1. `MAX_FACADE_PUBLIC_METHODS` is deleted from `tools/arch/rules.py`, and the width check is deleted from `enforce.py::_structural_checks`. A module publishes the verbs it needs.
2. `rules.MAX_FACADE_FAN_IN = 8` replaces it (`tools/arch/rules.py:244`). `enforce.fan_in_warnings` counts, per facade, the number of distinct *units* that reach it by name, and warns above the threshold.
3. One unit counts once however many of its files touch the facade. A module's own files never count against its own facade — that is cohesion, not coupling.
4. Fan-in counts `modules/*` bare references even though the boundary check deliberately excludes them (`BARE_REF_UNITS`). That exclusion is right for reporting a violation and wrong for measuring coupling.
5. `game/tools/` (`harness`) is excluded: it drives screens headlessly and is built to touch many facades.
6. The existing patterns stand as house style on their own merits: a value a caller reads once is a `summary()` read key, not a verb; a class a caller needs is exposed by name, not re-exported through the facade.
7. `facade_constants.py` keeps its gate. Its *rationale* was the cap, but its finding does not depend on it: a facade constant named by nothing in `res://src` is dead surface whatever shape the module took. Four technique features shipped unreachable that way and were never over any limit.

## Consequences

- **One known finding, standing on purpose.** `ItemsApi` is reached by 11 units — `app`, `ui`, and nine modules. That is the god facade the width cap never saw, and it warns on every `tools arch` run. The threshold is not raised to hide it: moving a bound until a true finding disappears is weakening a rule to make it pass. A gate that is permanently red is a gate nobody reads, but this is a *warning* over a green gate, and the fact it reports is worth more than a clean line.
- Facade growth is now a review question rather than a gate, so a facade that accretes unrelated verbs can be caught late. Fan-in catches the case that matters; width did not catch either.
- The three technique suites that asserted `published <= MAX_FACADE_PUBLIC_METHODS` lose the constant. Their `_published_methods()` helper is KEPT and re-pointed at the rule that was always the point — every published verb has a production caller, which is the guard DEF-0303 acted on when it deleted `technique_state` for having zero.
- `docs/modding-guide.md` and `AGENTS.md` are updated in the same change, per the code-wins doc rule.
