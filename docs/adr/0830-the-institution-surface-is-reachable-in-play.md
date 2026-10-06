# The institution surface is reachable in play: membership, one loader, one route

Status: Accepted
Supersedes nothing. Extends ADR 0271 (the generic institution family), ADR 0278 (the
`core`-owned family), ADR 0084 (recognition, never power) and ADR 0083 (the three states).

## Context

ADR 0271 shipped a registry of kinds, ADR 0278 shipped a catalog of definitions, and the
later slices shipped a generic founding verb, a ledger with two writers and a projection.
`institution_screen.tscn` shipped with three Callables nothing bound and a `found` verb whose
written ledger it published and dropped.

The gap was named by the UI slice verbatim: **`core/` published no actor-scoped surface at
all.** `ui/` may legally read `core/`, so the screen could ask; there was nothing to ask.
`InstitutionLedger` publishes exactly two writers (`promote`, `move_standing`) and **neither
enrols anybody**. A hero could found a guild, be charged for it, and see the result discarded.

## Decision

**1. `core/institution_membership.gd` is the actor-scoped surface.** `summary`, `join`,
`leave`, `found`, `move_standing`, `reproject`, `claim_of`, `holds`, `roster_of`, `rosters`,
`source_tag`, `clear`. Twelve verbs, in `core/` because the machinery it drives is
`core`-owned and a module facade for a `core` type would be an indirection with no second
owner (ADR 0278's stated reason).

**2. The CLAIM lives on the actor; the ROSTER does not.** The split is by SUBJECT, which is
the rule `WorldPolityLedger` already states and enforces: *a fact whose subject includes an
actor id stays on that actor; a fact whose subject is the organization goes to the world.*

- The claim is `{version, claims}` under `module_data["institutions"]`, one row per
  organization. Plain `String` keys, primitives only, so it round-trips `Actor.to_dict`.
- The roster is a **process-wide table**, `institution: <organization_id>` →
  `{position_id: [actor_id]}`. `InstitutionFounding.write` puts a roster in the FOUNDER's
  ledger; measured, a member who joined rather than founded then saw no roster at all. This
  does not reproduce that.

**The roster does not survive a restart, and that is recorded rather than fixed.** No world
save slot can accept one: `WorldPolityLedger`'s row normalizer keeps `kind`, `standing`,
`standing_cap` and `sequence` and DROPS everything else, and its own boundary rule forbids an
actor id on a row. Adding a world container is DEF-0119's decision, not this ADR's. The
consequence is stated in the code and measured by the suite: after a restart the claims come
back and the roster does not, so an organization publishes `{}` and every office reads as
`holders not published` rather than as a vacancy nobody declared.

**3. Admission is never free.** A joiner is seated in an authored office — the first
UNBOUNDED one by id, or a named one — and immediately owes what the office and the house ask
(`duty_<office>`, `duty_<id>`, merged by the larger count per term). An office at its
authored `capacity` refuses the admit as `capacity_full`; `capacity == 0` is an unbounded room
and is never full. A joiner's standing starts at 0: `founder_standing` is the price of
FOUNDING, and recognition is earned.

**4. Leaving is always permitted and always costs.** `leave` refuses `no_actor` and
`not_a_member` and nothing else. It strips the recognition, drops the standing and removes
the roster row. A zero-argument `leave` walks out of EVERY organization the actor holds,
because the UI seam takes no id and "leave" has to mean something total rather than something
arbitrary.

**5. Recognition is re-projected on every change, strip first.** `InstitutionProjection.grant`
strips its own tag. The projection runs BEFORE the claim is stored, so a refused grant cannot
leave a member enrolled in a house that recognises them not at all.

**6. The N-fold sum is ACCEPTED, not bounded.** Each organization contributes its own bounded
percent under its own tag, so a member of N guilds at the ceiling carries N × 0.10. This is a
design consequence, not an oversight:

- ADR 0084's "no ladder of positions can add up" is about positions WITHIN one institution.
  The cap bounds each claim, not the sum.
- Bounding the SUM needs a second authority that knows every organization at once — a stat
  composer, which ADR 0084 refuses in a projector that is a pure function of four arguments.
- Bounding the INPUT would cap how many institutions a player may join, and the yin-yang rule
  binds the OUTPUT and never the INPUT: an input cap on membership taxes whoever has fewer
  houses.
- The tags are namespaced, so the composition is EXPLICIT and invertible term by term.
  `test_two_houses_each_contribute_their_own_bounded_percent` measures the sum and then
  removes one house to show the other survives.

**7. ONE loader.** `InstitutionBoot.install` and `.summary` delegate their scan to
`InstitutionDefCatalog`; the boot's own `CONTENT_ROOT` and its own `ContentScan` walk are
deleted. Two loaders naming one directory is how a mod's overlay roots reached one merge and
missed the other. The test that used to assert the two constants AGREED now asserts the boot
names **no** directory, which is stronger: a reintroduced second scan is a red test.

**8. The family is wired.** `InstitutionBoot.install()` runs from the attach pipeline beside
`EconomyBoot.install`; `ROUTE_INSTITUTION` binds the screen's three Callables; the
`institutions` overlay arm in `_wire_content_roots` reaches `set_overlay_roots` (DEF-0326).

## Consequences

- A player can found a trading guild, join a hunting guild and leave both, in play.
- The three shipped guild `.tres` files author an EMPTY `standing_percent_stats`, so their
  recognition is authored-but-unreachable until somebody writes ids into the content. The
  suite authors its own guild through the mod overlay seam rather than editing shipped
  content from a test.
- `move_standing` takes the registry as an argument. An earlier version reached for the
  shared one, and a caller driving its own registry had its recognition **silently stripped**
  on every standing move: `has_capability` answers `has: false` for an unknown kind as well as
  for a kind without offices, and the rebuild read the first as the second. `_project` now
  keeps the two answers apart — an unknown kind REFUSES, and a refusal is non-destructive.
- Nothing here ticks, and no institution owns a clock (DEF-0111).

## Note on the `institutions` family arm

`tools/institution_family.py` was **already** in `tools check`, in-process and hoisted above
`fmt --check` (INC-0017), and its nine red paths register on the same import. Only the
`institution-family` SUBCOMMAND was unregistered, because `tools/__main__.py` was held by
another session. `tools arch` is unaffected either way.