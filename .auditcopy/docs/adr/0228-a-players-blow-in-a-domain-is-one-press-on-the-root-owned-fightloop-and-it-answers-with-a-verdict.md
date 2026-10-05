# 0228 A player's blow in a domain is one press on the root-owned FightLoop, and it answers with a verdict

- Status: Accepted
- Date: 2026-10-05
- Resolves: BL-0210 (the player's attack), the COMBAT half of BL-0634
- Depends on: ADR 0197 (the fight is an exchange on the composition root's clock), ADR 0126
  (headless exchange, the spatial layer does not block it), ADR 0133 (spine is SSOT for actors)
- Amends: ADR 0197's "no 2D action layer is built"; ADR 0126's "`PlayerAdapter.attack` is
  where an injected attack callable lands"

## Context

BL-0210's text is stale in its first clause and true in its second. `PlayerAdapter.attack()`
is no longer a comment: it has a body, it gates on `State.COMBAT`, resolves a `Node2D` to an
`Actor` through `_defender_of`, and lands the blow through `CombatBoot.strike`
(`player_adapter.gd:184-203`), which reaches `CombatSpine.resolve_hit`
(`combat_boot.gd:511,624`). The stale half is the title's claim that "nothing the player does
in a domain resolves".

The true half is *who calls it*. Grep for `.attack(` across `game/` returns **tests only**:
`tests/modules/combat/test_combat_duel_hit.gd:202` and
`tests/modules/combat/test_combat_spare_wiring.gd`. `PlayerAdapter` is mounted only by
`DomainWorld.place_player` (`domain_world.gd:170-183`) and `WorldStage`, and
`DomainWorld.place_inhabitants` hands each creature a bare `Node2D` with `set_meta(&"actor")`
(`domain_world.gd:139-166`) — which is exactly what `_defender_of` reads, so the wiring is
one `set_state(COMBAT)` and an `add_interactable` away from working, and **nobody performs
either**. No screen publishes `STATE.COMBAT`, and `add_interactable` has one production
caller, `WorldStage._register_nodes` (`world_stage.gd:547`), which registers **resource
nodes**, not creatures.

So there are two fight models and neither reaches the player through the other:

- **The boss run** — `LootEncounterScreen.act_strike` → `CombatApi.exchange`
  (`loot_encounter.gd:239`) → `LootApi.strike`. This one IS reachable (a button) and IS the
  authored domain encounter, but it resolves a **share** of a frozen dictionary, not a body,
  and it never sees the inhabitants the domain actually placed.
- **The actor fight** — `FightLoop` → `CombatSpine`, both sides real `Actor`s. Reachable
  through `ItemWorkbenchFight.fight_verbs()` (`item_workbench_fight.gd:96-105`) bound by the
  `ROUTE_FIGHT` arm (`item_workbench_app.gd:899-901`) — but that page mints its own generic
  `fight_opponent` (`fight_loop.gd:206-222`), so it is a training dummy with no domain
  behind it and no `LootState` run to pay out.

**A domain inhabitant is currently unkillable.** `DomainApi` exposes `enter`, `leave`,
`visit_room`, `arm/attempt/claim_fixture` — no kill verb. `LootState.strike` spends only the
**active boss dictionary's** vitality (`loot_state.gd:296-336`), and nothing routes a spine
outcome on a placed inhabitant into `LootState._defeat`. So a player who walks the map, finds
a hostile creature and kills it has changed nothing: no ledger row, no run progress, no
reward, no map alteration.

## Decision

**The player's attack in a domain is ONE press on the root-owned `FightLoop`, and the
composition root is the only thing that may open it. The chain is
`intent → action → cost → effect → outcome`, and `outcome` is the only stage that may write
a run.**

| Stage | What it is, concretely | Owner |
|---|---|---|
| **intent** | a named hostile inhabitant within reach, published by the read model as an `engageable` row; nothing else is attackable | `domain` (read model) / `ui` (render) |
| **action** | one press → `FightLoop.exchange(seed)`, refused by name when not allowed | `app` root (`ItemWorkbenchFight`) |
| **cost** | the rate gate: `BASE_BLOW_INTERVAL / Stat.ATTACK_SPEED`, accumulated by the caller's `age(delta)` and published as `blows_remaining`. Never a second clock | `FightLoop` (already `fight_loop.gd:526-532`) |
| **effect** | two spine hits — hero then opponent — plus `StatusLoop` ageing the opponent's wound and sea ledgers | `CombatBoot.resolve_hit` (already) |
| **outcome** | `_decide` writes the duel ledger and the fate, closes the fight, returns `hero_won` / `hero_lost` | `FightLoop._decide` (already `fight_loop.gd:683-708`) |

**Three decisions ride that table.**

1. **`PlayerAdapter.attack()` is RETIRED as the domain path, not repaired.** It stays a
   world-interaction verb and stays tested, but the domain fight goes through the root's
   `FightLoop` for the reason ADR 0197 already gave: `app/` is a `PRIVATE_UNIT`, so `ui/`
   may neither hold a `FightLoop` nor mint an opponent, and the bridge-of-callables bundle
   (`item_workbench_fight.gd:96-105`) is the only legal door. Repairing the adapter instead
   means teaching a `CharacterBody2D` to own a contest, a cooldown and a verdict — a second
   clock on a tree where ADR 0106 gives the game exactly one.
2. **The cost is a gate on the press, never a background timer.** A blow is *available*
   when `attack_speed` says so, and the seconds remaining are published. This is ADR 0167 /
   0173's rule for every other player action, and it is what lets a headless probe drive a
   whole fight with a verb list.
3. **The rate gate is on the PRESS; the opponent always answers.** `FightLoop.exchange`
   already answers in the same call (`fight_loop.gd:344-352`), and that is deliberate:
   splitting it makes the opponent's blow a second press the player could decline — a dodge
   mechanic no ADR describes and the owner's anchor excludes.

**The stages that currently break are `intent` first and `outcome` second.** Nothing
publishes an attackable target, and nothing routes a decided outcome back into the run.
`action`, `cost` and the core of `effect` are built and reachable today behind the fight
page; the chain breaks at both ends, not in the middle.

## Consequences

- **A domain fight becomes a real fight against a real body.** The inhabitant already
  carries what a fight needs: `ActorFactory.spawn_inhabitant` gives it the same provider
  spine as the player (`actor_factory.gd:457-467`), and `spawn` applies `RealmScaling`
  (`domain_spawner.gd:124`), so both sides sit on `core/realm_power_table.tres`'s axis.
- **`CombatBoot.install` must reach the creature.** `start_fight` shows the order — mint,
  enrol, `CombatBoot.install`, then size (`fight_loop.gd:206-222`). An inhabitant minted by
  `spawn_inhabitant` has no mechanism bound, and `MechanismSlot.of` **asserts** at S4
  (`spine.gd:139`, `mechanism_slot.gd:75`), so an un-installed creature is a crash, not a
  chip. Installing it is a line in the spawn seam, not a new module.
- **BL-0634's combat half closes here; the reward half does not.** A boss that dies on this
  path mints nothing, because `LootState._defeat` is reached only by spending
  `active["vitality"]` (`loot_state.gd:325-336`). That is the reward agent's seam and this
  ADR does not touch it — but it must not be routed through `LootApi.strike` from here,
  because rule E1 keys the payload on the encounter id and a placed inhabitant has none.
  **What I need from that agent:** a named verb on `LootApi` that takes an encounter id the
  caller resolved, or a stated rule that a placed inhabitant pays nothing. Not an inversion
  of `strike`.
- **The mercy key survives.** `PlayerAdapter.interact` → `CombatMercy.commit` → `CombatApi.spare`
  is the third outcome besides kill and loss, and it must be reachable in the same exchange.
  A fight with two endings is not a fight.
- **`FightLoop._size_opponent` is for MINTED opponents only** and says so
  (`fight_loop.gd:546-554`): an authored creature's magnitude belongs to content. A creature
  with no authored pool (the default-minted `50.0` at `physique == 0`) dies in one press, so
  sizing a placed inhabitant is a **content** obligation, not a loop decision.

## Rejected

- **Wire `PlayerAdapter.attack()` to the loop's opponent instead.** Cheapest to write, and it
  keeps the spatial layer honest. Rejected: the adapter has no clock, no opponent field and
  no verdict, so closing it means teaching a `CharacterBody2D` to be a fight — the second
  clock ADR 0106 forbids, and the second verdict ADR 0076's single ledger forbids.
- **Give `domain` a `kill_inhabitant(actor, inhabitant_id)` verb.** Tempting — it is where the
  roster lives. Rejected: `domain` declares no `combat` edge, and a kill verb there makes
  traversal state depend on damage arithmetic it cannot see. The kill is recorded by
  `combat`; what `domain` learns is a fact, exactly as ADR 0137's split already works for
  quests.
- **Let a placed kill count as an encounter defeat and mint through `LootApi.strike`.**
  Rejected: rule E1's id is `domain/boss@tier#run` (`loot_state.gd:162-163`), and an
  encounter with no boss binding has no table. This is precisely the kind of fix that
  silently breaks rule E3's next-boss spawn.

## What would change my mind

- An owner ruling that the domain run is the *only* fight surface and the `fight` page's
  minted opponent is canonical. Then the placed inhabitant becomes loot content and the loop
  is already right — I would retire the encounter screen instead, not the adapter.
- A headless probe that can drive `PlayerAdapter.attack` through a real `SceneTree` frame.
  That is the only thing that would change the first rejection.
