# 0194 The UI may read the combat engine through its facade, and the readout panel owns the wording

- Status: Accepted
- Date: 2026-10-04

## Context

`combat_engine` is complete and green (the spine's eleven stages, all three mechanisms,
wound persistence, status application). Its own read model exists:
`CombatOutcome.to_dict()` returns **primitives only** and was written for exactly this
consumer — its docblock says "so `ui/` can render it" (ADR 0038).

**Nothing consumed it.** Measured across `game/src/ui/` at the time of writing:

- `grep CombatEngineApi game/src/ui` — zero hits. The module's facade had no reader in
  the UI program at all.
- `loot_encounter.gd` calls `CombatApi.exchange` — the **encounter** module's share
  model, not the spine. Its readout is `LootBossPanel`: boss vitality, player health,
  defeats, statuses. No band, no crit, no shield, no reflect, no lifesteal.
- `technique_loadout.gd` calls `casting.activate(actor, id, target)` and keeps the
  descriptor only long enough to word a message ("Fired %s" / the refusal reason). The
  spine's eleven-stage answer is discarded at the call site.
- No screen renders `wounds_of`, a meridian's severity, a necrosis, a mind sea's
  turbulence/clarity, or any `effects[]` entry.

So every stage and every mechanism the program spent six waves building is invisible to
a player. The engine is a library with no readout.

The blocker was a boundary one. `rules.UI_MODULES` grants `ui/` facade-only access to a
named list of modules, and `combat_engine` was **not on it** — correctly, until now,
because no screen had needed it.

## Decision

**1. `combat_engine` joins `rules.UI_MODULES`, with NO module dependency** (`[]`).

This is the `status` grant (ADR 0106) repeated for the same reason: the read model
already exists, is already primitives-only, and a readout panel adds no edge it would
need. `combat_engine` declares `["contracts", "core"]` in `registry.json` and reads no
sibling module, so `ui/` gains nothing it could not already reach through `core`.

The grant is for the **read side only**. `ui/` may name `CombatEngineApi`; naming
`CombatSpine`, `CombatOutcome`, `MechanismSlot`, `BodyWounds` or any mechanism from
`ui/` remains a facade-rule violation, because only `api.gd` is a facade. The
enforcement is `enforce.py`'s existing `is_facade()` check and needs nothing new.

**2. The readout is a PANEL, and the panel owns every figure.**

`CombatReadoutPanel` (`src/ui/panels/`) takes a `CombatOutcome.to_dict()` payload
verbatim plus the effect kinds it is allowed to know, and turns it into sentences. Every
`%d`, every decimal, every verdict word and every effect id is the panel's. A screen
that formats a number itself gets two places to change the same figure, which is the
defect ADR 0038 was written against.

**3. The panel does NOT re-derive a rule, and it does not need a new facade method.**

`CombatEngineApi` is at its **12-method cap** (`MAX_FACADE_PUBLIC_METHODS`), so a new
facade verb was not available without splitting the interface. It was not needed:
`breakdown`, `band`, `summary` and `wounds_of` already answer everything a readout
renders. **No `api.gd` change ships with this decision.**

**4. `effects[]` kinds are named by the panel, as ids — not by the module's constants.**

A `ui/` file may not hold a typed reference to `BodyWounds.EFFECT_KIND`, because that
names a class outside `api.gd`. The panel therefore spells the three effect ids as its
own `StringName` constants and treats any other id as UNKNOWN and shows it raw. This is
the same shape `LootBossPanel._status_name` already uses for status ids (ADR 0106), and
it is deliberately lossy: the readout must never be able to change what the engine
computed.

**5. The screen resolves a hit through the module's own facade, with a null `rng`.**

`CombatReadoutScreen` calls `CombatEngineApi.breakdown(actor, target, technique, tuning,
null)`. A null generator means no randomness and every attack lands, which is what a
readout wants: a readout that reported "0 damage" for a miss would teach the reader that
a whiff and a gut-punch are the same event. The screen therefore shows bands as a
*separate* read (`CombatEngineApi.band`) and never fabricates one.

**6. A readout screen is a ROUTE like any other, or it is a dead surface.**

`ScreenRoutes` names every reachable screen and `test_screen_reachability.gd` asserts
every shipped screen scene has one. A new screen that ships without a route is exactly
the "green but unreachable" shape BL-0118 was filed about, so the route ships in the
same change, with its own `project.godot` input action (a route reachable only by a
button is a route a keyboard player cannot reach).

## Consequences

- **One ADR-level boundary change: `tools/arch/rules.py`.** The gate stays green and
  the grant is visible in the rule itself, which is where AGENTS.md says boundary truth
  lives. No `registry.json` edit: `combat_engine` is already registered.
- **What is now observable:** `base`, `proposed`, `amount`, `absorbed`, `overflow`,
  `health_delta`, `reflected`, `lifesteal`, the five booleans (`crit`, `parried`,
  `blocked`, `landed`, `clean`, `neutral`, `chain_dropped`), the band roll's `draw`, the
  wound/neckrosis/erosion rows carried in `effects[]`, and the actor's own offense and
  defense through `summary`.
- **What is still NOT observable, and no ADR claimed otherwise:** the boss fight. It
  resolves through `CombatApi.exchange`, the encounter module's share model, by ADR
  0123's designed split. Routing it through the spine is the realm-vs-vitality desync
  ADR 0133 records as OPEN and is an owner decision, not a UI one.
- **The screen's target is injected.** `ui/` may not name `ActorFactory` or spawn NPCs,
  so a drill opponent arrives as a `Callable` from the composition root — the same
  ADR 0143 seam the quest and soul screens use. Unwired, the screen says so on its own
  line rather than showing zeros.
- **No arithmetic changed.** Every number in `spine.gd`, `qi_damage.gd`,
  `body_damage.gd` and `mind_damage.gd` is untouched.