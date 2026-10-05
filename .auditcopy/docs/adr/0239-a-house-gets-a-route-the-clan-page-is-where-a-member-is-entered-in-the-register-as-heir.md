# 0239 A house gets a route: the clan page is where a member is entered in the register as heir

- Status: Accepted
- Date: 2026-10-05
- Resolves: DEF-0229, DEF-0286
- Depends on: ADR 0064 (clan is born to; position and standing never derive from each
  other), ADR 0083 (one claim shape), ADR 0113 (a write is a call of the owner of the
  moment), ADR 0137 (a module records its own facts), ADR 0143 (the composition root
  injects what `ui/` may not name)

## Context

`ClanHeir.register` is the **sole** writer of `household_heir_registered`, and it had
zero production callers — `grep ClanHeir game/src` returned its own `class_name` line.
Four authored quest steps demand that fact, which transitively blocked two fates
(`ancestral_debt_unpaid`, `household_registered_as_heir`) and one destiny
(`the_oath_bound`).

DEF-0229 named the reason and left the decision unmade: *"this build ships no clan screen
at all, so there is no surface on which that action could live, and inventing one is a
product decision rather than a wiring fix."*

Both halves were true, and only one of them was a reason not to ship:

- **`ClanApi.join` also had zero production callers**, so no player was ever a member of
  a house — `register` is defined only over members and its second refusal is
  `not_a_member`.
- **`ui/` shipped `sect_screen` and `nation_screen` and no clan screen.** The two other
  institution tiers had a page; the third had a module, a catalog, three authored
  `.tres`, a gate vocabulary and a fact.
- **`app/clan_registry.gd` already existed** — a seam in the exact `CombatMercy` shape,
  with `install` / `installed` / `available` / `commit`, the four module refusals aliased,
  and a docstring naming the line that would give it a caller. That line was never
  written. This is the same UNWIRED shape the gather, custody and shop audits found on
  the other side of the program.

## Decision

**Clan gets a player-facing surface, and it is a route like every other one.** The two
alternative readings were both rejected as dishonest rather than as expensive:

- **The fact is written from `ClanApi.join`.** Rejected: joining a house and being entered
  in its register *as its heir* are different acts. ADR 0064's whole point is that
  registration is political and standing is earned; a `join` that also made you heir would
  hand every member of every house a fact four quests are built around, and would make
  `household_heir_registered` mean "was admitted" — a lie in the ledger's only vocabulary.
- **A timer or an ambient pass drives it.** Rejected by ADR 0113 and by the same argument
  `app/institution_resolver.gd` makes: a module that both decides and executes is the
  political layer deciding its own outcomes. A registration the world performs on your
  behalf is not an appointment.

### What ships

- **`ScreenRoutes.ROUTES` gains a `clan` entry** beside `sect` and `nation`, with key `h`
  and a matching `nav_route_h` in `project.godot`. A route with no declared input action is
  a route a keyboard player cannot reach, so the key and the action land together.
- **`game/src/ui/screens/clan_screen.{gd,tscn}`** — the page. It is a **pure consumer** of
  the facade: `clan` is already a declared `rules.UI_MODULES` grant, so `ClanApi.summary`
  answers the whole screen in one call and is read by bare name.
- **The registration arrives as TWO Callables**, bound by the composition root's `ROUTE_CLAN`
  arm in `_bind_route_screen`: `ClanRegistry.commit` (the verb a press runs) and
  `ClanRegistry.available` (the gate that says whether it could mean anything). `ClanHeir`
  is a module interior and `ClanApi` is at `rules.MAX_FACADE_PUBLIC_METHODS`, so the page
  may not name it; this is ADR 0143's seam, the one `ROUTE_QUEST`, `ROUTE_FORAGE` and
  `ROUTE_SOUL_HEARTH` already use.

### The two rules that make this more than a missing call

1. **Both halves of the seam or neither.** A screen given only `commit` would have to
   re-derive the gate to decide whether to *offer* the press, and a re-derivation is a
   second authority on who may be heir — precisely what `no_heir_rank` refuses.
   `ClanScreen.register_seam_bound` is one conjunct over both, and an unbound page refuses
   `no_register_seam` rather than pretending a house spoke.
2. **The registration is a register, so it is non-trivial by construction.** It needs a
   member, and a member is somebody who has been admitted to a house — which a fresh
   player is not. The page therefore cannot offer the press to a bare actor at all, and
   `ClanApi.admission_unmet` stays the only door into membership. The fact is earned by
   reaching a house first; it is not a free counter.

## Consequences

- **Two fates and one destiny become earnable through content**, from one door.
- **`ClanApi.join` remains unwired**, and this ADR does not pretend otherwise: with no clan
  route before this one, and none of the clan verbs mounted, a player still cannot join a
  house through the shipped program. A *save* carrying a clan ledger, or a future screen
  that admits one, is what puts a member on the ladder. The registration is unreachable
  until then, and it refuses `not_a_member` by name rather than firing for nobody — which
  is the honest state and is **owed**: joining a house is the next clan slice, and this ADR
  deliberately does not decide how much surface it earns.
- **`ClanHeir` and `ClanFacts` are unchanged.** No new verb, no new writer, no second copy
  of the fact.
- **The page publishes ADR 0064's split as data**: `last_standing_before`,
  `last_standing_after` and `last_moved_standing`, so "registration moved the position and
  not the earned number" is a readable boolean rather than a claim in a docstring.