# 0273 A registrable System is a module that publishes a contract, and the framework ships the seams and no System

- Status: Accepted
- Date: 2026-10-06
- Extends: ADR 0184 (five seams), ADR 0265 (facade width uncapped, coupling is fan-in),
  ADR 0066 (one claim shape), ADR 0050 (a rate is not a magnitude)

## Context

The game wants the "System" — the diegetic overlay a solo-leveling protagonist sees: a
board of purchasable rows, a counter that climbs, tiers that unlock. Three properties made
it a framework problem rather than a feature.

**It is content, not code.** A System with a board, a price list and a currency is exactly
the shape a mod already is. Building it as engine code would mean every System is a
release, and the interesting ones are the ones nobody shipped.

**It must not become a second power curve.** The tree already has three per-realm
magnitude tables and one shared rate — `RealmRate.factor` (`core/realm_rate.gd:146`) — and
AGENTS.md is explicit that a new
power-shaped number needs its own ADR rather than a second curve. A System that says "+40%
to all damage" is a magnitude, and the ladder would learn a second one from a JSON file.

**The obvious name collides.** `system` is engine vocabulary (`System` is a Godot class),
and a module named after the platform's own noun reads as infrastructure no matter what it
does.

## Decision

**The module is `doctrine`** (道統 — the transmitted lineage), so the names read
`DoctrineApi`, `DoctrineRule`, `DoctrineBoardDef`, `register_doctrine`.

**A doctrine grants values and rates. Never a magnitude.** Flat, bounded, realm-keyed
values, and rates that reuse `RealmRate.factor` — never a new per-realm multiplier, never a
fourth magnitude table. The contract shape enforces it structurally: no method takes a realm
id and none returns a multiplier, so there is nowhere to put one.

**The framework ships the seams and no System.** Every candidate shape is supported and
none is implemented. A framework that ships an example has decided the shape; this one
publishes the contract and gets out of the way.

**The counter is one int; the tiers are the mechanic.** Persisted through
`Actor.set_module_data` (`core/actor.gd:336`) under `doctrine/<id>`, with tiers derived from
it and grants banded by tier. A million levels
must be representable, so there is never a million-entry table. The counter is flavour and
progression feel; the tiers are what a board row actually reads.

**`earn` and `redeem` ship together.** A register with no sink is an accumulating debt, so
the sink is part of the earn's definition rather than a later slice.

**No tick.** Nothing in `doctrine/` reads `Time.get_ticks*`, declares `_process`, or calls
`get_tree()` (DEF-0111). A System is precisely the thing that wants a clock; accrual takes an
explicit `periods` from a caller that owns time, which is what makes a System testable at
all.

**An unnamed System has no state key.** `data_key` (`contracts/doctrine_rule.gd:234`) is
empty rather than shared, because
two unnamed Systems writing one dictionary restores one System's board into another's.

## Consequences

- `game/src/contracts/doctrine_rule.gd` (ADR 0267) is the whole extension surface: a System
  is anything satisfying it, including a mod's class.
- A mod declares its numbers in **JSON in the mod**, because the Python gates cannot execute
  GDScript — a System whose truth lives in code is invisible to `tools/data.py`. That seam
  is the sixth one and amends ADR 0184 decision 6 in its own ADR.
- **Balance is explicitly not a blocker.** Imbalanced mods are normal in every game with a
  mod scene; the framework's job is to make an unbalanced System *legible*, not to prevent it.
- Placement follows coupling, not width. ADR 0265 removed the 12-verb cap precisely so a
  coherent feature is not contorted to fit an interface budget; `MAX_FACADE_FAN_IN`
  (`tools/arch/rules.py:241`) is the
  measure that predicts a god object.
- **A base-stat writer IS owed, and this was wrong when first written here.** The obvious
  answer looked settled: `ItemUse._apply_learned` reads base gains and calls `set_base`
  (`modules/items/item_use.gd:211`), so a learned item is the delivery and no verb is
  needed. That branch is unreachable. `ItemActivation.BY_CATEGORY` maps exactly one
  category to `LEARNED` — `TECHNIQUE` — and `_apply_learned` sends `TECHNIQUE` to
  `_study_technique` on its first line, which calls an injected `Callable` and writes no
  stat. A consumable refuses outright (`modules/items/item_use.gd:136-140`, ADR 0001: a
  base-attribute consumable "restores nothing and applies nothing"). So **no item channel
  grants a permanent base attribute at all**, and a board row saying "+1 physique" has
  nothing to call. A transient grant still goes through `Actor.add_status`
  (`core/actor.gd:265`), which is not a base attribute and never was.
  `game/tests/modules/doctrine/test_doctrine_base_stat_channel.gd` pins the reachability
  and is expected to fail once a channel exists (DEF-0321).